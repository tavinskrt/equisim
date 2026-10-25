/** Resolve o prior transversal do beta a partir do universo. */

import type { BenchmarkRepository, FundamentalsRepository, PriceRepository } from '../repositories/repositories';
import { DateTime } from '../lang/date-time';
import { TotalReturnIndex, type CashDividend } from '../services/b3/cash-dividends';
import { BetaCalculator } from '../services/metrics/beta';
import { BetaPrior, BetaShrinkage } from '../services/metrics/beta-shrinkage';
import { MarketLeverage } from '../services/metrics/market-leverage';
import { ValuationParameters } from '../services/valuation/growth-guards';
import { Inference } from '../services/valuation/inference';
import { PointInTimeView } from '../time/point-in-time-view';
import { DateRange } from '../value-objects/date-range';
import type { Ticker } from '../value-objects/ticker';

/**
 * Um ativo já medido, para compor o prior. Existe para que o agregador seja
 * **puro**: quem vai à rede é o chamador.
 */
export class BetaObservation {
  /** Beta observado na regressão. */
  readonly leveredBeta: number;

  /** Chave do setor, ou `null`. */
  readonly sectorKey: string | null;

  /** Dívida **líquida** sobre valor de mercado do capital próprio (decisões 54 e 104). */
  readonly debtToEquity: number;

  /** Alíquota estrutural do ativo. */
  readonly taxRate: number;

  constructor(args: { leveredBeta: number; sectorKey: string | null; debtToEquity: number; taxRate: number }) {
    this.leveredBeta = args.leveredBeta;
    this.sectorKey = args.sectorKey;
    this.debtToEquity = args.debtToEquity;
    this.taxRate = args.taxRate;
  }
}

/**
 * Monta o [BetaPrior] do universo. A cascata avalia um ativo por vez e é
 * pura; mediana setorial e dispersão transversal chegam como insumo.
 */
export const ResolveBetaPrior = {
  /** Pares mínimos para a mediana de um setor ser usada. **Três, e é pouco de propósito.** */
  minimumPeers: 3,

  /** Agrega observações já medidas num prior. **Puro.** `null` sem observação utilizável. */
  fromObservations(observations: readonly BetaObservation[]): BetaPrior | null {
    const unleveredBetas = new Map<string | null, number[]>();
    const allUnlevered: number[] = [];
    const allLevered: number[] = [];

    for (const o of observations) {
      if (!Number.isFinite(o.leveredBeta)) continue;
      allLevered.push(o.leveredBeta);
      const u = BetaShrinkage.unlever({ leveredBeta: o.leveredBeta, debtToEquity: o.debtToEquity, taxRate: o.taxRate });
      if (u === null || !Number.isFinite(u)) continue;
      allUnlevered.push(u);
      const k = o.sectorKey?.trim() ?? null;
      const key = k === null || k.length === 0 ? null : k;
      let bucket = unleveredBetas.get(key);
      if (bucket === undefined) {
        bucket = [];
        unleveredBetas.set(key, bucket);
      }
      bucket.push(u);
    }

    const universe = Inference.median(allUnlevered);
    if (universe === null || !Number.isFinite(universe)) return null;

    const bySector = new Map<string, number>();
    for (const [k, values] of unleveredBetas) {
      if (k === null || values.length < ResolveBetaPrior.minimumPeers) continue;
      const m = Inference.median(values);
      if (m !== null && Number.isFinite(m)) bySector.set(k, m);
    }

    // Dispersão do prior: robusta, sobre os betas **alavancados**. Recuo para
    // 0,5 quando a amostra colapsa — próximo do medido (0,53) e conservador.
    const dispersion = Inference.scaledMad(allLevered);

    return new BetaPrior({
      unleveredBySector: bySector,
      unleveredUniverse: universe,
      dispersion: dispersion !== null && Number.isFinite(dispersion) && dispersion > 0 ? dispersion : 0.5,
    });
  },

  /**
   * Varre o universo e devolve o prior. Vai à rede. Ativo que falhe em
   * qualquer etapa é **pulado**, não interrompe.
   */
  async call(args: {
    tickers: readonly Ticker[];
    prices: PriceRepository;
    fundamentals: FundamentalsRepository;
    benchmark: BenchmarkRepository;
    asOf: DateTime;
    windowYears?: number;
    dividendsFor?: ((t: Ticker) => CashDividend[]) | null;
  }): Promise<BetaPrior | null> {
    const { asOf } = args;
    const windowYears = args.windowYears ?? 5;
    const window = new DateRange(DateTime.local(asOf.year - windowYears, asOf.month, asOf.day), asOf);
    const indexResult = await args.benchmark.ibovespa(window);
    if (indexResult.isErr) return null;
    const index = indexResult.unwrap();
    const view = new PointInTimeView(asOf);

    const observations: BetaObservation[] = [];
    for (const t of args.tickers) {
      const seriesResult = await args.prices.daily(t, window);
      if (seriesResult.isErr) continue;
      const points = seriesResult.unwrap().points.filter((p) => window.contains(p.date));
      if (points.length < 2) continue;

      const dates = points.map((p) => p.date);
      const closes = points.map((p) => p.close);
      const dividends = args.dividendsFor?.(t) ?? null;
      const estimate = BetaCalculator.estimate({
        returns: BetaCalculator.alignReturns({
          assetDates: dates,
          assetIndex:
            dividends === null || dividends.length === 0
              ? closes
              : TotalReturnIndex.build({ dates, closes, dividends }).index,
          marketDates: index.dates,
          marketIndex: index.points.map((p) => p.close),
        }),
      });
      if (estimate.isErr) continue;

      const historyResult = await args.fundamentals.history(t);
      if (historyResult.isErr) continue;
      const pub = view.published(historyResult.unwrap());
      if (pub.length === 0) continue;
      const last = pub[pub.length - 1]!;
      const equity = last.marketCap;
      if (equity === null || equity <= 0) continue;

      const profile = await args.fundamentals.profile(t);
      const key = profile.isOk ? profile.unwrap().sector.key.trim() : '';

      observations.push(
        new BetaObservation({
          leveredBeta: estimate.unwrap().beta,
          sectorKey: key.length === 0 ? null : key,
          // A mesma régua de [PrepareValuationInputs]: dívida líquida, medida
          // na janela em que o beta foi estimado.
          debtToEquity:
            MarketLeverage.overWindow({ snapshots: pub, prices: points, window }) ??
            last.debtToMarketEquity(equity) ??
            0.0,
          // A estatutária: o `(1 − τ)` de Hamada é escudo fiscal do juro (decisão 55).
          taxRate: ValuationParameters.statutoryTaxRate,
        }),
      );
    }

    return ResolveBetaPrior.fromObservations(observations);
  },
};
