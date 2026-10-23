import { describe, expect, it } from 'vitest';

import {
  B3CashDividends,
  CashDividend,
  CashDividendKind,
  CashDividendsCodec,
  DateTime,
  Duration,
  type JsonObject,
  TotalReturn,
  TotalReturnIndex,
} from '../../src/core';
import { expectClose, expectDate } from './helpers';

const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

const row = (
  o: { shareClass?: string; label?: string; withInput?: string; value?: string; lot?: string; price?: string } = {},
): JsonObject => ({
  typeStock: o.shareClass ?? 'PN',
  dateApproval: '20/12/2007',
  valueCash: o.value ?? '0,32',
  ratio: o.lot ?? '1',
  corporateAction: o.label ?? 'DIVIDENDO',
  lastDatePriorEx: o.withInput ?? '20/12/2007',
  closingPricePriorExDate: o.price ?? '11,60',
  quotedPerShares: o.lot ?? '1',
});

const only = <T>(items: readonly T[]): T => {
  expect(items).toHaveLength(1);
  return items[0]!;
};

describe('Proventos da B3 — item A4', () => {
  it('lê valor, classe, rótulo e as duas datas', () => {
    // ABCB4, 20/12/2007: JCP de R$ 0,32 sobre fechamento de R$ 11,60 — os
    // 2,758621% que a própria B3 publica em `corporateActionPrice`.
    const p = only(B3CashDividends.parse([row({ label: 'JRS CAP PROPRIO' })]));
    expect(p.shareClass).toBe('PN');
    expect(p.kind).toBe(CashDividendKind.interestOnEquity);
    expectDate(p.lastDateWithRights, d(2007, 12, 20));
    expectDate(p.exDate, d(2007, 12, 21));
    expectClose(p.amount, 0.32, 1e-12);
    expectClose(p.amount / p.closeWithRights!, 0.02758621, 1e-8);
  });

  it('a data ex pula fim de semana e feriado', () => {
    expectDate(only(B3CashDividends.parse([row({ withInput: '12/09/2025' })])).exDate, d(2025, 9, 15));
    expectDate(
      only(B3CashDividends.parse([row({ withInput: '30/12/2014' })])).exDate,
      d(2015, 1, 2),
      '31/12 não tem pregão e 1º/01 é feriado',
    );
  });

  it('lote de mil vira valor por ação', () => {
    const p = only(B3CashDividends.parse([row({ value: '320,00', lot: '1000', price: '11.600,00' })]));
    expectClose(p.amount, 0.32, 1e-12);
    expectClose(p.closeWithRights!, 11.6, 1e-12);
  });

  it('preço zerado não é preço', () => {
    expect(only(B3CashDividends.parse([row({ price: '0,00' })])).closeWithRights).toBeNull();
  });

  it('recusa o que inventaria provento', () => {
    expect(
      B3CashDividends.parse([
        row({ value: '0,00' }),
        row({ label: 'BONIFICACAO' }),
        row({ withInput: '' }),
        row({ shareClass: '' }),
        'isto não é linha',
      ]),
    ).toEqual([]);
  });

  it('só o juro sobre capital próprio perde o imposto retido', () => {
    const jcp = only(B3CashDividends.parse([row({ label: 'JRS CAP PROPRIO' })]));
    const div = only(B3CashDividends.parse([row()]));
    expectClose(jcp.netAmount, 0.32 * 0.85, 1e-12);
    expectClose(div.netAmount, 0.32, 1e-12);
  });

  it('classe pelo sufixo do ticker', () => {
    expect(B3CashDividends.shareClassOf('PETR3')).toBe('ON');
    expect(B3CashDividends.shareClassOf('PETR4')).toBe('PN');
    expect(B3CashDividends.shareClassOf('USIM5')).toBe('PNA');
    expect(B3CashDividends.shareClassOf('TAEE11')).toBe('UNT');
    expect(B3CashDividends.shareClassOf('XPTO9')).toBeNull();
  });
});

describe('Retorno total', () => {
  const dividends = [
    new CashDividend({
      shareClass: 'PN',
      kind: CashDividendKind.dividend,
      lastDateWithRights: d(2024, 3, 1),
      exDate: d(2024, 3, 4),
      amount: 1.0,
    }),
    new CashDividend({
      shareClass: 'PN',
      kind: CashDividendKind.interestOnEquity,
      lastDateWithRights: d(2024, 9, 2),
      exDate: d(2024, 9, 3),
      amount: 2.0,
    }),
  ];

  it('reinveste no fechamento da data ex, provento a provento', () => {
    const r = TotalReturn.factor({
      dividends,
      from: d(2024, 1, 1),
      until: d(2024, 12, 31),
      closeOnExDate: (x) => (x.month === 3 ? 20.0 : 40.0),
    });
    expectClose(r.factor, (1 + 1 / 20) * (1 + (2 * 0.85) / 40), 1e-12);
    expect(r.applied).toBe(2);
  });

  it('a janela é (de, até]: data ex no primeiro dia não entra', () => {
    const r = TotalReturn.factor({
      dividends,
      from: d(2024, 3, 4),
      until: d(2024, 9, 3),
      closeOnExDate: () => 40.0,
      net: false,
    });
    expect(r.applied).toBe(1);
    expectClose(r.factor, 1 + 2 / 40, 1e-12);
  });

  it('provento sem pregão nem preço com direito fica de fora e é contado', () => {
    const r = TotalReturn.factor({
      dividends,
      from: d(2024, 1, 1),
      until: d(2024, 12, 31),
      closeOnExDate: (x) => (x.month === 3 ? null : 40.0),
    });
    expect(r.applied).toBe(1);
    expect(r.withoutPrice).toBe(1);
  });

  it('sem pregão, o preço com direito da B3 menos o provento', () => {
    const withPrice = [
      new CashDividend({
        shareClass: 'ON',
        kind: CashDividendKind.dividend,
        lastDateWithRights: d(2019, 3, 1),
        exDate: d(2019, 3, 5),
        amount: 1.0,
        closeWithRights: 21.0,
      }),
    ];
    const r = TotalReturn.factor({
      dividends: withPrice,
      from: d(2019, 1, 1),
      until: d(2019, 12, 31),
      closeOnExDate: () => null,
    });
    expectClose(r.factor, 1 + 1 / 20, 1e-12);
    expect(r.approximated).toBe(1);
    expect(r.withoutPrice).toBe(0);
  });
});

describe('proventos da mesma data ex', () => {
  // Dividendo e juro sobre capital próprio no mesmo dia: o fator é o do
  // total, sem o termo cruzado de um rendendo sobre o outro.
  const dividend = (value: number, kind: CashDividendKind): CashDividend =>
    new CashDividend({
      shareClass: 'PN',
      kind,
      lastDateWithRights: d(2024, 6, 3),
      exDate: d(2024, 6, 4),
      amount: value,
      closeWithRights: 24.0,
    });
  const sameDay = [dividend(2.0, CashDividendKind.dividend), dividend(2.0, CashDividendKind.interestOnEquity)];

  it('com o pregão ex, 1 + (D₁ + D₂)/P_ex', () => {
    const r = TotalReturn.factor({
      dividends: sameDay,
      from: d(2024, 1, 1),
      until: d(2024, 12, 31),
      closeOnExDate: () => 20.0,
      net: false,
    });
    expectClose(r.factor, 1 + 4 / 20, 1e-12, 'o produto separado daria 1,21, com 0,01 de termo cruzado');
    expect(r.applied).toBe(2);
  });

  it('sem o pregão, o preço ex sai do com direito menos os dois', () => {
    const r = TotalReturn.factor({
      dividends: sameDay,
      from: d(2024, 1, 1),
      until: d(2024, 12, 31),
      closeOnExDate: () => null,
      net: false,
    });
    // P_ex = 24 − 2 − 2 = 20.
    expectClose(r.factor, 1 + 4 / 20, 1e-12);
    expect(r.approximated).toBe(2);
  });

  it('o imposto do juro sai do que se recebe, não da queda do preço', () => {
    const r = TotalReturn.factor({
      dividends: sameDay,
      from: d(2024, 1, 1),
      until: d(2024, 12, 31),
      closeOnExDate: () => 20.0,
    });
    expectClose(r.factor, 1 + (2 + 2 * 0.85) / 20, 1e-12);
  });
});

describe('Índice de retorno total — o beta da decisão 89', () => {
  const div = (ex: DateTime, value: number, withInput: number, kind = CashDividendKind.dividend): CashDividend =>
    new CashDividend({
      shareClass: 'ON',
      kind,
      lastDateWithRights: ex.subtract(new Duration({ days: 1 })),
      exDate: ex,
      amount: value,
      closeWithRights: withInput,
    });

  it('na data ex, o retorno é o do preço mais o rendimento com direito', () => {
    const r = TotalReturnIndex.build({
      dates: [d(2024, 3, 1), d(2024, 3, 4), d(2024, 3, 5)],
      closes: [20.0, 19.0, 19.38],
      dividends: [div(d(2024, 3, 4), 1.0, 20.0)],
    });
    expectClose(r.index[1]!, 19 / 20 + 1 / 20, 1e-12, 'queda do dia ex coberta pelo provento: retorno total zero');
    expectClose(r.index[2]!, (r.index[1]! * 19.38) / 19, 1e-12);
    expect(r.applied).toBe(1);
  });

  it('a série ajustada por desdobramento dá o mesmo índice', () => {
    // Desdobramento de 1 para 2 depois do período: a fonte divide o passado
    // por dois, e o rendimento, que é bruto sobre bruto, não muda.
    const raw = TotalReturnIndex.build({
      dates: [d(2024, 3, 1), d(2024, 3, 4)],
      closes: [20.0, 19.0],
      dividends: [div(d(2024, 3, 4), 1.0, 20.0)],
    });
    const adjusted = TotalReturnIndex.build({
      dates: [d(2024, 3, 1), d(2024, 3, 4)],
      closes: [10.0, 9.5],
      dividends: [div(d(2024, 3, 4), 1.0, 20.0)],
    });
    expectClose(adjusted.index[adjusted.index.length - 1]!, raw.index[raw.index.length - 1]!, 1e-12);
  });

  it('data ex sem pregão cai no pregão seguinte; antes da série, fora', () => {
    const r = TotalReturnIndex.build({
      dates: [d(2024, 3, 1), d(2024, 3, 5)],
      closes: [20.0, 19.0],
      dividends: [div(d(2024, 2, 1), 5.0, 25.0), div(d(2024, 3, 4), 1.0, 20.0)],
    });
    expect(r.applied).toBe(1);
    expectClose(r.index[r.index.length - 1]!, 19 / 20 + 0.05, 1e-12);
  });

  it('sem preço com direito, o provento não entra e é contado', () => {
    const r = TotalReturnIndex.build({
      dates: [d(2024, 3, 1), d(2024, 3, 4)],
      closes: [20.0, 19.0],
      dividends: [
        new CashDividend({
          shareClass: 'ON',
          kind: CashDividendKind.dividend,
          lastDateWithRights: d(2024, 3, 1),
          exDate: d(2024, 3, 4),
          amount: 1.0,
        }),
      ],
    });
    expect(r.withoutPrice).toBe(1);
    expectClose(r.index[r.index.length - 1]!, 0.95, 1e-12);
  });
});

describe('Pacote de proventos', () => {
  it('ida e volta, e a classe separa os papéis do emissor', () => {
    const on = B3CashDividends.parse([row({ shareClass: 'ON' })]);
    const pn = B3CashDividends.parse([row({ shareClass: 'PN', label: 'JRS CAP PROPRIO', price: '0,00' })]);
    const parsed = CashDividendsCodec.decode(
      CashDividendsCodec.encode(new Map([['ABCB', [...on, ...pn]]]), { generatedAt: d(2026, 9, 14) }),
    );
    const ofPn = only(CashDividendsCodec.forTicker(parsed, 'ABCB4'));
    expect(ofPn.kind).toBe(CashDividendKind.interestOnEquity);
    expect(ofPn.closeWithRights).toBeNull();
    expectClose(only(CashDividendsCodec.forTicker(parsed, 'ABCB3')).amount, 0.32, 1e-12);
    expect(CashDividendsCodec.forTicker(parsed, 'PETR4')).toEqual([]);
  });

  it('versão desconhecida não é lida', () => {
    expect(CashDividendsCodec.decode({ versao: 99, emissores: {} }).size).toBe(0);
  });
});
