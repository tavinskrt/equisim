import { describe, expect, it } from 'vitest';

import {
  AuditRecorder,
  type CalculationTrace,
  CapmInputs,
  CashTiming,
  type DateTime,
  DcfAssumptions,
  DcfCalculator,
  FundamentalsSnapshot,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  type ValuationResult,
} from '../../src/core';
import { day, expectClose } from './helpers';

/** Concessionária de energia com fluxo da firma sustentado. */
const history = (ticker: Ticker): FundamentalsSnapshot[] => {
  const out: FundamentalsSnapshot[] = [];
  for (let year = 2016; year <= 2025; year++) {
    const k = year - 2015;
    out.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(year, 12, 31),
        netIncome: 1000.0 * k,
        ebit: 1400.0 * k,
        ebitda: 1800.0 * k,
        incomeBeforeTax: 1300.0 * k,
        incomeTaxExpense: 300.0 * k,
        interestExpense: 120.0,
        operatingCashFlow: 1600.0 * k,
        freeCashFlow: 1200.0 * k,
        shortTermDebt: 400.0,
        longTermDebt: 1600.0,
        cash: 300.0,
        nopat: 1000.0 * k,
        sharesOutstanding: 1000.0,
        sharesOutstandingAsOf: 1000.0,
        marketCap: 20000.0,
        bookValuePerShare: 8.0 * k,
        enterpriseToEbitda: 6.0,
      }),
    );
  }
  return out;
};

const inputsFor = (
  ticker: Ticker,
  o: { end?: DateTime | null; sector?: string | null; subsector?: string | null } = {},
): ValuationInputs =>
  new ValuationInputs({
    ticker,
    asOf: day(2026, 9, 14),
    fundamentals: history(ticker),
    marketPrice: 20.0,
    capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055 }),
    projectionYears: 10,
    sectorKey: 'sector' in o ? o.sector : 'utilidade-publica',
    industry: 'subsector' in o ? o.subsector : 'Energia Elétrica / Energia Elétrica',
    concessionEnd: o.end ?? null,
  });

const ticker = Ticker.parse('TAEE11');

const inRange = (v: number, lo: number, hi: number, reason?: string): void => {
  expect(v >= lo && v <= hi, `${v} fora de [${lo}, ${hi}]${reason === undefined ? '' : ` (${reason})`}`).toBe(true);
};

describe('O terminal do contrato — decisão 88', () => {
  const assumptions = (returnRate: number, contract: number | null): DcfAssumptions =>
    new DcfAssumptions({
      growthRate: 0.045,
      perpetualGrowth: 0.045,
      discountRate: 0.12,
      returnOnCapital: returnRate,
      cashTiming: CashTiming.endOfYear,
      contractYearsAfterHorizon: contract,
    });
  const firm = (returnRate: number, contract: number | null): number =>
    DcfCalculator.firm({
      baseProfit: 1000,
      assumptions: assumptions(returnRate, contract),
      netDebt: 0,
      sharesOutstanding: 1,
    }).unwrap().fairValuePerShare;

  // A identidade verdadeira: com o capital rendendo exatamente o custo dele,
  // não há excedente a cortar, e o prazo não muda nada.
  for (const m of [0, 15, 40]) {
    it(`capital que rende o custo dele: contrato de ${m} anos além = perpétuo`, () => {
      const perpetual = firm(0.12, null);
      expectClose(firm(0.12, m), perpetual, perpetual * 1e-9);
    });
  }

  it('capital que rende mais que o custo: o contrato corta o excedente', () => {
    // O que a lente `metodo` apontou: `lucro_{N+1}/r` perpetua o excedente do
    // capital existente, e o contrato que acaba não o paga para sempre.
    const perpetual = firm(0.24, null);
    const atEnd = firm(0.24, 0);
    const far = firm(0.24, 15);
    const veryFar = firm(0.24, 400);
    expect(atEnd).toBeLessThan(far);
    expect(far).toBeLessThan(perpetual);
    expectClose(veryFar, perpetual, perpetual * 1e-6, 'contrato sem fim à vista é a perpetuidade');
  });

  it('capital que rende menos que o custo: o contrato devolve mais', () => {
    expect(firm(0.08, 0)).toBeGreaterThan(firm(0.08, null));
  });

  it('sem retorno utilizável, não há capital, e o terminal fica perpétuo', () => {
    expectClose(firm(0.0, 0), firm(0.0, null), 1e-9);
  });

  it('na rota derivada, o contrato longo tende à perpetuidade do acionista, e fica entre ela e o capital devolvido', () => {
    const terminal = (contract: number | null): number =>
      DcfCalculator.equityFromFirm({
        baseProfit: 1000,
        assumptions: assumptions(0.24, contract),
        netDebt: 2000,
        sharesOutstanding: 1,
        costOfDebt: 0.1,
        taxRate: 0.34,
        equityDiscountRate: 0.15,
        terminalEquityDiscountRate: 0.15,
      }).unwrap().terminalValue;
    const perpetual = terminal(null);
    const returned = terminal(0);
    expectClose(terminal(400), perpetual, Math.abs(perpetual) * 1e-6);
    const smaller = Math.min(returned, perpetual);
    const greater = Math.max(returned, perpetual);
    let previous = returned;
    for (const m of [5, 15, 30, 60]) {
      const v = terminal(m);
      inRange(v, smaller, greater, `${m} anos`);
      // Monótono no prazo, na direção do perpétuo.
      expect((v - previous) * (perpetual - returned)).toBeGreaterThanOrEqual(0);
      previous = v;
    }
  });

  it('na rota derivada, no contrato que acaba no horizonte, o terminal do acionista é o da firma menos a dívida', () => {
    const a = assumptions(0.24, 0);
    const firmR = DcfCalculator.firm({ baseProfit: 1000, assumptions: a, netDebt: 2000, sharesOutstanding: 1 }).unwrap();
    const derivedOutcome = DcfCalculator.equityFromFirm({
      baseProfit: 1000,
      assumptions: a,
      netDebt: 2000,
      sharesOutstanding: 1,
      costOfDebt: 0.1,
      taxRate: 0.34,
      equityDiscountRate: 0.15,
      terminalEquityDiscountRate: 0.15,
    }).unwrap();
    const debtAtN = 2000 * Math.pow(1.045, 10);
    expectClose(derivedOutcome.terminalValue, firmR.terminalValue - debtAtN, 1e-6);
  });
});

describe('O contrato encurta a projeção só quando acaba dentro dela', () => {
  it('anos até o fim, arredondados, e nunca abaixo de um', () => {
    expect(ValuationCascade.contractYears(inputsFor(ticker, { end: day(2030, 9, 14) }))).toBe(4);
    expect(ValuationCascade.contractYears(inputsFor(ticker, { end: day(2026, 10, 1) }))).toBe(1);
    expect(ValuationCascade.contractYears(inputsFor(ticker))).toBeNull();
    expect(
      ValuationCascade.contractYears(inputsFor(ticker, { end: day(2016, 2, 29) })),
      'contrato vencido no formulário não impõe horizonte',
    ).toBeNull();
    expect(
      ValuationCascade.contractYears(
        inputsFor(ticker, { end: day(2030, 9, 14), sector: 'bens-industriais', subsector: 'Máquinas e Equipamentos' }),
      ),
      'só concessão tem contrato',
    ).toBeNull();
  });

  it('dentro da projeção, o preço muda e o aviso diz até quando', () => {
    const full = ValuationCascade.evaluate(inputsFor(ticker)).unwrap();
    const short = ValuationCascade.evaluate(inputsFor(ticker, { end: day(2030, 9, 14) })).unwrap();
    expect(Math.abs(short.fairValue.cents - full.fairValue.cents)).toBeGreaterThan(0);
    expect(short.warnings.join(' ')).toContain('14/09/2030');
    expect(short.warnings.join(' ')).toContain('vai até lá, 4 anos');
  });

  it('depois da projeção, o preço fica entre o do contrato curto e o perpétuo', () => {
    const full = ValuationCascade.evaluate(inputsFor(ticker)).unwrap();
    const short = ValuationCascade.evaluate(inputsFor(ticker, { end: day(2036, 9, 14) })).unwrap();
    const longTerm = ValuationCascade.evaluate(inputsFor(ticker, { end: day(2047, 8, 11) })).unwrap();
    // **Entre os dois, na direção que o excedente do acionista dá** (decisão
    // 102). O capital próprio sai do fluxo do acionista derivado, ao `Ke`, e
    // o terminal do contrato é a perpetuidade truncada com o capital devolvido
    // no fim: o contrato longo fica entre o que acaba no horizonte e o
    // perpétuo. Se fica acima ou abaixo do perpétuo é o excedente do
    // acionista sobre o capital contábil que decide — e neste fixture, ao `Ke`
    // do CAPM, o capital devolvido vale mais que a perpetuidade, embora a
    // firma renda acima do WACC: sem taxas resolvidas, WACC e `Ke` não
    // conversam, e a ordem da firma não é a do acionista.
    const smaller = Math.min(short.fairValue.cents, full.fairValue.cents);
    const greater = Math.max(short.fairValue.cents, full.fairValue.cents);
    inRange(longTerm.fairValue.cents, smaller, greater);
    expect(short.fairValue.cents).not.toBe(full.fairValue.cents);
    expect(longTerm.warnings.join(' ')).toContain('anos depois da projeção');
  });

  it('fora de concessão, o fim declarado não faz nada', () => {
    const evaluate = (end: DateTime | null): ValuationResult =>
      ValuationCascade.evaluate(
        inputsFor(ticker, { end, sector: 'bens-industriais', subsector: 'Máquinas e Equipamentos / Motores' }),
      ).unwrap();
    expect(evaluate(day(2028, 1, 1)).fairValue.cents).toBe(evaluate(null).fairValue.cents);
  });

  it('sem prazo lido, o aviso diz o que se supõe e o que acontece se não', () => {
    const warning = ValuationCascade.evaluate(inputsFor(ticker)).unwrap().warnings.join(' ');
    expect(warning).toContain('o prazo não foi lido');
    expect(warning).toContain('excedente de retorno sobre o capital existente');
    expect(warning, 'a truncagem sem indenização não é a conta certa').not.toContain('0,80');
  });
});

describe('O rastro do terminal da concessão', () => {
  // Lente `metodo`, 21/09/2026. Com prazo, o terminal é
  // `capital_N + EVA·anuidade(M)` (decisão 88), e o rastro imprimia a
  // perpetuidade de Gordon — a mesma forma de defeito que a ponte `EV − D`
  // tinha antes da decisão 102: rastro que descreve outra conta é pior que
  // nenhum.
  const traceOf = (end: DateTime | null): CalculationTrace[] => {
    const captured: CalculationTrace[] = [];
    AuditRecorder.attach((e) => captured.push(...e.calculations));
    try {
      ValuationCascade.evaluate(inputsFor(Ticker.parse('TEST3'), { end }));
    } finally {
      AuditRecorder.detach();
    }
    return captured;
  };

  it('com prazo, o rastro traz o capital devolvido e a anuidade', () => {
    const step = traceOf(day(2040, 6, 30)).find((c) => c.formulaName.includes('Valor terminal'))!;
    expect(step.formulaName).toContain('contrato com prazo');
    expect(step.latexRepresentation).toContain('K_N');
    expect(step.mappedVariables['M (anos de contrato além de N)']).not.toBeUndefined();
    expect(step.mappedVariables['M (anos de contrato além de N)']).not.toBeNull();
    expect(step.intermediateSteps[0]).toContain('o capital volta');
    expect(step.latexRepresentation, 'a perpetuidade não é a conta que foi feita aqui').not.toContain(
      String.raw`\frac{L_{N+1}}{r_\infty}`,
    );
  });

  it('sem prazo, continua sendo a perpetuidade de retorno neutro', () => {
    const step = traceOf(null).find((c) => c.formulaName.includes('Valor terminal'))!;
    expect(step.formulaName).toContain('retorno neutro');
    expect(step.mappedVariables['M (anos de contrato além de N)'] ?? null).toBeNull();
  });
});
