// O ajuste que a fonte de preços deixou de fazer (item B29).
//
// A fonte ajusta desdobramento e grupamento, e não toda bonificação: a data ex
// de uma bonificação não ajustada é uma queda que não aconteceu, e ela entrava
// no beta, na volatilidade da faixa e em todo retorno que a atravessa.
import { describe, expect, it } from 'vitest';

import {
  CapitalEvents,
  CapitalEventsCodec,
  CorporateEvents,
  DateTime,
  Duration,
  type JsonObject,
  Money,
  PricePoint,
  PriceSeries,
  ShareEvent,
  ShareIssue,
  Ticker,
} from '../../src/core';
import { day, expectClose } from './helpers';

const t = Ticker.parse('ABCD3');

/** Série diária de dias úteis com [price] constante, salvo o [jump] aplicado a partir de [ex]. */
function series(args: { jump: number; ex?: DateTime; price?: number }): PriceSeries {
  const price = args.price ?? 10;
  const pts: PricePoint[] = [];
  // O laço anda em UTC, que não tem horário de verão; o ponto trunca para o
  // dia local, como a fonte.
  let d = DateTime.utc(2024, 3, 1);
  while (d.isBefore(DateTime.utc(2024, 5, 1))) {
    if (d.weekday <= 5) {
      const local = day(d.year, d.month, d.day);
      const after = args.ex !== undefined && !local.isBefore(args.ex);
      pts.push(new PricePoint({ date: local, close: after ? price * args.jump : price, volume: 1000 }));
    }
    d = d.add(new Duration({ days: 1 }));
  }
  return new PriceSeries({ ticker: t, points: pts });
}

const event = (ex: DateTime, factor: number): ShareEvent => new ShareEvent({ exDate: ex, factor, observedRatio: 1 / factor });

const ex = day(2024, 4, 2);

describe('completeAdjustment', () => {
  it('bonificação de 10% sem ajuste: a queda sai e o volume sobe', () => {
    const s = series({ jump: 1 / 1.1, ex });
    const r = CorporateEvents.completeAdjustment(s, [event(ex, 1.1)]);
    expect(r.applied).toHaveLength(1);
    const before = r.series.points.find((p) => p.date.equals(day(2024, 4, 1)))!;
    const after = r.series.points.find((p) => p.date.equals(ex))!;
    expectClose(after.close / before.close, 1, 1e-9, 'a série fica contínua na data ex');
    expectClose(before.volume! * before.close, 1000 * 10, 1e-6, 'o financeiro do dia não muda');
  });

  it('evento que a fonte já ajustou não muda nada', () => {
    const s = series({ jump: 1.0 });
    const r = CorporateEvents.completeAdjustment(s, [event(ex, 1.1)]);
    expect(r.applied).toEqual([]);
    expect(r.series).toBe(s);
  });

  it('desdobramento de 2 para 1 sem ajuste também sai', () => {
    const s = series({ jump: 0.5, ex });
    const r = CorporateEvents.completeAdjustment(s, [event(ex, 2)]);
    expect(r.applied).toHaveLength(1);
    expectClose(r.series.points[0]!.close, 5, 1e-9);
  });

  it('um pregão de −5% na data ex de bonificação já ajustada fica como está', () => {
    // Com a folga de 6% ele passaria por bonificação não ajustada, e o
    // ajuste inventaria uma alta de 10% no lugar da queda.
    const s = series({ jump: 0.95, ex });
    expect(CorporateEvents.completeAdjustment(s, [event(ex, 1.1)]).applied).toEqual([]);
  });

  it('bonificação não ajustada com o mercado andando 2% no dia sai', () => {
    const s = series({ jump: 0.98 / 1.1, ex });
    expect(CorporateEvents.completeAdjustment(s, [event(ex, 1.1)]).applied).toHaveLength(1);
  });

  it('evento sem pregão vizinho na série não ajusta nada', () => {
    const s = series({ jump: 1 / 1.1, ex });
    expect(CorporateEvents.completeAdjustment(s, [event(day(2023, 1, 10), 1.1)]).applied).toEqual([]);
  });
});

it('applyToSeries ajusta sem perguntar', () => {
  const s = series({ jump: 1.0 });
  const a = CorporateEvents.applyToSeries(s, [event(ex, 1.1)]);
  expectClose(a.points[0]!.close, 10 / 1.1, 1e-9);
  expectClose(a.points[a.points.length - 1]!.close, 10, 1e-9);
});

it('o pacote de eventos de capital vai e volta, e pula o malformado', () => {
  const pkg = CapitalEventsCodec.encodePackage(
    new Map([
      [
        'ABCD3',
        new CapitalEvents({
          issues: [new ShareIssue({ date: day(2026, 2, 4), amount: Money.fromReais(5.4e9), shares: 270000000 })],
          shareEvents: [event(day(2024, 4, 16), 2)],
        }),
      ],
      ['VAZI3', new CapitalEvents()],
    ]),
    { generatedAt: day(2026, 9, 24) },
  );
  const assets = pkg['ativos'] as JsonObject;
  expect('VAZI3' in assets).toBe(false);
  const parsed = CapitalEventsCodec.decodePackage({
    ...pkg,
    ativos: {
      ...assets,
      RUIM3: {
        emissoes: [
          { data: 'não é data', centavos: 100, acoes: 1 },
          { data: '2026-01-01', centavos: -500, acoes: 1 },
          // Fração de ação e centavo fracionário são entrada malformada.
          { data: '2026-01-01', centavos: 500, acoes: 1.5 },
          { data: '2026-01-01', centavos: 50.5, acoes: 1 },
        ],
        eventos: [{ dataEx: '2026-01-01', fator: 0 }],
      },
    },
  });
  expect([...parsed.keys()]).toEqual(['ABCD3']);
  const abcd = parsed.get('ABCD3')!;
  expect(abcd.issues).toHaveLength(1);
  expect(abcd.issues[0]!.amount.equals(Money.fromReais(5.4e9))).toBe(true);
  expect(abcd.issues[0]!.shares).toBe(270000000);
  expect(abcd.shareEvents).toHaveLength(1);
  expect(abcd.shareEvents[0]!.factor).toBe(2);
});
