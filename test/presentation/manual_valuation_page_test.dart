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
  Future<ValuationResult> montar(
    WidgetTester tester, {
    bool firma = true,
    double largura = 390,
    ManualPremises Function(ManualPremises motor)? inicial,
  }) async {
    final r = avaliacaoDaCascata(firma: firma);
    tester.view.devicePixelRatio = 1.0;
    // Alta o bastante para a lista construir todos os cartões: o teste confere
    // o resultado, e não a rolagem.
    tester.view.physicalSize = Size(largura, 7000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildFinTheme(isLight: true),
      home: ManualValuationPage(
        result: r,
        inicial: inicial?.call(r.manual!.motorPremises),
      ),
    ));
    await tester.pumpAndSettle();
    return r;
  }

  /// O preço do usuário, como a barra do rodapé o escreve.
  String precoDaBarra(WidgetTester tester) {
    final barra = find.ancestor(
      of: find.text('Seu preço justo').last,
      matching: find.byType(Column),
    ).first;
    final textos = find.descendant(of: barra, matching: find.byType(Text));
    return tester.widget<Text>(textos.at(1)).data!;
  }

  testWidgets('abre nos números do motor, com o preço do motor', (tester) async {
    final r = await montar(tester);
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
    expect(precoDaBarra(tester), Fmt.money(r.fairValue.reais));
    expect(find.text('Seu número'), findsNothing);
    // A via da firma parte do lucro da operação.
    expect(find.text('Lucro operacional de partida'), findsWidgets);
  });

  testWidgets('digitar a taxa recalcula o preço na hora', (tester) async {
    final r = await montar(tester);
    final m = r.manual!;
    final taxa = find.byKey(const ValueKey('campo-discountRate'));
    await tester.ensureVisible(taxa);
    await tester.enterText(taxa, '20');
    await tester.pumpAndSettle();
    final esperado = m
        .evaluate(m.motorPremises.copyWith(discountRate: 0.20))
        .unwrap()
        .fairValuePerShare;
    expect(precoDaBarra(tester), Fmt.money(esperado));
    expect(esperado, lessThan(m.motorFairValue));
    expect(find.text('Seu número'), findsOneWidget);
    expect(find.text('A conta do motor com os seus números'), findsOneWidget);
    // A decomposição tem um degrau só: a taxa.
    expect(find.text('Taxa de desconto'), findsWidgets);
    expect(find.text('sem valor finito'), findsNothing);
  });

  testWidgets('o mais da taxa sobe um quarto de ponto, e voltar ao motor '
      'desfaz tudo', (tester) async {
    final r = await montar(tester);
    final m = r.manual!;
    final mais = find.byTooltip('Aumentar taxa de desconto');
    await tester.ensureVisible(mais);
    await tester.tap(mais);
    await tester.pumpAndSettle();
    final campo = tester.widget<TextField>(
      find.byKey(const ValueKey('campo-discountRate')),
    );
    final taxa = m.motorPremises.discountRate;
    final esperada = ((taxa + 0.0025) / 0.0025).roundToDouble() * 0.0025;
    expect(campo.controller!.text, Fmt.ratio(esperada * 100, decimals: 2));

    await tester.tap(find.text('Voltar aos números do motor'));
    await tester.pumpAndSettle();
    expect(precoDaBarra(tester), Fmt.money(r.fairValue.reais));
    expect(find.text('Seu número'), findsNothing);
  });

  testWidgets('a recusa nomeia o campo, e o preço some', (tester) async {
    await montar(
      tester,
      inicial: (m) => m.copyWith(
        reinvestment: ManualReinvestment.parcelaFixa,
        retention: 0.3,
        perpetualGrowth: 0.40,
      ),
    );
    expect(precoDaBarra(tester), '—');
    expect(
      find.textContaining('precisa superar o crescimento perpétuo'),
      findsWidgets,
    );
  });

  testWidgets('o que o preço de hoje supõe, e usar o valor', (tester) async {
    final r = await montar(tester);
    final calcular = find.text('Calcular');
    await tester.ensureVisible(calcular);
    await tester.tap(calcular);
    await tester.pumpAndSettle();
    expect(find.textContaining('teria de ser'), findsOneWidget);
    final usar = find.text('Usar este valor');
    await tester.ensureVisible(usar);
    await tester.tap(usar);
    await tester.pumpAndSettle();
    // O preço justo passa a ser o de mercado.
    expect(precoDaBarra(tester), Fmt.money(r.marketPrice.reais));
  });

  testWidgets('a via do acionista parte do lucro líquido', (tester) async {
    final r = await montar(tester, firma: false);
    expect(r.manual!.lane, ValuationLane.shareholder);
    expect(find.text('Lucro líquido de partida'), findsWidgets);
    expect(find.text('Retorno sobre o patrimônio'), findsWidgets);
  });

  testWidgets('em tela larga, o resultado fica ao lado e sem barra no rodapé',
      (tester) async {
    await montar(tester, largura: 1200);
    // O título do resumo aparece no cartão, e não há barra fixa.
    expect(find.text('SEU PREÇO JUSTO'), findsOneWidget);
    expect(find.text('Seu preço justo'), findsNothing);
  });
}
