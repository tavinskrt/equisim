import { expect, it } from 'vitest';

import { CapmInputs, CurveVertex, Ticker, ValuationInputs, YieldCurve } from '../../src/core';
import { day, expectClose } from './helpers';

/** O deslocamento do nível da taxa livre de risco — o instrumento da varredura do item B10. */
const today = day(2026, 9, 14);
const flatCurve = YieldCurve.of(today, [new CurveVertex(1, 0.1), new CurveVertex(5, 0.1), new CurveVertex(10, 0.1)])!;

function inputs(a: { curve?: YieldCurve; terminal?: number } = {}): ValuationInputs {
  return new ValuationInputs({
    ticker: Ticker.parse('PETR4'),
    asOf: today,
    fundamentals: [],
    marketPrice: 30,
    capm: new CapmInputs({ riskFreeRate: 0.12, beta: 1.1, marketPremium: 0.055 }),
    riskFreeCurve: a.curve ?? null,
    declaredTerminalRiskFreeRate: a.terminal ?? null,
  });
}

it('desloca a corrente, a de equilíbrio declarada e a curva inteira', () => {
  const d = inputs({ curve: flatCurve, terminal: 0.09 }).withRiskFreeShift(0.02);
  expectClose(d.capm.riskFreeRate, 0.14, 1e-12);
  expectClose(d.declaredTerminalRiskFreeRate, 0.11, 1e-12);
  // Curva plana deslocada continua plana: todo forward sobe o deslocamento.
  for (const f of d.riskFreeCurve!.annualForwards(10)) expectClose(f, 0.12, 1e-12);
  // Com curva, a perpetuidade é o forward dela, e ele também se desloca.
  expectClose(d.terminalRiskFreeRate, 0.12, 1e-12);
  // O resto não muda.
  expect(d.capm.beta).toBe(1.1);
  expect(d.marketPrice).toBe(30);
});

it('sem curva, a perpetuidade é a declarada deslocada', () => {
  const d = inputs({ terminal: 0.09 }).withRiskFreeShift(-0.03);
  expect(d.riskFreeCurve).toBeNull();
  expectClose(d.terminalRiskFreeRate, 0.06, 1e-12);
  expectClose(d.capm.riskFreeRate, 0.09, 1e-12);
});

it('taxa que ficaria negativa para no piso de 0,1%', () => {
  const d = inputs({ curve: flatCurve, terminal: 0.09 }).withRiskFreeShift(-0.2);
  expectClose(d.capm.riskFreeRate, 0.001, 1e-12);
  expectClose(d.declaredTerminalRiskFreeRate, 0.001, 1e-12);
  expect(d.riskFreeCurve!.vertices.every((v) => Math.abs(v.rate - 0.001) < 1e-12)).toBe(true);
});
