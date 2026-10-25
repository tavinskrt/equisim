// Os eventos de ações e as emissões por valor das coortes (itens B28 a B30).
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { DateTime, Duration, Money, PricePoint, PriceSeries, ShareEvent, ShareIssue, Ticker } from '../../src/core';
import { TradingDay } from '../../tool/b3/dividends';
import { issuancesWithoutEvent, notAdjustedBySource, sharesWithEvents } from '../../tool/cohorts/share-events';
import { FreIssuances } from '../../tool/cvm/fre-issues';
import { expectDate } from '../core/helpers';

const t = Ticker.parse('ABCD3');

/**
 * Pregões úteis de março e abril de 2024: o bruto cai pelo [factor] a partir
 * de [ex]; a fonte cai junto quando [adjusted] é falso, e fica contínua quando
 * é verdadeiro.
 */
function security(args: { ex: DateTime; factor: number; adjusted: boolean }): { rawSessions: TradingDay[]; source: PriceSeries } {
  const rawSessions: TradingDay[] = [];
  const pts: PricePoint[] = [];
  let d = DateTime.utc(2024, 3, 1);
  while (d.isBefore(DateTime.utc(2024, 5, 1))) {
    if (d.weekday <= 5) {
      const after = !d.isBefore(args.ex);
      const raw = after ? 20 / args.factor : 20.0;
      rawSessions.push(new TradingDay(d, raw, after ? 2 : 1));
      const source = args.adjusted ? 20 / args.factor : raw;
      pts.push(new PricePoint({ date: DateTime.local(d.year, d.month, d.day), close: source }));
    }
    d = d.add(new Duration({ days: 1 }));
  }
  return { rawSessions, source: new PriceSeries({ ticker: t, points: pts }) };
}

const ev = (ex: DateTime, f: number): ShareEvent => new ShareEvent({ exDate: ex, factor: f, observedRatio: 1 / f });

const ex = DateTime.utc(2024, 4, 2);

describe('o que a fonte não ajustou', () => {
  it('bonificação que a fonte deixou como veio sai, com o dia do salto', () => {
    const p = security({ ex, factor: 1.1, adjusted: false });
    const without = notAdjustedBySource(p.source, p.rawSessions, [ev(ex, 1.1)]);
    expect(without).toHaveLength(1);
    expectDate(without[0]!.exDate, DateTime.utc(2024, 4, 2));
  });

  it('evento que a fonte ajustou não sai', () => {
    const p = security({ ex, factor: 2, adjusted: true });
    expect(notAdjustedBySource(p.source, p.rawSessions, [ev(ex, 2)])).toEqual([]);
  });

  it('evento mal localizado a até dez dias é achado no salto', () => {
    const p = security({ ex, factor: 1.25, adjusted: false });
    const without = notAdjustedBySource(p.source, p.rawSessions, [ev(DateTime.utc(2024, 3, 28), 1.25)]);
    expect(without).toHaveLength(1);
    expectDate(without[0]!.exDate, DateTime.utc(2024, 4, 2));
  });

  it('sem salto que case, nada sai — ajustar no dia errado inventaria um', () => {
    const p = security({ ex, factor: 1.0, adjusted: false });
    expect(notAdjustedBySource(p.source, p.rawSessions, [ev(ex, 1.5)])).toEqual([]);
  });
});

describe('a contagem que o FRE ainda não absorveu', () => {
  const count = [{ since: DateTime.utc(2020, 1, 1), shares: 1000.0 }];

  it('parada desde antes do desdobramento, recebe o fator', () => {
    const r = sharesWithEvents(count, DateTime.local(2024, 6, 30), [ev(DateTime.utc(2024, 4, 16), 2)]);
    expect(r.shares).toBe(2000);
    expect(r.applied).toHaveLength(1);
  });

  it('já absorvido pelo fator, fica como está', () => {
    const r = sharesWithEvents([...count, { since: DateTime.utc(2024, 3, 10), shares: 2000.0 }], DateTime.local(2024, 6, 30), [
      ev(DateTime.utc(2024, 4, 16), 2),
    ]);
    expect(r.shares).toBe(2000);
    expect(r.applied).toEqual([]);
  });

  it('mudou depois do evento por outro fator: a conta não reconstrói', () => {
    const r = sharesWithEvents([...count, { since: DateTime.utc(2024, 5, 1), shares: 1300.0 }], DateTime.local(2024, 6, 30), [
      ev(DateTime.utc(2024, 4, 16), 2),
    ]);
    expect(r.shares).toBe(1300);
  });

  it('o formulário tratou o evento junto com outra operação: fica', () => {
    // A AERI3 registrou o grupamento de 20 para 1 antes da data ex e junto
    // com uma emissão, com razão 0,081; aplicar de novo tirava 95% do valor.
    const r = sharesWithEvents(
      [
        { since: DateTime.utc(2020, 12, 11), shares: 766.21e6 },
        { since: DateTime.utc(2024, 4, 11), shares: 62.12e6 },
      ],
      DateTime.local(2024, 6, 30),
      [ev(DateTime.utc(2024, 5, 14), 0.05)],
    );
    expect(r.shares).toBe(62.12e6);
    expect(r.applied).toEqual([]);
  });

  it('evento anterior à contagem, ou posterior à data, não entra', () => {
    const r = sharesWithEvents(count, DateTime.local(2024, 6, 30), [ev(DateTime.utc(1989, 9, 15), 10), ev(DateTime.utc(2024, 7, 1), 2)]);
    expect(r.shares).toBe(1000);
  });
});

describe('a variação do capital que nenhum evento explica', () => {
  const cand = [
    {
      issuance: new ShareIssue({ date: DateTime.utc(2024, 3, 20), amount: Money.fromReais(500), shares: 100 }),
      ratio: 1.1,
    },
  ];

  it('com o salto e a troca de DISMES no preço, é bonificação', () => {
    const p = security({ ex, factor: 1.1, adjusted: false });
    expect(issuancesWithoutEvent(cand, p.rawSessions, [])).toEqual([]);
  });

  it('com evento de mesmo fator no registro, também', () => {
    const p = security({ ex, factor: 1.0, adjusted: false });
    expect(issuancesWithoutEvent(cand, p.rawSessions, [ev(DateTime.utc(2024, 5, 7), 1.1)])).toEqual([]);
  });

  it('sem nenhum dos dois, sai como emissão sem valor declarado', () => {
    const p = security({ ex, factor: 1.0, adjusted: false });
    const r = issuancesWithoutEvent(cand, p.rawSessions, []);
    expect(r).toHaveLength(1);
    expect(r[0]!.amount.equals(Money.fromReais(500))).toBe(true);
    expect(r[0]!.declared).toBe(false);
  });
});

describe('as emissões por valor do FRE', () => {
  let folder = '';

  const writeFile = (name: string, rows: readonly string[]): void => writeFileSync(join(folder, name), rows.join('\n'), 'latin1');

  const header =
    'CNPJ_Companhia;Data_Referencia;Versao;ID_Documento;' +
    'Nome_Companhia;ID_Capital_Social_Aumento;Data_Deliberacao;' +
    'Orgao_Deliberacao_Aumento;Data_Emissao;Valor_Total_Emissao;' +
    'Tipo_Subscricao;Quantidade_Acoes_Ordinarias;' +
    'Quantidade_Acoes_Preferenciais;Quantidade_Total_Acoes;' +
    'Subscricao_Capital_Anterior;Fator_Cotacao;Preco_Emissao;' +
    'Criterio_Determinacao_Preco_Emissao;Forma_Integralizacao';

  beforeEach(() => {
    folder = mkdtempSync(join(tmpdir(), 'fre_'));
    writeFile('fre_cia_aberta_2025.csv', [
      'CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;CD_CVM;CATEG_DOC;ID_DOC;DT_RECEB;LINK_DOC',
      '1;2025-01-01;1;X;1;FRE;D1;2025-05-30;',
      '1;2025-01-01;2;X;1;FRE;D2;2026-03-10;',
    ]);
    writeFile('fre_cia_aberta_capital_social_aumento_2025.csv', [
      header,
      // A primeira versão: a emissão ainda com R$ 1,0 bilhão, repetida.
      '1;2025-01-01;1;D1;X;a1;2025-03-01;AGE;2025-03-01;1000000000;Subscrição particular;100;0;100;0;R$;10;;Em dinheiro',
      '1;2025-01-01;1;D1;X;a2;2025-03-01;AGE;2025-03-01;1000000000;Subscrição particular;100;0;100;0;R$;10;;Em dinheiro',
      // A segunda versão relista com outro identificador e o valor final, e
      // traz uma bonificação e uma capitalização sem ação nova.
      '1;2025-01-01;2;D2;X;b1;2025-03-01;AGE;2025-03-01;1300000000;Subscrição particular;100;0;100;0;R$;13;;Em dinheiro',
      '1;2025-01-01;2;D2;X;b2;2025-12-10;AGE;2025-12-10;500;Subscrição particular;1000;0;1000;0;R$;0.5;;Ações Bonificadas',
      '1;2025-01-01;2;D2;X;b3;2026-01-05;AGE;;700;Sem emissão de ações;0;0;0;0;R$;0;;',
    ]);
  });

  afterEach(() => rmSync(folder, { recursive: true, force: true }));

  it('vale o formulário mais recente recebido até a data, inteiro', () => {
    const fre = FreIssuances.read(folder)!;
    expect(fre.known('1', DateTime.local(2025, 1, 1)), 'nenhum formulário recebido ainda').toEqual([]);
    const first = fre.known('1', DateTime.local(2025, 6, 1));
    expect(first, 'a mesma emissão repetida no formulário entra uma vez').toHaveLength(1);
    expect(first[0]!.amount.equals(Money.fromReais(1e9))).toBe(true);
    const second = fre.known('1', DateTime.local(2026, 9, 1));
    // A versão nova relista com outro identificador: somar as duas contaria a
    // emissão duas vezes; bonificação e capitalização sem ação nova saem.
    expect(second.map((e) => e.amount.reais)).toEqual([1.3e9]);
  });
});
