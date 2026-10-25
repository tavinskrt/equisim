// A ponte por papel na data da coorte (item C3).
//
// O que se confere aqui é o que a montagem antiga errava por construção: o
// preço na base de ações de hoje contra a contagem na base do exercício, e a
// razão de unidade que saía 1 para qualquer unit. As referências são grandezas
// de fora da função testada — o financeiro do COTAHIST, a composição declarada
// da unit, a razão de unidade medida pelo próprio motor.
import { describe, expect, it } from 'vitest';

import {
  DateTime,
  Duration,
  EligibilityGate,
  PricePoint,
  PriceSeries,
  str,
  Ticker,
  UnitCompositionCodec,
  ValuationCascade,
} from '../../src/core';
import { TradingDay } from '../../tool/b3/dividends';
import { baseFactorOf, CapitalClasses, chain, companyCodes, kindOf, MarketValue, seriesOnDateBasis } from '../../tool/cohorts/as-of-base';
import { expectClose } from '../core/helpers';

const d = (y: number, m: number, day: number): DateTime => DateTime.utc(y, m, day);

/** Pregões diários de [from] em diante, com fechamento e financeiro dados. */
const tradingDays = (from: DateTime, closes: readonly number[], tradedValue = 1e6): TradingDay[] =>
  closes.map((c, i) => new TradingDay(from.add(new Duration({ days: i })), c, 100, tradedValue));

describe('kindOf', () => {
  it('lê a espécie pelo número do ticker', () => {
    expect(kindOf('SAPR3')).toBe('common');
    expect(kindOf('SAPR4')).toBe('preferred');
    expect(kindOf('USIM6')).toBe('preferred');
    expect(kindOf('SAPR11')).toBe('unit');
    expect(kindOf('AZUL53')).toBeNull();
    expect(kindOf('AZUL97')).toBeNull();
  });
});

describe('companyCodes', () => {
  it('a unit leva às espécies da mesma raiz, que a FCA nem sempre declara', () => {
    const c = companyCodes(['ALUP11']);
    for (const x of ['ALUP11', 'ALUP3', 'ALUP4', 'ALUP5', 'ALUP6']) expect(c.has(x)).toBe(true);
    const other = companyCodes(['BHIA3', 'VVAR3']);
    for (const x of ['VVAR4', 'BHIA11']) expect(other.has(x)).toBe(true);
  });
});

describe('chain', () => {
  it('junta o código anterior da mesma espécie, e o de hoje vence no dia comum', () => {
    const cotahist = new Map([
      ['VVAR3', tradingDays(d(2020, 1, 1), [10, 11, 12])],
      ['BHIA3', tradingDays(d(2020, 1, 3), [120, 130])],
      ['VVAR4', tradingDays(d(2020, 1, 1), [99, 99, 99])],
    ]);
    const s = chain('BHIA3', ['BHIA3', 'VVAR3', 'VVAR4'], cotahist);
    expect(s.map((p) => p.close)).toEqual([10, 11, 120, 130]);
  });
});

describe('baseFactorOf', () => {
  it('mede o evento posterior pelo preço bruto contra o da fonte', () => {
    // Grupamento de 10 para 1 depois da coorte: a fonte, na base de hoje,
    // publica o fechamento de 2020 multiplicado por dez.
    const rawSessions = tradingDays(d(2020, 9, 28), [8.5, 8.6, 8.4]);
    const source = new PriceSeries({
      ticker: Ticker.parse('MGLU3'),
      points: rawSessions.map((p) => new PricePoint({ date: p.date, close: p.close * 10 })),
    });
    const f = baseFactorOf({ source, rawSessions, date: d(2020, 9, 30) });
    expectClose(f!.factor, 0.1, 1e-12);
    expect(f!.tradingDay.close).toBe(8.4);
  });

  it('sem pregão a até dez dias não há preço da data', () => {
    const rawSessions = tradingDays(d(2020, 8, 1), [5, 5]);
    const source = new PriceSeries({
      ticker: Ticker.parse('ABCD3'),
      points: [new PricePoint({ date: d(2020, 8, 1), close: 5 }), new PricePoint({ date: d(2020, 9, 30), close: 5 })],
    });
    expect(baseFactorOf({ source, rawSessions, date: d(2020, 9, 30) })).toBeNull();
  });

  it('sem fechamento da fonte no dia do pregão, recusa em vez de misturar dias', () => {
    const rawSessions = tradingDays(d(2020, 9, 30), [5]);
    const source = new PriceSeries({ ticker: Ticker.parse('ABCD3'), points: [new PricePoint({ date: d(2020, 9, 29), close: 50 })] });
    expect(baseFactorOf({ source, rawSessions, date: d(2020, 9, 30) })).toBeNull();
  });
});

describe('seriesOnDateBasis', () => {
  it('a Porta 0 volta a medir o financeiro do COTAHIST', () => {
    // A fonte ajusta o fechamento e não o volume: com o grupamento de 10 para
    // 1 depois, `fechamento × volume` da fonte sai dez vezes o negociado.
    const rawSessions: TradingDay[] = [];
    for (let i = 0; i < 30; i++) {
      rawSessions.push(new TradingDay(d(2020, 9, 1).add(new Duration({ days: i })), 8.0 + (i % 3), 100, 1e6 + 1e4 * i));
    }
    const source = new PriceSeries({
      ticker: Ticker.parse('MGLU3'),
      points: rawSessions.map((p) => new PricePoint({ date: p.date, close: p.close * 10, volume: p.tradedValue! / p.close })),
    });
    const wrongValue = EligibilityGate.medianTradedValue(source)!;
    const base = seriesOnDateBasis(source, rawSessions, 0.1);
    const right = EligibilityGate.medianTradedValue(base)!;
    const tradedValues = rawSessions.map((p) => p.tradedValue!).sort((a, b) => a - b);
    const median = (tradedValues[14]! + tradedValues[15]!) / 2;
    expectClose(wrongValue, 10 * median, 1e-3);
    expectClose(right, median, 1e-3);
    expectClose(base.points[base.points.length - 1]!.close, rawSessions[rawSessions.length - 1]!.close, 1e-12);
  });

  it('dia sem COTAHIST mantém o volume da fonte', () => {
    const source = new PriceSeries({ ticker: Ticker.parse('ABCD3'), points: [new PricePoint({ date: d(2020, 9, 1), close: 20, volume: 7 })] });
    const s = seriesOnDateBasis(source, [], 0.5);
    expect(s.points).toHaveLength(1);
    expect(s.points[0]!.close).toBe(10);
    expect(s.points[0]!.volume).toBe(7);
  });
});

describe('MarketValue.atDate', () => {
  it('soma as espécies, cada uma pelo preço do papel mais negociado dela', () => {
    const securities = new Map([
      ['ABCD3', tradingDays(d(2020, 9, 25), [10, 10], 5e5)],
      ['ABCD5', tradingDays(d(2020, 9, 25), [11, 11], 1e5)],
      ['ABCD6', tradingDays(d(2020, 9, 25), [12, 12], 9e5)],
    ]);
    const v = MarketValue.atDate({ shares: 100, commonFraction: 0.4, securities, date: d(2020, 9, 30) });
    expectClose(v!.value, 100 * (0.4 * 10 + 0.6 * 12), 1e-9);
    expect(v!.origin).toBe('especies');
  });

  it('espécie sem pregão vai pelo preço da outra', () => {
    const v = MarketValue.atDate({
      shares: 100,
      commonFraction: 0.5,
      securities: new Map([['ABCD4', tradingDays(d(2020, 9, 29), [6])]]),
      date: d(2020, 9, 30),
    });
    expectClose(v!.value, 600, 1e-9);
    expect(v!.origin).toBe('umaEspecie');
  });

  it('pregão velho não dá preço, e sem papel nenhum não há valor', () => {
    expect(
      MarketValue.atDate({
        shares: 100,
        commonFraction: 1,
        securities: new Map([['ABCD3', tradingDays(d(2020, 8, 1), [6])]]),
        date: d(2020, 9, 30),
      }),
    ).toBeNull();
  });

  it('a unit volta a medir as ações dela — a montagem antiga dava 1', () => {
    // SAPR11 é 1 ON + 4 PN. Com as duas espécies ao mesmo preço, a unit vale
    // cinco ações, e o motor tem de medir cinco.
    const shares = 1.5e9;
    const sharePrice = 5.0;
    const unitPrice = 5 * sharePrice;
    const securities = new Map([
      ['SAPR3', tradingDays(d(2020, 9, 29), [sharePrice])],
      ['SAPR4', tradingDays(d(2020, 9, 29), [sharePrice])],
    ]);
    const v = MarketValue.atDate({ shares, commonFraction: 0.2, securities, date: d(2020, 9, 30) });
    const composition = UnitCompositionCodec.parse('1 ON e 4 PN')!;
    expect(ValuationCascade.quotedUnitRatio({ sharesOutstanding: shares, marketCap: v!.value, marketPrice: unitPrice })).toBe(composition);
    // A reescala antiga: valor de mercado = contagem × preço do próprio papel.
    expect(ValuationCascade.quotedUnitRatio({ sharesOutstanding: shares, marketCap: shares * unitPrice, marketPrice: unitPrice })).toBe(1.0);
  });
});

describe('CapitalClasses', () => {
  const row = (ref: string, version: number, approval: string, on: number, pn: number, kind = 'Capital Integralizado'): Record<string, string> => ({
    Tipo_Capital: kind,
    Data_Referencia: ref,
    Versao: `${version}`,
    Data_Autorizacao_Aprovacao: approval,
    Quantidade_Acoes_Ordinarias: str(on),
    Quantidade_Acoes_Preferenciais: str(pn),
  });

  it('cada aprovação vale pela primeira declaração, na maior versão dela', () => {
    const c = CapitalClasses.fromFre([
      row('2018-01-01', 1, '2017-04-30', 40, 60),
      row('2018-01-01', 2, '2017-04-30', 50, 50),
      // O formulário seguinte repete a aprovação antiga com outra divisão.
      row('2019-01-01', 1, '2017-04-30', 10, 90),
      row('2019-01-01', 1, '2019-03-15', 100, 0),
    ]);
    expect(c.at(d(2016, 1, 1))).toBe(0.5);
    expect(c.at(d(2018, 6, 30))).toBe(0.5);
    expect(c.at(d(2019, 6, 30))).toBe(1.0);
    expect(CapitalClasses.fromJson(c.toJson()).at(d(2019, 6, 30))).toBe(1.0);
  });

  it('sem capital integralizado, lê o emitido; sem nada, não divide', () => {
    const c = CapitalClasses.fromFre([row('2020-01-01', 1, '2019-01-01', 3, 1, 'Capital Emitido')]);
    expect(c.at(d(2020, 1, 1))).toBe(0.75);
    expect(CapitalClasses.fromFre([]).at(d(2020, 1, 1))).toBeNull();
  });
});

// A leitura do texto passou ao núcleo em 20/09/2026 (item B16): ela deixou de
// ser conferência de ferramenta e virou o que o motor usa, e por isso é
// testada também em `unit-composition.test.ts`. Este caso fica porque é o que
// confere a lista inteira contra a FCA de 2024.
describe('UnitCompositionCodec.parse', () => {
  it('lê as composições declaradas na FCA de 2024', () => {
    const cases: [string, number][] = [
      ['1 ação ordinária e 4 ações preferenciais', 5],
      ['1 ON + 4 PN', 5],
      ['1 ON / 2 PN', 3],
      ['1 ON E 2 PN', 3],
      ['1 ON+ 2PN', 3],
      ['2 ações preferenciais e 1 ação ordinária', 3],
      ['1 ON e 2 PN', 3],
      ['1 PN + 3 Recibos de Subscrição', 1],
      ['1 ON e 4 PN', 5],
      ['1 KLBN3 + 4 KLBN4', 5],
      ['1 ON + 1 PN', 2],
    ];
    for (const [text, expected] of cases) expect(UnitCompositionCodec.parse(text), text).toBe(expected);
    expect(UnitCompositionCodec.parse('não se aplica')).toBeNull();
  });
});
