import {
  type CashDividend,
  DateRange,
  DateTime,
  Duration,
  err,
  FairValueReading,
  FlowBenchmarks,
  InsufficientData,
  InvalidInput,
  isoDay,
  monthsBetween,
  ok,
  PortfolioTracker,
  type PriceSeries,
  projectedEndValue,
  RequiredReturnSolver,
  type Result,
  type Ticker,
  type TrackingOutcome,
  type TrackingRecord,
  type UpsideCohorts,
  type ValuationResult,
} from '../core';
import type { StoredTracking } from '../data/persistence/tracking-store';
import type { Services } from './services';

/** Uma curva de comparação: os mesmos aportes noutro destino. */
export interface TrackingCurve {
  readonly key: 'exigido' | 'esperado' | 'cdi' | 'ibov';
  readonly label: string;
  readonly values: readonly number[];
  /** XIRR da curva, ao ano: a taxa exigida e a esperada são elas mesmas. */
  readonly annual: number | null;
}

/** O acompanhamento pronto para a tela. */
export interface TrackingView {
  readonly record: TrackingRecord;
  readonly outcome: TrackingOutcome;
  /** Taxa anual que a meta exige. */
  readonly required: number | null;
  /** Retorno esperado da carteira congelado no início, ao ano. */
  readonly expected: number | null;
  readonly curves: readonly TrackingCurve[];
  /** Patrimônio que o caminho exigido teria hoje, em reais. */
  readonly requiredNow: number | null;
  /** Meses de prazo que faltam, contados do último pregão. */
  readonly remainingMonths: number;
  /** Onde a carteira chega no fim do prazo no ritmo do XIRR de agora. */
  readonly projectedAtPace: number | null;
  /** Última coorte do pacote, ou `null` sem pacote. */
  readonly lastCohort: DateTime | null;
  readonly notes: readonly string[];
}

/** O acompanhamento ainda sem pregão a partir da data de início. */
export interface TrackingWaiting {
  readonly record: TrackingRecord;
  readonly waiting: true;
}

/** Folga de cotação antes do início: a coorte vigente na data de início pode ser de até um trimestre antes. */
const PRICE_LEAD_DAYS = 130;

/** Preço justo de hoje pelo motor, para os aportes ao vivo. */
export function liveReading(v: ValuationResult): FairValueReading {
  return new FairValueReading({
    ticker: v.ticker,
    fairValue: v.fairValue.reais,
    origin: 'motor',
    asOf: v.asOf,
    costOfEquity: v.diagnostics?.costOfEquity ?? null,
  });
}

/**
 * **Monta o acompanhamento** de [stored] até [today] (decisão 159): cotações,
 * proventos, coortes e — só se houver aporte ao vivo vencido — as avaliações
 * de hoje, e então os benchmarks com os mesmos aportes.
 *
 * As avaliações ao vivo são pedidas **depois** de uma primeira passada sem
 * elas: a cascata custa segundos por ativo, e na maioria das aberturas não há
 * aporte vencido para decidir.
 */
export async function computeTracking(args: {
  services: Services;
  stored: StoredTracking;
  today: DateTime;
  live: (tickers: readonly Ticker[]) => Promise<ReadonlyMap<Ticker, ValuationResult>>;
}): Promise<Result<TrackingView | TrackingWaiting>> {
  const { services, stored, today } = args;
  const { record } = stored;
  const plan = record.plan;
  const range = new DateRange(plan.start.subtract(new Duration({ days: PRICE_LEAD_DAYS })), today);

  const batch = await services.prices.dailyBatch(plan.tickers, range);
  if (batch.isErr) return err(batch.failureOrNull!);
  const prices: Map<Ticker, PriceSeries> = batch.unwrap();
  const hasStartPrice = [...prices.values()].some((s) => !s.isEmpty && !s.points[s.points.length - 1]!.date.isBefore(plan.start));
  if (!hasStartPrice) return ok({ record, waiting: true });

  const [cohorts, dividendLists] = await Promise.all([
    services.upsideCohorts(),
    Promise.all(plan.tickers.map(async (t) => [t, await services.dividends(t)] as const)),
  ]);
  const dividends = new Map<Ticker, readonly CashDividend[]>(dividendLists);
  const retro = (t: Ticker, d: DateTime) => cohorts?.readingAt(t, d, prices.get(t)) ?? null;

  const base = { plan, prices, dividends, recorded: stored.orders, until: today, retro };
  let run = PortfolioTracker.run(base);
  if (run.isErr) return err(run.failureOrNull!);
  if (run.unwrap().pendingLive > 0) {
    const valuations = await args.live(plan.tickers);
    const readings = new Map<Ticker, FairValueReading>();
    for (const [t, v] of valuations) readings.set(t, liveReading(v));
    run = PortfolioTracker.run({ ...base, live: (t) => readings.get(t) ?? null });
    if (run.isErr) return err(run.failureOrNull!);
  }
  const outcome = run.unwrap();
  return ok(await assemble({ services, record, outcome, cohorts }));
}

async function assemble(args: {
  services: Services;
  record: TrackingRecord;
  outcome: TrackingOutcome;
  cohorts: UpsideCohorts | null;
}): Promise<TrackingView> {
  const { services, record, outcome, cohorts } = args;
  const { dates, flowCents } = outcome;
  const window = new DateRange(dates[0]!, dates[dates.length - 1]!);
  const notes: string[] = [...outcome.warnings];

  const solved = RequiredReturnSolver.solve(record.goal);
  const required = solved.isOk ? solved.unwrap().annual : null;
  const expected = record.expectedReturn;

  const curves: TrackingCurve[] = [];
  let requiredNow: number | null = null;
  if (required !== null && Number.isFinite(required) && required > -1) {
    const values = FlowBenchmarks.atAnnualRate({ dates, flowCents, annual: required });
    requiredNow = values[values.length - 1] ?? null;
    curves.push({ key: 'exigido', label: 'Exigido pela meta', values, annual: required });
  }
  if (expected !== null && Number.isFinite(expected) && expected > -1) {
    curves.push({
      key: 'esperado',
      label: 'Esperado da carteira',
      values: FlowBenchmarks.atAnnualRate({ dates, flowCents, annual: expected }),
      annual: expected,
    });
  }

  const [cdi, ibov] = await Promise.all([services.macro.riskFreeDaily(window), services.benchmark.ibovespa(window)]);
  if (cdi.isOk && !cdi.unwrap().isEmpty) {
    const { values, covered } = FlowBenchmarks.onDailyRates({ dates, flowCents, rates: cdi.unwrap() });
    curves.push({ key: 'cdi', label: 'CDI realizado', values, annual: FlowBenchmarks.moneyWeighted({ dates, flowCents, values }) });
    if (!covered) notes.push('A série do CDI do Banco Central não cobre o período inteiro: a curva do CDI subestima o rendimento.');
  } else {
    notes.push('Sem a série do CDI do Banco Central: a comparação com a renda fixa ficou de fora.');
  }
  if (ibov.isOk) {
    const values = FlowBenchmarks.onIndex({ dates, flowCents, index: ibov.unwrap() });
    if (values !== null) {
      curves.push({ key: 'ibov', label: 'Ibovespa realizado', values, annual: FlowBenchmarks.moneyWeighted({ dates, flowCents, values }) });
    } else {
      notes.push('A série do Ibovespa não cobre o início do acompanhamento: a comparação com a bolsa ficou de fora.');
    }
  } else {
    notes.push('Sem a série do Ibovespa: a comparação com a bolsa ficou de fora.');
  }

  const last = outcome.lastDate;
  const remainingMonths = Math.max(0, monthsBetween(last, record.endDate));
  const xirr = outcome.moneyWeightedReturn;
  const projectedAtPace =
    xirr === null
      ? null
      : projectedEndValue({
          currentWealth: outcome.finalValueCents / 100,
          monthlyContribution: record.plan.monthly.reais,
          remainingMonths,
          annual: xirr,
        });

  const lastCohort = cohorts?.lastDate ?? null;
  if (outcome.staleOrders > 0 && lastCohort !== null) {
    notes.push(
      `${outcome.staleOrders} compra(s) usaram o preço justo da última coorte (${isoDay(lastCohort)}) contra o preço do dia, ` +
        'porque não há coorte mais recente.',
    );
  }
  if (outcome.pendingLive > 0) {
    notes.push(`${outcome.pendingLive} aporte(s) vencido(s) esperam a avaliação do motor para comprar.`);
  }

  return {
    record,
    outcome,
    required,
    expected,
    curves,
    requiredNow,
    remainingMonths,
    projectedAtPace,
    lastCohort,
    notes,
  };
}

/** Mensagem da recusa ao iniciar, ou `null` quando a data serve. */
export function startDateProblem(args: { start: DateTime; today: DateTime; cohorts: UpsideCohorts | null }): string | null {
  const { start, today, cohorts } = args;
  const key = (d: DateTime) => d.year * 10000 + d.month * 100 + d.day;
  if (key(start) > key(today)) return 'A data de início não pode estar no futuro.';
  if (key(start) === key(today)) return null;
  if (cohorts === null || cohorts.firstDate === null) {
    return 'Sem o pacote das coortes, o acompanhamento só pode começar hoje: não há preço justo ponto no tempo para o passado.';
  }
  if (key(start) < key(cohorts.firstDate)) {
    return `A primeira coorte ponto no tempo é de ${isoDay(cohorts.firstDate)}: antes dela não há preço justo daquela data.`;
  }
  return null;
}

/** Valida o pedido de início. */
export function validateStart(args: { tickers: readonly Ticker[]; problem: string | null }): Result<void> {
  if (args.tickers.length === 0) return err(new InvalidInput('Monte a carteira Principal antes de iniciar o acompanhamento.'));
  if (args.problem !== null) return err(new InsufficientData(args.problem));
  return ok(undefined);
}

/** Hoje como dia civil local. */
export function civilToday(clock: () => DateTime): DateTime {
  const now = clock();
  return DateTime.local(now.year, now.month, now.day);
}
