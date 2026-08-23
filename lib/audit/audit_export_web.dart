import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Entrega o arquivo de auditoria ao usuário como download do navegador.
///
/// O conteúdo é montado em memória e publicado como *object URL*; nada trafega
/// pela rede. O `revokeObjectURL` logo em seguida devolve a memória — sem ele,
/// exportar várias vezes numa sessão longa deixaria cópias do arquivo presas
/// até a aba ser fechada.
bool downloadJson(String filename, String content) {
  final blob = web.Blob(
    <JSAny>[content.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
