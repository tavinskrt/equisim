import { expect, it } from 'vitest';

import { MoatFixedPoint, ValuationParameters } from '../../src/core';

/**
 * A volta entre o veredito do moat e a taxa de equilíbrio (item D3).
 *
 * O veredito aqui é um `number | null` — o retorno terminal que ele concede — e
 * as taxas são a taxa terminal. As funções sintéticas reproduzem os três
 * desfechos que a cascata trata: estabiliza, alterna até o teto, e trava no
 * solucionador.
 */

// A "taxa" que cada retorno terminal produz: alta com moat, baixa sem.
const rateOf = (moat: number | null): number => (moat === null ? 0.1 : 0.12);
const identity = (v: number | null): number | null => v;

it('estabiliza quando o veredito refeito repete o anterior', () => {
  const r = MoatFixedPoint.iterate<number | null, number>({
    verdict: 0.15,
    moat: 0.15,
    rates: rateOf(0.15),
    reassess: () => 0.15,
    moatOf: identity,
    solve: rateOf,
  });
  expect(r.stable).toBe(true);
  expect(r.passes).toBe(1);
  expect(r.moat).toBe(0.15);
});

it('converge em alguns passes e devolve o par do último', () => {
  // O veredito sobe até 0,15 e para: 0,12 → 0,14 → 0,15 → 0,15. A escada
  // é indexada pelo passe, e não pelo valor: número não serve de chave
  // (regra R6).
  const ladder = [0.14, 0.15, 0.15];
  let pass = 0;
  const r = MoatFixedPoint.iterate<number | null, number>({
    verdict: 0.12,
    moat: 0.12,
    rates: rateOf(0.12),
    reassess: () => ladder[pass]!,
    moatOf: identity,
    solve: (m) => {
      pass++;
      return rateOf(m);
    },
  });
  expect(r.stable).toBe(true);
  expect(r.passes).toBe(3);
  expect(r.moat).toBe(0.15);
  expect(r.verdict).toBe(0.15);
});

it('alterna até o teto, e o par devolvido é consistente entre si', () => {
  // O ativo na fronteira: com a taxa do moat (0,12) o excedente some e o
  // veredito recusa; sem moat a taxa cai (0,10), o excedente volta e o
  // veredito concede. Para sempre.
  const r = MoatFixedPoint.iterate<number | null, number>({
    verdict: 0.15,
    moat: 0.15,
    rates: rateOf(0.15),
    reassess: (rate) => (rate > 0.11 ? null : 0.15),
    moatOf: identity,
    solve: rateOf,
    maxPasses: 5,
  });
  expect(r.stable).toBe(false);
  expect(r.solverFailed).toBe(false);
  expect(r.passes).toBe(5);
  // Consistência: a taxa devolvida é a do moat devolvido, e não a do passe
  // seguinte — que nunca foi adotado.
  expect(r.rates).toBe(rateOf(r.moat));
  expect(r.verdict).toBe(r.moat);
});

it('o teto padrão é o da cascata', () => {
  let calls = 0;
  const r = MoatFixedPoint.iterate<number | null, number>({
    verdict: 0.15,
    moat: 0.15,
    rates: rateOf(0.15),
    reassess: (rate) => {
      calls++;
      return rate > 0.11 ? null : 0.15;
    },
    moatOf: identity,
    solve: rateOf,
  });
  expect(r.passes).toBe(ValuationParameters.moatMaxPasses);
  expect(calls).toBe(ValuationParameters.moatMaxPasses - 1);
});

it('o solucionador que não fecha para a volta no último par válido', () => {
  const r = MoatFixedPoint.iterate<number | null, number>({
    verdict: 0.15,
    moat: 0.15,
    rates: rateOf(0.15),
    reassess: () => null,
    moatOf: identity,
    solve: () => null,
  });
  expect(r.solverFailed).toBe(true);
  expect(r.stable).toBe(false);
  expect(r.passes).toBe(1);
  // O veredito que pedia a taxa inexistente não foi adotado.
  expect(r.moat).toBe(0.15);
  expect(r.verdict).toBe(0.15);
  expect(r.rates).toBe(rateOf(0.15));
});

it('a imposição externa vale sobre o veredito refeito', () => {
  // `moatOf` é onde `terminalReturnOverride` entra: com ela, o veredito
  // pode mudar à vontade que o retorno terminal não muda.
  const r = MoatFixedPoint.iterate<number | null, number>({
    verdict: 0.15,
    moat: 0.2,
    rates: rateOf(0.2),
    reassess: (rate) => (rate > 0.11 ? null : 0.15),
    moatOf: () => 0.2,
    solve: rateOf,
  });
  expect(r.stable).toBe(true);
  expect(r.moat).toBe(0.2);
});
