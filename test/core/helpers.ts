/**
 * Auxiliares da suíte do núcleo: os casamentos do `package:test` do Dart que
 * o Vitest não traz prontos — `closeTo` com tolerância absoluta e igualdade
 * de data pelo instante.
 */

import { expect } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  type CalculationTrace,
  DateTime,
  ValuationCascade,
  type ValuationInputs,
  type ValuationResult,
} from '../../src/core';

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

/** Avaliação com o coletor de auditoria ligado: o resultado e o único evento emitido. */
export function evaluateAudited(
  inputs: ValuationInputs,
  options: Parameters<typeof ValuationCascade.evaluate>[1] = {},
): { r: ValuationResult; ev: AuditEvent } {
  const events: AuditEvent[] = [];
  AuditRecorder.attach((e) => events.push(e));
  try {
    const r = ValuationCascade.evaluate(inputs, options);
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    expect(events).toHaveLength(1);
    return { r: r.unwrap(), ev: events[0]! };
  } finally {
    AuditRecorder.detach();
  }
}

/** O único passo do rastro cujo nome começa por [prefix] — o `singleWhere` do Dart. */
export function traceStep(ev: AuditEvent, prefix: string): CalculationTrace {
  const found = ev.calculations.filter((c) => c.formulaName.startsWith(prefix));
  expect(found, `passo «${prefix}» no rastro`).toHaveLength(1);
  return found[0]!;
}
