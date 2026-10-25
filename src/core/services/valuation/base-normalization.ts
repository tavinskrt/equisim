/** Por que o lucro de partida foi normalizado — ou não —, e em que direção. */

import { DartEnum, type WireKeyed } from '../../lang/dart-enum';
import type { ValuationLane, YearValue } from './capital-base';

/**
 * O que a normalização fez com o lucro de partida.
 *
 * Cada valor responde à pergunta de quem lê a avaliação: **o motor partiu do
 * lucro publicado, ou de outro, e por quê?**
 */
export class BaseNormalizationOutcome extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /**
   * O último exercício rendeu **menos** que o retorno típico da empresa — a
   * mediana do ciclo —, e destoou o bastante: a base subiu até o lucro que a
   * empresa teria rendendo o típico.
   */
  static readonly upward = new BaseNormalizationOutcome('upward', 0, 'paraCima');

  /**
   * O último exercício rendeu **mais** que o típico, e destoou o bastante: a
   * base desceu até o lucro que a empresa teria rendendo o típico.
   */
  static readonly downward = new BaseNormalizationOutcome('downward', 1, 'paraBaixo');

  /** O último exercício está dentro do normal da empresa: a base é o lucro publicado. */
  static readonly withinNormal = new BaseNormalizationOutcome('withinNormal', 2, 'dentroDoNormal');

  /**
   * Destoou, mas o retorno tem tendência que domina a reversão ao ciclo: o
   * último exercício é lido como o novo patamar, e a base é o publicado.
   */
  static readonly trend = new BaseNormalizationOutcome('trend', 3, 'tendencia');

  /**
   * Subiria, mas o lucro ou o EBITDA caiu mais da metade em três anos: a
   * empresa mudou de patamar, e a base fica no publicado.
   */
  static readonly healthLocked = new BaseNormalizationOutcome('healthLocked', 4, 'travadaPelaSaude');

  /**
   * O último exercício deu prejuízo: não há fator a aplicar, e a base é o
   * retorno típico sobre o capital de hoje (decisão 53).
   */
  static readonly rebuilt = new BaseNormalizationOutcome('rebuilt', 5, 'reconstruida');

  /**
   * Sem ciclo medível — série curta, ou ciclo que não é positivo —: a base é o
   * publicado.
   */
  static readonly noCycle = new BaseNormalizationOutcome('noCycle', 6, 'semCiclo');

  /** Fator imposto de fora, por varredura de diagnóstico. */
  static readonly imposed = new BaseNormalizationOutcome('imposed', 7, 'imposta');

  static readonly values: readonly BaseNormalizationOutcome[] = [
    BaseNormalizationOutcome.upward,
    BaseNormalizationOutcome.downward,
    BaseNormalizationOutcome.withinNormal,
    BaseNormalizationOutcome.trend,
    BaseNormalizationOutcome.healthLocked,
    BaseNormalizationOutcome.rebuilt,
    BaseNormalizationOutcome.noCycle,
    BaseNormalizationOutcome.imposed,
  ];

  /**
   * Chave gravada nas saídas — pacote de dados, rastro de auditoria,
   * relatório. É dado, e não nome de código: renomear o valor não a muda.
   */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'BaseNormalizationOutcome';
  }
}

/** Primeiro e último ano da janela do ciclo. */
export interface WindowYears {
  readonly first: number;
  readonly last: number;
}

/** Campos de [BaseNormalization]. */
export interface BaseNormalizationArgs {
  lane: ValuationLane;
  latestYear?: number | null;
  latestReturn?: number | null;
  cycleWindow?: readonly YearValue[];
  cycleReturn?: number | null;
  ratio?: number | null;
  robustZ?: number | null;
  deviates?: boolean;
  trendSlope?: number | null;
  trendT?: number | null;
  trendCriticalT?: number | null;
  trendDominates?: boolean;
  cyclicalPrecedence?: boolean;
  operationalDecline?: number | null;
  healthCapped?: boolean;
  healthExempt?: boolean;
  rawFactor?: number;
  factor?: number;
  saturated?: boolean;
  rebuilt?: boolean;
  rebuiltPositiveShare?: number | null;
  imposed?: boolean;
  publishedProfit?: number | null;
  baseProfit?: number | null;
}

/**
 * **A decisão da normalização do lucro de partida, com tudo o que a decidiu**
 * (Saída 1 da Porta 2).
 *
 * O motor não parte do lucro do último exercício quando ele destoa do retorno
 * típico da empresa: um ano só pode estar num pico ou num vale, e o preço justo
 * é proporcional ao lucro de partida. Ele compara o retorno sobre o capital do
 * último exercício com a mediana dos oito anteriores e, quando os dois
 * destoam, parte do lucro que a empresa de hoje teria rendendo a mediana:
 *
 * ```
 * fator = retorno típico ÷ retorno do último exercício   (entre 0,33 e 3)
 * base  = lucro do último exercício × fator
 * ```
 *
 * **Existe para explicar, e não para decidir.** Cada campo é o valor que a
 * cascata já usou — nada aqui recalcula a guarda —, e o rastro de auditoria e
 * a tela de edição do valuation leem daqui o porquê e a direção.
 */
export class BaseNormalization {
  /**
   * Via da avaliação: retorno sobre o capital investido na da firma, sobre o
   * patrimônio na do acionista.
   */
  readonly lane: ValuationLane;

  /** Ano e retorno do último exercício, ou `null` sem retorno medível. */
  readonly latestYear: number | null;
  readonly latestReturn: number | null;

  /**
   * Os exercícios cuja mediana é o retorno típico: os oito anteriores ao
   * último, ou menos quando a série é mais curta.
   */
  readonly cycleWindow: readonly YearValue[];

  /** O retorno típico — a mediana de [cycleWindow] —, ou `null` sem ciclo. */
  readonly cycleReturn: number | null;

  /** O último exercício sobre o típico, ou `null` sem ciclo positivo. */
  readonly ratio: number | null;

  /** A distância entre os dois, em desvios robustos da janela. */
  readonly robustZ: number | null;

  /**
   * `true` quando o último exercício destoa do típico (Guarda 3): a razão sai
   * de `[0,75; 1,33]` ou a distância passa de 1,5 desvio robusto.
   */
  readonly deviates: boolean;

  /**
   * A tendência do retorno (Guarda 1): inclinação em fração ao ano, `t` de
   * Newey-West e o crítico, ou `null` quando a série não a sustenta.
   */
  readonly trendSlope: number | null;
  readonly trendT: number | null;
  readonly trendCriticalT: number | null;

  /** `true` quando a tendência é significante e domina a reversão ao ciclo. */
  readonly trendDominates: boolean;

  /**
   * `true` em commodity e cíclico pesado, onde a reversão ao ciclo tem
   * precedência sobre a tendência (decisão 28).
   */
  readonly cyclicalPrecedence: boolean;

  /** Queda do lucro ou do EBITDA no triênio, em fração, ou `null` sem medida. */
  readonly operationalDecline: number | null;

  /** `true` quando a queda impediu a base de subir (decisões 28 e 29). */
  readonly healthCapped: boolean;

  /**
   * `true` quando a queda passou do limite, mas o setor é cíclico e está
   * isento da trava (decisão 30).
   */
  readonly healthExempt: boolean;

  /** O fator que a razão pedia, antes dos limites. */
  readonly rawFactor: number;

  /** O fator aplicado ao lucro do último exercício. */
  readonly factor: number;

  /** `true` quando o fator bruto saiu de `[0,33; 3]` e foi limitado. */
  readonly saturated: boolean;

  /**
   * `true` quando a base foi reconstruída do ciclo (decisão 53), e a fração
   * positiva da janela que a autorizou.
   */
  readonly rebuilt: boolean;
  readonly rebuiltPositiveShare: number | null;

  /** `true` quando o fator foi imposto de fora. */
  readonly imposed: boolean;

  /**
   * Lucro do último exercício, em reais, sem a normalização: `NOPAT` na via
   * da firma, lucro líquido na do acionista. `null` quando não é medível.
   */
  readonly publishedProfit: number | null;

  /** O lucro de partida que a cascata usou, em reais. */
  readonly baseProfit: number | null;

  /** Declara a decisão. Quem a monta é a cascata, na Saída 1. */
  constructor(args: BaseNormalizationArgs) {
    this.lane = args.lane;
    this.latestYear = args.latestYear ?? null;
    this.latestReturn = args.latestReturn ?? null;
    this.cycleWindow = args.cycleWindow ?? [];
    this.cycleReturn = args.cycleReturn ?? null;
    this.ratio = args.ratio ?? null;
    this.robustZ = args.robustZ ?? null;
    this.deviates = args.deviates ?? false;
    this.trendSlope = args.trendSlope ?? null;
    this.trendT = args.trendT ?? null;
    this.trendCriticalT = args.trendCriticalT ?? null;
    this.trendDominates = args.trendDominates ?? false;
    this.cyclicalPrecedence = args.cyclicalPrecedence ?? false;
    this.operationalDecline = args.operationalDecline ?? null;
    this.healthCapped = args.healthCapped ?? false;
    this.healthExempt = args.healthExempt ?? false;
    this.rawFactor = args.rawFactor ?? 1.0;
    this.factor = args.factor ?? 1.0;
    this.saturated = args.saturated ?? false;
    this.rebuilt = args.rebuilt ?? false;
    this.rebuiltPositiveShare = args.rebuiltPositiveShare ?? null;
    this.imposed = args.imposed ?? false;
    this.publishedProfit = args.publishedProfit ?? null;
    this.baseProfit = args.baseProfit ?? null;
  }

  /** O que a normalização fez, pela ordem em que a cascata decide. */
  get outcome(): BaseNormalizationOutcome {
    if (this.imposed) return BaseNormalizationOutcome.imposed;
    if (this.rebuilt) return BaseNormalizationOutcome.rebuilt;
    const current = this.latestReturn;
    const cycle = this.cycleReturn;
    if (current === null || cycle === null || cycle <= 0 || current <= 0) {
      return BaseNormalizationOutcome.noCycle;
    }
    if (!this.deviates) return BaseNormalizationOutcome.withinNormal;
    if (this.trendDominates && !this.cyclicalPrecedence) {
      return BaseNormalizationOutcome.trend;
    }
    if (this.healthCapped) return BaseNormalizationOutcome.healthLocked;
    if (this.factor > 1) return BaseNormalizationOutcome.upward;
    if (this.factor < 1) return BaseNormalizationOutcome.downward;
    return BaseNormalizationOutcome.withinNormal;
  }

  /** O primeiro e o último ano da janela do ciclo, ou `null` sem janela. */
  get windowYears(): WindowYears | null {
    return this.cycleWindow.length === 0
      ? null
      : { first: this.cycleWindow[0]!.year, last: this.cycleWindow[this.cycleWindow.length - 1]!.year };
  }
}
