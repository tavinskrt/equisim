import { expect, it } from 'vitest';

import {
  CashDividend,
  CashDividendKind,
  DateTime,
  FundamentalsSnapshot,
  PrepareValuationInputs,
  PricePoint,
  PriceSeries,
  Ticker,
  type ValuationInputs,
} from '../../src/core';
import { FixedFundamentals, FixedIndex, FixedPrices, tradingDays } from './fakes';
import { day, expectClose } from './helpers';

const ticker = Ticker.parse('TAEE3');

it('com os proventos da B3, o beta sai do retorno total — decisão 89', async () => {
  // O ativo anda exatamente com o índice, e paga 4% nos dias de alta forte.
  // Pelo fechamento, a queda da data ex coincide com a alta do mercado e
  // derruba o beta; pelo retorno total, ele é 1.
  const days = tradingDays(day(2021, 1, 4), day(2025, 12, 30));
  const market = [1000];
  const asset = [50];
  const dividends: CashDividend[] = [];
  for (let i = 1; i < days.length; i++) {
    const m = 0.012 * Math.sin(i * 0.7) + 0.004 * Math.cos(i * 1.3);
    market.push(market[i - 1]! * (1 + m));
    const ex = m > 0.013 && i % 3 === 0;
    if (ex) {
      const d = asset[i - 1]! * 0.04;
      const before = days[i - 1]!;
      const at = days[i]!;
      dividends.push(
        new CashDividend({
          shareClass: 'ON',
          kind: CashDividendKind.dividend,
          lastDateWithRights: DateTime.utc(before.year, before.month, before.day),
          exDate: DateTime.utc(at.year, at.month, at.day),
          amount: d,
          closeWithRights: asset[i - 1]!,
        }),
      );
      asset.push(asset[i - 1]! * (1 + m) - d);
    } else {
      asset.push(asset[i - 1]! * (1 + m));
    }
  }
  expect(dividends.length, 'o cenário precisa de datas ex suficientes para medir algo').toBeGreaterThan(20);

  const series = (v: number[]): PriceSeries =>
    new PriceSeries({ ticker, points: days.map((d, i) => new PricePoint({ date: d, close: v[i]! })) });

  const fundamentals = new FixedFundamentals(
    (t) => [new FundamentalsSnapshot({ ticker: t, fiscalPeriodEnd: day(2024, 12, 31), netIncome: 10 })],
    [ticker],
  );

  const prepare = async (d: CashDividend[] | null): Promise<ValuationInputs> =>
    (
      await PrepareValuationInputs.call({
        ticker,
        prices: new FixedPrices(series(asset)),
        fundamentals,
        benchmark: new FixedIndex(series(market)),
        riskFreeRate: 0.1,
        asOf: day(2025, 12, 31),
        dividends: d,
      })
    ).unwrap();

  const price = await prepare(null);
  const total = await prepare(dividends);

  expectClose(total.capm.beta, 1.0, 1e-9);
  expect(total.dividendsInBeta).toBe(dividends.length);
  expect(price.dividendsInBeta).toBe(0);
  expect(price.capm.beta, 'pelo fechamento, a data ex entra como risco').toBeLessThan(0.99);
});
