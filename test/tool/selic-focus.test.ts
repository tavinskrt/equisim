// A trajetória do Focus que `tool/selic-focus.ts` mede contra a curva
// (item B33): a Selic média de cada ano, e a curva que a reproduz.
import { describe, expect, it } from 'vitest';

import { DateTime } from '../../src/core';
import { focusForwards, forwardsCurve } from '../../tool/selic-focus';
import { expectClose } from '../core/helpers';

describe('Focus da Selic', () => {
  const today = DateTime.local(2026, 9, 14);

  it('Focus plano na taxa corrente dá a mesma taxa em todo ano', () => {
    const fw = focusForwards(
      today,
      0.12,
      new Map([
        [2026, 0.12],
        [2027, 0.12],
        [2028, 0.12],
      ]),
      10,
    );
    expect(fw).toHaveLength(10);
    for (const f of fw) expectClose(f, 0.12, 1e-9);
  });

  it('a taxa do ano fica entre a corrente e a do fim do ano, e depois do último ano segue a última expectativa', () => {
    const fw = focusForwards(
      today,
      0.14,
      new Map([
        [2026, 0.1375],
        [2027, 0.12],
        [2028, 0.105],
        [2029, 0.1],
        [2030, 0.1],
      ]),
      10,
    );
    // O primeiro ano atravessa a queda de 13,75% a 12%.
    expect(fw[0]).toBeLessThan(0.14);
    expect(fw[0]).toBeGreaterThan(0.12);
    // A trajetória só cai, e termina plana em 10%.
    for (let k = 1; k < fw.length; k++) expect(fw[k]).toBeLessThanOrEqual(fw[k - 1]! + 1e-12);
    expectClose(fw[fw.length - 1], 0.1, 1e-9);
  });

  it('a curva devolve os forwards de que foi montada, e a perpetuidade é o último', () => {
    const fw = [0.13, 0.12, 0.11, 0.105, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1];
    const curve = forwardsCurve(today, fw);
    const read = curve.annualForwards(10);
    for (let k = 0; k < 10; k++) expectClose(read[k], fw[k]!, 1e-9, `ano ${k + 1}`);
    expectClose(curve.terminalRate(10), 0.1, 1e-9);
  });
});
