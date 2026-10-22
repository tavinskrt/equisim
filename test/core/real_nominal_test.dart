import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Item B7 — a convenção de inflação é a mesma nas três pontas.
///
/// **O que se cobra aqui.** O motor desconta fluxo **nominal** a taxa
/// **nominal**, e usa o IPCA em dois lugares: no teto da perpetuidade e na
/// âncora da Saída 2. Nunca foi conferido que as duas pontas falam a mesma
/// língua no caminho inteiro.
///
/// **A prova é de invariância de unidade.** Valor presente é quantia de hoje, e
/// não muda quando a conta é reexpressa em moeda constante. Cada premissa vira
/// a sua versão real por Fisher — `(1+x)/(1+π) − 1` —, e o preço justo tem de
/// ficar onde estava. Onde ele não fica, há premissa que só vale numa unidade,
/// e este arquivo mede **cada uma em forma fechada**, em vez de aceitar uma
/// tolerância frouxa.
void main() {
  /// A única conversão aceita no projeto. A subtração erra quase meio ponto
  /// percentual com a inflação brasileira.
  double real(double nominal, double pi) => (1 + nominal) / (1 + pi) - 1;

  const pi = 0.045;

  DcfOutcome evaluate({
    required double g,
    required double gInf,
    required double r,
    required double rInf,
    bool inConstantCurrency = false,
    CashTiming timing = CashTiming.endOfYear,
    ReinvestmentPolicy policy = ReinvestmentPolicy.none,
    double roic = 0.0,
  }) {
    double u(double x) => inConstantCurrency ? real(x, pi) : x;
    return DcfCalculator.shareholder(
      baseProfit: 100,
      assumptions: DcfAssumptions(
        growthRate: u(g),
        perpetualGrowth: u(gInf),
        discountRate: u(r),
        terminalDiscountRate: u(rInf),
        returnOnCapital: u(roic),
        reinvestmentPolicy: policy,
        cashTiming: timing,
      ),
    ).unwrap();
  }

  double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);

  group('O caminho explícito é neutro à unidade', () {
    test('com caixa no fim do ano, a igualdade é exata', () {
      // Π(1+g_t) ÷ Π(1+r_t) não muda quando numerador e denominador são
      // deflacionados pelo mesmo (1+π): é a invariância que o desconto tem de
      // ter, e ela vale ao último dígito.
      final nominal = evaluate(g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385);
      final constant = evaluate(
        g: 0.12,
        gInf: 0.0652,
        r: 0.162,
        rInf: 0.1385,
        inConstantCurrency: true,
      );
      expect(sum(constant.discountedFlows) / sum(nominal.discountedFlows),
          closeTo(1.0, 1e-12));
    });

    test('o decaimento linear das duas taxas sobrevive a Fisher', () {
      // **Não era óbvio.** `g_t` e `r_t` são interpolações **lineares** entre
      // dois pontos, e Fisher não é linear. A conta fecha porque a interpolação
      // linear entre dois fatores brutos equivale à dos fatores deflacionados:
      // `1 + g'_t = (1 + g_t) ÷ (1 + π)` para todo `t`.
      final flat = evaluate(g: 0.08, gInf: 0.08, r: 0.15, rInf: 0.15);
      final flatReal = evaluate(
        g: 0.08,
        gInf: 0.08,
        r: 0.15,
        rInf: 0.15,
        inConstantCurrency: true,
      );
      final withDecay =
          evaluate(g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385);
      final withRealDecay = evaluate(
        g: 0.12,
        gInf: 0.0652,
        r: 0.162,
        rInf: 0.1385,
        inConstantCurrency: true,
      );
      final withoutDecay =
          sum(flatReal.discountedFlows) / sum(flat.discountedFlows);
      final withInput = sum(withRealDecay.discountedFlows) /
          sum(withDecay.discountedFlows);
      expect(withInput, closeTo(withoutDecay, 1e-12),
          reason: 'o decaimento não acrescenta desvio nenhum');
    });

    test('a subtração no lugar de Fisher quebra a igualdade, e por muito', () {
      // A guarda dos testes acima: sem ela, eles não provariam nada.
      final nominal = evaluate(g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385);
      final wrong = DcfCalculator.shareholder(
        baseProfit: 100,
        assumptions: const DcfAssumptions(
          growthRate: 0.12 - pi,
          perpetualGrowth: 0.0652 - pi,
          discountRate: 0.162 - pi,
          terminalDiscountRate: 0.1385 - pi,
          reinvestmentPolicy: ReinvestmentPolicy.none,
        ),
      ).unwrap();
      final deviation =
          (wrong.fairValuePerShare / nominal.fairValuePerShare - 1).abs();
      expect(deviation, greaterThan(0.05));
    });
  });

  group('Onde a unidade não é neutra, e quanto vale cada caso', () {
    test('o caixa no meio do ano custa exatamente meia inflação', () {
      // A convenção de meio de ano levanta o fluxo por `(1+r)^0,5`, o que põe o
      // fluxo do ano `t` no poder de compra do **fim** do ano `t`. O desvio é a
      // meia inflação que sobra: `(1+π)^−0,5`. Exato, e é o menor dos três.
      final nominal = evaluate(
        g: 0.12,
        gInf: 0.0652,
        r: 0.162,
        rInf: 0.1385,
        timing: CashTiming.midYear,
      );
      final constant = evaluate(
        g: 0.12,
        gInf: 0.0652,
        r: 0.162,
        rInf: 0.1385,
        timing: CashTiming.midYear,
        inConstantCurrency: true,
      );
      expect(sum(constant.discountedFlows) / sum(nominal.discountedFlows),
          closeTo(1 / math.sqrt(1 + pi), 1e-12),
          reason: 'meia inflação, e nada mais');
    });

    test('o terminal neutro vale r ÷ (r − π), e é o caso grande', () {
      // `VT = lucro_{N+1} ÷ r` capitaliza pela taxa **líquida**, e taxa líquida
      // não deflaciona por Fisher: `r' = (r − π)/(1 + π)`, de modo que
      // `r ÷ ((1+π)·r') = r ÷ (r − π)`.
      for (final rInf in [0.1385, 0.15, 0.20]) {
        final nominal = evaluate(g: 0.08, gInf: 0.0652, r: rInf, rInf: rInf);
        final constant = evaluate(
          g: 0.08,
          gInf: 0.0652,
          r: rInf,
          rInf: rInf,
          inConstantCurrency: true,
        );
        expect(
          constant.discountedTerminalValue / nominal.discountedTerminalValue,
          closeTo(rInf / (rInf - pi), 1e-9),
          reason: 'r = $rInf',
        );
      }
    });

    test('os dois efeitos compõem, e nada mais aparece', () {
      // Se houvesse uma quarta fonte de desvio, este teste a pegaria: o
      // terminal com caixa no meio do ano tem de ser exatamente o produto dos
      // dois fatores já nomeados.
      const rInf = 0.1385;
      final nominal = evaluate(
        g: 0.12,
        gInf: 0.0652,
        r: 0.162,
        rInf: rInf,
        timing: CashTiming.midYear,
      );
      final constant = evaluate(
        g: 0.12,
        gInf: 0.0652,
        r: 0.162,
        rInf: rInf,
        timing: CashTiming.midYear,
        inConstantCurrency: true,
      );
      expect(
        constant.discountedTerminalValue / nominal.discountedTerminalValue,
        closeTo(rInf / (rInf - pi) / math.sqrt(1 + pi), 1e-9),
      );
    });

    test('o freio é nominal porque a identidade g = b·ROIC é nominal', () {
      // **É a raiz dos dois casos acima.** A retenção é `b = g ÷ ROIC`, e a
      // identidade `g = b·ROIC` vale entre grandezas **nominais**: reter `b` do
      // lucro e aplicá-lo a um `ROIC` nominal faz o lucro **nominal** crescer
      // `b·ROIC`. Em termos reais a mesma fórmula dá outro `b`, e o que ela dá
      // está **errado** — não é o motor que é nominal por descuido, é a
      // identidade.
      const roic = 0.20;
      const g = 0.08;
      final nominal = evaluate(
        g: g,
        gInf: 0.0652,
        r: 0.15,
        rInf: 0.15,
        policy: ReinvestmentPolicy.measured,
        roic: roic,
      );
      final constant = evaluate(
        g: g,
        gInf: 0.0652,
        r: 0.15,
        rInf: 0.15,
        policy: ReinvestmentPolicy.measured,
        roic: roic,
        inConstantCurrency: true,
      );
      const bNominal = g / roic;
      final bReal = real(g, pi) / real(roic, pi);
      expect(bReal, lessThan(bNominal),
          reason: 'crescer em termos reais parece exigir menos retenção — e é '
              'justamente a conta que não vale');
      expect(constant.fairValuePerShare,
          isNot(closeTo(nominal.fairValuePerShare, 1e-6)));
    });
  });

  group('O teto da perpetuidade é nominal, e por composição', () {
    test('o teto é (1 + real)(1 + π) − 1, e não a soma', () {
      const anchors = MarketAnchors.fallback2026;
      expect(
        anchors.nominalEconomyGrowth,
        closeTo(
          (1 + anchors.realEconomyGrowth) * (1 + anchors.inflationCagr) - 1,
          1e-15,
        ),
      );
      expect(
        anchors.nominalEconomyGrowth,
        isNot(closeTo(anchors.realEconomyGrowth + anchors.inflationCagr, 1e-9)),
      );
    });

    test('o teto e o desconto estão na mesma unidade', () {
      // Um teto **real** contra um desconto **nominal** faria o spread
      // `r − g∞` ser nominal menos real, e o terminal sairia de outro modelo.
      const anchors = MarketAnchors.fallback2026;
      final withNominalCap = evaluate(
        g: 0.12,
        gInf: anchors.nominalEconomyGrowth,
        r: 0.162,
        rInf: 0.1385,
      );
      final withRealCap = evaluate(
        g: 0.12,
        gInf: anchors.realEconomyGrowth,
        r: 0.162,
        rInf: 0.1385,
      );
      expect(withRealCap.fairValuePerShare,
          isNot(closeTo(withNominalCap.fairValuePerShare, 1e-6)),
          reason: 'os dois não são intercambiáveis, e o nominal é o correto');
    });

    test('o recuo da cascata é o teto nominal, e fica acima da inflação', () {
      final inputs = ValuationInputs(
        ticker: Ticker.parse('PETR4'),
        asOf: DateTime(2026, 9, 21),
        fundamentals: const [],
        marketPrice: 10.0,
        capm: const CapmInputs(
            riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
      );
      expect(inputs.perpetualGrowthCap,
          closeTo((1 + 0.0145) * (1 + 0.05) - 1, 5e-5),
          reason: 'composição de 1,45% real com 5,0% de IPCA');
      expect(inputs.perpetualGrowthCap, greaterThan(inputs.inflation),
          reason: 'teto nominal acima da própria inflação: o real é positivo');
    });
  });

  group('A âncora da Saída 2 é crescimento real zero', () {
    test('adotar a inflação como crescimento afirma real zero, por Fisher', () {
      expect(real(pi, pi), closeTo(0.0, 1e-15));
    });

    test('o freio em crescimento real deflaciona por Fisher, e não por menos',
        () {
      const roic = 0.20;
      const nominalAs = DcfAssumptions(
        growthRate: 0.08,
        perpetualGrowth: 0.0652,
        discountRate: 0.15,
        returnOnCapital: roic,
        reinvestmentPolicy: ReinvestmentPolicy.measured,
      );
      final realAs = nominalAs.copyWith(
        reinvestmentPolicy: ReinvestmentPolicy.realGrowth,
        inflation: pi,
      );
      final g1 = nominalAs.growthAt(1);
      expect(nominalAs.retentionAt(1), closeTo(g1 / roic, 1e-12));
      expect(realAs.retentionAt(1), closeTo(real(g1, pi) / roic, 1e-12),
          reason: 'Fisher, e não `g − π`');
      expect(realAs.retentionAt(1), lessThan(nominalAs.retentionAt(1)));
    });
  });
}
