import 'dart:convert';
import 'dart:io';

import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shared/ui_kit.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'populated_state.dart' show valuationOf;

/// A faixa calibrada na tela de avaliação (item C2, decisão 92): aparece com o
/// pacote, some sem ele, e a tela **carregada** não estoura em celular pequeno
/// — foi este teste que achou o gráfico de sensibilidade estourando 134 px em
/// 320 dp, que o teste de estouro com a tela vazia não via.
void main() {
  final tables = CalibratedBandCodec.decode(
      jsonDecode(File(calibratedBandAsset).readAsStringSync())
          as Map<String, dynamic>);

  // A avaliação que a tela recebe. É variável porque a família de providers não
  // aceita ser sobrescrita duas vezes no mesmo contêiner, e um dos casos precisa
  // de uma avaliação sem volatilidade.
  ValuationResult? Function(String) valuation =
      (symbol) => valuationOf(symbol, fairValue: 42.80);

  Widget screen(List<Override> overrides) => ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('usuario-1'),
          marketAnchorsProvider
              .overrideWith((ref) async => MarketAnchors.fallback2026),
          valuationProvider
              .overrideWith((ref, ticker) async => valuation(ticker.value)),
          isLightModeProvider.overrideWith(() => IsLightMode(initial: false)),
          ...overrides,
        ],
        child: MaterialApp(
          theme: buildFinTheme(isLight: false),
          home: Scaffold(
            body: ValuationView(ticker: Ticker.parse('PETR4')),
          ),
        ),
      );

  for (final width in const [320.0, 1024.0]) {
    testWidgets('com o pacote, mostra os dois horizontes sem estouro em '
        '${width.toInt()} dp', (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen([
        calibratedBandsProvider.overrideWith((ref) async => tables),
      ]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('FAIXA CALIBRADA'), findsOneWidget);
      expect(find.text('Em 12 meses'), findsOneWidget);
      expect(find.text('Em 36 meses'), findsOneWidget);
      // R$ 42,80 vezes os fatores da faixa de 80% em 12 meses, lidos do pacote.
      final t = CalibratedBand.select(tables, months: 12, nominal: 0.8)!;
      final b = CalibratedBand.of(
        Money.fromReais(42.80),
        t,
        marketPrice: valuationOf('PETR4', fairValue: 42.80).marketPrice,
        volatility: valuationOf('PETR4', fairValue: 42.80).priceVolatility,
      )!;
      expect(find.textContaining(Fmt.money(b.low.reais)), findsOneWidget);
      // A cobertura de cada horizonte aparece como foi medida.
      final t36 = CalibratedBand.select(tables, months: 36, nominal: 0.8)!;
      expect(
          find.textContaining(
              Fmt.percent(t.outOfSampleCoverage!, decimals: 1)),
          findsOneWidget);
      expect(
          find.textContaining(
              Fmt.percent(t36.outOfSampleCoverage!, decimals: 1)),
          findsOneWidget);
    });
  }

  // A tela só diz "8 de cada 10" quando a faixa de 80% cobriu isso fora da
  // amostra, a até 5 pontos (decisão 97). O pacote de hoje não cobre, e a tela
  // tem de dizê-lo; uma tabela sintética calibrada confere o outro caminho.
  CalibratedBandTable withCoverage(int months, double coverage) =>
      VolatilityBandTable(
        months: months,
        nominal: 0.8,
        a: 0.08,
        b: 0.03,
        zLower: -1.2,
        zUpper: 1.2,
        observations: 1000,
        firstCohort: 2018,
        lastCohort: 2025,
        outOfSampleCoverage: coverage,
        outOfSampleObservations: 900,
      );

  for (final (label, coverages, expected, missing) in [
    (
      'calibrada',
      (0.79, 0.804),
      'Em 8 de cada 10 avaliações passadas',
      'não está calibrada',
    ),
    (
      'fora do critério',
      (0.749, 0.73),
      'não está calibrada',
      'Em 8 de cada 10',
    ),
  ]) {
    testWidgets('faixa $label: o texto diz a cobertura medida', (tester) async {
      tester.view.physicalSize = const Size(1024, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen([
        calibratedBandsProvider.overrideWith((ref) async => [
              withCoverage(12, coverages.$1),
              withCoverage(36, coverages.$2),
            ]),
      ]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining(expected), findsOneWidget);
      expect(find.textContaining(missing), findsNothing);
      expect(find.textContaining(Fmt.percent(coverages.$2, decimals: 1)),
          findsOneWidget);
    });
  }

  // A faixa da volatilidade precisa da volatilidade do papel, e a avaliação a
  // traz da mesma série que a cascata usou. Sem ela — papel com menos de 120
  // pregões na janela —, o cartão some em vez de inventar uma largura.
  testWidgets('sem a volatilidade do papel, o cartão não aparece',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    valuation = (symbol) => ValuationResult(
          ticker: Ticker.parse(symbol),
          asOf: DateTime(2024, 12, 31),
          model: ValuationModel.dcfEarnings,
          fairValue: Money.fromReais(42.80),
          marketPrice: Money.fromReais(33.15),
          discountRate: 0.132,
        );
    addTearDown(() => valuation = (s) => valuationOf(s, fairValue: 42.80));

    await tester.pumpWidget(screen([
      calibratedBandsProvider.overrideWith((ref) async => tables),
    ]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('FAIXA CALIBRADA'), findsNothing);
  });

  testWidgets('sem pacote, o cartão não aparece e a sensibilidade fica',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(screen([
      calibratedBandsProvider
          .overrideWith((ref) async => const <CalibratedBandTable>[]),
    ]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('FAIXA CALIBRADA'), findsNothing);
    expect(find.text('SENSIBILIDADE'), findsOneWidget);
  });
}
