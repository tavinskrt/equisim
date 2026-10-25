// O aviso do custo da dívida descreve a regra que a conta aplica (item B32).
//
// Até 27/09/2026 ele dizia a regra de antes das decisões 31 e 130: o observado
// «fora da faixa defensável» e o adotado «por alavancagem», mesmo com o
// observado dentro da faixa e o prêmio vindo da cobertura.
import { expect, it } from 'vitest';

import { CapmInputs, FundamentalsSnapshot, Ticker, ValuationCascade, ValuationInputs } from '../../src/core';
import { day } from './helpers';

const ticker = Ticker.parse('ABCD3');

/**
 * Dívida bruta de 4.000 e EBIT de 1.800 no primeiro exercício, crescendo 5%
 * ao ano; [interest] é a despesa financeira, constante.
 */
function series(interest: number): FundamentalsSnapshot[] {
  const out: FundamentalsSnapshot[] = [];
  let e = 1.0;
  for (let i = 12; i >= 0; i--) {
    out.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(2025 - i, 12, 31),
        totalRevenue: 10000 * e,
        ebit: 1800 * e,
        ebitda: 2400 * e,
        netIncome: 900 * e,
        incomeBeforeTax: 1300 * e,
        incomeTaxExpense: -400 * e,
        interestExpense: interest,
        earningsPerShare: 0.9 * e,
        cash: 200,
        shortTermDebt: 1000,
        longTermDebt: 3000,
        totalStockholderEquity: 6000 * e,
        bookValuePerShare: 6.0 * e,
        operatingCashFlow: 2000 * e,
        nopat: 1188 * e,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 12000,
      }),
    );
    e *= 1.05;
  }
  return out;
}

function warning(interest: number): string | null {
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 9, 9),
      fundamentals: series(interest),
      marketPrice: 12.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
      declaredTerminalRiskFreeRate: 0.094,
    }),
  );
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  const warnings = r.unwrap().warnings.filter((w) => w.startsWith('O custo da dívida implícito'));
  if (warnings.length === 0) return null;
  expect(warnings).toHaveLength(1);
  return warnings[0]!;
}

it('observado dentro da faixa: a cobertura fala, e o aviso diz que o prêmio veio dela', () => {
  // 960 ÷ 4.000 = 24%, dentro de [14%, 24%]; a cobertura de 3,4x dá 2,4
  // p.p., e a alavancagem de 0,9x, 1,3 p.p.
  const w = warning(960)!;
  expect(w).toContain('deu 24.0% a.a., e o adotado é 16.4% a.a.');
  expect(w).toContain('dentro da faixa defensável de 14.0% a 24.0%');
  expect(w).toContain('o da cobertura, de 2.4%');
  expect(w).not.toContain('fora da faixa');
});

it('observado fora da faixa: a cobertura sai, e o prêmio é o da alavancagem', () => {
  // 400 ÷ 4.000 = 10%, abaixo da taxa livre de risco.
  const w = warning(400)!;
  expect(w).toContain('deu 10.0% a.a., e o adotado é 15.3% a.a.');
  expect(w).toContain('fora da faixa defensável de 14.0% a 24.0%');
  expect(w).toContain('prêmio é o da alavancagem de 0.88x');
  expect(w).toContain('de 1.3%');
});

it('observado perto do adotado não gera aviso', () => {
  // 16,4% observado contra 16,4% adotado.
  expect(warning(656)).toBeNull();
});
