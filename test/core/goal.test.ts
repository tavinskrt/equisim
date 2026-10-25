import { describe, expect, it } from 'vitest';

import {
  ComputationFailure,
  FeasibilityLevel,
  FeasibilityReason,
  type FeasibilityVerdict,
  FinancialGoal,
  GoalFeasibility,
  MarketAnchors,
  Money,
  RequiredReturn,
  RequiredReturnSolver,
} from '../../src/core';
import { expectClose } from './helpers';

const goal = (initial: number, monthly: number, months: number, target: number): FinancialGoal =>
  FinancialGoal.unvalidated({
    initialContribution: initial === 0 ? Money.zero : Money.fromReais(initial),
    monthlyContribution: monthly === 0 ? Money.zero : Money.fromReais(monthly),
    months,
    targetWealth: Money.fromReais(target),
  });

function monthlyFromAnnual(annual: number): number {
  let lo = -0.5;
  let hi = 1.0;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    const candidate = new RequiredReturn({ monthly: mid }).annual;
    if (candidate < annual) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}

describe('RequiredReturnSolver — sem aporte mensal (forma fechada conhecida)', () => {
  it('dobrar o capital em 12 meses exige 2^(1/12) − 1', () => {
    const result = RequiredReturnSolver.solve(goal(1000, 0, 12, 2000));
    expect(result.isOk).toBe(true);
    // 2^(1/12) − 1 = 0,059463094359295...
    expectClose(result.unwrap().monthly, 0.0594630943592953, 1e-9);
  });
});

describe('RequiredReturnSolver — com aporte mensal', () => {
  it('caso conferível: PMT 100, n 12, alvo 1268,25 → 1% ao mês', () => {
    // Valor futuro de série uniforme a 1% a.m.:
    // 100 × ((1,01¹² − 1)/0,01) = 1268,2503...
    // Equivale a TAXA(12; -100; 0; 1268,25) no Excel.
    const result = RequiredReturnSolver.solve(goal(0, 100, 12, 1268.25));
    expect(result.isOk).toBe(true);
    expectClose(result.unwrap().monthly, 0.01, 1e-5);
  });

  it('a forma fechada ingênua superestimaria grosseiramente a taxa', () => {
    // Erro que o solver evita: tratar (Vf/V0)^(1/n) − 1 como resposta.
    const result = RequiredReturnSolver.solve(goal(10000, 1000, 120, 300000));
    expect(result.isOk).toBe(true);
    const correct = result.unwrap().monthly;
    // A fórmula sem aportes exigiria (300000/10000)^(1/120) − 1 ≈ 2,87% a.m.
    const naive = 0.0287;
    expect(correct, 'ignorar os aportes infla a taxa exigida em várias vezes').toBeLessThan(naive / 2);
  });

  it('solução satisfaz a equação de valor futuro (ida e volta)', () => {
    const rate = RequiredReturnSolver.solve(goal(5000, 750, 84, 120000)).unwrap().monthly;
    const futureValue = RequiredReturnSolver.futureValue({ rate, initial: 5000, monthly: 750, months: 84 });
    expectClose(futureValue, 120000, 0.01);
  });

  it('taxa nula é tratada sem divisão por zero', () => {
    expectClose(RequiredReturnSolver.futureValue({ rate: 0.0, initial: 1000, monthly: 100, months: 12 }), 2200.0, 1e-9);
  });

  it('converte taxa mensal para anual', () => {
    expectClose(new RequiredReturn({ monthly: 0.01 }).annual, 0.12682503, 1e-7);
  });
});

describe('RequiredReturnSolver — casos-limite', () => {
  it('meta já coberta pelos próprios aportes', () => {
    const g = goal(1000, 1000, 12, 5000);
    expect(g.reachableWithoutReturn).toBe(true);
    const result = RequiredReturnSolver.solve(g);
    expect(result.isOk).toBe(true);
    expect(result.unwrap().monthly).toBeLessThanOrEqual(0.0);
  });

  it('meta impossível é reportada como falha, não como número absurdo', () => {
    const result = RequiredReturnSolver.solve(goal(1, 0, 12, 1000000000));
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(ComputationFailure);
  });

  it('rejeita plano sem capital algum', () => {
    expect(RequiredReturnSolver.solve(goal(0, 0, 12, 1000)).isErr).toBe(true);
  });

  it('rejeita prazo não positivo', () => {
    expect(RequiredReturnSolver.solve(goal(1000, 0, 0, 2000)).isErr).toBe(true);
  });
});

describe('GoalFeasibility — limiares ancorados em dados observados', () => {
  const anchors = MarketAnchors.fallback2026; // CDI 9,40% · IBOV 11,26%

  const verdictFor = (annualRate: number): FeasibilityVerdict =>
    GoalFeasibility.assess({ required: new RequiredReturn({ monthly: monthlyFromAnnual(annualRate) }), anchors });

  it('abaixo do CDI: avisa que a meta dispensa risco de mercado', () => {
    const verdict = verdictFor(0.06);
    expect(verdict.level).toBe(FeasibilityLevel.riskFreeSufficient);
    expect(verdict.level).not.toBe(FeasibilityLevel.unrealistic);
    // O motivo, e não a frase: o texto é composto na apresentação desde que
    // o núcleo parou de montar prosa (ver `FeasibilityCopy`).
    expect(verdict.reason).toBe(FeasibilityReason.belowRiskFree);
  });

  it('entre CDI e Ibovespa: plausível', () => {
    expect(verdictFor(0.105).level).toBe(FeasibilityLevel.plausible);
  });

  it('acima do Ibovespa: alerta sem bloquear', () => {
    const verdict = verdictFor(0.18);
    expect(verdict.level).toBe(FeasibilityLevel.demanding);
    expect(verdict.level).not.toBe(FeasibilityLevel.unrealistic);
  });

  it('acima de 2,5× o Ibovespa: bloqueia e cita o número', () => {
    const verdict = verdictFor(0.4);
    expect(verdict.level).toBe(FeasibilityLevel.unrealistic);
    expect(verdict.reason).toBe(FeasibilityReason.beyondAnyReference);
    // O múltiplo viaja apurado, para a tela citá-lo sem recalcular.
    expectClose(verdict.marketMultiple!, 0.4 / 0.1126, 1e-9);
  });

  it('aportes que já bastam dispensam rentabilidade', () => {
    const verdict = GoalFeasibility.assess({
      required: new RequiredReturn({ monthly: 0.0 }),
      anchors,
      goal: goal(1000, 1000, 12, 5000),
    });
    expect(verdict.level).toBe(FeasibilityLevel.riskFreeSufficient);
  });
});
