import { describe, expect, it } from 'vitest';

import {
  CvmDocumentKind,
  CvmPeriodDocument,
  CvmSeries,
  DateTime,
  FieldSource,
  FundamentalsSnapshot,
  PointInTimeView,
  Ticker,
} from '../../src/core';
import { expectDate } from './helpers';

const t = Ticker.parse('TEST3');
const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

const s = (end: DateTime, o: { profit?: number; mc?: number; rec?: DateTime } = {}): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: end,
    netIncome: o.profit ?? null,
    marketCap: o.mc ?? null,
    receiptDate: o.rec ?? null,
  });

const dfp = (a: number): CvmPeriodDocument =>
  new CvmPeriodDocument({
    kind: CvmDocumentKind.dfp,
    periodStart: d(a, 1, 1),
    periodEnd: d(a, 12, 31),
    current: s(d(a, 12, 31), { profit: 10, rec: d(a + 1, 3, 1) }),
  });

const itr = (a: number): CvmPeriodDocument =>
  new CvmPeriodDocument({
    kind: CvmDocumentKind.itr,
    periodStart: d(a, 1, 1),
    periodEnd: d(a, 6, 30),
    current: s(d(a, 6, 30), { profit: 6, rec: d(a, 8, 10) }),
    prior: s(d(a - 1, 6, 30), { profit: 5 }),
    priorStart: d(a - 1, 1, 1),
  });

const all = (): boolean => true;
const range = (from: number, to: number): number[] => Array.from({ length: to - from + 1 }, (_, i) => from + i);
const publishedAt = (asOf: DateTime): ((s: FundamentalsSnapshot) => boolean) => {
  const view = new PointInTimeView(asOf);
  return (snapshot) => view.isPublished(snapshot);
};

// Mercado cobre 2016-2022, sempre em dezembro, com valor de mercado.
const market = range(2016, 2022).map((a) => s(d(a, 12, 31), { profit: 9, mc: 1000.0 + a }));
const anchoredDocs = (): CvmPeriodDocument[] => [...range(2018, 2022).map(dfp), ...range(2019, 2023).map(itr)];

it('anual: CVM onde existe, mercado onde só ele existe', () => {
  const r = CvmSeries.build({ documents: range(2019, 2022).map(dfp), market, published: all, anchored: false });
  expect(r.anchoredOnQuarter).toBe(false);
  expect(r.series.length, '2016–2018 do mercado, 2019–2022 da CVM').toBe(7);
  expect(r.series[r.series.length - 1]!.netIncome, 'a CVM vence onde tem').toBe(10);
  expect(r.series[0]!.netIncome).toBe(9);
});

it('DFP recebida depois da data não apaga o exercício de mercado', () => {
  // USIM3: a DFP de 2023 foi reapresentada, e a versão ingerida tem
  // recebimento em 16/01/2025. Em 04/09/2024 ela não existia — mas ocupava
  // o ano na mescla, o exercício de mercado de 2023 era descartado, e a
  // cascata depois removia o ponto mesclado por ser do futuro. O ano sumia.
  const docs = [
    ...range(2019, 2021).map(dfp),
    new CvmPeriodDocument({
      kind: CvmDocumentKind.dfp,
      periodStart: d(2022, 1, 1),
      periodEnd: d(2022, 12, 31),
      current: s(d(2022, 12, 31), { profit: 10, rec: d(2024, 1, 16) }),
    }),
  ];
  const asOf = d(2023, 9, 1);
  const r = CvmSeries.build({ documents: docs, market, published: publishedAt(asOf), anchored: false });
  const visible = r.series.filter(publishedAt(asOf));
  const last = visible[visible.length - 1]!;
  expectDate(last.fiscalPeriodEnd, d(2022, 12, 31), 'o exercício de 2022 estava publicado pelo mercado');
  expect(last.netIncome, 'e é o do mercado').toBe(9);
});

it('ancorada: só junhos, e o mercado de dezembro não entra no meio', () => {
  const r = CvmSeries.build({ documents: anchoredDocs(), market, published: all, anchored: true });
  expect(r.anchoredOnQuarter).toBe(true);
  expect(new Set(r.series.map((x) => x.fiscalPeriodEnd.month))).toEqual(new Set([6]));
});

it('a mescla não olha para a frente: junho usa o dezembro ANTERIOR', () => {
  const r = CvmSeries.build({ documents: anchoredDocs(), market, published: all, anchored: true });
  // O ponto de jun/2022 tem de levar o valor de mercado de dez/2021.
  const jun22 = r.series.find((x) => x.fiscalPeriodEnd.year === 2022)!;
  expect(jun22.marketCap).toBe(1000.0 + 2021);
});

it('e o dezembro anterior não empresta fluxo ao junho — decisão 78', () => {
  const withInterest = market.map(
    (x) =>
      new FundamentalsSnapshot({
        ticker: x.ticker,
        fiscalPeriodEnd: x.fiscalPeriodEnd,
        netIncome: x.netIncome,
        marketCap: x.marketCap,
        interestExpense: -3,
      }),
  );
  const anchored = CvmSeries.build({ documents: anchoredDocs(), market: withInterest, published: all, anchored: true });
  expect(
    anchored.series.every((x) => x.interestExpense === null),
    'juros de dezembro num ponto de junho',
  ).toBe(true);
  expect(anchored.series.every((x) => x.marketCap !== null)).toBe(true);

  // Na anual, dezembro com dezembro: o mercado continua completando.
  const annual = CvmSeries.build({ documents: anchoredDocs(), market: withInterest, published: all, anchored: false });
  expect(annual.series.every((x) => x.interestExpense === -3)).toBe(true);
});

it('ancorada que recua para DFP se comporta como a anual', () => {
  // Sem ITR de 2021, a série ancorada recua. Recuada, ela tem de aceitar os
  // exercícios que só o mercado tem — senão encurta à toa.
  const docs = [...range(2019, 2022).map(dfp), ...[2020, 2022, 2023].map(itr)];
  const anchored = CvmSeries.build({ documents: docs, market, published: all, anchored: true });
  const annual = CvmSeries.build({ documents: docs, market, published: all, anchored: false });
  expect(anchored.anchoredOnQuarter).toBe(false);
  expect(anchored.series.length).toBe(annual.series.length);
});

it('sem documento da CVM, a série de mercado passa intacta', () => {
  const r = CvmSeries.build({ documents: [], market, published: all, anchored: true });
  expect(r.series.length).toBe(market.length);
  expect(r.provenance.size).toBe(0);
});

it('a procedência soma as duas fontes', () => {
  const r = CvmSeries.build({ documents: range(2019, 2022).map(dfp), market, published: all, anchored: false });
  expect(r.provenance.get(FieldSource.cvm)).toBeGreaterThan(0);
  expect(r.provenance.get(FieldSource.market)).toBeGreaterThan(0);
});

describe('versões do mesmo documento (item B8)', () => {
  // A DFP de 2021 saiu com lucro 10 em 01/03/2022 e foi reapresentada com
  // lucro 4 em 15/06/2023. Quem avaliava em 2022 só tinha a original.
  const version = (profit: number, rec: DateTime): CvmPeriodDocument =>
    new CvmPeriodDocument({
      kind: CvmDocumentKind.dfp,
      periodStart: d(2021, 1, 1),
      periodEnd: d(2021, 12, 31),
      current: s(d(2021, 12, 31), { profit, rec }),
    });
  const original = version(10, d(2022, 3, 1));
  const restated = version(4, d(2023, 6, 15));
  const docs = [dfp(2020), restated, original];

  const ofYear2021 = (asOf: DateTime): FundamentalsSnapshot => {
    const series = CvmSeries.build({ documents: docs, market, published: publishedAt(asOf), anchored: false }).series;
    return series.filter((x) => x.fiscalPeriodEnd.year === 2021).at(-1)!;
  };

  it('antes da reapresentação, a coorte lê a original', () => {
    expect(ofYear2021(d(2022, 9, 30)).netIncome).toBe(10);
  });

  it('depois dela, a reapresentada — em qualquer ordem da lista', () => {
    expect(ofYear2021(d(2023, 9, 30)).netIncome).toBe(4);
  });

  it('um exercício entra uma vez só, com qualquer número de versões', () => {
    const r = CvmSeries.build({ documents: docs, market, published: all, anchored: false });
    expect(r.series.filter((x) => x.fiscalPeriodEnd.year === 2021).length).toBe(1);
  });

  it('vigentes: descarta a versão ainda não recebida e a superada', () => {
    const in2022 = CvmSeries.inForceAt(docs, publishedAt(d(2022, 9, 30)));
    expect(
      in2022.map((x) => x.current.netIncome),
      'a DFP de 2020 e a original de 2021',
    ).toEqual([10, 10]);
    const in2023 = CvmSeries.inForceAt(docs, publishedAt(d(2023, 9, 30)));
    expect(in2023[in2023.length - 1]).toBe(restated);
  });

  it('com uma versão por documento, vigentes é o filtro de publicados', () => {
    const single = range(2019, 2022).map(dfp);
    const p = publishedAt(d(2022, 9, 30));
    expect(CvmSeries.inForceAt(single, p)).toEqual(single.filter((x) => p(x.current)));
  });
});
