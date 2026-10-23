/**
 * Oráculo de paridade, lado TypeScript.
 *
 * Refaz, passo a passo, o que `test/parity/dart/harness.dart` fez sobre o
 * núcleo Dart original compilado para JavaScript: lê os pacotes versionados de
 * `assets/` (CVM, B3, Tesouro, mercado, validação), monta um mercado sintético
 * **determinístico** — cotações, Ibovespa, CDI, IPCA e IBC-Br sorteados pelo
 * mesmo gerador `Random(seed)` do Dart, que `SeededRandom` reproduz bit a bit —
 * e avalia cada ativo em treze montagens da cascata.
 *
 * O gabarito gravado pelo lado Dart está em `test/parity/golden/`. A suíte
 * `cascade-parity.test.ts` compara as duas saídas campo a campo; o rastro de
 * auditoria de cada avaliação entra pela impressão SHA-256 do JSON que o
 * `jsonEncode` do Dart produziria.
 *
 * **Por que um mercado sintético, e não o real.** Os fundamentos são os da CVM
 * empacotados no repositório, mas as cotações vêm da brapi pela rede, e o
 * gabarito tem de se reproduzir sem rede. O sintético é ancorado no
 * patrimônio publicado de cada companhia, para que os caminhos da cascata
 * sejam os de dado real.
 */

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  Asset,
  AuditRecorder,
  B3RegistryCodec,
  BetaPriorCodec,
  BrazilianCalendar,
  ContributionPlan,
  EvaluateGoalAlignment,
  ExpectedReturn,
  FinancialGoal,
  GoalFeasibility,
  ManualField,
  ManualGrowthPath,
  ManualRatePath,
  ManualReinvestment,
  ManualValuationRecord,
  Money,
  Portfolio,
  PortfolioBacktest,
  PortfolioEntry,
  PortfolioKind,
  RequiredReturnSolver,
  SectorConcentration,
  SkillReadingCodec,
  SwapAssetBetweenPortfolios,
  TransactionCosts,
  TransversalOrdering,
  TransversalSignals,
  Weight,
  CalibratedBand,
  CalibratedBandCodec,
  CapitalEventsCodec,
  CapmInputs,
  CashDividendsCodec,
  CashTiming,
  ConcessionTermsCodec,
  CvmDocumentCodec,
  CvmDocumentKind,
  CvmSeries,
  DateTime,
  FundamentalsSnapshot,
  ImpliedPremiumCodec,
  InsufficientData,
  MarketAnchors,
  MarketPremiumSource,
  OfficialShareCount,
  PeerMultipleCodec,
  PointInTimeView,
  PrepareValuationInputs,
  PricePoint,
  PriceSeries,
  RatePoint,
  RateSeries,
  ReinvestmentPolicy,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  SeededRandom,
  Sector,
  ShareholderControl,
  ShareholderControlHistory,
  StochasticScenarios,
  Ticker,
  TimeBasis,
  TreasuryCurve,
  TreasuryQuotesCodec,
  UnitCompositionCodec,
  ValuationCascade,
  ValuationLane,
  err,
  ok,
  round,
  roundToDouble,
  str,
  DateRange as DateRangeClass,
  type AuditEvent,
  type B3Issuer,
  type BacktestOutcome,
  type GoalAlignment,
  type ManualOutcome,
  type ManualPremises,
  type ManualValuation,
  type SkillReading,
  type BaseNormalization,
  type BenchmarkRepository,
  type CalibratedBandTable,
  type CashDividend,
  type CvmPeriodDocument,
  type DateRange,
  type Failure,
  type FundamentalsRepository,
  type JsonObject,
  type MacroRepository,
  type PeerTriangulation,
  type PriceRepository,
  type Result,
  type ShareholderControlPeriod,
  type ValuationDiagnostics,
  type ValuationInputs,
  type ValuationResult,
  type YieldCurve,
} from '../../src/core';

/** Data de referência do oráculo: o dia seguinte à data-base da curva empacotada. */
export const ORACLE_AS_OF = DateTime.local(2026, 10, 16);

const asOf = ORACLE_AS_OF;

// ── Serialização no formato do `jsonEncode` do Dart na web ─────────────────

/**
 * O texto que o `jsonEncode` do Dart compilado para JavaScript produz.
 *
 * Igual ao `JSON.stringify` em tudo, menos no número: o Dart escreve
 * `double.toString()`, que é o `String(x)` do JavaScript exceto no `-0.0`.
 * É a diferença que importa para a impressão do rastro.
 */
export function dartJsonEncode(value: unknown): string {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error(`Converting object to an encodable object failed: ${value}`);
    return str(value);
  }
  if (typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (Array.isArray(value)) return `[${value.map(dartJsonEncode).join(',')}]`;
  if (value instanceof Map) {
    const parts: string[] = [];
    for (const [k, v] of value) parts.push(`${JSON.stringify(String(k))}:${dartJsonEncode(v)}`);
    return `{${parts.join(',')}}`;
  }
  if (typeof value === 'object') {
    const parts: string[] = [];
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      parts.push(`${JSON.stringify(k)}:${dartJsonEncode(v)}`);
    }
    return `{${parts.join(',')}}`;
  }
  throw new Error(`Converting object to an encodable object failed: ${String(value)}`);
}

/** SHA-256 em hexadecimal do texto em UTF-8. */
export function sha256(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

// ── Utilitários numéricos ─────────────────────────────────────────────────

function n(x: number | null | undefined): number | string | null {
  if (x === null || x === undefined) return null;
  if (Number.isFinite(x)) return x;
  return Number.isNaN(x) ? 'NaN' : x > 0 ? 'Infinity' : '-Infinity';
}

function normal(r: SeededRandom): number {
  const u1 = r.nextDouble();
  const u2 = r.nextDouble();
  return Math.sqrt(-2 * Math.log(1 - u1)) * Math.cos(2 * Math.PI * u2);
}

function round2(x: number): number {
  return round(x * 100) / 100;
}

function businessDays(from: DateTime, to: DateTime): DateTime[] {
  const out: DateTime[] = [];
  let d = from;
  while (!d.isAfter(to)) {
    if (d.weekday <= 5) out.push(d);
    d = DateTime.local(d.year, d.month, d.day + 1);
  }
  return out;
}

// ── Mercado sintético ─────────────────────────────────────────────────────

interface Market {
  readonly days: DateTime[];
  readonly marketReturns: number[];
  readonly ibovespa: PriceSeries;
  readonly prices: Map<string, PriceSeries>;
  readonly snapshots: Map<string, FundamentalsSnapshot[]>;
  readonly profiles: Map<string, Asset>;
  readonly failedProfiles: Set<string>;
  readonly distressed: Set<string>;
}

const SECTOR_KEYS = [
  'servicos-financeiros',
  'energia',
  'materiais-basicos',
  'consumo',
  'saneamento',
  'tecnologia',
  'saude',
  'industria',
  '',
];

function copyAs(
  c: FundamentalsSnapshot,
  t: Ticker,
  marketCap: number | null,
  shares: number | null,
): FundamentalsSnapshot {
  return new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: c.fiscalPeriodEnd,
    totalRevenue: c.totalRevenue,
    ebit: c.ebit,
    ebitda: c.ebitda,
    netIncome: c.netIncome,
    incomeBeforeTax: c.incomeBeforeTax,
    incomeTaxExpense: c.incomeTaxExpense,
    interestExpense: c.interestExpense,
    earningsPerShare: c.earningsPerShare,
    nopat: c.nopat,
    cash: c.cash,
    shortTermInvestments: c.shortTermInvestments,
    shortTermDebt: c.shortTermDebt,
    longTermDebt: c.longTermDebt,
    totalStockholderEquity: c.totalStockholderEquity,
    bookValuePerShare: c.bookValuePerShare,
    propertyPlantEquipment: c.propertyPlantEquipment,
    intangibleAssets: c.intangibleAssets,
    totalCurrentAssets: c.totalCurrentAssets,
    currentLiabilities: c.currentLiabilities,
    realizedShareCapital: c.realizedShareCapital,
    profitReserves: c.profitReserves,
    operatingCashFlow: c.operatingCashFlow,
    investmentCashFlow: c.investmentCashFlow,
    freeCashFlow: c.freeCashFlow,
    sharesOutstanding: shares,
    sharesOutstandingAsOf: c.sharesOutstandingAsOf,
    marketCap,
    enterpriseToEbitda: c.enterpriseToEbitda,
    minorityInterest: c.minorityInterest,
    equityIncomeResult: c.equityIncomeResult,
    receiptDate: null,
    treasuryShares: c.treasuryShares,
    treasuryFraction: c.treasuryFraction,
    totalAssets: c.totalAssets,
  });
}

function buildMarket(
  tickers: readonly string[],
  docs: ReadonlyMap<string, readonly CvmPeriodDocument[]>,
  registry: ReadonlyMap<string, B3Issuer>,
): Market {
  const days = businessDays(DateTime.local(2011, 1, 3), asOf);
  const ibovRng = new SeededRandom(20260914);
  let level = 60000.0;
  const rm: number[] = [];
  const ibovPoints: PricePoint[] = [];
  for (const d of days) {
    const r = 0.0004 + 0.013 * normal(ibovRng);
    level *= Math.exp(r);
    rm.push(r);
    ibovPoints.push(new PricePoint({ date: d, close: round2(level) }));
  }
  const ibovespa = new PriceSeries({ ticker: Ticker.parse('IBOV11'), points: ibovPoints });

  const prices = new Map<string, PriceSeries>();
  const snapshots = new Map<string, FundamentalsSnapshot[]>();
  const profiles = new Map<string, Asset>();
  const failed = new Set<string>();
  const distressed = new Set<string>();
  for (let i = 0; i < tickers.length; i++) {
    const code = tickers[i]!;
    const t = Ticker.parse(code);
    const rng = new SeededRandom(1000 + i);
    const beta = 0.3 + 1.4 * rng.nextDouble();
    const idio = 0.008 + 0.025 * rng.nextDouble();
    const drift = -0.0002 + 0.0006 * rng.nextDouble();
    const pbShock = normal(rng);
    const liquidityShock = normal(rng);
    const fallbackPrice = 5 + 45 * rng.nextDouble();
    const sharesDraw = rng.nextDouble();

    // O último DFP publicado ancora o nível de preço.
    const dfps = (docs.get(code) ?? [])
      .filter((d) => d.kind === CvmDocumentKind.dfp && !d.periodEnd.isAfter(asOf))
      .sort((a, b) => a.periodEnd.compareTo(b.periodEnd));
    const last = dfps.length === 0 ? null : dfps[dfps.length - 1]!.current;
    const equity = last?.totalStockholderEquity ?? null;
    const shares =
      last?.sharesOutstanding ?? registry.get(code.substring(0, 4))?.totalShares ?? roundToDouble(1e8 * (1 + 9 * sharesDraw));
    let target = equity !== null && equity > 0 && shares > 0 ? (Math.exp(-0.3 + 0.6 * pbShock) * equity) / shares : fallbackPrice;
    if (target < 0.5) target = 0.5;
    if (target > 500) target = 500;

    let start = 0;
    if (i % 17 === 0) start = days.length - 200;
    const cum: number[] = [];
    let acc = 0.0;
    for (let k = start; k < days.length; k++) {
      acc += drift + beta * (rm[k]! - 0.0004) + idio * normal(rng);
      cum.push(acc);
    }
    const points: PricePoint[] = [];
    const tradedValue = Math.exp(Math.log(1.2e7) + 1.4 * liquidityShock);
    const lastCum = cum[cum.length - 1]!;
    for (let k = 0; k < cum.length; k++) {
      let close = round2(target * Math.exp(cum[k]! - lastCum));
      if (close < 0.01) close = 0.01;
      const volume = i % 13 === 0 ? null : roundToDouble((tradedValue / close) * Math.exp(0.3 * normal(rng)));
      points.push(new PricePoint({ date: days[start + k]!, close, volume }));
    }
    if (i % 23 !== 0) prices.set(code, new PriceSeries({ ticker: t, points }));

    // Fundamentos «de mercado»: valor de mercado e ações no fim de cada ano;
    // um em cada quatro ativos traz o exercício inteiro, como a brapi.
    const market: FundamentalsSnapshot[] = [];
    for (let y = 2011; y <= 2025; y++) {
      const end = DateTime.local(y, 12, 31);
      let atEnd: PricePoint | null = null;
      for (const p of points) {
        if (!p.date.isAfter(end)) atEnd = p;
      }
      let dfpOfYear: FundamentalsSnapshot | null = null;
      for (const d of dfps) {
        if (d.periodEnd.year === y) dfpOfYear = d.current;
      }
      const s = dfpOfYear?.sharesOutstanding ?? shares;
      const cap = atEnd === null ? null : atEnd.close * s;
      if (i % 4 === 0 && dfpOfYear !== null) {
        market.push(copyAs(dfpOfYear, t, cap, s));
      } else {
        market.push(new FundamentalsSnapshot({ ticker: t, fiscalPeriodEnd: end, marketCap: cap, sharesOutstanding: s }));
      }
    }
    snapshots.set(code, market);

    if (i % 11 === 0) {
      failed.add(code);
    } else {
      const key = SECTOR_KEYS[i % SECTOR_KEYS.length]!;
      profiles.set(
        code,
        new Asset({
          ticker: t,
          name: `Companhia ${code}`,
          sector: key.length === 0 ? Sector.unknown : Sector.fromKey(key, { label: key }),
          industry: i % 5 === 0 ? 'Energia Elétrica' : null,
        }),
      );
    }
    if (i % 37 === 5) distressed.add(code);
  }
  return { days, marketReturns: rm, ibovespa, prices, snapshots, profiles, failedProfiles: failed, distressed };
}

// ── Repositórios em memória ───────────────────────────────────────────────

class MemoryPrices implements PriceRepository {
  constructor(private readonly m: Market) {}

  async daily(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    const s = this.m.prices.get(ticker.value);
    if (s === undefined) {
      return err(new InsufficientData(`Sem cotações de ${ticker.value}.`, { subject: ticker.value }));
    }
    return ok(new PriceSeries({ ticker, points: s.points.filter((p) => range.contains(p.date)) }));
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

class MemoryBenchmark implements BenchmarkRepository {
  constructor(private readonly m: Market) {}

  async ibovespa(range: DateRange): Promise<Result<PriceSeries>> {
    return ok(
      new PriceSeries({
        ticker: this.m.ibovespa.ticker,
        points: this.m.ibovespa.points.filter((p) => range.contains(p.date)),
      }),
    );
  }
}

class MemoryMacro implements MacroRepository {
  constructor(private readonly m: Market) {}

  async riskFreeDaily(range: DateRange): Promise<Result<RateSeries>> {
    const pts: RatePoint[] = [];
    for (let k = 0; k < this.m.days.length; k++) {
      const d = this.m.days[k]!;
      if (!range.contains(d)) continue;
      const annual = 0.1 + 0.04 * Math.sin(k / 400);
      pts.push(new RatePoint({ date: d, rate: Math.pow(1 + annual, 1 / 252) - 1 }));
    }
    return ok(new RateSeries(pts));
  }

  private months(range: DateRange): DateTime[] {
    const out: DateTime[] = [];
    for (let y = 2011; y <= 2026; y++) {
      for (let mo = 1; mo <= 12; mo++) {
        if (range.contains(DateTime.local(y, mo, 1))) out.push(DateTime.local(y, mo, 1));
      }
    }
    return out;
  }

  async inflationMonthly(range: DateRange): Promise<Result<RateSeries>> {
    const ms = this.months(range);
    return ok(
      new RateSeries(
        ms.map((d, k) => new RatePoint({ date: d, rate: 0.0035 + 0.0015 * Math.sin(k / 5) })),
        { basis: TimeBasis.monthly },
      ),
    );
  }

  async activityIndexMonthly(range: DateRange): Promise<Result<RateSeries>> {
    const ms = this.months(range);
    return ok(
      new RateSeries(
        ms.map((d, k) => new RatePoint({ date: d, rate: 130 * Math.pow(1.002, k) * (1 + 0.01 * Math.sin(k / 3)) })),
        { basis: TimeBasis.monthly },
      ),
    );
  }
}

class MemoryFundamentals implements FundamentalsRepository {
  constructor(
    private readonly m: Market,
    private readonly all: Ticker[],
  ) {}

  async history(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const s = this.m.snapshots.get(ticker.value);
    if (s === undefined) return err(new InsufficientData(`Sem exercícios de ${ticker.value}.`));
    return ok(s);
  }

  async profile(ticker: Ticker): Promise<Result<Asset>> {
    const p = this.m.profiles.get(ticker.value);
    if (p === undefined) return err(new InsufficientData(`Perfil de ${ticker.value} indisponível.`));
    return ok(p);
  }

  async universe(): Promise<Result<Ticker[]>> {
    return ok(this.all);
  }
}

class FromCvm implements FundamentalsRepository {
  constructor(
    private readonly market: FundamentalsRepository,
    private readonly docs: ReadonlyMap<string, readonly CvmPeriodDocument[]>,
    private readonly anchored = false,
  ) {}

  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const base = await this.market.history(t);
    if (base.isErr) return base;
    const own = this.docs.get(t.value);
    if (own === undefined || own.length === 0) return base;
    const view = new PointInTimeView(asOf);
    return ok([
      ...CvmSeries.build({
        documents: own,
        market: base.unwrap(),
        published: (s) => view.isPublished(s),
        anchored: this.anchored,
      }).series,
    ]);
  }

  profile(t: Ticker): Promise<Result<Asset>> {
    return this.market.profile(t);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.market.universe();
  }
}

class OfficialSector implements FundamentalsRepository {
  constructor(
    private readonly inner: FundamentalsRepository,
    private readonly registry: ReadonlyMap<string, B3Issuer>,
  ) {}

  history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    return this.inner.history(t);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.inner.universe();
  }

  async profile(ticker: Ticker): Promise<Result<Asset>> {
    const profile = await this.inner.profile(ticker);
    const t = ticker.value;
    const official = t.length < 4 ? null : (this.registry.get(t.substring(0, 4))?.classification ?? null);
    if (official === null) return profile;
    const sector = new Sector({ key: official.sectorKey, label: official.sector });
    const industry = official.industry.length === 0 ? null : official.industry;
    return ok(
      new Asset({
        ticker,
        name: profile.isOk ? profile.unwrap().name : ticker.value,
        sector,
        industry,
      }),
    );
  }
}

// ── Serialização ──────────────────────────────────────────────────────────

type Json = unknown;

function failureJson(f: Failure): Record<string, Json> {
  return { falha: f.runtimeType, mensagem: f.message };
}

function normalizationJson(b: BaseNormalization | null): Json {
  if (b === null) return null;
  return {
    lane: b.lane.name,
    latestYear: b.latestYear,
    latestReturn: n(b.latestReturn),
    cycleWindow: b.cycleWindow.map((w) => [w.year, n(w.value)]),
    cycleReturn: n(b.cycleReturn),
    ratio: n(b.ratio),
    robustZ: n(b.robustZ),
    deviates: b.deviates,
    trendSlope: n(b.trendSlope),
    trendT: n(b.trendT),
    trendCriticalT: n(b.trendCriticalT),
    trendDominates: b.trendDominates,
    cyclicalPrecedence: b.cyclicalPrecedence,
    operationalDecline: n(b.operationalDecline),
    healthCapped: b.healthCapped,
    healthExempt: b.healthExempt,
    rawFactor: n(b.rawFactor),
    factor: n(b.factor),
    saturated: b.saturated,
    rebuilt: b.rebuilt,
    rebuiltPositiveShare: n(b.rebuiltPositiveShare),
    imposed: b.imposed,
    publishedProfit: n(b.publishedProfit),
    baseProfit: n(b.baseProfit),
    outcome: b.outcome.key,
  };
}

function diagnosticsJson(d: ValuationDiagnostics | null): Json {
  if (d === null) return null;
  return {
    terminalShare: n(d.terminalShare),
    equityShare: n(d.equityShare),
    baseFactor: n(d.baseFactor),
    growthIdentified: d.growthIdentified,
    moatApplied: d.moatApplied,
    terminalDiscountRate: n(d.terminalDiscountRate),
    terminalRetainedSpread: n(d.terminalRetainedSpread),
    growthRate: n(d.growthRate),
    returnOnCapital: n(d.returnOnCapital),
    terminalReturnOnCapital: n(d.terminalReturnOnCapital),
    firmTaxRate: n(d.firmTaxRate),
    terminalCostOfEquity: n(d.terminalCostOfEquity),
    costOfEquity: n(d.costOfEquity),
    retentionPath: d.retentionPath.map((x) => n(x)),
    growthPath: d.growthPath.map((x) => n(x)),
    terminalExcessShare: n(d.terminalExcessShare),
    impliedTerminalReturn: n(d.impliedTerminalReturn),
    terminalEquityShare: n(d.terminalEquityShare),
    postStatementCapital: n(d.postStatementCapital),
    baseNormalization: normalizationJson(d.baseNormalization),
    caveats: d.caveats.map((c) => c.key),
  };
}

function triangulationJson(t: PeerTriangulation | null): Json {
  if (t === null) return null;
  return {
    readings: t.readings.map((r) => ({
      kind: r.kind.key,
      fairValuePerShare: n(r.fairValuePerShare),
      peer: r.peer === null ? null : { median: n(r.peer.median), peers: r.peer.peers, group: r.peer.group },
      refusal: r.refusal?.key ?? null,
      applied: r.applied,
    })),
    consolidated: n(t.consolidated),
    divergence: n(t.divergence),
    asOf: t.asOf.toIso8601String(),
    applied: t.applied,
    diverges: t.diverges,
  };
}

function resultJson(r: Result<ValuationResult>, bandTables: readonly CalibratedBandTable[]): Record<string, Json> {
  if (r.isErr) return failureJson(r.failureOrNull!);
  const v = r.unwrap();
  const dist = v.distribution;
  const scenarios = v.discreteScenarios;
  return {
    ticker: v.ticker.value,
    asOf: v.asOf.toIso8601String(),
    model: v.model.name,
    fairValue: v.fairValue.cents,
    marketPrice: v.marketPrice.cents,
    discountRate: n(v.discountRate),
    marginOfSafety: n(v.marginOfSafety),
    mode: v.mode.name,
    discreteScenarios:
      scenarios === null ? null : Object.fromEntries([...scenarios.entries()].map(([k, m]) => [k.name, m.cents])),
    distribution:
      dist === null
        ? null
        : {
            n: dist.sortedValues.length,
            p5: n(dist.p5),
            median: n(dist.median),
            p95: n(dist.p95),
            mean: n(dist.mean),
            aboveMarket: n(dist.probabilityAbove(v.marketPrice.reais)),
            values: dist.sortedValues.map(str).join(','),
          },
    warnings: [...v.warnings],
    diagnostics: diagnosticsJson(v.diagnostics),
    priceVolatility: n(v.priceVolatility),
    triangulation: triangulationJson(v.triangulation),
    safetyPrice: v.safetyPrice.cents,
    upside: n(v.upside),
    isUndervalued: v.isUndervalued,
    bands: bandTables.map((t) => {
      const b = CalibratedBand.of(v.fairValue, t, { marketPrice: v.marketPrice, volatility: v.priceVolatility });
      return b === null ? null : [t.months, b.low.cents, b.high.cents];
    }),
  };
}

// ── Execução ──────────────────────────────────────────────────────────────

/** O que o oráculo produz: o cabeçalho e as linhas por ativo. */
export interface OracleOutput {
  readonly header: Record<string, Json>;
  readonly rows: Record<string, Record<string, Record<string, Json>>>;
  /** Os serviços além da cascata: manual, simulação histórica, metas, calendário. */
  readonly services: Record<string, Json>;
  /** O JSON de cada rastro, quando pedido — para achar a divergência. */
  readonly traces: Map<string, string>;
}

function readPackage(repo: string, name: string): JsonObject {
  return JSON.parse(readFileSync(join(repo, name), 'utf8')) as JsonObject;
}

/**
 * Roda o oráculo sobre o repositório em [repo].
 *
 * - [limit]: quantos ativos avaliar, na ordem alfabética; `0` para todos.
 * - [keepTraces]: guardar o JSON de cada rastro, além da impressão.
 */
export async function runOracle(options: { repo: string; limit?: number; keepTraces?: boolean }): Promise<OracleOutput> {
  const { repo } = options;
  const limit = options.limit ?? 0;
  const keepTraces = options.keepTraces ?? false;
  const traces = new Map<string, string>();
  const hashes = new Map<string, string>();

  const curve = TreasuryCurve.at(TreasuryQuotesCodec.decode(readPackage(repo, 'assets/tesouro/curva.json')), asOf);
  const registry = B3RegistryCodec.decodePackage(readPackage(repo, 'assets/b3/emissores.json'));
  const docs = CvmDocumentCodec.decodePackage(readPackage(repo, 'assets/cvm/documentos.json'));
  const terms = ConcessionTermsCodec.decode(readPackage(repo, 'assets/cvm/outorgas.json'));
  const dividends = CashDividendsCodec.decode(readPackage(repo, 'assets/b3/proventos.json'));
  const packagePrior = BetaPriorCodec.decode(readPackage(repo, 'assets/mercado/beta_prior.json'));
  const premiumPackage = ImpliedPremiumCodec.decode(readPackage(repo, 'assets/mercado/premio_implicito.json'));
  const packagePremium = premiumPackage?.normalizedAt(asOf) ?? null;
  const capital = CapitalEventsCodec.decodePackage(readPackage(repo, 'assets/cvm/capital.json'));
  const units = UnitCompositionCodec.decodePackage(readPackage(repo, 'assets/cvm/units.json'));
  const control: ReadonlyMap<string, readonly ShareholderControlPeriod[]> =
    ShareholderControlHistory.decode(readPackage(repo, 'assets/cvm/controle.json'))?.byIssuer ?? new Map();
  const peers = PeerMultipleCodec.decode(readPackage(repo, 'assets/mercado/multiplos_setoriais.json'));
  const bandTables = CalibratedBandCodec.decode(readPackage(repo, 'assets/validacao/banda_calibrada.json'));

  const codes = [...docs.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const tickers = codes.map((c) => Ticker.parse(c));
  const market = buildMarket(codes, docs, registry);
  const memory = new MemoryFundamentals(market, tickers);
  const prices = new MemoryPrices(market);
  const benchmark = new MemoryBenchmark(market);
  const macro = new MemoryMacro(market);

  const stateOwned = (t: Ticker): boolean => {
    const p = control.get(t.value.substring(0, 4));
    return p !== undefined && ShareholderControlHistory.at(p, asOf) === ShareholderControl.state;
  };

  let lastEvent: AuditEvent | null = null;
  AuditRecorder.attach((e) => {
    lastEvent = e;
  });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro, benchmark, asOf })).getOrElse(MarketAnchors.fallback2026);

    const withSector = new OfficialSector(new FromCvm(memory, docs), registry);
    const anchoredWithSector = new OfficialSector(new FromCvm(memory, docs, true), registry);
    const dividendsOf = (t: Ticker): CashDividend[] => CashDividendsCodec.forTicker(dividends, t.value);

    const prior = await ResolveBetaPrior.call({
      tickers,
      prices,
      fundamentals: withSector,
      benchmark,
      asOf,
      dividendsFor: dividendsOf,
    });

    const header: Record<string, Json> = {
      asOf: asOf.toIso8601String(),
      tickers: codes.length,
      anchors: {
        riskFreeCagr: n(anchors.riskFreeCagr),
        currentRiskFreeRate: n(anchors.currentRiskFreeRate),
        marketCagr: n(anchors.marketCagr),
        inflationCagr: n(anchors.inflationCagr),
        realEconomyGrowth: n(anchors.realEconomyGrowth),
        observedYears: anchors.observedYears,
        nominalEconomyGrowth: n(anchors.nominalEconomyGrowth),
      },
      curve:
        curve === null
          ? null
          : {
              referenceDate: curve.referenceDate.toIso8601String(),
              vertices: curve.vertices.map((v) => [n(v.years), n(v.rate)]),
            },
      premium: n(packagePremium),
      packagePrior:
        packagePrior === null
          ? null
          : {
              universe: n(packagePrior.prior.unleveredUniverse),
              dispersion: n(packagePrior.prior.dispersion),
              sectors: Object.fromEntries([...packagePrior.prior.unleveredBySector.entries()].map(([k, v]) => [k, n(v)])),
            },
      resolvedPrior:
        prior === null
          ? null
          : {
              universe: n(prior.unleveredUniverse),
              dispersion: n(prior.dispersion),
              sectors: Object.fromEntries([...prior.unleveredBySector.entries()].map(([k, v]) => [k, n(v)])),
            },
      bandTables: bandTables.length,
    };

    const prepare = (
      t: Ticker,
      a: {
        fundamentals: FundamentalsRepository;
        c?: YieldCurve | null;
        app?: boolean;
        withPrior?: boolean;
        marginOfSafety?: number;
        projectionYears?: number;
      },
    ): Promise<Result<ValuationInputs>> => {
      const app = a.app ?? false;
      const e = t.value.length < 4 ? null : (registry.get(t.value.substring(0, 4)) ?? null);
      const totalShares = e?.totalShares ?? null;
      return PrepareValuationInputs.call({
        ticker: t,
        prices,
        fundamentals: a.fundamentals,
        benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf,
        marketPremium: app && packagePremium !== null ? packagePremium : CapmInputs.defaultMarketPremium,
        premiumSource:
          app && packagePremium !== null ? MarketPremiumSource.impliedNormalized : MarketPremiumSource.parameterized,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: a.c ?? null,
        marginOfSafety: a.marginOfSafety ?? 0.0,
        projectionYears: a.projectionYears ?? 10,
        officialShares:
          app && e !== null && totalShares !== null ? new OfficialShareCount({ total: totalShares, asOf: e.consultedOn }) : null,
        isDistressed: app && market.distressed.has(t.value),
        concessionEnd: app ? (terms.get(t.value)?.end ?? null) : null,
        dividends: app ? dividendsOf(t) : null,
        betaPrior: (a.withPrior ?? false) ? prior : app ? (packagePrior?.prior ?? null) : null,
        declaredSharesPerUnit: app ? (UnitCompositionCodec.at(units.get(t.value) ?? [], asOf)?.shares ?? null) : null,
        peerMultiples: app ? (peers.get(t.value) ?? null) : null,
        shareEvents: app ? (capital.get(t.value)?.shareEvents ?? []) : [],
        shareIssues: app ? (capital.get(t.value)?.issues ?? []) : [],
        stateControlled: app && stateOwned(t),
      });
    };

    const evaluate = (key: string, i: ValuationInputs, random = false): Record<string, Json> => {
      lastEvent = null;
      const r = ValuationCascade.evaluate(i, {
        scenarioBuilder: random ? (b) => StochasticScenarios.around(b) : null,
        monteCarloSamples: 300,
      });
      const ev = lastEvent as AuditEvent | null;
      if (ev !== null) {
        const j = ev.toJson();
        const text = dartJsonEncode({
          endpoint: j['endpoint'],
          entrada: j['inputPayload'],
          saida: j['outputPayload'],
          calculos: j['calculations'],
        });
        hashes.set(key, sha256(text));
        if (keepTraces) traces.set(key, text);
      }
      return resultJson(r, bandTables);
    };

    const shifts = [-0.02, -0.005, 0.01, 0.03];
    const priorInputs = new Map<string, ValuationInputs>();
    const rows: Record<string, Record<string, Record<string, Json>>> = {};
    let count = 0;
    for (const t of tickers) {
      if (limit > 0 && count >= limit) break;
      count++;
      const row: Record<string, Record<string, Json>> = {};
      const assembly = async (
        name: string,
        prep: Promise<Result<ValuationInputs>>,
        f: (key: string, i: ValuationInputs) => Record<string, Json>,
      ): Promise<void> => {
        lastEvent = null;
        const p = await prep;
        if (p.isErr) {
          const ev = lastEvent as AuditEvent | null;
          row[name] = {
            preparo: failureJson(p.failureOrNull!),
            evento:
              ev === null
                ? null
                : dartJsonEncode({ endpoint: ev.endpoint, entrada: ev.inputPayload, saida: ev.outputPayload }),
          };
          return;
        }
        row[name] = f(`${t.value}/${name}`, p.unwrap());
      };

      await assembly('doisPontos', prepare(t, { fundamentals: memory }), evaluate);
      await assembly('curva', prepare(t, { fundamentals: memory, c: curve }), evaluate);
      await assembly('aplicativo', prepare(t, { fundamentals: withSector, c: curve, app: true }), evaluate);
      await assembly('ancorada', prepare(t, { fundamentals: anchoredWithSector, c: curve, app: true }), evaluate);
      await assembly('semCurva', prepare(t, { fundamentals: withSector, app: true }), evaluate);
      const withPrior = prepare(t, { fundamentals: withSector, c: curve, app: true, withPrior: true });
      await assembly('prior', withPrior, (k, i) => {
        priorInputs.set(t.value, i);
        return evaluate(k, i);
      });
      await assembly('monteCarlo', withPrior, (k, i) => evaluate(k, i, true));
      await assembly('viaFirma', withPrior, (k, i) => evaluate(k, i.withOverrides({ lane: ValuationLane.firm })));
      await assembly('viaAcionista', withPrior, (k, i) =>
        evaluate(k, i.withOverrides({ lane: ValuationLane.shareholder })),
      );
      await assembly('impostos', withPrior, (k, i) =>
        evaluate(
          k,
          i.withOverrides({
            terminalReturn: 0.13,
            growth: 0.06,
            baseFactor: 1.1,
            reinvestment: ReinvestmentPolicy.realGrowth,
            cashTiming: CashTiming.endOfYear,
          }),
        ),
      );
      await assembly(
        'margemCurta',
        prepare(t, { fundamentals: withSector, c: curve, app: true, marginOfSafety: 0.25, projectionYears: 7 }),
        evaluate,
      );
      await assembly('notas', withPrior, (_k, i) =>
        resultJson(ValuationCascade.evaluate(i.withContextNotes(['nota de contexto do oráculo'])), bandTables),
      );
      await assembly('deslocamentos', withPrior, (_k, i) => {
        const out: Record<string, Json> = {};
        for (const d of shifts) {
          const r = ValuationCascade.evaluate(i.withRiskFreeShift(d));
          if (r.isErr) {
            out[str(d)] = failureJson(r.failureOrNull!);
            continue;
          }
          const v = r.unwrap();
          out[str(d)] = {
            model: v.model.name,
            fairValue: v.fairValue.cents,
            discountRate: n(v.discountRate),
            warnings: v.warnings.length,
          };
        }
        return out;
      });
      for (const [name, value] of Object.entries(row)) {
        const h = hashes.get(`${t.value}/${name}`);
        if (h !== undefined) value['rastro'] = h;
      }
      rows[t.value] = row;
    }
    AuditRecorder.detach();
    const histories = new Map<string, FundamentalsSnapshot[]>();
    const profiles = new Map<string, Asset | null>();
    for (const t of tickers) histories.set(t.value, (await withSector.history(t)).valueOrNull ?? []);
    for (const t of tickers) profiles.set(t.value, (await withSector.profile(t)).valueOrNull ?? null);
    const servicesOut = services({
      market,
      tickers,
      anchors,
      priorInputs,
      histories,
      profiles,
      skill: SkillReadingCodec.decode(readPackage(repo, 'assets/validacao/habilidade.json')),
      premium: packagePremium ?? CapmInputs.defaultMarketPremium,
    });
    return { header, rows, services: servicesOut, traces };
  } finally {
    AuditRecorder.detach();
  }
}

// ── Serviços além da cascata ──────────────────────────────────────────────

function premisesJson(p: ManualPremises): Json {
  return {
    baseProfit: n(p.baseProfit),
    growth: n(p.growth),
    growthPath: p.growthPath.name,
    discountRate: n(p.discountRate),
    ratePath: p.ratePath.name,
    perpetualGrowth: n(p.perpetualGrowth),
    reinvestment: p.reinvestment.name,
    returnOnCapital: n(p.returnOnCapital),
    retention: n(p.retention),
    terminalReturn: n(p.terminalReturn),
  };
}

function manualOutcomeJson(r: Result<ManualOutcome>): Json {
  if (r.isErr) return failureJson(r.failureOrNull!);
  const o = r.unwrap();
  return {
    fairValuePerShare: n(o.fairValuePerShare),
    equityValue: n(o.equityValue),
    explicitPresentValue: n(o.explicitPresentValue),
    terminalValue: n(o.terminalValue),
    terminalPresentValue: n(o.terminalPresentValue),
    minorityInterest: n(o.minorityInterest),
    postStatementCapital: n(o.postStatementCapital),
    terminalRate: n(o.terminalRate),
    capitalCostRates: o.capitalCostRates === null ? null : o.capitalCostRates.map((x) => n(x)),
    terminalCapitalCost: n(o.terminalCapitalCost),
    terminalKind: o.terminalKind.name,
    years: o.years.map((y) => [
      y.year,
      n(y.growth),
      n(y.plannedGrowth),
      n(y.profit),
      n(y.retention),
      n(y.firmFlow),
      n(y.debtService),
      n(y.flow),
      n(y.rate),
      n(y.discountFactor),
      n(y.presentValue),
    ]),
    notices: o.notices.map((x) => [x.kind.name, [...x.years]]),
  };
}

function manualJson(m: ManualValuation, rng: SeededRandom, t: Ticker): Json {
  const engine = m.enginePremises;
  const jitter = (x: number, spread: number): number => x + spread * (2 * rng.nextDouble() - 1);
  const variants: ManualPremises[] = [];
  variants.push(engine);
  variants.push(engine.copyWith({ growth: jitter(engine.growth, 0.05) }));
  variants.push(engine.copyWith({ discountRate: jitter(engine.discountRate, 0.03) }));
  variants.push(
    engine.copyWith({ perpetualGrowth: jitter(engine.perpetualGrowth, 0.01), growthPath: ManualGrowthPath.constant }),
  );
  variants.push(engine.copyWith({ reinvestment: ManualReinvestment.fixedFraction, retention: 0.2 + 0.6 * rng.nextDouble() }));
  {
    const returnOnCapital = jitter(engine.returnOnCapital, 0.08);
    const terminalReturn = 0.08 + 0.1 * rng.nextDouble();
    variants.push(engine.copyWith({ returnOnCapital, terminalReturn }));
  }
  {
    const discountRate = jitter(engine.discountRate, 0.02);
    const baseProfit = engine.baseProfit * (0.7 + 0.6 * rng.nextDouble());
    variants.push(engine.copyWith({ ratePath: ManualRatePath.constant, discountRate, baseProfit }));
  }
  variants.push(engine.copyWith({ baseProfit: -1.0 }));
  const last = variants[6]!;
  const record = ManualValuationRecord.capture({
    id: `oraculo-${t.value}`,
    ticker: t,
    engineAsOf: asOf,
    valuation: m,
    premises: last,
    savedAt: DateTime.utc(2026, 10, 16, 12, 30),
  });
  const recordJson = record.isOk ? record.unwrap().toJson() : null;
  const reread =
    recordJson === null ? null : ManualValuationRecord.fromJson(JSON.parse(dartJsonEncode(recordJson)) as JsonObject);
  return {
    lane: m.lane.name,
    shares: n(m.shares),
    marketPrice: n(m.marketPrice),
    engineFairValue: n(m.engineFairValue),
    projectionYears: m.projectionYears,
    isConcession: m.isConcession,
    engine: premisesJson(engine),
    variants: variants.map((v) => ({ premises: premisesJson(v), outcome: manualOutcomeJson(m.evaluate(v)) })),
    attribution: m.attribution(last).map((s) => ({ groups: s.groups.map((g) => g.name), from: n(s.from), to: n(s.to) })),
    solve: ManualField.values.map((f) => {
      const s = m.solve(f, last);
      return [f.name, n(s.target), n(s.value), n(s.closestValue), n(s.closestPrice)];
    }),
    record: record.isErr ? failureJson(record.failureOrNull!) : dartJsonEncode(recordJson),
    reread: reread === null ? null : dartJsonEncode(reread.toJson()),
  };
}

function seriesText(xs: readonly number[]): string {
  return xs.map(str).join(',');
}

function backtestJson(r: Result<BacktestOutcome>): Json {
  if (r.isErr) return failureJson(r.failureOrNull!);
  const o = r.unwrap();
  const m = o.metrics;
  const tickers = [...o.perAsset.keys()].sort((a, b) => a.compareTo(b));
  return {
    start: o.effectivePeriod.start.toIso8601String(),
    end: o.effectivePeriod.end.toIso8601String(),
    dates: o.dates.length,
    firstDate: o.dates.length === 0 ? null : o.dates[0]!.toIso8601String(),
    lastDate: o.dates.length === 0 ? null : o.dates[o.dates.length - 1]!.toIso8601String(),
    wealth: seriesText(o.wealth),
    base100: seriesText(o.base100),
    totalContributed: o.totalContributed.cents,
    totalAllocated: o.totalAllocated.cents,
    transactionCosts: o.transactionCosts.cents,
    finalValue: o.finalValue.cents,
    residualCash: o.residualCash.cents,
    metrics: {
      twr: n(m.timeWeightedReturn),
      mwr: n(m.moneyWeightedReturn),
      cagr: n(m.cagr),
      volatility: n(m.volatility),
      maxDrawdown: n(m.maxDrawdown),
      sharpe: n(m.sharpe),
      sortino: n(m.sortino),
      calmar: n(m.calmar),
    },
    perAsset: tickers.map((t) => {
      const a = o.perAsset.get(t)!;
      return [
        t.value,
        n(a.targetWeight.value),
        n(a.currentWeight),
        n(a.totalReturn),
        a.invested.cents,
        a.finalValue.cents,
        a.cash.cents,
        a.shares,
        n(a.drift),
      ];
    }),
    warnings: [...o.warnings],
  };
}

function services(a: {
  market: Market;
  tickers: readonly Ticker[];
  anchors: MarketAnchors;
  priorInputs: ReadonlyMap<string, ValuationInputs>;
  histories: ReadonlyMap<string, FundamentalsSnapshot[]>;
  profiles: ReadonlyMap<string, Asset | null>;
  skill: SkillReading | null;
  premium: number;
}): Record<string, Json> {
  const { market, tickers, anchors, histories, profiles, skill, premium } = a;
  const valuations = new Map<Ticker, ValuationResult>();
  const manual: Record<string, Json> = {};
  let i = 0;
  for (const t of tickers) {
    const inputs = a.priorInputs.get(t.value);
    i++;
    if (inputs === undefined) continue;
    const r = ValuationCascade.evaluate(inputs);
    if (r.isErr) continue;
    const v = r.unwrap();
    valuations.set(t, v);
    const m = v.manual;
    if (m !== null) manual[t.value] = manualJson(m, new SeededRandom(7000 + i), t);
  }

  const priced = tickers.filter((t) => market.prices.has(t.value));
  const longPriced = priced.filter((t) => market.prices.get(t.value)!.points.length > 1000);
  const assetOf = (t: Ticker): Asset => profiles.get(t.value) ?? new Asset({ ticker: t, name: t.value });

  const costs = [
    TransactionCosts.none,
    TransactionCosts.b3,
    new TransactionCosts({ feePartsPerMillion: 250, brokeragePerOrder: Money.fromReais(4.5) }),
  ];
  const backtests: Json[] = [];
  const alignments: Json[] = [];
  const concentrations: Json[] = [];
  const swaps: Json[] = [];
  const portfolios: Portfolio[] = [];
  for (let j = 0; j < 80; j++) {
    const rng = new SeededRandom(9000 + j);
    const k = 1 + rng.nextInt(15);
    const chosen: Ticker[] = [];
    let guard = 0;
    while (chosen.length < k && guard < 200) {
      guard++;
      const pool = j % 6 === 5 ? priced : longPriced;
      const t = pool[rng.nextInt(pool.length)]!;
      if (!chosen.includes(t)) chosen.push(t);
    }
    const kind = j % 5 === 4 ? PortfolioKind.reserve : PortfolioKind.principal;
    let built: Result<Portfolio>;
    if (j % 3 === 0) {
      const raw = chosen.map(() => 0.2 + rng.nextDouble());
      const total = raw.reduce((x, y) => x + y, 0);
      built = ok(
        new Portfolio({
          id: `p${j}`,
          name: `Carteira ${j}`,
          kind,
          entries: new Map(
            chosen.map((t, q) => [t, new PortfolioEntry({ asset: assetOf(t), weight: Weight.fraction(raw[q]! / total) })]),
          ),
        }),
      );
    } else {
      built = Portfolio.equalWeighted({ id: `p${j}`, name: `Carteira ${j}`, kind, assets: chosen.map(assetOf) });
    }
    const initial = rng.nextDouble() < 0.2 ? 0.0 : 1000 + 99000 * rng.nextDouble();
    const monthly = rng.nextDouble() < 0.25 ? 0.0 : 100 + 4900 * rng.nextDouble();
    const day = 1 + rng.nextInt(28);
    const startIndex = rng.nextInt(market.days.length - 300);
    const length = 250 + rng.nextInt(2500);
    const endIndex = Math.min(startIndex + length, market.days.length - 1);
    const range = new DateRangeClass(market.days[startIndex]!, market.days[endIndex]!);
    const rf = j % 4 === 0 ? 0.0 : anchors.currentRiskFreeRate;
    if (built.isErr) {
      backtests.push(failureJson(built.failureOrNull!));
      continue;
    }
    const portfolio = built.unwrap();
    portfolios.push(portfolio);
    const prices = new Map<Ticker, PriceSeries>();
    for (const t of chosen) {
      if (j % 7 !== 3 || t !== chosen[0]) prices.set(t, market.prices.get(t.value)!);
    }
    const outcome = PortfolioBacktest.run({
      portfolio,
      prices,
      plan: new ContributionPlan({
        initial: Money.fromReais(initial),
        monthly: Money.fromReais(monthly),
        contributionDay: day,
      }),
      range,
      riskFreeRate: rf,
      costs: costs[j % 3]!,
    });
    backtests.push({
      tickers: portfolio.tickers.map((t) => t.value),
      weights: portfolio.tickers.map((t) => n(portfolio.entries.get(t)!.weight.value)),
      outcome: backtestJson(outcome),
    });

    const report = SectorConcentration.analyze(portfolio);
    concentrations.push(report.concentrated.map((e) => [e.sector.key, e.sector.label, e.count, n(e.weight)]));

    const goalResult = FinancialGoal.create({
      initialContribution: Money.fromReais(initial),
      monthlyContribution: Money.fromReais(monthly),
      months: 12 + rng.nextInt(360),
      targetWealth: Money.fromReais(50000 + 5e6 * rng.nextDouble()),
    });
    if (goalResult.isErr) {
      alignments.push(failureJson(goalResult.failureOrNull!));
    } else {
      const goal = goalResult.unwrap();
      const signals = new Map<Ticker, TransversalSignals>();
      for (const t of portfolio.tickers) {
        signals.set(
          t,
          TransversalSignals.fromHistory(histories.get(t.value) ?? [], {
            asOf,
            potential: valuations.get(t)?.upside ?? null,
          }),
        );
      }
      const crossSection = [...valuations.values()].map((v) => v.upside);
      const alignmentJson = (g0: Result<GoalAlignment>): Json => {
        if (g0.isErr) return failureJson(g0.failureOrNull!);
        const g = g0.unwrap();
        return {
          requiredMonthly: n(g.required.monthly),
          requiredAnnual: n(g.required.annual),
          expected: n(g.expectedReturn),
          coverage: n(g.valuationCoverage),
          gap: n(g.gap),
          meets: g.meetsGoal,
          weak: g.coverageIsWeak,
        };
      };
      const req = RequiredReturnSolver.solve(goal);
      let feasibility: Json;
      if (req.isErr) {
        feasibility = failureJson(req.failureOrNull!);
      } else {
        const f = GoalFeasibility.assess({ required: req.unwrap(), anchors, goal });
        feasibility = [f.level.name, f.reason.name, n(f.requiredAnnualRate), n(f.marketMultiple)];
      }
      alignments.push({
        crossSectional: alignmentJson(
          EvaluateGoalAlignment.call({ portfolio, goal, valuations, anchors, crossSection, riskPremium: premium }),
        ),
        ordered: alignmentJson(
          EvaluateGoalAlignment.call({
            portfolio,
            goal,
            valuations,
            anchors,
            ordering: skill?.premiumOrdering ?? null,
            signals,
            riskPremium: premium,
          }),
        ),
        orderedNone: alignmentJson(
          EvaluateGoalAlignment.call({
            portfolio,
            goal,
            valuations,
            anchors,
            ordering: TransversalOrdering.values[j % 3]!,
            signals,
          }),
        ),
        feasibility,
      });
    }
  }

  for (let j = 0; j + 1 < portfolios.length; j += 2) {
    const pa = portfolios[j]!;
    const pb = portfolios[j + 1]!;
    const principal = pa.kind === PortfolioKind.principal ? pa : pb;
    const reserve = new Portfolio({
      id: `r${j}`,
      name: `Reserva ${j}`,
      kind: PortfolioKind.reserve,
      entries: (pa.kind === PortfolioKind.principal ? pb : pa).entries,
    });
    const ticker = (j % 4 === 0 ? reserve : principal).tickers[0]!;
    const r = SwapAssetBetweenPortfolios.call({ principal, reserve, ticker, toPrincipal: j % 4 === 0 });
    if (r.isErr) {
      swaps.push(failureJson(r.failureOrNull!));
    } else {
      const o = r.unwrap();
      swaps.push({
        principal: o.principal.tickers.map((t) => [t.value, n(o.principal.entries.get(t)!.weight.value)]),
        reserve: o.reserve.tickers.map((t) => [t.value, n(o.reserve.entries.get(t)!.weight.value)]),
      });
    }
  }

  const goals: Json[] = [];
  for (let j = 0; j < 150; j++) {
    const rng = new SeededRandom(11000 + j);
    const initial = rng.nextDouble() < 0.15 ? 0.0 : 200000 * rng.nextDouble();
    const monthly = rng.nextDouble() < 0.15 ? 0.0 : 10000 * rng.nextDouble();
    const months = j % 29 === 0 ? 0 : 1 + rng.nextInt(480);
    const target = j % 31 === 0 ? -5.0 : 1e4 + 1e7 * rng.nextDouble();
    const g = FinancialGoal.create({
      initialContribution: Money.fromReais(initial),
      monthlyContribution: Money.fromReais(monthly),
      months,
      targetWealth: Money.fromReais(target),
    });
    if (g.isErr) {
      goals.push(failureJson(g.failureOrNull!));
      continue;
    }
    const goal = g.unwrap();
    const req = RequiredReturnSolver.solve(goal);
    if (req.isErr) {
      goals.push({
        falha: failureJson(req.failureOrNull!),
        unsolvable: GoalFeasibility.unsolvable({ anchors }).reason.name,
      });
      continue;
    }
    const rr = req.unwrap();
    const f = GoalFeasibility.assess({ required: rr, anchors, goal });
    goals.push({
      monthly: n(rr.monthly),
      annual: n(rr.annual),
      fv: n(
        RequiredReturnSolver.futureValue({
          rate: rr.monthly,
          initial: goal.initialContribution.reais,
          monthly: goal.monthlyContribution.reais,
          months: goal.months,
        }),
      ),
      level: f.level.name,
      reason: f.reason.name,
      multiple: n(f.marketMultiple),
      withoutReturn: goal.reachableWithoutReturn,
      total: goal.totalContributed.cents,
    });
  }

  const costOfEquity = new Map<Ticker, number>();
  for (const [t, v] of valuations) {
    if (v.diagnostics !== null) costOfEquity.set(t, v.diagnostics.costOfEquity);
  }
  const crossSection = ExpectedReturn.crossSection({
    upsides: new Map([...valuations.entries()].map(([t, v]) => [t, v.upside])),
    spotRiskFree: anchors.currentRiskFreeRate,
    costOfEquity,
    riskPremium: premium,
  });

  const calendar: Json[] = [];
  for (let j = 0; j < 120; j++) {
    const rng = new SeededRandom(13000 + j);
    const year = 2000 + rng.nextInt(30);
    const month = 1 + rng.nextInt(12);
    const dayOfMonth = 1 + rng.nextInt(28);
    const da = DateTime.local(year, month, dayOfMonth);
    const db = DateTime.local(da.year, da.month, da.day + rng.nextInt(800));
    calendar.push([
      da.toIso8601String(),
      db.toIso8601String(),
      BrazilianCalendar.businessDaysBetween(da, db),
      BrazilianCalendar.isBusinessDay(da),
      BrazilianCalendar.isTradingDay(db),
      BrazilianCalendar.nextTradingSession(da).toIso8601String(),
      BrazilianCalendar.treasurySettlement(db).toIso8601String(),
    ]);
  }
  const easter: string[] = [];
  for (let y = 1900; y <= 2100; y++) easter.push(BrazilianCalendar.easter(y).toIso8601String());

  return {
    valuations: valuations.size,
    manual,
    backtests,
    concentrations,
    alignments,
    swaps,
    goals,
    crossSection: [...crossSection.entries()].map(([t, c]) => [
      t.value,
      n(c.z),
      n(c.expected),
      c.floored,
      c.anchoredOnCostOfEquity,
    ]),
    calendar,
    easter,
  };
}
