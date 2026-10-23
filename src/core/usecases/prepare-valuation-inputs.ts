/**
 * Busca e resolve os insumos de uma avaliação. É a única etapa que vai à rede:
 * a cascata ([ValuationCascade]) recebe tudo pronto e continua pura.
 */

import { AuditRecorder } from '../audit/audit-recorder';
import type { PriceSeries } from '../entities/price-series';
import type { ShareIssue } from '../entities/share-issue';
import { InsufficientData, type Failure } from '../failures/failure';
import { err, ok, type Result } from '../failures/result';
import { DateTime } from '../lang/date-time';
import { toStringAsFixed } from '../lang/num';
import type { BenchmarkRepository, FundamentalsRepository, PriceRepository } from '../repositories/repositories';
import { TotalReturnIndex, type CashDividend } from '../services/b3/cash-dividends';
import { CorporateEvents, type ShareEvent } from '../services/b3/corporate-events';
import { BetaCalculator } from '../services/metrics/beta';
import { BetaShrinkage, type BetaPrior } from '../services/metrics/beta-shrinkage';
import { MarketLeverage } from '../services/metrics/market-leverage';
import { BetaSource, CapmInputs, MarketPremiumSource } from '../services/valuation/cost-of-capital';
import { ValuationParameters } from '../services/valuation/growth-guards';
import type { PeerMultipleSet } from '../services/valuation/peer-multiples';
import type { YieldCurve } from '../services/valuation/yield-curve';
import { PointInTimeView } from '../time/point-in-time-view';
import { DateRange } from '../value-objects/date-range';
import type { Ticker } from '../value-objects/ticker';
import { ValuationCascade, ValuationInputs, type OfficialShareCount } from './compute-valuation';

/** Beta estimado, com a origem e a janela que a série de fato cobriu. */
interface BetaEstimateOutcome {
  readonly beta: number;
  readonly source: BetaSource;
  readonly standardError: number | null;
  readonly dividends: number;
  readonly windowInYears: number;
}

/** Janela, em anos, do beta — a mesma constante da cascata, para que as duas não divirjam. */
const BETA_WINDOW_YEARS = ValuationCascade.betaWindowYears;

/**
 * Registra a falha do preparo como transação de auditoria abortada — um ativo
 * que nem chegou à cascata é tão auditável quanto um avaliado.
 */
function failureOf(ticker: Ticker, asOf: DateTime, source: string, failure: Failure): Result<ValuationInputs> {
  AuditRecorder.begin(`/core/valuation/${ticker.value}`, {
    inputPayload: { ticker: ticker.value, asOf: asOf.toIso8601String(), etapa: 'preparo' },
  })?.abort(failure.message, {
    extra: { etapa: 'preparo', fonte: source, falha: failure.runtimeType },
  });
  return err(failure);
}

/** A ressalva do ajuste de eventos de ações que a fonte deixou de fazer (item B29). */
function adjustmentNote(applied: readonly ShareEvent[]): string {
  const day = (d: DateTime) =>
    `${String(d.day).padStart(2, '0')}/` + `${String(d.month).padStart(2, '0')}/${d.year}`;
  const factor = (f: number) =>
    f >= 1
      ? `${toStringAsFixed((f - 1) * 100, 0)}% de ações novas`
      : `grupamento de ${toStringAsFixed(1 / f, 0)} para 1`;
  const list = applied.map((e) => `${day(e.exDate)} (${factor(e.factor)})`);
  return (
    'A série de preços da fonte não trazia ' +
    `${applied.length === 1 ? 'ajustado o evento de ações de' : 'ajustados os eventos de ações de'} ` +
    `${list.join(', ')}: a data ex aparecia como queda de preço que não ` +
    'aconteceu. A série foi ajustada antes do beta, do corte de liquidez e ' +
    'da volatilidade da faixa.'
  );
}

/**
 * Estima o beta contra o Ibovespa na janela, com **retorno total dos dois
 * lados** quando há proventos (decisão 89). Recua para β = 1, declarado como
 * manual, quando o índice falha ou a série é curta.
 */
async function estimateBeta(args: {
  series: PriceSeries;
  benchmark: BenchmarkRepository;
  window: DateRange;
  dividends: readonly CashDividend[] | null;
}): Promise<BetaEstimateOutcome> {
  const { series, benchmark, window, dividends } = args;
  const manual: BetaEstimateOutcome = {
    beta: 1.0,
    source: BetaSource.manual,
    standardError: null,
    dividends: 0,
    windowInYears: 0.0,
  };
  const marketResult = await benchmark.ibovespa(window);
  if (marketResult.isErr) return manual;

  const market = marketResult.unwrap();
  if (market.points.length < 30) return manual;

  const assetPoints = series.points.filter((p) => window.contains(p.date));
  if (assetPoints.length < 2) return manual;

  const dates = assetPoints.map((p) => p.date);
  const closes = assetPoints.map((p) => p.close);
  const total =
    dividends === null || dividends.length === 0 ? null : TotalReturnIndex.build({ dates, closes, dividends });

  const aligned = BetaCalculator.alignReturns({
    assetDates: dates,
    assetIndex: total?.index ?? closes,
    marketDates: market.dates,
    marketIndex: market.points.map((p) => p.close),
  });

  const estimate = BetaCalculator.estimate({ returns: aligned });
  const reinvested = total?.applied ?? 0;
  // **A janela que a série de fato cobriu** (item B17).
  const effectiveWindow =
    dates.length < 2 ? 0.0 : dates[dates.length - 1]!.difference(dates[0]!).inDays / 365.25;

  return estimate.fold<BetaEstimateOutcome>(
    (value) => ({
      beta: value.beta,
      source: BetaSource.computed,
      standardError: value.standardError,
      dividends: reinvested,
      windowInYears: effectiveWindow,
    }),
    () => ({
      beta: 1.0,
      source: BetaSource.manual,
      standardError: null,
      dividends: 0,
      windowInYears: effectiveWindow,
    }),
  );
}

/** Prepara os insumos de [ValuationCascade.evaluate] para um ativo. */
export const PrepareValuationInputs = {
  betaWindowYears: BETA_WINDOW_YEARS,

  async call(args: {
    ticker: Ticker;
    prices: PriceRepository;
    fundamentals: FundamentalsRepository;
    benchmark: BenchmarkRepository;
    riskFreeRate: number;
    asOf?: DateTime | null;
    marketPremium?: number;
    premiumSource?: MarketPremiumSource;
    peerMultiples?: PeerMultipleSet | null;
    marginOfSafety?: number;
    projectionYears?: number;
    perpetualGrowthCap?: number;
    inflation?: number;
    terminalRiskFreeRate?: number | null;
    riskFreeCurve?: YieldCurve | null;
    officialShares?: OfficialShareCount | null;
    isDistressed?: boolean;
    stateControlled?: boolean;
    betaPrior?: BetaPrior | null;
    concessionEnd?: DateTime | null;
    dividends?: readonly CashDividend[] | null;
    declaredSharesPerUnit?: number | null;
    shareEvents?: readonly ShareEvent[];
    shareIssues?: readonly ShareIssue[];
  }): Promise<Result<ValuationInputs>> {
    const { ticker, prices, fundamentals, benchmark, riskFreeRate } = args;
    const today = args.asOf ?? DateTime.now();
    const window = new DateRange(DateTime.local(today.year - BETA_WINDOW_YEARS, today.month, today.day), today);

    const historyResult = await fundamentals.history(ticker);
    if (historyResult.isErr) {
      return failureOf(ticker, today, 'exercícios', historyResult.failureOrNull!);
    }

    // O perfil alimenta a Porta 1. Falha dele **não** interrompe: sem setor a
    // porta não dispara e o roteamento cai na Porta 3.
    const profile = await fundamentals.profile(ticker);
    const sectorKey = profile.isOk ? profile.unwrap().sector.key.toLowerCase() : null;
    // O subsetor alimenta a precedência da Guarda 3 sobre a Guarda 1.
    const industry = profile.isOk ? profile.unwrap().industry : null;

    const priceResult = await prices.daily(ticker, window);
    if (priceResult.isErr) {
      return failureOf(ticker, today, 'cotações', priceResult.failureOrNull!);
    }

    // **O ajuste que a fonte deixou de fazer** (item B29).
    const adjustment = CorporateEvents.completeAdjustment(priceResult.unwrap(), args.shareEvents ?? []);
    const series = adjustment.series;
    if (series.isEmpty) {
      return failureOf(
        ticker,
        today,
        'cotações',
        new InsufficientData(`Sem cotações de ${ticker.value} na janela de análise.`, { subject: ticker.value }),
      );
    }

    const beta = await estimateBeta({ series, benchmark, window, dividends: args.dividends ?? null });

    // Encolhimento por precisão. Sem prior, ou sem valor de mercado para medir
    // a alavancagem, vale a regressão crua — e o resultado diz qual valeu.
    const published = new PointInTimeView(today).published(historyResult.unwrap());
    const last = published.length === 0 ? null : published[published.length - 1]!;
    const marketEquity = last?.marketCap ?? null;
    let betaFinal = beta.beta;
    let betaOrigin = beta.source;
    let unleveredBeta: number | null = null;
    const betaPrior = args.betaPrior ?? null;
    if (betaPrior !== null && last !== null && marketEquity !== null && marketEquity > 0) {
      const shrunk = BetaShrinkage.shrink({
        leveredBeta: beta.beta,
        standardError: beta.standardError,
        prior: betaPrior,
        sectorKey,
        // **A alavancagem da janela do beta, e não a de hoje** (decisão 55).
        debtToEquity:
          MarketLeverage.overWindow({ snapshots: published, prices: series.points, window }) ??
          last.debtToMarketEquity(marketEquity) ??
          0.0,
        // **A estatutária, e é a mesma que a realavancagem usa** (decisão 55).
        taxRate: ValuationParameters.statutoryTaxRate,
      });
      betaFinal = shrunk.beta;
      unleveredBeta = shrunk.unlevered;
      if (shrunk.weight < 1.0) betaOrigin = BetaSource.shrunk;
    }

    return ok(
      new ValuationInputs({
        ticker,
        asOf: today,
        fundamentals: historyResult.unwrap(),
        marketPrice: series.points[series.points.length - 1]!.close,
        capm: new CapmInputs({
          riskFreeRate,
          beta: betaFinal,
          marketPremium: args.marketPremium ?? CapmInputs.defaultMarketPremium,
          betaSource: betaOrigin,
          premiumSource: args.premiumSource ?? MarketPremiumSource.parameterized,
        }),
        marginOfSafety: args.marginOfSafety ?? 0.0,
        projectionYears: args.projectionYears ?? 10,
        perpetualGrowthCap: args.perpetualGrowthCap ?? 0.0652,
        sectorKey,
        industry,
        inflation: args.inflation ?? 0.05,
        declaredTerminalRiskFreeRate: args.terminalRiskFreeRate ?? null,
        riskFreeCurve: args.riskFreeCurve ?? null,
        officialShares: args.officialShares ?? null,
        // A mesma série que estima o beta alimenta o corte de liquidez da Porta 0.
        prices: series,
        isDistressed: args.isDistressed ?? false,
        stateControlled: args.stateControlled ?? false,
        unleveredBeta,
        concessionEnd: args.concessionEnd ?? null,
        dividendsInBeta: beta.dividends,
        // A taxa da data arbitra a despesa financeira, e não a do cenário (B10).
        creditReferenceRiskFree: riskFreeRate,
        // A composição declarada da unit, quando a companhia a publica (B16).
        declaredSharesPerUnit: args.declaredSharesPerUnit ?? null,
        // A segunda leitura, por múltiplos de pares (item B5). Só viaja.
        peerMultiples: args.peerMultiples ?? null,
        // A janela que a série de fato cobriu (item B17).
        betaWindowYears: beta.windowInYears,
        // As emissões por valor: a cascata soma as posteriores ao balanço (B28).
        shareIssues: args.shareIssues ?? [],
        contextNotes: adjustment.applied.length > 0 ? [adjustmentNote(adjustment.applied)] : [],
      }),
    );
  },
};
