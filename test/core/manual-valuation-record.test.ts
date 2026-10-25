// O valuation confirmado guarda as premissas e o resultado juntos, e vai ao
// armazenamento e ao painel de auditoria pelo mesmo retrato (decisão 150).
//
// O que estes testes travam: o registro guarda **o que a conta deu**, sem
// refazê-la; relê-lo devolve os mesmos números, bit a bit; um documento
// corrompido é descartado sem lançar; e o evento do painel carrega o mesmo
// identificador e os mesmos valores da tela.
import { beforeAll, describe, expect, it } from 'vitest';

import {
  AuditEvent,
  CapmInputs,
  DateTime,
  FundamentalsSnapshot,
  InvalidInput,
  type JsonMap,
  ManualField,
  type ManualPremises,
  ManualRatePath,
  ManualReinvestment,
  type ManualValuation,
  ManualValuationRecord,
  Money,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  type ValuationResult,
} from '../../src/core';
import { day, expectDate } from './helpers';

/**
 * A mesma companhia sintética da cascata usada na tela (`populated_state`):
 * a via da firma com o resultado operacional sustentado, a do acionista com
 * ele negativo.
 */
function cascade(firm = true): ValuationResult {
  const ticker = Ticker.parse(firm ? 'WEGE3' : 'ITUB4');
  const series: FundamentalsSnapshot[] = [];
  let e = 1.0;
  for (let i = 12; i >= 0; i--) {
    series.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(2025 - i, 12, 31),
        totalRevenue: 10000e6 * e,
        ebit: (firm ? 1800e6 : -200e6) * e,
        ebitda: (firm ? 2400e6 : 300e6) * e,
        netIncome: 900e6 * e,
        incomeBeforeTax: (firm ? 1300e6 : 1200e6) * e,
        incomeTaxExpense: (firm ? -400e6 : -300e6) * e,
        interestExpense: firm ? 400e6 : 50e6,
        earningsPerShare: 0.9 * e,
        cash: firm ? 200e6 : 2000e6 * e,
        shortTermDebt: firm ? 1000e6 : 500e6,
        longTermDebt: firm ? 3000e6 : 500e6,
        totalStockholderEquity: 6000e6 * e,
        bookValuePerShare: 6.0 * e,
        operatingCashFlow: firm ? 2000e6 * e : null,
        nopat: firm ? 1188e6 * e : null,
        sharesOutstanding: 1000e6,
        sharesOutstandingAsOf: 1000e6,
        marketCap: 12000e6,
      }),
    );
    e *= i % 2 === 0 ? 1.04 : 1.06;
  }
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 9, 9),
      fundamentals: series,
      marketPrice: 12.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
      declaredTerminalRiskFreeRate: 0.1,
      unleveredBeta: firm ? 0.8 : 0.9,
    }),
  );
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap();
}

const savedAt = DateTime.utc(2026, 10, 22, 18, 30, 15);

function capture(r: ValuationResult, p: ManualPremises, id = '7f0c2b1e-0000-4000-8000-000000000001'): ManualValuationRecord {
  const record = ManualValuationRecord.capture({
    id,
    ticker: r.ticker,
    engineAsOf: r.asOf,
    valuation: r.manual!,
    premises: p,
    savedAt,
  });
  expect(record.isOk, record.failureOrNull?.message).toBe(true);
  return record.unwrap();
}

/** O que se grava, passado por texto como o armazenamento e o canal fazem. */
const wire = (json: JsonMap): JsonMap => JSON.parse(JSON.stringify(json)) as JsonMap;

for (const firm of [true, false]) {
  const via = firm ? 'da firma' : 'do acionista';

  describe(`via ${via}`, () => {
    let r: ValuationResult;
    let m: ManualValuation;

    beforeAll(() => {
      r = cascade(firm);
      m = r.manual!;
    });

    it('sem troca, o registro guarda o preço do motor, bit a bit', () => {
      const record = capture(r, m.enginePremises);
      expect(record.fairValuePerShare).toBe(m.engineFairValue);
      expect(record.changedFields).toEqual([]);
      expect(record.attribution).toEqual([]);
      expect(record.lane).toBe(firm ? ValuationLane.firm : ValuationLane.shareholder);
    });

    it('com troca, guarda o que a conta deu, sem refazê-la', () => {
      const p = m.enginePremises.copyWith({
        growth: m.enginePremises.growth + 0.02,
        discountRate: m.enginePremises.discountRate - 0.01,
        ratePath: ManualRatePath.constant,
      });
      const record = capture(r, p);
      const expected = m.evaluate(p).unwrap();
      expect(record.fairValuePerShare).toBe(expected.fairValuePerShare);
      expect(record.outcome.equityValue).toBe(expected.equityValue);
      expect(record.outcome.years.length).toBe(expected.years.length);
      expect(record.changedFields).toEqual([ManualField.growth, ManualField.discountRate]);
      expect(record.attribution.length).toBeGreaterThan(0);
      expect(record.engineDelta).toBe(expected.fairValuePerShare - m.engineFairValue);
      expect(record.upside).toBe(expected.fairValuePerShare / m.marketPrice - 1);
      expect(record.fairValue.equals(Money.fromReais(expected.fairValuePerShare))).toBe(true);
    });

    it('relido do texto, o registro é o mesmo, número a número', () => {
      const p = m.enginePremises.copyWith({
        baseProfit: m.enginePremises.baseProfit * 1.2,
        reinvestment: ManualReinvestment.fixedFraction,
        retention: 0.35,
        terminalReturn: m.enginePremises.discountRate + 0.04,
      });
      const record = capture(r, p);
      const again = ManualValuationRecord.fromJson(wire(record.toJson()));
      expect(again).not.toBeNull();
      expect(again!.toJson()).toEqual(record.toJson());
      expect(again!.id).toBe(record.id);
      expect(again!.ticker).toBe(record.ticker);
      expect(again!.savedAt.isAtSameMomentAs(record.savedAt)).toBe(true);
      expectDate(again!.engineAsOf, record.engineAsOf);
      expect(again!.premises.retention).toBe(0.35);
      expect(again!.premises.reinvestment).toBe(ManualReinvestment.fixedFraction);
      expect(again!.fairValuePerShare).toBe(record.fairValuePerShare);
      expect(again!.changedFields).toEqual(record.changedFields);
    });

    it('o evento do painel carrega o mesmo identificador e os números', () => {
      const p = m.enginePremises.copyWith({ perpetualGrowth: m.enginePremises.perpetualGrowth + 0.005 });
      const record = capture(r, p);
      const event = record.toAuditEvent();

      expect(event.transactionId).toBe(record.id);
      expectDate(event.timestamp, record.savedAt);
      expect(event.endpoint).toBe(`/core/valuation/manual/${r.ticker.value}`);
      // O painel conta o evento entre os cálculos pela origem `/core/`.
      expect(event.endpoint.startsWith('/core/')).toBe(true);
      expect(event.outputPayload['status']).toBe('confirmado');
      expect(event.outputPayload['precoJusto']).toBe(record.fairValuePerShare);
      expect(event.outputPayload['precoJustoCentavos']).toBe(record.fairValue.cents);
      expect(event.inputPayload['camposTrocados']).toEqual(['crescimentoPerpetuo']);

      const byName = new Map(event.calculations.map((c) => [c.formulaName, c.finalValue]));
      expect(byName.get('Preço justo por ação — seus números')).toBe(record.fairValuePerShare);
      expect(byName.get('Valor do patrimônio — seus números')).toBe(record.outcome.equityValue);
      expect(byName.get('Valor presente dos anos explícitos — seus números')).toBe(record.outcome.explicitPresentValue);

      // O canal entre janelas e a exportação passam o evento por JSON.
      const back = AuditEvent.fromJson(wire(event.toJson()));
      expect(back.transactionId).toBe(record.id);
      expect(back.calculations.length).toBe(event.calculations.length);
    });
  });
}

describe('recusa e leitura tolerante', () => {
  let r: ValuationResult;

  beforeAll(() => {
    r = cascade();
  });

  it('premissa sem conta não vira registro, e a falha nomeia o campo', () => {
    const p = r.manual!.enginePremises.copyWith({ baseProfit: -1 });
    const record = ManualValuationRecord.capture({
      id: 'x',
      ticker: r.ticker,
      engineAsOf: r.asOf,
      valuation: r.manual!,
      premises: p,
      savedAt,
    });
    expect(record.isOk).toBe(false);
    const failure = record.failureOrNull;
    expect(failure).toBeInstanceOf(InvalidInput);
    expect((failure as InvalidInput).field).toBe(ManualField.baseProfit.name);
  });

  it('identificador vazio é recusado', () => {
    const record = ManualValuationRecord.capture({
      id: '  ',
      ticker: r.ticker,
      engineAsOf: r.asOf,
      valuation: r.manual!,
      premises: r.manual!.enginePremises,
      savedAt,
    });
    expect(record.failureOrNull).toBeInstanceOf(InvalidInput);
  });

  it('documento corrompido devolve null, e não lança', () => {
    const good = wire(capture(r, r.manual!.enginePremises).toJson());
    const without = (key: string): JsonMap => {
      const copy = { ...good };
      delete copy[key];
      return copy;
    };

    expect(ManualValuationRecord.fromJson({ ...good, formato: 2 })).toBeNull();
    expect(ManualValuationRecord.fromJson(without('resultado'))).toBeNull();
    expect(ManualValuationRecord.fromJson(without('premissas'))).toBeNull();
    expect(ManualValuationRecord.fromJson({ ...good, via: 'outra' })).toBeNull();
    expect(ManualValuationRecord.fromJson({ ...good, ticker: '??' })).toBeNull();
    expect(ManualValuationRecord.fromJson({ ...good, id: '' })).toBeNull();
    expect(ManualValuationRecord.fromJson({ ...good, salvoEm: 'ontem' })).toBeNull();
    expect(ManualValuationRecord.fromJson({})).toBeNull();
  });

  it('a mesma confirmação dá sempre o mesmo registro', () => {
    const p = r.manual!.enginePremises.copyWith({ growth: 0.07 });
    expect(capture(r, p).toJson()).toEqual(capture(r, p).toJson());
  });
});
