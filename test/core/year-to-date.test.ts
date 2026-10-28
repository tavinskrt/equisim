import { describe, expect, it } from 'vitest';

import {
  CapitalSeries,
  CvmDocumentKind,
  CvmPeriodDocument,
  CvmSeries,
  DateTime,
  EligibilityGate,
  FundamentalsSnapshot,
  GrowthGuards,
  Ticker,
  ValuationLane,
  YearToDate,
} from '../../src/core';
import { expectDate } from './helpers';

const t = Ticker.parse('TEST3');
const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);
const always = (): boolean => true;

const s = (end: DateTime, o: { profit?: number; equity?: number; revenue?: number; received?: DateTime } = {}) =>
  new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: end,
    netIncome: o.profit ?? null,
    totalRevenue: o.revenue ?? null,
    totalStockholderEquity: o.equity ?? null,
    receiptDate: o.received ?? null,
  });

const dfp = (year: number, profit: number, equity: number): CvmPeriodDocument =>
  new CvmPeriodDocument({
    kind: CvmDocumentKind.dfp,
    periodStart: d(year, 1, 1),
    periodEnd: d(year, 12, 31),
    current: s(d(year, 12, 31), { profit, equity, revenue: 10 * profit, received: d(year + 1, 3, 1) }),
  });

const itr = (year: number, month: number, day: number, profit: number, equity: number): CvmPeriodDocument =>
  new CvmPeriodDocument({
    kind: CvmDocumentKind.itr,
    periodStart: d(year, 1, 1),
    periodEnd: d(year, month, day),
    current: s(d(year, month, day), { profit, equity, revenue: 10 * profit, received: d(year, month + 1, 15) }),
    prior: s(d(year - 1, month, day), { profit: profit + 1 }),
    priorStart: d(year - 1, 1, 1),
  });

/** Dez exercícios de lucro 15 sobre patrimônio 100, crescendo 5 por ano. */
const history = (): CvmPeriodDocument[] => {
  const out: CvmPeriodDocument[] = [];
  for (let y = 2016; y <= 2025; y++) out.push(dfp(y, 15, 100 + 5 * (y - 2016)));
  return out;
};

describe('Ano corrente anualizado (decisão 153)', () => {
  it('conta os meses do acumulado pelo número de dias', () => {
    expect(YearToDate.months(d(2026, 1, 1), d(2026, 3, 31))).toBe(3);
    expect(YearToDate.months(d(2026, 1, 1), d(2026, 6, 30))).toBe(6);
    expect(YearToDate.months(d(2026, 1, 1), d(2026, 9, 30))).toBe(9);
  });

  it('anualiza o fluxo do ITR mais recente e mantém o balanço da data dele', () => {
    const docs = [...history(), itr(2026, 3, 31, 3, 150), itr(2026, 6, 30, 7, 152)];
    const p = YearToDate.latest(docs)!;
    expect(p.annualizedMonths).toBe(6);
    expect(p.netIncome).toBe(14);
    expect(p.totalRevenue).toBe(140);
    expect(p.totalStockholderEquity).toBe(152);
    expect(p.earningsPerShare).toBeNull();
    expectDate(p.fiscalPeriodEnd, d(2026, 6, 30));
  });

  it('o acumulado de nove meses vale 12/9', () => {
    const p = YearToDate.latest([...history(), itr(2026, 9, 30, 9, 155)])!;
    expect(p.annualizedMonths).toBe(9);
    expect(p.netIncome).toBeCloseTo(12, 12);
  });

  it('sem ITR depois da última DFP não há ano corrente', () => {
    expect(YearToDate.latest(history())).toBeNull();
    // O ITR do ano da própria DFP já está dentro dela.
    expect(YearToDate.latest([...history(), itr(2025, 6, 30, 7, 140)])).toBeNull();
  });

  it('recusa o acumulado que não começa no dia seguinte à DFP', () => {
    const shifted = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2026, 4, 1),
      periodEnd: d(2026, 6, 30),
      current: s(d(2026, 6, 30), { profit: 4, equity: 150 }),
    });
    expect(YearToDate.latest([...history(), shifted])).toBeNull();
  });

  it('a série anual termina no ano corrente só quando pedido', () => {
    const docs = [...history(), itr(2026, 6, 30, 7, 152)];
    const off = CvmSeries.build({ documents: docs, market: [], published: always, anchored: false });
    expect(off.series.length).toBe(10);
    expect(off.endsAnnualized).toBe(false);

    const on = CvmSeries.build({ documents: docs, market: [], published: always, anchored: false, yearToDate: true });
    expect(on.series.length).toBe(11);
    expect(on.endsAnnualized).toBe(true);
    const last = on.series[on.series.length - 1]!;
    expect(last.annualizedMonths).toBe(6);
    expect(last.netIncome).toBe(14);
  });

  it('o ITR ainda não publicado não entra', () => {
    const docs = [...history(), itr(2026, 6, 30, 7, 152)];
    const beforeJuly = (x: FundamentalsSnapshot): boolean =>
      x.receiptDate === null || !x.receiptDate.isAfter(d(2026, 7, 1));
    const r = CvmSeries.build({ documents: docs, market: [], published: beforeJuly, anchored: false, yearToDate: true });
    expect(r.endsAnnualized).toBe(false);
  });

  it('o ponto entra no retorno e fica fora das variações da base', () => {
    const docs = [...history(), itr(2026, 6, 30, 7, 152)];
    const series = CvmSeries.build({ documents: docs, market: [], published: always, anchored: false, yearToDate: true });
    const capital = CapitalSeries.build(series.series, ValuationLane.shareholder);
    // Lucro anualizado 14 sobre o patrimônio de dez/2025, 145.
    expect(capital.latestReturn).toBeCloseTo(14 / 145, 12);
    const without = CapitalSeries.build(series.series.slice(0, -1), ValuationLane.shareholder);
    expect(capital.annualVariations).toEqual(without.annualVariations);
    expect(capital.retentions).toEqual(without.retentions);
  });

  it('o capital externo não lê a variação de meses como de um ano', () => {
    // Patrimônio do ITR muito acima do de dezembro: lido como um ano, seria
    // capital externo; a guarda o ignora.
    const docs = [...history(), itr(2026, 6, 30, 7, 400)];
    const series = CvmSeries.build({ documents: docs, market: [], published: always, anchored: false, yearToDate: true });
    const withPoint = GrowthGuards.externalCapitalRatio(CapitalSeries.build(series.series, ValuationLane.shareholder));
    expect(withPoint).toBe(0);
  });

  it('o ano corrente não conta como exercício publicado na Porta 0', () => {
    const docs = [...history().slice(0, 7), itr(2023, 6, 30, 7, 140)];
    const series = CvmSeries.build({ documents: docs, market: [], published: always, anchored: false, yearToDate: true });
    expect(series.endsAnnualized).toBe(true);
    const verdict = EligibilityGate.assess({ snapshots: series.series, minPeriods: 8 });
    expect(verdict.publishedPeriods).toBe(7);
    expect(verdict.isEligible).toBe(false);
  });
});
