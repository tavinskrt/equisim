// A taxa de cada ano segue a curva também sem o custo de capital resolvido
// (item B37), e o rastro descreve a conta que foi feita (item B35).
//
// Sem o ponto fixo — o banco, que não realavanca, e o recuo de quem não tem
// beta desalavancado — o desconto interpolava em linha reta do CDI de hoje até
// o forward depois do ano N, e o aviso dizia que a taxa seguia a curva. O
// rastro da via da firma montava o fator com o `WACC` e mostrava ao lado o
// valor presente do fluxo do acionista, descontado ao `Ke`.
import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  CurveVertex,
  DcfAssumptions,
  DcfCalculator,
  FundamentalsSnapshot,
  Ticker,
  ValuationInputs,
  ValuationModel,
  YieldCurve,
} from '../../src/core';
import { day, evaluateAudited, expectClose, traceStep } from './helpers';

const today = day(2026, 9, 14);

/** Curva com inclinação: 14% no primeiro ano, 12% no longo. */
const curve = YieldCurve.of(today, [new CurveVertex(1, 0.14), new CurveVertex(3, 0.13), new CurveVertex(10, 0.12)])!;

/** O banco do teste da Porta 1: lucro de 12% sobre o patrimônio, sem dívida. */
function bankHistory(t: Ticker): FundamentalsSnapshot[] {
  const points: FundamentalsSnapshot[] = [];
  let pl = 1000.0;
  for (let year = 2012; year <= 2025; year++) {
    const profit = (year % 2 === 0 ? 0.11 : 0.13) * pl;
    pl += profit;
    points.push(
      new FundamentalsSnapshot({
        ticker: t,
        fiscalPeriodEnd: day(year, 12, 31),
        bookValuePerShare: pl / 1000,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        netIncome: profit,
        nopat: profit,
        ebit: profit * 1.4,
        longTermDebt: 0,
        marketCap: 20000,
      }),
    );
  }
  return points;
}

/**
 * Companhia não financeira da via da firma, sem beta desalavancado — o custo de
 * capital não é resolvido.
 */
const fiscalYear = (t: Ticker, year: number, scale: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: day(year, 12, 31),
    totalRevenue: 10000 * scale,
    ebit: 1400 * scale,
    ebitda: 1900 * scale,
    netIncome: 700 * scale,
    incomeBeforeTax: 1000 * scale,
    incomeTaxExpense: -300 * scale,
    interestExpense: 120,
    earningsPerShare: 0.7 * scale,
    cash: 500,
    shortTermInvestments: 200,
    shortTermDebt: 400,
    longTermDebt: 1600,
    totalStockholderEquity: 6000 * scale,
    bookValuePerShare: 6.0 * scale,
    operatingCashFlow: 1500 * scale,
    freeCashFlow: 900 * scale,
    nopat: 924 * scale,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 1000,
    marketCap: 10000,
  });

const firmHistory = (t: Ticker): FundamentalsSnapshot[] => {
  const out: FundamentalsSnapshot[] = [];
  for (let i = 15; i >= 0; i--) out.push(fiscalYear(t, 2025 - i, Math.pow(1.05, 15 - i)));
  return out;
};

const capm = new CapmInputs({ riskFreeRate: 0.15, beta: 1.0, marketPremium: 0.055 });
const fw = curve.annualForwards(10);
const num = (v: unknown): number => v as number;

describe('Sem resolução, a taxa de cada ano é a da curva (B37)', () => {
  const bank = (c: YieldCurve | null = null): ValuationInputs =>
    new ValuationInputs({
      ticker: Ticker.parse('BANC3'),
      asOf: today,
      fundamentals: bankHistory(Ticker.parse('BANC3')),
      marketPrice: 20.0,
      capm,
      sectorKey: 'financeiro',
      industry: 'Intermediários Financeiros / Bancos',
      riskFreeCurve: c,
      declaredTerminalRiskFreeRate: 0.1,
    });

  it('o banco desconta o ano 1 ao forward do ano 1, e não ao CDI', () => {
    const { r } = evaluateAudited(bank(curve));
    expect(r.model).toBe(ValuationModel.dcfEarnings);
    expectClose(r.discountRate, fw[0]! + 0.055, 1e-12);
    expect(Math.abs(r.discountRate - capm.costOfEquity)).toBeGreaterThan(1e-6);
  });

  it('o rastro do banco mostra o K_e de cada ano sobre o forward', () => {
    const { ev } = evaluateAudited(bank(curve));
    const d = traceStep(ev, 'Projeção e desconto do período explícito');
    expectClose(num(d.mappedVariables['K_e,1 (% a.a.)']), (fw[0]! + 0.055) * 100, 0.006);
    expectClose(num(d.mappedVariables['K_e,N (% a.a.)']), (fw[fw.length - 1]! + 0.055) * 100, 0.006);
    const term = traceStep(ev, 'Estrutura a termo');
    expect(term.intermediateSteps[0]).toContain('forward');
  });

  it('sem curva, vale a interpolação da corrente à estrutural', () => {
    expectClose(evaluateAudited(bank()).r.discountRate, capm.costOfEquity, 1e-12);
  });

  it('a via da firma sem beta desalavancado desconta ao K_e da curva', () => {
    const t = Ticker.parse('FIRM3');
    const { ev } = evaluateAudited(
      new ValuationInputs({
        ticker: t,
        asOf: today,
        fundamentals: firmHistory(t),
        marketPrice: 10.0,
        capm,
        riskFreeCurve: curve,
        declaredTerminalRiskFreeRate: 0.1,
      }),
    );
    const d = traceStep(ev, 'Fluxo do acionista e desconto ao K_e');
    expectClose(num(d.mappedVariables['K_e,1 (% a.a.)']), (fw[0]! + 0.055) * 100, 0.006);
    expectClose(num(d.mappedVariables['K_e,N (% a.a.)']), (fw[fw.length - 1]! + 0.055) * 100, 0.006);
    const bridge = traceStep(ev, 'Capital próprio pelo fluxo do acionista');
    expect(bridge.mappedVariables['desconto']).toContain('forward');
  });
});

describe('O rastro da via da firma fecha com a conta (B35)', () => {
  const t = Ticker.parse('FIRM3');
  const inputs = new ValuationInputs({
    ticker: t,
    asOf: today,
    fundamentals: firmHistory(t),
    marketPrice: 10.0,
    capm,
    riskFreeCurve: curve,
    declaredTerminalRiskFreeRate: 0.1,
    unleveredBeta: 0.8,
  });

  it('explícito e terminal do rastro são os que a ponte soma', () => {
    const a = evaluateAudited(inputs);
    const explicitValue = traceStep(a.ev, 'Fluxo do acionista e desconto ao K_e');
    const terminal = traceStep(a.ev, 'Valor terminal (');
    const bridge = traceStep(a.ev, 'Capital próprio pelo fluxo do acionista');
    expect(terminal.formulaName).toContain('convertido para o acionista');
    expectClose(num(bridge.mappedVariables['VP do fluxo explícito do acionista (R$)']), explicitValue.finalValue!, 0.006);
    expectClose(num(bridge.mappedVariables['VP do terminal do acionista (R$)']), terminal.finalValue!, 0.006);
    expectClose(bridge.finalValue, a.r.fairValue.reais, 0.006);
    // A projeção da firma vem antes, e não desconta nada.
    expect(a.ev.calculations.some((c) => c.formulaName === 'Projeção do fluxo da firma (NOPAT)')).toBe(true);
  });

  it('o desfecho expõe as taxas que descontaram cada fluxo', () => {
    const assumptions = new DcfAssumptions({
      projectionYears: 5,
      growthRate: 0.08,
      perpetualGrowth: 0.04,
      discountRate: 0.14,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.2,
    });
    const ke = [0.18, 0.175, 0.17, 0.165, 0.16];
    const o = DcfCalculator.equityFromFirm({
      baseProfit: 1000,
      assumptions,
      netDebt: 2000,
      sharesOutstanding: 100,
      costOfDebt: 0.16,
      taxRate: 0.34,
      equityDiscountRate: ke[0]!,
      terminalEquityDiscountRate: 0.155,
      equityDiscountRatePath: ke,
      cash: 500,
      cashYield: 0.14,
    }).unwrap();
    expect(o.discountRates).toEqual(ke);
    expect(o.terminalDiscountRateUsed).toBe(0.155);
    let factor = 1.0;
    for (let i = 0; i < 5; i++) {
      factor *= 1 + ke[i]!;
      // O fluxo do acionista é o da firma menos o serviço da dívida.
      expectClose(o.projectedFlows[i]!, o.firmFlows![i]! - o.debtService![i]!, 1e-9);
      // «fluxo × levantamento ÷ fator» dá o valor presente escrito ao lado.
      expectClose(o.discountedFlows[i]!, (o.projectedFlows[i]! * Math.sqrt(1 + ke[i]!)) / factor, 1e-9);
    }
    expectClose(o.terminalEquityFlow!, o.terminalFirmFlow! - o.terminalDebtService!, 1e-9);
    expectClose(o.terminalValue, o.terminalEquityFlow! / (0.155 - 0.04), 1e-6);
    expectClose(o.discountedTerminalValue, (o.terminalValue * Math.sqrt(1.155)) / factor, 1e-6);
  });
});
