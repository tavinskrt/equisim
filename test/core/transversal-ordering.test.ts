import { describe, expect, it } from 'vitest';

import {
  Asset,
  CapmInputs,
  ExpectedReturn,
  FundamentalsSnapshot,
  Money,
  Portfolio,
  PortfolioKind,
  Sector,
  Ticker,
  TransversalOrdering,
  TransversalScore,
  TransversalSignals,
  ValuationDiagnostics,
  ValuationModel,
  ValuationResult,
} from '../../src/core';
import { day, expectClose } from './helpers';

/** A ordenação transversal que decide o prêmio do retorno esperado (item B1). */

const m = <K, V>(entries: [K, V][]): Map<K, V> => new Map(entries);

describe('Escore robusto', () => {
  it('(x − mediana) ÷ MAD escalado, confinado a ±2', () => {
    // Mediana 3; desvios 2, 1, 0, 1, 97 → MAD 1 → escala 1,4826.
    const z = TransversalScore.robustZ(
      m([
        ['a', 1.0],
        ['b', 2.0],
        ['c', 3.0],
        ['d', 4.0],
        ['e', 100.0],
      ]),
    );
    expectClose(z.get('a')!, -2 / 1.4826, 1e-12);
    expect(z.get('c')).toBe(0.0);
    expectClose(z.get('d')!, 1 / 1.4826, 1e-12);
    expect(z.get('e'), 'a cauda é confinada, e não decide sozinha').toBe(2.0);
  });

  it('seção sem escala dá zero a todos, e valor não finito sai', () => {
    expect(
      TransversalScore.robustZ(
        m([
          ['a', 1.0],
          ['b', 2.0],
        ]),
      ),
    ).toEqual(
      m([
        ['a', 0.0],
        ['b', 0.0],
      ]),
    );
    expect(
      TransversalScore.robustZ(
        m([
          ['a', 5.0],
          ['b', 5.0],
          ['c', 5.0],
          ['d', 5.0],
        ]),
      ),
    ).toEqual(
      m([
        ['a', 0.0],
        ['b', 0.0],
        ['c', 0.0],
        ['d', 0.0],
      ]),
    );
    expect(
      TransversalScore.robustZ(
        m([
          ['a', Number.NaN],
          ['b', 1.0],
        ]),
      ).has('a'),
    ).toBe(false);
  });
});

describe('Ordenações', () => {
  const signals = m<string, TransversalSignals>([
    ['A', new TransversalSignals({ potential: -0.5, bookToMarket: 0.2, earningsYield: 0.02 })],
    ['B', new TransversalSignals({ potential: 0.1, bookToMarket: 0.6, earningsYield: 0.08 })],
    ['C', new TransversalSignals({ potential: 0.4, bookToMarket: 1.4, earningsYield: 0.15 })],
    ['D', new TransversalSignals({ potential: 0.0, bookToMarket: null, earningsYield: 0.05 })],
  ]);
  const bmSection = m([
    ['A', 0.2],
    ['B', 0.6],
    ['C', 1.4],
  ]);

  it('a de um sinal só é o escore dele, e quem não tem o sinal fica fora', () => {
    const bm = TransversalScore.scores(signals, TransversalOrdering.bookToMarket);
    expect([...bm.keys()].sort()).toEqual(['A', 'B', 'C']);
    expect(bm).toEqual(TransversalScore.robustZ(bmSection));
    const upsides = TransversalScore.scores(signals, TransversalOrdering.potential);
    expect([...upsides.keys()].sort()).toEqual(['A', 'B', 'C', 'D']);
  });

  it('o composto é a média dos escores que o ativo tem, com pesos iguais', () => {
    const comp = TransversalScore.scores(signals, TransversalOrdering.composite);
    const zP = TransversalScore.robustZ(new Map([...signals].map(([k, v]) => [k, v.potential!])));
    const zB = TransversalScore.robustZ(bmSection);
    const zE = TransversalScore.robustZ(new Map([...signals].map(([k, v]) => [k, v.earningsYield!])));
    expectClose(comp.get('B')!, (zP.get('B')! + zB.get('B')! + zE.get('B')!) / 3, 1e-12);
    // Sem book-to-market, a média é dos dois que ele tem.
    expectClose(comp.get('D')!, (zP.get('D')! + zE.get('D')!) / 2, 1e-12);
  });

  it('os sinais saem do último exercício, pela conta das coortes', () => {
    const petr = Ticker.parse('PETR4');
    const s = TransversalSignals.of(
      new FundamentalsSnapshot({
        ticker: petr,
        fiscalPeriodEnd: day(2025, 12, 31),
        marketCap: 1000,
        bookValuePerShare: 4,
        sharesOutstandingAsOf: 100,
        netIncome: 80,
      }),
      { potential: -0.2 },
    );
    expect(s.potential).toBe(-0.2);
    expectClose(s.bookToMarket!, 0.4, 1e-12);
    expectClose(s.earningsYield!, 0.08, 1e-12);
    const withoutMarketValue = TransversalSignals.of(
      new FundamentalsSnapshot({
        ticker: petr,
        fiscalPeriodEnd: day(2025, 12, 31),
        bookValuePerShare: 4,
        sharesOutstandingAsOf: 100,
        netIncome: 80,
      }),
    );
    expect(withoutMarketValue.bookToMarket).toBeNull();
    expect(withoutMarketValue.earningsYield).toBeNull();
    expect(TransversalSignals.of(null).bookToMarket).toBeNull();
  });

  it('da série, vale o último exercício publicado na data, e não o último', () => {
    const fiscalYear = (year: number, profit: number): FundamentalsSnapshot =>
      new FundamentalsSnapshot({
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: day(year, 12, 31),
        marketCap: 1000,
        bookValuePerShare: 4,
        sharesOutstandingAsOf: 100,
        netIncome: profit,
      });
    const series = [fiscalYear(2024, 50), fiscalYear(2025, 80)];
    // Em 30/01/2026 o exercício de 2025 ainda não foi publicado.
    const before = TransversalSignals.fromHistory(series, { asOf: day(2026, 1, 30) });
    const after = TransversalSignals.fromHistory(series, { asOf: day(2026, 9, 16) });
    expectClose(before.earningsYield!, 0.05, 1e-12);
    expectClose(after.earningsYield!, 0.08, 1e-12);
  });
});

describe('Retorno esperado com a ordenação medida', () => {
  const a = Ticker.parse('AAAA3');
  const b = Ticker.parse('BBBB3');
  const c = Ticker.parse('CCCC3');
  const valuation = (t: Ticker, ke: number, upside = 0): ValuationResult =>
    new ValuationResult({
      ticker: t,
      asOf: day(2026, 9, 16),
      model: ValuationModel.dcfFcff,
      fairValue: Money.fromReais(10 * (1 + upside)),
      marketPrice: Money.fromReais(10),
      discountRate: 0.13,
      diagnostics: new ValuationDiagnostics({
        terminalShare: 0.5,
        equityShare: 0.8,
        baseFactor: 1,
        growthIdentified: true,
        moatApplied: false,
        costOfEquity: ke,
        terminalDiscountRate: 0.12,
        terminalRetainedSpread: 0,
        growthRate: 0.05,
        returnOnCapital: 0.15,
      }),
    });
  const portfolioOf = (ts: Ticker[]): Portfolio =>
    Portfolio.equalWeighted({
      id: 'p',
      name: 'Principal',
      kind: PortfolioKind.principal,
      assets: ts.map((t) => new Asset({ ticker: t, name: t.value, sector: Sector.fromKey('energia', { label: 'energia' }) })),
    }).unwrap();
  const portfolio = portfolioOf([a, b, c]);
  const valuations = m([
    [a, valuation(a, 0.14, -0.3)],
    [b, valuation(b, 0.15, 0.0)],
    [c, valuation(c, 0.16, 0.3)],
  ]);

  it('sem ordenação não há prêmio: é a média dos Ke', () => {
    const r = ExpectedReturn.forPortfolioOrdered({
      portfolio,
      valuations,
      signals: new Map(),
      ordering: null,
      spotRiskFree: 0.14,
    });
    expectClose(r, (0.14 + 0.15 + 0.16) / 3, 1e-12);
  });

  it('com o book-to-market, quem é mais barato por ele espera mais', () => {
    const expected = (bmA: number): number =>
      ExpectedReturn.forPortfolioOrdered({
        portfolio: portfolioOf([a]),
        valuations,
        signals: m([
          [a, new TransversalSignals({ bookToMarket: bmA })],
          [b, new TransversalSignals({ bookToMarket: 0.5 })],
          [c, new TransversalSignals({ bookToMarket: 0.8 })],
        ]),
        ordering: TransversalOrdering.bookToMarket,
        spotRiskFree: 0.14,
      });
    // A seção é a da carteira; com um ativo só não há escala, e o prêmio é
    // zero — a leitura neutra.
    expectClose(expected(2.0), 0.14, 1e-12);

    const withThree = ExpectedReturn.forPortfolioOrdered({
      portfolio,
      valuations,
      signals: m([
        [a, new TransversalSignals({ bookToMarket: 2.0 })],
        [b, new TransversalSignals({ bookToMarket: 0.5 })],
        [c, new TransversalSignals({ bookToMarket: 0.8 })],
      ]),
      ordering: TransversalOrdering.bookToMarket,
      spotRiskFree: 0.14,
    });
    const z = TransversalScore.robustZ(
      m([
        [a, 2.0],
        [b, 0.5],
        [c, 0.8],
      ]),
    );
    const premium = CapmInputs.defaultMarketPremium;
    expectClose(
      withThree,
      (0.14 + z.get(a)! * premium + (0.15 + z.get(b)! * premium) + (0.16 + z.get(c)! * premium)) / 3,
      1e-12,
    );
  });

  it('ativo avaliado sem o sinal recebe a âncora, e não sai da conta', () => {
    const r = ExpectedReturn.forPortfolioOrdered({
      portfolio,
      valuations,
      signals: m([
        [a, new TransversalSignals({ bookToMarket: 2.0 })],
        [b, new TransversalSignals({ bookToMarket: 0.5 })],
      ]),
      ordering: TransversalOrdering.bookToMarket,
      spotRiskFree: 0.14,
    });
    // Dois com sinal: seção curta demais para escala, prêmio zero nos dois;
    // o terceiro, sem sinal, fica no Ke dele. A média é a dos três Ke.
    expectClose(r, (0.14 + 0.15 + 0.16) / 3, 1e-12);
  });
});
