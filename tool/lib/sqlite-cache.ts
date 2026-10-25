import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import type { Duration } from '../../src/core';
import {
  CACHED_FUNDAMENTAL_FIELDS,
  type CachedFundamentals,
  type CachedMacroRate,
  type CachedPrice,
  type CachedProfile,
  type FundamentalsUpsert,
  type MarketCache,
} from '../../src/data/cache/cache-database';

/** `sharesOutstandingAsOf` → `shares_outstanding_as_of`, como o drift nomeava. */
const snake = (field: string) => field.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);

const FUNDAMENTAL_COLUMNS = CACHED_FUNDAMENTAL_FIELDS.map(snake);

/**
 * O cache das ferramentas, em SQLite **com as tabelas do cache do aplicativo
 * Flutter** — `cached_prices`, `cached_fundamentals_table`, `cached_profiles`,
 * `cached_macro_rates` e `cache_entries`, colunas em `snake_case` e
 * `fetched_at` em segundos desde a época, como o drift gravava.
 *
 * A compatibilidade é o ponto: o `validation_cache.sqlite` e o
 * `data/gabarito/cache.sqlite` que as execuções em Dart deixaram continuam
 * valendo, e a entrada congelada do gabarito (decisão 152) não precisa ser
 * baixada de novo — baixar de novo é justamente o que a descongelaria.
 *
 * Usa o `node:sqlite` embutido no Node 22, sem dependência nova.
 */
export class SqliteCacheDatabase implements MarketCache {
  private readonly db: DatabaseSync;

  /**
   * - [path]: arquivo do banco; o diretório é criado se faltar.
   * - [frozen]: toda entrada presente vale como fresca, e a execução só vai à
   *   rede pelo que falta — é o que congela a entrada do gabarito.
   * - [now]: relógio do controle de validade, em milissegundos.
   */
  constructor(
    path: string,
    private readonly options: { frozen?: boolean; now?: () => number } = {},
  ) {
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS cached_prices (
        ticker TEXT NOT NULL, date TEXT NOT NULL, close REAL NOT NULL,
        adjusted_close REAL NULL, volume REAL NULL,
        PRIMARY KEY (ticker, date));
      CREATE TABLE IF NOT EXISTS cached_fundamentals_table (
        ticker TEXT NOT NULL, fiscal_period_end TEXT NOT NULL,
        ${FUNDAMENTAL_COLUMNS.map((c) => `${c} REAL NULL`).join(', ')},
        PRIMARY KEY (ticker, fiscal_period_end));
      CREATE TABLE IF NOT EXISTS cached_profiles (
        ticker TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        sector_key TEXT NULL, sector_label TEXT NULL, industry TEXT NULL);
      CREATE TABLE IF NOT EXISTS cached_macro_rates (
        series_id INTEGER NOT NULL, date TEXT NOT NULL, value REAL NOT NULL,
        PRIMARY KEY (series_id, date));
      CREATE TABLE IF NOT EXISTS cache_entries (
        key TEXT NOT NULL PRIMARY KEY, fetched_at INTEGER NOT NULL);
    `);
    // Um cache de versão antiga do drift pode não ter as colunas que a
    // decisão 25 acrescentou; elas entram vazias, como a migração do drift fazia.
    const present = new Set(
      (this.db.prepare('PRAGMA table_info(cached_fundamentals_table)').all() as { name: string }[]).map((r) => r.name),
    );
    for (const c of FUNDAMENTAL_COLUMNS) {
      if (!present.has(c)) this.db.exec(`ALTER TABLE cached_fundamentals_table ADD COLUMN ${c} REAL NULL`);
    }
    const priceColumns = new Set((this.db.prepare('PRAGMA table_info(cached_prices)').all() as { name: string }[]).map((r) => r.name));
    if (!priceColumns.has('volume')) this.db.exec('ALTER TABLE cached_prices ADD COLUMN volume REAL NULL');
  }

  private get now(): number {
    return (this.options.now ?? Date.now)();
  }

  close(): void {
    this.db.close();
  }

  // ------------------------------------------------------------------ TTL --

  async isFresh(key: string, ttl: Duration): Promise<boolean> {
    const row = this.db.prepare('SELECT fetched_at FROM cache_entries WHERE key = ?').get(key) as { fetched_at: number | string } | undefined;
    if (row === undefined) return false;
    if (this.options.frozen === true) return true;
    // O drift grava segundos inteiros; um banco gravado como texto ISO também é lido.
    const fetchedMs = typeof row.fetched_at === 'number' ? row.fetched_at * 1000 : Date.parse(row.fetched_at);
    return this.now - fetchedMs < ttl.inMilliseconds;
  }

  async touch(key: string): Promise<void> {
    this.db
      .prepare('INSERT INTO cache_entries (key, fetched_at) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET fetched_at = excluded.fetched_at')
      .run(key, Math.floor(this.now / 1000));
  }

  async invalidate(key: string): Promise<void> {
    this.db.prepare('DELETE FROM cache_entries WHERE key = ?').run(key);
  }

  // --------------------------------------------------------------- Preços --

  async pricesIn(ticker: string, startIso: string, endIso: string): Promise<CachedPrice[]> {
    const rows = this.db
      .prepare('SELECT date, close, adjusted_close, volume FROM cached_prices WHERE ticker = ? AND date >= ? AND date <= ? ORDER BY date')
      .all(ticker, startIso, endIso) as { date: string; close: number; adjusted_close: number | null; volume: number | null }[];
    return rows.map((r) => ({ date: r.date, close: r.close, adjustedClose: r.adjusted_close, volume: r.volume }));
  }

  async upsertPrices(ticker: string, rows: readonly CachedPrice[]): Promise<void> {
    const stmt = this.db.prepare(
      'INSERT INTO cached_prices (ticker, date, close, adjusted_close, volume) VALUES (?, ?, ?, ?, ?) ' +
        'ON CONFLICT(ticker, date) DO UPDATE SET close = excluded.close, adjusted_close = excluded.adjusted_close, volume = excluded.volume',
    );
    this.transaction(() => {
      for (const r of rows) stmt.run(ticker, r.date, r.close, r.adjustedClose, r.volume);
    });
  }

  async deletePricesOf(ticker: string): Promise<void> {
    this.db.prepare('DELETE FROM cached_prices WHERE ticker = ?').run(ticker);
  }

  // ----------------------------------------------------------- Fundamentos --

  async fundamentalsOf(ticker: string): Promise<CachedFundamentals[]> {
    const rows = this.db
      .prepare(`SELECT fiscal_period_end, ${FUNDAMENTAL_COLUMNS.join(', ')} FROM cached_fundamentals_table WHERE ticker = ? ORDER BY fiscal_period_end`)
      .all(ticker) as Record<string, number | string | null>[];
    return rows.map((r) => {
      const out = { fiscalPeriodEnd: String(r['fiscal_period_end']) } as CachedFundamentals;
      CACHED_FUNDAMENTAL_FIELDS.forEach((field, i) => {
        const v = r[FUNDAMENTAL_COLUMNS[i]!];
        out[field] = v === null || v === undefined ? null : Number(v);
      });
      return out;
    });
  }

  /** Campo ausente na linha nova não toca o que está em disco; `null` só entra em linha nova. */
  async upsertFundamentals(ticker: string, rows: readonly FundamentalsUpsert[]): Promise<void> {
    this.transaction(() => {
      for (const r of rows) {
        const exists = this.db
          .prepare('SELECT 1 AS x FROM cached_fundamentals_table WHERE ticker = ? AND fiscal_period_end = ?')
          .get(ticker, r.fiscalPeriodEnd);
        if (exists === undefined) {
          const values = CACHED_FUNDAMENTAL_FIELDS.map((f) => r[f] ?? null);
          this.db
            .prepare(
              `INSERT INTO cached_fundamentals_table (ticker, fiscal_period_end, ${FUNDAMENTAL_COLUMNS.join(', ')}) VALUES (?, ?, ${FUNDAMENTAL_COLUMNS.map(() => '?').join(', ')})`,
            )
            .run(ticker, r.fiscalPeriodEnd, ...values);
          continue;
        }
        const present = CACHED_FUNDAMENTAL_FIELDS.map((f, i) => [f, FUNDAMENTAL_COLUMNS[i]!] as const).filter(([f]) => r[f] !== undefined);
        if (present.length === 0) continue;
        this.db
          .prepare(`UPDATE cached_fundamentals_table SET ${present.map(([, c]) => `${c} = ?`).join(', ')} WHERE ticker = ? AND fiscal_period_end = ?`)
          .run(...present.map(([f]) => r[f] ?? null), ticker, r.fiscalPeriodEnd);
      }
    });
  }

  // --------------------------------------------------------------- Perfil --

  async profileOf(ticker: string): Promise<CachedProfile | null> {
    const r = this.db.prepare('SELECT name, sector_key, sector_label, industry FROM cached_profiles WHERE ticker = ?').get(ticker) as
      | { name: string; sector_key: string | null; sector_label: string | null; industry: string | null }
      | undefined;
    return r === undefined ? null : { name: r.name, sectorKey: r.sector_key, sectorLabel: r.sector_label, industry: r.industry };
  }

  async upsertProfile(ticker: string, row: CachedProfile): Promise<void> {
    this.db
      .prepare(
        'INSERT INTO cached_profiles (ticker, name, sector_key, sector_label, industry) VALUES (?, ?, ?, ?, ?) ' +
          'ON CONFLICT(ticker) DO UPDATE SET name = excluded.name, sector_key = excluded.sector_key, sector_label = excluded.sector_label, industry = excluded.industry',
      )
      .run(ticker, row.name, row.sectorKey, row.sectorLabel, row.industry);
  }

  // ---------------------------------------------------------------- Macro --

  async macroIn(seriesId: number, startIso: string, endIso: string): Promise<CachedMacroRate[]> {
    return this.db
      .prepare('SELECT date, value FROM cached_macro_rates WHERE series_id = ? AND date >= ? AND date <= ? ORDER BY date')
      .all(seriesId, startIso, endIso) as unknown as CachedMacroRate[];
  }

  async upsertMacro(seriesId: number, rows: readonly CachedMacroRate[]): Promise<void> {
    const stmt = this.db.prepare(
      'INSERT INTO cached_macro_rates (series_id, date, value) VALUES (?, ?, ?) ON CONFLICT(series_id, date) DO UPDATE SET value = excluded.value',
    );
    this.transaction(() => {
      for (const r of rows) stmt.run(seriesId, r.date, r.value);
    });
  }

  private transaction(work: () => void): void {
    this.db.exec('BEGIN');
    try {
      work();
      this.db.exec('COMMIT');
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
  }
}
