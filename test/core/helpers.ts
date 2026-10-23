/**
 * Auxiliares da suíte do núcleo: os casamentos do `package:test` do Dart que
 * o Vitest não traz prontos — `closeTo` com tolerância absoluta e igualdade
 * de data pelo instante.
 */

import { expect } from 'vitest';

import { DateTime } from '../../src/core';

/** `DateTime(y, m, d)` do Dart: data local. */
export function day(year: number, month = 1, dayOfMonth = 1): DateTime {
  return DateTime.local(year, month, dayOfMonth);
}

/** `expect(actual, closeTo(expected, delta))`. */
export function expectClose(actual: number | null | undefined, expected: number, delta: number, reason?: string): void {
  const why = reason === undefined ? '' : ` (${reason})`;
  expect(actual, `valor ausente${why}`).not.toBeNull();
  expect(actual, `valor ausente${why}`).not.toBeUndefined();
  const ok = Math.abs((actual as number) - expected) <= delta;
  expect(ok, `esperado ${expected} ± ${delta}, obtido ${String(actual)}${why}`).toBe(true);
}

/** Igualdade de [DateTime] pelo instante e pelo fuso, como o `==` do Dart. */
export function expectDate(actual: DateTime | null | undefined, expected: DateTime, reason?: string): void {
  expect(actual, reason).not.toBeNull();
  expect(actual?.toIso8601String(), reason).toBe(expected.toIso8601String());
}
