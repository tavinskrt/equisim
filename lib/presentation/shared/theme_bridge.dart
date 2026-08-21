import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/theme_controller.dart';

/// Ponte entre o controlador de tema legado e o Riverpod.
///
/// O `ThemeController` continua sendo `ChangeNotifier` e continua servindo às
/// telas de autenticação, que seguem em Provider. A **mesma instância** é
/// injetada nas duas árvores em `main.dart`, de modo que não existem dois
/// estados de tema concorrendo — o que aconteceria se cada árvore criasse o
/// seu.
///
/// A alternativa seria converter as seis telas legadas para `ConsumerWidget`
/// só para ler um booleano. Preservá-las intactas mantém o risco onde ele deve
/// estar: nas telas novas, não nas que já funcionam.
final themeControllerProvider = Provider<ThemeController>(
  (ref) => throw UnimplementedError(
    'themeControllerProvider deve ser sobrescrito na raiz com a mesma '
    'instância entregue ao Provider legado.',
  ),
);

/// `true` quando o modo claro está ativo.
///
/// Provider separado para que a interface reconstrua ao alternar o tema sem
/// depender de `ChangeNotifier` dentro do Riverpod.
final isLightModeProvider = StateProvider<bool>((ref) => false);
