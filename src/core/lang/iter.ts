/**
 * Atalhos de coleção que o Dart tinha no `Iterable` e o `Array` não tem.
 *
 * Cada um reproduz a ordem de avaliação do original — `fold` da esquerda para a
 * direita, `reduce` lançando em coleção vazia —, porque a soma de `double` não
 * é associativa e a ordem muda o último bit.
 */

import { compareNum, StateError } from './num';

/** `fold` do Dart: acumula da esquerda para a direita. */
export function fold<T, R>(items: Iterable<T>, initial: R, combine: (acc: R, item: T) => R): R {
  let acc = initial;
  for (const item of items) acc = combine(acc, item);
  return acc;
}

/** Soma da esquerda para a direita, começando de `0.0` — o `fold(0.0, (a, b) => a + b)`. */
export function sum(items: Iterable<number>): number {
  let acc = 0;
  for (const item of items) acc += item;
  return acc;
}

/** `reduce` do Dart: lança [StateError] em coleção vazia. */
export function reduce<T>(items: readonly T[], combine: (a: T, b: T) => T): T {
  if (items.length === 0) throw new StateError('No element');
  let acc = items[0] as T;
  for (let i = 1; i < items.length; i++) acc = combine(acc, items[i] as T);
  return acc;
}

/** `first` do Dart: lança [StateError] em coleção vazia. */
export function first<T>(items: readonly T[]): T {
  if (items.length === 0) throw new StateError('No element');
  return items[0]!;
}

/** `last` do Dart: lança [StateError] em coleção vazia. */
export function last<T>(items: readonly T[]): T {
  if (items.length === 0) throw new StateError('No element');
  return items[items.length - 1]!;
}

/** `firstOrNull` do Dart. */
export function firstOrNull<T>(items: readonly T[]): T | null {
  return items.length === 0 ? null : items[0]!;
}

/** `lastOrNull` do Dart. */
export function lastOrNull<T>(items: readonly T[]): T | null {
  return items.length === 0 ? null : items[items.length - 1]!;
}

/** `firstWhereOrNull` do pacote `collection`, ou `firstWhere(..., orElse: () => null)`. */
export function firstWhereOrNull<T>(items: Iterable<T>, test: (item: T) => boolean): T | null {
  for (const item of items) if (test(item)) return item;
  return null;
}

/** `lastWhereOrNull`. */
export function lastWhereOrNull<T>(items: readonly T[], test: (item: T) => boolean): T | null {
  for (let i = items.length - 1; i >= 0; i--) if (test(items[i]!)) return items[i]!;
  return null;
}

/** `List.generate` do Dart. */
export function generate<T>(length: number, make: (i: number) => T): T[] {
  const out: T[] = new Array<T>(length);
  for (let i = 0; i < length; i++) out[i] = make(i);
  return out;
}

/** `sublist(start, end)` do Dart: lança se a faixa estiver fora da lista. */
export function sublist<T>(items: readonly T[], start: number, end?: number): T[] {
  const e = end ?? items.length;
  if (start < 0 || start > items.length || e < start || e > items.length) {
    throw new RangeError(`sublist(${start}, ${e}) fora de 0..${items.length}`);
  }
  return items.slice(start, e);
}

/** Cópia ordenada, sem alterar a original — `[...items]..sort(compare)`. */
export function sorted<T>(items: Iterable<T>, compare: (a: T, b: T) => number): T[] {
  return [...items].sort(compare);
}

/**
 * Cópia ordenada de números — o `[...values]..sort()` do Dart sem comparador,
 * que ordena pelo `compareTo` (`-0.0` antes de `0.0`, `NaN` no fim).
 */
export function sortedNums(items: Iterable<number>): number[] {
  return [...items].sort(compareNum);
}
