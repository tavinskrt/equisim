import 'dart:convert';
import 'dart:io';

import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/goals/goal_page.dart';
import 'package:equisim/presentation/goals/skill_copy.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ressalva da tela de metas sobre o prêmio tirado do potencial (item B1.0):
/// a §0 do plano chamou de defeito em produção a tela que soma ao `Ke` um
/// prêmio de um ordenador que não bate o book-to-market, sem dizer isso.
void main() {
  final doPacote = SkillReadingCodec.decode(
      jsonDecode(File(skillReadingAsset).readAsStringSync())
          as Map<String, dynamic>)!;

  SkillReading leitura({
    double t = 0.24,
    double critico = 2.70,
    double nw = 0.69,
    double icPotencial = 0.09,
    double icBm = 0.18,
  }) =>
      SkillReading(
        months: 36,
        cohorts: 22,
        conditionalCoefficient: 0.03,
        overlapT: t,
        overlapCritical: critico,
        neweyWestT: nw,
        potentialIc: icPotencial,
        bookToMarketIc: icBm,
      );

  Widget tela(List<Override> overrides) => ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('usuario-1'),
          universeProvider.overrideWith((ref) async => const <Ticker>[]),
          riskFreeRateProvider.overrideWith((ref) async => 0.094),
          marketAnchorsProvider
              .overrideWith((ref) async => MarketAnchors.fallback2026),
          portfolioValuationsProvider
              .overrideWith((ref) async => const <Ticker, ValuationResult>{}),
          valuationProvider.overrideWith((ref, ticker) async => null),
          isLightModeProvider.overrideWith(() => IsLightMode(inicial: false)),
          goalFeasibilityProvider.overrideWith((ref) async => null),
          goalAlignmentProvider.overrideWith((ref) async => GoalAlignment(
                required: const RequiredReturn(monthly: 0.0142, iterations: 24),
                verdict: FeasibilityVerdict(
                  level: FeasibilityLevel.demanding,
                  reason: FeasibilityReason.aboveMarket,
                  requiredAnnualRate: 0.1844,
                  anchors: MarketAnchors.fallback2026,
                ),
                expectedReturn: 0.1495,
                valuationCoverage: 1,
              )),
          ...overrides,
        ],
        child: MaterialApp(
          theme: buildFinTheme(isLight: false),
          home: const Scaffold(body: GoalPage()),
        ),
      );

  Future<void> abrir(WidgetTester tester, SkillReading? s) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 4000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        tela([skillReadingProvider.overrideWith((ref) async => s)]));
    await tester.pumpAndSettle();
  }

  String? ressalvaNaTela(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((t) => t.startsWith('O prêmio pelo desconto relativo'))
      .firstOrNull;

  testWidgets('com a leitura do pacote, a tela cita o que a validação mediu',
      (tester) async {
    await abrir(tester, doPacote);

    expect(doPacote.demonstrated, isFalse,
        reason: 'se o C1 aprovar, este teste precisa mudar junto com o plano');
    final texto = ressalvaNaTela(tester);
    expect(texto, isNotNull);
    expect(texto, contains('não comprovou saber ordenar ações'));
    expect(texto, contains('t corrigido de ${_duas(doPacote.overlapT)}'));
    expect(texto, contains('contra ${_duas(doPacote.overlapCritical)} exigido'));
    expect(texto, contains('acima do Ke não está comprovada'));
    // Dentro do cartão do confronto, e uma vez só.
    expect(find.text('CARTEIRA FRENTE À META'), findsOneWidget);
    expect(find.byIcon(Icons.rule_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('com a habilidade comprovada, a ressalva some', (tester) async {
    await abrir(tester, leitura(t: 3.1, nw: 2.4));
    expect(ressalvaNaTela(tester), isNull);
    expect(find.byIcon(Icons.rule_outlined), findsNothing);
  });

  testWidgets('sem pacote, a ressalva diz que a habilidade não foi medida',
      (tester) async {
    await abrir(tester, null);
    expect(ressalvaNaTela(tester), contains('não veio medida'));
  });

  group('a frase segue a medição, e não um texto fixo', () {
    test('ordenar pior que o B/M só é dito quando o IC é menor', () {
      expect(SkillCopy.caveat(leitura()),
          contains('pior que o valor patrimonial sobre o preço'));
      expect(SkillCopy.caveat(leitura()), contains('0,09 contra 0,18'));
      expect(SkillCopy.caveat(leitura(icPotencial: 0.2)),
          isNot(contains('pior')));
    });

    test('a perna do critério que falhou é a que a frase cita', () {
      // O corrigido passou e o Newey-West não.
      final nw = SkillCopy.caveat(leitura(t: 2.9, nw: 1.5))!;
      expect(nw, contains('não passou no Newey-West'));
      expect(nw, contains('t de 1,50, contra 2,00 exigido'));
      expect(nw, isNot(contains('t corrigido')));
    });
  });
}

String _duas(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
