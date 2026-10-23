/**
 * O cálculo do usuário refaz a conta do motor com os números de quem discorda
 * dele (decisão 147).
 *
 * A promessa que estes testes travam: **sem nenhuma troca, o resultado é o
 * preço justo do motor** — em cada rota da cascata —, e cada troca muda só a
 * premissa trocada.
 */
import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  CurveVertex,
  DcfAssumptions,
  DcfCalculator,
  FundamentalsSnapshot,
  InvalidInput,
  ManualField,
  ManualGroup,
  ManualGrowthPath,
  ManualNoticeKind,
  type ManualPremises,
  ManualRatePath,
  ManualReinvestment,
  ManualTerminal,
  ManualValuation,
  Money,
  ShareIssue,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  ValuationModel,
  type ValuationResult,
  YieldCurve,
} from '../../src/core';
import { day, expectClose } from './helpers';

const ticker = Ticker.parse('ABCD3');
const today = day(2026, 9, 9);

/** Companhia operacional: o resultado operacional sustenta a via da firma. */
const firmYear = (y: number, e: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(y, 12, 31),
    totalRevenue: 10000 * e,
    ebit: 1800 * e,
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
    nopat: 1188 * e,
    minorityInterest: 150,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 1000,
    marketCap: 12000,
  });

/**
 * Companhia cujo resultado operacional é negativo e o lucro líquido positivo:
 * a Porta 3 a manda para a via do acionista.
 */
const shareholderYear = (y: number, e: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(y, 12, 31),
    totalRevenue: 10000 * e,
    ebit: -200 * e,
    ebitda: 300 * e,
    netIncome: 900 * e,
    incomeBeforeTax: 1200 * e,
    incomeTaxExpense: -300 * e,
    interestExpense: 50,
    earningsPerShare: 0.9 * e,
    cash: 2000 * e,
    shortTermDebt: 500,
    longTermDebt: 500,
    totalStockholderEquity: 6000 * e,
    bookValuePerShare: 6.0 * e,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 1000,
    marketCap: 12000,
  });

const series = (year: (y: number, e: number) => FundamentalsSnapshot): FundamentalsSnapshot[] => {
  const out: FundamentalsSnapshot[] = [];
  let e = 1.0;
  for (let i = 12; i >= 0; i--) {
    out.push(year(2025 - i, e));
    // Crescimento que oscila em torno de 5%: série sem dispersão não deixa o
    // erro-padrão ser medido.
    e *= i % 2 === 0 ? 1.04 : 1.06;
  }
  return out;
};

const inputs = (
  o: { firm?: boolean; unlevered?: number; curve?: YieldCurve | null; issuances?: ShareIssue[] } = {},
): ValuationInputs =>
  new ValuationInputs({
    ticker,
    asOf: today,
    fundamentals: series(o.firm ?? true ? firmYear : shareholderYear),
    marketPrice: 12.0,
    capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
    declaredTerminalRiskFreeRate: 0.1,
    unleveredBeta: o.unlevered ?? null,
    riskFreeCurve: o.curve ?? null,
    shareIssues: o.issuances ?? [],
  });

const evaluate = (i: ValuationInputs): ValuationResult => {
  const r = ValuationCascade.evaluate(i);
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap();
};

const curve = YieldCurve.of(today, [new CurveVertex(1, 0.14), new CurveVertex(3, 0.13), new CurveVertex(10, 0.12)]);

/** As rotas da cascata que a conta congelada precisa reproduzir. */
const routes = new Map<string, () => ValuationInputs>([
  ['firma, taxas resolvidas', () => inputs({ unlevered: 0.8 })],
  ['firma, interpolação de dois pontos', () => inputs()],
  ['firma, sobre a curva sem resolução', () => inputs({ curve })],
  [
    'firma, com emissão depois do balanço',
    () =>
      inputs({
        issuances: [new ShareIssue({ date: day(2026, 4, 15), amount: Money.fromReais(1200), shares: 100 })],
      }),
  ],
  ['acionista, Ke resolvido', () => inputs({ firm: false, unlevered: 0.9 })],
  ['acionista, interpolação', () => inputs({ firm: false })],
  ['acionista, sobre a curva', () => inputs({ firm: false, curve })],
]);

/**
 * Uma conta congelada sintética da via do acionista, para os testes que
 * precisam de fórmula fechada.
 */
const synthetic = (
  o: { rate?: number; g?: number; gInf?: number; returnRate?: number; advantage?: number | null } = {},
): ManualValuation => {
  const rate = o.rate ?? 0.13;
  const a = new DcfAssumptions({
    growthRate: o.g ?? 0.06,
    perpetualGrowth: o.gInf ?? 0.04,
    discountRate: rate,
    terminalDiscountRate: rate,
    returnOnCapital: o.returnRate ?? 0.2,
    terminalReturnOnCapital: o.advantage ?? null,
  });
  const outcome = DcfCalculator.shareholder({ baseProfit: 1.0, assumptions: a }).unwrap();
  return new ManualValuation({
    lane: ValuationLane.shareholder,
    shares: 100,
    marketPrice: 10,
    engineFairValue: outcome.fairValuePerShare,
    engineBase: 1.0,
    engineAssumptions: a,
    engineRates: outcome.discountRates!,
    engineTerminalRate: outcome.terminalDiscountRateUsed!,
  });
};

describe('sem nenhuma troca, o preço é o do motor', () => {
  for (const [name, build] of routes) {
    it(name, () => {
      const r = evaluate(build());
      const m = r.manual;
      expect(m, 'a cascata congela a conta da via').not.toBeNull();
      const o = m!.evaluate(m!.enginePremises);
      expect(o.isOk, o.failureOrNull?.message).toBe(true);
      const yours = o.unwrap().fairValuePerShare;
      // Igualdade exata, e não tolerância: sem troca, a conta é a mesma.
      expect(yours).toBe(m!.engineFairValue);
      expect(Money.fromReais(yours).equals(r.fairValue)).toBe(true);
      expect(m!.lane === ValuationLane.firm).toBe(r.model === ValuationModel.dcfFcff);
    });
  }

  it('o patrimônio fecha: explícito + perpetuidade − minoritários + emissão = preço × papéis', () => {
    for (const build of routes.values()) {
      const m = evaluate(build()).manual!;
      const o = m.evaluate(m.enginePremises).unwrap();
      expectClose(
        o.explicitPresentValue + o.terminalPresentValue - o.minorityInterest + o.postStatementCapital,
        o.fairValuePerShare * m.shares,
        1e-6,
      );
      expectClose(o.equityValue, o.fairValuePerShare * m.shares, 1e-6);
      // Cada ano: fluxo ÷ fator = valor presente.
      for (const y of o.years) {
        expectClose(y.flow / y.discountFactor, y.presentValue, 1e-9);
      }
    }
  });

  it('na via da firma, a emissão posterior entra pelo valor de emissão', () => {
    const m = evaluate(routes.get('firma, com emissão depois do balanço')!()).manual!;
    expect(m.postStatementCapital).toBe(1200);
    expect(m.evaluate(m.enginePremises).unwrap().postStatementCapital).toBe(1200);
  });
});

describe('cada troca muda só a premissa trocada', () => {
  for (const [name, build] of routes) {
    it(`taxa mais alta, preço mais baixo — ${name}`, () => {
      const m = evaluate(build()).manual!;
      const p = m.enginePremises;
      const base = m.evaluate(p).unwrap().fairValuePerShare;
      const high = m.evaluate(p.copyWith({ discountRate: p.discountRate + 0.01 })).unwrap().fairValuePerShare;
      const low = m.evaluate(p.copyWith({ discountRate: p.discountRate - 0.01 })).unwrap().fairValuePerShare;
      expect(high).toBeLessThan(base);
      expect(low).toBeGreaterThan(base);
    });
  }

  it('o caminho do motor desloca todos os anos e a perpetuidade juntos', () => {
    const m = evaluate(inputs({ curve, firm: false })).manual!;
    const p = m.enginePremises.copyWith({ discountRate: m.enginePremises.discountRate + 0.02 });
    const o = m.evaluate(p).unwrap();
    for (let i = 0; i < o.years.length; i++) {
      expectClose(o.years[i]!.rate, m.engineRates[i]! + 0.02, 1e-12);
    }
    expectClose(o.terminalRate, m.engineTerminalRate + 0.02, 1e-12);
  });

  it('a taxa constante vale do primeiro ano à perpetuidade', () => {
    const m = evaluate(inputs({ curve })).manual!;
    const p = m.enginePremises.copyWith({ ratePath: ManualRatePath.constant, discountRate: 0.15 });
    const o = m.evaluate(p).unwrap();
    for (const y of o.years) {
      expectClose(y.rate, 0.15, 1e-15);
    }
    expectClose(o.terminalRate, 0.15, 1e-15);
  });

  it('na via da firma, a taxa desconta e o custo médio do capital fica', () => {
    // A taxa do usuário entra no `Ke` que desconta o fluxo do acionista; o
    // `WACC`, alvo do retorno e da perpetuidade da firma, é o do motor.
    const m = evaluate(inputs({ unlevered: 0.8 })).manual!;
    const p = m.enginePremises;
    const before = m.evaluate(p).unwrap();
    const after = m.evaluate(p.copyWith({ discountRate: p.discountRate + 0.01 })).unwrap();
    expect(after.capitalCostRates).toEqual(before.capitalCostRates);
    expect(after.terminalCapitalCost).toBe(before.terminalCapitalCost);
    for (let i = 0; i < before.years.length; i++) {
      // O fluxo do ano não muda: só o desconto.
      expectClose(after.years[i]!.flow, before.years[i]!.flow, 1e-9);
      expectClose(after.years[i]!.rate, before.years[i]!.rate + 0.01, 1e-12);
    }
  });

  it('na via do acionista, o preço é proporcional ao lucro de partida', () => {
    const m = evaluate(inputs({ firm: false })).manual!;
    const p = m.enginePremises;
    const one = m.evaluate(p).unwrap().fairValuePerShare;
    const two = m.evaluate(p.copyWith({ baseProfit: p.baseProfit * 2 })).unwrap().fairValuePerShare;
    expectClose(two, 2 * one, 1e-9);
  });

  it('o lucro de partida é o do ano, em reais, nas duas vias', () => {
    const firm = evaluate(inputs()).manual!;
    const shareholder = evaluate(inputs({ firm: false })).manual!;
    expect(firm.enginePremises.baseProfit).toBe(firm.engineBase);
    expectClose(shareholder.enginePremises.baseProfit, shareholder.engineBase * shareholder.shares, 1e-9);
    // O último exercício publicado, sem a normalização: lucro líquido de
    // 900 × e na via do acionista.
    expect(shareholder.publishedBase).not.toBeNull();
    expect(shareholder.publishedBase! > 0).toBe(true);
  });

  it('o crescimento constante vale nos dez anos', () => {
    const m = synthetic();
    const p = m.enginePremises.copyWith({ growth: 0.08, growthPath: ManualGrowthPath.constant });
    const o = m.evaluate(p).unwrap();
    expect(o.years.every((y) => Math.abs(y.growth - 0.08) < 1e-12)).toBe(true);
  });
});

describe('as formas da perpetuidade', () => {
  it('a parcela fixa é Gordon com a mesma parcela, em fórmula fechada', () => {
    const r = 0.13;
    const g = 0.07;
    const gInf = 0.04;
    const b = 0.35;
    const m = synthetic({ rate: r });
    const p = m.enginePremises.copyWith({
      reinvestment: ManualReinvestment.fixedFraction,
      retention: b,
      growth: g,
      growthPath: ManualGrowthPath.constant,
      perpetualGrowth: gInf,
    });
    const o = m.evaluate(p).unwrap();
    expect(o.terminalKind).toBe(ManualTerminal.fixedFraction);
    // A conta à mão: lucro por papel de 1, dez anos a 7%, metade do ano.
    let vp = 0.0;
    let profit = 1.0;
    for (let t = 1; t <= 10; t++) {
      profit *= 1 + g;
      vp += (profit * (1 - b) * Math.sqrt(1 + r)) / Math.pow(1 + r, t);
    }
    const vt = (profit * (1 + gInf) * (1 - b)) / (r - gInf);
    vp += (vt * Math.sqrt(1 + r)) / Math.pow(1 + r, 10);
    expectClose(o.fairValuePerShare, vp, 1e-9);
    expect(o.years.every((y) => y.retention === b)).toBe(true);
  });

  it('a parcela fixa solta o crescimento do retorno', () => {
    // Retorno de 5% não financia crescer 30%: pelo retorno o motor confina,
    // com a parcela fixa não.
    const m = synthetic({ returnRate: 0.05 });
    const withGrowth = m.evaluate(m.enginePremises.copyWith({ growth: 0.3 })).unwrap();
    expect(withGrowth.notices.some((n) => n.kind === ManualNoticeKind.confinedGrowth)).toBe(true);
    expect(withGrowth.years[0]!.growth).toBeLessThan(0.3);
    const fixed = m
      .evaluate(
        m.enginePremises.copyWith({ growth: 0.3, reinvestment: ManualReinvestment.fixedFraction, retention: 0.4 }),
      )
      .unwrap();
    expect(fixed.years[0]!.growth).toBe(0.3);
    expect(fixed.notices.some((n) => n.kind === ManualNoticeKind.confinedGrowth)).toBe(false);
  });

  it('devolver a vantagem competitiva ao estado estacionário', () => {
    const m = synthetic({ advantage: 0.22 });
    expect(m.enginePremises.terminalReturn).toBe(0.22);
    const o = m.evaluate(m.enginePremises.copyWith({ terminalReturn: null })).unwrap();
    expect(o.terminalKind).toBe(ManualTerminal.neutral);
    // Neutro: lucro do ano 11 ÷ taxa.
    const profit10 = o.years[o.years.length - 1]!.profit / m.shares;
    expectClose(o.terminalValue / m.shares, (profit10 * (1 + 0.04)) / 0.13, 1e-9);
  });

  it('o capital novo acima da taxa dá valor ao crescimento perpétuo', () => {
    const m = synthetic();
    const price = (gInf: number, ronic: number | null): number =>
      m.evaluate(m.enginePremises.copyWith({ perpetualGrowth: gInf, terminalReturn: ronic })).unwrap().fairValuePerShare;
    // Com retorno de 25% sobre o capital novo, crescer mais vale mais.
    expect(price(0.06, 0.25)).toBeGreaterThan(price(0.04, 0.25));
    const neutral = m.evaluate(m.enginePremises.copyWith({ perpetualGrowth: 0.06 })).unwrap();
    expect(neutral.notices.some((n) => n.kind === ManualNoticeKind.neutralPerpetuity)).toBe(true);
  });
});

describe('as recusas nomeiam o campo', () => {
  const m = synthetic();
  const p = m.enginePremises;

  const field = (x: ManualPremises): string | null => {
    const f = m.evaluate(x).failureOrNull;
    return f instanceof InvalidInput ? f.field : null;
  };

  it('lucro de partida não positivo', () => {
    expect(field(p.copyWith({ baseProfit: 0 }))).toBe(ManualField.baseProfit.name);
  });

  it('parcela reinvestida de 100% ou mais', () => {
    expect(field(p.copyWith({ reinvestment: ManualReinvestment.fixedFraction, retention: 1.0 }))).toBe(
      ManualField.retention.name,
    );
  });

  it('taxa não positiva', () => {
    expect(field(p.copyWith({ discountRate: -0.01 }))).toBe(ManualField.discountRate.name);
  });

  it('perpetuidade de Gordon sem margem sobre o crescimento', () => {
    const f = m
      .evaluate(p.copyWith({ reinvestment: ManualReinvestment.fixedFraction, retention: 0.3, perpetualGrowth: 0.13 }))
      .failureOrNull;
    expect(f).toBeInstanceOf(InvalidInput);
    const i = f as InvalidInput;
    expect(i.field).toBe(ManualField.perpetualGrowth.name);
    expect(i.limit).toBe(DcfCalculator.minimumSpread);
    expectClose(i.actual, 0.0, 1e-12);
  });

  it('retorno do capital novo não positivo', () => {
    expect(field(p.copyWith({ terminalReturn: 0.0 }))).toBe(ManualField.terminalReturn.name);
  });
});

describe('onde você discorda do motor', () => {
  it('os degraus somam a diferença inteira', () => {
    const m = evaluate(inputs({ unlevered: 0.8 })).manual!;
    const p = m.enginePremises.copyWith({
      baseProfit: m.enginePremises.baseProfit * 1.2,
      growth: m.enginePremises.growth + 0.02,
      discountRate: m.enginePremises.discountRate - 0.01,
    });
    const steps = m.attribution(p);
    expect(
      steps.map((d) => {
        expect(d.groups).toHaveLength(1);
        return d.groups[0];
      }),
    ).toEqual([ManualGroup.profit, ManualGroup.growth, ManualGroup.rate]);
    const sum = steps.reduce((s, d) => s + d.delta!, 0.0);
    const yours = m.evaluate(p).unwrap().fairValuePerShare;
    expectClose(sum, yours - m.engineFairValue, 1e-9);
  });

  it('sem troca, nenhum degrau', () => {
    const m = synthetic();
    expect(m.attribution(m.enginePremises)).toHaveLength(0);
  });

  it('o grupo que sozinho não fecha a conta se soma ao seguinte', () => {
    // Taxa de 4,2% com o crescimento perpétuo de 4% do motor fica sem a
    // margem de 0,5 p.p.; com o perpétuo de 2% do usuário, fecha.
    const m = synthetic();
    const p = m.enginePremises.copyWith({
      reinvestment: ManualReinvestment.fixedFraction,
      retention: 0.3,
      discountRate: 0.042,
      perpetualGrowth: 0.02,
    });
    const steps = m.attribution(p);
    expect(steps[steps.length - 1]!.groups).toEqual([ManualGroup.rate, ManualGroup.perpetuity]);
    expect(steps[steps.length - 1]!.to).not.toBeNull();
  });
});

describe('o que o preço de hoje supõe', () => {
  it('a taxa que iguala o preço justo ao de mercado', () => {
    const m = evaluate(inputs({ unlevered: 0.8 })).manual!;
    const s = m.solve(ManualField.discountRate, m.enginePremises);
    expect(s.value).not.toBeNull();
    const price = m.evaluate(m.enginePremises.copyWith({ discountRate: s.value! })).unwrap().fairValuePerShare;
    expectClose(price, m.marketPrice, 1e-6);
  });

  it('o lucro de partida que o preço supõe, nas duas vias', () => {
    for (const firm of [true, false]) {
      const m = evaluate(inputs({ firm })).manual!;
      const s = m.solve(ManualField.baseProfit, m.enginePremises);
      expect(s.value).not.toBeNull();
      const price = m.evaluate(m.enginePremises.copyWith({ baseProfit: s.value! })).unwrap().fairValuePerShare;
      expectClose(price, m.marketPrice, 1e-6);
    }
  });

  it('sem solução, devolve o mais perto que o campo chega', () => {
    const m = synthetic();
    // Nenhum retorno do capital novo leva o preço a mil reais.
    const s = m.solve(ManualField.terminalReturn, m.enginePremises, { target: 1000 });
    expect(s.value).toBeNull();
    expect(s.closestValue).not.toBeNull();
    expect(s.closestPrice!).toBeLessThan(1000);
  });

  it('a resposta é determinística', () => {
    const m = evaluate(inputs()).manual!;
    const a = m.solve(ManualField.growth, m.enginePremises);
    const b = m.solve(ManualField.growth, m.enginePremises);
    expect(a.value).toBe(b.value);
    expect(a.closestValue).toBe(b.closestValue);
  });
});

describe('as premissas novas não mudam a produção', () => {
  it('sem caminho de crescimento, o planejado é o decaimento linear', () => {
    const a = new DcfAssumptions({ growthRate: 0.1, perpetualGrowth: 0.04, discountRate: 0.13 });
    for (let t = 1; t <= 10; t++) {
      expectClose(a.plannedGrowthAt(t), 0.1 - (0.06 * (t - 1)) / 9, 1e-15);
      expect(a.growthAt(t)).toBe(a.plannedGrowthAt(t));
    }
  });

  it('caminho de crescimento com tamanho errado é recusado', () => {
    const a = new DcfAssumptions({ growthRate: 0.05, perpetualGrowth: 0.04, discountRate: 0.13 }).copyWith({
      growthPath: [0.05, 0.05],
    });
    expect(DcfCalculator.shareholder({ baseProfit: 1, assumptions: a }).isErr).toBe(true);
  });

  it('a cópia com o retorno terminal nulo mantém todo o resto', () => {
    const a = new DcfAssumptions({
      growthRate: 0.05,
      perpetualGrowth: 0.04,
      discountRate: 0.13,
      terminalDiscountRate: 0.11,
      returnOnCapital: 0.2,
      terminalReturnOnCapital: 0.18,
      contractYearsAfterHorizon: 7,
      inflation: 0.04,
    }).copyWith({ fixedRetention: 0.3, growthPath: new Array<number>(10).fill(0.05) });
    const b = a.withTerminalReturnOnCapital(null);
    expect(b.terminalReturnOnCapital).toBeNull();
    expect(b.terminalDiscountRate).toBe(a.terminalDiscountRate);
    expect(b.contractYearsAfterHorizon).toBe(a.contractYearsAfterHorizon);
    expect(b.inflation).toBe(a.inflation);
    expect(b.fixedRetention).toBe(a.fixedRetention);
    expect(b.growthPath).toEqual(a.growthPath);
    expect(b.returnOnCapital).toBe(a.returnOnCapital);
  });
});
