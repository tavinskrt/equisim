import { describe, expect, it } from 'vitest';

import {
  DateRange,
  Duration,
  MarketAnchors,
  PricePoint,
  PriceSeries,
  RatePoint,
  RateSeries,
  ResolveMarketAnchors,
  Ticker,
  TimeBasis,
} from '../../src/core';
import { FixedIndex, FixedMacro } from './fakes';
import { day, expectClose } from './helpers';

const today = day(2026, 9, 4);

const rates = (n: number, v: number, basis: TimeBasis): RateSeries => {
  const points: RatePoint[] = [];
  for (let i = 0; i < n; i++) points.push(new RatePoint({ date: today.subtract(new Duration({ days: n - i })), rate: v }));
  return new RateSeries(points, { basis });
};

/**
 * Índice que cresce a [perYear] composto, com ruído multiplicando as pontas.
 *
 * Os pontos ficam a **um dia de calendário** um do outro, e por isso a
 * composição usa 365,25 — a mesma base de `DateRange.years`, que é quem mede o
 * expoente do outro lado. Compor em 252 aqui faria a série crescer por pregão e
 * ser medida por calendário, e o `perYear` do nome seria falso.
 */
function index(args: { tradingDays: number; perYear: number; finalNoise?: number; initialNoise?: number }): PriceSeries {
  const daily = Math.pow(1 + args.perYear, 1 / 365.25) - 1;
  let level = 100.0;
  const points: PricePoint[] = [];
  for (let i = 0; i < args.tradingDays; i++) {
    let close = level;
    if (i === args.tradingDays - 1) close *= args.finalNoise ?? 1.0;
    if (i === 0) close *= args.initialNoise ?? 1.0;
    points.push(new PricePoint({ date: today.subtract(new Duration({ days: args.tradingDays - i })), close }));
    level *= 1 + daily;
  }
  return new PriceSeries({ ticker: Ticker.parse('IBOV11'), points });
}

async function cagrOf(ibov: PriceSeries): Promise<number> {
  const r = await ResolveMarketAnchors.call({
    macro: new FixedMacro({
      cdi: rates(500, 0.0004, TimeBasis.businessDaily),
      ipca: rates(60, 0.004, TimeBasis.monthly),
      ibc: rates(60, 1.0, TimeBasis.monthly),
    }),
    benchmark: new FixedIndex(ibov),
    asOf: today,
  });
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap().marketCagr;
}

describe('CAGR do índice — as pontas são médias, não dois dias', () => {
  // O índice de atividade já era medido por média móvel nas pontas: "um CAGR
  // entre dois pontos isolados herdaria inteiramente o ruído deles". O
  // Ibovespa, que oscila muito mais, era o único sem o mesmo tratamento.
  // Medido em 11/09/2026 na janela de dez anos: **12,57% ponta a ponta
  // contra 11,06%** com trimestre nas pontas. Decisão 60.

  it('sobre uma exponencial limpa, recupera a taxa exata', async () => {
    // **É esta a razão de medir de centro a centro, e não de ponta a
    // ponta.** Promediar as pontas sem deslocar as datas encurtaria o
    // expoente e enviesaria o CAGR para cima; com os centros, o estimador
    // devolve a taxa verdadeira sem viés nenhum.
    for (const rate of [0.05, 0.1, 0.18]) {
      expectClose(await cagrOf(index({ tradingDays: 1260, perYear: rate })), rate, 1e-9);
    }
  });

  it('um salto no último pregão quase não move o CAGR', async () => {
    const clean = await cagrOf(index({ tradingDays: 1260, perYear: 0.1 }));
    const withJump = await cagrOf(index({ tradingDays: 1260, perYear: 0.1, finalNoise: 1.2 }));
    expect(Math.abs(withJump - clean), 'um dia 20% acima é diluído por 63 pregões').toBeLessThan(0.005);
  });

  it('e um buraco no primeiro pregão também não', async () => {
    const clean = await cagrOf(index({ tradingDays: 1260, perYear: 0.1 }));
    const withGap = await cagrOf(index({ tradingDays: 1260, perYear: 0.1, initialNoise: 0.8 }));
    expect(Math.abs(withGap - clean)).toBeLessThan(0.005);
  });

  it('sem a média, o mesmo salto moveria muito mais', async () => {
    // O contrafactual, calculado aqui: ponta a ponta, 20% no último dia
    // sobre cinco anos elevam o CAGR em ~3,7 p.p.
    const p = index({ tradingDays: 1260, perYear: 0.1, finalNoise: 1.2 }).points;
    const first = p[0]!;
    const last = p[p.length - 1]!;
    const years = new DateRange(first.date, last.date).years;
    const endToEnd = Math.pow(last.close / first.close, 1 / years) - 1;
    const clean = await cagrOf(index({ tradingDays: 1260, perYear: 0.1 }));
    expect(
      Math.abs(endToEnd - clean),
      'se o contrafactual não se movesse, o teste anterior não estaria medindo nada',
    ).toBeGreaterThan(0.02);
  });

  it('série curta parte as pontas ao meio, e ainda mede', async () => {
    const measured = await cagrOf(index({ tradingDays: 40, perYear: 0.1 }));
    expect(Number.isFinite(measured)).toBe(true);
    expect(measured, 'quarenta pregões bastam, com pontas de vinte').not.toBe(MarketAnchors.fallback2026.marketCagr);
  });

  it('série de um ponto cai no recuo declarado', async () => {
    const only = new PriceSeries({
      ticker: Ticker.parse('IBOV11'),
      points: [new PricePoint({ date: today, close: 100 })],
    });
    expect(await cagrOf(only)).toBe(MarketAnchors.fallback2026.marketCagr);
  });
});
