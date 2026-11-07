import type { PriceSeries } from '../../entities/price-series';
import { FinancialGoal } from '../../entities/financial-goal';
import { InsufficientData, InvalidInput } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { DateTime } from '../../lang/date-time';
import { asDouble, isJsonObject, type JsonObject } from '../../lang/json';
import { compareNum, tryParseInt } from '../../lang/num';
import type { RateSeries } from '../../repositories/repositories';
import { DateRange } from '../../value-objects/date-range';
import { Money } from '../../value-objects/money';
import { WealthPathBuilder } from '../../value-objects/paired-series';
import { Ticker } from '../../value-objects/ticker';
import type { CashDividend } from '../b3/cash-dividends';
import { affordableShares, TransactionCosts } from '../backtest/portfolio-backtest';
import { CashFlow, Returns } from '../metrics/returns';
import { RequiredReturnSolver } from './required-return';

// ------------------------------------------------------------- Calendário --

/**
 * O dia civil como inteiro `AAAAMMDD`.
 *
 * **Toda comparação de data deste módulo é por dia civil, e nunca por
 * instante.** Os proventos chegam em UTC e as cotações em hora local; o mesmo
 * dia nas duas marcações são instantes diferentes, e comparar instantes
 * erraria a data ex por um dia.
 */
function dayKey(d: DateTime): number {
  return d.year * 10000 + d.month * 100 + d.day;
}

/** O dia civil em hora local, a marcação das cotações. */
function localDay(d: DateTime): DateTime {
  return DateTime.local(d.year, d.month, d.day);
}

/**
 * Dias corridos entre dois dias civis. Conta sobre UTC para que um horário
 * de verão no intervalo não roube uma hora — e, com ela, um dia inteiro.
 */
function civilDaysBetween(a: DateTime, b: DateTime): number {
  const ua = DateTime.utc(a.year, a.month, a.day).millisecondsSinceEpoch;
  const ub = DateTime.utc(b.year, b.month, b.day).millisecondsSinceEpoch;
  return Math.round((ub - ua) / 86_400_000);
}

function pad(n: number, width: number): string {
  return String(n).padStart(width, '0');
}

/** `AAAA-MM-DD`, o formato de dia dos documentos gravados. */
export function isoDay(d: DateTime): string {
  return `${pad(d.year, 4)}-${pad(d.month, 2)}-${pad(d.day, 2)}`;
}

/** Lê `AAAA-MM-DD` como dia civil local, ou `null`. */
export function parseIsoDay(v: unknown): DateTime | null {
  if (typeof v !== 'string' || v.length < 10) return null;
  const p = v.substring(0, 10).split('-');
  if (p.length !== 3) return null;
  const y = tryParseInt(p[0]!);
  const m = tryParseInt(p[1]!);
  const d = tryParseInt(p[2]!);
  if (y === null || m === null || d === null || m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime.local(y, m, d);
}

// ------------------------------------------- Preço justo ponto no tempo --

/** De onde veio o preço justo que decidiu uma compra. */
export type FairValueOrigin = 'coorte' | 'motor';

/**
 * O preço justo de um ativo **conhecido numa data**, na base da série de
 * cotações do aplicativo (ajustada por desdobramento e grupamento).
 *
 * Guardar o preço justo, e não o potencial, é o que deixa o potencial do dia
 * da compra sair do preço daquele dia: `justo ÷ preço − 1`. O preço justo só
 * muda quando há balanço novo; o preço muda todo pregão.
 */
export class FairValueReading {
  readonly ticker: Ticker;
  /** Preço justo por ação, em reais, na base da série de cotações. */
  readonly fairValue: number;
  /** A coorte trimestral ponto no tempo, ou o motor ao vivo. */
  readonly origin: FairValueOrigin;
  /** Data da avaliação: a da coorte, ou a do motor. */
  readonly asOf: DateTime;
  /** Custo do capital próprio do ativo naquela avaliação, ou `null`. */
  readonly costOfEquity: number | null;

  constructor(args: {
    ticker: Ticker;
    fairValue: number;
    origin: FairValueOrigin;
    asOf: DateTime;
    costOfEquity?: number | null;
  }) {
    this.ticker = args.ticker;
    this.fairValue = args.fairValue;
    this.origin = args.origin;
    this.asOf = localDay(args.asOf);
    this.costOfEquity = args.costOfEquity ?? null;
  }

  /** Potencial contra [price]: `justo ÷ preço − 1`. `null` sem preço positivo. */
  upsideAt(price: number): number | null {
    return price > 0 ? this.fairValue / price - 1 : null;
  }
}

/** Um ativo avaliado numa coorte. */
export interface UpsideCohortEntry {
  /** Potencial na data da coorte, em fração. */
  readonly upside: number;
  /** Preço do ativo na data da coorte, na unidade da fonte da coorte. */
  readonly price: number;
}

/** Uma coorte trimestral: a data e os ativos que o motor avaliou nela. */
export interface UpsideCohort {
  readonly date: DateTime;
  readonly entries: ReadonlyMap<string, UpsideCohortEntry>;
}

/**
 * Formato do pacote `assets/validacao/upside_coortes.json`.
 *
 * Mora no núcleo pelo mesmo motivo do `CashDividendsCodec`: a ferramenta que
 * grava e o repositório que lê têm de concordar sobre o formato. Cada ativo é
 * um par `[potencial, preço]`, para o pacote ficar na casa de cem quilobytes.
 *
 * **O custo do capital próprio das coortes fica de fora de propósito.** Ele
 * sai, nelas, na casa de 7,5% ao ano mesmo em 2023 e 2025, com o CDI acima de
 * 13%, e não é comparável ao `Ke` que o motor de hoje mostra na Meta. O
 * esperado do acompanhamento é o da Meta, congelado no dia da criação.
 */
export const UpsideCohortsCodec = {
  version: 1,

  encode(cohorts: readonly UpsideCohort[], args: { generatedAt: DateTime }): JsonObject {
    return {
      versao: UpsideCohortsCodec.version,
      geradoEm: isoDay(args.generatedAt),
      coortes: cohorts.map((c) => {
        const ativos: JsonObject = {};
        for (const [t, e] of c.entries) ativos[t] = [e.upside, e.price];
        return { data: isoDay(c.date), ativos };
      }),
    };
  },

  /** Lê o pacote. Versão desconhecida ou formato ilegível devolve `null`. */
  decode(pkg: unknown): UpsideCohorts | null {
    if (!isJsonObject(pkg) || pkg['versao'] !== UpsideCohortsCodec.version) return null;
    const list = pkg['coortes'];
    if (!Array.isArray(list)) return null;
    const cohorts: UpsideCohort[] = [];
    for (const raw of list) {
      if (!isJsonObject(raw)) continue;
      const date = parseIsoDay(raw['data']);
      const assets = raw['ativos'];
      if (date === null || !isJsonObject(assets)) continue;
      const entries = new Map<string, UpsideCohortEntry>();
      for (const [ticker, trio] of Object.entries(assets)) {
        if (!Array.isArray(trio) || trio.length < 2) continue;
        const upside = asDouble(trio[0]);
        const price = asDouble(trio[1]);
        if (upside === null || price === null || !(price > 0) || !Number.isFinite(upside)) continue;
        entries.set(ticker, { upside, price });
      }
      cohorts.push({ date, entries });
    }
    if (cohorts.length === 0) return null;
    return new UpsideCohorts(cohorts, { generatedAt: parseIsoDay(pkg['geradoEm']) });
  },
};

/**
 * **As coortes trimestrais ponto no tempo**, a fonte do preço justo das
 * compras com data passada.
 *
 * Cada coorte avaliou o universo só com os balanços já entregues à CVM na
 * data dela (`PointInTimeView`), e por isso a compra de um mês passado usa a
 * coorte mais recente **anterior ou igual** à data: o que era público ali.
 * Usar a avaliação de hoje para decidir a compra de 2021 escolheria o ativo
 * que já se sabe que andou — o viés de olhar o futuro.
 */
export class UpsideCohorts {
  /** Em ordem de data. */
  readonly cohorts: readonly UpsideCohort[];
  readonly generatedAt: DateTime | null;

  constructor(cohorts: readonly UpsideCohort[], options: { generatedAt?: DateTime | null } = {}) {
    this.cohorts = Object.freeze(
      [...cohorts].map((c) => ({ date: localDay(c.date), entries: c.entries })).sort((a, b) => a.date.compareTo(b.date)),
    );
    this.generatedAt = options.generatedAt ?? null;
  }

  /**
   * Quanto uma coorte vale depois da data dela, em dias: um trimestre e a
   * folga de um mês. Além disso o preço justo é velho, e a compra o declara.
   */
  static readonly staleAfterDays = 122;

  get firstDate(): DateTime | null {
    return this.cohorts[0]?.date ?? null;
  }

  get lastDate(): DateTime | null {
    return this.cohorts[this.cohorts.length - 1]?.date ?? null;
  }

  /** A coorte mais recente com data anterior ou igual a [date], ou `null`. */
  cohortAsOf(date: DateTime): UpsideCohort | null {
    const key = dayKey(date);
    let found: UpsideCohort | null = null;
    for (const c of this.cohorts) {
      if (dayKey(c.date) > key) break;
      found = c;
    }
    return found;
  }

  /**
   * O preço justo de [ticker] conhecido em [date], na base de [series].
   *
   * A coorte guarda o potencial `u_c` e o preço da fonte dela, que pode estar
   * noutra base de desdobramento. O preço justo que vale para a série do
   * aplicativo é `(1 + u_c) · P(c)`, com `P(c)` o fechamento da própria série
   * na data da coorte: assim o potencial do dia `t` é
   * `(1 + u_c) · P(c) / P(t) − 1`, e nenhum desdobramento entre as duas datas
   * o distorce.
   *
   * `null` quando o ativo não foi avaliado na coorte (recusado pelo motor, ou
   * fora do universo dela), ou quando a série não tem cotação na data da
   * coorte.
   */
  readingAt(ticker: Ticker, date: DateTime, series: PriceSeries | undefined): FairValueReading | null {
    const cohort = this.cohortAsOf(date);
    if (cohort === null || series === undefined || series.isEmpty) return null;
    const entry = cohort.entries.get(ticker.value);
    if (entry === undefined) return null;
    if (dayKey(series.firstDate) > dayKey(cohort.date)) return null;
    const priceAtCohort = series.closeAsOf(cohort.date);
    if (priceAtCohort === null || !(priceAtCohort > 0)) return null;
    return new FairValueReading({
      ticker,
      fairValue: (1 + entry.upside) * priceAtCohort,
      origin: 'coorte',
      asOf: cohort.date,
    });
  }
}

// -------------------------------------------------------- Regra de compra --

/** Um ativo que pode receber o aporte, como a regra o vê no dia. */
export interface PurchaseCandidate {
  readonly ticker: Ticker;
  /** Ordem do ativo na carteira: desempata potenciais iguais. */
  readonly order: number;
  readonly priceCents: number;
  readonly reading: FairValueReading;
  readonly upside: number;
  /** Valor de mercado da posição antes da compra, em centavos. */
  readonly positionCents: number;
}

/** A compra decidida. */
export interface PurchaseDecision {
  readonly candidate: PurchaseCandidate;
  readonly quantity: number;
  readonly costCents: number;
  /** `true` quando nenhum ativo estava abaixo do teto e valeu o maior potencial geral. */
  readonly capOverridden: boolean;
}

/**
 * **A regra do aporte**: o ativo de maior potencial **entre os que estão
 * abaixo do teto de peso**.
 *
 * O maior potencial puro concentra: o preço justo só muda a cada balanço, e
 * nas coortes de 2021 a 2025 o líder de potencial de uma carteira de dez
 * ativos se repete em 60% dos trimestres. O teto devolve a diversificação sem
 * tirar o aporte do ativo mais descontado — ele só deixa de receber **todos**.
 *
 * - O peso é o da posição no total **em ações**, antes da compra; carteira
 *   ainda vazia tem todos os pesos em zero.
 * - Está abaixo do teto quem tem peso **estritamente menor** que ele.
 * - Nenhum abaixo do teto: vale o maior potencial geral, e a decisão diz isso.
 * - O ativo escolhido é o primeiro, nessa ordem, de que o caixa paga ao menos
 *   uma ação com a tarifa; o potencial empatado sai pela ordem da carteira.
 * - Nenhum que caiba: não há compra, e o caixa espera o mês seguinte.
 */
export const TopUpsidePolicy = {
  /** O teto padrão: o dobro do peso igual, `2/N`, limitado a 100%. */
  defaultCap(assetCount: number): number {
    return assetCount <= 0 ? 1 : Math.min(1, 2 / assetCount);
  },

  choose(args: {
    candidates: readonly PurchaseCandidate[];
    /** Valor de mercado de **todas** as posições, avaliadas ou não, em centavos. */
    totalPositionCents: number;
    cashCents: number;
    cap: number;
    costs: TransactionCosts;
  }): PurchaseDecision | null {
    const { candidates, totalPositionCents, cashCents, cap, costs } = args;
    if (cashCents <= 0 || candidates.length === 0) return null;
    const ranked = [...candidates].sort((a, b) => {
      const byUpside = compareNum(b.upside, a.upside);
      return byUpside !== 0 ? byUpside : compareNum(a.order, b.order);
    });
    const weight = (c: PurchaseCandidate) => (totalPositionCents > 0 ? c.positionCents / totalPositionCents : 0);
    const below = ranked.filter((c) => weight(c) < cap);
    const pick = (list: readonly PurchaseCandidate[], capOverridden: boolean): PurchaseDecision | null => {
      for (const candidate of list) {
        const quantity = affordableShares(cashCents, candidate.priceCents, costs);
        if (quantity <= 0) continue;
        return { candidate, quantity, costCents: costs.orderCents(quantity * candidate.priceCents), capOverridden };
      }
      return null;
    };
    return below.length > 0 ? pick(below, false) : pick(ranked, true);
  },
};

// ----------------------------------------------------- Plano e registros --

/**
 * O plano do acompanhamento, congelado no dia em que ele começa.
 *
 * Os ativos são os da carteira Principal **naquele dia**: trocar um ativo no
 * meio reescreveria as compras já feitas. Mudou a carteira, começa-se outro
 * acompanhamento.
 */
export class TrackingPlan {
  /** Dia em que a carteira começa: o aporte inicial sai no primeiro pregão a partir dele. */
  readonly start: DateTime;
  /**
   * Dia em que o acompanhamento foi criado. **Separa o passado do futuro**:
   * aporte agendado antes dele é retrospectivo, decidido pelas coortes; a
   * partir dele, ao vivo, decidido pelo motor no dia em que é executado.
   */
  readonly createdOn: DateTime;
  readonly initial: Money;
  readonly monthly: Money;
  /** Dia do mês do aporte, de 1 a 28. */
  readonly contributionDay: number;
  readonly tickers: readonly Ticker[];
  /** Teto de peso por ativo, em fração. */
  readonly weightCap: number;
  /** Credita os proventos no caixa (JCP líquido da retenção: 15% até 2025, 17,5% desde 2026). */
  readonly reinvestDividends: boolean;
  readonly costs: TransactionCosts;

  constructor(args: {
    start: DateTime;
    createdOn: DateTime;
    initial: Money;
    monthly: Money;
    contributionDay?: number;
    tickers: readonly Ticker[];
    weightCap?: number;
    reinvestDividends?: boolean;
    costs?: TransactionCosts;
  }) {
    this.start = localDay(args.start);
    this.createdOn = localDay(args.createdOn);
    this.initial = args.initial;
    this.monthly = args.monthly;
    this.contributionDay = Math.min(28, Math.max(1, Math.round(args.contributionDay ?? 5)));
    this.tickers = Object.freeze([...args.tickers]);
    this.weightCap = args.weightCap ?? TopUpsidePolicy.defaultCap(args.tickers.length);
    this.reinvestDividends = args.reinvestDividends ?? true;
    this.costs = args.costs ?? TransactionCosts.b3;
  }

  toJson(): JsonObject {
    return {
      inicio: isoDay(this.start),
      criadoEm: isoDay(this.createdOn),
      aporteInicialCentavos: this.initial.cents,
      aporteMensalCentavos: this.monthly.cents,
      diaDoAporte: this.contributionDay,
      ativos: this.tickers.map((t) => t.value),
      tetoDePeso: this.weightCap,
      proventos: this.reinvestDividends,
      tarifaPpm: this.costs.feePartsPerMillion,
      corretagemCentavos: this.costs.brokeragePerOrder.cents,
    };
  }

  static fromJson(j: unknown): TrackingPlan | null {
    if (!isJsonObject(j)) return null;
    const start = parseIsoDay(j['inicio']);
    const createdOn = parseIsoDay(j['criadoEm']);
    const initial = j['aporteInicialCentavos'];
    const monthly = j['aporteMensalCentavos'];
    const tickers = Array.isArray(j['ativos']) ? j['ativos'].map((t) => (typeof t === 'string' ? Ticker.tryParse(t) : null)) : null;
    if (start === null || createdOn === null || tickers === null || tickers.some((t) => t === null)) return null;
    if (!Number.isInteger(initial) || !Number.isInteger(monthly)) return null;
    const day = j['diaDoAporte'];
    const cap = asDouble(j['tetoDePeso']);
    const fee = j['tarifaPpm'];
    const brokerage = j['corretagemCentavos'];
    return new TrackingPlan({
      start,
      createdOn,
      initial: new Money(initial as number),
      monthly: new Money(monthly as number),
      contributionDay: Number.isInteger(day) ? (day as number) : 5,
      tickers: tickers as Ticker[],
      weightCap: cap ?? undefined,
      reinvestDividends: j['proventos'] !== false,
      costs: new TransactionCosts({
        feePartsPerMillion: Number.isInteger(fee) ? (fee as number) : TransactionCosts.b3.feePartsPerMillion,
        brokeragePerOrder: new Money(Number.isInteger(brokerage) ? (brokerage as number) : 0),
      }),
    });
  }
}

/**
 * **Um aporte e a compra que ele fez** — o registro que vai ao Firestore e não
 * muda mais.
 *
 * A compra gravada é a prova de que não houve olhar o futuro: ela leva o
 * preço, o preço justo, a origem dele e a data em que foi decidida. Reabrir o
 * acompanhamento reconstrói o patrimônio a partir destes registros, e só
 * decide os aportes que ainda não têm registro.
 */
export class TrackingOrder {
  /** 0 é o aporte inicial; 1, o primeiro mensal; e assim por diante. */
  readonly seq: number;
  /** Pregão em que o aporte caiu no caixa. */
  readonly scheduledOn: DateTime;
  /** Pregão em que a compra foi feita: o mesmo, no retrospectivo; o da abertura da tela, ao vivo. */
  readonly executedOn: DateTime;
  readonly contribution: Money;
  /** Ativo comprado, ou `null` quando nenhum coube no caixa. */
  readonly ticker: Ticker | null;
  readonly quantity: number;
  readonly priceCents: number;
  readonly costCents: number;
  readonly upside: number | null;
  readonly fairValue: number | null;
  readonly origin: FairValueOrigin | null;
  readonly fairValueAsOf: DateTime | null;
  /** O teto não tinha ninguém abaixo dele, e valeu o maior potencial geral. */
  readonly capOverridden: boolean;
  /** Caixa da carteira depois da compra, em centavos. Informativo. */
  readonly cashAfterCents: number;

  constructor(args: {
    seq: number;
    scheduledOn: DateTime;
    executedOn: DateTime;
    contribution: Money;
    ticker?: Ticker | null;
    quantity?: number;
    priceCents?: number;
    costCents?: number;
    upside?: number | null;
    fairValue?: number | null;
    origin?: FairValueOrigin | null;
    fairValueAsOf?: DateTime | null;
    capOverridden?: boolean;
    cashAfterCents?: number;
  }) {
    this.seq = args.seq;
    this.scheduledOn = localDay(args.scheduledOn);
    this.executedOn = localDay(args.executedOn);
    this.contribution = args.contribution;
    this.ticker = args.ticker ?? null;
    this.quantity = args.quantity ?? 0;
    this.priceCents = args.priceCents ?? 0;
    this.costCents = args.costCents ?? 0;
    this.upside = args.upside ?? null;
    this.fairValue = args.fairValue ?? null;
    this.origin = args.origin ?? null;
    this.fairValueAsOf = args.fairValueAsOf === null || args.fairValueAsOf === undefined ? null : localDay(args.fairValueAsOf);
    this.capOverridden = args.capOverridden ?? false;
    this.cashAfterCents = args.cashAfterCents ?? 0;
  }

  /** Valor pago pelas ações, sem a tarifa, em centavos. */
  get tradedCents(): number {
    return this.quantity * this.priceCents;
  }

  /** Dias entre o aporte cair no caixa e a compra. */
  get delayDays(): number {
    return civilDaysBetween(this.scheduledOn, this.executedOn);
  }

  /** Dias entre a avaliação que decidiu a compra e a compra. */
  get fairValueAgeDays(): number | null {
    return this.fairValueAsOf === null ? null : civilDaysBetween(this.fairValueAsOf, this.executedOn);
  }

  toJson(): JsonObject {
    return {
      seq: this.seq,
      agendadoEm: isoDay(this.scheduledOn),
      executadoEm: isoDay(this.executedOn),
      aporteCentavos: this.contribution.cents,
      ativo: this.ticker?.value ?? null,
      quantidade: this.quantity,
      precoCentavos: this.priceCents,
      custoCentavos: this.costCents,
      potencial: this.upside,
      precoJusto: this.fairValue,
      origem: this.origin,
      avaliadoEm: this.fairValueAsOf === null ? null : isoDay(this.fairValueAsOf),
      tetoIgnorado: this.capOverridden,
      caixaDepoisCentavos: this.cashAfterCents,
    };
  }

  static fromJson(j: unknown): TrackingOrder | null {
    if (!isJsonObject(j)) return null;
    const seq = j['seq'];
    const scheduledOn = parseIsoDay(j['agendadoEm']);
    const executedOn = parseIsoDay(j['executadoEm']);
    const contribution = j['aporteCentavos'];
    if (!Number.isInteger(seq) || (seq as number) < 0 || scheduledOn === null || executedOn === null) return null;
    if (!Number.isInteger(contribution)) return null;
    const rawTicker = j['ativo'];
    const ticker = typeof rawTicker === 'string' ? Ticker.tryParse(rawTicker) : null;
    if (typeof rawTicker === 'string' && ticker === null) return null;
    const int = (v: unknown) => (Number.isInteger(v) ? (v as number) : 0);
    const origin = j['origem'] === 'coorte' || j['origem'] === 'motor' ? j['origem'] : null;
    return new TrackingOrder({
      seq: seq as number,
      scheduledOn,
      executedOn,
      contribution: new Money(contribution as number),
      ticker,
      quantity: int(j['quantidade']),
      priceCents: int(j['precoCentavos']),
      costCents: int(j['custoCentavos']),
      upside: asDouble(j['potencial']),
      fairValue: asDouble(j['precoJusto']),
      origin,
      fairValueAsOf: parseIsoDay(j['avaliadoEm']),
      capOverridden: j['tetoIgnorado'] === true,
      cashAfterCents: int(j['caixaDepoisCentavos']),
    });
  }
}

/**
 * O acompanhamento como ele é gravado: o plano, a meta do dia em que começou
 * e o retorno esperado congelado naquele dia.
 */
export class TrackingRecord {
  readonly id: string;
  readonly name: string;
  /** Instante da criação. Metadado: não entra em conta nenhuma. */
  readonly createdAt: DateTime;
  readonly plan: TrackingPlan;
  readonly targetWealth: Money;
  /** Prazo da meta, em meses, contado do início. */
  readonly months: number;
  /** Retorno esperado da carteira na data de início (Ke médio), ou `null`. */
  readonly expectedReturn: number | null;
  /** De onde veio o esperado: `coorte AAAA-MM-DD` ou `motor AAAA-MM-DD`. */
  readonly expectedSource: string | null;
  /** Data de geração do pacote de coortes usado, ou `null`. */
  readonly cohortsGeneratedAt: string | null;

  constructor(args: {
    id: string;
    name: string;
    createdAt: DateTime;
    plan: TrackingPlan;
    targetWealth: Money;
    months: number;
    expectedReturn?: number | null;
    expectedSource?: string | null;
    cohortsGeneratedAt?: string | null;
  }) {
    this.id = args.id;
    this.name = args.name;
    this.createdAt = args.createdAt;
    this.plan = args.plan;
    this.targetWealth = args.targetWealth;
    this.months = args.months;
    this.expectedReturn = args.expectedReturn ?? null;
    this.expectedSource = args.expectedSource ?? null;
    this.cohortsGeneratedAt = args.cohortsGeneratedAt ?? null;
  }

  /** A meta do dia em que o acompanhamento começou. */
  get goal(): FinancialGoal {
    return FinancialGoal.unvalidated({
      initialContribution: this.plan.initial,
      monthlyContribution: this.plan.monthly,
      months: this.months,
      targetWealth: this.targetWealth,
    });
  }

  /** O dia em que o prazo da meta termina. */
  get endDate(): DateTime {
    const s = this.plan.start;
    const total = s.month - 1 + this.months;
    return DateTime.local(s.year + Math.floor(total / 12), (total % 12) + 1, Math.min(s.day, 28));
  }

  toJson(): JsonObject {
    return {
      id: this.id,
      nome: this.name,
      criadoEm: this.createdAt.toUtc().toIso8601String(),
      plano: this.plan.toJson(),
      valorDesejadoCentavos: this.targetWealth.cents,
      prazoMeses: this.months,
      esperado: this.expectedReturn,
      origemDoEsperado: this.expectedSource,
      coortesGeradasEm: this.cohortsGeneratedAt,
    };
  }

  static fromJson(j: unknown): TrackingRecord | null {
    if (!isJsonObject(j)) return null;
    const plan = TrackingPlan.fromJson(j['plano']);
    const id = j['id'];
    const target = j['valorDesejadoCentavos'];
    const months = j['prazoMeses'];
    const createdAt = typeof j['criadoEm'] === 'string' ? DateTime.tryParse(j['criadoEm']) : null;
    if (plan === null || typeof id !== 'string' || id.length === 0 || createdAt === null) return null;
    if (!Number.isInteger(target) || !Number.isInteger(months) || (months as number) <= 0) return null;
    return new TrackingRecord({
      id,
      name: typeof j['nome'] === 'string' ? j['nome'] : 'Acompanhamento',
      createdAt,
      plan,
      targetWealth: new Money(target as number),
      months: months as number,
      expectedReturn: asDouble(j['esperado']),
      expectedSource: typeof j['origemDoEsperado'] === 'string' ? j['origemDoEsperado'] : null,
      cohortsGeneratedAt: typeof j['coortesGeradasEm'] === 'string' ? j['coortesGeradasEm'] : null,
    });
  }
}

// ---------------------------------------------------------- Acompanhamento --

/** A posição de um ativo ao final do acompanhamento. */
export interface TrackingHolding {
  readonly ticker: Ticker;
  readonly shares: number;
  /** Valor de mercado no último pregão, em centavos. */
  readonly valueCents: number;
  /** Peso no patrimônio (ações mais caixa). */
  readonly weight: number;
  /** Pago pelas ações, com a tarifa, em centavos. */
  readonly paidCents: number;
  /** Proventos recebidos, líquidos, em centavos. */
  readonly dividendsCents: number;
  readonly purchases: number;
}

/** Resultado do acompanhamento até o último pregão disponível. */
export class TrackingOutcome {
  /** Pregões, do primeiro aporte ao último disponível. */
  readonly dates: readonly DateTime[];
  /** Patrimônio dia a dia: ações a mercado mais caixa, em reais. */
  readonly wealth: readonly number[];
  /** Aporte de cada pregão, em centavos — o fluxo dos benchmarks. */
  readonly flowCents: readonly number[];
  /** Aportado acumulado dia a dia, em reais: a linha "só os aportes". */
  readonly contributed: readonly number[];
  /** Todos os aportes com registro, em ordem de `seq`: os gravados e os novos. */
  readonly orders: readonly TrackingOrder[];
  /** Os aportes decididos agora, que ainda não estão gravados. */
  readonly newOrders: readonly TrackingOrder[];
  /** Aportes ao vivo vencidos que esperam a avaliação do motor para comprar. */
  readonly pendingLive: number;
  readonly holdings: readonly TrackingHolding[];
  readonly cashCents: number;
  readonly totalContributedCents: number;
  readonly totalCostCents: number;
  readonly totalDividendsCents: number;
  /** Proventos que ficaram de fora por falta do preço com direito. */
  readonly dividendsWithoutPrice: number;
  /** Retorno ponderado pelo dinheiro (XIRR), ao ano, ou `null`. */
  readonly moneyWeightedReturn: number | null;
  /** Retorno ponderado pelo tempo (TWR), acumulado. */
  readonly timeWeightedReturn: number;
  readonly warnings: readonly string[];

  constructor(args: {
    dates: readonly DateTime[];
    wealth: readonly number[];
    flowCents: readonly number[];
    contributed: readonly number[];
    orders: readonly TrackingOrder[];
    newOrders: readonly TrackingOrder[];
    pendingLive: number;
    holdings: readonly TrackingHolding[];
    cashCents: number;
    totalContributedCents: number;
    totalCostCents: number;
    totalDividendsCents: number;
    dividendsWithoutPrice: number;
    moneyWeightedReturn: number | null;
    timeWeightedReturn: number;
    warnings: readonly string[];
  }) {
    this.dates = args.dates;
    this.wealth = args.wealth;
    this.flowCents = args.flowCents;
    this.contributed = args.contributed;
    this.orders = args.orders;
    this.newOrders = args.newOrders;
    this.pendingLive = args.pendingLive;
    this.holdings = args.holdings;
    this.cashCents = args.cashCents;
    this.totalContributedCents = args.totalContributedCents;
    this.totalCostCents = args.totalCostCents;
    this.totalDividendsCents = args.totalDividendsCents;
    this.dividendsWithoutPrice = args.dividendsWithoutPrice;
    this.moneyWeightedReturn = args.moneyWeightedReturn;
    this.timeWeightedReturn = args.timeWeightedReturn;
    this.warnings = args.warnings;
  }

  get lastDate(): DateTime {
    return this.dates[this.dates.length - 1]!;
  }

  /** Patrimônio no último pregão, em centavos: ações a mercado mais caixa. */
  get finalValueCents(): number {
    let positions = 0;
    for (const h of this.holdings) positions += h.valueCents;
    return positions + this.cashCents;
  }

  /** Compras feitas com preço justo de coorte vencida — depois da última coorte. */
  get staleOrders(): number {
    return this.orders.filter((o) => o.origin === 'coorte' && (o.fairValueAgeDays ?? 0) > UpsideCohorts.staleAfterDays).length;
  }
}

/** Um aporte do cronograma. */
interface ScheduledEvent {
  readonly seq: number;
  readonly date: DateTime;
  readonly amountCents: number;
  readonly live: boolean;
}

/**
 * O cronograma de aportes sobre o calendário [dates]: o inicial no primeiro
 * pregão, e cada mensal no primeiro pregão a partir do dia pedido — ou no
 * último pregão do mês, quando o dia pedido não chega a existir nele.
 *
 * **Um mês ainda em curso só tem aporte quando o dia dele já chegou.** No fim
 * da série, o último pregão disponível não é o último do mês, e tratá-lo como
 * tal anteciparia o aporte — diferença que o backtest não tem, porque a
 * janela dele é toda passada.
 */
function schedule(plan: TrackingPlan, dates: readonly DateTime[]): ScheduledEvent[] {
  const events: ScheduledEvent[] = [];
  if (dates.length === 0) return events;
  const createdKey = dayKey(plan.createdOn);
  const first = dates[0]!;
  events.push({ seq: 0, date: first, amountCents: plan.initial.cents, live: dayKey(first) >= createdKey });
  if (!plan.monthly.isPositive) return events;
  let i = 0;
  let seq = 1;
  // Pula o mês do aporte inicial.
  while (i < dates.length && dates[i]!.year === first.year && dates[i]!.month === first.month) i++;
  while (i < dates.length) {
    const y = dates[i]!.year;
    const m = dates[i]!.month;
    let j = i;
    let chosen: DateTime | null = null;
    while (j < dates.length && dates[j]!.year === y && dates[j]!.month === m) {
      if (chosen === null && dates[j]!.day >= plan.contributionDay) chosen = dates[j]!;
      j++;
    }
    const monthEnded = j < dates.length;
    if (chosen === null && monthEnded) chosen = dates[j - 1]!;
    if (chosen === null) break;
    events.push({ seq, date: chosen, amountCents: plan.monthly.cents, live: dayKey(chosen) >= createdKey });
    seq++;
    i = j;
  }
  return events;
}

/**
 * **O acompanhamento da carteira**: o patrimônio que o plano da
 * meta produz quando cada aporte compra o ativo de maior potencial do dia.
 *
 * - Cada aporte cai no **caixa da carteira**, e o caixa compra ações
 *   **inteiras** — lote de uma ação, como no mercado fracionário da B3 — do
 *   ativo que [TopUpsidePolicy] escolhe. O que sobra espera o aporte
 *   seguinte.
 * - **Proventos** entram no caixa na data ex, sobre as ações detidas na
 *   data-com, com o JCP líquido da retenção da data-com — 15% até 2025,
 *   17,5% desde 2026. O valor por ação sai do rendimento
 *   `D ÷ P_com` sobre o fechamento da série na data-com, a mesma identidade
 *   do `TotalReturnIndex`: provento e preço com direito estão na base daquele
 *   dia, e a série, na base de hoje.
 * - Aporte agendado **antes** de [TrackingPlan.createdOn] é retrospectivo: a
 *   compra sai no próprio pregão do aporte, com o preço justo de [retro] — a
 *   coorte ponto no tempo. A partir dele, é ao vivo: a compra sai no último
 *   pregão disponível, com o preço justo de [live] — o motor de hoje. Sem
 *   [live], os aportes ao vivo vencidos ficam em [TrackingOutcome.pendingLive]
 *   e o caixa os espera.
 * - [recorded] são as compras já gravadas: valem como estão, e só o aporte
 *   sem registro é decidido.
 * - Aporte em que **nenhum** ativo tem preço justo não compra e não vai a
 *   [TrackingOutcome.newOrders]: a falta é de dado, e a decisão se refaz na
 *   abertura seguinte, em vez de ficar gravada como "não comprar".
 *
 * Tudo em centavos inteiros, como no backtest: o patrimônio fecha ao centavo
 * com `aportado + proventos − pago − tarifa = caixa`.
 */
export const PortfolioTracker = {
  run(args: {
    plan: TrackingPlan;
    prices: ReadonlyMap<Ticker, PriceSeries>;
    dividends?: ReadonlyMap<Ticker, readonly CashDividend[]>;
    recorded?: readonly TrackingOrder[];
    until: DateTime;
    retro: (ticker: Ticker, date: DateTime) => FairValueReading | null;
    live?: ((ticker: Ticker) => FairValueReading | null) | null;
  }): Result<TrackingOutcome> {
    const { plan, prices } = args;
    const live = args.live ?? null;
    if (plan.tickers.length === 0) return err(new InvalidInput('O acompanhamento precisa de ao menos um ativo.'));
    if (!plan.initial.isPositive && !plan.monthly.isPositive) {
      return err(new InvalidInput('É necessário ao menos um aporte inicial ou mensal.'));
    }
    if (plan.initial.cents < 0 || plan.monthly.cents < 0) return err(new InvalidInput('Os aportes não podem ser negativos.'));
    const startKey = dayKey(plan.start);
    const untilKey = dayKey(args.until);
    if (startKey > untilKey) return err(new InvalidInput('A data de início é posterior à data final.'));

    const calendar = new Map<number, DateTime>();
    for (const t of plan.tickers) {
      const series = prices.get(t);
      if (series === undefined) continue;
      for (const p of series.points) {
        const k = dayKey(p.date);
        if (k >= startKey && k <= untilKey && !calendar.has(k)) calendar.set(k, localDay(p.date));
      }
    }
    const dates = [...calendar.entries()].sort((a, b) => a[0] - b[0]).map(([, d]) => d);
    if (dates.length === 0) {
      return err(new InsufficientData('Nenhum ativo da carteira tem cotação a partir da data de início.'));
    }

    const warnings: string[] = [];
    const events = schedule(plan, dates);
    const recorded = new Map<number, TrackingOrder>();
    for (const o of args.recorded ?? []) {
      if (o.seq >= events.length) {
        warnings.push(`A compra gravada do aporte ${o.seq} não cabe no calendário de cotações e ficou de fora.`);
        continue;
      }
      recorded.set(o.seq, o);
    }

    const order = new Map<Ticker, number>();
    plan.tickers.forEach((t, i) => order.set(t, i));
    const shares = new Map<Ticker, number>();
    const paid = new Map<Ticker, number>();
    const dividendsOf = new Map<Ticker, number>();
    const purchases = new Map<Ticker, number>();
    for (const t of plan.tickers) {
      shares.set(t, 0);
      paid.set(t, 0);
      dividendsOf.set(t, 0);
      purchases.set(t, 0);
    }
    const sortedDividends = new Map<Ticker, CashDividend[]>();
    for (const t of plan.tickers) {
      const list = [...(args.dividends?.get(t) ?? [])].sort((a, b) => dayKey(a.exDate) - dayKey(b.exDate));
      sortedDividends.set(t, list);
    }
    const dividendCursor = new Map<Ticker, number>();
    for (const t of plan.tickers) {
      // Provento com data ex no primeiro pregão ou antes não é desta carteira:
      // ela ainda não tinha ação na data-com.
      const list = sortedDividends.get(t)!;
      let k = 0;
      while (k < list.length && dayKey(list[k]!.exDate) <= dayKey(dates[0]!)) k++;
      dividendCursor.set(t, k);
    }

    let cash = 0;
    let totalContributed = 0;
    let totalCost = 0;
    let totalDividends = 0;
    let withoutPrice = 0;
    let negativeCashWarned = false;
    const path = new WealthPathBuilder();
    const flows: number[] = [];
    const contributed: number[] = [];
    const cashFlows: CashFlow[] = [];
    const allOrders: TrackingOrder[] = [];
    const newOrders: TrackingOrder[] = [];
    let pendingLive = 0;
    // Aportes decididos sem preço justo para ativo nenhum: ficam fora de
    // [newOrders], porque gravá-los congelaria uma falta de dado como se
    // fosse a decisão de não comprar.
    let unpriced = 0;
    let nextEvent = 0;
    const executedSeqs = new Set<number>();
    const lastIndex = dates.length - 1;

    const priceCentsOn = (t: Ticker, d: DateTime): number | null => {
      const close = prices.get(t)?.closeAsOf(d) ?? null;
      if (close === null || !(close > 0)) return null;
      const c = Money.fromReais(close).cents;
      return c > 0 ? c : null;
    };

    /**
     * A compra do aporte, e se algum ativo tinha preço justo. Sem nenhum, a
     * falta é de dado, e não de decisão: a compra não é gravada, e o aporte
     * se decide de novo na próxima abertura (ver [unpriced]).
     */
    const decide = (
      event: ScheduledEvent,
      d: DateTime,
      reading: (t: Ticker) => FairValueReading | null,
    ): { order: TrackingOrder; priced: boolean } => {
      const values = new Map<Ticker, number>();
      let totalPositions = 0;
      for (const t of plan.tickers) {
        const pc = priceCentsOn(t, d);
        const v = pc === null ? 0 : shares.get(t)! * pc;
        values.set(t, v);
        totalPositions += v;
      }
      const candidates: PurchaseCandidate[] = [];
      for (const t of plan.tickers) {
        const pc = priceCentsOn(t, d);
        if (pc === null) continue;
        const r = reading(t);
        if (r === null) continue;
        const u = r.upsideAt(pc / 100);
        if (u === null || !Number.isFinite(u)) continue;
        candidates.push({ ticker: t, order: order.get(t)!, priceCents: pc, reading: r, upside: u, positionCents: values.get(t)! });
      }
      const decision = TopUpsidePolicy.choose({
        candidates,
        totalPositionCents: totalPositions,
        cashCents: cash,
        cap: plan.weightCap,
        costs: plan.costs,
      });
      const priced = candidates.length > 0;
      if (decision === null) {
        const idle = new TrackingOrder({
          seq: event.seq,
          scheduledOn: event.date,
          executedOn: d,
          contribution: new Money(event.amountCents),
          cashAfterCents: cash,
        });
        return { order: idle, priced };
      }
      const c = decision.candidate;
      const traded = decision.quantity * c.priceCents;
      const bought = new TrackingOrder({
        seq: event.seq,
        scheduledOn: event.date,
        executedOn: d,
        contribution: new Money(event.amountCents),
        ticker: c.ticker,
        quantity: decision.quantity,
        priceCents: c.priceCents,
        costCents: decision.costCents,
        upside: c.upside,
        fairValue: c.reading.fairValue,
        origin: c.reading.origin,
        fairValueAsOf: c.reading.asOf,
        capOverridden: decision.capOverridden,
        cashAfterCents: cash - traded - decision.costCents,
      });
      return { order: bought, priced };
    };

    const apply = (o: TrackingOrder): void => {
      executedSeqs.add(o.seq);
      allOrders.push(o);
      if (o.ticker === null || o.quantity <= 0) return;
      if (!shares.has(o.ticker)) {
        warnings.push(`A compra gravada do aporte ${o.seq} é de ${o.ticker.value}, que não está no plano, e ficou de fora.`);
        return;
      }
      const spent = o.tradedCents + o.costCents;
      shares.set(o.ticker, shares.get(o.ticker)! + o.quantity);
      paid.set(o.ticker, paid.get(o.ticker)! + spent);
      purchases.set(o.ticker, purchases.get(o.ticker)! + 1);
      totalCost += o.costCents;
      cash -= spent;
      if (cash < 0 && !negativeCashWarned) {
        negativeCashWarned = true;
        warnings.push(
          `O caixa recalculado não cobre a compra gravada do aporte ${o.seq}: os proventos ou as cotações mudaram desde a gravação.`,
        );
      }
    };

    for (let i = 0; i < dates.length; i++) {
      const d = dates[i]!;
      const key = dayKey(d);
      let flowToday = 0;

      // 1) Proventos com data ex até hoje, sobre as ações de ontem.
      if (plan.reinvestDividends) {
        for (const t of plan.tickers) {
          const list = sortedDividends.get(t)!;
          let k = dividendCursor.get(t)!;
          while (k < list.length && dayKey(list[k]!.exDate) <= key) {
            const p = list[k++]!;
            const held = shares.get(t)!;
            if (held <= 0) continue;
            const withRights = p.closeWithRights;
            const closeCom = prices.get(t)?.closeAsOf(localDay(p.lastDateWithRights)) ?? null;
            if (withRights === null || !(withRights > 0) || closeCom === null || !(closeCom > 0)) {
              withoutPrice++;
              continue;
            }
            const credit = Money.fromReais((held * closeCom * p.netAmountOnRecordDate) / withRights).cents;
            if (credit <= 0) continue;
            cash += credit;
            totalDividends += credit;
            dividendsOf.set(t, dividendsOf.get(t)! + credit);
          }
          dividendCursor.set(t, k);
        }
      }

      // 2) Aportes agendados para hoje entram no caixa.
      while (nextEvent < events.length && dayKey(events[nextEvent]!.date) === key) {
        const e = events[nextEvent++]!;
        if (e.amountCents > 0) {
          cash += e.amountCents;
          flowToday += e.amountCents;
          totalContributed += e.amountCents;
          cashFlows.push(new CashFlow({ date: d, amount: new Money(e.amountCents).negate() }));
        }
      }

      // 3) Compras de hoje, em ordem de aporte: as gravadas valem como estão;
      // as retrospectivas sem registro se decidem no próprio pregão do aporte;
      // as ao vivo vencidas, no último pregão disponível.
      const todays: { seq: number; run: () => void }[] = [];
      for (const [seq, o] of recorded) {
        if (dayKey(o.executedOn) === key) todays.push({ seq, run: () => apply(o) });
      }
      for (let e = 0; e < nextEvent; e++) {
        const ev = events[e]!;
        if (recorded.has(ev.seq) || executedSeqs.has(ev.seq)) continue;
        if (!ev.live && dayKey(ev.date) === key) {
          todays.push({
            seq: ev.seq,
            run: () => {
              const { order, priced } = decide(ev, d, (t) => args.retro(t, d));
              if (priced) newOrders.push(order);
              else unpriced++;
              apply(order);
            },
          });
        } else if (ev.live && i === lastIndex) {
          if (live === null) {
            pendingLive++;
            continue;
          }
          todays.push({
            seq: ev.seq,
            run: () => {
              const { order, priced } = decide(ev, d, live);
              if (priced) newOrders.push(order);
              else unpriced++;
              apply(order);
            },
          });
        }
      }
      todays.sort((a, b) => a.seq - b.seq);
      for (const t of todays) t.run();

      // 4) Marcação a mercado, em centavos inteiros.
      let positions = 0;
      for (const t of plan.tickers) {
        const pc = priceCentsOn(t, d);
        if (pc !== null) positions += shares.get(t)! * pc;
      }
      path.add({ value: (positions + cash) / 100, externalFlow: flowToday / 100 });
      flows.push(flowToday);
      contributed.push(totalContributed / 100);
    }

    for (const [seq, o] of recorded) {
      if (!executedSeqs.has(seq)) {
        warnings.push(`A compra gravada do aporte ${seq} tem data (${isoDay(o.executedOn)}) fora do calendário de cotações.`);
      }
    }

    const last = dates[lastIndex]!;
    const holdings: TrackingHolding[] = [];
    let positionsEnd = 0;
    const endValues = new Map<Ticker, number>();
    for (const t of plan.tickers) {
      const pc = priceCentsOn(t, last);
      const v = pc === null ? 0 : shares.get(t)! * pc;
      endValues.set(t, v);
      positionsEnd += v;
    }
    const wealthEnd = positionsEnd + cash;
    for (const t of plan.tickers) {
      holdings.push({
        ticker: t,
        shares: shares.get(t)!,
        valueCents: endValues.get(t)!,
        weight: wealthEnd > 0 ? endValues.get(t)! / wealthEnd : 0,
        paidCents: paid.get(t)!,
        dividendsCents: dividendsOf.get(t)!,
        purchases: purchases.get(t)!,
      });
    }

    const wealthPath = path.build();
    if (wealthEnd > 0) cashFlows.push(new CashFlow({ date: last, amount: new Money(wealthEnd) }));
    const xirr = Returns.extendedIrr(cashFlows).valueOrNull;
    const twr = Returns.timeWeighted(wealthPath);
    if (withoutPrice > 0) {
      warnings.push(`${withoutPrice} provento(s) ficaram de fora por falta do preço com direito publicado pela B3.`);
    }
    if (unpriced > 0) {
      warnings.push(
        `${unpriced} aporte(s) não compraram porque nenhum ativo tinha preço justo naquele dia: o dinheiro ficou em caixa, ` +
          'e a decisão não foi gravada — ela se refaz na próxima abertura.',
      );
    }

    allOrders.sort((a, b) => a.seq - b.seq);
    return ok(
      new TrackingOutcome({
        dates,
        wealth: wealthPath.values,
        flowCents: flows,
        contributed,
        orders: allOrders,
        newOrders,
        pendingLive,
        holdings,
        cashCents: cash,
        totalContributedCents: totalContributed,
        totalCostCents: totalCost,
        totalDividendsCents: totalDividends,
        dividendsWithoutPrice: withoutPrice,
        moneyWeightedReturn: xirr,
        timeWeightedReturn: twr,
        warnings,
      }),
    );
  },
};

// ------------------------------------------------- Benchmarks realizados --

/**
 * **Os mesmos aportes, nas mesmas datas, noutro destino**.
 *
 * A Meta comparava o plano com o CAGR decenal do CDI e do Ibovespa. O
 * acompanhamento compara com o que o CDI e o Ibovespa **realmente** renderam
 * no período, recebendo o mesmo fluxo de aportes da carteira: é a pergunta
 * "e se eu tivesse posto o mesmo dinheiro ali?".
 */
export const FlowBenchmarks = {
  /**
   * O fluxo crescendo a uma taxa **anual efetiva** [annual], composta por dia
   * corrido na base de 365: `V_k = V_{k−1} · (1+a)^(Δdias/365) + aporte_k`.
   *
   * A base de 365 é a do XIRR (`Returns.extendedIrr`), e por isso a carteira
   * cujo XIRR é igual a [annual] termina exatamente sobre esta curva.
   */
  atAnnualRate(args: { dates: readonly DateTime[]; flowCents: readonly number[]; annual: number }): number[] {
    const { dates, flowCents, annual } = args;
    const out: number[] = [];
    let v = 0;
    for (let k = 0; k < dates.length; k++) {
      if (k > 0) v *= Math.pow(1 + annual, civilDaysBetween(dates[k - 1]!, dates[k]!) / 365);
      v += (flowCents[k] ?? 0) / 100;
      out.push(v);
    }
    return out;
  },

  /**
   * O fluxo aplicado num índice — o Ibovespa, que a B3 calcula como índice de
   * retorno total. Cada aporte compra cotas do índice no fechamento do dia.
   * `null` quando o índice não cobre o primeiro aporte.
   */
  onIndex(args: { dates: readonly DateTime[]; flowCents: readonly number[]; index: PriceSeries }): number[] | null {
    const { dates, flowCents, index } = args;
    if (index.isEmpty || dates.length === 0 || dayKey(index.firstDate) > dayKey(dates[0]!)) return null;
    const out: number[] = [];
    let units = 0;
    for (let k = 0; k < dates.length; k++) {
      const level = index.closeAsOf(dates[k]!);
      if (level === null || !(level > 0)) return null;
      units += (flowCents[k] ?? 0) / 100 / level;
      out.push(units * level);
    }
    return out;
  },

  /**
   * O fluxo aplicado no CDI diário do Banco Central.
   *
   * A taxa publicada para o dia `D` remunera o depósito de `D` para o dia útil
   * seguinte; por isso o saldo do pregão `k−1` recebe as taxas dos dias
   * `[d_{k−1}, d_k)`, e o aporte de `d_k` começa a render no próprio dia.
   * `covered` diz se a série cobre o período, com folga de uma semana.
   */
  onDailyRates(args: { dates: readonly DateTime[]; flowCents: readonly number[]; rates: RateSeries }): {
    values: number[];
    covered: boolean;
  } {
    const { dates, flowCents, rates } = args;
    const points = rates.points;
    const out: number[] = [];
    let v = 0;
    let j = 0;
    for (let k = 0; k < dates.length; k++) {
      if (k > 0) {
        const from = dayKey(dates[k - 1]!);
        const to = dayKey(dates[k]!);
        while (j < points.length && dayKey(points[j]!.date) < from) j++;
        let factor = 1;
        while (j < points.length && dayKey(points[j]!.date) < to) {
          factor *= 1 + points[j]!.rate;
          j++;
        }
        v *= factor;
      }
      v += (flowCents[k] ?? 0) / 100;
      out.push(v);
    }
    const covered =
      points.length > 0 &&
      dates.length > 0 &&
      civilDaysBetween(points[0]!.date, dates[0]!) >= -7 &&
      civilDaysBetween(dates[dates.length - 1]!, points[points.length - 1]!.date) >= -7;
    return { values: out, covered };
  },

  /** XIRR de uma curva que recebeu [flowCents] e termina em `values[último]`. */
  moneyWeighted(args: { dates: readonly DateTime[]; flowCents: readonly number[]; values: readonly number[] }): number | null {
    const flows: CashFlow[] = [];
    for (let k = 0; k < args.dates.length; k++) {
      const c = args.flowCents[k] ?? 0;
      if (c > 0) flows.push(new CashFlow({ date: args.dates[k]!, amount: new Money(c).negate() }));
    }
    const end = args.values[args.values.length - 1];
    if (end === undefined || !(end > 0)) return null;
    flows.push(new CashFlow({ date: args.dates[args.dates.length - 1]!, amount: Money.fromReais(end) }));
    return Returns.extendedIrr(flows).valueOrNull;
  },
};

/**
 * **Onde a carteira chega no fim do prazo, no ritmo de agora**: o patrimônio
 * de hoje e os aportes que faltam, à taxa anual [annual] — o valor futuro de
 * uma série uniforme, a mesma conta da curva de acumulação da Meta.
 */
export function projectedEndValue(args: {
  currentWealth: number;
  monthlyContribution: number;
  remainingMonths: number;
  annual: number;
}): number {
  const m = Math.max(0, Math.round(args.remainingMonths));
  if (!(args.annual > -1)) return args.monthlyContribution * m;
  return RequiredReturnSolver.futureValue({
    rate: Math.pow(1 + args.annual, 1 / 12) - 1,
    initial: args.currentWealth,
    monthly: args.monthlyContribution,
    months: m,
  });
}

/** Meses inteiros de [from] a [to], contados pelo calendário. */
export function monthsBetween(from: DateTime, to: DateTime): number {
  const m = (to.year - from.year) * 12 + (to.month - from.month);
  return to.day < from.day ? m - 1 : m;
}

/** O período de [dates], para anualizar. */
export function trackingRange(dates: readonly DateTime[]): DateRange | null {
  return dates.length < 2 ? null : new DateRange(dates[0]!, dates[dates.length - 1]!);
}
