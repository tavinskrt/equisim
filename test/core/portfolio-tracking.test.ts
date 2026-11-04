import { describe, expect, it } from 'vitest';

import {
  B3CashDividends,
  CashDividend,
  CashDividendKind,
  DateTime,
  Duration,
  FairValueReading,
  FlowBenchmarks,
  Money,
  monthsBetween,
  PortfolioTracker,
  PricePoint,
  PriceSeries,
  projectedEndValue,
  RatePoint,
  RateSeries,
  Ticker,
  TopUpsidePolicy,
  TrackingOrder,
  TrackingPlan,
  TrackingRecord,
  TransactionCosts,
  UpsideCohorts,
  UpsideCohortsCodec,
} from '../../src/core';
import { day, expectClose } from './helpers';

const A = Ticker.parse('AAAA3');
const B = Ticker.parse('BBBB4');
const C = Ticker.parse('CCCC3');

/** Um pregão por dia útil, de [start] a [end], com o fechamento que [close] der. */
function series(t: Ticker, start: DateTime, end: DateTime, close: (d: DateTime) => number): PriceSeries {
  const points: PricePoint[] = [];
  for (let d = start; !d.isAfter(end); d = d.add(new Duration({ days: 1 }))) {
    if (d.weekday === 6 || d.weekday === 7) continue;
    points.push(new PricePoint({ date: d, close: close(d) }));
  }
  return new PriceSeries({ ticker: t, points });
}

const flat = (v: number) => () => v;

function plan(args: Partial<ConstructorParameters<typeof TrackingPlan>[0]> = {}): TrackingPlan {
  return new TrackingPlan({
    start: day(2024, 1, 2),
    createdOn: day(2030, 1, 1),
    initial: Money.fromReais(1000),
    monthly: Money.fromReais(500),
    contributionDay: 5,
    tickers: [A, B],
    costs: TransactionCosts.none,
    ...args,
  });
}

/** Preço justo fixo por ativo, como se uma coorte só valesse o período inteiro. */
const fixedFair =
  (fair: Map<Ticker, number>) =>
  (t: Ticker, d: DateTime): FairValueReading | null => {
    const v = fair.get(t);
    return v === undefined ? null : new FairValueReading({ ticker: t, fairValue: v, origin: 'coorte', asOf: d });
  };

describe('UpsideCohorts', () => {
  const cohorts = new UpsideCohorts([
    { date: day(2024, 3, 31), entries: new Map([['AAAA3', { upside: 0.5, price: 20 }]]) },
    { date: day(2024, 6, 30), entries: new Map([['AAAA3', { upside: -0.2, price: 25 }]]) },
  ]);

  it('usa a coorte mais recente anterior ou igual à data, e nenhuma antes da primeira', () => {
    expect(cohorts.cohortAsOf(day(2024, 3, 30))).toBeNull();
    expect(cohorts.cohortAsOf(day(2024, 3, 31))!.date.month).toBe(3);
    expect(cohorts.cohortAsOf(day(2024, 6, 29))!.date.month).toBe(3);
    expect(cohorts.cohortAsOf(day(2024, 7, 15))!.date.month).toBe(6);
  });

  it('leva o preço justo para a base da série: um desdobramento depois da coorte não muda o potencial', () => {
    // A fonte da coorte cotava a R$ 20; a série de hoje, ajustada por um
    // desdobramento de 2 para 1, cota o mesmo dia a R$ 10.
    const s = series(A, day(2024, 1, 1), day(2024, 5, 31), flat(10));
    const r = cohorts.readingAt(A, day(2024, 5, 10), s)!;
    expect(r.origin).toBe('coorte');
    expectClose(r.fairValue, 15, 1e-12);
    expectClose(r.upsideAt(10)!, 0.5, 1e-12);
    // O preço sobe 20% depois da coorte, e o potencial cai na mesma conta.
    expectClose(r.upsideAt(12)!, 15 / 12 - 1, 1e-12);
  });

  it('não lê ativo ausente da coorte nem série que começa depois dela', () => {
    const s = series(B, day(2024, 1, 1), day(2024, 5, 31), flat(10));
    expect(cohorts.readingAt(B, day(2024, 5, 10), s)).toBeNull();
    const late = series(A, day(2024, 4, 15), day(2024, 5, 31), flat(10));
    expect(cohorts.readingAt(A, day(2024, 5, 10), late)).toBeNull();
  });

  it('o pacote volta igual do formato gravado', () => {
    const json = UpsideCohortsCodec.encode(cohorts.cohorts, { generatedAt: day(2026, 11, 3) });
    const back = UpsideCohortsCodec.decode(JSON.parse(JSON.stringify(json)))!;
    expect(back.cohorts).toHaveLength(2);
    expect(back.cohorts[1]!.entries.get('AAAA3')).toEqual({ upside: -0.2, price: 25 });
    expect(back.generatedAt!.day).toBe(3);
    expect(UpsideCohortsCodec.decode({ versao: 99, coortes: [] })).toBeNull();
  });
});

describe('TopUpsidePolicy', () => {
  const reading = (t: Ticker) => new FairValueReading({ ticker: t, fairValue: 1, origin: 'motor', asOf: day(2024, 1, 1) });
  const candidate = (t: Ticker, order: number, upside: number, positionCents: number, priceCents = 1000) => ({
    ticker: t,
    order,
    priceCents,
    reading: reading(t),
    upside,
    positionCents,
  });

  it('o teto padrão é o dobro do peso igual, nunca acima de 100%', () => {
    expect(TopUpsidePolicy.defaultCap(10)).toBeCloseTo(0.2, 12);
    expect(TopUpsidePolicy.defaultCap(2)).toBe(1);
    expect(TopUpsidePolicy.defaultCap(1)).toBe(1);
  });

  it('compra o maior potencial entre os abaixo do teto', () => {
    const d = TopUpsidePolicy.choose({
      candidates: [candidate(A, 0, 0.9, 8000), candidate(B, 1, 0.5, 1000), candidate(C, 2, 0.1, 1000)],
      totalPositionCents: 10000,
      cashCents: 5000,
      cap: 0.5,
      costs: TransactionCosts.none,
    })!;
    expect(d.candidate.ticker).toBe(B);
    expect(d.quantity).toBe(5);
    expect(d.capOverridden).toBe(false);
  });

  it('com todos no teto, vale o maior potencial geral, e a decisão diz isso', () => {
    const d = TopUpsidePolicy.choose({
      candidates: [candidate(A, 0, 0.2, 10000), candidate(B, 1, 0.9, 10000)],
      totalPositionCents: 20000,
      cashCents: 3000,
      cap: 0.5,
      costs: TransactionCosts.none,
    })!;
    expect(d.candidate.ticker).toBe(B);
    expect(d.capOverridden).toBe(true);
  });

  it('pula o ativo de que o caixa não paga uma ação, e empata pela ordem da carteira', () => {
    const d = TopUpsidePolicy.choose({
      candidates: [candidate(A, 0, 0.9, 0, 6000), candidate(C, 2, 0.3, 0), candidate(B, 1, 0.3, 0)],
      totalPositionCents: 0,
      cashCents: 5000,
      cap: 0.5,
      costs: TransactionCosts.none,
    })!;
    expect(d.candidate.ticker).toBe(B);
    expect(
      TopUpsidePolicy.choose({ candidates: [candidate(A, 0, 0.9, 0, 6000)], totalPositionCents: 0, cashCents: 5000, cap: 1, costs: TransactionCosts.none }),
    ).toBeNull();
  });
});

describe('PortfolioTracker', () => {
  const end = day(2024, 4, 30);
  const prices = new Map([
    [A, series(A, day(2024, 1, 1), end, flat(30))],
    [B, series(B, day(2024, 1, 1), end, flat(45))],
  ]);
  // A está mais descontado: justo 60 contra 30 (+100%); B, justo 54 contra 45 (+20%).
  const fair = new Map([
    [A, 60],
    [B, 54],
  ]);

  it('cada aporte compra ações inteiras do maior potencial abaixo do teto, e a sobra espera o mês seguinte', () => {
    const r = PortfolioTracker.run({ plan: plan({ weightCap: 0.6 }), prices, until: end, retro: fixedFair(fair) }).unwrap();
    // Inicial em 02/01 e mensais em 05/02, 05/03 e 05/04.
    expect(r.orders.map((o) => o.seq)).toEqual([0, 1, 2, 3]);
    expect(r.orders.map((o) => o.executedOn.day)).toEqual([2, 5, 5, 5]);
    const [first, second, third] = r.orders;
    // R$ 1.000 a R$ 30: 33 ações e R$ 10 de sobra.
    expect(first!.ticker).toBe(A);
    expect(first!.quantity).toBe(33);
    expect(first!.cashAfterCents).toBe(1000);
    // A com 100% passa do teto de 60%: o mês vai a B. Caixa 510 a R$ 45: 11 ações.
    expect(second!.ticker).toBe(B);
    expect(second!.quantity).toBe(11);
    expect(second!.cashAfterCents).toBe(1500);
    // A ainda pesa 990/(990 + 495) = 66,7%, acima do teto: o mês fica com B.
    expect(third!.ticker).toBe(B);
    expect(r.orders.every((o) => o.origin === 'coorte')).toBe(true);
    expect(r.newOrders).toHaveLength(4);
    expect(r.pendingLive).toBe(0);
  });

  it('fecha ao centavo: aportado + proventos − pago − tarifa é o caixa, e ações mais caixa é o patrimônio', () => {
    const r = PortfolioTracker.run({
      plan: plan({ costs: TransactionCosts.b3 }),
      prices,
      until: end,
      retro: fixedFair(fair),
    }).unwrap();
    let paid = 0;
    let fees = 0;
    for (const o of r.orders) {
      paid += o.tradedCents;
      fees += o.costCents;
    }
    expect(r.totalContributedCents).toBe(250000);
    expect(r.totalContributedCents + r.totalDividendsCents - paid - fees).toBe(r.cashCents);
    expect(fees).toBe(r.totalCostCents);
    expect(Math.round(r.wealth[r.wealth.length - 1]! * 100)).toBe(r.finalValueCents);
    expect(r.contributed[r.contributed.length - 1]).toBe(2500);
  });

  it('a retenção do JCP é a da data-com: 15% até 2025 e 17,5% desde 2026 (LC 224/2025)', () => {
    const jcp = (y: number, m: number, d: number) =>
      new CashDividend({
        shareClass: 'ON',
        kind: CashDividendKind.interestOnEquity,
        lastDateWithRights: DateTime.utc(y, m, d),
        exDate: DateTime.utc(y, m, d + 1),
        amount: 1,
      });
    expect(B3CashDividends.jcpWithholdingOn(DateTime.utc(2025, 12, 31))).toBe(0.15);
    expect(B3CashDividends.jcpWithholdingOn(DateTime.utc(2026, 1, 1))).toBe(0.175);
    expect(jcp(2025, 12, 30).netAmountOnRecordDate).toBeCloseTo(0.85, 12);
    expect(jcp(2026, 3, 10).netAmountOnRecordDate).toBeCloseTo(0.825, 12);
    // O líquido da validação não muda: as coortes e o beta seguem nos 15%.
    expect(jcp(2026, 3, 10).netAmount).toBeCloseTo(0.85, 12);
    const dividend = new CashDividend({
      shareClass: 'ON',
      kind: CashDividendKind.dividend,
      lastDateWithRights: DateTime.utc(2026, 3, 10),
      exDate: DateTime.utc(2026, 3, 11),
      amount: 1,
    });
    expect(dividend.netAmountOnRecordDate).toBe(1);
  });

  it('credita o provento na data ex sobre as ações da data-com, com o JCP líquido de 15%', () => {
    const dividends = new Map([
      [
        A,
        [
          new CashDividend({
            shareClass: 'ON',
            kind: CashDividendKind.interestOnEquity,
            lastDateWithRights: DateTime.utc(2024, 1, 10),
            exDate: DateTime.utc(2024, 1, 11),
            // R$ 2 por ação na base da época, com o papel a R$ 60 antes de um
            // desdobramento de 2 para 1: na série de hoje, R$ 1 por ação.
            amount: 2,
            closeWithRights: 60,
          }),
        ],
      ],
    ]);
    const r = PortfolioTracker.run({ plan: plan(), prices, dividends, until: end, retro: fixedFair(fair) }).unwrap();
    // 33 ações × R$ 30 × (2 × 0,85) / 60 = R$ 28,05.
    expect(r.totalDividendsCents).toBe(2805);
    expect(r.holdings.find((h) => h.ticker === A)!.dividendsCents).toBe(2805);
    const off = PortfolioTracker.run({
      plan: plan({ reinvestDividends: false }),
      prices,
      dividends,
      until: end,
      retro: fixedFair(fair),
    }).unwrap();
    expect(off.totalDividendsCents).toBe(0);
  });

  it('a compra gravada vale como está, e só o aporte sem registro é decidido', () => {
    const recorded = [
      new TrackingOrder({
        seq: 0,
        scheduledOn: day(2024, 1, 2),
        executedOn: day(2024, 1, 2),
        contribution: Money.fromReais(1000),
        ticker: B,
        quantity: 22,
        priceCents: 4500,
        origin: 'coorte',
      }),
    ];
    const r = PortfolioTracker.run({ plan: plan(), prices, recorded, until: end, retro: fixedFair(fair) }).unwrap();
    expect(r.orders[0]!.ticker).toBe(B);
    expect(r.newOrders.map((o) => o.seq)).toEqual([1, 2, 3]);
    // Caixa depois da gravada: 1.000 − 990 = 10; com o aporte de 05/02, 510.
    expect(r.newOrders[0]!.ticker).toBe(A);
    expect(r.newOrders[0]!.quantity).toBe(17);
  });

  it('ao vivo: o aporte vencido espera o motor, e com ele compra no último pregão', () => {
    const live = plan({ start: day(2024, 4, 1), createdOn: day(2024, 4, 1) });
    const pending = PortfolioTracker.run({ plan: live, prices, until: end, retro: fixedFair(fair) }).unwrap();
    expect(pending.pendingLive).toBe(1);
    expect(pending.orders).toHaveLength(0);
    // Sem compra, o aporte está em caixa: o patrimônio é o aportado.
    expect(pending.cashCents).toBe(100000);

    const motor = (t: Ticker) => new FairValueReading({ ticker: t, fairValue: t === B ? 90 : 31, origin: 'motor', asOf: end });
    const done = PortfolioTracker.run({ plan: live, prices, until: end, retro: fixedFair(fair), live: motor }).unwrap();
    expect(done.newOrders).toHaveLength(1);
    expect(done.newOrders[0]!.ticker).toBe(B);
    expect(done.newOrders[0]!.origin).toBe('motor');
    expect(done.newOrders[0]!.executedOn.day).toBe(30);
    expect(done.newOrders[0]!.scheduledOn.day).toBe(1);
    expect(done.newOrders[0]!.delayDays).toBe(29);
  });

  it('o mês em curso só tem aporte quando o dia dele chega', () => {
    const r = PortfolioTracker.run({ plan: plan({ contributionDay: 20 }), prices, until: day(2024, 4, 15), retro: fixedFair(fair) }).unwrap();
    expect(r.orders.map((o) => `${o.scheduledOn.month}/${o.scheduledOn.day}`)).toEqual(['1/2', '2/20', '3/20']);
  });

  it('o retrospectivo é reproduzível: a mesma entrada dá as mesmas compras', () => {
    const one = PortfolioTracker.run({ plan: plan(), prices, until: end, retro: fixedFair(fair) }).unwrap();
    const two = PortfolioTracker.run({ plan: plan(), prices, until: end, retro: fixedFair(fair) }).unwrap();
    expect(two.orders.map((o) => JSON.stringify(o.toJson()))).toEqual(one.orders.map((o) => JSON.stringify(o.toJson())));
  });

  it('recusa plano sem ativo ou sem aporte', () => {
    expect(PortfolioTracker.run({ plan: plan({ tickers: [] }), prices, until: end, retro: fixedFair(fair) }).isErr).toBe(true);
    expect(
      PortfolioTracker.run({ plan: plan({ initial: Money.zero, monthly: Money.zero }), prices, until: end, retro: fixedFair(fair) }).isErr,
    ).toBe(true);
  });
});

describe('registros gravados', () => {
  it('a compra e o acompanhamento voltam iguais do JSON', () => {
    const o = new TrackingOrder({
      seq: 3,
      scheduledOn: day(2024, 2, 5),
      executedOn: day(2024, 2, 7),
      contribution: Money.fromReais(500),
      ticker: A,
      quantity: 16,
      priceCents: 3000,
      costCents: 14,
      upside: 0.25,
      fairValue: 37.5,
      origin: 'motor',
      fairValueAsOf: day(2024, 2, 7),
      cashAfterCents: 1986,
    });
    expect(TrackingOrder.fromJson(JSON.parse(JSON.stringify(o.toJson())))!.toJson()).toEqual(o.toJson());
    const rec = new TrackingRecord({
      id: 'x',
      name: 'Principal',
      createdAt: DateTime.utc(2026, 11, 4, 12),
      plan: plan(),
      targetWealth: Money.fromReais(500000),
      months: 120,
      expectedReturn: 0.149,
      expectedSource: 'motor 2026-11-04',
    });
    const back = TrackingRecord.fromJson(JSON.parse(JSON.stringify(rec.toJson())))!;
    expect(back.toJson()).toEqual(rec.toJson());
    expect(back.endDate.year).toBe(2034);
    expect(TrackingOrder.fromJson({ seq: -1 })).toBeNull();
  });
});

describe('FlowBenchmarks', () => {
  const dates = [day(2024, 1, 2), day(2024, 7, 1), day(2025, 1, 2)];
  const flows = [100000, 50000, 0];

  it('à taxa zero, a curva é o aportado; e o XIRR da curva a 12% é 12%', () => {
    expect(FlowBenchmarks.atAnnualRate({ dates, flowCents: flows, annual: 0 })).toEqual([1000, 1500, 1500]);
    const v = FlowBenchmarks.atAnnualRate({ dates, flowCents: flows, annual: 0.12 });
    // O valor final vira centavo antes do XIRR: o meio centavo pesa na sexta casa.
    expectClose(FlowBenchmarks.moneyWeighted({ dates, flowCents: flows, values: v })!, 0.12, 1e-5);
  });

  it('no índice, cada aporte compra cotas no fechamento do dia', () => {
    const index = new PriceSeries({
      ticker: Ticker.parse('IBOV11'),
      points: [new PricePoint({ date: day(2024, 1, 2), close: 100 }), new PricePoint({ date: day(2024, 7, 1), close: 125 }), new PricePoint({ date: day(2025, 1, 2), close: 150 })],
    });
    const v = FlowBenchmarks.onIndex({ dates, flowCents: flows, index })!;
    expectClose(v[1]!, 1250 + 500, 1e-9);
    expectClose(v[2]!, (10 + 4) * 150, 1e-9);
  });

  it('no CDI, o depósito rende a taxa do próprio dia', () => {
    const rates = new RateSeries([
      new RatePoint({ date: day(2024, 1, 2), rate: 0.001 }),
      new RatePoint({ date: day(2024, 3, 1), rate: 0.001 }),
      new RatePoint({ date: day(2024, 12, 30), rate: 0.001 }),
    ]);
    const { values, covered } = FlowBenchmarks.onDailyRates({ dates, flowCents: flows, rates });
    expectClose(values[1]!, 1000 * 1.001 * 1.001 + 500, 1e-9);
    expectClose(values[2]!, (1000 * 1.001 * 1.001 + 500) * 1.001, 1e-9);
    expect(covered).toBe(true);
  });
});

describe('projeção', () => {
  it('conta os meses pelo calendário e projeta o valor futuro dos aportes que faltam', () => {
    expect(monthsBetween(day(2024, 1, 5), day(2024, 3, 4))).toBe(1);
    expect(monthsBetween(day(2024, 1, 5), day(2024, 3, 5))).toBe(2);
    expect(projectedEndValue({ currentWealth: 1000, monthlyContribution: 100, remainingMonths: 12, annual: 0 })).toBe(2200);
    expectClose(projectedEndValue({ currentWealth: 1000, monthlyContribution: 0, remainingMonths: 12, annual: 0.1 }), 1100, 1e-9);
  });
});
