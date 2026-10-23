/**
 * Gerador pseudoaleatório com semente — o `Random(seed)` do Dart na web.
 *
 * **Por que reproduzir em vez de usar outro gerador.** O Monte Carlo da
 * avaliação sorteia com semente fixa (`ScenarioEngine`), e a mesma semente tem
 * de produzir os mesmos sorteios que o motor original produzia: é o que faz a
 * distribuição P5–P95 de uma avaliação ser reprodutível entre a versão Dart e
 * esta. O algoritmo é *multiply-with-carry* de base 2³² com a constante
 * `0xFFFFDA61` (Numerical Recipes, 3ª ed., p. 348), com a semente embaralhada
 * pela função de mistura de 64 bits de Thomas Wang.
 *
 * Transcrito de `sdk/lib/_internal/js_runtime/lib/math_patch.dart` (classe
 * `_Random`), do SDK do Dart 3.13. As operações de bit seguem a semântica do
 * Dart compilado para JavaScript: o resultado de `&`, `|`, `^`, `~` e `<<` é um
 * inteiro sem sinal de 32 bits — daí o `>>> 0` em cada uma.
 */

import { intDiv, RangeError } from './num';

const POW2_32 = 0x100000000;
const POW2_53_D = 0x20000000000000;
const POW2_27_D = 1 << 27;
const MASK32 = 0xffffffff;

const and = (a: number, b: number): number => (a & b) >>> 0;
const or = (a: number, b: number): number => (a | b) >>> 0;
const xor = (a: number, b: number): number => (a ^ b) >>> 0;
const not = (a: number): number => ~a >>> 0;
const shl = (a: number, b: number): number => (b > 31 ? 0 : (a << b) >>> 0);
const shr = (a: number, b: number): number =>
  a > 0 ? (b > 31 ? 0 : a >>> b) : (a >> (b > 31 ? 31 : b)) >>> 0;

/** Contrato de um gerador: o mesmo do `Random` do Dart. */
export interface RandomSource {
  nextInt(max: number): number;
  nextDouble(): number;
  nextBool(): boolean;
}

/** `Random(seed)` do Dart na web. */
export class SeededRandom implements RandomSource {
  private lo = 0;
  private hi = 0;

  constructor(seed: number) {
    let s = seed;
    let emptySeed = 0;
    if (s < 0) emptySeed = -1;
    do {
      let low = and(s, MASK32);
      s = intDiv(s - low, POW2_32);
      let high = and(s, MASK32);
      s = intDiv(s - high, POW2_32);

      // key = ~key + (key << 21);
      let tmplow = shl(low, 21);
      let tmphigh = or(shl(high, 21), shr(low, 11));
      tmplow = and(not(low), MASK32) + tmplow;
      low = and(tmplow, MASK32);
      high = and(not(high) + tmphigh + intDiv(tmplow - low, 0x100000000), MASK32);
      // key = key ^ (key >> 24).
      tmphigh = shr(high, 24);
      tmplow = or(shr(low, 24), shl(high, 8));
      low = xor(low, tmplow);
      high = xor(high, tmphigh);
      // key = key * 265
      tmplow = low * 265;
      low = and(tmplow, MASK32);
      high = and(high * 265 + intDiv(tmplow - low, 0x100000000), MASK32);
      // key = key ^ (key >> 14);
      tmphigh = shr(high, 14);
      tmplow = or(shr(low, 14), shl(high, 18));
      low = xor(low, tmplow);
      high = xor(high, tmphigh);
      // key = key * 21
      tmplow = low * 21;
      low = and(tmplow, MASK32);
      high = and(high * 21 + intDiv(tmplow - low, 0x100000000), MASK32);
      // key = key ^ (key >> 28).
      tmphigh = shr(high, 28);
      tmplow = or(shr(low, 28), shl(high, 4));
      low = xor(low, tmplow);
      high = xor(high, tmphigh);
      // key = key + (key << 31);
      tmplow = shl(low, 31);
      tmphigh = or(shl(high, 31), shr(low, 1));
      tmplow += low;
      low = and(tmplow, MASK32);
      high = and(high + tmphigh + intDiv(tmplow - low, 0x100000000), MASK32);
      // Fim da mistura.

      // seed = seed * 1037 ^ key;
      tmplow = this.lo * 1037;
      this.lo = and(tmplow, MASK32);
      this.hi = and(this.hi * 1037 + intDiv(tmplow - this.lo, 0x100000000), MASK32);
      this.lo = xor(this.lo, low);
      this.hi = xor(this.hi, high);
    } while (s !== emptySeed);

    if (this.hi === 0 && this.lo === 0) {
      this.lo = 0x5a17;
    }
    this.nextState();
    this.nextState();
    this.nextState();
    this.nextState();
  }

  // var state = (A * _lo + _hi) & _MASK_64; _lo = state & _MASK_32; _hi = state >> 32;
  private nextState(): void {
    // Simula (0xFFFFDA61 * lo + hi) sem passar de 53 bits.
    const tmpHi = 0xffff0000 * this.lo;
    const tmpHiLo = and(tmpHi, MASK32);
    const tmpHiHi = tmpHi - tmpHiLo;
    const tmpLo = 0xda61 * this.lo;
    const tmpLoLo = and(tmpLo, MASK32);
    const tmpLoHi = tmpLo - tmpLoLo;

    const newLo = tmpLoLo + tmpHiLo + this.hi;
    this.lo = and(newLo, MASK32);
    const newLoHi = newLo - this.lo;
    this.hi = and(intDiv(tmpLoHi + tmpHiHi + newLoHi, POW2_32), MASK32);
  }

  nextInt(max: number): number {
    if (max <= 0 || max > POW2_32) {
      throw new RangeError(`max must be in range 0 < max ≤ 2^32, was ${max}`);
    }
    if (and(max, max - 1) === 0) {
      this.nextState();
      return and(this.lo, max - 1);
    }
    let rnd32: number;
    let result: number;
    do {
      this.nextState();
      rnd32 = this.lo;
      result = rnd32 % max;
    } while (rnd32 - result + max >= POW2_32);
    return result;
  }

  nextDouble(): number {
    this.nextState();
    const bits26 = and(this.lo, (1 << 26) - 1);
    this.nextState();
    const bits27 = and(this.lo, (1 << 27) - 1);
    return (bits26 * POW2_27_D + bits27) / POW2_53_D;
  }

  nextBool(): boolean {
    this.nextState();
    return and(this.lo, 1) === 0;
  }
}

/** `Random()` sem semente do Dart na web: o `Math.random` do navegador. */
export const unseededRandom: RandomSource = {
  nextInt(max: number): number {
    if (max <= 0 || max > POW2_32) {
      throw new RangeError(`max must be in range 0 < max ≤ 2^32, was ${max}`);
    }
    return (Math.random() * max) >>> 0;
  },
  nextDouble: () => Math.random(),
  nextBool: () => Math.random() < 0.5,
};
