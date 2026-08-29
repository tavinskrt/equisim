import 'audit_channel_stub.dart'
    if (dart.library.js_interop) 'audit_channel_web.dart' as impl;

/// Canal de auditoria entre a janela que calcula e a janela que audita.
///
/// **Por que não WebSocket ou SSE.** O requisito pede transmissão em tempo real
/// a partir do "backend", mas neste sistema não existe backend próprio: o motor
/// financeiro é um pacote Dart puro que roda dentro da própria aplicação, e a
/// única API remota é a brapi.dev, de terceiros. Levantar um servidor só para
/// reemitir eventos criaria uma peça de infraestrutura que não participa do
/// cálculo — e, pior, o que ela retransmitisse seria uma cópia do que aconteceu
/// no navegador, não o cálculo em si.
///
/// O equivalente fiel, no alvo web, é a `BroadcastChannel` do próprio
/// navegador: canal nomeado, mesma origem, entrega por *push* entre abas, com
/// a mesma semântica de assinatura de um SSE — e o evento sai de dentro do
/// cálculo, sem intermediário que possa divergir dele.
///
/// A abstração existe porque o aplicativo também compila para Android, iOS,
/// Windows e Linux, onde `BroadcastChannel` não existe. Lá a implementação
/// degrada para entrega local, e o painel continua funcionando na mesma aba.
abstract class AuditChannel {
  /// Constrói o canal apropriado à plataforma.
  factory AuditChannel(String name) = impl.PlatformAuditChannel;

  /// `true` quando há transporte real entre janelas.
  bool get supportsCrossWindow;

  /// Publica uma mensagem já serializada em JSON.
  void post(String json);

  /// Mensagens vindas de **outras** janelas. A `BroadcastChannel` não entrega
  /// ao próprio remetente — a entrega local é responsabilidade do barramento.
  Stream<String> get incoming;

  /// Encerra o canal e libera o transporte.
  ///
  /// Depois disto [incoming] não emite mais e [post] não tem efeito. Chamar
  /// duas vezes é inofensivo.
  void close();
}
