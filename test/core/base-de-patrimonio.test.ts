// Sem o par VPA × contagem, a base de patrimônio é o PL da demonstração
// (item B47).
//
// A fonte de mercado devolve, para Fleury, Copasa e Armac, o VPA vazio e a
// contagem do exercício zerada; a mescla da decisão 81 não tinha por onde
// dividir, e a elegibilidade recusava como insolvente quem tinha bilhões de
// patrimônio publicado.
import { expect, it } from 'vitest';

import { FundamentalsSnapshot, Ticker } from '../../src/core';
import { day } from './helpers';

function year(a: { y: number; bookValuePerShare?: number; count?: number; pl?: number }): FundamentalsSnapshot {
  return new FundamentalsSnapshot({
    ticker: Ticker.parse('BASE3'),
    fiscalPeriodEnd: day(a.y, 12, 31),
    bookValuePerShare: a.bookValuePerShare ?? null,
    sharesOutstandingAsOf: a.count ?? null,
    totalStockholderEquity: a.pl ?? null,
  });
}

it('com o par, vale o produto, como antes', () => {
  expect(year({ y: 2025, bookValuePerShare: 4, count: 100, pl: 999 }).equityBookValue).toBe(400);
});

it('sem o par, vale o PL da demonstração', () => {
  expect(year({ y: 2025, count: 0, pl: 5096268000 }).equityBookValue).toBe(5096268000);
  expect(year({ y: 2025, bookValuePerShare: 4, pl: 800 }).equityBookValue).toBe(800);
});

it('VPA negativo continua sendo insolvência, mesmo com PL publicado', () => {
  expect(year({ y: 2025, bookValuePerShare: -1, count: 100, pl: 500 }).equityBookValue).toBeNull();
});

it('sem nada, continua sem base', () => {
  expect(year({ y: 2025, count: 0 }).equityBookValue).toBeNull();
  expect(year({ y: 2025, pl: -300 }).equityBookValue).toBeNull();
});
