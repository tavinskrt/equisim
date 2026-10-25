import {
  type BacktestOutcome,
  BetaCalculator,
  ContributionPlan,
  DateRange,
  DateTime,
  type FinancialGoal,
  type Portfolio,
  PortfolioBacktest,
  type PriceRepository,
  type PriceSeries,
  type Result,
  Returns,
  RiskMetrics,
  type Ticker,
} from '../core';
import { FailureCopy } from '../copy';

/** Parâmetros da simulação histórica. */
export interface BacktestSettings {
  /** Anos de histórico, contados para trás a partir de hoje. */
  readonly windowYears: number;
  /** Dia do mês do aporte. Limitado a 28 pelo domínio; sem controle na interface. */
  readonly contributionDay: number;
}

export const BacktestLimits = {
  /** Piso da janela, em anos. */
  minWindowYears: 1,
  /**
   * Teto da janela, em anos — o que a fonte de cotações entrega. Nomeado
   * porque é citado no controle, no mutador e no aviso de horizonte.
   */
  maxWindowYears: 10,
} as const;

export const defaultBacktestSettings: BacktestSettings = { windowYears: 5, contributionDay: 5 };

/** Trava a janela na faixa declarada. */
export function clampWindowYears(years: number): number {
  return Math.min(BacktestLimits.maxWindowYears, Math.max(BacktestLimits.minWindowYears, Math.round(years)));
}

/**
 * Papel de um ponto na dispersão risco × retorno. O candidato da Reserva se
 * distingue do ativo já detido porque é essa comparação que sustenta a troca.
 */
export type RiskReturnKind = 'principalAsset' | 'reserveAsset' | 'principal' | 'reserve';

/** Um ponto da dispersão, em **pontos percentuais** — a unidade dos eixos. */
export interface RiskReturnPoint {
  readonly label: string;
  /** Volatilidade anualizada, em p.p. */
  readonly risk: number;
  /** Retorno anualizado, em p.p. */
  readonly ret: number;
  readonly kind: RiskReturnKind;
}

export function isPortfolioPoint(p: RiskReturnPoint): boolean {
  return p.kind === 'principal' || p.kind === 'reserve';
}

/** Resultado comparativo das duas carteiras sob o mesmo plano de aportes. */
export class PortfolioComparison {
  /** Resultado da Principal, ou `null` — e aí o motivo está em [principalFailure]. */
  readonly principal: BacktestOutcome | null;
  readonly reserve: BacktestOutcome | null;
  /** Janela **efetivamente simulada**, idêntica nas duas carteiras. */
  readonly window: DateRange;
  /** Janela pedida, antes de qualquer encurtamento. */
  readonly requestedWindow: DateRange;
  /** Ativo cujo histórico obrigou a encurtar a janela, quando houve. */
  readonly limitingTicker: Ticker | null;
  readonly principalFailure: string | null;
  readonly reserveFailure: string | null;
  readonly riskReturn: readonly RiskReturnPoint[];

  constructor(args: {
    window: DateRange;
    requestedWindow: DateRange;
    principal?: BacktestOutcome | null;
    reserve?: BacktestOutcome | null;
    limitingTicker?: Ticker | null;
    principalFailure?: string | null;
    reserveFailure?: string | null;
    riskReturn?: readonly RiskReturnPoint[];
  }) {
    this.window = args.window;
    this.requestedWindow = args.requestedWindow;
    this.principal = args.principal ?? null;
    this.reserve = args.reserve ?? null;
    this.limitingTicker = args.limitingTicker ?? null;
    this.principalFailure = args.principalFailure ?? null;
    this.reserveFailure = args.reserveFailure ?? null;
    this.riskReturn = args.riskReturn ?? [];
  }

  /** `true` quando as duas carteiras foram simuladas. */
  get hasBoth(): boolean {
    return this.principal !== null && this.reserve !== null;
  }

  /** `true` quando a janela simulada ficou menor que a pedida. */
  get windowWasShortened(): boolean {
    return this.window.start.isAfter(this.requestedWindow.start);
  }

  /**
   * Diferença de TWR, em pontos percentuais. TWR é a métrica certa aqui:
   * neutraliza o cronograma de aportes, idêntico nas duas carteiras.
   */
  get twrGap(): number | null {
    return this.principal !== null && this.reserve !== null
      ? (this.principal.metrics.timeWeightedReturn - this.reserve.metrics.timeWeightedReturn) * 100
      : null;
  }
}

/**
 * Executa o backtest das duas carteiras com o mesmo plano de aportes.
 *
 * **As duas carteiras são simuladas na mesma janela**: o início comum é o
 * primeiro pregão em que *todos* os ativos das duas já negociavam. Sem esse
 * alinhamento, os patrimônios aportados divergiam e o TWR comparava períodos
 * diferentes.
 */
export async function comparePortfolios(args: {
  principal: Portfolio;
  reserve: Portfolio;
  goal: FinancialGoal | null;
  settings: BacktestSettings;
  prices: PriceRepository;
  today: DateTime;
  riskFreeRateFor: (window: DateRange) => Promise<number>;
}): Promise<PortfolioComparison | null> {
  const { principal, reserve, goal, settings, prices, today } = args;
  if (principal.isEmpty && reserve.isEmpty) return null;
  if (goal === null) return null;

  const requested = requestedWindow(today, settings.windowYears);
  // A taxa livre de risco do Sharpe é a da própria janela (decisão 58).
  const riskFree = await args.riskFreeRateFor(requested);

  const tickers = [...new Set([...principal.tickers, ...reserve.tickers])];
  if (tickers.length === 0) return null;

  // Um único lote para todos os ativos das duas carteiras.
  const priceResult = await prices.dailyBatch(tickers, requested);
  if (priceResult.isErr) {
    const message = FailureCopy.of(priceResult.failureOrNull!);
    return new PortfolioComparison({
      window: requested,
      requestedWindow: requested,
      principalFailure: message,
      reserveFailure: message,
    });
  }
  const priceMap = priceResult.unwrap();

  // Início comum: o mais tardio dos primeiros pregões.
  let start = requested.start;
  let limiting: Ticker | null = null;
  for (const t of tickers) {
    const series = priceMap.get(t);
    if (series === undefined || series.isEmpty) continue;
    if (series.firstDate.isAfter(start)) {
      start = series.firstDate;
      limiting = t;
    }
  }
  const window = new DateRange(start, requested.end);

  const plan = new ContributionPlan({
    initial: goal.initialContribution,
    monthly: goal.monthlyContribution,
    contributionDay: settings.contributionDay,
  });

  const runFor = (portfolio: Portfolio): Result<BacktestOutcome> | null =>
    portfolio.isEmpty
      ? null
      : PortfolioBacktest.run({ portfolio, prices: priceMap, plan, range: window, riskFreeRate: riskFree });

  const principalRun = runFor(principal);
  const reserveRun = runFor(reserve);
  const principalOutcome = principalRun?.isOk ? principalRun.unwrap() : null;
  const reserveOutcome = reserveRun?.isOk ? reserveRun.unwrap() : null;

  return new PortfolioComparison({
    window,
    requestedWindow: requested,
    limitingTicker: limiting,
    principal: principalOutcome,
    reserve: reserveOutcome,
    principalFailure: copyOf(principalRun),
    reserveFailure: copyOf(reserveRun),
    riskReturn: riskReturnPoints({
      principalPortfolio: principal,
      reservePortfolio: reserve,
      prices: priceMap,
      window,
      principal: principalOutcome,
      reserve: reserveOutcome,
    }),
  });
}

/** A janela pedida: [years] anos para trás a partir de [today]. */
export function requestedWindow(today: DateTime, years: number): DateRange {
  return new DateRange(DateTime.local(today.year - years, today.month, today.day), today);
}

/**
 * Monta a dispersão risco × retorno. Cada ativo entra com a volatilidade e o
 * CAGR da **sua própria** série de fechamentos; as carteiras, com as métricas
 * do backtest. A carteira costuma cair à esquerda da nuvem: é a
 * diversificação, visível.
 */
export function riskReturnPoints(args: {
  principalPortfolio: Portfolio;
  reservePortfolio: Portfolio;
  prices: ReadonlyMap<Ticker, PriceSeries>;
  window: DateRange;
  principal: BacktestOutcome | null;
  reserve: BacktestOutcome | null;
}): RiskReturnPoint[] {
  const points: RiskReturnPoint[] = [];
  // Um ticker desenhado duas vezes empilharia rótulos no mesmo pixel; a
  // carteira em que ele aparece primeiro responde por ele.
  const drawn = new Set<Ticker>();

  const addAssets = (portfolio: Portfolio, kind: RiskReturnKind) => {
    for (const t of portfolio.tickers) {
      if (drawn.has(t)) continue;
      drawn.add(t);
      const series = args.prices.get(t);
      if (series === undefined || series.isEmpty) continue;
      const path = closesIn(series, args.window);
      // Menos de um mês de pregões não sustenta desvio-padrão anualizado.
      if (path.dates.length < 21) continue;
      const years = new DateRange(path.dates[0]!, path.dates[path.dates.length - 1]!).years;
      if (years <= 0) continue;
      const first = path.closes[0]!;
      if (first <= 0) continue;
      const totalReturn = path.closes[path.closes.length - 1]! / first - 1;
      points.push({
        label: t.value,
        risk: RiskMetrics.annualizedVolatility(dailyReturns(path.closes)) * 100,
        ret: Returns.annualize(totalReturn, years) * 100,
        kind,
      });
    }
  };
  addAssets(args.principalPortfolio, 'principalAsset');
  addAssets(args.reservePortfolio, 'reserveAsset');

  const addPortfolio = (outcome: BacktestOutcome | null, label: string, kind: RiskReturnKind) => {
    if (outcome === null) return;
    points.push({ label, risk: outcome.metrics.volatility * 100, ret: outcome.metrics.cagr * 100, kind });
  };
  addPortfolio(args.principal, 'Principal', 'principal');
  addPortfolio(args.reserve, 'Reserva', 'reserve');
  return points;
}

/** A matriz de correlação dos ativos, com os tickers na ordem das linhas. */
export interface CorrelationMatrix {
  readonly tickers: readonly Ticker[];
  readonly matrix: readonly (readonly number[])[];
}

/**
 * Matriz de correlação entre os ativos de uma carteira, sobre o `close` —
 * nunca o `adjustedClose` da fonte, que embute provento com ajuste que a
 * auditoria reprovou (§0.4). Todas as séries pareadas pelo calendário comum:
 * correlação sobre datas desencontradas mediria ruído de calendário.
 */
export async function correlationOf(args: {
  tickers: readonly Ticker[];
  window: DateRange;
  prices: PriceRepository;
}): Promise<CorrelationMatrix | null> {
  const { tickers, window } = args;
  if (tickers.length < 2) return null;
  const priceResult = await args.prices.dailyBatch(tickers, window);
  if (priceResult.isErr) return null;
  return correlationFromSeries(tickers, priceResult.unwrap(), window);
}

/** A parte pura de [correlationOf], para o teste. */
export function correlationFromSeries(
  tickers: readonly Ticker[],
  priceMap: ReadonlyMap<Ticker, PriceSeries>,
  window: DateRange,
): CorrelationMatrix | null {
  const available = tickers.filter((t) => priceMap.has(t));
  if (available.length < 2) return null;

  let common = new Set(priceMap.get(available[0]!)!.dates.map((d) => d.key));
  for (const t of available.slice(1)) {
    const keys = new Set(priceMap.get(t)!.dates.map((d) => d.key));
    common = new Set([...common].filter((k) => keys.has(k)));
  }
  const calendar = priceMap
    .get(available[0]!)!
    .dates.filter((d) => common.has(d.key))
    .sort((a, b) => a.compareTo(b));
  if (calendar.length < 30) return null;

  const returns: number[][] = [];
  for (const t of available) {
    const path = closesIn(priceMap.get(t)!, window);
    const byDate = new Map<string, number>();
    path.dates.forEach((d, i) => byDate.set(d.key, path.closes[i]!));
    const series: number[] = [];
    let previous: number | null = null;
    for (const date of calendar) {
      const value = byDate.get(date.key);
      if (value === undefined || value <= 0) continue;
      if (previous !== null && previous > 0) series.push(value / previous - 1);
      previous = value;
    }
    returns.push(series);
  }
  return { tickers: available, matrix: BetaCalculator.correlationMatrix(returns) };
}

/**
 * Fechamentos de uma série dentro da janela. Sem provento no modelo, a
 * trajetória de um ativo **é** a série de `close`.
 */
function closesIn(series: PriceSeries, window: DateRange): { dates: DateTime[]; closes: number[] } {
  const dates: DateTime[] = [];
  const closes: number[] = [];
  for (const p of series.points) {
    if (!window.contains(p.date)) continue;
    dates.push(p.date);
    closes.push(p.close);
  }
  return { dates, closes };
}

/** Retornos simples; pares com fechamento anterior não positivo são descartados. */
function dailyReturns(closes: readonly number[]): number[] {
  const out: number[] = [];
  for (let i = 1; i < closes.length; i++) {
    if (closes[i - 1]! > 0) out.push(closes[i]! / closes[i - 1]! - 1.0);
  }
  return out;
}

/** Diagnóstico de uma simulação sem resultado; `null` quando nem foi simulada. */
function copyOf(run: Result<BacktestOutcome> | null): string | null {
  const failure = run?.failureOrNull ?? null;
  return failure === null ? null : FailureCopy.of(failure);
}
