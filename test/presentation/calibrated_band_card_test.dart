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
  final tabelas = CalibratedBandCodec.decode(
      jsonDecode(File(calibratedBandAsset).readAsStringSync())
          as Map<String, dynamic>);

  Widget tela(List<Override> overrides) => ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('usuario-1'),
          marketAnchorsProvider
              .overrideWith((ref) async => MarketAnchors.fallback2026),
          valuationProvider.overrideWith(
              (ref, ticker) async => valuationOf(ticker.value, justo: 42.80)),
          isLightModeProvider.overrideWith(() => IsLightMode(inicial: false)),
          ...overrides,
        ],
        child: MaterialApp(
          theme: buildFinTheme(isLight: false),
          home: Scaffold(
            body: ValuationView(ticker: Ticker.parse('PETR4'), isLight: false),
          ),
        ),
      );

  for (final largura in const [320.0, 1024.0]) {
    testWidgets('com o pacote, mostra os dois horizontes sem estouro em '
        '${largura.toInt()} dp', (tester) async {
      tester.view.physicalSize = Size(largura, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(tela([
        calibratedBandsProvider.overrideWith((ref) async => tabelas),
      ]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('FAIXA CALIBRADA'), findsOneWidget);
      expect(find.text('Em 12 meses'), findsOneWidget);
      expect(find.text('Em 36 meses'), findsOneWidget);
      // R$ 42,80 × 0,6248 e × 9,2125, na faixa de 80% em 12 meses.
      final t = CalibratedBand.select(tabelas, months: 12, nominal: 0.8)!;
      final b = CalibratedBand.around(Money.fromReais(42.80), t)!;
      expect(find.textContaining(Fmt.money(b.low.reais)), findsOneWidget);
      expect(find.textContaining('medidos fora da amostra'), findsOneWidget);
    });
  }

  testWidgets('sem pacote, o cartão não aparece e a sensibilidade fica',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(tela([
      calibratedBandsProvider
          .overrideWith((ref) async => const <CalibratedBandTable>[]),
    ]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('FAIXA CALIBRADA'), findsNothing);
    expect(find.textContaining('Sensibilidade:'), findsOneWidget);
  });
}
