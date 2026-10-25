import { describe, expect, it } from 'vitest';

import { CorporateEvents, DateTime, type FreRow, RawQuote, ShareCountHistory, ShareCountSource } from '../../src/core';
import { expectClose, expectDate } from './helpers';

const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

const cap = (
  kind: string,
  approval: string,
  total: string,
  options: { reference?: string; version?: string; id?: string } = {},
): FreRow => ({
  ID_Documento: options.id ?? '',
  Tipo_Capital: kind,
  Data_Autorizacao_Aprovacao: approval,
  Data_Referencia: options.reference ?? '2022-12-31',
  Versao: options.version ?? '1',
  Quantidade_Total_Acoes: total,
});

const series = (v: readonly (readonly [DateTime, number, number])[]): RawQuote[] =>
  v.map(([date, close, dist]) => new RawQuote(date, close, dist));

describe('Contagem por data do FRE — item A3.4', () => {
  it('cada aprovação vale até a seguinte', () => {
    const h = ShareCountHistory.fromFre([
      cap('Capital Integralizado', '2012-04-30', '100000000'),
      cap('Capital Integralizado', '2018-06-15', '200000000'),
      cap('Capital Autorizado', '2010-01-01', '999999999'),
    ]);
    expect(h.points).toHaveLength(2);
    expect(h.at(d(2011, 1, 1))).toBeNull();
    expectClose(h.at(d(2015, 9, 30))!.total, 1e8, 1e-6);
    expectClose(h.at(d(2018, 6, 15))!.total, 2e8, 1e-6);
  });

  // O caso da CPFL Transmissão: grupamento de 40 para 1 em 2016, sem capital
  // novo. O formulário de 2017 repete a aprovação de 2010 com a contagem de
  // depois do grupamento.
  const forms = [
    cap('Capital Integralizado', '2010-04-30', '4000', { reference: '2011-01-01' }),
    cap('Capital Integralizado', '2010-04-30', '100', { reference: '2017-01-01', id: 'doc2017' }),
  ];

  it('grupamento sem capital novo: a contagem da época vale até o evento', () => {
    const h = ShareCountHistory.fromFre(forms, { events: [{ date: d(2016, 4, 29), totalAfter: 100 }] });
    expectClose(h.at(d(2012, 12, 31))!.total, 4000, 1e-9);
    expectClose(h.at(d(2016, 5, 2))!.total, 100, 1e-9);
    expect(h.at(d(2016, 5, 2))!.source).toBe(ShareCountSource.shareEvent);
  });

  it('evento não declarado entra no recebimento do formulário que o mostra', () => {
    const h = ShareCountHistory.fromFre(forms, { receivedOn: new Map([['doc2017', d(2017, 5, 31)]]) });
    expectClose(h.at(d(2016, 12, 31))!.total, 4000, 1e-9);
    expectClose(h.at(d(2017, 6, 1))!.total, 100, 1e-9);
    expect(h.at(d(2017, 6, 1))!.source).toBe(ShareCountSource.filingCorrection);
  });

  it('formulário que a série explica não corrige nada', () => {
    const h = ShareCountHistory.fromFre(forms, {
      events: [{ date: d(2016, 4, 29), totalAfter: 100 }],
      receivedOn: new Map([['doc2017', d(2017, 5, 31)]]),
    });
    expect(h.points.filter((p) => p.source === ShareCountSource.filingCorrection)).toEqual([]);
  });

  it('na mesma referência, a maior versão', () => {
    const h = ShareCountHistory.fromFre([
      cap('Capital Integralizado', '2018-06-15', '205', { version: '1' }),
      cap('Capital Integralizado', '2018-06-15', '210', { version: '2' }),
    ]);
    expect(h.points).toHaveLength(1);
    expectClose(h.points[0]!.total, 210, 1e-9);
  });

  it('sem integralizado, recua ao emitido; sem nenhum, série vazia', () => {
    const issued = ShareCountHistory.fromFre([cap('Capital Emitido', '2024-05-01', '300')]).points;
    expect(issued).toHaveLength(1);
    expectClose(issued[0]!.total, 300, 1e-9);
    expect(ShareCountHistory.fromFre([cap('Capital Autorizado', '2024-05-01', '300')]).points).toEqual([]);
  });
});

describe('Data ex de evento declarado — item A3.4', () => {
  it('desdobramento de 1 para 10: o preço se divide no pregão certo', () => {
    const ev = CorporateEvents.locate(
      series([
        [d(2019, 3, 1), 50.0, 100],
        [d(2019, 3, 29), 51.0, 100],
        [d(2019, 4, 1), 5.12, 101],
        [d(2019, 4, 2), 5.1, 101],
      ]),
      { factor: 10, approvedOn: d(2019, 3, 15) },
    )!;
    expectDate(ev.exDate, d(2019, 4, 1));
    expectClose(ev.factor, 10, 1e-12);
  });

  it('salto antes da aprovação não é o evento', () => {
    const ev = CorporateEvents.locate(
      series([
        [d(2019, 3, 1), 50.0, 100],
        [d(2019, 3, 4), 5.0, 101],
        [d(2019, 3, 20), 5.0, 101],
      ]),
      { factor: 10, approvedOn: d(2019, 3, 15) },
    );
    expect(ev).toBeNull();
  });

  it('bonificação pequena sai pela troca de DISMES', () => {
    const ev = CorporateEvents.locate(
      series([
        [d(2020, 5, 4), 20.0, 200],
        [d(2020, 5, 5), 19.1, 200],
        [d(2020, 5, 6), 18.3, 201],
      ]),
      { factor: 1.05, approvedOn: d(2020, 4, 30) },
    )!;
    expectDate(ev.exDate, d(2020, 5, 6));
  });

  it('grupamento de papel em crise: o dia despenca e o fator ainda casa', () => {
    // Grupamento de 25 para 1 com o papel caindo 15% no mesmo pregão: a
    // razão sai 21,25, fora da folga de 6%, e a troca de DISMES localiza.
    const ev = CorporateEvents.locate(
      series([
        [d(2016, 5, 2), 0.04, 300],
        [d(2016, 5, 20), 0.04, 300],
        [d(2016, 5, 23), 0.85, 301],
      ]),
      { factor: 0.04, approvedOn: d(2016, 4, 29) },
    )!;
    expectDate(ev.exDate, d(2016, 5, 23));
  });

  it('troca de DISMES com razão distante do fator não é o evento', () => {
    const ev = CorporateEvents.locate(
      series([
        [d(2016, 5, 2), 0.04, 300],
        [d(2016, 5, 3), 0.038, 301],
      ]),
      { factor: 0.04, approvedOn: d(2016, 4, 29) },
    );
    expect(ev, 'dividendo, e não grupamento').toBeNull();
  });

  it('fora da janela, não localiza', () => {
    const ev = CorporateEvents.locate(
      series([
        [d(2021, 1, 4), 30.0, 10],
        [d(2022, 3, 1), 30.0, 10],
        [d(2022, 3, 2), 15.0, 11],
      ]),
      { factor: 2, approvedOn: d(2021, 1, 10) },
    );
    expect(ev).toBeNull();
  });
});
