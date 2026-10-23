/** Encolhimento do beta por precisão, e a relação de Hamada que o desalavanca. */

import type { JsonMap } from '../../audit/calculation-trace';
import { DateTime } from '../../lang/date-time';
import { clamp, toInt } from '../../lang/num';

/** Número de um campo do JSON, como o `(x as num?)?.toDouble()` do Dart. */
function asNum(value: unknown): number | null {
  return typeof value === 'number' ? value : null;
}

/** Interpolação `'$x'` do Dart para um valor de JSON. */
function interpolate(value: unknown): string {
  return value === null || value === undefined ? 'null' : String(value);
}

/**
 * Prior transversal do beta, resolvido fora do núcleo.
 *
 * **Por que vem de fora.** A cascata avalia **um** ativo por vez e é pura: ela
 * não enxerga a seção transversal. A mediana setorial e a dispersão do
 * universo só existem depois de varrer o universo, e por isso chegam como
 * insumo — o mesmo arranjo que `MarketAnchors` já usa para as âncoras macro.
 */
export class BetaPrior {
  /** Beta **desalavancado** mediano por chave de setor. */
  readonly unleveredBySector: ReadonlyMap<string, number>;

  /** Beta desalavancado mediano do universo, para ativo sem setor utilizável. */
  readonly unleveredUniverse: number;

  /**
   * Dispersão robusta dos betas **alavancados** do universo — a variância do
   * prior no encolhimento. Medida em 0,53 sobre os 363 papéis em 10/09/2026.
   */
  readonly dispersion: number;

  constructor(args: {
    unleveredBySector: ReadonlyMap<string, number>;
    unleveredUniverse: number;
    dispersion: number;
  }) {
    this.unleveredBySector = args.unleveredBySector;
    this.unleveredUniverse = args.unleveredUniverse;
    this.dispersion = args.dispersion;
  }

  /** Beta desalavancado do setor, com recuo para o do universo. */
  unleveredFor(sectorKey: string | null | undefined): number {
    const k = sectorKey?.trim();
    if (k === undefined || k.length === 0) return this.unleveredUniverse;
    return this.unleveredBySector.get(k) ?? this.unleveredUniverse;
  }
}

/**
 * O prior empacotado para o aplicativo (item B11).
 *
 * **Por que empacotado, e não resolvido em tempo de execução.** Resolver o
 * prior é varrer o universo inteiro para avaliar **um** ativo. **O prior é
 * lento, e é isso que torna o pacote honesto**: um dia a mais ou a menos não o
 * move. O pacote traz [generatedAt] para que uma defasagem grande demais seja
 * recusada em vez de passar em silêncio (decisão 86).
 */
export class BetaPriorPackage {
  readonly prior: BetaPrior;
  readonly generatedAt: DateTime;
  readonly observations: number;

  constructor(args: { prior: BetaPrior; generatedAt: DateTime; observations: number }) {
    this.prior = args.prior;
    this.generatedAt = args.generatedAt;
    this.observations = args.observations;
  }
}

/** Serialização do prior do beta. */
export const BetaPriorCodec = {
  /** Versão do formato. */
  version: 1,

  /** Grava o pacote. */
  encode(prior: BetaPrior, args: { generatedAt: DateTime; observations: number }): JsonMap {
    return {
      versao: BetaPriorCodec.version,
      geradoEm: args.generatedAt.toIso8601String().substring(0, 10),
      observacoes: args.observations,
      universo: prior.unleveredUniverse,
      dispersao: prior.dispersion,
      setores: Object.fromEntries(prior.unleveredBySector),
    };
  },

  /**
   * Lê o pacote, ou devolve `null` quando ele não é utilizável. Recusa em vez
   * de adivinhar: versão diferente, mediana do universo ausente ou não
   * positiva, e dispersão não positiva devolvem `null`.
   */
  decode(pkg: JsonMap): BetaPriorPackage | null {
    if (pkg['versao'] !== BetaPriorCodec.version) return null;
    const universe = asNum(pkg['universo']);
    const dispersion = asNum(pkg['dispersao']);
    const date = DateTime.tryParse(interpolate(pkg['geradoEm']));
    if (universe === null || !Number.isFinite(universe) || universe <= 0) return null;
    if (dispersion === null || !Number.isFinite(dispersion) || dispersion <= 0) return null;
    if (date === null) return null;
    const sectors = new Map<string, number>();
    const raw = pkg['setores'];
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      for (const [k, value] of Object.entries(raw as JsonMap)) {
        const v = asNum(value);
        if (v !== null && Number.isFinite(v) && v > 0) sectors.set(k, v);
      }
    }
    const obs = asNum(pkg['observacoes']);
    return new BetaPriorPackage({
      prior: new BetaPrior({ unleveredBySector: sectors, unleveredUniverse: universe, dispersion }),
      generatedAt: date,
      observations: obs !== null ? toInt(obs) : 0,
    });
  },
};

/** Beta resultante do encolhimento, com o peso que o produziu. */
export class ShrunkBeta {
  /** Beta a usar no CAPM. */
  readonly beta: number;

  /** Peso do estimador individual em `[0, 1]`. `1` significa que a regressão decidiu sozinha. */
  readonly weight: number;

  /** Beta desalavancado do próprio ativo, por Hamada. É o que liga `Ke` a `WACC`. */
  readonly unlevered: number | null;

  constructor(args: { beta: number; weight: number; unlevered: number | null }) {
    this.beta = args.beta;
    this.weight = args.weight;
    this.unlevered = args.unlevered;
  }
}

/**
 * Desalavancagem e encolhimento do beta.
 *
 * **O que a medição de 10/09/2026 estabeleceu.** Substituir a regressão
 * individual pela mediana setorial realavancada **não se justifica**: o
 * erro-padrão individual fica em 0,07 na mediana, o setor reduz a dispersão em
 * só 13,1%, 95 dos 363 não têm setor com pares suficientes, e a troca moveria o
 * `Ke` do ativo mediano em 2,13 p.p. sem ganho medido.
 *
 * O que sobra é **encolher por precisão**:
 *
 * ```
 * w = (1/SE²) / (1/SE² + 1/σ_prior²)
 * β = w · β_regressão + (1 − w) · β_prior
 * ```
 *
 * Nenhum limiar decide — a precisão decide, e é contínua. Peso mediano de
 * **0,98**; onde ele age é onde precisa (AZUL3, erro-padrão de 83.228).
 */
export const BetaShrinkage = {
  /**
   * Teto da relação `D/E` usada em Hamada.
   *
   * **Existe porque a relação é linear e a realidade não.** `D/E` tem mediana
   * de 0,28 e p75 de 1,96 — mas chega a **94,5** na AZUL3. Em 3,0 a dívida
   * responde por 75% do capital.
   */
  maxDebtToEquity: 3.0,

  /** `β_U = β_L / (1 + (1 − t)·D/E)` — Hamada. Devolve `null` com entrada não finita. */
  unlever(args: { leveredBeta: number; debtToEquity: number; taxRate: number }): number | null {
    if (!Number.isFinite(args.leveredBeta) || !Number.isFinite(args.debtToEquity)) return null;
    const f = BetaShrinkage.leverageFactor({ debtToEquity: args.debtToEquity, taxRate: args.taxRate });
    if (f === null || f <= 0) return null;
    const v = args.leveredBeta / f;
    return Number.isFinite(v) ? v : null;
  },

  /** `1 + (1 − t)·D/E`, com `D/E` confinado. `null` com entrada não finita. */
  leverageFactor(args: { debtToEquity: number; taxRate: number }): number | null {
    if (!Number.isFinite(args.debtToEquity) || !Number.isFinite(args.taxRate)) return null;
    const clampedDebtToEquity = clamp(args.debtToEquity, 0.0, BetaShrinkage.maxDebtToEquity);
    const f = 1 + (1 - args.taxRate) * clampedDebtToEquity;
    return Number.isFinite(f) ? f : null;
  },

  /**
   * Encolhe [leveredBeta] em direção ao prior, pela precisão de cada um.
   *
   * [standardError] nulo ou não positivo entrega o prior inteiro. Sem prior
   * utilizável devolve o próprio [leveredBeta] com peso 1.
   */
  shrink(args: {
    leveredBeta: number;
    standardError: number | null;
    prior: BetaPrior;
    sectorKey: string | null;
    debtToEquity: number;
    taxRate: number;
  }): ShrunkBeta {
    const { leveredBeta, standardError, prior } = args;
    const factor = BetaShrinkage.leverageFactor({ debtToEquity: args.debtToEquity, taxRate: args.taxRate });
    const leveredPrior = factor === null ? leveredBeta : prior.unleveredFor(args.sectorKey) * factor;

    // **O desalavancado sai do beta que sai daqui, e não do cru** (decisão
    // 54). Encolher em espaço alavancado e desalavancar o resultado é
    // idêntico a encolher em espaço desalavancado, porque o fator é o mesmo
    // nos dois lados.
    const unlever = (b: number): number | null =>
      factor !== null && factor > 0 && Number.isFinite(b) ? b / factor : null;

    const result = (beta: number, weight: number): ShrunkBeta =>
      new ShrunkBeta({ beta, weight, unlevered: unlever(beta) });

    if (!Number.isFinite(leveredPrior) || prior.dispersion <= 0) {
      return result(leveredBeta, 1.0);
    }

    if (standardError === null || !Number.isFinite(standardError) || standardError <= 0) {
      return result(leveredPrior, 0.0);
    }

    const individualPrecision = 1 / (standardError * standardError);
    const priorPrecision = 1 / (prior.dispersion * prior.dispersion);
    const sum = individualPrecision + priorPrecision;
    if (!Number.isFinite(sum) || sum <= 0) return result(leveredBeta, 1.0);

    const w = clamp(individualPrecision / sum, 0.0, 1.0);
    const shrunk = w * leveredBeta + (1 - w) * leveredPrior;

    return Number.isFinite(shrunk) ? result(shrunk, w) : result(leveredPrior, w);
  },
};
