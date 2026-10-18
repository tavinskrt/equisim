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
  ValuationResult avaliacao({required double duras, required double brandas}) =>
      ValuationResult(
        ticker: Ticker.parse('PETR4'),
        asOf: DateTime(2026, 9, 14),
        model: ValuationModel.dcfFcff,
        fairValue: Money.fromReais(20),
        marketPrice: Money.fromReais(25),
        discountRate: 0.15,
        discreteScenarios: {
          ScenarioBand.bear: Money.fromReais(duras),
          ScenarioBand.base: Money.fromReais(20),
          ScenarioBand.bull: Money.fromReais(brandas),
        },
      );

  Future<void> montar(
    WidgetTester tester,
    ValuationResult r, {
    double largura = 390,
    double escala = 1.0,
  }) async {
    tester.view.physicalSize = Size(largura, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('usuario-1'),
        valuationProvider.overrideWith((ref, ticker) async => r),
        calibratedBandsProvider
            .overrideWith((ref) async => const <CalibratedBandTable>[]),
        isLightModeProvider.overrideWith(() => IsLightMode(inicial: true)),
      ],
      child: MaterialApp(
        theme: buildFinTheme(isLight: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(largura, 2400),
            textScaler: TextScaler.linear(escala),
          ),
          child: Scaffold(
            body: ValuationView(ticker: Ticker.parse('PETR4'), isLight: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('um cartão só, com os conjuntos nomeados pelas premissas',
      (tester) async {
    await montar(tester, avaliacao(duras: 14, brandas: 28));
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
    await montar(tester, avaliacao(duras: 18, brandas: 15));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Aqui as premissas mais brandas dão preço menor'),
        findsOneWidget);
  });

  for (final escala in const [1.0, 2.0]) {
    testWidgets('cabe em 320 dp sob ${escala}x, também invertido',
        (tester) async {
      await montar(
        tester,
        avaliacao(duras: 18, brandas: 15),
        largura: 320,
        escala: escala,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
