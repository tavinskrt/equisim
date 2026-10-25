import { describe, expect, it } from 'vitest';

import {
  Asset,
  CapmInputs,
  CostOfCapital,
  CurveVertex,
  DateTime,
  EvaluateGoalAlignment,
  FinancialGoal,
  FundamentalsSnapshot,
  type GoalAlignment,
  GrowthEstimator,
  InsufficientData,
  InvalidInput,
  MarketAnchors,
  Money,
  Portfolio,
  PortfolioKind,
  ScenarioMode,
  Sector,
  StochasticScenarios,
  SwapAssetBetweenPortfolios,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
  ValuationResult,
  Weights,
  YieldCurve,
} from '../../src/core';
import { day, expectClose } from './helpers';

const ticker = Ticker.parse('PETR4');
const asOf = day(2026, 8, 19);

const capm = new CapmInputs({ riskFreeRate: 0.094, beta: 1.0, marketPremium: CapmInputs.defaultMarketPremium });

/** Exercício com todos os campos necessários ao FCFF. */
const complete = (year: number, scale = 1.0): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(year, 12, 31),
    totalRevenue: 1000 * scale,
    ebit: 300 * scale,
    ebitda: 400 * scale,
    netIncome: 200 * scale,
    incomeBeforeTax: 300 * scale,
    incomeTaxExpense: 100 * scale,
    interestExpense: 55,
    earningsPerShare: 2.0 * scale,
    cash: 100,
    shortTermInvestments: 50,
    shortTermDebt: 100,
    longTermDebt: 400,
    totalStockholderEquity: 1500 * scale,
    bookValuePerShare: 15 * scale,
    operatingCashFlow: 320 * scale,
    freeCashFlow: 250 * scale,
    // NOPAT publicado e patrimônio crescendo com o lucro retido: é o que a
    // decisão 25 exige para reconstituir base de capital e retorno.
    nopat: 200 * scale,
    sharesOutstanding: 100,
    sharesOutstandingAsOf: 100,
    marketCap: 3000,
    enterpriseToEbitda: 6.0,
  });

/**
 * Série de exercícios crescendo à taxa informada.
 *
 * Dez exercícios por padrão: a Porta 0 exige ao menos oito publicados, que é o
 * mínimo em que a janela de ciclo existe e os testes das guardas têm graus de
 * liberdade (decisão 25).
 */
const growingHistory = (o: { rate: number; years?: number; endYear?: number }): FundamentalsSnapshot[] => {
  const years = o.years ?? 10;
  const endYear = o.endYear ?? 2025;
  const out: FundamentalsSnapshot[] = [];
  let scale = 1.0;
  for (let i = years - 1; i >= 0; i--) {
    out.push(complete(endYear - i, scale));
    scale *= 1 + o.rate;
  }
  return out;
};

describe('GrowthEstimator', () => {
  it('perpetuidade nunca supera o crescimento da economia', () => {
    // O teto passa a ser informado, não constante: 6,52% é a composição do
    // crescimento real medido do IBC-Br com o IPCA observado (decisão 25).
    const cap = 0.0652;
    expect(GrowthEstimator.perpetual({ explicitGrowth: 0.15, economyGrowth: cap })).toBe(cap);
    expect(GrowthEstimator.perpetual({ explicitGrowth: 0.01, economyGrowth: cap })).toBe(0.01);
    // **O piso é o da banda de sanidade, e não zero** (decisão 56). O piso
    // em zero afirmava que toda empresa em declínio volta a crescer zero em
    // dez anos, e tornava inalcançável o limite que o projeto já declarara
    // em `floorRate` — com a razão escrita lá.
    expect(GrowthEstimator.perpetual({ explicitGrowth: -0.05, economyGrowth: cap })).toBe(GrowthEstimator.floorRate);
    expect(GrowthEstimator.perpetual({ explicitGrowth: -0.02, economyGrowth: cap })).toBe(-0.02);
    // Abaixo da banda, o piso segura: encolher para sempre tem limite.
    expect(GrowthEstimator.perpetual({ explicitGrowth: -0.4, economyGrowth: cap })).toBe(GrowthEstimator.floorRate);
    // E o teto continua onde estava, mesmo com economia encolhendo.
    expectClose(GrowthEstimator.perpetual({ explicitGrowth: 0.1, economyGrowth: -0.01 }), -0.01, 1e-12);
    // Economia encolhendo mais que o piso: o teto vence, e não estoura.
    // `clamp` lança quando o piso passa o teto.
    expectClose(GrowthEstimator.perpetual({ explicitGrowth: 0.1, economyGrowth: -0.2 }), -0.2, 1e-12);
    expectClose(GrowthEstimator.perpetual({ explicitGrowth: -0.3, economyGrowth: -0.2 }), -0.2, 1e-12);
  });
});

describe('ValuationCascade — escolha do modelo', () => {
  const inputsWith = (fundamentals: FundamentalsSnapshot[], price = 30.0): ValuationInputs =>
    new ValuationInputs({ ticker, asOf, fundamentals, marketPrice: price, capm });

  describe('Curva de juros observada — decisão 74', () => {
    const flat = (r: number): YieldCurve =>
      YieldCurve.of(DateTime.utc(2026, 9, 10), [
        new CurveVertex(0.5, r),
        new CurveVertex(2, r),
        new CurveVertex(5, r),
        new CurveVertex(10, r),
      ])!;

    it('curva plana na mesma taxa reproduz o motor sem curva', () => {
      // Se a curva é plana em Rf e a taxa estrutural também é Rf, o caminho
      // de forwards e o de interpolação linear são o mesmo número. É a
      // prova de que a ligação troca a fonte da taxa e nada mais.
      const rf = capm.riskFreeRate;
      const base = inputsWith(growingHistory({ rate: 0.08 }));
      const withoutCurve = ValuationCascade.evaluate(
        new ValuationInputs({
          ticker: base.ticker,
          asOf: base.asOf,
          fundamentals: base.fundamentals,
          marketPrice: base.marketPrice,
          capm: base.capm,
          declaredTerminalRiskFreeRate: rf,
        }),
      ).unwrap();
      const withCurve = ValuationCascade.evaluate(
        new ValuationInputs({
          ticker: base.ticker,
          asOf: base.asOf,
          fundamentals: base.fundamentals,
          marketPrice: base.marketPrice,
          capm: base.capm,
          riskFreeCurve: flat(rf),
        }),
      ).unwrap();
      expectClose(withCurve.upside, withoutCurve.upside, 1e-9);
    });

    it('a perpetuidade passa a ser o forward longo da curva', () => {
      const base = inputsWith(growingHistory({ rate: 0.08 }));
      const i = new ValuationInputs({
        ticker: base.ticker,
        asOf: base.asOf,
        fundamentals: base.fundamentals,
        marketPrice: base.marketPrice,
        capm: base.capm,
        declaredTerminalRiskFreeRate: 0.09,
        riskFreeCurve: flat(0.14),
      });
      expectClose(i.terminalRiskFreeRate, 0.14, 1e-12, 'a curva vence a média decenal do CDI');
    });

    it('taxa longa mais alta baixa o preço justo, e o aviso diz de onde veio', () => {
      const base = inputsWith(growingHistory({ rate: 0.08 }));
      const withInput = (r: number): ValuationResult =>
        ValuationCascade.evaluate(
          new ValuationInputs({
            ticker: base.ticker,
            asOf: base.asOf,
            fundamentals: base.fundamentals,
            marketPrice: base.marketPrice,
            capm: base.capm,
            riskFreeCurve: flat(r),
          }),
        ).unwrap();
      const low = withInput(0.09);
      const high = withInput(0.14);
      expect(high.upside).toBeLessThan(low.upside);
      expect(high.warnings.some((w) => w.includes('curva dos títulos prefixados'))).toBe(true);
      expect(high.warnings.some((w) => w.includes('sem curva de juros'))).toBe(false);
    });
  });

  it('usa FCFF quando há fluxo, dívida e ações', () => {
    const result = ValuationCascade.evaluate(inputsWith(growingHistory({ rate: 0.08 })));
    expect(result.isOk).toBe(true);
    expect(result.unwrap().model).toBe(ValuationModel.dcfFcff);
  });

  it('FCFF desconta ao WACC, abaixo do custo do capital próprio', () => {
    const valuation = ValuationCascade.evaluate(inputsWith(growingHistory({ rate: 0.08 }))).unwrap();
    expect(valuation.discountRate, 'com dívida e benefício fiscal, o WACC fica abaixo do Ke').toBeLessThan(
      capm.costOfEquity,
    );
  });

  it('sem lucro operacional recorrente, a Porta 3 manda para a via do acionista', () => {
    // Antes da decisão 25 a via caía pelo sinal do fluxo de caixa de um
    // exercício. Agora quem decide é o lucro operacional recorrente, que é o
    // fluxo de manutenção sob a aproximação de capex de manutenção igual à
    // depreciação — o que não penaliza quem está em ciclo de investimento.
    //
    // **Não remova esta migração sem refazer a medição da decisão 64.** A
    // lente `metodo` propôs recusar estes ativos em vez de migrá-los; sobre
    // 8 coortes *point-in-time*, a Porta 3 saiu com o MAIOR poder de
    // ordenação dos três roteamentos (IC12 +0,4197, IC36 +0,3815), e
    // recusá-la baixaria o IC do universo inteiro.
    const history = growingHistory({ rate: 0.08 }).map(
      (s) =>
        new FundamentalsSnapshot({
          ticker: s.ticker,
          fiscalPeriodEnd: s.fiscalPeriodEnd,
          earningsPerShare: s.earningsPerShare,
          netIncome: s.netIncome,
          bookValuePerShare: s.bookValuePerShare,
          sharesOutstanding: s.sharesOutstanding,
          sharesOutstandingAsOf: s.sharesOutstandingAsOf,
        }),
    );

    const result = ValuationCascade.evaluate(inputsWith(history));
    expect(result.isOk).toBe(true);
    const valuation = result.unwrap();
    expect(valuation.model).toBe(ValuationModel.dcfEarnings);
    expectClose(valuation.discountRate, capm.costOfEquity, 1e-12, 'fluxo do acionista se desconta ao Ke, não ao WACC');
    expect(
      valuation.warnings.some((w) => w.includes('lucro operacional')),
      'a escolha de via precisa ficar visível',
    ).toBe(true);
  });

  it('sem base de capital reconstituível, recusa em vez de inventar piso', () => {
    // Até a decisão 25 este ativo caía para múltiplos e devolvia o valor
    // patrimonial rotulado como piso contábil. O degrau saiu: ele reconstruía
    // o valor da firma a partir do múltiplo que o mercado já atribui ao
    // próprio ativo, devolvendo o preço de mercado por construção — e um
    // potencial de valorização nulo por aritmética, não por análise.
    const history: FundamentalsSnapshot[] = [];
    for (let y = 2020; y <= 2025; y++) {
      history.push(new FundamentalsSnapshot({ ticker, fiscalPeriodEnd: day(y, 12, 31), bookValuePerShare: 15 }));
    }

    const result = ValuationCascade.evaluate(inputsWith(history));
    expect(
      result.isErr,
      'sem contagem de ações do exercício não há patrimônio nem capital investido, e nenhuma das duas vias se sustenta',
    ).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('múltiplo próprio não é mais degrau de cascata', () => {
    // O EV/EBITDA da própria empresa reconstrói o próprio preço. Com dado
    // suficiente só para ele, a resposta correta é recusar.
    const history: FundamentalsSnapshot[] = [];
    for (let y = 2020; y <= 2025; y++) {
      history.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(y, 12, 31),
          ebitda: 400,
          enterpriseToEbitda: 6.0,
          sharesOutstanding: 100,
          shortTermDebt: 100,
          longTermDebt: 400,
          cash: 100,
        }),
      );
    }
    const result = ValuationCascade.evaluate(inputsWith(history));
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('falha explicitamente quando nada é aplicável', () => {
    const history: FundamentalsSnapshot[] = [];
    for (let y = 2020; y <= 2025; y++) {
      history.push(new FundamentalsSnapshot({ ticker, fiscalPeriodEnd: day(y, 12, 31) }));
    }
    const result = ValuationCascade.evaluate(inputsWith(history));
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('rejeita preço de mercado inválido', () => {
    const result = ValuationCascade.evaluate(inputsWith(growingHistory({ rate: 0.05 }), 0));
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InvalidInput);
  });
});

describe('ValuationCascade — barreira temporal', () => {
  it('exercício ainda não divulgado não é usado', () => {
    // Exercício encerrado 30 dias antes da análise: dentro da defasagem
    // de 90 dias, portanto ainda não público.
    const result = ValuationCascade.evaluate(
      new ValuationInputs({ ticker, asOf: day(2026, 1, 30), fundamentals: [complete(2025)], marketPrice: 30, capm }),
    );
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull!.message).toContain('divulgado');
  });

  it('avisa quando o exercício disponível está defasado', () => {
    const result = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf,
        fundamentals: growingHistory({ rate: 0.05, endYear: 2021 }),
        marketPrice: 30,
        capm,
      }),
    );
    expect(result.isOk).toBe(true);
    expect(result.unwrap().warnings.some((w) => w.includes('desatualizada'))).toBe(true);
  });
});

describe('ValuationCascade — cenários', () => {
  const baseInputs = (): ValuationInputs =>
    new ValuationInputs({ ticker, asOf, fundamentals: growingHistory({ rate: 0.08 }), marketPrice: 30, capm });

  it('modo discreto é o padrão e traz as três faixas', () => {
    const valuation = ValuationCascade.evaluate(baseInputs()).unwrap();
    expect(valuation.mode).toBe(ScenarioMode.discrete);
    expect(valuation.discreteScenarios!.size).toBe(3);
  });

  it('Monte Carlo é ativado trocando a fonte de premissas', () => {
    const valuation = ValuationCascade.evaluate(baseInputs(), {
      scenarioBuilder: (base) => StochasticScenarios.around(base),
      monteCarloSamples: 1000,
    }).unwrap();
    expect(valuation.mode).toBe(ScenarioMode.monteCarlo);
    expect(valuation.distribution).not.toBeNull();
    expect(valuation.distribution!.p5).toBeLessThan(valuation.distribution!.p95);
  });

  it('trocar de modo não altera o cenário base', () => {
    const inputs = baseInputs();
    const discrete = ValuationCascade.evaluate(inputs).unwrap();
    const stochastic = ValuationCascade.evaluate(inputs, {
      scenarioBuilder: (base) => StochasticScenarios.around(base),
      monteCarloSamples: 500,
    }).unwrap();
    expect(discrete.fairValue.equals(stochastic.fairValue)).toBe(true);
  });
});

describe('Unidade de negociação', () => {
  it('ação comum devolve razão 1', () => {
    expect(
      ValuationCascade.quotedUnitRatio({ sharesOutstanding: 12888733000, marketCap: 571228600000, marketPrice: 44.32 }),
    ).toBe(1.0);
  });

  it('unit de cinco ações é reconhecida pelos números da fonte', () => {
    // SAPR11 em 21/08/2026: 1,511 bi de ações, valor de mercado de
    // R$ 10,08 bi e unit a R$ 33,35.
    expect(
      ValuationCascade.quotedUnitRatio({ sharesOutstanding: 1511205500, marketCap: 10079740685, marketPrice: 33.35 }),
    ).toBe(5.0);
  });

  it('unit de três ações também', () => {
    // BPAC11 nas mesmas condições.
    expect(
      ValuationCascade.quotedUnitRatio({ sharesOutstanding: 11670063000, marketCap: 202203291580, marketPrice: 51.97 }),
    ).toBe(3.0);
  });

  it('a unit é reconhecida mesmo com o preço andado desde o valor de mercado', () => {
    // SAPR11 em 04/09/2026: 503,7 mi de ações, R$ 3,608 bi de valor de
    // mercado e unit a R$ 34,95 — razão medida de **4,8799**, a 0,1201 do
    // inteiro. A banda absoluta de 0,12 recusava por **0,0001**, e a unit
    // de cinco ações caía para a convenção de ação comum. Decisão 61.
    expect(
      ValuationCascade.quotedUnitRatio({ sharesOutstanding: 503733800, marketCap: 3607751300, marketPrice: 34.95 }),
    ).toBe(5.0);
  });

  it('a mesma discordância relativa decide igual em qualquer unit', () => {
    // O desvio mede quanto o preço andou desde o valor de mercado
    // publicado, e isso não depende de quantas ações formam a unit. Com
    // banda absoluta, 3% valiam 0,06 em u = 2 e 0,15 em u = 5 — aceito ali,
    // recusado aqui, pela mesma discordância.
    for (const u of [2, 3, 5, 10]) {
      expect(
        ValuationCascade.quotedUnitRatio({ sharesOutstanding: u * 1.03e9, marketCap: 1e9, marketPrice: 1.0 }),
        '3% de discordância cabe em qualquer unit',
      ).toBe(u);
    }
  });

  it('e a tolerância relativa aperta a unit de duas ações', () => {
    // 5,5% em u = 2 são 0,11 absolutos — dentro da banda antiga, fora da
    // nova. A troca não é permissiva em toda parte: de u = 3 para cima
    // afrouxa, em u = 2 aperta, e em u = 1 não decide nada.
    expect(ValuationCascade.quotedUnitRatio({ sharesOutstanding: 2.11e9, marketCap: 1e9, marketPrice: 1.0 })).toBe(1.0);
  });

  it('em ação comum a tolerância não decide nada', () => {
    // Aceitar devolve 1,0 e recusar devolve 1,0. É por isso que apertar a
    // banda em u = 1 não tem consequência.
    for (const raw of [0.79, 0.95, 1.0, 1.05, 1.21]) {
      expect(ValuationCascade.quotedUnitRatio({ sharesOutstanding: raw * 1e9, marketCap: 1e9, marketPrice: 1.0 })).toBe(
        1.0,
      );
    }
  });

  it('razão longe de um inteiro é recusada em favor de 1', () => {
    expect(
      ValuationCascade.quotedUnitRatio({ sharesOutstanding: 1000, marketCap: 1000, marketPrice: 2.4 }),
      'nenhuma unit da B3 tem 2,4 ações; melhor não aplicar fator',
    ).toBe(1.0);
  });

  it('sem valor de mercado publicado, não se inventa fator', () => {
    expect(ValuationCascade.quotedUnitRatio({ sharesOutstanding: 1000, marketCap: null, marketPrice: 10 })).toBe(1.0);
  });

  it('o preço justo sai por unit, não por ação', () => {
    // Mesma empresa, mesmos demonstrativos: só muda a forma de negociar.
    const perShareResult = ValuationCascade.evaluate(
      new ValuationInputs({ ticker, asOf, fundamentals: growingHistory({ rate: 0.05 }), marketPrice: 30, capm }),
    );
    // 100 ações a R$ 30 valem R$ 3.000 de mercado; em units de 5, são 20
    // units a R$ 150.
    const byUnit = ValuationCascade.evaluate(
      new ValuationInputs({ ticker, asOf, fundamentals: growingHistory({ rate: 0.05 }), marketPrice: 150, capm }),
    );

    expect(perShareResult.isOk).toBe(true);
    expect(byUnit.isOk).toBe(true);
    expectClose(
      byUnit.unwrap().fairValue.reais,
      perShareResult.unwrap().fairValue.reais * 5,
      0.05,
      'o valor da firma é o mesmo; muda o número de papéis',
    );
    // E o que importa para a decisão — a distância até o preço justo — fica
    // igual nos dois casos.
    expectClose(byUnit.unwrap().upside, perShareResult.unwrap().upside, 0.01);
  });
});

describe('MarketAnchors — unidades', () => {
  it('crescimento perpétuo composto real com inflação', () => {
    const anchors = new MarketAnchors({ riskFreeCagr: 0.094, marketCagr: 0.1126, inflationCagr: 0.05, observedYears: 10 });
    // (1 + 1,45%) × (1 + 5%) − 1. A parcela real deixou de ser a constante
    // de 3% e passou a ser medida do IBC-Br (decisão 25).
    expectClose(anchors.nominalEconomyGrowth, 0.0652, 1e-4);
    expect(
      anchors.nominalEconomyGrowth,
      'o teto nominal precisa superar o real, ou a unidade se mistura',
    ).toBeGreaterThan(anchors.realEconomyGrowth);
  });

  it('sem taxa corrente informada, cai para a média histórica', () => {
    const anchors = new MarketAnchors({ riskFreeCagr: 0.094, marketCagr: 0.1126, observedYears: 10 });
    expect(anchors.currentRiskFreeRate).toBe(0.094);
  });

  it('taxa de desconto e limiar da meta são números distintos', () => {
    const anchors = new MarketAnchors({
      riskFreeCagr: 0.094,
      currentRiskFreeRate: 0.1415,
      marketCagr: 0.1126,
      observedYears: 10,
    });
    expect(anchors.riskFreeCagr).not.toBe(anchors.currentRiskFreeRate);
    expect(anchors.currentRiskFreeRate).toBe(0.1415);
  });
});

describe('CostOfCapital — banda de sanidade', () => {
  const rf = 0.125;
  const capmRf = new CapmInputs({ riskFreeRate: rf, beta: 1.0, marketPremium: CapmInputs.defaultMarketPremium });

  it('o prêmio de crédito vem da alavancagem, não da despesa financeira', () => {
    // A cobertura de juros foi o primeiro substituto da razão observada e
    // herdava o defeito dela: a despesa contaminada por arrendamento e
    // variação cambial está no denominador. Medido, ela punia justamente as
    // sólidas — ABEV3 e WEGE3, de caixa líquido, pagavam 2,4 p.p.; a SAPR11,
    // com 0,60x de alavancagem, pagava o teto de 10 p.p.
    const netCash = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.473,
      taxRate: 0.34,
      equityValue: 203,
      debtValue: 4.6,
      interestCoverage: 3.68,
      netDebtToEbitda: -0.3,
    });
    expectClose(netCash.effectiveCostOfDebt, rf + 0.01, 1e-12);
    expect(netCash.costOfDebtWasClamped).toBe(true);

    const moderate = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.279,
      taxRate: 0.34,
      equityValue: 3.6,
      debtValue: 3.2,
      interestCoverage: 1.26,
      netDebtToEbitda: 1.17,
    });
    expectClose(moderate.effectiveCostOfDebt, rf + 0.018, 1e-12, 'alavancagem de 1,17x não é crédito de pré-falência');

    const leveraged = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.2,
      taxRate: 0.34,
      equityValue: 20,
      debtValue: 80,
      interestCoverage: 2.0,
      netDebtToEbitda: 6.0,
    });
    expectClose(leveraged.effectiveCostOfDebt, rf + CostOfCapital.maxCreditSpread, 1e-12);

    expect(netCash.effectiveCostOfDebt).toBeLessThan(moderate.effectiveCostOfDebt);
    expect(
      moderate.effectiveCostOfDebt,
      'a ordenação de risco de crédito precisa ser monótona na alavancagem',
    ).toBeLessThan(leveraged.effectiveCostOfDebt);
  });

  it('a faixa que decide se a cobertura fala é a da data, e não a da taxa suposta — item B10', () => {
    // Despesa financeira de 14% ao ano, cobertura apertada de 1,3x e
    // alavancagem baixa: a cobertura só fala se 14% estiver dentro de
    // `[Rf, Rf + 10 p.p.]`. Medida contra a taxa do CAPM, a resposta mudava com
    // o cenário — com a Rf a 14,5% a cobertura saía da conta e o custo da
    // dívida caía 5,5 p.p. —, e o preço justo subia com a taxa.
    const withInput = (assumedRf: number, reference: number | null = null): CostOfCapital =>
      new CostOfCapital({
        capm: new CapmInputs({ riskFreeRate: assumedRf, beta: 1.0, marketPremium: CapmInputs.defaultMarketPremium }),
        costOfDebt: 0.14,
        taxRate: 0.34,
        equityValue: 100,
        debtValue: 50,
        interestCoverage: 1.3,
        netDebtToEbitda: 0.8,
        creditReferenceRate: reference,
      });
    // Sem referência, a faixa anda com a taxa suposta: é o degrau.
    expectClose(withInput(0.135).effectiveCostOfDebt, 0.135 + 0.075, 1e-12);
    expectClose(withInput(0.145).effectiveCostOfDebt, 0.145 + 0.013, 1e-12);
    // Com a referência da data, o veredito é um só, e o custo da dívida sobe
    // com a taxa suposta, sem saltar.
    const low = withInput(0.135, 0.125).effectiveCostOfDebt;
    const high = withInput(0.145, 0.125).effectiveCostOfDebt;
    expectClose(low, 0.135 + 0.075, 1e-12);
    expectClose(high, 0.145 + 0.075, 1e-12);
    expectClose(high - low, 0.01, 1e-12);
  });

  it('sem EBITDA positivo, o prêmio é o do pior caso', () => {
    const coc = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.9,
      taxRate: 0.34,
      equityValue: 100,
      debtValue: 50,
      interestCoverage: 3.0,
    });
    expect(coc.effectiveCostOfDebt).toBe(rf + CostOfCapital.maxCreditSpread);
    expect(coc.costOfDebtWasClamped).toBe(true);
  });

  it('observado próximo do estimado não é declarado como substituição', () => {
    // Cobertura de 3,7x pede Rf + 2,4 p.p. = 14,9%. O observado de 14,5%
    // está a 0,4 p.p. disso — dentro do passo da própria tabela de prêmios,
    // e portanto não é divergência a declarar.
    const coc = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.149,
      taxRate: 0.34,
      equityValue: 100,
      debtValue: 40,
      netDebtToEbitda: 2.4,
      interestCoverage: 9.0,
    });
    expectClose(coc.effectiveCostOfDebt, rf + 0.024, 1e-12);
    expect(coc.costOfDebtWasClamped).toBe(false);
    expect(coc.waccWasFloored).toBe(false);
  });

  it('o escudo fiscal é limitado pela capacidade de usá-lo', () => {
    // Com EBIT abaixo da despesa financeira, a dedução excedente não abate
    // imposto no exercício: o escudo vale 34% × cobertura, não 34%.
    const withoutMargin = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.18,
      taxRate: 0.34,
      equityValue: 10,
      debtValue: 90,
      interestCoverage: 0.5,
      netDebtToEbitda: 2.0,
    });
    expectClose(withoutMargin.effectiveTaxShield, 0.34 * 0.5, 1e-12);

    const withMargin = new CostOfCapital({
      capm: capmRf,
      costOfDebt: 0.18,
      taxRate: 0.34,
      equityValue: 10,
      debtValue: 90,
      interestCoverage: 4.0,
      netDebtToEbitda: 2.0,
    });
    expect(withMargin.effectiveTaxShield).toBe(0.34);
    expect(withoutMargin.rawWacc, 'menos escudo é mais custo de capital').toBeGreaterThan(withMargin.rawWacc);
  });

  it('WACC nunca desce abaixo da taxa livre de risco', () => {
    // Empresa muito alavancada, com custo de dívida no piso da tabela: o
    // benefício fiscal empurraria o desconto para baixo do soberano, e a
    // perpetuidade explodiria.
    const coc = new CostOfCapital({
      capm: capmRf,
      costOfDebt: rf,
      taxRate: 0.34,
      equityValue: 10,
      debtValue: 90,
      interestCoverage: 20.0,
      netDebtToEbitda: -1.0,
    });
    expectClose(coc.effectiveCostOfDebt, rf + 0.01, 1e-12);
    expect(coc.rawWacc).toBeLessThan(rf);
    expect(coc.wacc).toBe(rf);
    expect(coc.waccWasFloored).toBe(true);
  });
});

describe('SwapAssetBetweenPortfolios', () => {
  const assetOf = (symbol: string, sector: string): Asset =>
    new Asset({ ticker: Ticker.parse(symbol), name: symbol, sector: Sector.fromKey(sector, { label: sector }) });

  const principalWith = (assets: Asset[]): Portfolio =>
    Portfolio.equalWeighted({ id: 'principal', name: 'Principal', kind: PortfolioKind.principal, assets }).unwrap();

  const reserveWith = (assets: Asset[]): Portfolio =>
    Portfolio.equalWeighted({ id: 'reserva', name: 'Reserva', kind: PortfolioKind.reserve, assets }).unwrap();

  it('promove ativo da reserva e reequipondera as duas carteiras', () => {
    const result = SwapAssetBetweenPortfolios.call({
      principal: principalWith([assetOf('PETR4', 'energia'), assetOf('VALE3', 'materiais')]),
      reserve: reserveWith([assetOf('ITUB4', 'financeiro')]),
      ticker: Ticker.parse('ITUB4'),
      toPrincipal: true,
    });

    expect(result.isOk).toBe(true);
    const outcome = result.unwrap();
    expect(outcome.principal.length).toBe(3);
    expect(outcome.reserve.length).toBe(0);
    expect(Weights.sumsToOne(outcome.principal.weights)).toBe(true);
    for (const w of outcome.principal.weights) {
      expectClose(w.value, 1 / 3, 1e-9);
    }
  });

  it('rebaixa ativo do principal para a reserva', () => {
    const outcome = SwapAssetBetweenPortfolios.call({
      principal: principalWith([assetOf('PETR4', 'energia'), assetOf('VALE3', 'materiais')]),
      reserve: reserveWith([assetOf('ITUB4', 'financeiro')]),
      ticker: Ticker.parse('PETR4'),
      toPrincipal: false,
    }).unwrap();
    expect(outcome.principal.length).toBe(1);
    expect(outcome.reserve.length).toBe(2);
  });

  it('rejeita ativo ausente na origem', () => {
    const result = SwapAssetBetweenPortfolios.call({
      principal: principalWith([assetOf('PETR4', 'energia')]),
      reserve: reserveWith([assetOf('ITUB4', 'financeiro')]),
      ticker: Ticker.parse('VALE3'),
      toPrincipal: true,
    });
    expect(result.isErr).toBe(true);
  });

  it('respeita o teto de 15 ativos no destino', () => {
    const full = principalWith(Array.from({ length: 15 }, (_, i) => assetOf(`AAAA${i}`, 'financeiro')));
    const result = SwapAssetBetweenPortfolios.call({
      principal: full,
      reserve: reserveWith([assetOf('ITUB4', 'financeiro')]),
      ticker: Ticker.parse('ITUB4'),
      toPrincipal: true,
    });
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull!.message).toContain('15');
  });
});

describe('EvaluateGoalAlignment', () => {
  const portfolio = Portfolio.equalWeighted({
    id: 'p',
    name: 'Principal',
    kind: PortfolioKind.principal,
    assets: [new Asset({ ticker: Ticker.parse('PETR4'), name: 'PETR4' }), new Asset({ ticker: Ticker.parse('VALE3'), name: 'VALE3' })],
  }).unwrap();

  const valuationWith = (symbol: string, fair: number, price: number): ValuationResult =>
    new ValuationResult({
      ticker: Ticker.parse(symbol),
      asOf,
      model: ValuationModel.dcfFcff,
      fairValue: Money.fromReais(fair),
      marketPrice: Money.fromReais(price),
      discountRate: 0.12,
    });

  const goalOf = (target: number): FinancialGoal =>
    FinancialGoal.unvalidated({
      initialContribution: Money.fromReais(10000),
      monthlyContribution: Money.fromReais(1000),
      months: 120,
      targetWealth: Money.fromReais(target),
    });

  const both = (fair: number, price: number): Map<Ticker, ValuationResult> =>
    new Map([
      [Ticker.parse('PETR4'), valuationWith('PETR4', fair, price)],
      [Ticker.parse('VALE3'), valuationWith('VALE3', fair, price)],
    ]);

  it('carteira que supera a exigência é aprovada', () => {
    const result = EvaluateGoalAlignment.call({
      portfolio,
      goal: goalOf(200000),
      valuations: both(60, 40),
      anchors: MarketAnchors.fallback2026,
    });

    expect(result.isOk).toBe(true);
    const alignment = result.unwrap();
    // Os dois ativos têm o mesmo potencial, então a seção transversal colapsa
    // num ponto: não há escala robusta a estimar, o escore é zero e cada um
    // recebe a âncora — o CDI corrente de 14,15%. É a leitura neutra, e é o
    // que se quer: com dois pontos iguais não há ordenação a premiar.
    expectClose(alignment.expectedReturn, MarketAnchors.fallback2026.currentRiskFreeRate, 1e-9);
    expect(alignment.meetsGoal).toBe(true);
    expect(alignment.gap).toBeGreaterThan(0);
    expectClose(alignment.valuationCoverage, 1.0, 1e-9);
  });

  it('o esperado ordena pelo desconto relativo, ancorado no CDI', () => {
    const goal = goalOf(200000);

    // Seção larga o bastante para ter escala: potenciais de −50% a +100%,
    // mediana em 0%. A carteira fica acima da mediana e recebe prêmio.
    const crossSection = [-0.5, -0.25, 0.0, 0.25, 1.0];

    const run = (fair: number): GoalAlignment =>
      EvaluateGoalAlignment.call({
        portfolio,
        goal,
        valuations: both(fair, 40),
        anchors: MarketAnchors.fallback2026,
        crossSection,
      }).unwrap();

    const cdi = 0.1415;
    // Preço justo igual ao de mercado: potencial nulo, que é a mediana da
    // seção. Recebe exatamente a âncora.
    expectClose(run(40).expectedReturn, cdi, 1e-9);
    // Descontada em relação aos pares: acima do CDI.
    expect(run(60).expectedReturn).toBeGreaterThan(cdi);
    // Esticada: abaixo do CDI, e ainda assim **não negativa** — que é o
    // ponto do estimador. Pelo caminho antigo, um preço justo de R$ 4,00
    // contra R$ 40,00 dava (0,10)^(1/3) − 1 = −53,6% ao ano, e nenhuma meta
    // era alcançável por construção.
    const stretched = run(4).expectedReturn;
    expect(stretched).toBeLessThan(cdi);
    expect(stretched).toBeGreaterThan(0);
  });

  it('a lacuna é a distância até o exigido, e nada mais', () => {
    // O esperado é retorno de PREÇO desde a decisão 023. Uma carteira que
    // paga bem aparece em déficit permanente, e o número que desfaz essa
    // leitura é a própria lacuna invertida — não uma estimativa de yield.
    const alignment = EvaluateGoalAlignment.call({
      portfolio,
      goal: goalOf(400000),
      valuations: both(44, 40),
      anchors: MarketAnchors.fallback2026,
    }).unwrap();

    expect(alignment.meetsGoal).toBe(false);
    // A lacuna é negativa quando o esperado não alcança o exigido, e é o
    // único número desta leitura. `yieldToCloseGap` saiu pela decisão 62:
    // somar um yield ao esperado contaria o provento duas vezes desde que
    // a âncora virou o `Ke`, que é retorno total pelo CAPM.
    expect(alignment.gap).toBeLessThan(0);
    expectClose(alignment.gap / 100, alignment.expectedReturn - alignment.required.annual, 1e-12);
  });

  it('meta atingida não tem lacuna', () => {
    const alignment = EvaluateGoalAlignment.call({
      portfolio,
      goal: goalOf(200000),
      valuations: both(60, 40),
      anchors: MarketAnchors.fallback2026,
    }).unwrap();

    expect(alignment.meetsGoal).toBe(true);
    expect(alignment.gap).toBeGreaterThanOrEqual(0);
  });

  it('sinaliza cobertura fraca de avaliação', () => {
    const alignment = EvaluateGoalAlignment.call({
      portfolio,
      goal: goalOf(200000),
      valuations: new Map([[Ticker.parse('PETR4'), valuationWith('PETR4', 50, 40)]]),
      anchors: MarketAnchors.fallback2026,
    }).unwrap();

    expectClose(alignment.valuationCoverage, 0.5, 1e-9);
    expect(alignment.coverageIsWeak).toBe(true);
  });

  it('meta impossível propaga a falha do solver', () => {
    const goal = FinancialGoal.unvalidated({
      initialContribution: Money.fromReais(1),
      monthlyContribution: Money.zero,
      months: 12,
      targetWealth: Money.fromReais(1000000000),
    });
    const result = EvaluateGoalAlignment.call({
      portfolio,
      goal,
      valuations: new Map(),
      anchors: MarketAnchors.fallback2026,
    });
    expect(result.isErr).toBe(true);
  });
});
