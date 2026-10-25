/**
 * Casos de uso da carteira: trocar ativo entre Principal e Reserva, confrontar
 * o esperado com a meta e derivar as âncoras de mercado das séries observadas.
 */

import type { FinancialGoal, RequiredReturn } from '../entities/financial-goal';
import type { Portfolio } from '../entities/portfolio';
import type { PricePoint, PriceSeries } from '../entities/price-series';
import type { ValuationResult } from '../entities/valuation';
import { InsufficientData, InvalidInput } from '../failures/failure';
import { err, ok, type Result } from '../failures/result';
import { DateTime } from '../lang/date-time';
import type { BenchmarkRepository, MacroRepository, RateSeries } from '../repositories/repositories';
import { MarketAnchors } from '../services/goal/feasibility';
import { RequiredReturnSolver } from '../services/goal/required-return';
import { Returns } from '../services/metrics/returns';
import { ExpectedReturn } from '../services/portfolio/expected-return';
import type { TransversalOrdering, TransversalSignals } from '../services/portfolio/transversal-ordering';
import { CapmInputs } from '../services/valuation/cost-of-capital';
import { DateRange } from '../value-objects/date-range';
import type { Ticker } from '../value-objects/ticker';

/**
 * Resultado de mover um ativo entre as carteiras: as duas já reequiponderadas,
 * para a interface repintar sem recalcular nada por conta própria.
 */
export class RebalanceOutcome {
  readonly principal: Portfolio;
  readonly reserve: Portfolio;

  constructor(args: { principal: Portfolio; reserve: Portfolio }) {
    this.principal = args.principal;
    this.reserve = args.reserve;
  }
}

/**
 * Move um ativo entre Principal e Reserva. **Síncrono de propósito**: o
 * recálculo custa microssegundos, e o arrastar-e-soltar atualiza a cada quadro.
 */
export const SwapAssetBetweenPortfolios = {
  call(args: { principal: Portfolio; reserve: Portfolio; ticker: Ticker; toPrincipal: boolean }): Result<RebalanceOutcome> {
    const { principal, reserve, ticker, toPrincipal } = args;
    const source = toPrincipal ? reserve : principal;
    const target = toPrincipal ? principal : reserve;

    const entry = source.entries.get(ticker);
    if (entry === undefined) {
      return err(new InvalidInput(`${ticker.value} não está na carteira ${source.kind.key}.`));
    }
    if (target.entries.has(ticker)) {
      return err(new InvalidInput(`${ticker.value} já está na carteira ${target.kind.key}.`));
    }

    const added = target.add(entry.asset);
    if (added.isErr) return err(added.failureOrNull!);

    const removed = source.remove(ticker);
    if (removed.isErr) return err(removed.failureOrNull!);

    const newPrincipal = toPrincipal ? added.unwrap() : removed.unwrap();
    const newReserve = toPrincipal ? removed.unwrap() : added.unwrap();

    return ok(new RebalanceOutcome({ principal: newPrincipal, reserve: newReserve }));
  },
};

/** Situação da carteira frente à meta patrimonial. */
export class GoalAlignment {
  readonly required: RequiredReturn;

  /**
   * Retorno anual esperado da carteira, pelo **estimador transversal**:
   * `Ke_i + z · prêmio`, ponderado pelos pesos. **A âncora é o custo de
   * capital próprio de cada ativo, e não o CDI** (decisão 58), e só entra
   * prêmio da ordenação que a validação comprovou (decisão 103). **É retorno
   * total**: o `Ke` do CAPM inclui o provento (decisão 62), e a meta é um
   * plano de patrimônio que o reinveste.
   */
  readonly expectedReturn: number;

  /** Fração do peso da carteira que possui avaliação disponível. */
  readonly valuationCoverage: number;

  constructor(args: { required: RequiredReturn; expectedReturn: number; valuationCoverage: number }) {
    this.required = args.required;
    this.expectedReturn = args.expectedReturn;
    this.valuationCoverage = args.valuationCoverage;
  }

  /** Diferença entre o esperado e o exigido, em pontos percentuais ao ano. */
  get gap(): number {
    return (this.expectedReturn - this.required.annual) * 100;
  }

  get meetsGoal(): boolean {
    return this.expectedReturn >= this.required.annual;
  }

  /** Cobertura baixa torna o retorno esperado pouco representativo. */
  get coverageIsWeak(): boolean {
    return this.valuationCoverage < 0.6;
  }

  // Aqui existiu `yieldToCloseGap`, **removido pela decisão 62**: somar um
  // yield a um retorno total é contar o provento duas vezes.
}

/** Confronta o retorno esperado da carteira com a rentabilidade exigida. */
export const EvaluateGoalAlignment = {
  /**
   * - [crossSection]: potenciais que definem mediana e escala do escore;
   *   omitido, a seção é a própria carteira (limitação declarada).
   * - [ordering] e [signals]: a ordenação medida que decide o prêmio (item B1).
   * - [riskPremium]: o prêmio de mercado do escore (decisão 142).
   */
  call(args: {
    portfolio: Portfolio;
    goal: FinancialGoal;
    valuations: ReadonlyMap<Ticker, ValuationResult>;
    anchors: MarketAnchors;
    crossSection?: Iterable<number> | null;
    ordering?: TransversalOrdering | null;
    signals?: ReadonlyMap<Ticker, TransversalSignals> | null;
    riskPremium?: number;
  }): Result<GoalAlignment> {
    const { portfolio, goal, valuations, anchors } = args;
    const signals = args.signals ?? null;
    const riskPremium = args.riskPremium ?? CapmInputs.defaultMarketPremium;
    const solved = RequiredReturnSolver.solve(goal);
    if (solved.isErr) return err(solved.failureOrNull!);

    const required = solved.unwrap();
    return ok(
      new GoalAlignment({
        required,
        expectedReturn:
          signals === null
            ? ExpectedReturn.forPortfolioCrossSectional({
                portfolio,
                valuations,
                spotRiskFree: anchors.currentRiskFreeRate,
                reference: args.crossSection ?? null,
                riskPremium,
              })
            : ExpectedReturn.forPortfolioOrdered({
                portfolio,
                valuations,
                signals,
                ordering: args.ordering ?? null,
                spotRiskFree: anchors.currentRiskFreeRate,
                riskPremium,
              }),
        valuationCoverage: ExpectedReturn.coverage({ portfolio, valuations }),
      }),
    );
  },
};

/** Janela padrão das âncoras, em anos. */
const DEFAULT_WINDOW_YEARS = 10;

/**
 * Trimestre mais recente do CDI, anualizado: a taxa livre de risco de **hoje**,
 * longa o bastante para não repicar num dia atípico.
 */
const CURRENT_RATE_WINDOW_DAYS = 63;

/** Pregões de cada ponta que formam a média do CAGR do índice (decisão 60). */
const INDEX_END_WINDOW_DAYS = 63;

function currentRateOf(series: RateSeries): number {
  if (series.isEmpty) return MarketAnchors.fallback2026.currentRiskFreeRate;
  return series.tail(CURRENT_RATE_WINDOW_DAYS).annualized();
}

/**
 * CAGR do índice entre as **médias das duas pontas**, medido de centro a
 * centro (decisão 60). Fallback quando a série é curta, tem preço não positivo
 * ou colapsa num único dia.
 */
function cagrOf(series: PriceSeries): number {
  const p = series.points;
  if (p.length < 2) return MarketAnchors.fallback2026.marketCagr;

  // Com série curta, cada ponta é metade do que há — nunca sobrepostas.
  const half = Math.floor(p.length / 2);
  const n = half < INDEX_END_WINDOW_DAYS ? half : INDEX_END_WINDOW_DAYS;
  if (n < 1) return MarketAnchors.fallback2026.marketCagr;

  const mean = (xs: readonly PricePoint[]): number => {
    let total = 0.0;
    let howMany = 0;
    for (const x of xs) {
      total += x.close;
      howMany++;
    }
    return howMany === 0 ? 0 : total / howMany;
  };

  const start = mean(p.slice(0, n));
  const end = mean(p.slice(p.length - n));
  if (start <= 0 || end <= 0) return MarketAnchors.fallback2026.marketCagr;

  const initialCenter = p[Math.floor((n - 1) / 2)]!.date;
  const finalCenter = p[p.length - 1 - Math.floor((n - 1) / 2)]!.date;
  const years = new DateRange(initialCenter, finalCenter).years;
  if (years <= 0) return MarketAnchors.fallback2026.marketCagr;

  return Returns.annualize(end / start - 1, years);
}

/**
 * Crescimento real anual a partir do índice de atividade, por **média móvel
 * de 12 meses nas duas pontas**. `null` sem 12 meses em cada ponta ou com
 * janela efetiva curta demais.
 */
function activityCagrOf(series: RateSeries): number | null {
  const window = 12;
  const v = series.rates;
  if (v.length < window * 2) return null;

  const mean = (end: number): number => {
    let total = 0.0;
    for (let i = end - window + 1; i <= end; i++) total += v[i]!;
    return total / window;
  };

  const start = mean(window - 1);
  const end = mean(v.length - 1);
  if (start <= 0 || end <= 0) return null;

  // Anos entre os centros das duas médias móveis.
  const months = v.length - window;
  const years = months / 12.0;
  if (years < 1) return null;

  const g = Math.pow(end / start, 1 / years) - 1;
  return Number.isFinite(g) ? g : null;
}

/**
 * Deriva as âncoras de mercado a partir das séries observadas. Os limiares de
 * viabilidade da meta **não são constantes de código**: saem do CDI e do
 * Ibovespa na janela consultada.
 */
export const ResolveMarketAnchors = {
  defaultWindowYears: DEFAULT_WINDOW_YEARS,
  currentRateWindowDays: CURRENT_RATE_WINDOW_DAYS,
  indexEndWindowDays: INDEX_END_WINDOW_DAYS,

  async call(args: {
    macro: MacroRepository;
    benchmark: BenchmarkRepository;
    asOf?: DateTime | null;
    windowYears?: number;
  }): Promise<Result<MarketAnchors>> {
    const { macro, benchmark } = args;
    const windowYears = args.windowYears ?? DEFAULT_WINDOW_YEARS;
    const end = args.asOf ?? DateTime.now();
    const range = new DateRange(DateTime.local(end.year - windowYears, end.month, end.day), end);

    const cdi = await macro.riskFreeDaily(range);
    const ibov = await benchmark.ibovespa(range);
    const ipca = await macro.inflationMonthly(range);
    const ibc = await macro.activityIndexMonthly(range);

    if (cdi.isErr && ibov.isErr) {
      return err(new InsufficientData('Nem CDI nem Ibovespa puderam ser carregados para calibrar os limiares.'));
    }

    const riskFree = cdi.isOk ? cdi.unwrap().annualized() : MarketAnchors.fallback2026.riskFreeCagr;
    const market = ibov.isOk ? cagrOf(ibov.unwrap()) : MarketAnchors.fallback2026.marketCagr;
    // A série do IPCA é mensal; sem ela, a inflação de fallback mantém o
    // crescimento perpétuo nominal.
    const inflation =
      ipca.isOk && ipca.unwrap().rates.length > 0 ? ipca.unwrap().annualized() : MarketAnchors.fallback2026.inflationCagr;
    const current = cdi.isOk ? currentRateOf(cdi.unwrap()) : MarketAnchors.fallback2026.currentRiskFreeRate;
    // Parcela real do teto da perpetuidade, medida em vez de arbitrada.
    const realGrowth = ibc.isOk
      ? (activityCagrOf(ibc.unwrap()) ?? MarketAnchors.fallback2026.realEconomyGrowth)
      : MarketAnchors.fallback2026.realEconomyGrowth;

    return ok(
      new MarketAnchors({
        riskFreeCagr: riskFree,
        currentRiskFreeRate: current,
        marketCagr: market,
        inflationCagr: inflation,
        realEconomyGrowth: realGrowth,
        observedYears: windowYears,
      }),
    );
  },
};
