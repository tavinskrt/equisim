import 'dart:async';
import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/foundation.dart';

import 'audit_channel.dart';

/// Chave que liga a auditoria.
///
/// O padrão acompanha o modo de depuração — é onde o painel é usado —, mas fica
/// sobrescrevível por `--dart-define=EQUISIM_AUDIT=true` para o caso de a
/// apresentação ser feita a partir de um build de release, que é o cenário em
/// que descobrir o painel desligado seria mais caro.
const bool auditEnabled =
    bool.fromEnvironment('EQUISIM_AUDIT', defaultValue: kDebugMode);

/// Papel desta janela no barramento de auditoria.
enum AuditRole {
  /// A janela onde o usuário opera: produz os eventos.
  emitter,

  /// A janela paralela de inspeção: apenas consome.
  inspector,
}

/// Barramento que liga o motor de cálculo ao painel de auditoria.
///
/// Une três origens numa única fonte para a interface:
///
/// 1. o coletor do núcleo ([AuditRecorder]), quando esta janela é a que calcula;
/// 2. o interceptador de rede, pelo mesmo coletor;
/// 3. o canal entre janelas, quando o painel está em outra aba.
///
/// O histórico é mantido em memória dos dois lados. O motivo é prático: a
/// `BroadcastChannel` não guarda nada, e o painel costuma ser aberto **depois**
/// de o usuário já ter feito algumas consultas. Sem o histórico, a segunda aba
/// abriria vazia e a apresentação começaria com uma tela em branco — por isso o
/// inspetor pede um *replay* ao entrar, e a janela emissora responde com o que
/// tiver no anel.
class AuditBus extends ChangeNotifier {
  AuditBus._();

  static final AuditBus instance = AuditBus._();

  /// Nome do canal. Fixo: as duas janelas precisam concordar sem combinar.
  static const String channelName = 'equisim-audit-v1';

  /// Teto do anel de **cálculos**.
  ///
  /// **Dois anéis, e não um** (item D4). Com um só, de 200, cada avaliação
  /// dispara várias idas à rede, e numa carteira de quinze ativos o ruído de
  /// rede empurrava para fora justamente as avaliações que se abre o painel
  /// para depurar. Cada anel descarta o seu mais antigo, e o descarte é
  /// contado — ver [discardedCalculations].
  static const int calculationLimit = 200;

  /// Teto do anel de eventos de **rede**.
  static const int networkLimit = 300;

  /// O evento é de cálculo do núcleo, e não de ida à rede?
  ///
  /// **Pela origem, e não pela presença de passos** (item D4). Uma avaliação
  /// recusada antes do primeiro passo — preço de mercado ausente, falha de
  /// preparo — não tem cálculo decomposto, e a regra antiga a mostrava como ida
  /// à rede.
  static bool isCalculation(AuditEvent event) =>
      event.endpoint.startsWith('/core/');

  final List<AuditEvent> _buffer = [];
  final Set<String> _seen = <String>{};

  int _discardedCalculations = 0;
  int _discardedNetwork = 0;
  int _originDiscardedCalculations = 0;
  int _originDiscardedNetwork = 0;
  int _untransmitted = 0;

  AuditChannel? _channel;
  StreamSubscription<String>? _subscription;
  AuditRole? _role;

  /// Eventos, do mais antigo ao mais recente.
  List<AuditEvent> get history => List.unmodifiable(_buffer);

  /// Cálculos que saíram do histórico por falta de espaço, **nesta janela ou
  /// na que calcula** — o maior dos dois, porque o painel em outra aba só vê
  /// o que a janela emissora ainda tinha. Um arquivo exportado com descarte não
  /// está completo, e diz isso.
  int get discardedCalculations =>
      _discardedCalculations > _originDiscardedCalculations
          ? _discardedCalculations
          : _originDiscardedCalculations;

  /// Eventos de rede descartados, pela mesma regra.
  int get discardedNetwork => _discardedNetwork > _originDiscardedNetwork
      ? _discardedNetwork
      : _originDiscardedNetwork;

  /// Eventos que não puderam ser transmitidos à outra janela. Com a
  /// serialização segura do núcleo, deve ser sempre zero.
  int get untransmitted => _untransmitted;

  /// Papel assumido pelo barramento, ou `null` enquanto ele não foi ligado.
  AuditRole? get role => _role;

  /// `true` quando existe canal real entre janelas (alvo web).
  bool get crossWindow => _channel?.supportsCrossWindow ?? false;

  /// Liga o barramento. Chamar duas vezes é inofensivo.
  void start(AuditRole role) {
    if (_role != null) return;
    _role = role;

    final channel = AuditChannel(channelName);
    _channel = channel;
    _subscription = channel.incoming.listen(_onRemoteMessage);

    if (role == AuditRole.emitter) {
      // A partir daqui todo cálculo do núcleo passa a emitir rastro. Antes
      // disto, `AuditRecorder.begin` devolvia `null` e nada era montado.
      AuditRecorder.attach(_publishLocal);
    } else {
      // O painel entrou depois: pede o que já aconteceu.
      channel.post(jsonEncode({'kind': 'replay-request'}));
    }
  }

  /// Reenvia o pedido de histórico — usado pelo botão de reconexão do painel.
  void requestReplay() =>
      _channel?.post(jsonEncode({'kind': 'replay-request'}));

  /// Apaga o histórico em **todas** as janelas.
  ///
  /// Limpar só a lista local deixaria o anel da janela emissora intacto, e o
  /// próximo *replay* traria de volta exatamente o que o usuário mandou apagar.
  void clear() {
    _clearLocal();
    _channel?.post(jsonEncode({'kind': 'clear'}));
  }

  @override
  void dispose() {
    if (_role == AuditRole.emitter) AuditRecorder.detach();
    _subscription?.cancel();
    _channel?.close();
    _role = null;
    super.dispose();
  }

  // ------------------------------------------------------------- Interno --

  void _publishLocal(AuditEvent event) {
    _record(event);
    // **O coletor roda dentro da transação que fecha o cálculo**: uma exceção
    // aqui subiria para a avaliação. A serialização do núcleo já é segura
    // (`AuditJson`), e esta guarda é a segunda linha — o evento fica no
    // histórico local mesmo que não atravesse para a outra janela.
    try {
      _channel?.post(jsonEncode({
        'kind': 'event',
        'event': event.toJson(),
        'descartados': _discardedPayload,
      }));
    } catch (error) {
      _untransmitted++;
      debugPrint('⚠️  Evento de auditoria não transmitido: $error');
    }
  }

  void _record(AuditEvent event) {
    if (!_seen.add(event.transactionId)) return;
    _buffer.add(event);
    final calculo = isCalculation(event);
    final teto = calculo ? calculationLimit : networkLimit;
    var mesmos = _buffer.where((e) => isCalculation(e) == calculo).length;
    while (mesmos > teto) {
      final i = _buffer.indexWhere((e) => isCalculation(e) == calculo);
      _seen.remove(_buffer.removeAt(i).transactionId);
      mesmos--;
      if (calculo) {
        _discardedCalculations++;
      } else {
        _discardedNetwork++;
      }
    }
    notifyListeners();
  }

  void _clearLocal() {
    _discardedCalculations = 0;
    _discardedNetwork = 0;
    _originDiscardedCalculations = 0;
    _originDiscardedNetwork = 0;
    if (_buffer.isEmpty) return;
    _buffer.clear();
    _seen.clear();
    notifyListeners();
  }

  Map<String, int> get _discardedPayload => {
        'calculos': _discardedCalculations,
        'rede': _discardedNetwork,
      };

  void _readOriginDiscarded(Object? raw) {
    if (raw is! Map) return;
    final c = raw['calculos'], r = raw['rede'];
    if (c is int && c > _originDiscardedCalculations) {
      _originDiscardedCalculations = c;
    }
    if (r is int && r > _originDiscardedNetwork) _originDiscardedNetwork = r;
  }

  void _onRemoteMessage(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      debugPrint('⚠️  Mensagem de auditoria ilegível: $error');
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    switch (decoded['kind']) {
      case 'event':
        _readOriginDiscarded(decoded['descartados']);
        final payload = decoded['event'];
        if (payload is Map<String, dynamic>) {
          _record(AuditEvent.fromJson(payload));
        }

      case 'replay-request':
        // Só quem calcula tem histórico de verdade a oferecer.
        if (_role != AuditRole.emitter || _buffer.isEmpty) return;
        _channel?.post(jsonEncode({
          'kind': 'replay',
          'events': [for (final e in _buffer) e.toJson()],
          'descartados': _discardedPayload,
        }));

      case 'replay':
        _readOriginDiscarded(decoded['descartados']);
        final events = decoded['events'];
        if (events is! List) return;
        for (final item in events) {
          if (item is Map<String, dynamic>) _record(AuditEvent.fromJson(item));
        }

      case 'clear':
        _clearLocal();
    }
  }
}
