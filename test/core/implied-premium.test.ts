// O prêmio de mercado é a média de dez anos do prêmio implícito (decisão 142).
//
// A série chega por pacote, e a média sai dela: os trimestres com fim em
// `(data − dez anos, data]`, com pelo menos vinte; o prêmio de cada trimestre é
// `r − Rf`, a forma que o CAPM do motor soma.
import { afterEach, describe, expect, it } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  CapmInputs,
  DateTime,
  FundamentalsSnapshot,
  ImpliedPremiumCodec,
  ImpliedPremiumPackage,
  ImpliedPremiumQuarter,
  MarketPremiumSource,
  Ticker,
  ValuationCascade,
  ValuationInputs,
} from '../../src/core';
import { day, expectClose, expectDate } from './helpers';

/** Trimestres de 2011 a 2026, com `r − Rf` igual a [premium] de cada um. */
function makePackage(premium: (d: DateTime) => number): ImpliedPremiumPackage {
  const q: ImpliedPremiumQuarter[] = [];
  for (let year = 2011; year <= 2026; year++) {
    for (const month of [3, 6, 9, 12]) {
      const d = DateTime.utc(year, month + 1, 0);
      if (d.isAfter(DateTime.utc(2026, 6, 30))) continue;
      q.push(new ImpliedPremiumQuarter({ date: d, impliedReturn: 0.13 + premium(d), riskFree: 0.13 }));
    }
  }
  return new ImpliedPremiumPackage({ generatedAt: DateTime.utc(2026, 9, 14), quarters: q });
}

afterEach(() => AuditRecorder.detach());

it('o prêmio do trimestre é r − Rf, e não a razão de Fisher', () => {
  const q = new ImpliedPremiumQuarter({ date: DateTime.utc(2026, 9, 14), impliedReturn: 0.1326, riskFree: 0.1438 });
  expectClose(q.premium, -0.0112, 1e-12);
});

it('a média é a dos trimestres em (data − dez anos, data]', () => {
  // Prêmio de 1% até 2016 e de 2% depois: em 14/09/2026 a janela começa no
  // trimestre de 30/09/2016, e tem 40 trimestres, 39 deles de 2%.
  const p = makePackage((d) => (d.year <= 2016 && d.month <= 6 ? 0.01 : 0.02));
  const window = p.window(day(2026, 9, 14));
  expect(window.length).toBe(40);
  expectDate(window[0]!.date, DateTime.utc(2016, 9, 30));
  expectDate(window[window.length - 1]!.date, DateTime.utc(2026, 6, 30));
  expectClose(p.normalizedAt(day(2026, 9, 14))!, 0.02, 1e-12);
});

it('a ponta final entra, e a inicial não', () => {
  const p = makePackage((d) => (d.equals(DateTime.utc(2016, 6, 30)) ? 1.0 : 0.0));
  // Em 30/06/2026 a janela é (30/06/2016, 30/06/2026]: o trimestre de
  // 30/06/2016 fica fora, e o de 30/06/2026 entra.
  expect(p.normalizedAt(day(2026, 6, 30))).toBe(0.0);
  const w = p.window(day(2026, 6, 30));
  expectDate(w[w.length - 1]!.date, DateTime.utc(2026, 6, 30));
  expect(p.normalizedAt(day(2026, 6, 29)), 'um dia antes, a janela ainda alcança 30/06/2016').toBeGreaterThan(0);
});

it('com menos de vinte trimestres não há média, e com vinte há', () => {
  const p = makePackage(() => 0.015);
  // A série começa em 31/03/2011: em 31/12/2015 há 20 trimestres.
  expect(p.window(day(2015, 12, 31)).length).toBe(20);
  expectClose(p.normalizedAt(day(2015, 12, 31))!, 0.015, 1e-12);
  expect(p.normalizedAt(day(2015, 9, 30))).toBeNull();
  // As coortes de 2018 usam os trimestres que havia: 29 em 31/03/2018.
  expect(p.window(day(2018, 3, 31)).length).toBe(29);
});

describe('codec', () => {
  it('ida e volta preservam a série', () => {
    const p = makePackage((d) => d.year / 100000);
    const parsed = ImpliedPremiumCodec.decode(ImpliedPremiumCodec.encode(p))!;
    expectDate(parsed.generatedAt, p.generatedAt);
    expect(parsed.quarters.length).toBe(p.quarters.length);
    expectClose(parsed.normalizedAt(day(2026, 9, 14))!, p.normalizedAt(day(2026, 9, 14))!, 1e-15);
  });

  it('recusa versão diferente, série vazia e número não finito', () => {
    const valid = ImpliedPremiumCodec.encode(makePackage(() => 0.01));
    expect(ImpliedPremiumCodec.decode({ ...valid, versao: 99 })).toBeNull();
    expect(ImpliedPremiumCodec.decode({ ...valid, trimestres: [] })).toBeNull();
    expect(ImpliedPremiumCodec.decode({ ...valid, geradoEm: 'ontem' })).toBeNull();
    expect(
      ImpliedPremiumCodec.decode({
        ...valid,
        trimestres: [{ data: '2020-03-31', retornoImplicito: Number.NaN, prefixado10: 0.1 }],
      }),
    ).toBeNull();
    expect(ImpliedPremiumCodec.decode({ ...valid, trimestres: [{ data: '2020-03-31', prefixado10: 0.1 }] })).toBeNull();
  });
});

it('o rastro do CAPM diz de onde veio o prêmio', () => {
  const captured: AuditEvent[] = [];
  AuditRecorder.attach((e) => captured.push(e));
  const ticker = Ticker.parse('PREM3');
  const cases: [MarketPremiumSource, string][] = [
    [MarketPremiumSource.impliedNormalized, 'média de dez anos do prêmio implícito'],
    [MarketPremiumSource.parameterized, 'o prêmio parametrizado'],
  ];
  for (const [origin, excerpt] of cases) {
    captured.length = 0;
    const fundamentals: FundamentalsSnapshot[] = [];
    for (let year = 2016; year <= 2025; year++) {
      const k = year - 2015;
      fundamentals.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          netIncome: 1000.0 * k,
          ebit: 1400.0 * k,
          ebitda: 1800.0 * k,
          incomeBeforeTax: 1300.0 * k,
          incomeTaxExpense: 300.0 * k,
          interestExpense: 120.0,
          operatingCashFlow: 1600.0 * k,
          freeCashFlow: 1200.0 * k,
          shortTermDebt: 400.0,
          longTermDebt: 1600.0,
          cash: 300.0,
          nopat: 1000.0 * k,
          sharesOutstanding: 1000.0,
          sharesOutstandingAsOf: 1000.0,
          marketCap: 20000.0,
          bookValuePerShare: 8.0 * k,
          enterpriseToEbitda: 6.0,
        }),
      );
    }
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 8, 20),
        fundamentals,
        marketPrice: 20.0,
        capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.0136, premiumSource: origin }),
        projectionYears: 5,
      }),
    );
    expect(captured).toHaveLength(1);
    const capm = captured[0]!.calculations.find((c) => c.formulaName.includes('CAPM'))!;
    expect(capm.mappedVariables['origem do prêmio']).toBe(origin.name);
    expect(capm.intermediateSteps[0]).toContain(excerpt);
  }
});
