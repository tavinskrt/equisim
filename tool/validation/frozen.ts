// A entrada congelada do gabarito, para quem só quer medir sobre ela.
//
// **Por que existe.** O gabarito da cascata (`tool/cascade-golden.ts`) congela
// cache, Ibovespa e universo, e monta a entrada a partir dos pacotes
// versionados — é a única forma de medir o efeito de uma mudança sem misturá-lo
// com a deriva do dado de mercado. As medições dos itens B12, B14 e B15
// precisam da mesma entrada, e reescrever a montagem em cada uma é como duas
// cópias divergem.
//
// **Este módulo não grava nada e não vai à rede**: ele exige que o gabarito já
// tenha congelado a entrada, e falha dizendo o que rodar antes. Quem grava
// continua sendo o gabarito.
//
// **A conferência é parte do contrato.** [Frozen.checkAgainstAnswerKey]
// compara as avaliações deste módulo com as que o gabarito gravou na montagem
// `aplicativo`: se as duas montagens divergirem, a medição não vale, e o
// programa que a usa precisa saber disso antes de imprimir número.
import { existsSync, readFileSync } from 'node:fs';

import {
  type Asset,
  type B3Issuer,
  B3RegistryCodec,
  type BenchmarkRepository,
  type BetaPrior,
  BetaPriorCodec,
  type CapitalEvents,
  CapitalEventsCodec,
  type CashDividend,
  CashDividendsCodec,
  CapmInputs,
  type ConcessionTerm,
  ConcessionTermsCodec,
  CvmDocumentCodec,
  type CvmPeriodDocument,
  CvmSeries,
  DateRange,
  type DateTime,
  date,
  err,
  type FundamentalsRepository,
  type FundamentalsSnapshot,
  ImpliedPremiumCodec,
  InsufficientData,
  type JsonObject,
  MarketAnchors,
  MarketPremiumSource,
  OfficialShareCount,
  ok,
  PointInTimeView,
  PrepareValuationInputs,
  PricePoint,
  PriceSeries,
  ResolveMarketAnchors,
  type Result,
  ShareholderControl,
  ShareholderControlHistory,
  type ShareholderControlPeriod,
  Ticker,
  TreasuryCurve,
  TreasuryQuotesCodec,
  type UnitComposition,
  UnitCompositionCodec,
  type ValuationInputs,
  type ValuationResult,
  type YieldCurve,
  DateTime as DT,
} from '../../src/core';
import { OfficialSectorFundamentalsRepository } from '../../src/data/repositories/b3-registry-repository';
import { ValidationContext } from './context';

/** A data de referência da entrada congelada — a mesma do gabarito. */
export const frozenToday: DateTime = date(2026, 9, 14);

const folder = 'data/gabarito';
const cacheFile = `${folder}/cache.sqlite`;
const ibovespaFile = `${folder}/ibovespa.json`;
const universeFile = `${folder}/universo.json`;

/** O pacote do prêmio implícito (decisão 142). */
const premiumPackageFile = 'public/assets/mercado/premio_implicito.json';
const answerKeyFile = 'docs/validacao/gabarito_cascata.json';

const readJson = (path: string): JsonObject => JSON.parse(readFileSync(path, 'utf8')) as JsonObject;

/**
 * O Ibovespa gravado pelo gabarito. Janela não gravada é recusada — ir à rede
 * aqui descongelaria a entrada sem avisar.
 */
export class SavedIbovespa implements BenchmarkRepository {
  constructor(readonly saved: Map<string, PriceSeries>) {}

  async ibovespa(range: DateRange): Promise<Result<PriceSeries>> {
    const k = `${range.start.toIso8601String()}|${range.end.toIso8601String()}`;
    const g = this.saved.get(k);
    if (g !== undefined) return ok(g);
    return err(new InsufficientData(`Ibovespa não gravado para ${k}`));
  }

  static read(j: JsonObject): Map<string, PriceSeries> {
    const out = new Map<string, PriceSeries>();
    for (const [key, value] of Object.entries(j)) {
      const v = value as { ticker: string; pontos: [string, number, number | null, number | null][] };
      out.set(
        key,
        new PriceSeries({
          ticker: Ticker.parse(v.ticker),
          points: v.pontos.map(
            (p) => new PricePoint({ date: DT.parse(p[0]), close: p[1], adjustedClose: p[2] ?? null, volume: p[3] ?? null }),
          ),
        }),
      );
    }
    return out;
  }
}

/** Fundamentos de mercado com a demonstração da CVM mesclada, como o aplicativo faz. */
export class CvmFundamentals implements FundamentalsRepository {
  constructor(
    readonly market: FundamentalsRepository,
    readonly docs: Map<string, CvmPeriodDocument[]>,
    readonly options: { today: DateTime; anchored?: boolean },
  ) {}

  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const base = await this.market.history(t);
    if (base.isErr) return base;
    const ownDocs = this.docs.get(t.value);
    if (ownDocs === undefined || ownDocs.length === 0) return base;
    const view = new PointInTimeView(this.options.today);
    return ok([
      ...CvmSeries.build({
        documents: ownDocs,
        market: base.unwrap(),
        published: (s) => view.isPublished(s),
        anchored: this.options.anchored ?? false,
        // A mesma série do aplicativo: o ano corrente anualizado (decisão 153).
        yearToDate: CvmSeries.yearToDateByDefault,
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

export interface PremiumChoice {
  readonly value: number;
  readonly origin: MarketPremiumSource;
}

/** A entrada congelada, montada. */
export class Frozen {
  /** O Ibovespa da janela do beta, já congelado. */
  readonly betaWindow: DateRange = new DateRange(
    date(frozenToday.year - PrepareValuationInputs.betaWindowYears, frozenToday.month, frozenToday.day),
    frozenToday,
  );

  private constructor(
    readonly ctx: ValidationContext,
    /** Fundamentos com a CVM mesclada e o setor da B3 por emissor. */
    readonly fundamentals: FundamentalsRepository,
    readonly anchors: MarketAnchors,
    readonly curve: YieldCurve | null,
    readonly universe: Ticker[],
    /** O prior do pacote — o que o aplicativo lê (decisão 105). */
    readonly prior: BetaPrior | null,
    readonly registry: Map<string, B3Issuer>,
    readonly terms: Map<string, ConcessionTerm>,
    readonly dividends: Map<string, readonly CashDividend[]>,
    readonly units: Map<string, UnitComposition[]>,
    /** Emissões e eventos de ações do pacote do aplicativo (itens B28 e B29). */
    readonly capital: Map<string, CapitalEvents>,
    /** O controle acionário de cada emissor, pela raiz do código (item B46). */
    readonly control: Map<string, ShareholderControlPeriod[]>,
    /** O prêmio de mercado da montagem do aplicativo, e de onde ele veio (decisão 142). */
    readonly premium: PremiumChoice,
  ) {}

  /** `true` quando o emissor de [t] é de controle estatal na data congelada. */
  stateOwned(t: Ticker): boolean {
    const p = this.control.get(t.value.slice(0, 4));
    return p !== undefined && ShareholderControlHistory.at(p, frozenToday) === ShareholderControl.state;
  }

  issuer(t: Ticker): B3Issuer | null {
    return this.registry.get(t.value.length >= 4 ? t.value.slice(0, 4) : '') ?? null;
  }

  dividendsOf(t: Ticker): readonly CashDividend[] {
    return CashDividendsCodec.forTicker(this.dividends, t.value);
  }

  /**
   * Monta a entrada, exigindo que o gabarito já tenha congelado a dele.
   *
   * Encerra o processo com código 2 quando falta a entrada congelada: medir
   * sobre dado fresco daria outro número a cada execução, e é exatamente o que
   * este módulo existe para não deixar acontecer.
   */
  static async build(): Promise<Frozen> {
    for (const f of [cacheFile, ibovespaFile, universeFile]) {
      if (existsSync(f)) continue;
      process.stderr.write(`sem entrada congelada em ${f}. Rode antes:\n`);
      process.stderr.write('  npm run tool -- cascade-golden\n');
      process.exit(2);
    }

    const curve = TreasuryCurve.at(TreasuryQuotesCodec.decode(readJson('public/assets/tesouro/curva.json')), frozenToday);
    const registry = B3RegistryCodec.decodePackage(readJson('public/assets/b3/emissores.json'));
    const docs = CvmDocumentCodec.decodePackage(readJson('public/assets/cvm/documentos.json'));
    const terms = ConcessionTermsCodec.decode(readJson('public/assets/cvm/outorgas.json'));
    const dividends = CashDividendsCodec.decode(readJson('public/assets/b3/proventos.json'));
    const prior = existsSync('public/assets/mercado/beta_prior.json')
      ? (BetaPriorCodec.decode(readJson('public/assets/mercado/beta_prior.json'))?.prior ?? null)
      : null;
    const capital = existsSync('public/assets/cvm/capital.json')
      ? CapitalEventsCodec.decodePackage(readJson('public/assets/cvm/capital.json'))
      : new Map<string, CapitalEvents>();
    const units = existsSync('public/assets/cvm/units.json')
      ? UnitCompositionCodec.decodePackage(readJson('public/assets/cvm/units.json'))
      : new Map<string, UnitComposition[]>();
    // O controle acionário (item B46), como o aplicativo o lê.
    const control = existsSync('public/assets/cvm/controle.json')
      ? (ShareholderControlHistory.decode(readJson('public/assets/cvm/controle.json'))?.byIssuer ?? new Map<string, ShareholderControlPeriod[]>())
      : new Map<string, ShareholderControlPeriod[]>();
    // O prêmio de mercado do aplicativo (decisão 142): a média de dez anos da
    // série do pacote, na data congelada. Sem pacote, o recuo do aplicativo —
    // os 5,5% parametrizados —, dito no terminal.
    const premiumPackage = existsSync(premiumPackageFile) ? ImpliedPremiumCodec.decode(readJson(premiumPackageFile)) : null;
    const mean = premiumPackage?.normalizedAt(frozenToday) ?? null;
    const premium: PremiumChoice =
      mean === null
        ? { value: CapmInputs.defaultMarketPremium, origin: MarketPremiumSource.parameterized }
        : { value: mean, origin: MarketPremiumSource.impliedNormalized };
    if (mean === null) {
      process.stderr.write(
        `sem ${premiumPackageFile} utilizável: o prêmio é o parametrizado de 5,5% (rode npm run tool -- implied-premium --so-serie)\n`,
      );
    }

    const ctx0 = ValidationContext.create({ outputDir: 'docs/validacao', cacheFile, frozenCache: true });
    const ibov = new SavedIbovespa(SavedIbovespa.read(readJson(ibovespaFile)));
    // O Ibovespa gravado no lugar do de rede; o resto do contexto é o mesmo.
    const ctx = ctx0.withBenchmark(ibov);

    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: frozenToday })).getOrElse(
      MarketAnchors.fallback2026,
    );

    const universe = (JSON.parse(readFileSync(universeFile, 'utf8')) as string[]).map((s) => Ticker.parse(s));

    const issuer = (t: Ticker) => registry.get(t.value.length >= 4 ? t.value.slice(0, 4) : '') ?? null;
    const fundamentals = new OfficialSectorFundamentalsRepository({
      inner: new CvmFundamentals(ctx.fundamentals, docs, { today: frozenToday }),
      classification: async (t) => issuer(t)?.classification ?? null,
    });

    return new Frozen(ctx, fundamentals, anchors, curve, universe, prior, registry, terms, dividends, units, capital, control, premium);
  }

  /**
   * A entrada da montagem **do aplicativo**, a mesma do gabarito.
   *
   * [years] existe para a varredura do horizonte (item B6) e **nada mais**: o
   * padrão de 10 é o do gabarito, e passar outro valor produz uma montagem que
   * não é a dele — quem varre precisa dizer isso ao imprimir número.
   *
   * [premium] existe para a varredura do prêmio de risco de mercado (itens B3
   * e B42), e tem a mesma ressalva: ausente, é o do aplicativo — a média de
   * dez anos do prêmio implícito, do pacote (decisão 142) —, que é o do
   * gabarito; informado, entra como parametrizado.
   *
   * [rate] troca a fonte da taxa livre de risco, para a medição da Selic
   * prevista (`tool/selic-focus.ts`): `curve` no lugar da do Tesouro — nula,
   * o motor usa os dois pontos do CDI — e `structural` no lugar da média
   * decenal. Ausente, é a montagem do gabarito.
   *
   * [withPrior] falso tira o prior do beta, e o beta fica o medido, sem
   * encolhimento — para a medição do item B46, que compara os dois. Com o
   * padrão, é a montagem do gabarito.
   */
  prepare(
    t: Ticker,
    options: {
      years?: number;
      premium?: number | null;
      rate?: { curve: YieldCurve | null; structural: number | null } | null;
      withPrior?: boolean;
    } = {},
  ): Promise<Result<ValuationInputs>> {
    const e = this.issuer(t);
    const premium = options.premium ?? null;
    const rate = options.rate ?? null;
    return PrepareValuationInputs.call({
      ticker: t,
      prices: this.ctx.prices,
      fundamentals: this.fundamentals,
      benchmark: this.ctx.benchmark,
      riskFreeRate: this.anchors.currentRiskFreeRate,
      asOf: frozenToday,
      perpetualGrowthCap: this.anchors.nominalEconomyGrowth,
      inflation: this.anchors.inflationCagr,
      terminalRiskFreeRate: rate?.structural ?? this.anchors.riskFreeCagr,
      riskFreeCurve: rate === null ? this.curve : rate.curve,
      projectionYears: options.years ?? 10,
      marketPremium: premium ?? this.premium.value,
      premiumSource: premium === null ? this.premium.origin : MarketPremiumSource.parameterized,
      officialShares: e?.totalShares != null ? new OfficialShareCount({ total: e.totalShares, asOf: e.consultedOn }) : null,
      concessionEnd: this.terms.get(t.value)?.end ?? null,
      dividends: this.dividendsOf(t),
      betaPrior: (options.withPrior ?? true) ? this.prior : null,
      declaredSharesPerUnit: UnitCompositionCodec.at(this.units.get(t.value) ?? [], frozenToday)?.shares ?? null,
      shareEvents: this.capital.get(t.value)?.shareEvents ?? [],
      shareIssues: this.capital.get(t.value)?.issues ?? [],
      stateControlled: this.stateOwned(t),
    });
  }

  /**
   * Confere as avaliações deste módulo contra o que o gabarito gravou.
   *
   * Devolve os tickers que divergem. Lista vazia com gabarito presente é a
   * prova de que as duas montagens são a mesma; gabarito ausente devolve
   * `null`, e quem chama precisa dizer que não conferiu.
   */
  async checkAgainstAnswerKey(own: Map<Ticker, ValuationResult | null>): Promise<string[] | null> {
    if (!existsSync(answerKeyFile)) return null;
    const g = readJson(answerKeyFile);
    const divergent: string[] = [];
    for (const [ticker, result] of own) {
      const saved = (g[ticker.value] as JsonObject | undefined)?.['aplicativo'];
      const cents = saved !== null && typeof saved === 'object' ? (saved as JsonObject)['justoCentavos'] : null;
      const mine = result?.fairValue.cents ?? null;
      if ((cents === null || cents === undefined) && mine === null) continue;
      if (typeof cents !== 'number' || !Number.isInteger(cents) || mine !== cents) divergent.push(ticker.value);
    }
    return divergent;
  }
}
