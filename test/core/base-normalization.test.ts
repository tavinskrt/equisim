// Por que o lucro de partida foi normalizado, e em que direção (pedido do
// orientador, 14/10/2026).
//
// O registro `BaseNormalization` explica a Saída 1 da Porta 2 com os valores
// que a cascata usou. Estes testes travam duas coisas: que ele concorda com o
// fator que entrou no preço justo, e que a direção dita é a que aconteceu.
import { describe, expect, it } from 'vitest';

import {
  AuditRecorder,
  BaseNormalization,
  BaseNormalizationOutcome,
  type CalculationTrace,
  CapmInputs,
  FundamentalsSnapshot,
  Ticker,
  ValuationCascade,
  ValuationCaveat,
  ValuationInputs,
  ValuationLane,
  type ValuationResult,
} from '../../src/core';
import { day, expectClose } from './helpers';

const ticker = Ticker.parse('ABCD3');

/**
 * Companhia operacional de retorno estável, com o último exercício
 * multiplicado por [shock] no resultado operacional.
 */
function series(shock = 1.0): FundamentalsSnapshot[] {
  const out: FundamentalsSnapshot[] = [];
  let e = 1.0;
  for (let i = 12; i >= 0; i--) {
    const y = 2025 - i;
    // Os anos do ciclo oscilam 6% para cada lado, como resultado operacional
    // de verdade: sem dispersão, qualquer desvio do último ano seria raro, e o
    // teste mediria a guarda da tendência no lugar da normalização.
    const k = i === 0 ? shock : i % 2 === 0 ? 1.06 : 0.94;
    out.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(y, 12, 31),
        totalRevenue: 10000 * e,
        ebit: 1800 * e * k,
        // EBITDA e lucro líquido estáveis: a trava de saúde mede a queda deles,
        // e o teste é da normalização, e não da trava.
        ebitda: 2400 * e,
        netIncome: 900 * e,
        incomeBeforeTax: 1300 * e,
        incomeTaxExpense: -400 * e,
        interestExpense: 400,
        earningsPerShare: 0.9 * e,
        cash: 200,
        shortTermDebt: 1000,
        longTermDebt: 3000,
        totalStockholderEquity: 6000 * e,
        bookValuePerShare: 6.0 * e,
        operatingCashFlow: 2000 * e,
        nopat: 1188 * e * k,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 12000,
      }),
    );
    e *= i % 2 === 0 ? 1.04 : 1.06;
  }
  return out;
}

function evaluate(shock = 1.0): { r: ValuationResult; step: CalculationTrace } {
  let step: CalculationTrace | null = null;
  AuditRecorder.attach((event) => {
    step = event.calculations.find((c) => c.formulaName.startsWith('Base do fluxo')) ?? null;
  });
  try {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(shock),
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.1,
      }),
    );
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    expect(step).not.toBeNull();
    return { r: r.unwrap(), step: step! };
  } finally {
    AuditRecorder.detach();
  }
}

function median(v: readonly number[]): number {
  const s = [...v].sort((a, b) => a - b);
  const m = Math.trunc(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

describe('o resultado, pela ordem em que a cascata decide', () => {
  const n = (
    o: {
      current?: number | null;
      cycle?: number | null;
      deviates?: boolean;
      trend?: boolean;
      cyclical?: boolean;
      health?: boolean;
      factor?: number;
      rebuilt?: boolean;
      imposed?: boolean;
    } = {},
  ): BaseNormalization =>
    new BaseNormalization({
      lane: ValuationLane.firm,
      latestReturn: 'current' in o ? o.current : 0.1,
      cycleReturn: 'cycle' in o ? o.cycle : 0.14,
      deviates: o.deviates ?? true,
      trendDominates: o.trend ?? false,
      cyclicalPrecedence: o.cyclical ?? false,
      healthCapped: o.health ?? false,
      factor: o.factor ?? 1.4,
      rebuilt: o.rebuilt ?? false,
      imposed: o.imposed ?? false,
    });

  it('abaixo do típico e destoando, sobe', () => {
    expect(n().outcome).toBe(BaseNormalizationOutcome.upward);
  });

  it('acima do típico e destoando, desce', () => {
    expect(n({ current: 0.2, factor: 0.7 }).outcome).toBe(BaseNormalizationOutcome.downward);
  });

  it('sem destoar, fica no publicado — mesmo com tendência', () => {
    expect(n({ deviates: false, factor: 1, trend: true }).outcome).toBe(BaseNormalizationOutcome.withinNormal);
  });

  it('destoando com tendência, fica no publicado; em commodity, não', () => {
    expect(n({ trend: true, factor: 1 }).outcome).toBe(BaseNormalizationOutcome.trend);
    expect(n({ trend: true, cyclical: true }).outcome).toBe(BaseNormalizationOutcome.upward);
  });

  it('a trava de saúde segura a subida', () => {
    expect(n({ health: true, factor: 1 }).outcome).toBe(BaseNormalizationOutcome.healthLocked);
  });

  it('prejuízo reconstruído, e sem ciclo positivo', () => {
    expect(n({ current: -0.05, rebuilt: true, factor: 1 }).outcome).toBe(BaseNormalizationOutcome.rebuilt);
    expect(n({ cycle: null, factor: 1 }).outcome).toBe(BaseNormalizationOutcome.noCycle);
    expect(n({ cycle: -0.02, factor: 1 }).outcome).toBe(BaseNormalizationOutcome.noCycle);
  });

  it('o fator imposto vem antes de tudo', () => {
    expect(n({ imposed: true }).outcome).toBe(BaseNormalizationOutcome.imposed);
  });
});

describe('pela cascata: o registro concorda com o preço justo', () => {
  const cases: [string, number, BaseNormalizationOutcome][] = [
    ['último ano deprimido', 0.6, BaseNormalizationOutcome.upward],
    ['último ano de pico', 1.6, BaseNormalizationOutcome.downward],
    ['último ano normal', 1.0, BaseNormalizationOutcome.withinNormal],
  ];
  for (const [name, shock, expected] of cases) {
    it(name, () => {
      const { r, step } = evaluate(shock);
      const n = r.diagnostics!.baseNormalization!;
      expect(n.outcome).toBe(expected);
      // O fator explicado é o fator que entrou no preço.
      expect(n.factor).toBe(r.diagnostics!.baseFactor);
      // O típico é a mediana dos oito anteriores ao último.
      expect(n.cycleWindow).toHaveLength(8);
      expect(n.latestYear).toBe(2025);
      expect(n.cycleWindow[n.cycleWindow.length - 1]!.year).toBe(2024);
      expectClose(n.cycleReturn!, median(n.cycleWindow.map((p) => p.value)), 1e-12);
      expectClose(n.ratio!, n.latestReturn! / n.cycleReturn!, 1e-12);
      // O lucro de partida é o publicado vezes o fator.
      expectClose(n.baseProfit!, n.publishedProfit! * n.factor, 1e-6);
      // A direção dita é a que aconteceu.
      if (expected === BaseNormalizationOutcome.upward) {
        expect(n.factor).toBeGreaterThan(1);
        expect(n.latestReturn).toBeLessThan(n.cycleReturn!);
      } else if (expected === BaseNormalizationOutcome.downward) {
        expect(n.factor).toBeLessThan(1);
        expect(n.latestReturn).toBeGreaterThan(n.cycleReturn!);
      } else {
        expect(n.factor).toBe(1.0);
      }
      // O rastro explica com os mesmos números.
      expect(step.explanation.length).toBeGreaterThan(0);
      expect(step.explanation[0]!.startsWith('Por que normalizar')).toBe(true);
      expect(step.mappedVariables['resultado da normalização']).toBe(expected.key);
    });
  }

  it('o rastro diz a direção e a conta', () => {
    const above = evaluate(0.6).step.explanation;
    expect(above[1]!.startsWith('Para cima: em 2025')).toBe(true);
    expect(above.some((l) => l.startsWith('O teste de destoar'))).toBe(true);
    expect(above.some((l) => l.startsWith('A conta:'))).toBe(true);
    const low = evaluate(1.6).step.explanation;
    expect(low[1]!.startsWith('Para baixo: em 2025')).toBe(true);
    const normal = evaluate().step.explanation;
    expect(normal[1]!.startsWith('Sem normalização')).toBe(true);
    expect(normal[normal.length - 1]!.endsWith('Não destoou.')).toBe(true);
  });

  it('o aviso diz a direção', () => {
    const { r } = evaluate(0.6);
    expect(r.warnings.some((w) => w.includes('normalizada para cima'))).toBe(true);
    expect(
      r.warnings.some((w) => w.includes('ao longo da projeção')),
      'o fator vale já no ano zero; o que converge é o retorno',
    ).toBe(false);
  });

  it('prejuízo no último ano: a base é reconstruída do ciclo', () => {
    const { r, step } = evaluate(-0.2);
    const n = r.diagnostics!.baseNormalization!;
    expect(n.outcome).toBe(BaseNormalizationOutcome.rebuilt);
    expect(r.caveats).toContain(ValuationCaveat.rebuiltBase);
    expect(n.rebuiltPositiveShare).toBeGreaterThanOrEqual(0.6);
    expect(step.explanation[1]!.startsWith('Base reconstruída')).toBe(true);
  });
});
