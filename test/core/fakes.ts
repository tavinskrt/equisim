/**
 * Repositórios em memória para os testes do núcleo — os `_Prices`, `_Index` e
 * `_Fundamentals` que cada arquivo de teste do Dart declarava por conta própria.
 */

import {
  type Asset,
  type BenchmarkRepository,
  type DateRange,
  DateTime,
  err,
  type FundamentalsRepository,
  type FundamentalsSnapshot,
  InsufficientData,
  type MacroRepository,
  ok,
  type PriceRepository,
  PriceSeries,
  type RateSeries,
  type Result,
  type Ticker,
} from '../../src/core';

/** Pregões de segunda a sexta, de [start] a [end], pontas inclusivas. */
export function tradingDays(start: DateTime, end: DateTime): DateTime[] {
  const out: DateTime[] = [];
  for (let d = start; !d.isAfter(end); d = DateTime.local(d.year, d.month, d.day + 1)) {
    if (d.weekday <= 5) out.push(d);
  }
  return out;
}

/** Devolve sempre a mesma série, inteira, para qualquer ativo e janela. */
export class FixedPrices implements PriceRepository {
  constructor(private readonly series: PriceSeries) {}

  daily(_ticker: Ticker, _range: DateRange): Promise<Result<PriceSeries>> {
    return Promise.resolve(ok(this.series));
  }

  dailyBatch(_tickers: readonly Ticker[], _range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>> {
    return Promise.resolve(ok(new Map([[this.series.ticker, this.series]])));
  }

  adjustedCloseRaw(_ticker: Ticker, _range: DateRange): Promise<Result<PriceSeries>> {
    return Promise.resolve(ok(this.series));
  }
}

/** Uma série por ativo; ativo ausente é falha de dado, como no repositório real. */
export class MapPrices implements PriceRepository {
  constructor(private readonly byTicker: ReadonlyMap<Ticker, PriceSeries>) {}

  daily(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    const s = this.byTicker.get(ticker);
    if (s === undefined) return Promise.resolve(err(new InsufficientData(`Sem cotações de ${ticker.value}.`)));
    return Promise.resolve(ok(new PriceSeries({ ticker, points: s.points.filter((p) => range.contains(p.date)) })));
  }

  async dailyBatch(tickers: readonly Ticker[], range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>> {
    const out = new Map<Ticker, PriceSeries>();
    for (const t of tickers) {
      const r = await this.daily(t, range);
      if (r.isOk) out.set(t, r.unwrap());
    }
    return ok(out);
  }

  adjustedCloseRaw(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return this.daily(ticker, range);
  }
}

/** Ibovespa fixo. */
export class FixedIndex implements BenchmarkRepository {
  constructor(private readonly series: PriceSeries) {}

  ibovespa(_range: DateRange): Promise<Result<PriceSeries>> {
    return Promise.resolve(ok(this.series));
  }
}

/** Fundamentos fixos: o mesmo histórico para qualquer ativo, perfil opcional. */
export class FixedFundamentals implements FundamentalsRepository {
  constructor(
    private readonly make: (t: Ticker) => FundamentalsSnapshot[],
    private readonly tickers: readonly Ticker[],
    private readonly assetOf: ((t: Ticker) => Asset | null) | null = null,
  ) {}

  history(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    return Promise.resolve(ok(this.make(ticker)));
  }

  profile(ticker: Ticker): Promise<Result<Asset>> {
    const a = this.assetOf?.(ticker) ?? null;
    return Promise.resolve(a === null ? err(new InsufficientData('sem perfil')) : ok(a));
  }

  universe(): Promise<Result<Ticker[]>> {
    return Promise.resolve(ok([...this.tickers]));
  }
}

/** Repositório macro que devolve o que lhe entregam, para qualquer janela. */
export class FixedMacro implements MacroRepository {
  constructor(private readonly series: { cdi: RateSeries; ipca: RateSeries; ibc: RateSeries }) {}

  riskFreeDaily(_range: DateRange): Promise<Result<RateSeries>> {
    return Promise.resolve(ok(this.series.cdi));
  }

  inflationMonthly(_range: DateRange): Promise<Result<RateSeries>> {
    return Promise.resolve(ok(this.series.ipca));
  }

  activityIndexMonthly(_range: DateRange): Promise<Result<RateSeries>> {
    return Promise.resolve(ok(this.series.ibc));
  }
}
