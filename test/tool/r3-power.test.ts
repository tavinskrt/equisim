// O poder do teste do R3 (item C6): a simulação tem de estar calibrada antes de
// dizer qualquer coisa sobre o motor.
import { describe, expect, it } from 'vitest';

import { DateTime } from '../../src/core';
import { availableAt, minimumEffect, power } from '../../tool/r3-power';
import { Regression } from '../../tool/validation/regression';
import { expectDate } from '../core/helpers';

describe('poder do R3', () => {
  // A amostra do R3: 22 coortes trimestrais de 36 meses, 11 sobreposições.
  const k = 22;
  const overlap = 11;
  const critical = Regression.overlapCritical(k, overlap);

  it('sem efeito, o poder é o nível do critério', () => {
    // `t > 2` unilateral sob a normal é 2,28%; o Newey-West acima de 2 só pode
    // tirar, e 4.000 sorteios têm erro-padrão de 0,24 p.p.
    const level = power({ mu: 0, deviation: 1, k, overlap, critical });
    expect(level).toBeLessThan(Regression.r3Tail + 0.01);
    expect(level).toBeGreaterThan(0.005);
  });

  it('o poder cresce com o efeito e chega a quase 1', () => {
    const p = (mu: number): number => power({ mu, deviation: 1, k, overlap, critical });
    expect(p(0.5)).toBeGreaterThan(p(0));
    expect(p(1.5)).toBeGreaterThan(p(0.5));
    expect(p(6)).toBeGreaterThan(0.99);
  });

  it('o efeito mínimo detectável tem 80% de poder, e não mais que isso', () => {
    const mde = minimumEffect({ deviation: 1, k, overlap, critical });
    expect(power({ mu: mde, deviation: 1, k, overlap, critical })).toBeGreaterThanOrEqual(0.8);
    expect(power({ mu: mde * 0.9, deviation: 1, k, overlap, critical })).toBeLessThan(0.8);
  });

  it('a data de disponibilidade confere com a amostra que existe', () => {
    // A 22ª coorte é a de 30/06/2023, e o retorno de 36 meses dela fecha em
    // 30/06/2026 — o último que o backtest de 22/09/2026 tinha.
    expectDate(availableAt(22, 36), DateTime.utc(2026, 6, 30));
    expectDate(availableAt(1, 12), DateTime.utc(2019, 3, 31));
  });
});
