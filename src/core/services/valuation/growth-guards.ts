/** As guardas e saídas da Porta 2, conforme a decisão 25. */

import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DartEnum, type WireKeyed } from '../../lang/dart-enum';
import { clamp, toStringAsFixed } from '../../lang/num';
import type { CapitalSeries } from './capital-base';
import { Inference } from './inference';

/**
 * Parâmetros homologados das portas e guardas.
 *
 * Todos foram calibrados sobre os dezoito ativos das carteiras de teste; a
 * tabela de hoje está em `docs/motor/03-base-e-crescimento.md`. **Continuam
 * sendo escolhas** — o ganho é que passaram a ter interpretação (nível de
 * significância, ponto de ruptura, materialidade, precisão), não que
 * dispensem calibragem.
 */
export const ValuationParameters = {
  /**
   * P3 — nível de significância dos testes de tendência e de dispersão.
   *
   * 10% e não 5%: com séries de 8 a 16 exercícios o poder é baixo. Medido:
   * passar para 5% não muda nenhuma classificação da amostra.
   */
  alpha: 0.1,

  /** P4 — desvios robustos a partir dos quais o exercício é atípico. */
  robustZ: 1.5,

  /**
   * P5 — banda de materialidade do nível do retorno, em razão contra o ciclo.
   * Vale em **união** com [robustZ]: o `z` mede raridade e a razão mede
   * materialidade.
   */
  bandLow: 0.75,
  bandHigh: 1.33,

  /**
   * P6 — capital externo tolerado, em múltiplos da base inicial da janela.
   * **Limiar de declaração, não de bloqueio**, desde 07/09/2026.
   */
  maxExternalCapital: 1.0,

  /** P7 — piso absoluto de materialidade da discordância entre estimadores. */
  dispersionFloor: 0.02,

  /** P8 — piso relativo da mesma discordância, em fração do próprio crescimento. */
  dispersionRelative: 0.25,

  /** P9 — fração de exercícios com fluxo de manutenção positivo exigida pela Porta 3. */
  minPositiveFlow: 0.6,

  // P10 — a participação mínima do equity como pós-condição da via da firma —
  // saiu pela decisão 102: ela trocava de via, e a troca era o degrau na taxa.

  /**
   * Teto e piso do fator de normalização da base.
   *
   * O fator é `f = retorno_ciclo / retorno_atual`, e ele explode quando o
   * denominador some. A saturação é **simétrica em razão**, `1/3` contra `3`.
   * **O teto cai para 1,00 quando a saúde operacional reprova**, exceto em
   * setor cíclico.
   */
  baseFactorFloor: 0.33,
  baseFactorCeiling: 3.0,

  /** P11 — janela do ciclo, em exercícios. **O parâmetro mais sensível de todos.** */
  cycleWindow: 8,

  /** P13 — erro-padrão máximo do estimador de crescimento. */
  maxGrowthStdError: 0.03,

  /** Inclinação mínima relativa: a deriva precisa superar a correção da reversão. */
  minTrendDominance: 1.0,

  /**
   * Janela, em anos, sobre a qual a deriva da tendência é medida. **É
   * [cycleWindow], e não o horizonte de projeção**: um veredito sobre a série
   * não pode depender de quantos anos o usuário pediu para ver projetados.
   */
  trendDriftWindow: 8,

  // ------------------------------------- Vantagem competitiva residual --

  /**
   * Teto da persistência anual do excedente de retorno (decisão 36). Em 0,90,
   * o `λ` máximo em dez anos é 0,35.
   */
  moatMaxPersistence: 0.9,

  /** Pares adjacentes mínimos para estimar a persistência. **Conta pares, não pontos.** */
  moatMinPersistencePairs: 4,

  /**
   * Teto de capital externo para o crescimento ser considerado orgânico.
   * **0,60 e não mais 0,35**, por determinação de 07/09/2026.
   */
  moatMaxExternalCapital: 0.6,

  /**
   * Queda máxima tolerada de lucro ou de EBITDA no triênio recente. Filtro de
   * saúde operacional; desde a decisão 36 vale só na Porta 2a, e setor
   * cíclico é isento ali.
   */
  maxOperationalDecline: 0.5,

  /** Exercícios do triênio de saúde operacional. */
  operationalHealthWindow: 3,

  /** Exercícios mínimos de histórico para a vantagem ser considerada comprovada. */
  moatMinPeriods: 8,

  /**
   * Teto de passes do veredito contra a taxa que o ponto fixo devolve
   * (decisão 44). Dez é onde a cauda medida termina.
   */
  moatMaxPasses: 10,

  // ---------------------------------------------- Alíquota do escudo fiscal --

  /**
   * Alíquota marginal estatutária brasileira: IRPJ 15% + adicional 10% + CSLL
   * 9% = **34%**. É a alíquota do escudo fiscal do WACC, e não a efetiva do
   * exercício.
   */
  statutoryTaxRate: 0.34,
} as const;

/** Como o crescimento foi obtido. */
export class GrowthOrigin extends DartEnum {
  /** Mediana das variações anuais da base de capital. */
  static readonly fundamental = new GrowthOrigin('fundamental', 0);

  /** Âncora *top-down* pela inflação, autorizada pela retenção observada. */
  static readonly inflationAnchor = new GrowthOrigin('inflationAnchor', 1);

  /** Sem crescimento: valor da capacidade de gerar lucro. */
  static readonly earningsPower = new GrowthOrigin('earningsPower', 2);

  static readonly values: readonly GrowthOrigin[] = [
    GrowthOrigin.fundamental,
    GrowthOrigin.inflationAnchor,
    GrowthOrigin.earningsPower,
  ];

  protected get typeName(): string {
    return 'GrowthOrigin';
  }
}

/** Resultado do teste de tendência da Guarda 1. */
export class TrendVerdict {
  /** Inclinação anual do retorno, em fração por ano. */
  readonly slope: number;

  /** Estatística `t` com erro-padrão de Newey-West. */
  readonly tStatistic: number;

  /** Valor crítico de `t` ao nível adotado. */
  readonly criticalT: number;

  /** Razão entre a deriva da tendência e a correção por reversão. */
  readonly dominance: number;

  /** `true` quando há tendência significante **e** ela domina a reversão. */
  readonly dominates: boolean;

  constructor(args: { slope: number; tStatistic: number; criticalT: number; dominance: number; dominates: boolean }) {
    this.slope = args.slope;
    this.tStatistic = args.tStatistic;
    this.criticalT = args.criticalT;
    this.dominance = args.dominance;
    this.dominates = args.dominates;
  }

  get isSignificant(): boolean {
    return Math.abs(this.tStatistic) >= this.criticalT;
  }
}

/** Resultado do teste de dispersão da Saída 2. */
export class DispersionVerdict {
  /** Crescimento pela mediana das variações. */
  readonly medianGrowth: number;

  /** Crescimento pela regressão log-linear. */
  readonly regressionGrowth: number;

  /** Erro-padrão do estimador por regressão, pelo método delta. */
  readonly stdError: number;

  /** Discordância padronizada. */
  readonly d: number;

  /** Valor crítico de `D`. */
  readonly criticalD: number;

  /** `true` quando o estimador é preciso e os dois métodos concordam. */
  readonly isIdentified: boolean;

  /** Por que não foi identificado, quando não foi. */
  readonly failure: string | null;

  constructor(args: {
    medianGrowth: number;
    regressionGrowth: number;
    stdError: number;
    d: number;
    criticalD: number;
    isIdentified: boolean;
    failure?: string | null;
  }) {
    this.medianGrowth = args.medianGrowth;
    this.regressionGrowth = args.regressionGrowth;
    this.stdError = args.stdError;
    this.d = args.d;
    this.criticalD = args.criticalD;
    this.isIdentified = args.isIdentified;
    this.failure = args.failure ?? null;
  }
}

/**
 * Qual condição barrou a vantagem competitiva residual. Existe para
 * **auditoria metodológica**, não para a conta.
 */
export class MoatBlock extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** Sem retorno do ciclo medível — série curta ou lucro não publicado. */
  static readonly noCycleReturn = new MoatBlock('noCycleReturn', 0, 'semRetornoDoCiclo');

  /** Custo de capital de equilíbrio não positivo: nada a comparar. */
  static readonly noCostOfCapital = new MoatBlock('noCostOfCapital', 1, 'semCustoDeCapital');

  /** Histórico mais curto que [ValuationParameters.moatMinPeriods]. */
  static readonly shortHistory = new MoatBlock('shortHistory', 2, 'historicoCurto');

  /** Φ não medido. Ausência não é aprovação. */
  static readonly externalCapitalUnmeasured = new MoatBlock('externalCapitalUnmeasured', 3, 'capitalExternoNaoMedido');

  /** Φ acima de [ValuationParameters.moatMaxExternalCapital]. */
  static readonly inorganicGrowth = new MoatBlock('inorganicGrowth', 4, 'crescimentoInorganico');

  /** Excedente com menos pares adjacentes que o mínimo: sem `λ`. */
  static readonly persistenceNotEstimable = new MoatBlock('persistenceNotEstimable', 5, 'persistenciaNaoEstimavel');

  /** O excedente do ciclo não é positivo: não há vantagem a preservar. */
  static readonly noExcess = new MoatBlock('noExcess', 6, 'semExcedente');

  /** A persistência medida não deixa excedente sobreviver ao horizonte. */
  static readonly degenerateExcess = new MoatBlock('degenerateExcess', 7, 'excedenteDegenerado');

  /** O negócio opera sob contrato de prazo determinado. */
  static readonly fixedTerm = new MoatBlock('fixedTerm', 8, 'prazoDeterminado');

  static readonly values: readonly MoatBlock[] = [
    MoatBlock.noCycleReturn,
    MoatBlock.noCostOfCapital,
    MoatBlock.shortHistory,
    MoatBlock.externalCapitalUnmeasured,
    MoatBlock.inorganicGrowth,
    MoatBlock.persistenceNotEstimable,
    MoatBlock.noExcess,
    MoatBlock.degenerateExcess,
    MoatBlock.fixedTerm,
  ];

  /** Chave gravada nas saídas. É dado, e não nome de código. */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'MoatBlock';
  }
}

/** Veredito da vantagem competitiva residual, com o porquê da recusa. */
export class MoatVerdict {
  /** Retorno terminal preservado, ou `null` no estado estacionário. */
  readonly terminalReturn: number | null;

  /** Condições que reprovaram, na ordem em que são avaliadas. Vazia quando comprovada. */
  readonly blocks: readonly MoatBlock[];

  /** ROIC ou ROE mediano do ciclo, como entrou na conta. */
  readonly cycleReturn: number | null;

  /** Custo de capital de equilíbrio contra o qual o retorno foi medido. */
  readonly terminalDiscountRate: number;

  /** Φ — capital externo em múltiplos da base inicial da janela. */
  readonly externalCapitalRatio: number | null;

  /** Exercícios utilizáveis na série de capital. */
  readonly periods: number;

  /** Persistência anual do excedente, crua, sem teto. */
  readonly rawPersistence: number | null;

  /** Persistência aplicada: a crua confinada em `[0, moatMaxPersistence]`. */
  readonly persistence: number | null;

  /** Fração do excedente preservada na perpetuidade — `φ^N`. */
  readonly retainedFraction: number | null;

  /** Pares usados na regressão de persistência. */
  readonly persistencePoints: number;

  constructor(args: {
    terminalReturn: number | null;
    blocks: readonly MoatBlock[];
    cycleReturn: number | null;
    terminalDiscountRate: number;
    externalCapitalRatio: number | null;
    periods: number;
    rawPersistence: number | null;
    persistence: number | null;
    retainedFraction: number | null;
    persistencePoints: number;
  }) {
    this.terminalReturn = args.terminalReturn;
    this.blocks = args.blocks;
    this.cycleReturn = args.cycleReturn;
    this.terminalDiscountRate = args.terminalDiscountRate;
    this.externalCapitalRatio = args.externalCapitalRatio;
    this.periods = args.periods;
    this.rawPersistence = args.rawPersistence;
    this.persistence = args.persistence;
    this.retainedFraction = args.retainedFraction;
    this.persistencePoints = args.persistencePoints;
  }

  /** `true` quando a vantagem foi comprovada. */
  get isProven(): boolean {
    return this.terminalReturn !== null;
  }

  /** Primeira condição que barrou, ou `null` quando comprovada. */
  get primaryBlock(): MoatBlock | null {
    return this.blocks.length === 0 ? null : this.blocks[0]!;
  }

  /** Excedente do ciclo sobre o custo de capital de equilíbrio, em fração. */
  get spread(): number | null {
    return this.cycleReturn === null ? null : this.cycleReturn - this.terminalDiscountRate;
  }
}

/** Excedente de um exercício, com o ano. */
export interface YearExcess {
  readonly year: number;
  readonly excess: number;
}

/** Desvio do exercício contra o ciclo, com as duas medidas que o decidem. */
export interface CycleDeviation {
  readonly z: number;
  readonly ratio: number;
  readonly deviates: boolean;
}

/** Persistência estimada do excedente. */
export interface ExcessPersistence {
  readonly phi: number;
  readonly rawPhi: number;
  readonly pairs: number;
}

/**
 * `base^expoente` para expoente inteiro. **Expoente zero devolve 1, e não 0**;
 * expoente negativo ou base não positiva devolve 0.
 */
function power(base: number, exponent: number): number {
  if (exponent === 0) return 1;
  if (exponent < 0 || base <= 0) return 0;
  let r = 1.0;
  for (let i = 0; i < exponent; i++) r *= base;
  return r;
}

/** As guardas da Porta 2 e a decisão da taxa. */
export const GrowthGuards = {
  /**
   * Guarda 1 — a tendência do retorno domina a reversão à média?
   *
   * Roda sobre a **série completa**, e exige significância **e** dominância.
   * A deriva é medida na janela do ciclo, não no horizonte de projeção.
   */
  trend(series: CapitalSeries, options: { driftWindow?: number } = {}): TrendVerdict | null {
    const driftWindow = options.driftWindow ?? ValuationParameters.trendDriftWindow;
    const r = series.returns;
    if (r.length < 6) return null;

    const xs = r.map((p) => p.year);
    const ys = r.map((p) => p.value);
    const fit = Inference.ols(xs, ys);
    if (fit === null) return null;

    const se = Inference.hacSlopeStdError(xs, fit) ?? fit.slopeStdError;
    const t = fit.slope / se;
    const tc = Inference.studentT(1 - ValuationParameters.alpha / 2, fit.degreesOfFreedom);

    const current = series.latestReturn;
    const cycle = series.cycleReturn({ window: ValuationParameters.cycleWindow });
    if (current === null || cycle === null) return null;

    const correction = Math.abs(current - cycle);
    const drift = Math.abs(fit.slope) * driftWindow;
    const rho = correction > 1e-12 ? drift / correction : Infinity;

    const significant = Math.abs(t) >= tc;
    return new TrendVerdict({
      slope: fit.slope,
      tStatistic: t,
      criticalT: tc,
      dominance: rho,
      dominates: significant && rho >= ValuationParameters.minTrendDominance,
    });
  },

  /**
   * Guarda 2 — quanto da expansão da base veio de capital externo:
   * `externo = max(0, ΔBase − lucro)` somado na janela, sobre a base inicial.
   * **Não usa a variação do capital social.** `null` sem janela suficiente.
   */
  externalCapitalRatio(series: CapitalSeries): number | null {
    const p = series.points;
    const w = ValuationParameters.cycleWindow;
    if (p.length < w + 1) return null;

    const window = p.slice(p.length - w - 1);
    const initial = window[0]!.base;
    if (initial <= 0) return null;

    let externalRepository = 0.0;
    for (let i = 1; i < window.length; i++) {
      const a = window[i - 1]!;
      const b = window[i]!;
      // O ano corrente anualizado não entra: a base variou por meses, e o
      // lucro é de um ano (decisão 153).
      if (b.year - a.year !== 1 || b.partial) continue;
      const delta = b.base - a.base;
      const profit = b.profit ?? 0.0;
      const excess = delta - profit;
      if (excess > 0) externalRepository += excess;
    }
    const phi = externalRepository / initial;
    return Number.isFinite(phi) ? phi : null;
  },

  /** Guarda 3 — o exercício corrente destoa do ciclo o bastante para normalizar? */
  deviatesFromCycle(series: CapitalSeries): boolean | null {
    return GrowthGuards.cycleDeviation(series)?.deviates ?? null;
  },

  /**
   * A Guarda 3 com as duas medidas que a decidem: `z` em desvios robustos (o
   * MAD escalado da janela, ou zero sem dispersão) e a razão contra o ciclo.
   */
  cycleDeviation(series: CapitalSeries): CycleDeviation | null {
    const current = series.latestReturn;
    const cycle = series.cycleReturn({ window: ValuationParameters.cycleWindow });
    if (current === null || cycle === null || cycle <= 0) return null;

    const r = series.returns;
    const ini = r.length - 1 - ValuationParameters.cycleWindow;
    const window = r.slice(ini < 0 ? 0 : ini, r.length - 1);
    const scale = Inference.scaledMad(window.map((x) => x.value));

    const z = scale === null ? 0.0 : Math.abs(current - cycle) / scale;
    const ratio = current / cycle;

    return {
      z,
      ratio,
      deviates:
        z > ValuationParameters.robustZ || ratio < ValuationParameters.bandLow || ratio > ValuationParameters.bandHigh,
    };
  },

  /**
   * Saída 2, primeira perna — o crescimento é identificável? Precisão,
   * concordância e materialidade. `null` quando a série não sustenta nenhum
   * dos dois estimadores.
   */
  dispersion(series: CapitalSeries): DispersionVerdict | null {
    const changes = series.annualVariations;
    if (changes.length < 4) return null;
    const gMedian = Inference.median(changes);
    if (gMedian === null) return null;

    // A regressão da base também deixa de fora o ano corrente anualizado, cuja
    // base é de meses depois da anterior, e não de um ano (decisão 153).
    const full = series.points.filter((p) => !p.partial);
    const xs = full.map((p) => p.year);
    const ys = full.map((p) => Math.log(p.base));
    const fit = Inference.ols(xs, ys);
    if (fit === null) return null;

    const gRegression = Math.exp(fit.slope) - 1;
    // Método delta sobre g = e^b − 1: se(ĝ) = e^b · se(b̂).
    const se = (1 + gRegression) * fit.slopeStdError;
    if (!Number.isFinite(se) || se <= 0) return null;

    const difference = Math.abs(gMedian - gRegression);
    const d = difference / se;
    const dc = Inference.studentT(1 - ValuationParameters.alpha / 2, fit.degreesOfFreedom);
    const delta = Math.max(ValuationParameters.dispersionFloor, ValuationParameters.dispersionRelative * Math.abs(gMedian));

    let failure: string | null = null;
    if (se > ValuationParameters.maxGrowthStdError) {
      failure =
        'estimador impreciso: erro-padrão de ' +
        `${toStringAsFixed(se * 100, 1)} pontos percentuais, acima do ` +
        `máximo de ${toStringAsFixed(ValuationParameters.maxGrowthStdError * 100, 0)}`;
    } else if (d > dc && difference > delta) {
      failure =
        'os dois estimadores discordam em ' +
        `${toStringAsFixed(difference * 100, 1)} pontos percentuais ` +
        `(${toStringAsFixed(d, 1)} erros-padrão), acima do que a série sustenta`;
    }

    return new DispersionVerdict({
      medianGrowth: gMedian,
      regressionGrowth: gRegression,
      stdError: se,
      d,
      criticalD: dc,
      isIdentified: failure === null,
      failure,
    });
  },

  /**
   * Saída 2, segunda perna — a âncora de inflação é financiável? Crescer à
   * inflação exige reter `inflação / retorno`.
   */
  anchorIsFundable(args: { inflation: number; cycleReturn: number | null; observedRetention: number | null }): boolean {
    const { inflation, cycleReturn, observedRetention } = args;
    if (cycleReturn === null || cycleReturn <= 0) return false;
    if (observedRetention === null) return false;
    const requiredValue = inflation / cycleReturn;
    return requiredValue < 1.0 && requiredValue <= observedRetention;
  },

  /**
   * Porta 3 — o fluxo da firma sustenta uma perpetuidade? Mede sobre o
   * **fluxo de manutenção** (`≈ NOPAT`).
   */
  firmFlowIsSustained(snapshots: readonly FundamentalsSnapshot[]): boolean {
    const v: number[] = [];
    for (const s of snapshots) {
      const n = s.nopatOrDerived;
      if (n !== null) v.push(n);
    }
    if (v.length < 4) return false;
    const positives = v.filter((x) => x > 0).length;
    return positives / v.length >= ValuationParameters.minPositiveFlow;
  },

  /**
   * Queda de lucro ou de EBITDA no triênio recente, em fração — a **pior**
   * das duas. `null` sem referência positiva a comparar.
   */
  recentOperationalDecline(snapshots: readonly FundamentalsSnapshot[]): number | null {
    const w = ValuationParameters.operationalHealthWindow;
    if (snapshots.length < w + 1) return null;

    const current = snapshots[snapshots.length - 1]!;
    const reference = snapshots[snapshots.length - 1 - w]!;
    // O triênio precisa ser mesmo de três anos: buraco na série compararia
    // pontas de distâncias diferentes e o limiar deixaria de significar o mesmo.
    if (current.fiscalPeriodEnd.year - reference.fiscalPeriodEnd.year !== w) {
      return null;
    }

    const decline = (recent: number | null, base: number | null): number | null => {
      if (recent === null || base === null || base <= 0) return null;
      const q = 1 - recent / base;
      return Number.isFinite(q) ? q : null;
    };

    const byProfit = decline(current.netIncome, reference.netIncome);
    const byEbitda = decline(current.ebitda, reference.ebitda);
    if (byProfit === null) return byEbitda;
    if (byEbitda === null) return byProfit;
    return byProfit > byEbitda ? byProfit : byEbitda;
  },

  /**
   * Persistência anual do excedente de retorno, por AR(1) sobre pares de
   * anos **adjacentes**. Sem correção de viés de amostra pequena — tentada e
   * descartada por medição. Confinada em `[0, moatMaxPersistence]`.
   */
  excessPersistence(excessReturns: readonly YearExcess[]): ExcessPersistence | null {
    const x: number[] = [];
    const y: number[] = [];
    for (let i = 1; i < excessReturns.length; i++) {
      const previous = excessReturns[i - 1]!;
      const current = excessReturns[i]!;
      if (current.year - previous.year !== 1) continue;
      if (!Number.isFinite(previous.excess) || !Number.isFinite(current.excess)) continue;
      x.push(previous.excess);
      y.push(current.excess);
    }
    if (x.length < ValuationParameters.moatMinPersistencePairs) return null;

    const fit = Inference.ols(x, y);
    if (fit === null || !Number.isFinite(fit.slope)) return null;

    const raw = fit.slope;
    const confined = clamp(raw, 0.0, ValuationParameters.moatMaxPersistence);

    return { phi: confined, rawPhi: raw, pairs: x.length };
  },

  /**
   * Retorno terminal que a persistência medida do excedente sustenta:
   * `ROIC_∞ = WACC_∞ + φ^N · (ROIC_ciclo − WACC_∞)`. As condições são
   * **todas avaliadas**, e não em curto-circuito.
   */
  residualMoat(args: {
    cycleReturn: number | null;
    terminalDiscountRate: number;
    externalCapitalRatio: number | null;
    periods: number;
    excessReturns: readonly YearExcess[];
    projectionYears: number;
    finiteTerm?: boolean;
  }): MoatVerdict {
    const { cycleReturn, terminalDiscountRate, externalCapitalRatio, periods, projectionYears } = args;
    const finiteTerm = args.finiteTerm ?? false;
    const returnRate = cycleReturn !== null && Number.isFinite(cycleReturn) ? cycleReturn : null;
    const persistence = GrowthGuards.excessPersistence(args.excessReturns);

    const blocks: MoatBlock[] = [];
    if (finiteTerm) blocks.push(MoatBlock.fixedTerm);
    if (returnRate === null) blocks.push(MoatBlock.noCycleReturn);
    if (terminalDiscountRate <= 0) blocks.push(MoatBlock.noCostOfCapital);
    if (periods < ValuationParameters.moatMinPeriods) {
      blocks.push(MoatBlock.shortHistory);
    }
    if (externalCapitalRatio === null) {
      blocks.push(MoatBlock.externalCapitalUnmeasured);
    } else if (externalCapitalRatio > ValuationParameters.moatMaxExternalCapital) {
      blocks.push(MoatBlock.inorganicGrowth);
    }
    if (persistence === null) blocks.push(MoatBlock.persistenceNotEstimable);
    if (returnRate !== null && returnRate <= terminalDiscountRate) {
      blocks.push(MoatBlock.noExcess);
    }

    let lambda: number | null = null;
    let terminal: number | null = null;
    if (blocks.length === 0) {
      // O horizonte é o expoente do decaimento, e horizonte nulo daria
      // `φ⁰ = 1` — o excedente inteiro preservado para sempre. `DcfCalculator`
      // já recusa projeção com menos de um ano; este piso existe para que a
      // função não dependa dessa recusa para estar certa.
      const horizon = projectionYears < 1 ? 1 : projectionYears;
      lambda = power(persistence!.phi, horizon);
      const t = terminalDiscountRate + lambda * (returnRate! - terminalDiscountRate);
      if (Number.isFinite(t) && t > terminalDiscountRate) {
        terminal = t;
      } else {
        blocks.push(MoatBlock.degenerateExcess);
      }
    }

    return new MoatVerdict({
      terminalReturn: terminal,
      blocks: Object.freeze([...blocks]),
      cycleReturn: returnRate,
      terminalDiscountRate,
      externalCapitalRatio,
      periods,
      rawPersistence: persistence?.rawPhi ?? null,
      persistence: persistence?.phi ?? null,
      retainedFraction: lambda,
      persistencePoints: persistence?.pairs ?? 0,
    });
  },
};
