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
class IsLightMode extends Notifier<bool> {
  /// Declara o notificador com o valor de partida.
  ///
  /// O valor vem por construtor porque `main` já conhece a preferência antes
  /// do primeiro quadro — semear aqui é o que evita a piscada de tema.
  IsLightMode({bool initial = false}) : _initial = initial;

  final bool _initial;

  @override
  bool build() => _initial;

  /// Escreve o tema corrente.
  ///
  /// Método em vez de `state` público: em `Notifier` o setter é protegido, e
  /// expor a escrita por um nome próprio deixa explícito quem pode alterá-la.
  void setValue(bool value) => state = value;
}

/// `true` quando o modo claro está ativo.
///
/// Era um `StateProvider`, que o Riverpod 3 moveu para `legacy.dart`. Migrado para
/// `Notifier` em vez de importar o legado: a escrita continua existindo, mas
/// agora atrás de um método nomeado.
final isLightModeProvider = NotifierProvider<IsLightMode, bool>(
  IsLightMode.new,
);
