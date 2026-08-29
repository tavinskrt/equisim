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

  /// Teto do anel de histórico.
  ///
  /// Duzentos eventos cobrem com folga uma sessão de demonstração e mantêm o
  /// *replay* numa mensagem que o navegador transmite sem esforço.
  static const int bufferLimit = 200;

  final List<AuditEvent> _buffer = [];
  final Set<String> _seen = <String>{};

  AuditChannel? _channel;
  StreamSubscription<String>? _subscription;
  AuditRole? _role;

  /// Eventos, do mais antigo ao mais recente.
  List<AuditEvent> get history => List.unmodifiable(_buffer);

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
    _channel?.post(jsonEncode({'kind': 'event', 'event': event.toJson()}));
  }

  void _record(AuditEvent event) {
    if (!_seen.add(event.transactionId)) return;
    _buffer.add(event);
    while (_buffer.length > bufferLimit) {
      _seen.remove(_buffer.removeAt(0).transactionId);
    }
    notifyListeners();
  }

  void _clearLocal() {
    if (_buffer.isEmpty) return;
    _buffer.clear();
    _seen.clear();
    notifyListeners();
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
        }));

      case 'replay':
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
