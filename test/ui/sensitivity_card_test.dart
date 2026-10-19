import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// O cartão de sensibilidade da tela de avaliação (decisão 148): um cartão só,
/// com os conjuntos fixos nomeados pelas premissas, e a inversão declarada
/// quando as premissas mais brandas dão preço menor (item B38).
void main() {
  ValuationResult valuation({required double harsh, required double mild}) =>
      ValuationResult(
        ticker: Ticker.parse('PETR4'),
        asOf: DateTime(2026, 9, 14),
        model: ValuationModel.dcfFcff,
        fairValue: Money.fromReais(20),
        marketPrice: Money.fromReais(25),
        discountRate: 0.15,
        discreteScenarios: {
          ScenarioBand.bear: Money.fromReais(harsh),
          ScenarioBand.base: Money.fromReais(20),
          ScenarioBand.bull: Money.fromReais(mild),
        },
      );

  Future<void> build(
    WidgetTester tester,
    ValuationResult r, {
    double width = 390,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('usuario-1'),
        valuationProvider.overrideWith((ref, ticker) async => r),
        calibratedBandsProvider
            .overrideWith((ref) async => const <CalibratedBandTable>[]),
        isLightModeProvider.overrideWith(() => IsLightMode(initial: true)),
      ],
      child: MaterialApp(
        theme: buildFinTheme(isLight: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 2400),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: ValuationView(ticker: Ticker.parse('PETR4')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('um cartão só, com os conjuntos nomeados pelas premissas',
      (tester) async {
    await build(tester, valuation(harsh: 14, mild: 28));
    expect(find.text('SENSIBILIDADE'), findsOneWidget);
    expect(find.text('CENÁRIOS'), findsNothing);
    expect(find.text('Premissas mais duras'), findsOneWidget);
    expect(find.text('Premissas do motor'), findsOneWidget);
    expect(find.text('Premissas mais brandas'), findsOneWidget);
    expect(find.text('Pessimista'), findsNothing);
    expect(find.text('Otimista'), findsNothing);
    // A nota diz quanto foi mexido, com o número que a conta usa.
    expect(find.text('crescimento −3 p.p., taxa +2 p.p.'),
        findsOneWidget);
    expect(find.text('crescimento +3 p.p., taxa −2 p.p.'),
        findsOneWidget);
    expect(find.textContaining('dão preço menor'), findsNothing);
  });

  testWidgets('premissas mais brandas abaixo das mais duras: o cartão diz por '
      'quê', (tester) async {
    await build(tester, valuation(harsh: 18, mild: 15));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Aqui as premissas mais brandas dão preço menor'),
        findsOneWidget);
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('cabe em 320 dp sob ${scale}x, também invertido',
        (tester) async {
      await build(
        tester,
        valuation(harsh: 18, mild: 15),
        width: 320,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
