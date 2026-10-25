import { DartEnum } from '../../lang/dart-enum';
import type { FinancialGoal, RequiredReturn } from '../../entities/financial-goal';

/**
 * Referências de mercado usadas para julgar se uma meta é plausível.
 *
 * Os valores **não são constantes de código**: vêm das séries observadas, de
 * modo que os limiares se atualizam sozinhos conforme o mercado muda.
 */
export class MarketAnchors {
  /**
   * CAGR do CDI na janela de referência, em fração. Média **histórica**, para
   * julgar a meta. Não serve como taxa de desconto — para isso existe
   * [currentRiskFreeRate].
   */
  readonly riskFreeCagr: number;

  /**
   * CDI **corrente** anualizado, em fração — a taxa livre de risco do CAPM.
   * Desconto olha para frente: o custo de oportunidade de hoje é o juro de
   * hoje, não a média da década.
   */
  readonly currentRiskFreeRate: number;

  /** CAGR do índice de mercado na janela de referência, em fração. */
  readonly marketCagr: number;

  /**
   * Inflação anual observada na janela (IPCA, BCB SGS 433), em fração. Existe
   * para manter **real e nominal na mesma unidade**.
   */
  readonly inflationCagr: number;

  /**
   * Crescimento **real** da economia na janela, em fração — IBC-Br
   * dessazonalizado por média móvel de 12 meses (decisão 25).
   */
  readonly realEconomyGrowth: number;

  /** Janela observada, para exibição. */
  readonly observedYears: number;

  /**
   * Declara as âncoras. **Omitir [currentRiskFreeRate] faz cair para
   * [riskFreeCagr]** — o comportamento antigo, preservado para quem constrói
   * as âncoras à mão.
   */
  constructor(args: {
    riskFreeCagr: number;
    marketCagr: number;
    observedYears: number;
    inflationCagr?: number;
    realEconomyGrowth?: number;
    currentRiskFreeRate?: number | null;
  }) {
    this.riskFreeCagr = args.riskFreeCagr;
    this.marketCagr = args.marketCagr;
    this.observedYears = args.observedYears;
    this.inflationCagr = args.inflationCagr ?? 0.045;
    this.realEconomyGrowth = args.realEconomyGrowth ?? 0.0145;
    this.currentRiskFreeRate = args.currentRiskFreeRate ?? args.riskFreeCagr;
  }

  /**
   * Âncoras medidas em 19/08/2026 sobre janela de 10 anos: CDI 9,40% a.a.
   * (BCB SGS 12), Ibovespa 11,26% a.a. (^BVSP) e IPCA 4,50% a.a. (BCB SGS
   * 433). Servem apenas de fallback.
   */
  static readonly fallback2026 = new MarketAnchors({
    riskFreeCagr: 0.094,
    marketCagr: 0.1126,
    inflationCagr: 0.045,
    realEconomyGrowth: 0.0145,
    currentRiskFreeRate: 0.1415,
    observedYears: 10,
  });

  /**
   * Crescimento nominal de longo prazo da economia:
   * `(1 + real) × (1 + inflação) − 1`. **É composição, não PIB nominal
   * medido** (decisão 25).
   */
  get nominalEconomyGrowth(): number {
    return (1 + this.realEconomyGrowth) * (1 + this.inflationCagr) - 1;
  }
}

/** Classificação de viabilidade da meta. */
export class FeasibilityLevel extends DartEnum {
  /** Meta atingível sem risco: a renda fixa já entrega a taxa necessária. */
  static readonly riskFreeSufficient = new FeasibilityLevel('riskFreeSufficient', 0);
  /** Dentro do retorno histórico do mercado. */
  static readonly plausible = new FeasibilityLevel('plausible', 1);
  /** Acima do mercado: exige superá-lo de forma consistente. */
  static readonly demanding = new FeasibilityLevel('demanding', 2);
  /** Fora de qualquer referência histórica: bloquear. */
  static readonly unrealistic = new FeasibilityLevel('unrealistic', 3);

  static readonly values: readonly FeasibilityLevel[] = [
    FeasibilityLevel.riskFreeSufficient,
    FeasibilityLevel.plausible,
    FeasibilityLevel.demanding,
    FeasibilityLevel.unrealistic,
  ];

  protected get typeName(): string {
    return 'FeasibilityLevel';
  }
}

/**
 * Por que a meta recebeu o veredito que recebeu. Mais fino que
 * [FeasibilityLevel] de propósito: é **este** enum que a apresentação consome
 * para escolher o texto.
 */
export class FeasibilityReason extends DartEnum {
  /** O plano nem chegou a ter taxa: o solver o recusou. */
  static readonly unsolvable = new FeasibilityReason('unsolvable', 0);
  /** Os aportes sozinhos já superam o valor desejado. */
  static readonly contributionsAlreadySuffice = new FeasibilityReason('contributionsAlreadySuffice', 1);
  /** A taxa exigida fica abaixo do CDI histórico. */
  static readonly belowRiskFree = new FeasibilityReason('belowRiskFree', 2);
  /** A taxa exigida cabe dentro do retorno histórico do índice. */
  static readonly withinMarket = new FeasibilityReason('withinMarket', 3);
  /** Acima do índice, mas até o múltiplo de alerta. */
  static readonly aboveMarket = new FeasibilityReason('aboveMarket', 4);
  /** Acima do múltiplo de alerta, até o de bloqueio. */
  static readonly farAboveMarket = new FeasibilityReason('farAboveMarket', 5);
  /** Além de qualquer referência histórica. */
  static readonly beyondAnyReference = new FeasibilityReason('beyondAnyReference', 6);

  static readonly values: readonly FeasibilityReason[] = [
    FeasibilityReason.unsolvable,
    FeasibilityReason.contributionsAlreadySuffice,
    FeasibilityReason.belowRiskFree,
    FeasibilityReason.withinMarket,
    FeasibilityReason.aboveMarket,
    FeasibilityReason.farAboveMarket,
    FeasibilityReason.beyondAnyReference,
  ];

  protected get typeName(): string {
    return 'FeasibilityReason';
  }
}

/**
 * Veredito sobre a meta.
 *
 * **Carrega dados, não prosa.** A frase que o usuário lê é composta na
 * apresentação, a partir de [reason] e dos números que viajam aqui — ver
 * `feasibilityCopy`, em `src/ui/copy/`.
 */
export class FeasibilityVerdict {
  /** Classificação da meta. */
  readonly level: FeasibilityLevel;

  /** Caso concreto que produziu [level]. */
  readonly reason: FeasibilityReason;

  /**
   * Taxa anual exigida pela meta, em fração. `null` quando não há taxa
   * (decisão 58: nulo em vez de `Infinity`).
   */
  readonly requiredAnnualRate: number | null;

  /** Quantas vezes a taxa exigida supera o CAGR histórico do índice, ou `null`. */
  readonly marketMultiple: number | null;

  /** Âncoras contra as quais a meta foi julgada. */
  readonly anchors: MarketAnchors;

  constructor(args: {
    level: FeasibilityLevel;
    reason: FeasibilityReason;
    requiredAnnualRate: number | null;
    anchors: MarketAnchors;
    marketMultiple?: number | null;
  }) {
    this.level = args.level;
    this.reason = args.reason;
    this.requiredAnnualRate = args.requiredAnnualRate;
    this.anchors = args.anchors;
    this.marketMultiple = args.marketMultiple ?? null;
  }
}

/**
 * Julga se uma meta patrimonial é plausível diante do que o mercado entregou.
 *
 * Os limiares são **múltiplos do CAGR observado do Ibovespa**, não constantes
 * absolutas: uma exigência de 15% a.a. é modesta numa década de juro alto e
 * agressiva numa de juro baixo.
 */
export const GoalFeasibility = {
  /** Múltiplo do retorno de mercado acima do qual a meta é bloqueada. */
  blockingMultiple: 2.5,

  /** Múltiplo acima do qual a meta recebe alerta. */
  warningMultiple: 2.0,

  /**
   * Classifica a meta. Abaixo do CDI é `riskFreeSufficient`; até o CAGR do
   * mercado é `plausible`; até [blockingMultiple] vezes esse CAGR é
   * `demanding`, em duas faixas; acima disso é `unrealistic`. Nunca falha.
   */
  assess(args: { required: RequiredReturn; anchors: MarketAnchors; goal?: FinancialGoal | null }): FeasibilityVerdict {
    const { anchors } = args;
    const annual = args.required.annual;
    // Guarda de divisão: âncora não positiva produziria `Infinity`.
    const multiple = anchors.marketCagr > 0 ? annual / anchors.marketCagr : null;

    const verdict = (level: FeasibilityLevel, why: FeasibilityReason): FeasibilityVerdict =>
      new FeasibilityVerdict({ level, reason: why, requiredAnnualRate: annual, anchors, marketMultiple: multiple });

    const goal = args.goal ?? null;
    if (goal !== null && goal.reachableWithoutReturn) {
      return new FeasibilityVerdict({
        level: FeasibilityLevel.riskFreeSufficient,
        reason: FeasibilityReason.contributionsAlreadySuffice,
        requiredAnnualRate: annual,
        anchors,
      });
    }

    if (annual < anchors.riskFreeCagr) {
      return verdict(FeasibilityLevel.riskFreeSufficient, FeasibilityReason.belowRiskFree);
    }
    if (annual <= anchors.marketCagr) {
      return verdict(FeasibilityLevel.plausible, FeasibilityReason.withinMarket);
    }
    if (annual <= anchors.marketCagr * GoalFeasibility.warningMultiple) {
      return verdict(FeasibilityLevel.demanding, FeasibilityReason.aboveMarket);
    }
    if (annual <= anchors.marketCagr * GoalFeasibility.blockingMultiple) {
      return verdict(FeasibilityLevel.demanding, FeasibilityReason.farAboveMarket);
    }
    return verdict(FeasibilityLevel.unrealistic, FeasibilityReason.beyondAnyReference);
  },

  /**
   * Veredito para o plano que `RequiredReturnSolver` recusou. A taxa sai
   * **nula** — não há taxa.
   */
  unsolvable(args: { anchors: MarketAnchors }): FeasibilityVerdict {
    return new FeasibilityVerdict({
      level: FeasibilityLevel.unrealistic,
      reason: FeasibilityReason.unsolvable,
      requiredAnnualRate: null,
      anchors: args.anchors,
    });
  },
};
