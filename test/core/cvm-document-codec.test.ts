import { expect, it } from 'vitest';

import {
  CvmDocumentCodec,
  CvmDocumentKind,
  CvmPeriodDocument,
  DateTime,
  FundamentalsSnapshot,
  Ticker,
  TrailingTwelveMonths,
  type JsonObject,
} from '../../src/core';
import { expectDate } from './helpers';

const t = Ticker.parse('WEGE3');
const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

function itr(): CvmPeriodDocument {
  return new CvmPeriodDocument({
    kind: CvmDocumentKind.itr,
    periodStart: d(2023, 1, 1),
    periodEnd: d(2023, 6, 30),
    current: new FundamentalsSnapshot({
      ticker: t,
      fiscalPeriodEnd: d(2023, 6, 30),
      receiptDate: d(2023, 7, 26),
      totalRevenue: 15867479000,
      netIncome: 2733728000,
      cash: 4918937000,
      treasuryFraction: 0.0012,
    }),
    prior: new FundamentalsSnapshot({
      ticker: t,
      fiscalPeriodEnd: d(2022, 6, 30),
      totalRevenue: 14013893000,
      netIncome: 1879602000,
    }),
    priorStart: d(2022, 1, 1),
  });
}

const viaJson = (doc: CvmPeriodDocument): CvmPeriodDocument =>
  CvmDocumentCodec.decode(t, JSON.parse(JSON.stringify(CvmDocumentCodec.encode(doc))) as JsonObject)!;

it('ida e volta preserva cada campo, período e publicidade', () => {
  const original = itr();
  // Pelo JSON de verdade, e não só pelo mapa: é o que o aplicativo lê.
  const roundTrip = viaJson(original);
  expect(roundTrip.kind).toBe(CvmDocumentKind.itr);
  expectDate(roundTrip.periodStart, original.periodStart);
  expectDate(roundTrip.periodEnd, original.periodEnd);
  expectDate(roundTrip.priorStart, original.priorStart!);
  expectDate(roundTrip.current.receiptDate, original.current.receiptDate!);
  expect(roundTrip.current.totalRevenue).toBe(original.current.totalRevenue);
  expect(roundTrip.current.netIncome).toBe(original.current.netIncome);
  expect(roundTrip.current.cash).toBe(original.current.cash);
  expect(roundTrip.current.treasuryFraction).toBe(original.current.treasuryFraction);
  expect(roundTrip.prior!.netIncome).toBe(original.prior!.netIncome);
  expect(roundTrip.current.ebit, 'nulo continua nulo').toBeNull();
});

it('a soma de doze meses dá o mesmo resultado antes e depois do codec', () => {
  const dfp = new CvmPeriodDocument({
    kind: CvmDocumentKind.dfp,
    periodStart: d(2022, 1, 1),
    periodEnd: d(2022, 12, 31),
    current: new FundamentalsSnapshot({ ticker: t, fiscalPeriodEnd: d(2022, 12, 31), totalRevenue: 29904000000 }),
  });
  const direct = TrailingTwelveMonths.build({ annual: dfp, itr: itr() })!;
  const withCodec = TrailingTwelveMonths.build({ annual: viaJson(dfp), itr: viaJson(itr()) })!;
  expect(withCodec.totalRevenue).toBe(direct.totalRevenue);
});

it('omite nulo e grava inteiro sem casas', () => {
  const m = CvmDocumentCodec.encode(itr());
  const c = m['c'] as JsonObject;
  expect('ebit' in c).toBe(false);
  expect(Number.isInteger(c['rev'])).toBe(true);
  expect(Number.isInteger(c['tf'])).toBe(false);
});

it('pacote de versão desconhecida não é lido pela metade', () => {
  const pkg = CvmDocumentCodec.encodePackage(new Map([['WEGE3', [itr()]]]), { generatedAt: d(2026, 9, 14) });
  const read = CvmDocumentCodec.decodePackage(JSON.parse(JSON.stringify(pkg)) as JsonObject);
  expect(read.get('WEGE3')).toHaveLength(1);

  const future = { ...pkg, versao: CvmDocumentCodec.version + 1 };
  expect(CvmDocumentCodec.decodePackage(JSON.parse(JSON.stringify(future)) as JsonObject).size).toBe(0);
});

it('documento sem período ou de tipo desconhecido é descartado', () => {
  expect(CvmDocumentCodec.decode(t, { k: 'D', c: {} })).toBeNull();
  expect(CvmDocumentCodec.decode(t, { k: 'X', s: '2023-01-01', e: '2023-12-31', c: {} })).toBeNull();
});
