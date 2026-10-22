import 'package:equisim/presentation/shared/charts.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estado vazio dos graficos sob escala de texto ampliada.
///
/// Existe porque `overflow_test.dart` NAO cobre estes widgets: naquele harness
/// os providers remotos devolvem vazio, entao os graficos nem chegam a ser
/// construidos. Foi essa cegueira que deixou passar um `SizedBox(height: 230)`
/// travando o estado vazio da dispersao -- achado que so apareceu na auditoria.
///
/// Aqui os widgets sao montados direto, com dado insuficiente de proposito,
/// que e o caminho que renderiza o `EmptyState`.
Widget _host(Widget child, {required double scale, required double width}) =>
    MaterialApp(
      theme: buildFinTheme(isLight: true),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  const widths = <double>[320, 390];
  const scales = <double>[1.0, 1.3, 2.0];

  group('Base100Chart — sem série', () {
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('cabe em ${width.toInt()} dp sob ${scale}x', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(
              // Menos de duas datas é o caminho do estado vazio.
              const Base100Chart(
                series: [],
                dates: [],
              ),
              scale: scale,
              width: width,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'O estado vazio do gráfico estourou em '
                '${width.toInt()} dp sob ${scale}x. A altura declarada é a '
                'do gráfico; o texto que ocupa o lugar dele precisa de piso, '
                'não de teto.',
          );
        });
      }
    }
  });

  group('RiskReturnScatter — sem pontos', () {
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('cabe em ${width.toInt()} dp sob ${scale}x', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(
              const RiskReturnScatter(points: []),
              scale: scale,
              width: width,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
