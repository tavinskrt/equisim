import { beforeEach, describe, expect, it } from 'vitest';

import { TrackingActions, useTrackings } from '../../src/app/state/tracking-store';
import { computeTracking, startDateProblem, type TrackingView } from '../../src/app/tracking';
import type { Services } from '../../src/app/services';
import {
  DateRange,
  DateTime,
  Duration,
  FinancialGoal,
  Money,
  ok,
  PricePoint,
  PriceSeries,
  RatePoint,
  RateSeries,
  Ticker,
  TrackingOrder,
  TrackingPlan,
  TrackingRecord,
  UpsideCohorts,
  type ValuationResult,
} from '../../src/core';
import { MemoryKeyValueStore } from '../../src/data/cache/key-value-store';
import { KeyValueTrackingStore, orderDocId } from '../../src/data/persistence/tracking-store';
import { day } from '../core/helpers';
import { testRuntime } from './harness';

const A = Ticker.parse('AAAA3');
const B = Ticker.parse('BBBB4');

function series(t: Ticker, start: DateTime, end: DateTime, close: number): PriceSeries {
  const points: PricePoint[] = [];
  for (let d = start; !d.isAfter(end); d = d.add(new Duration({ days: 1 }))) {
    if (d.weekday === 6 || d.weekday === 7) continue;
    points.push(new PricePoint({ date: d, close }));
  }
  return new PriceSeries({ ticker: t, points });
}

function record(args: { start: DateTime; createdOn: DateTime; id?: string }): TrackingRecord {
  return new TrackingRecord({
    id: args.id ?? 'acomp-1',
    name: 'Principal',
    createdAt: DateTime.utc(2024, 1, 1),
    plan: new TrackingPlan({
      start: args.start,
      createdOn: args.createdOn,
      initial: Money.fromReais(1000),
      monthly: Money.fromReais(500),
      tickers: [A, B],
    }),
    targetWealth: Money.fromReais(10000),
    months: 24,
    expectedReturn: 0.14,
    expectedSource: 'motor 2024-01-02',
  });
}

/** Uma raiz de dependências mínima: só o que o acompanhamento lê. */
function fakeServices(): Services {
  const end = day(2024, 6, 28);
  const prices = new Map([
    [A, series(A, day(2023, 9, 1), end, 30)],
    [B, series(B, day(2023, 9, 1), end, 45)],
  ]);
  const cohorts = new UpsideCohorts([
    {
      date: day(2023, 12, 31),
      entries: new Map([
        ['AAAA3', { upside: 1, price: 30 }],
        ['BBBB4', { upside: 0.2, price: 45 }],
      ]),
    },
  ]);
  const rates = new RateSeries(series(A, day(2023, 12, 1), end, 0).points.map((p) => new RatePoint({ date: p.date, rate: 0.0004 })));
  return {
    // Como a fonte real, devolve só a janela pedida: a falta da cotação da
    // coorte fora dela é o que impedia a compra depois da última coorte.
    prices: {
      dailyBatch: async (tickers: readonly Ticker[], range: DateRange) =>
        ok(
          new Map(
            tickers.map((t) => [
              t,
              new PriceSeries({
                ticker: t,
                points: prices.get(t)!.points.filter((p) => !p.date.isBefore(range.start) && !p.date.isAfter(range.end)),
              }),
            ]),
          ),
        ),
    },
    upsideCohorts: async () => cohorts,
    dividends: async () => [],
    macro: { riskFreeDaily: async () => ok(rates) },
    benchmark: { ibovespa: async () => ok(series(Ticker.parse('IBOV11'), day(2023, 9, 1), end, 100)) },
  } as unknown as Services;
}

describe('KeyValueTrackingStore', () => {
  it('cria, acrescenta sem sobrescrever a compra gravada, lista e apaga só do dono', async () => {
    const store = new KeyValueTrackingStore(new MemoryKeyValueStore(), () => {});
    const rec = record({ start: day(2024, 1, 2), createdOn: day(2024, 7, 1) });
    expect((await store.create('ana', rec)).isOk).toBe(true);
    const first = new TrackingOrder({ seq: 0, scheduledOn: day(2024, 1, 2), executedOn: day(2024, 1, 2), contribution: Money.fromReais(1000), ticker: A, quantity: 33, priceCents: 3000 });
    await store.appendOrders('ana', rec.id, [first]);
    // A mesma compra regravada com outro conteúdo não substitui a primeira.
    const altered = new TrackingOrder({ seq: 0, scheduledOn: day(2024, 1, 2), executedOn: day(2024, 1, 2), contribution: Money.fromReais(1000), ticker: B, quantity: 22, priceCents: 4500 });
    await store.appendOrders('ana', rec.id, [altered]);
    const listed = (await store.listFor('ana')).unwrap();
    expect(listed).toHaveLength(1);
    expect(listed[0]!.orders.map((o) => o.ticker?.value)).toEqual(['AAAA3']);
    expect((await store.listFor('bia')).unwrap()).toHaveLength(0);
    expect((await store.appendOrders('bia', rec.id, [first])).isErr).toBe(true);
    expect((await store.delete('bia', rec.id)).isErr).toBe(true);
    expect((await store.delete('ana', rec.id)).isOk).toBe(true);
    expect((await store.listFor('ana')).unwrap()).toHaveLength(0);
  });

  it('o documento da compra é nomeado pelo acompanhamento e pelo aporte', () => {
    expect(orderDocId('abc', 7)).toBe('abc-0007');
  });
});

describe('computeTracking', () => {
  it('monta o retrospectivo com as coortes e os quatro destinos de comparação, sem pedir o motor', async () => {
    let asked = 0;
    const r = await computeTracking({
      services: fakeServices(),
      stored: { record: record({ start: day(2024, 1, 2), createdOn: day(2024, 7, 1) }), orders: [] },
      today: day(2024, 6, 28),
      live: async () => {
        asked++;
        return new Map();
      },
    });
    const view = r.unwrap() as TrackingView;
    expect(asked).toBe(0);
    expect(view.outcome.orders.every((o) => o.origin === 'coorte')).toBe(true);
    expect(view.outcome.newOrders.length).toBe(view.outcome.orders.length);
    expect(view.curves.map((c) => c.key)).toEqual(['exigido', 'esperado', 'cdi', 'ibov']);
    // O Ibovespa parado devolve o aportado; o CDI, mais que ele.
    const ibov = view.curves.find((c) => c.key === 'ibov')!;
    expect(ibov.values[ibov.values.length - 1]).toBeCloseTo(view.outcome.contributed[view.outcome.contributed.length - 1]!, 6);
    const cdi = view.curves.find((c) => c.key === 'cdi')!;
    expect(cdi.annual!).toBeGreaterThan(0.09);
    expect(view.required).not.toBeNull();
  });

  it('depois da última coorte, a compra retrospectiva usa a última coorte, mesmo meses depois dela', async () => {
    // A coorte é de 31/12/2023 e o início, 03/06/2024: mais de cinco meses
    // depois, como um início em julho de 2026 contra a coorte de 30/09/2025.
    const r = await computeTracking({
      services: fakeServices(),
      stored: { record: record({ start: day(2024, 6, 3), createdOn: day(2024, 7, 1) }), orders: [] },
      today: day(2024, 6, 28),
      live: async () => new Map(),
    });
    const view = r.unwrap() as TrackingView;
    expect(view.outcome.orders).toHaveLength(1);
    const order = view.outcome.orders[0]!;
    expect(order.ticker).toBe(A);
    expect(order.origin).toBe('coorte');
    expect(order.fairValueAsOf!.month).toBe(12);
    expect(view.outcome.staleOrders).toBe(1);
    expect(view.outcome.newOrders).toHaveLength(1);
  });

  it('o aporte ao vivo vencido pede a avaliação de hoje e compra com ela', async () => {
    const valuation = (t: Ticker, fair: number) =>
      ({ ticker: t, fairValue: Money.fromReais(fair), asOf: day(2024, 6, 28), diagnostics: null }) as unknown as ValuationResult;
    const r = await computeTracking({
      services: fakeServices(),
      stored: { record: record({ start: day(2024, 6, 3), createdOn: day(2024, 6, 3) }), orders: [] },
      today: day(2024, 6, 28),
      live: async () => new Map([[A, valuation(A, 31)], [B, valuation(B, 90)]]),
    });
    const view = r.unwrap() as TrackingView;
    expect(view.outcome.newOrders).toHaveLength(1);
    expect(view.outcome.newOrders[0]!.origin).toBe('motor');
    expect(view.outcome.newOrders[0]!.ticker).toBe(B);
  });

  it('data de início sem pregão ainda é espera, e não erro', async () => {
    const r = await computeTracking({
      services: fakeServices(),
      stored: { record: record({ start: day(2024, 7, 1), createdOn: day(2024, 7, 1) }), orders: [] },
      today: day(2024, 7, 1),
      live: async () => new Map(),
    });
    expect('waiting' in r.unwrap()).toBe(true);
  });
});

describe('startDateProblem', () => {
  const cohorts = new UpsideCohorts([{ date: day(2018, 3, 31), entries: new Map() }]);
  it('aceita hoje sempre, e o passado só desde a primeira coorte', () => {
    expect(startDateProblem({ start: day(2026, 11, 4), today: day(2026, 11, 4), cohorts: null })).toBeNull();
    expect(startDateProblem({ start: day(2026, 11, 5), today: day(2026, 11, 4), cohorts })).toContain('futuro');
    expect(startDateProblem({ start: day(2018, 3, 1), today: day(2026, 11, 4), cohorts })).toContain('2018-03-31');
    expect(startDateProblem({ start: day(2020, 1, 1), today: day(2026, 11, 4), cohorts: null })).toContain('só pode começar hoje');
    expect(startDateProblem({ start: day(2020, 1, 1), today: day(2026, 11, 4), cohorts })).toBeNull();
  });
});

describe('TrackingActions', () => {
  beforeEach(() => {
    useTrackings.setState({ status: 'idle', items: [], error: null, busy: false, syncError: null });
  });

  it('inicia com a meta e a Principal congeladas, grava as compras e encerra', async () => {
    testRuntime();
    const goal = FinancialGoal.unvalidated({
      initialContribution: Money.fromReais(10000),
      monthlyContribution: Money.fromReais(1000),
      months: 120,
      targetWealth: Money.fromReais(500000),
    });
    const started = await TrackingActions.start({
      goal,
      tickers: [A, B],
      start: day(2024, 1, 2),
      today: day(2026, 11, 4),
      createdAt: DateTime.utc(2026, 11, 4, 12),
      contributionDay: 10,
      expectedReturn: 0.15,
      cohortsGeneratedAt: day(2026, 11, 3),
    });
    const stored = started.unwrap();
    expect(stored.record.plan.contributionDay).toBe(10);
    expect(stored.record.plan.weightCap).toBe(1);
    expect(stored.record.expectedSource).toBe('motor 2026-11-04');
    const order = new TrackingOrder({ seq: 0, scheduledOn: day(2024, 1, 2), executedOn: day(2024, 1, 2), contribution: Money.fromReais(10000) });
    await TrackingActions.appendOrders(stored.record.id, [order]);
    expect(useTrackings.getState().items[0]!.orders).toHaveLength(1);
    await TrackingActions.load();
    expect(useTrackings.getState().items[0]!.orders).toHaveLength(1);
    expect((await TrackingActions.remove(stored.record.id)).isOk).toBe(true);
    expect(useTrackings.getState().items).toHaveLength(0);
  });

  it('sem sessão, recusa iniciar', async () => {
    testRuntime({ user: null });
    const goal = FinancialGoal.unvalidated({
      initialContribution: Money.fromReais(1),
      monthlyContribution: Money.fromReais(1),
      months: 12,
      targetWealth: Money.fromReais(100),
    });
    const r = await TrackingActions.start({
      goal,
      tickers: [A],
      start: day(2024, 1, 2),
      today: day(2026, 11, 4),
      createdAt: DateTime.utc(2026, 11, 4),
      contributionDay: 5,
      expectedReturn: null,
      cohortsGeneratedAt: null,
    });
    expect(r.isErr).toBe(true);
  });
});
