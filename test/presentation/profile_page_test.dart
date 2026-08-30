import 'package:equisim/controllers/theme_controller.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/views/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rede de segurança da tela de perfil.
///
/// Escrito ANTES da decomposição da UI-11 justamente porque não havia nenhum:
/// mover 700 linhas de um `build` sem teste é o tipo de mudança que quebra em
/// silêncio. O que ele trava não é o arranjo interno -- que a refatoração pode
/// e deve mudar -- e sim o que a tela precisa continuar mostrando e o fato de
/// caber nas larguras suportadas.
Future<Widget> _host({
  required bool isLight,
  double escala = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({ThemeController.prefsKey: isLight});
  final theme = await ThemeController.load();

  return ChangeNotifierProvider<ThemeController>.value(
    value: theme,
    child: MaterialApp(
      theme: buildFinTheme(isLight: isLight),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala)),
          child: const ProfilePage(),
        ),
      ),
    ),
  );
}

void main() {
  group('ProfilePage — estrutura', () {
    testWidgets('monta e mostra as seções da conta', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 3000);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await _host(isLight: true));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Meu Perfil'), findsOneWidget);
      expect(find.text('INFORMAÇÕES DA CONTA'), findsOneWidget);
    });

    testWidgets('funciona nos dois temas', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 3000);
      addTearDown(tester.view.reset);

      for (final isLight in [true, false]) {
        await tester.pumpWidget(await _host(isLight: isLight));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'A tela quebrou no tema ${isLight ? "claro" : "escuro"}.',
        );
      }
    });
  });

  group('ProfilePage — layout', () {
    for (final largura in <double>[320, 390, 1024]) {
      for (final escala in <double>[1.0, 1.3, 2.0]) {
        testWidgets('cabe em ${largura.toInt()} dp sob ${escala}x', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1.0;
          // Altura generosa: a tela é longa e rolável, e o alvo aqui é a
          // LARGURA. Sem isso o teste mediria o corte vertical do viewport,
          // que não é defeito.
          tester.view.physicalSize = Size(largura, 4000);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(await _host(isLight: true, escala: escala));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'ProfilePage estourou em ${largura.toInt()} dp sob '
                'escala ${escala}x.',
          );
        });
      }
    }
  });
}
