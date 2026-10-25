// O aviso das contagens discordantes diz a contagem que a ponte usou
// (item B40).
//
// O texto dizia sempre «a ponte por papel usa a implícita no valor de
// mercado», e desde a decisão 83 o divisor pode ser a contagem oficial da B3:
// na SAPR11 o aviso nomeava as 103.850.066 do valor de mercado ao lado de uma
// ponte de 302.241.104.
import { expect, it } from 'vitest';

import {
  CapmInputs,
  FundamentalsSnapshot,
  OfficialShareCount,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  type ValuationResult,
} from '../../src/core';
import { day } from './helpers';

const ticker = Ticker.parse('CONT3');

/**
 * As duas contagens publicadas discordam por 3x: 1.000 correntes contra 3.000
 * do exercício. O valor de mercado, a R$ 10, implica 3.000.
 */
function year(y: number, e: number): FundamentalsSnapshot {
  return new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(y, 12, 31),
    totalRevenue: 10000 * e,
    ebit: 1400 * e,
    ebitda: 1900 * e,
    netIncome: 700 * e,
    incomeBeforeTax: 1000 * e,
    incomeTaxExpense: -300 * e,
    interestExpense: 120,
    earningsPerShare: (0.7 * e) / 3,
    cash: 500,
    shortTermDebt: 400,
    longTermDebt: 1600,
    totalStockholderEquity: 6000 * e,
    bookValuePerShare: 2.0 * e,
    nopat: 924 * e,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 3000,
    marketCap: 30000,
  });
}

function evaluate(official?: OfficialShareCount): ValuationResult {
  const fundamentals: FundamentalsSnapshot[] = [];
  for (let i = 15; i >= 0; i--) fundamentals.push(year(2025 - i, Math.pow(1.05, 15 - i)));
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 9, 9),
      fundamentals,
      marketPrice: 10.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
      declaredTerminalRiskFreeRate: 0.094,
      officialShares: official ?? null,
    }),
  );
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap();
}

function warning(v: ValuationResult): string {
  const found = v.warnings.filter((w) => w.includes('As duas contagens de ações'));
  expect(found).toHaveLength(1);
  return found[0]!;
}

it('com a contagem oficial adotada, o aviso nomeia a oficial', () => {
  const w = warning(evaluate(new OfficialShareCount({ total: 3000, asOf: day(2026, 9, 1) })));
  expect(w).toContain('contagem oficial da B3');
  expect(w).not.toContain('implícita no valor de mercado');
  expect(w).toContain('3000 papéis');
});

it('sem a oficial, o aviso nomeia a que a ponte usou', () => {
  const w = warning(evaluate());
  expect(w).toContain('a ponte por papel usa a implícita no valor');
  expect(w).toContain('3000 papéis');
});
