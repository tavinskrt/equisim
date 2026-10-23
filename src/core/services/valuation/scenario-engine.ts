/** Motor de cenários: três faixas nomeadas ou Monte Carlo, pela mesma avaliação. */

import { ScenarioBand, ScenarioMode, ValueDistribution } from '../../entities/valuation';
import { ComputationFailure } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { sortedNums } from '../../lang/iter';
import { SeededRandom, type RandomSource } from '../../lang/random';
import { DcfCalculator, type DcfAssumptions } from './dcf';

/**
 * Faixa triangular (mínimo, moda, máximo) para uma premissa: exige apenas os
 * três números que um analista sabe dizer, e não pressupõe simetria.
 */
export class TriangularRange {
  /** Piso da faixa. */
  readonly min: number;

  /** Valor mais provável. Deve ficar em `[min, max]`. */
  readonly mode: number;

  /** Teto da faixa. */
  readonly max: number;

  /**
   * Declara a faixa. **Não valida** `min ≤ mode ≤ max`: a violação produz
   * `NaN` em [sample], pela raiz de número negativo.
   */
  constructor(args: { min: number; mode: number; max: number }) {
    this.min = args.min;
    this.mode = args.mode;
    this.max = args.max;
  }

  /** `true` quando a faixa colapsou num único ponto e [sample] é constante. */
  get isDegenerate(): boolean {
    return this.min === this.max;
  }

  /**
   * Amostragem por transformada inversa — determinística dado o gerador.
   * Devolve [mode] sem consumir sorteio quando a faixa é degenerada.
   */
  sample(rng: RandomSource): number {
    if (this.isDegenerate) return this.mode;
    const u = rng.nextDouble();
    const span = this.max - this.min;
    const modeFraction = (this.mode - this.min) / span;
    if (u < modeFraction) {
      return this.min + Math.sqrt(u * span * (this.mode - this.min));
    }
    return this.max - Math.sqrt((1 - u) * span * (this.max - this.mode));
  }
}

/**
 * Fonte de premissas para o motor de cenários. Alternar entre cenários
 * nomeados e Monte Carlo é troca de configuração, não refatoração.
 */
export interface AssumptionSource {
  /** Como esta fonte gera cenários. */
  readonly mode: ScenarioMode;

  /** Premissas do cenário central, usadas como resultado principal. */
  readonly base: DcfAssumptions;

  /** Gera conjuntos de premissas a avaliar, com o gerador semeado. */
  draw(samples: number, rng: RandomSource): DcfAssumptions[];
}

/** Três conjuntos fixos de premissas — Pessimista, Base e Otimista. */
export class DiscreteScenarios implements AssumptionSource {
  /** Premissas por faixa. **Precisa conter [ScenarioBand.base].** */
  readonly scenarios: ReadonlyMap<ScenarioBand, DcfAssumptions>;

  constructor(scenarios: ReadonlyMap<ScenarioBand, DcfAssumptions>) {
    this.scenarios = scenarios;
  }

  /** Deslocamento padrão do crescimento do primeiro ano: 3 p.p. (decisão 148). */
  static readonly defaultGrowthDelta = 0.03;

  /** Deslocamento padrão das duas taxas de desconto: 2 p.p. */
  static readonly defaultDiscountDelta = 0.02;

  /**
   * As três faixas a partir de um cenário central. **O deslocamento alcança
   * as duas taxas de desconto**; no otimista a terminal é limitada por baixo a
   * `perpetualGrowth + minimumSpread`.
   */
  static around(
    center: DcfAssumptions,
    options: { growthDelta?: number; discountDelta?: number } = {},
  ): DiscreteScenarios {
    const growthDelta = options.growthDelta ?? DiscreteScenarios.defaultGrowthDelta;
    const discountDelta = options.discountDelta ?? DiscreteScenarios.defaultDiscountDelta;
    const scenarios = new Map<ScenarioBand, DcfAssumptions>();
    scenarios.set(
      ScenarioBand.bear,
      center.copyWith({
        growthRate: center.growthRate - growthDelta,
        discountRate: center.discountRate + discountDelta,
        terminalDiscountRate: center.terminalDiscountRate + discountDelta,
      }),
    );
    scenarios.set(ScenarioBand.base, center);
    scenarios.set(
      ScenarioBand.bull,
      center.copyWith({
        growthRate: center.growthRate + growthDelta,
        // A taxa corrente **não** participa do quociente da perpetuidade:
        // basta que continue positiva.
        discountRate: Math.max(center.discountRate - discountDelta, DcfCalculator.minimumSpread),
        terminalDiscountRate: Math.max(
          center.terminalDiscountRate - discountDelta,
          center.perpetualGrowth + DcfCalculator.minimumSpread,
        ),
      }),
    );
    return new DiscreteScenarios(scenarios);
  }

  get mode(): ScenarioMode {
    return ScenarioMode.discrete;
  }

  /** Premissas da faixa Base. Lança se ela faltar. */
  get base(): DcfAssumptions {
    const b = this.scenarios.get(ScenarioBand.base);
    if (b === undefined) throw new TypeError('Null check operator used on a null value');
    return b;
  }

  /** Os três cenários fixos, **ignorando [samples] e [rng]** — consumir o gerador quebraria a reprodutibilidade. */
  draw(_samples: number, _rng: RandomSource): DcfAssumptions[] {
    return [...this.scenarios.values()];
  }
}

/** Premissas sorteadas de distribuições declaradas. */
export class StochasticScenarios implements AssumptionSource {
  readonly base: DcfAssumptions;

  /** Faixa do crescimento explícito, em fração ao ano. */
  readonly growth: TriangularRange;

  /** Faixa da taxa de desconto, em fração ao ano. */
  readonly discount: TriangularRange;

  /** Faixa do crescimento na perpetuidade; cada sorteio é truncado em [draw]. */
  readonly perpetual: TriangularRange;

  constructor(args: {
    base: DcfAssumptions;
    growth: TriangularRange;
    discount: TriangularRange;
    perpetual: TriangularRange;
  }) {
    this.base = args.base;
    this.growth = args.growth;
    this.discount = args.discount;
    this.perpetual = args.perpetual;
  }

  /**
   * Faixas simétricas em torno do cenário central (padrões 4, 2 e 1 p.p.). O
   * piso da faixa perpétua é travado em zero.
   */
  static around(
    center: DcfAssumptions,
    options: { growthSpread?: number; discountSpread?: number; perpetualSpread?: number } = {},
  ): StochasticScenarios {
    const growthSpread = options.growthSpread ?? 0.04;
    const discountSpread = options.discountSpread ?? 0.02;
    const perpetualSpread = options.perpetualSpread ?? 0.01;
    return new StochasticScenarios({
      base: center,
      growth: new TriangularRange({
        min: center.growthRate - growthSpread,
        mode: center.growthRate,
        max: center.growthRate + growthSpread,
      }),
      discount: new TriangularRange({
        min: center.discountRate - discountSpread,
        mode: center.discountRate,
        max: center.discountRate + discountSpread,
      }),
      perpetual: new TriangularRange({
        min: Math.max(0.0, center.perpetualGrowth - perpetualSpread),
        mode: center.perpetualGrowth,
        max: center.perpetualGrowth + perpetualSpread,
      }),
    });
  }

  get mode(): ScenarioMode {
    return ScenarioMode.monteCarlo;
  }

  draw(samples: number, rng: RandomSource): DcfAssumptions[] {
    const out: DcfAssumptions[] = [];
    for (let i = 0; i < samples; i++) {
      const r = this.discount.sample(rng);
      // O sorteio desloca as duas taxas pelo mesmo tanto: o deslocamento é
      // paralelo.
      const shift = r - this.base.discountRate;
      const rInf = this.base.terminalDiscountRate + shift;
      const gp = this.perpetual.sample(rng);
      const growthRate = this.growth.sample(rng);
      out.push(
        this.base.copyWith({
          growthRate,
          discountRate: r,
          terminalDiscountRate: rInf,
          // Mantém a distância mínima contra a taxa **terminal**.
          perpetualGrowth: Math.min(gp, rInf - DcfCalculator.minimumSpread),
        }),
      );
    }
    return out;
  }
}

/** Resultado consolidado de uma rodada de cenários. */
export class ScenarioOutcome {
  /** Como os cenários foram gerados. */
  readonly mode: ScenarioMode;

  /** Valor por ação do cenário central. */
  readonly baseValue: number;

  /** Preenchido no modo discreto. */
  readonly discrete: ReadonlyMap<ScenarioBand, number> | null;

  /** Preenchido no modo Monte Carlo. */
  readonly distribution: ValueDistribution | null;

  /** Sorteios descartados por não produzirem valor válido. */
  readonly discarded: number;

  constructor(args: {
    mode: ScenarioMode;
    baseValue: number;
    discrete?: ReadonlyMap<ScenarioBand, number> | null;
    distribution?: ValueDistribution | null;
    discarded?: number;
  }) {
    this.mode = args.mode;
    this.baseValue = args.baseValue;
    this.discrete = args.discrete ?? null;
    this.distribution = args.distribution ?? null;
    this.discarded = args.discarded ?? 0;
  }
}

/** Executa uma avaliação sobre um conjunto de cenários e consolida o resultado. */
export const ScenarioEngine = {
  /**
   * Avalia todos os cenários da fonte. [seed] fixa o gerador: a mesma entrada
   * produz sempre o mesmo resultado. Propaga a falha do cenário central;
   * devolve [ComputationFailure] quando **nenhum** cenário produz valor.
   */
  run(args: {
    source: AssumptionSource;
    valuate: (a: DcfAssumptions) => Result<number>;
    samples?: number;
    seed?: number;
  }): Result<ScenarioOutcome> {
    const { source, valuate } = args;
    const samples = args.samples ?? 10000;
    const seed = args.seed ?? 42;
    const baseResult = valuate(source.base);
    if (baseResult.isErr) return err(baseResult.failureOrNull!);
    const baseValue = baseResult.unwrap();

    const rng = new SeededRandom(seed);

    if (source.mode === ScenarioMode.discrete) {
      if (!(source instanceof DiscreteScenarios)) {
        throw new TypeError('Fonte discreta que não é DiscreteScenarios.');
      }
      const results = new Map<ScenarioBand, number>();
      let discarded = 0;
      for (const [band, assumptions] of source.scenarios) {
        const r = valuate(assumptions);
        if (r.isOk) {
          results.set(band, r.unwrap());
        } else {
          discarded++;
        }
      }
      if (results.size === 0) {
        return err(new ComputationFailure('Nenhum cenário discreto produziu valor válido.'));
      }
      return ok(new ScenarioOutcome({ mode: ScenarioMode.discrete, baseValue, discrete: results, discarded }));
    }

    const values: number[] = [];
    let discarded = 0;
    for (const a of source.draw(samples, rng)) {
      const r = valuate(a);
      if (r.isOk) {
        const v = r.unwrap();
        if (Number.isFinite(v) && v > 0) {
          values.push(v);
        } else {
          discarded++;
        }
      } else {
        discarded++;
      }
    }

    if (values.length === 0) {
      return err(new ComputationFailure('Nenhum sorteio produziu valor válido: revise as faixas de premissas.'));
    }

    return ok(
      new ScenarioOutcome({
        mode: ScenarioMode.monteCarlo,
        baseValue,
        distribution: new ValueDistribution(sortedNums(values)),
        discarded,
      }),
    );
  },
};
