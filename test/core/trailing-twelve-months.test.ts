import { describe, expect, it } from 'vitest';

import {
  CvmDocumentKind,
  CvmPeriodDocument,
  DateTime,
  FundamentalsSnapshot,
  Ticker,
  TrailingTwelveMonths,
} from '../../src/core';
import { expectDate } from './helpers';

const t = Ticker.parse('TEST3');
const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

const s = (
  end: DateTime,
  o: { revenue?: number; profit?: number; ebit?: number; ebitda?: number; cash?: number | null; received?: DateTime } = {},
): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: end,
    totalRevenue: o.revenue ?? null,
    netIncome: o.profit ?? null,
    ebit: o.ebit ?? null,
    ebitda: o.ebitda ?? null,
    cash: o.cash ?? null,
    receiptDate: o.received ?? null,
  });

const dfp = (year: number, o: { revenue?: number; profit?: number } = {}): CvmPeriodDocument =>
  new CvmPeriodDocument({
    kind: CvmDocumentKind.dfp,
    periodStart: d(year, 1, 1),
    periodEnd: d(year, 12, 31),
    current: s(d(year, 12, 31), { revenue: o.revenue ?? 30, profit: o.profit ?? 3, received: d(year + 1, 3, 1) }),
  });

const itrJune = (
  year: number,
  o: { revenue?: number; profit?: number; previousRevenue?: number; previousProfit?: number; cash?: number | null } = {},
): CvmPeriodDocument =>
  new CvmPeriodDocument({
    kind: CvmDocumentKind.itr,
    periodStart: d(year, 1, 1),
    periodEnd: d(year, 6, 30),
    current: s(d(year, 6, 30), {
      revenue: o.revenue ?? 16,
      profit: o.profit ?? 2,
      cash: 'cash' in o ? o.cash : 5,
      received: d(year, 8, 10),
    }),
    prior: s(d(year - 1, 6, 30), { revenue: o.previousRevenue ?? 14, profit: o.previousProfit ?? 1 }),
    priorStart: d(year - 1, 1, 1),
  });

const months = (series: readonly FundamentalsSnapshot[]): Set<number> => new Set(series.map((p) => p.fiscalPeriodEnd.month));

describe('Doze meses', () => {
  it('anual + acumulado − anterior', () => {
    // FY22 = 30; 1S23 = 16; 1S22 = 14 -> jul/22 a jun/23 = 32.
    const ttm = TrailingTwelveMonths.build({ annual: dfp(2022), itr: itrJune(2023) })!;
    expect(ttm.totalRevenue).toBe(32);
    expect(ttm.netIncome).toBe(4);
    expectDate(ttm.fiscalPeriodEnd, d(2023, 6, 30));
  });

  it('identidade: um acumulado de doze meses devolve o próprio exercício', () => {
    // Se o "trimestral" cobre o exercício inteiro, a soma tem de reproduzir
    // a DFP dele. É a prova de que a aritmética soma os períodos certos.
    const fy22 = dfp(2022, { revenue: 30, profit: 3 });
    const asItr = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2023, 1, 1),
      periodEnd: d(2023, 12, 31),
      current: s(d(2023, 12, 31), { revenue: 37, profit: 5 }),
      prior: s(d(2022, 12, 31), { revenue: 30, profit: 3 }),
      priorStart: d(2022, 1, 1),
    });
    const ttm = TrailingTwelveMonths.build({ annual: fy22, itr: asItr })!;
    expect(ttm.totalRevenue).toBe(37);
    expect(ttm.netIncome).toBe(5);
  });

  it('estoque vem da data do trimestre, e a publicidade também', () => {
    const ttm = TrailingTwelveMonths.build({ annual: dfp(2022), itr: itrJune(2023) })!;
    expect(ttm.cash).toBe(5);
    expectDate(ttm.receiptDate, d(2023, 8, 10));
  });

  it('exercício social de abril a março soma do mesmo jeito', () => {
    // SMTO3, JALL3 e RAIZ4 encerram em março. FY abr/22–mar/23; o ITR de
    // jun/23 acumula abr–jun/23 e compara com abr–jun/22.
    const fy = new CvmPeriodDocument({
      kind: CvmDocumentKind.dfp,
      periodStart: d(2022, 4, 1),
      periodEnd: d(2023, 3, 31),
      current: s(d(2023, 3, 31), { revenue: 100 }),
    });
    const itr = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2023, 4, 1),
      periodEnd: d(2023, 6, 30),
      current: s(d(2023, 6, 30), { revenue: 28 }),
      prior: s(d(2022, 6, 30), { revenue: 25 }),
      priorStart: d(2022, 4, 1),
    });
    expect(TrailingTwelveMonths.build({ annual: fy, itr })!.totalRevenue).toBe(103);
  });

  it('EBITDA sai de EBIT e D&A somados, não do EBITDA de um período só', () => {
    const fy = new CvmPeriodDocument({
      kind: CvmDocumentKind.dfp,
      periodStart: d(2022, 1, 1),
      periodEnd: d(2022, 12, 31),
      current: s(d(2022, 12, 31), { ebit: 10, ebitda: 14 }),
    });
    const itr = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2023, 1, 1),
      periodEnd: d(2023, 6, 30),
      current: s(d(2023, 6, 30), { ebit: 6, ebitda: 8 }),
      prior: s(d(2022, 6, 30), { ebit: 5, ebitda: 7 }),
      priorStart: d(2022, 1, 1),
    });
    const ttm = TrailingTwelveMonths.build({ annual: fy, itr })!;
    expect(ttm.ebit).toBe(11);
    expect(ttm.ebitda).toBe(11 + (4 + 2 - 2));
  });
});

describe('Recusas — somar períodos que não fecham produz outro intervalo', () => {
  it('acumulado que não começa depois do exercício anual', () => {
    const itr = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2023, 2, 15),
      periodEnd: d(2023, 6, 30),
      current: s(d(2023, 6, 30), { revenue: 16 }),
      prior: s(d(2022, 6, 30), { revenue: 14 }),
      priorStart: d(2022, 1, 1),
    });
    expect(TrailingTwelveMonths.build({ annual: dfp(2022), itr })).toBeNull();
  });

  it('DFP de outro ano', () => {
    expect(TrailingTwelveMonths.build({ annual: dfp(2021), itr: itrJune(2023) })).toBeNull();
  });

  it('sem o comparativo do ano anterior', () => {
    const itr = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2023, 1, 1),
      periodEnd: d(2023, 6, 30),
      current: s(d(2023, 6, 30), { revenue: 16 }),
    });
    expect(TrailingTwelveMonths.build({ annual: dfp(2022), itr })).toBeNull();
  });

  it('tipos trocados', () => {
    expect(TrailingTwelveMonths.build({ annual: itrJune(2023), itr: dfp(2022) })).toBeNull();
  });

  it('campo ausente em uma parcela fica ausente, e não vira zero', () => {
    const itr = new CvmPeriodDocument({
      kind: CvmDocumentKind.itr,
      periodStart: d(2023, 1, 1),
      periodEnd: d(2023, 6, 30),
      current: s(d(2023, 6, 30), { revenue: 16, profit: 2 }),
      prior: s(d(2022, 6, 30), { revenue: 14 }), // sem lucro
      priorStart: d(2022, 1, 1),
    });
    const ttm = TrailingTwelveMonths.build({ annual: dfp(2022), itr })!;
    expect(ttm.totalRevenue).toBe(32);
    expect(ttm.netIncome).toBeNull();
  });
});

describe('Série ancorada', () => {
  const all = (): boolean => true;
  const documents = [
    ...[2018, 2019, 2020, 2021, 2022].map((a) => dfp(a)),
    ...[2019, 2020, 2021, 2022, 2023].map((a) => itrJune(a)),
  ];

  it('ancorada em ITR, todos os pontos terminam na mesma data, a um ano', () => {
    const series = TrailingTwelveMonths.anchoredSeries(documents, { published: all });
    expect(series.length).toBe(5);
    for (const p of series) {
      expect(p.fiscalPeriodEnd.month).toBe(6);
      expect(p.fiscalPeriodEnd.day).toBe(30);
    }
    for (let i = 1; i < series.length; i++) {
      expect(
        series[i]!.fiscalPeriodEnd.year - series[i - 1]!.fiscalPeriodEnd.year,
        'é o espaçamento anual que as guardas do motor presumem',
      ).toBe(1);
    }
  });

  it('ancorada em DFP, devolve as DFPs', () => {
    // Sem ITR publicado depois da última DFP, a série é a de sempre.
    const onlyDfp = [2018, 2019, 2020, 2021, 2022].map((a) => dfp(a));
    const series = TrailingTwelveMonths.anchoredSeries(onlyDfp, { published: all });
    expect(months(series)).toEqual(new Set([12]));
    expect(series.length).toBe(5);
  });

  it('a âncora troca quando o ITR é recebido, e só então', () => {
    const until = (dayLimit: DateTime, snap: FundamentalsSnapshot): boolean =>
      snap.receiptDate === null || !snap.receiptDate.isAfter(dayLimit);

    // Em 01/05/2023 o mais recente publicado é a DFP 2022, recebida em
    // março: a série é a das DFPs.
    const before = TrailingTwelveMonths.anchoredSeries(documents, { published: (x) => until(d(2023, 5, 1), x) });
    expectDate(before[before.length - 1]!.fiscalPeriodEnd, d(2022, 12, 31));

    // O ITR de jun/23 é recebido em 10/08/2023. Em 15/08 a âncora é ele, e a
    // série inteira passa a terminar em junho.
    const after = TrailingTwelveMonths.anchoredSeries(documents, { published: (x) => until(d(2023, 8, 15), x) });
    expectDate(after[after.length - 1]!.fiscalPeriodEnd, d(2023, 6, 30));
    expect(months(after)).toEqual(new Set([6]));
  });

  it('série com buraco recua INTEIRA para a âncora de DFP — decisão 73', () => {
    // Em 14/09/2026 a CVM não publica o ITR de 2025. A primeira versão
    // montou jun/24 seguido de jun/26, e as guardas anuais leram dois anos
    // como um: QUAL3 de -22% a +908%.
    const withoutItr2021 = documents.filter((x) => !(x.kind === CvmDocumentKind.itr && x.periodEnd.year === 2021));
    const series = TrailingTwelveMonths.anchoredSeries(withoutItr2021, { published: all });
    expect(months(series), 'nem buraco, nem mistura de âncoras').toEqual(new Set([12]));
    for (let i = 1; i < series.length; i++) {
      expect(series[i]!.fiscalPeriodEnd.year - series[i - 1]!.fiscalPeriodEnd.year).toBe(1);
    }
    expect(TrailingTwelveMonths.isAnchoredOnQuarter(series, withoutItr2021)).toBe(false);
  });

  it('sem a DFP anterior à âncora, também recua', () => {
    const withoutDfp2022 = documents.filter((x) => !(x.kind === CvmDocumentKind.dfp && x.periodEnd.year === 2022));
    expect(months(TrailingTwelveMonths.anchoredSeries(withoutDfp2022, { published: all }))).toEqual(new Set([12]));
  });

  it('série contígua é reconhecida como ancorada em trimestre', () => {
    const series = TrailingTwelveMonths.anchoredSeries(documents, { published: all });
    expect(TrailingTwelveMonths.isAnchoredOnQuarter(series, documents)).toBe(true);
  });
});
