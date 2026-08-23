import 'package:web/web.dart' as web;

/// Abre o painel numa guia nova do navegador.
///
/// O endereço é montado a partir da própria localização em vez de ser fixo:
/// a porta do `flutter run -d chrome` muda a cada execução, e um endereço
/// escrito no código quebraria na segunda vez que alguém rodasse o projeto.
///
/// O fragmento (`#/logs`) é o que carrega a rota — a estratégia de URL padrão
/// do Flutter web é a de *hash*, e é ela que faz a guia nova abrir direto no
/// painel sem exigir reescrita de rotas no servidor de desenvolvimento.
bool openLogsWindow(String route) {
  final location = web.window.location;
  final url = '${location.origin}${location.pathname}#$route';
  web.window.open(url, '_blank');
  return true;
}
