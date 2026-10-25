import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  CashTiming,
  CostOfCapital,
  DcfAssumptions,
  DcfCalculator,
  type DcfOutcome,
  DiscreteScenarios,
  InsufficientData,
  type Result,
  ScenarioBand,
  ScenarioEngine,
  ScenarioMode,
  StochasticScenarios,
  ValuationDiagnostics,
} from '../../src/core';
import { expectClose } from './helpers';

describe('CostOfCapital', () => {
  it('CAPM: Ke = Rf + β(Rm − Rf)', () => {
    const capm = new CapmInputs({ riskFreeRate: 0.094, beta: 1.2, marketPremium: 0.055 });
    expectClose(capm.costOfEquity, 0.094 + 1.2 * 0.055, 1e-12);
  });

  it('empresa sem dívida: WACC degenera para Ke', () => {
    const capm = new CapmInputs({ riskFreeRate: 0.09, beta: 1.0, marketPremium: 0.055 });
    const unlevered = new CostOfCapital({ capm, costOfDebt: 0.0, taxRate: 0.0, equityValue: 1.0, debtValue: 0.0 });
    expectClose(unlevered.wacc, capm.costOfEquity, 1e-12);
  });

  it('WACC fica abaixo do Ke quando há dívida com benefício fiscal', () => {
    const capm = new CapmInputs({ riskFreeRate: 0.09, beta: 1.0, marketPremium: 0.055 });
    const levered = new CostOfCapital({
      capm,
      costOfDebt: 0.11,
      taxRate: 0.34,
      equityValue: 600,
      debtValue: 400,
      interestCoverage: 9.0,
      netDebtToEbitda: -0.3,
    });
    // O custo da dívida aplicado é o sintético: Rf + 1,0 p.p. na faixa de
    // caixa líquido. Daí 0,6 × 0,145 + 0,4 × 0,10 × 0,66
    // = 0,087 + 0,0264 = 0,1134.
    expectClose(levered.effectiveCostOfDebt, 0.1, 1e-12);
    expectClose(levered.wacc, 0.1134, 1e-9);
    expect(levered.wacc).toBeLessThan(levered.costOfEquity);
  });
});

describe('O terminal neutro e o capital instalado', () => {
  // Item B12, decisão 107. O retorno terminal neutro fixa o retorno do
  // capital **novo** — é o que faz o crescimento sair da fórmula —, e não o
  // do capital que já existe. A mesma expressão reagrupada é
  // `VT = capital_N + EVA_(N+1)/r`, e a segunda parcela é perpétua.
  const assumptions = (o: { roic: number; g?: number; contract?: number | null }): DcfAssumptions =>
    new DcfAssumptions({
      projectionYears: 10,
      growthRate: o.g ?? 0.04,
      perpetualGrowth: o.g ?? 0.04,
      discountRate: 0.15,
      terminalDiscountRate: 0.15,
      returnOnCapital: o.roic,
      neutralTerminalReturn: true,
      contractYearsAfterHorizon: o.contract ?? null,
      cashTiming: CashTiming.endOfYear,
    });

  const firm = (o: { roic: number; contract?: number | null }): DcfOutcome =>
    DcfCalculator.firm({
      baseProfit: 1000,
      assumptions: assumptions(o),
      netDebt: 0,
      sharesOutstanding: 100,
    }).unwrap();

  it('o retorno implícito do instalado é o ROIC, e não o custo', () => {
    // O capital parte de `lucro_1/ROIC` e acumula a retenção; o retorno
    // médio caminha do ROIC observado em direção ao marginal, sem chegar.
    const low = firm({ roic: 0.08 });
    const high = firm({ roic: 0.25 });
    expect(low.impliedTerminalReturn!, 'quem rende abaixo do custo continua rendendo abaixo').toBeLessThan(0.15);
    expect(high.impliedTerminalReturn!).toBeGreaterThan(0.15);
    expect(low.impliedTerminalReturn!, 'o capital novo entra ao custo e puxa a média para cima').toBeGreaterThan(0.08);
  });

  it('o excedente é negativo quando o instalado rende abaixo do custo', () => {
    const low = firm({ roic: 0.08 });
    const high = firm({ roic: 0.25 });
    expect(low.discountedTerminalExcess!).toBeLessThan(0);
    expect(high.discountedTerminalExcess!).toBeGreaterThan(0);
  });

  it('tirar o excedente é o mesmo que cortar o contrato em zero ano', () => {
    // O ramo de contrato da decisão 88 faz `VT = capital_N + EVA·anuidade(M)`;
    // com `M = 0` sobra o capital. A decomposição tem de bater com ele **ao
    // centavo**, porque as duas contas são a mesma álgebra por caminhos
    // diferentes — é o que impede a parcela declarada de ser aproximação.
    for (const roic of [0.08, 0.15, 0.25]) {
      const neutral = firm({ roic });
      const noExcess = firm({ roic, contract: 0 });
      const excessPerShare = neutral.discountedTerminalExcess! / 100;
      expectClose(noExcess.fairValuePerShare, neutral.fairValuePerShare - excessPerShare, 1e-9, `ROIC ${roic}`);
    }
  });

  it('com o instalado rendendo o custo, o excedente é zero', () => {
    // O caso em que o rótulo "sem lucro econômico na perpetuidade" é
    // verdadeiro: o terminal vale exatamente o capital.
    const r = firm({ roic: 0.15 });
    expectClose(r.impliedTerminalReturn, 0.15, 1e-9);
    expectClose(r.discountedTerminalExcess, 0, 1e-9);
  });

  it('vantagem competitiva concedida não tem decomposição', () => {
    const withMoat = DcfCalculator.firm({
      baseProfit: 1000,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: 0.04,
        perpetualGrowth: 0.04,
        discountRate: 0.15,
        terminalDiscountRate: 0.15,
        returnOnCapital: 0.2,
        terminalReturnOnCapital: 0.18,
      }),
      netDebt: 0,
      sharesOutstanding: 100,
    }).unwrap();
    expect(withMoat.discountedTerminalExcess, 'ali o terminal é outro, e a álgebra não é esta').toBeNull();
  });
});

describe('DCF pela via da firma', () => {
  // Sem decaimento e sem freio, para que o valor confira com conta manual.
  const flat = new DcfAssumptions({
    projectionYears: 3,
    growthRate: 0.05,
    perpetualGrowth: 0.05,
    discountRate: 0.1,
    returnOnCapital: 0.0,
  });

  it('valor por papel confere com o cálculo manual', () => {
    const r = DcfCalculator.firm({ baseProfit: 100, assumptions: flat, netDebt: 0, sharesOutstanding: 10 });
    expect(r.isOk).toBe(true);
    const o = r.unwrap();

    // Fluxos: 105, 110,25, 115,7625.
    expectClose(o.projectedFlows[0], 105.0, 1e-9);
    expectClose(o.projectedFlows[2], 115.7625, 1e-6);

    // Terminal neutro: VT = fluxo_{N+1}/r = 115,7625 × 1,05 / 0,10.
    expectClose(o.terminalValue, (115.7625 * 1.05) / 0.1, 1e-6);

    // **Com o levantamento de meio de ano**, que é a convenção de produção
    // desde a decisão 48: o caixa do exercício chega ao longo do ano, e
    // descontá-lo inteiro no dia 31 de dezembro cobra doze meses de espera
    // por dinheiro que em média chegou no sexto. Com taxa plana o fator é o
    // mesmo em todo o valor, e a conta manual o carrega para fora.
    const midYear = Math.sqrt(1.1);
    let vp = 0.0;
    for (let t = 1; t <= 3; t++) {
      vp += (100 * Math.pow(1.05, t)) / Math.pow(1.1, t);
    }
    vp += o.terminalValue / Math.pow(1.1, 3);
    expectClose(o.fairValuePerShare, (vp * midYear) / 10, 1e-6);
  });

  it('o terminal neutro não depende do crescimento perpétuo', () => {
    // É a consequência algébrica de ROIC_∞ = WACC, e o que blinda o resultado
    // da premissa que carregava até 80% do valor.
    const terminal = (gInf: number): number =>
      DcfCalculator.firm({
        baseProfit: 100,
        assumptions: flat.copyWith({ perpetualGrowth: gInf }),
        netDebt: 0,
        sharesOutstanding: 10,
      }).unwrap().terminalValue;

    // A identidade que sustenta a afirmação: VT = lucro_{N+1}/r, sem nenhuma
    // divisão por (r − g) para amplificar a premissa. Com g_∞ a 0,02 ou a
    // 0,06 o denominador é o mesmo — 0,10 —, e só o numerador muda.
    for (const gInf of [0.02, 0.06, 0.09]) {
      const o = DcfCalculator.firm({
        baseProfit: 100,
        assumptions: flat.copyWith({ perpetualGrowth: gInf }),
        netDebt: 0,
        sharesOutstanding: 10,
      }).unwrap();
      const finalProfit = o.projectedFlows[o.projectedFlows.length - 1]!; // retenção nula: fluxo = lucro
      expectClose(o.terminalValue, (finalProfit * (1 + gInf)) / 0.1, 1e-6, 'o denominador é o desconto, não o spread');
    }
    // E o valor terminal continua finito quando g_∞ se aproxima de r, que é
    // onde a perpetuidade de Gordon explodiria.
    const nearDiscount = terminal(0.0999);
    expect(Number.isFinite(nearDiscount)).toBe(true);
  });

  it('o freio de reinvestimento reduz o fluxo distribuído', () => {
    const withoutBrake = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: flat,
      netDebt: 0,
      sharesOutstanding: 10,
    }).unwrap();
    const withBrake = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: flat.copyWith({ returnOnCapital: 0.125 }),
      netDebt: 0,
      sharesOutstanding: 10,
    }).unwrap();

    // g₁ = 5% e retorno de 12,5% → b₁ = 40%.
    expectClose(withBrake.projectedFlows[0], 105.0 * 0.6, 1e-9);
    expect(
      withBrake.fairValuePerShare,
      'crescer exige reinvestir; descontar o lucro inteiro e fazê-lo crescer conta o mesmo dinheiro duas vezes',
    ).toBeLessThan(withoutBrake.fairValuePerShare);
  });

  it('o crescimento decai linearmente até a perpetuidade', () => {
    const a = new DcfAssumptions({ projectionYears: 5, growthRate: 0.2, perpetualGrowth: 0.04, discountRate: 0.12 });
    expectClose(a.growthAt(1), 0.2, 1e-12);
    expectClose(a.growthAt(5), 0.04, 1e-12);
    expectClose(a.growthAt(3), 0.12, 1e-12, 'no meio do horizonte, o ponto médio entre as duas taxas');
  });

  it('dívida líquida reduz o valor do equity', () => {
    const withoutDebt = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: flat,
      netDebt: 0,
      sharesOutstanding: 10,
    }).unwrap();
    const withDebt = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: flat,
      netDebt: 500,
      sharesOutstanding: 10,
    }).unwrap();
    expectClose(withDebt.equityValue, withoutDebt.equityValue - 500, 1e-6);
    expect(withDebt.equityShare).toBeLessThan(withoutDebt.equityShare);
  });

  it('a participação do equity expõe a ponte fina', () => {
    const o = DcfCalculator.firm({ baseProfit: 100, assumptions: flat, netDebt: 0, sharesOutstanding: 10 }).unwrap();
    // Dívida a 95% do valor da firma deixa 5% de equity — abaixo dos 35% em
    // que a ressalva `ponteFragil` avisa; é o caso RENT3, em que o preço por
    // papel vira resíduo.
    const thin = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: flat,
      netDebt: o.enterpriseValue * 0.95,
      sharesOutstanding: 10,
    }).unwrap();
    expectClose(thin.equityShare, 0.05, 1e-6);
    expect(thin.equityShare).toBeLessThan(ValuationDiagnostics.fragileEquityShare);
  });

  it('lucro operacional negativo não é avaliável pela via da firma', () => {
    const r = DcfCalculator.firm({ baseProfit: -50, assumptions: flat, netDebt: 0, sharesOutstanding: 10 });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('exige quantidade de papéis válida', () => {
    const r = DcfCalculator.firm({ baseProfit: 100, assumptions: flat, netDebt: 0, sharesOutstanding: 0 });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull).toBeInstanceOf(InsufficientData);
  });
});

describe('DCF pela via do acionista', () => {
  const a = new DcfAssumptions({
    projectionYears: 3,
    growthRate: 0.06,
    perpetualGrowth: 0.06,
    discountRate: 0.12,
    returnOnCapital: 0.12,
  });

  it('desconta apenas a parcela distribuível do lucro', () => {
    const o = DcfCalculator.shareholder({ baseProfit: 10, assumptions: a }).unwrap();
    // g = 6% e ROE de 12% → b = 50%, e o payout é o complemento.
    expectClose(o.projectedFlows[0], 10 * 1.06 * 0.5, 1e-9, 'LPA × (1 − b) é literalmente o dividendo');
  });

  it('sem retenção, o terminal é LPA ÷ Ke', () => {
    const noGrowth = new DcfAssumptions({ projectionYears: 1, growthRate: 0.0, perpetualGrowth: 0.0, discountRate: 0.1 });
    const o = DcfCalculator.shareholder({ baseProfit: 10, assumptions: noGrowth }).unwrap();
    expectClose(o.terminalValue, 100.0, 1e-9);
  });

  it('não há ponte de dívida: o fluxo já é do acionista', () => {
    const o = DcfCalculator.shareholder({ baseProfit: 10, assumptions: a }).unwrap();
    expectClose(o.equityValue, o.enterpriseValue, 1e-12);
    expect(o.equityShare).toBe(1.0);
  });

  it('lucro base não positivo não é avaliável', () => {
    const r = DcfCalculator.shareholder({ baseProfit: 0, assumptions: a });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull).toBeInstanceOf(InsufficientData);
  });
});

describe('ScenarioEngine', () => {
  const center = new DcfAssumptions({ projectionYears: 5, growthRate: 0.05, perpetualGrowth: 0.02, discountRate: 0.1 });

  const valuate = (a: DcfAssumptions): Result<number> =>
    DcfCalculator.firm({ baseProfit: 100, assumptions: a, netDebt: 0, sharesOutstanding: 10 }).map(
      (o) => o.fairValuePerShare,
    );

  it('modo discreto produz as três faixas nomeadas', () => {
    const result = ScenarioEngine.run({ source: DiscreteScenarios.around(center), valuate });
    expect(result.isOk).toBe(true);
    const outcome = result.unwrap();
    expect(outcome.mode).toBe(ScenarioMode.discrete);
    expect(outcome.discrete!.size).toBe(3);
    // Pessimista < Base < Otimista.
    expect(outcome.discrete!.get(ScenarioBand.bear)!).toBeLessThan(outcome.discrete!.get(ScenarioBand.base)!);
    expect(outcome.discrete!.get(ScenarioBand.base)!).toBeLessThan(outcome.discrete!.get(ScenarioBand.bull)!);
  });

  it('modo Monte Carlo produz distribuição com percentis ordenados', () => {
    const result = ScenarioEngine.run({ source: StochasticScenarios.around(center), valuate, samples: 2000 });
    expect(result.isOk).toBe(true);
    const distribution = result.unwrap().distribution!;
    expect(distribution.sortedValues.length).toBeGreaterThan(1500);
    expect(distribution.p5).toBeLessThan(distribution.median);
    expect(distribution.median).toBeLessThan(distribution.p95);
  });

  it('mesma semente produz exatamente o mesmo resultado', () => {
    const first = ScenarioEngine.run({
      source: StochasticScenarios.around(center),
      valuate,
      samples: 500,
      seed: 7,
    }).unwrap();
    const second = ScenarioEngine.run({
      source: StochasticScenarios.around(center),
      valuate,
      samples: 500,
      seed: 7,
    }).unwrap();
    expect(first.distribution!.median).toBe(second.distribution!.median);
    expect(first.distribution!.p95).toBe(second.distribution!.p95);
  });

  it('os dois modos partem do mesmo cenário central', () => {
    const discrete = ScenarioEngine.run({ source: DiscreteScenarios.around(center), valuate }).unwrap();
    const stochastic = ScenarioEngine.run({
      source: StochasticScenarios.around(center),
      valuate,
      samples: 200,
    }).unwrap();
    expectClose(discrete.baseValue, stochastic.baseValue, 1e-12);
  });

  it('probabilidade de o valor justo superar o preço de mercado', () => {
    const distribution = ScenarioEngine.run({
      source: StochasticScenarios.around(center),
      valuate,
      samples: 1000,
    }).unwrap().distribution!;
    const probability = distribution.probabilityAbove(0.0);
    expectClose(probability, 1.0, 1e-9);
  });
});
