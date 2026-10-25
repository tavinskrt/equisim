import { ArgumentError, clamp, compareNum, str, toStringAsFixed } from '../lang/num';
import type { Ticker } from './ticker';

/**
 * Peso de alocação normalizado no intervalo [0, 1].
 *
 * Diferente de [Money], este valor **é** ponto flutuante: peso não é saldo, e
 * a fração exata `1/3` não tem representação decimal. Por isso a igualdade é
 * tolerante ([Weight.tolerance]) em vez de exata, e a soma de um conjunto é
 * conferida por [Weights.sumsToOne], não por `== 1.0`.
 */
export class Weight {
  /** Fração alocada, em `[0, 1]`. `0.25` representa 25% da carteira. */
  readonly value: number;

  private constructor(value: number) {
    this.value = value;
  }

  /**
   * Tolerância para comparação de soma. Um conjunto de pesos vindo de divisão
   * (1/3 + 1/3 + 1/3) nunca soma exatamente 1,0 em ponto flutuante.
   */
  static readonly tolerance = 1e-9;

  /**
   * Constrói a partir de uma fração.
   *
   * Admite uma folga de [tolerance] nas duas bordas para aceitar resíduo de
   * divisão, e depois trava o valor em `[0, 1]`.
   *
   * Lança [ArgumentError] se [v] for `NaN` ou estiver fora de
   * `[-tolerance, 1 + tolerance]`.
   */
  static fraction(v: number): Weight {
    if (Number.isNaN(v) || v < -Weight.tolerance || v > 1 + Weight.tolerance) {
      throw new ArgumentError(`Peso fora de [0,1]: ${str(v)}`);
    }
    return new Weight(clamp(v, 0.0, 1.0));
  }

  /** Alocação nula. Usado como valor inicial antes de reequiponderar. */
  static readonly zero = new Weight(0.0);

  /** Percentual correspondente (`0.25` devolve `25.0`). */
  get percent(): number {
    return this.value * 100.0;
  }

  compareTo(other: Weight): number {
    return compareNum(this.value, other.value);
  }

  /**
   * Igualdade **tolerante**: dois pesos separados por menos de [tolerance] são
   * o mesmo peso.
   */
  equals(other: unknown): boolean {
    return other instanceof Weight && Math.abs(other.value - this.value) < Weight.tolerance;
  }

  toString(): string {
    return `${toStringAsFixed(this.percent, 2)}%`;
  }
}

/**
 * Operações sobre conjuntos de pesos, com tratamento explícito do resíduo
 * de ponto flutuante — a origem clássica de carteiras que somam 99,99%.
 */
export const Weights = {
  /**
   * Verifica se a soma equivale a 100% dentro de uma tolerância prática. A
   * tolerância aqui é maior que [Weight.tolerance] porque acomoda o erro
   * acumulado de somar até 15 parcelas.
   */
  sumsToOne(weights: Iterable<Weight>, epsilon = 1e-6): boolean {
    let total = 0.0;
    for (const w of weights) total = total + w.value;
    return Math.abs(total - 1.0) < epsilon;
  },

  /** Soma bruta das frações, sem normalizar nem conferir. */
  sum(weights: Iterable<Weight>): number {
    let total = 0.0;
    for (const w of weights) total = total + w.value;
    return total;
  },

  /**
   * Distribui 1,0 igualmente entre [tickers].
   *
   * O resíduo da divisão inexata é absorvido pelo primeiro elemento, de modo
   * que a soma resultante é exatamente 1,0. Duplicatas colapsam, porque o
   * resultado é indexado por [Ticker].
   */
  equal(tickers: readonly Ticker[]): Map<Ticker, Weight> {
    if (tickers.length === 0) return new Map();
    const share = 1.0 / tickers.length;
    const result = new Map<Ticker, Weight>();
    let accumulated = 0.0;
    for (let i = 1; i < tickers.length; i++) {
      result.set(tickers[i]!, Weight.fraction(share));
      accumulated += share;
    }
    result.set(tickers[0]!, Weight.fraction(1.0 - accumulated));
    return result;
  },
};
