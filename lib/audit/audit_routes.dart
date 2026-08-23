import 'logs_window_stub.dart'
    if (dart.library.js_interop) 'logs_window_web.dart' as impl;

/// Endereçamento do painel de auditoria.
abstract final class AuditRoutes {
  /// Rota dedicada do painel.
  ///
  /// No alvo web a aplicação usa a estratégia de *hash* — o padrão do Flutter —
  /// então o endereço real é `http://host:porta/#/logs`. A vantagem é não
  /// depender de reescrita no servidor: o `flutter run -d chrome` serve a
  /// aplicação na raiz e o fragmento nunca chega ao servidor, de modo que
  /// recarregar a janela do painel funciona sem configuração nenhuma.
  static const String logs = '/logs';

  /// `true` quando a aplicação foi aberta diretamente no painel.
  ///
  /// A janela paralela é uma segunda instância completa da aplicação. Detectar
  /// isso no arranque permite subir só o painel — sem Firebase, sem sessão, sem
  /// a casca de navegação —, o que a deixa pronta em uma fração do tempo e a
  /// impede de disparar cálculos próprios que poluiriam a própria auditoria.
  static bool isLogsWindow(String routeName) {
    final normalized = routeName.split('?').first;
    return normalized == logs || normalized == '$logs/';
  }

  /// Abre o painel numa nova guia. Devolve `false` fora do navegador, onde não
  /// existe segunda janela e o painel é empilhado na própria aplicação.
  static bool openInNewWindow() => impl.openLogsWindow(logs);
}
