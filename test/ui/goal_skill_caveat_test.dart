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
import 'package:equisim/presentation/shared/domain_copy.dart';

/// A ressalva da tela de metas sobre o prêmio tirado do potencial (item B1.0):
/// a §0 do plano chamou de defeito em produção a tela que soma ao `Ke` um
/// prêmio de um ordenador que não bate o book-to-market, sem dizer isso.
void main() {
  final packagedQuotes = SkillReadingCodec.decode(
      jsonDecode(File(skillReadingAsset).readAsStringSync())
          as Map<String, dynamic>)!;

  OrderingReading order(double ic, {bool passes = false}) => OrderingReading(
        ic: ic,
        overlapT: passes ? 3.1 : 0.7,
        overlapCritical: 2.70,
        neweyWestT: passes ? 3.0 : 1.2,
      );

  SkillReading reading({
    double t = 0.24,
    double critical = 2.70,
    double nw = 0.69,
    double upsideIc = 0.09,
    double icBm = 0.18,
    bool bmPasses = false,
    bool compositePasses = false,
    bool upsidePasses = false,
  }) =>
      SkillReading(
        months: 36,
        cohorts: 22,
        conditionalCoefficient: 0.03,
        overlapT: t,
        overlapCritical: critical,
        neweyWestT: nw,
        orderings: {
          TransversalOrdering.composite: order(0.15, passes: compositePasses),
          TransversalOrdering.bookToMarket: order(icBm, passes: bmPasses),
          TransversalOrdering.potential: order(upsideIc, passes: upsidePasses),
        },
      );

  Widget screen(List<Override> overrides) => ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('usuario-1'),
          universeProvider.overrideWith((ref) async => const <Ticker>[]),
          riskFreeRateProvider.overrideWith((ref) async => 0.094),
          marketAnchorsProvider
              .overrideWith((ref) async => MarketAnchors.fallback2026),
          portfolioValuationsProvider
              .overrideWith((ref) async => const <Ticker, ValuationResult>{}),
          valuationProvider.overrideWith((ref, ticker) async => null),
          isLightModeProvider.overrideWith(() => IsLightMode(initial: false)),
          goalFeasibilityProvider.overrideWith((ref) async => null),
          goalAlignmentProvider.overrideWith((ref) async => GoalAlignment(
                required: const RequiredReturn(monthly: 0.0142),
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

  Future<void> open(WidgetTester tester, SkillReading? s) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 4000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        screen([skillReadingProvider.overrideWith((ref) async => s)]));
    await tester.pumpAndSettle();
  }

  String? caveatOnScreen(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((t) =>
          t.startsWith('O prêmio sobre o Ke') ||
          t.startsWith('Nenhuma ordenação') ||
          t.startsWith('A habilidade de ordenar'))
      .firstOrNull;

  testWidgets('com a leitura do pacote, a tela diz de onde sai o prêmio e o que '
      'a validação mediu do potencial', (tester) async {
    await open(tester, packagedQuotes);

    expect(packagedQuotes.demonstrated, isFalse,
        reason: 'se o C1 aprovar, este teste precisa mudar junto com o plano');
    final text = caveatOnScreen(tester);
    expect(text, isNotNull);
    final premium = packagedQuotes.premiumOrdering;
    if (premium == null) {
      expect(text, contains('O retorno esperado não leva prêmio'));
    } else {
      expect(text, contains('O prêmio sobre o Ke sai de ${premium.label}'));
    }
    expect(text, contains('O potencial do valuation sozinho não comprovou'));
    expect(text, contains('t corrigido de ${_twoDecimals(packagedQuotes.overlapT)}'));
    // Dentro do cartão do confronto, e uma vez só.
    expect(find.text('CARTEIRA FRENTE À META'), findsOneWidget);
    expect(find.byIcon(Icons.rule_outlined), findsOneWidget);
    expect(find.text('retorno total, com proventos reinvestidos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('com o potencial comprovado e dando o prêmio, a ressalva some',
      (tester) async {
    await open(tester, reading(t: 3.1, nw: 2.4, upsidePasses: true));
    expect(caveatOnScreen(tester), isNull);
    expect(find.byIcon(Icons.rule_outlined), findsNothing);
  });

  testWidgets('sem pacote, a tela diz que não mediu, e o esperado fica sem '
      'prêmio', (tester) async {
    await open(tester, null);
    expect(caveatOnScreen(tester), contains('não veio medida'));
    expect(caveatOnScreen(tester), contains('sem prêmio'));
    expect(find.text('Custo do capital próprio, sem prêmio'), findsOneWidget);
  });

  group('a frase segue a medição, e não um texto fixo', () {
    test('a ordenação do prêmio é a da regra, com o número dela', () {
      final bm = SkillCopy.caveat(reading(bmPasses: true))!;
      expect(bm, contains('O prêmio sobre o Ke sai de o valor patrimonial sobre o preço'));
      final composite =
          SkillCopy.caveat(reading(bmPasses: true, compositePasses: true))!;
      expect(composite, contains('sai de o composto'));
      expect(composite, contains('correlação de postos de 0,15'));
    });

    test('nenhuma ordenação comprovada: sem prêmio, e a tela diz', () {
      final nothing = SkillCopy.caveat(reading())!;
      expect(nothing, startsWith('Nenhuma ordenação comprovou habilidade'));
      expect(nothing, contains('é o Ke de cada ativo'));
    });

    test('ordenar pior que o B/M só é dito quando o IC é menor', () {
      expect(SkillCopy.caveat(reading()),
          contains('ordenou pior que ele — correlação de postos de 0,09 contra 0,18'));
      expect(SkillCopy.caveat(reading(upsideIc: 0.2)), isNot(contains('pior')));
    });

    test('a perna do critério que falhou é a que a frase cita', () {
      // O corrigido passou e o Newey-West não.
      final nw = SkillCopy.caveat(reading(t: 2.9, nw: 1.5))!;
      expect(nw, contains('não passou no Newey-West'));
      expect(nw, contains('t de 1,50, contra 2,00 exigido'));
    });
  });
}

String _twoDecimals(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
