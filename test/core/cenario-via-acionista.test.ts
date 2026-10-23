// O cenário de desconto alcança o período explícito na via do acionista com o
// custo de capital resolvido (item B36).
//
// O caminho de `Ke` resolvido ano a ano era copiado para o cenário sem o
// deslocamento, e o `+2 p.p.` do pessimista só chegava à perpetuidade: a AZEV4
// saía com o pessimista acima do otimista.
import { expect, it } from 'vitest';

import {
  CapmInputs,
  DiscreteScenarios,
  FundamentalsSnapshot,
  ScenarioBand,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
  type AssumptionSource,
  type DcfAssumptions,
} from '../../src/core';
import { day } from './helpers';

const ticker = Ticker.parse('ABCD3');

/**
 * Companhia não financeira cujo resultado operacional é negativo na maioria
 * dos exercícios — a Porta 3 a manda para a via do acionista —, e cujo lucro
 * líquido é positivo e cresce.
 */
function series(): FundamentalsSnapshot[] {
  const out: FundamentalsSnapshot[] = [];
  let e = 1.0;
  for (let i = 12; i >= 0; i--) {
    out.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(2025 - i, 12, 31),
        totalRevenue: 10000 * e,
        ebit: -200 * e,
        ebitda: 300 * e,
        netIncome: 900 * e,
        incomeBeforeTax: 1200 * e,
        incomeTaxExpense: -300 * e,
        interestExpense: 50,
        earningsPerShare: 0.9 * e,
        cash: 2000 * e,
        shortTermDebt: 500,
        longTermDebt: 500,
        totalStockholderEquity: 6000 * e,
        bookValuePerShare: 6.0 * e,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 12000,
      }),
    );
    // Crescimento que oscila em torno de 5%: série sem dispersão não deixa o
    // erro-padrão ser medido, e o motor recusa medir crescimento assim.
    e *= i % 2 === 0 ? 1.04 : 1.06;
  }
  return out;
}

function inputs(): ValuationInputs {
  return new ValuationInputs({
    ticker,
    asOf: day(2026, 9, 9),
    fundamentals: series(),
    marketPrice: 12.0,
    capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
    declaredTerminalRiskFreeRate: 0.1,
    // Com o beta desalavancado o `Ke` é resolvido ano a ano (decisão 46).
    unleveredBeta: 0.9,
  });
}

/** Só o desconto se move, e de dois jeitos: o cenário inteiro, e só a taxa de equilíbrio. */
const scenarios =
  () =>
  (c: DcfAssumptions): AssumptionSource =>
    new DiscreteScenarios(
      new Map([
        [
          ScenarioBand.bear,
          c.copyWith({ discountRate: c.discountRate + 0.02, terminalDiscountRate: c.terminalDiscountRate + 0.02 }),
        ],
        [ScenarioBand.base, c],
        [ScenarioBand.bull, c.copyWith({ terminalDiscountRate: c.terminalDiscountRate + 0.02 })],
      ]),
    );

it('a premissa: o ativo vai para a via do acionista, com Ke resolvido', () => {
  const r = ValuationCascade.evaluate(inputs());
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  expect(r.unwrap().model).toBe(ValuationModel.dcfEarnings);
  expect(r.unwrap().warnings.some((w) => w.includes('resolvido ano a ano'))).toBe(true);
});

it('deslocar o desconto inteiro pesa mais que deslocar só a perpetuidade', () => {
  const r = ValuationCascade.evaluate(inputs(), { scenarioBuilder: scenarios() }).unwrap();
  const whole = r.discreteScenarios!.get(ScenarioBand.bear)!.reais;
  const perpetuityOnly = r.discreteScenarios!.get(ScenarioBand.bull)!.reais;
  const base = r.discreteScenarios!.get(ScenarioBand.base)!.reais;
  expect(perpetuityOnly).toBeLessThan(base);
  expect(whole, 'o +2 p.p. do período explícito precisa chegar à conta').toBeLessThan(perpetuityOnly - 0.01);
});

it('o cenário base continua sendo o preço justo', () => {
  const r = ValuationCascade.evaluate(inputs()).unwrap();
  expect(r.discreteScenarios!.get(ScenarioBand.base)!.cents).toBe(r.fairValue.cents);
});
