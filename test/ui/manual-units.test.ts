import { describe, expect, it } from 'vitest';

import { ManualField } from '../../src/core';
import { Units } from '../../src/features/manual/units';

/** O que o editor manual lê do que a pessoa digita, em pt-BR. */
describe('Units.read', () => {
  it('lê o lucro em milhões, com vírgula decimal', () => {
    expect(Units.read('reais', '56.723,6')).toBeCloseTo(56_723.6e6, 0);
    expect(Units.read('reais', '12,5')).toBeCloseTo(12.5e6, 0);
    expect(Units.read('reais', 'R$ 1.250')).toBeCloseTo(1250e6, 0);
  });

  it('o ponto só separa milhar no lucro: numa taxa ele é decimal', () => {
    expect(Units.read('reais', '1.250')).toBeCloseTo(1250e6, 0);
    expect(Units.read('rate', '12.5')).toBeCloseTo(0.125, 10);
    expect(Units.read('rate', '12,5')).toBeCloseTo(0.125, 10);
    expect(Units.read('fraction', '35,0%')).toBeCloseTo(0.35, 10);
  });

  it('aceita o sinal tipográfico de menos', () => {
    expect(Units.read('rate', '−2,5')).toBeCloseTo(-0.025, 10);
  });

  it('campo vazio ou sem número é nulo, e não zero', () => {
    for (const text of ['', ' ', '-', 'abc', '1,2,3']) expect(Units.read('rate', text), JSON.stringify(text)).toBeNull();
  });

  it('o que se exibe volta igual pela leitura', () => {
    for (const [u, v] of [
      ['reais', 26_025.2e6],
      ['rate', 0.1065],
      ['fraction', 0.4],
    ] as const) {
      expect(Units.read(u, Units.display(u, v))).toBeCloseTo(v, u === 'reais' ? -4 : 6);
    }
  });
});

describe('Units.of', () => {
  it('o lucro de partida é em reais; a retenção, parcela; o resto, taxa', () => {
    expect(Units.of(ManualField.baseProfit)).toBe('reais');
    expect(Units.of(ManualField.retention)).toBe('fraction');
    expect(Units.of(ManualField.discountRate)).toBe('rate');
  });
});
