import 'dart:convert';
import 'dart:io';

import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'populated_state.dart' show valuationOf;

/// A segunda leitura na tela de avaliação (item B5, decisão 118): aparece com
/// o pacote, some sem ele, diz de quantos pares saiu cada múltiplo, e **não
/// estoura em celular pequeno**.
void main() {
  final today = DateTime(2026, 9, 14);

  FundamentalsSnapshot fiscalYear() => FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        totalRevenue: 12000,
        ebit: 1800,
        ebitda: 2400,
        netIncome: 1000,
        incomeBeforeTax: 1400,
        incomeTaxExpense: -400,
        interestExpense: 300,
        earningsPerShare: 1.0,
        cash: 500,
        shortTermDebt: 750,
        longTermDebt: 2250,
        totalStockholderEquity: 8000,
        bookValuePerShare: 8.0,
        operatingCashFlow: 2000,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 10000,
      );

  PeerMultipleSet pairs({bool withEbitda = true}) => PeerMultipleSet(
        asOf: today,
        byKind: {
          MultipleKind.priceToEarnings: const PeerMultiple(
              median: 11.4, peers: 8, group: 'petroleo-gas-e-biocombustiveis'),
          MultipleKind.priceToBook: const PeerMultiple(
              median: 1.6, peers: 10, group: 'petroleo-gas-e-biocombustiveis'),
          if (withEbitda)
            MultipleKind.evToEbitda: const PeerMultiple(
                median: 7.1, peers: 10, group: 'petroleo-gas-e-biocombustiveis'),
        },
      );

  ValuationResult withTriangulation({
    double fairValue = 42.80,
    bool withEbitda = true,
  }) {
    final base = valuationOf('PETR4', fairValue: fairValue);
    final t = PeerTriangulation.build(
      latest: fiscalYear(),
      shares: 1000,
      peers: pairs(withEbitda: withEbitda),
      dcfFairValue: fairValue,
    );
    return ValuationResult(
      ticker: base.ticker,
      asOf: base.asOf,
      model: base.model,
      fairValue: base.fairValue,
      marketPrice: base.marketPrice,
      discountRate: base.discountRate,
      marginOfSafety: base.marginOfSafety,
      mode: base.mode,
      discreteScenarios: base.discreteScenarios,
      warnings: base.warnings,
      priceVolatility: base.priceVolatility,
      triangulation: t,
    );
  }

  Widget screen(ValuationResult? result) => ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('usuario-1'),
          marketAnchorsProvider
              .overrideWith((ref) async => MarketAnchors.fallback2026),
          valuationProvider.overrideWith((ref, ticker) async => result),
          isLightModeProvider.overrideWith(() => IsLightMode(initial: false)),
        ],
        child: MaterialApp(
          theme: buildFinTheme(isLight: false),
          home: Scaffold(
            body: ValuationView(ticker: Ticker.parse('PETR4')),
          ),
        ),
      );

  testWidgets('sem pacote de pares, o cartão não existe', (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(screen(valuationOf('PETR4')));
    await tester.pumpAndSettle();

    expect(find.textContaining('MÚLTIPLOS DE PARES'), findsNothing);
  });

  for (final width in const [320.0, 1024.0]) {
    testWidgets('com o pacote, mostra as três leituras sem estouro em '
        '${width.toInt()} dp', (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen(withTriangulation()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // `SectionHeader` sobe o título para caixa alta.
      expect(find.textContaining('MÚLTIPLOS DE PARES'), findsOneWidget);
      // Os três rótulos, e a mediana de cada um com o tamanho do grupo.
      expect(find.text('P/L'), findsOneWidget);
      expect(find.text('P/VP'), findsOneWidget);
      expect(find.text('EV/EBITDA'), findsOneWidget);
      expect(find.textContaining('11.4× em 8 pares'), findsOneWidget);
    });
  }

  testWidgets('o rótulo diz que o preço justo continua sendo o do DCF',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(screen(withTriangulation()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('preço justo continua sendo o do fluxo descontado'),
      findsOneWidget,
    );
  });

  testWidgets('a divergência grande vira ressalva, e a pequena não',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // P/L 11,4 × R$ 1,00 = R$ 11,40; P/VP 1,6 × R$ 8,00 = R$ 12,80;
    // EV/EBITDA 7,1 × 2.400 − 2.500 = R$ 14,54. A mediana é R$ 12,80.
    await tester.pumpWidget(screen(withTriangulation(fairValue: 12.60)));
    await tester.pumpAndSettle();
    expect(find.textContaining('as duas leituras concordam'), findsOneWidget);
    expect(find.textContaining('as duas leituras discordam'), findsNothing);
  });

  testWidgets('divergência além do limite é dita na tela', (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Mediana dos múltiplos em R$ 12,80 contra um DCF de R$ 42,80: −70%.
    await tester.pumpWidget(screen(withTriangulation()));
    await tester.pumpAndSettle();
    expect(find.textContaining('as duas leituras discordam'), findsOneWidget);
  });

  testWidgets('múltiplo que não se aplica é dito, e não some', (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(screen(withTriangulation(withEbitda: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fora: EV/EBITDA'), findsOneWidget);
  });

  test('o pacote versionado do build é legível', () {
    // A conferência que impede o pacote de sair do build quebrado: se a
    // ferramenta mudar de formato e o codec não, a tela fica sem a segunda
    // leitura **em silêncio**.
    final file = File(peerMultiplesAsset);
    expect(file.existsSync(), isTrue,
        reason: 'rode tool/multiplos_empacotar.dart');
    final parsed = PeerMultipleCodec.decode(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    expect(parsed, isNotEmpty);
    final any = parsed.values.first;
    expect(any.byKind, isNotEmpty);
    for (final m in any.byKind.values) {
      expect(m.median, greaterThan(0));
      expect(m.peers, greaterThanOrEqualTo(PeerValuation.minimumPeers));
      expect(m.group, isNotEmpty);
    }
  });
}
