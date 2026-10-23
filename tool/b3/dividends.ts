// Leitores compartilhados dos itens A4 e A3.4: proventos da B3 e fechamento
// bruto do COTAHIST, para `dividends-check.ts`, `backtest-valuation.ts` e
// `b3-delisted-count.ts`.
import { existsSync, readdirSync } from 'node:fs';

import {
  B3CashDividends,
  type CashDividend,
  CashDividendsCodec,
  DateTime,
  intDiv,
  RawQuote,
  tryParseDouble,
  tryParseInt,
} from '../../src/core';
import { fail, filesIn, readJson, readLines } from '../lib/files';

/** Proventos por emissor de quatro letras, de `data/b3/complemento/`. */
export function readDividends(dir = 'data/b3/complemento'): Map<string, CashDividend[]> {
  if (!existsSync(dir)) fail(`sem ${dir} — rode: python tool/b3_complemento_baixar.py`);
  const out = new Map<string, CashDividend[]>();
  for (const name of readdirSync(dir)) {
    if (!name.endsWith('.json')) continue;
    const raw = readJson<Record<string, unknown>>(`${dir}/${name}`);
    const issuer = name.replaceAll('.json', '');
    out.set(issuer, B3CashDividends.parse((raw['proventos'] as unknown[] | undefined) ?? []));
  }
  return out;
}

/** Os proventos da classe de [ticker], ou lista vazia. */
export function dividendsOf(dividends: ReadonlyMap<string, readonly CashDividend[]>, ticker: string): CashDividend[] {
  return CashDividendsCodec.forTicker(dividends, ticker);
}

/** Um pregão do COTAHIST: fechamento bruto por ação e número de distribuição. */
export class TradingDay {
  constructor(
    readonly date: DateTime,
    readonly close: number,
    readonly distribution: number,
    /** Volume financeiro do dia, em reais. `null` quando o arquivo não o traz. */
    readonly tradedValue: number | null = null,
  ) {}

  get raw(): RawQuote {
    return new RawQuote(this.date, this.close, this.distribution);
  }
}

/**
 * Fechamento **bruto por ação** do COTAHIST, por ticker, em ordem de data.
 *
 * O CSV compacto guarda o fechamento em centavos por lote de `fatorCotacao`
 * ações, e o volume financeiro em centavos; aqui saem em reais.
 *
 * - [isins]: quando dado, só entra o pregão do ISIN do ticker. Um ticker pode
 *   ter sido de mais de um papel ao longo dos anos.
 */
export function readRawCotahist(tickers: ReadonlySet<string>, isins?: ReadonlyMap<string, string>): Map<string, TradingDay[]> {
  const out = new Map<string, TradingDay[]>();
  for (const f of filesIn('data/b3', /avista_\d{4}\.csv$/)) {
    let header = true;
    for (const row of readLines(f)) {
      if (header) {
        header = false;
        continue;
      }
      const c = row.split(';');
      if (c.length < 8 || !tickers.has(c[1]!)) continue;
      const isin = isins?.get(c[1]!);
      if (isin !== undefined && c[2] !== isin) continue;
      const date = DateTime.tryParse(`${c[0]}T00:00:00Z`);
      const cents = tryParseDouble(c[5]!);
      const factor = tryParseDouble(c[6]!);
      const distribution = tryParseInt(c[7]!) ?? 0;
      if (date === null || cents === null || factor === null || factor <= 0) continue;
      const volume = c.length > 8 ? tryParseDouble(c[8]!) : null;
      const list = out.get(c[1]!) ?? [];
      list.push(new TradingDay(date, cents / 100 / factor, distribution, volume === null ? null : volume / 100));
      out.set(c[1]!, list);
    }
  }
  for (const s of out.values()) s.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/** Primeiro pregão em ou depois de [day], até [marginDays] dias corridos. */
export function tradingDayFrom(series: readonly TradingDay[], day: DateTime, marginDays = 10): TradingDay | null {
  // O COTAHIST é lido em UTC; uma data local à meia-noite cairia três horas
  // depois do pregão do mesmo dia e o pularia.
  const date = DateTime.utc(day.year, day.month, day.day);
  let lo = 0;
  let hi = series.length;
  while (lo < hi) {
    const m = intDiv(lo + hi, 2);
    if (series[m]!.date.isBefore(date)) lo = m + 1;
    else hi = m;
  }
  if (lo >= series.length) return null;
  const p = series[lo]!;
  return p.date.difference(date).inDays <= marginDays ? p : null;
}

/** Último pregão em ou antes de [day], até [marginDays] dias corridos. */
export function tradingDayUntil(series: readonly TradingDay[], day: DateTime, marginDays = 10): TradingDay | null {
  const date = DateTime.utc(day.year, day.month, day.day);
  let lo = 0;
  let hi = series.length;
  while (lo < hi) {
    const m = intDiv(lo + hi, 2);
    if (series[m]!.date.isAfter(date)) hi = m;
    else lo = m + 1;
  }
  if (lo === 0) return null;
  const p = series[lo - 1]!;
  return date.difference(p.date).inDays <= marginDays ? p : null;
}
