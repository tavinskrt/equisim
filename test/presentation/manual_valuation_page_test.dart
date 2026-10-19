import 'package:equisim/presentation/shared/ui_kit.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/manual_valuation_page.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'populated_state.dart';

/// A tela de edição do valuation (decisão 147): os campos abrem nos números do
/// motor, cada troca recalcula o preço na hora, e a conta recusa com o campo
/// nomeado quando a premissa não tem conta.
void main() {
  Future<ValuationResult> build(
    WidgetTester tester, {
    bool firm = true,
    double width = 390,
    double shock = 1.0,
    ManualPremises Function(ManualPremises engine)? initial,
  }) async {
    final r = cascadeValuation(firm: firm, shock: shock);
    tester.view.devicePixelRatio = 1.0;
    // Alta o bastante para a lista construir todos os cartões: o teste confere
    // o resultado, e não a rolagem.
    tester.view.physicalSize = Size(width, 7000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildFinTheme(isLight: true),
      home: ManualValuationPage(
        result: r,
        initial: initial?.call(r.manual!.enginePremises),
      ),
    ));
    await tester.pumpAndSettle();
    return r;
  }

  /// O preço do usuário, como a barra do rodapé o escreve.
  String barPrice(WidgetTester tester) {
    final bar = find.ancestor(
      of: find.text('Seu preço justo').last,
      matching: find.byType(Column),
    ).first;
    final texts = find.descendant(of: bar, matching: find.byType(Text));
    return tester.widget<Text>(texts.at(1)).data!;
  }

  testWidgets('abre nos números do motor, com o preço do motor', (tester) async {
    final r = await build(tester);
    expect(find.text('Editar valuation'), findsOneWidget);
    expect(
      find.text('Igual ao do motor: nenhum campo foi trocado'),
      findsOneWidget,
    );
    expect(
      find.text('Troque um campo para ver quanto cada discordância move o '
          'preço.'),
      findsOneWidget,
    );
    expect(barPrice(tester), Fmt.money(r.fairValue.reais));
    expect(find.text('Seu número'), findsNothing);
    // A via da firma parte do lucro da operação.
    expect(find.text('Lucro operacional de partida'), findsWidgets);
  });

  testWidgets('digitar a taxa recalcula o preço na hora', (tester) async {
    final r = await build(tester);
    final m = r.manual!;
    final rate = find.byKey(const ValueKey('campo-discountRate'));
    await tester.ensureVisible(rate);
    await tester.enterText(rate, '20');
    await tester.pumpAndSettle();
    final expected = m
        .evaluate(m.enginePremises.copyWith(discountRate: 0.20))
        .unwrap()
        .fairValuePerShare;
    expect(barPrice(tester), Fmt.money(expected));
    expect(expected, lessThan(m.engineFairValue));
    expect(find.text('Seu número'), findsOneWidget);
    expect(find.text('A conta do motor com os seus números'), findsOneWidget);
    // A decomposição tem um degrau só: a taxa.
    expect(find.text('Taxa de desconto'), findsWidgets);
    expect(find.text('sem valor finito'), findsNothing);
  });

  testWidgets('o mais da taxa sobe um quarto de ponto, e voltar ao motor '
      'desfaz tudo', (tester) async {
    final r = await build(tester);
    final m = r.manual!;
    final plus = find.byTooltip('Aumentar taxa de desconto');
    await tester.ensureVisible(plus);
    await tester.tap(plus);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('campo-discountRate')),
    );
    final rate = m.enginePremises.discountRate;
    final expectedRate = ((rate + 0.0025) / 0.0025).roundToDouble() * 0.0025;
    expect(field.controller!.text, Fmt.ratio(expectedRate * 100, decimals: 2));

    await tester.tap(find.text('Voltar aos números do motor'));
    await tester.pumpAndSettle();
    expect(barPrice(tester), Fmt.money(r.fairValue.reais));
    expect(find.text('Seu número'), findsNothing);
  });

  testWidgets('a recusa nomeia o campo, e o preço some', (tester) async {
    await build(
      tester,
      initial: (m) => m.copyWith(
        reinvestment: ManualReinvestment.fixedFraction,
        retention: 0.3,
        perpetualGrowth: 0.40,
      ),
    );
    expect(barPrice(tester), '—');
    expect(
      find.textContaining('precisa superar o crescimento perpétuo'),
      findsWidgets,
    );
  });

  testWidgets('o que o preço de hoje supõe, e usar o valor', (tester) async {
    final r = await build(tester);
    final calculateButton = find.text('Calcular');
    await tester.ensureVisible(calculateButton);
    await tester.tap(calculateButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('teria de ser'), findsOneWidget);
    final useButton = find.text('Usar este valor');
    await tester.ensureVisible(useButton);
    await tester.tap(useButton);
    await tester.pumpAndSettle();
    // O preço justo passa a ser o de mercado.
    expect(barPrice(tester), Fmt.money(r.marketPrice.reais));
  });

  testWidgets('a via do acionista parte do lucro líquido', (tester) async {
    final r = await build(tester, firm: false);
    expect(r.manual!.lane, ValuationLane.shareholder);
    expect(find.text('Lucro líquido de partida'), findsWidgets);
    expect(find.text('Retorno sobre o patrimônio'), findsWidgets);
  });

  testWidgets('em tela larga, o resultado fica ao lado e sem barra no rodapé',
      (tester) async {
    await build(tester, width: 1200);
    // O título do resumo aparece no cartão, e não há barra fixa.
    expect(find.text('SEU PREÇO JUSTO'), findsOneWidget);
    expect(find.text('Seu preço justo'), findsNothing);
  });

  // ---------------------------------------------------------------------
  // Por que o motor normalizou o lucro de partida (orientador, 14/10/2026)
  // ---------------------------------------------------------------------

  testWidgets('o último ano deprimido: o painel abre dizendo que subiu, e por '
      'quê', (tester) async {
    final r = await build(tester, shock: 0.6);
    final n = r.diagnostics!.baseNormalization!;
    expect(n.outcome, BaseNormalizationOutcome.upward);
    expect(find.text('Por que o motor subiu o lucro de partida?'),
        findsOneWidget);
    expect(find.textContaining('Para cima, ×'), findsOneWidget);
    // Aberto: a resposta com os números do ativo, os anos do ciclo, o teste e
    // a conta.
    expect(find.textContaining('abaixo do seu típico'), findsOneWidget);
    expect(find.text('${n.latestYear}'), findsWidgets);
    expect(find.textContaining('O teste: o último ano dividido pelo típico'),
        findsOneWidget);
    expect(find.textContaining('A conta:'), findsOneWidget);
    // A referência do campo diz a direção.
    expect(find.textContaining('normalizado para cima pelo ciclo'),
        findsOneWidget);
  });

  testWidgets('o último ano de pico: o painel diz que baixou', (tester) async {
    final r = await build(tester, shock: 1.8);
    expect(r.diagnostics!.baseNormalization!.outcome,
        BaseNormalizationOutcome.downward);
    expect(find.text('Por que o motor baixou o lucro de partida?'),
        findsOneWidget);
    expect(find.textContaining('acima do seu típico'), findsOneWidget);
  });

  testWidgets('sem normalização, o painel fica fechado e abre com o toque',
      (tester) async {
    final r = await build(tester);
    final n = r.diagnostics!.baseNormalization!;
    expect(n.factor, 1.0);
    final question = find.text('Por que o motor usou o lucro publicado?');
    expect(question, findsOneWidget);
    expect(find.textContaining('O teste: o último ano'), findsNothing);
    await tester.ensureVisible(question);
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.textContaining('Um ano só pode ter sido um pico ou um vale'),
        findsOneWidget);
  });
}
