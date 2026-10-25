import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  CashTiming,
  DcfAssumptions,
  DcfCalculator,
  type DcfOutcome,
  MarketAnchors,
  ReinvestmentPolicy,
  Ticker,
  ValuationInputs,
} from '../../src/core';
import { day, expectClose, expectNotClose } from './helpers';

/**
 * Item B7 — a convenção de inflação é a mesma nas três pontas.
 *
 * **O que se cobra aqui.** O motor desconta fluxo **nominal** a taxa
 * **nominal**, e usa o IPCA em dois lugares: no teto da perpetuidade e na
 * âncora da Saída 2. Nunca foi conferido que as duas pontas falam a mesma
 * língua no caminho inteiro.
 *
 * **A prova é de invariância de unidade.** Valor presente é quantia de hoje, e
 * não muda quando a conta é reexpressa em moeda constante. Cada premissa vira
 * a sua versão real por Fisher — `(1+x)/(1+π) − 1` —, e o preço justo tem de
 * ficar onde estava. Onde ele não fica, há premissa que só vale numa unidade,
 * e este arquivo mede **cada uma em forma fechada**, em vez de aceitar uma
 * tolerância frouxa.
 */

/**
 * A única conversão aceita no projeto. A subtração erra quase meio ponto
 * percentual com a inflação brasileira.
 */
const real = (nominal: number, pi: number): number => (1 + nominal) / (1 + pi) - 1;

const pi = 0.045;

const evaluate = (o: {
  g: number;
  gInf: number;
  r: number;
  rInf: number;
  inConstantCurrency?: boolean;
  timing?: CashTiming;
  policy?: ReinvestmentPolicy;
  roic?: number;
}): DcfOutcome => {
  const u = (x: number): number => (o.inConstantCurrency === true ? real(x, pi) : x);
  return DcfCalculator.shareholder({
    baseProfit: 100,
    assumptions: new DcfAssumptions({
      growthRate: u(o.g),
      perpetualGrowth: u(o.gInf),
      discountRate: u(o.r),
      terminalDiscountRate: u(o.rInf),
      returnOnCapital: u(o.roic ?? 0.0),
      reinvestmentPolicy: o.policy ?? ReinvestmentPolicy.none,
      cashTiming: o.timing ?? CashTiming.endOfYear,
    }),
  }).unwrap();
};

const sum = (v: readonly number[]): number => v.reduce((a, b) => a + b, 0.0);

describe('O caminho explícito é neutro à unidade', () => {
  it('com caixa no fim do ano, a igualdade é exata', () => {
    // Π(1+g_t) ÷ Π(1+r_t) não muda quando numerador e denominador são
    // deflacionados pelo mesmo (1+π): é a invariância que o desconto tem de
    // ter, e ela vale ao último dígito.
    const nominal = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385 });
    const constant = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385, inConstantCurrency: true });
    expectClose(sum(constant.discountedFlows) / sum(nominal.discountedFlows), 1.0, 1e-12);
  });

  it('o decaimento linear das duas taxas sobrevive a Fisher', () => {
    // **Não era óbvio.** `g_t` e `r_t` são interpolações **lineares** entre
    // dois pontos, e Fisher não é linear. A conta fecha porque a interpolação
    // linear entre dois fatores brutos equivale à dos fatores deflacionados:
    // `1 + g'_t = (1 + g_t) ÷ (1 + π)` para todo `t`.
    const flat = evaluate({ g: 0.08, gInf: 0.08, r: 0.15, rInf: 0.15 });
    const flatReal = evaluate({ g: 0.08, gInf: 0.08, r: 0.15, rInf: 0.15, inConstantCurrency: true });
    const withDecay = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385 });
    const withRealDecay = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385, inConstantCurrency: true });
    const withoutDecay = sum(flatReal.discountedFlows) / sum(flat.discountedFlows);
    const withInput = sum(withRealDecay.discountedFlows) / sum(withDecay.discountedFlows);
    expectClose(withInput, withoutDecay, 1e-12, 'o decaimento não acrescenta desvio nenhum');
  });

  it('a subtração no lugar de Fisher quebra a igualdade, e por muito', () => {
    // A guarda dos testes acima: sem ela, eles não provariam nada.
    const nominal = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385 });
    const wrong = DcfCalculator.shareholder({
      baseProfit: 100,
      assumptions: new DcfAssumptions({
        growthRate: 0.12 - pi,
        perpetualGrowth: 0.0652 - pi,
        discountRate: 0.162 - pi,
        terminalDiscountRate: 0.1385 - pi,
        reinvestmentPolicy: ReinvestmentPolicy.none,
      }),
    }).unwrap();
    const deviation = Math.abs(wrong.fairValuePerShare / nominal.fairValuePerShare - 1);
    expect(deviation).toBeGreaterThan(0.05);
  });
});

describe('Onde a unidade não é neutra, e quanto vale cada caso', () => {
  it('o caixa no meio do ano custa exatamente meia inflação', () => {
    // A convenção de meio de ano levanta o fluxo por `(1+r)^0,5`, o que põe o
    // fluxo do ano `t` no poder de compra do **fim** do ano `t`. O desvio é a
    // meia inflação que sobra: `(1+π)^−0,5`. Exato, e é o menor dos três.
    const nominal = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf: 0.1385, timing: CashTiming.midYear });
    const constant = evaluate({
      g: 0.12,
      gInf: 0.0652,
      r: 0.162,
      rInf: 0.1385,
      timing: CashTiming.midYear,
      inConstantCurrency: true,
    });
    expectClose(
      sum(constant.discountedFlows) / sum(nominal.discountedFlows),
      1 / Math.sqrt(1 + pi),
      1e-12,
      'meia inflação, e nada mais',
    );
  });

  it('o terminal neutro vale r ÷ (r − π), e é o caso grande', () => {
    // `VT = lucro_{N+1} ÷ r` capitaliza pela taxa **líquida**, e taxa líquida
    // não deflaciona por Fisher: `r' = (r − π)/(1 + π)`, de modo que
    // `r ÷ ((1+π)·r') = r ÷ (r − π)`.
    for (const rInf of [0.1385, 0.15, 0.2]) {
      const nominal = evaluate({ g: 0.08, gInf: 0.0652, r: rInf, rInf });
      const constant = evaluate({ g: 0.08, gInf: 0.0652, r: rInf, rInf, inConstantCurrency: true });
      expectClose(
        constant.discountedTerminalValue / nominal.discountedTerminalValue,
        rInf / (rInf - pi),
        1e-9,
        `r = ${rInf}`,
      );
    }
  });

  it('os dois efeitos compõem, e nada mais aparece', () => {
    // Se houvesse uma quarta fonte de desvio, este teste a pegaria: o
    // terminal com caixa no meio do ano tem de ser exatamente o produto dos
    // dois fatores já nomeados.
    const rInf = 0.1385;
    const nominal = evaluate({ g: 0.12, gInf: 0.0652, r: 0.162, rInf, timing: CashTiming.midYear });
    const constant = evaluate({
      g: 0.12,
      gInf: 0.0652,
      r: 0.162,
      rInf,
      timing: CashTiming.midYear,
      inConstantCurrency: true,
    });
    expectClose(
      constant.discountedTerminalValue / nominal.discountedTerminalValue,
      rInf / (rInf - pi) / Math.sqrt(1 + pi),
      1e-9,
    );
  });

  it('o freio é nominal porque a identidade g = b·ROIC é nominal', () => {
    // **É a raiz dos dois casos acima.** A retenção é `b = g ÷ ROIC`, e a
    // identidade `g = b·ROIC` vale entre grandezas **nominais**: reter `b` do
    // lucro e aplicá-lo a um `ROIC` nominal faz o lucro **nominal** crescer
    // `b·ROIC`. Em termos reais a mesma fórmula dá outro `b`, e o que ela dá
    // está **errado** — não é o motor que é nominal por descuido, é a
    // identidade.
    const roic = 0.2;
    const g = 0.08;
    const nominal = evaluate({ g, gInf: 0.0652, r: 0.15, rInf: 0.15, policy: ReinvestmentPolicy.measured, roic });
    const constant = evaluate({
      g,
      gInf: 0.0652,
      r: 0.15,
      rInf: 0.15,
      policy: ReinvestmentPolicy.measured,
      roic,
      inConstantCurrency: true,
    });
    const bNominal = g / roic;
    const bReal = real(g, pi) / real(roic, pi);
    expect(
      bReal < bNominal,
      'crescer em termos reais parece exigir menos retenção — e é justamente a conta que não vale',
    ).toBe(true);
    expectNotClose(constant.fairValuePerShare, nominal.fairValuePerShare, 1e-6);
  });
});

describe('O teto da perpetuidade é nominal, e por composição', () => {
  it('o teto é (1 + real)(1 + π) − 1, e não a soma', () => {
    const anchors = MarketAnchors.fallback2026;
    expectClose(
      anchors.nominalEconomyGrowth,
      (1 + anchors.realEconomyGrowth) * (1 + anchors.inflationCagr) - 1,
      1e-15,
    );
    expectNotClose(anchors.nominalEconomyGrowth, anchors.realEconomyGrowth + anchors.inflationCagr, 1e-9);
  });

  it('o teto e o desconto estão na mesma unidade', () => {
    // Um teto **real** contra um desconto **nominal** faria o spread
    // `r − g∞` ser nominal menos real, e o terminal sairia de outro modelo.
    const anchors = MarketAnchors.fallback2026;
    const withNominalCap = evaluate({ g: 0.12, gInf: anchors.nominalEconomyGrowth, r: 0.162, rInf: 0.1385 });
    const withRealCap = evaluate({ g: 0.12, gInf: anchors.realEconomyGrowth, r: 0.162, rInf: 0.1385 });
    expectNotClose(
      withRealCap.fairValuePerShare,
      withNominalCap.fairValuePerShare,
      1e-6,
      'os dois não são intercambiáveis, e o nominal é o correto',
    );
  });

  it('o recuo da cascata é o teto nominal, e fica acima da inflação', () => {
    const inputs = new ValuationInputs({
      ticker: Ticker.parse('PETR4'),
      asOf: day(2026, 9, 21),
      fundamentals: [],
      marketPrice: 10.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
    });
    expectClose(inputs.perpetualGrowthCap, (1 + 0.0145) * (1 + 0.05) - 1, 5e-5, 'composição de 1,45% real com 5,0% de IPCA');
    expect(
      inputs.perpetualGrowthCap > inputs.inflation,
      'teto nominal acima da própria inflação: o real é positivo',
    ).toBe(true);
  });
});

describe('A âncora da Saída 2 é crescimento real zero', () => {
  it('adotar a inflação como crescimento afirma real zero, por Fisher', () => {
    expectClose(real(pi, pi), 0.0, 1e-15);
  });

  it('o freio em crescimento real deflaciona por Fisher, e não por menos', () => {
    const roic = 0.2;
    const nominalAs = new DcfAssumptions({
      growthRate: 0.08,
      perpetualGrowth: 0.0652,
      discountRate: 0.15,
      returnOnCapital: roic,
      reinvestmentPolicy: ReinvestmentPolicy.measured,
    });
    const realAs = nominalAs.copyWith({ reinvestmentPolicy: ReinvestmentPolicy.realGrowth, inflation: pi });
    const g1 = nominalAs.growthAt(1);
    expectClose(nominalAs.retentionAt(1), g1 / roic, 1e-12);
    expectClose(realAs.retentionAt(1), real(g1, pi) / roic, 1e-12, 'Fisher, e não `g − π`');
    expect(realAs.retentionAt(1)).toBeLessThan(nominalAs.retentionAt(1));
  });
});
