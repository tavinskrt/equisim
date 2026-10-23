// O cache em arquivo das ferramentas (`tool/lib/sqlite-cache.ts`) contra o
// cache do navegador (`CacheDatabase`).
//
// Os repositórios do aplicativo leem e gravam pelo contrato `MarketCache`, e as
// ferramentas de validação montam **os mesmos repositórios** sobre o SQLite. Se
// os dois armazenamentos responderem diferente à mesma sequência de operações,
// a medição deixa de ser a do código entregue. Por isso cada caso roda nos
// dois e compara as respostas, em vez de fixar a resposta de um só.
import { afterEach, describe, expect, it } from 'vitest';

import { Duration } from '../../src/core';
import { CacheDatabase, type MarketCache } from '../../src/data/cache/cache-database';
import { MemoryKeyValueStore } from '../../src/data/cache/key-value-store';
import { SqliteCacheDatabase } from '../../tool/lib/sqlite-cache';

/** Relógio controlado, em segundos inteiros: o SQLite grava o carimbo em segundos. */
class Clock {
  ms = 1_700_000_000_000;
  readonly now = (): number => this.ms;
}

const opened: SqliteCacheDatabase[] = [];
afterEach(() => {
  for (const db of opened.splice(0)) db.close();
});

function both(clock: Clock, options: { frozen?: boolean } = {}): { name: string; cache: MarketCache }[] {
  const sqlite = new SqliteCacheDatabase(':memory:', { now: clock.now, frozen: options.frozen ?? false });
  opened.push(sqlite);
  return [
    { name: 'navegador', cache: new CacheDatabase(new MemoryKeyValueStore(), clock.now) },
    { name: 'sqlite', cache: sqlite },
  ];
}

/** Roda [scenario] nos dois armazenamentos e devolve as duas respostas. */
async function compare<T>(scenario: (cache: MarketCache, clock: Clock) => Promise<T>): Promise<{ browser: T; sqlite: T }> {
  const results: T[] = [];
  for (const kind of ['navegador', 'sqlite']) {
    const clock = new Clock();
    const cache = both(clock).find((c) => c.name === kind)!.cache;
    results.push(await scenario(cache, clock));
  }
  return { browser: results[0]!, sqlite: results[1]! };
}

describe('validade', () => {
  it('recurso nunca buscado não está fresco; tocado, fica até o fim da validade', async () => {
    const ttl = new Duration({ hours: 1 });
    const { browser, sqlite } = await compare(async (cache, clock) => {
      const out: boolean[] = [await cache.isFresh('k', ttl)];
      await cache.touch('k');
      out.push(await cache.isFresh('k', ttl));
      clock.ms += 59 * 60 * 1000;
      out.push(await cache.isFresh('k', ttl));
      clock.ms += 60 * 1000;
      out.push(await cache.isFresh('k', ttl));
      await cache.touch('k');
      out.push(await cache.isFresh('k', ttl));
      await cache.invalidate('k');
      out.push(await cache.isFresh('k', ttl));
      return out;
    });
    expect(browser).toEqual([false, true, true, false, true, false]);
    expect(sqlite).toEqual(browser);
  });

  it('o cache congelado vale como fresco para sempre, e só o que falta vai à rede', async () => {
    const clock = new Clock();
    const [, frozen] = both(clock, { frozen: true });
    const ttl = new Duration({ hours: 1 });
    expect(await frozen!.cache.isFresh('k', ttl)).toBe(false);
    await frozen!.cache.touch('k');
    clock.ms += 365 * 24 * 3600 * 1000;
    expect(await frozen!.cache.isFresh('k', ttl)).toBe(true);
  });
});

describe('linhas', () => {
  it('cotações: intervalo fechado, ordem de data e regravação do mesmo pregão', async () => {
    const { browser, sqlite } = await compare(async (cache) => {
      await cache.upsertPrices('PETR4', [
        { date: '2024-01-03', close: 31, adjustedClose: 30.5, volume: 1000 },
        { date: '2024-01-02', close: 30, adjustedClose: null, volume: null },
        { date: '2024-01-04', close: 32, adjustedClose: 31.5, volume: 2000 },
      ]);
      await cache.upsertPrices('VALE3', [{ date: '2024-01-03', close: 70, adjustedClose: 69, volume: 5 }]);
      await cache.upsertPrices('PETR4', [{ date: '2024-01-03', close: 31.2, adjustedClose: 30.7, volume: 1100 }]);
      const range = await cache.pricesIn('PETR4', '2024-01-02', '2024-01-03');
      const all = await cache.pricesIn('PETR4', '2000-01-01', '2100-01-01');
      await cache.deletePricesOf('PETR4');
      const afterDelete = await cache.pricesIn('PETR4', '2000-01-01', '2100-01-01');
      const other = await cache.pricesIn('VALE3', '2000-01-01', '2100-01-01');
      return { range, all, afterDelete, other };
    });
    expect(browser.range.map((p) => p.date)).toEqual(['2024-01-02', '2024-01-03']);
    expect(browser.range[1]!.close).toBe(31.2);
    expect(browser.afterDelete).toEqual([]);
    expect(sqlite).toEqual(browser);
  });

  it('exercícios: campo ausente fica vazio, e o mesmo exercício é regravado', async () => {
    const { browser, sqlite } = await compare(async (cache) => {
      await cache.upsertFundamentals('PETR4', [
        { fiscalPeriodEnd: '2023-12-31', totalRevenue: 500, netIncome: 120 },
        { fiscalPeriodEnd: '2022-12-31', totalRevenue: 450, ebit: 90 },
      ]);
      await cache.upsertFundamentals('PETR4', [{ fiscalPeriodEnd: '2023-12-31', totalRevenue: 510 }]);
      return cache.fundamentalsOf('PETR4');
    });
    expect(browser.map((f) => f.fiscalPeriodEnd)).toEqual(['2022-12-31', '2023-12-31']);
    expect(browser[1]!.totalRevenue).toBe(510);
    expect(sqlite).toEqual(browser);
  });

  it('perfil e séries macroeconômicas', async () => {
    const { browser, sqlite } = await compare(async (cache) => {
      const missing = await cache.profileOf('PETR4');
      await cache.upsertProfile('PETR4', { name: 'Petrobras', sectorKey: 'energy', sectorLabel: 'Energia', industry: null });
      await cache.upsertProfile('PETR4', { name: 'Petrobras PN', sectorKey: 'energy', sectorLabel: 'Energia', industry: 'Petróleo' });
      const profile = await cache.profileOf('PETR4');
      await cache.upsertMacro(12, [
        { date: '2024-01-03', value: 0.0004 },
        { date: '2024-01-02', value: 0.00041 },
      ]);
      await cache.upsertMacro(433, [{ date: '2024-01-01', value: 0.005 }]);
      await cache.upsertMacro(12, [{ date: '2024-01-03', value: 0.00042 }]);
      const macro = await cache.macroIn(12, '2024-01-01', '2024-12-31');
      return { missing, profile, macro };
    });
    expect(browser.missing).toBeNull();
    expect(browser.profile?.industry).toBe('Petróleo');
    expect(browser.macro).toEqual([
      { date: '2024-01-02', value: 0.00041 },
      { date: '2024-01-03', value: 0.00042 },
    ]);
    expect(sqlite).toEqual(browser);
  });
});
