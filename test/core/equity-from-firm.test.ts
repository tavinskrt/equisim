/**
 * A identidade entre as duas rotas para o capital próprio.
 *
 * `DcfCalculator.equityFromFirm` não é uma segunda opinião sobre o valor: é a
 * mesma avaliação por um caminho que não passa pela subtração `EV − D`. O que
 * prova isso é a identidade, e é o que estes testes verificam:
 *
 * ```
 * FCFE_{N+1} = FCFF_{N+1} − D·[Kd(1−τ) − g] = E·(Ke − g)
 * ```
 *
 * Ela exige que o `WACC` tenha sido montado com os pesos `E/V` e `D/V` **do
 * próprio modelo**. Aqui isso é construído de propósito; em produção o peso do
 * equity vem do valor de mercado, e o resíduo daí é medido em
 * `docs/validacao/`.
 */
import { describe, expect, it } from 'vitest';

import { CashTiming, DcfAssumptions, DcfCalculator, type DcfOutcome, type Result } from '../../src/core';
import { expectClose } from './helpers';

describe('Identidade FCFF/WACC ≡ FCFE/Ke sob alavancagem constante', () => {
  /**
   * Monta o par consistente: dado `E`, `D`, `Ke` e `Kd`, devolve o `WACC`
   * que a estrutura de capital implica. É a única forma de a identidade
   * poder valer — com peso de mercado ela não vale, e é esse o achado.
   */
  const waccOf = (o: { equity: number; debt: number; ke: number; kd: number; tax: number }): number => {
    const v = o.equity + o.debt;
    return o.ke * (o.equity / v) + o.kd * (1 - o.tax) * (o.debt / v);
  };

  it('as duas rotas coincidem quando a alavancagem é de fato constante', () => {
    // **Sem crescimento**, e é o ponto: com `g = 0` a dívida não cresce, o
    // valor não cresce, e `D/V` é constante em todo ano da projeção. É a
    // única configuração em que a identidade pode valer — ver o teste
    // seguinte, que mede o que acontece quando ela não vale.
    const kd = 0.11;
    const tax = 0.3;
    const ke = 0.155;
    const g = 0.0;
    const base = 1000.0;
    const debt = 3000.0;
    const securities = 100.0;

    // Ponto fixo: parte de um `E` arbitrário, calcula o WACC que ele implica,
    // avalia, e repete até o `E` do modelo ser o `E` do peso. É a
    // circularidade do WACC resolvida por iteração — três dezenas de passos
    // bastam para o resíduo cair abaixo de um centavo.
    let equity = 5000.0;
    let firm: DcfOutcome | undefined;
    for (let i = 0; i < 60; i++) {
      const wacc = waccOf({ equity, debt, ke, kd, tax });
      const r = DcfCalculator.firm({
        baseProfit: base,
        assumptions: new DcfAssumptions({
          projectionYears: 10,
          growthRate: g,
          perpetualGrowth: g,
          discountRate: wacc,
          terminalDiscountRate: wacc,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.endOfYear,
        }),
        netDebt: debt,
        sharesOutstanding: securities,
      });
      expect(r.isOk, r.failureOrNull?.message).toBe(true);
      firm = r.unwrap();
      equity = firm.equityValue;
    }

    const wacc = waccOf({ equity, debt, ke, kd, tax });
    const shareholder = DcfCalculator.equityFromFirm({
      baseProfit: base,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: g,
        perpetualGrowth: g,
        discountRate: wacc,
        terminalDiscountRate: wacc,
        returnOnCapital: 0.0,
        cashTiming: CashTiming.endOfYear,
      }),
      netDebt: debt,
      sharesOutstanding: securities,
      costOfDebt: kd,
      taxRate: tax,
      equityDiscountRate: ke,
      terminalEquityDiscountRate: ke,
    });
    expect(shareholder.isOk, shareholder.failureOrNull?.message).toBe(true);

    const byFirm = firm!.fairValuePerShare;
    const byShareholder = shareholder.unwrap().fairValuePerShare;
    // Uma parte em dez mil: o que sobra é o ponto fixo não ter convergido a
    // zero absoluto, não discordância de método.
    expect(
      Math.abs(byShareholder / byFirm - 1),
      `firma R$ ${byFirm} contra acionista R$ ${byShareholder}`,
    ).toBeLessThan(1e-4);
  });

  it('sem dívida as duas rotas são a mesma conta', () => {
    const ke = 0.15;
    const a = new DcfAssumptions({
      projectionYears: 10,
      growthRate: 0.04,
      perpetualGrowth: 0.04,
      discountRate: ke,
      terminalDiscountRate: ke,
      returnOnCapital: 0.0,
    });
    const firm = DcfCalculator.firm({ baseProfit: 500, assumptions: a, netDebt: 0, sharesOutstanding: 50 }).unwrap();
    const shareholder = DcfCalculator.equityFromFirm({
      baseProfit: 500,
      assumptions: a,
      netDebt: 0,
      sharesOutstanding: 50,
      costOfDebt: 0.11,
      taxRate: 0.3,
      equityDiscountRate: ke,
      terminalEquityDiscountRate: ke,
    }).unwrap();
    expectClose(shareholder.fairValuePerShare, firm.fairValuePerShare, 1e-9);
  });

  it('a alavancagem instável quebra a identidade, e o quanto é medido', () => {
    // **O achado de A2.** Com `g > 0` a dívida cresce a `g`, mas o valor da
    // firma **não** cresce a `g` — a estrutura terminal faz `V` crescer a
    // outra taxa. Resultado: `D/V` muda ao longo da projeção, e o `WACC`
    // montado com os pesos do ano zero deixa de descrever os anos seguintes.
    //
    // Medido neste caso: no ano 10 o `E/V` do modelo é 0,62 contra os 0,71
    // com que o `WACC` foi construído, e as duas rotas divergem 4,2%.
    //
    // O conserto exige uma de duas coisas, e as duas são decisão nova:
    // amarrar a dívida ao **valor** em vez da base de capital, ou realavancar
    // o `Ke` ano a ano — que é onde o beta desalavancado da decisão 40 passa
    // a ser indispensável.
    const kd = 0.11;
    const tax = 0.3;
    const ke = 0.155;
    const g = 0.05;
    const debt = 3000.0;

    const waccFor = (equity: number): number => {
      const v = equity + debt;
      return ke * (equity / v) + kd * (1 - tax) * (debt / v);
    };

    let equity = 5000.0;
    let firm: DcfOutcome | undefined;
    let wacc = 0.0;
    for (let i = 0; i < 80; i++) {
      wacc = waccFor(equity);
      firm = DcfCalculator.firm({
        baseProfit: 1000,
        assumptions: new DcfAssumptions({
          projectionYears: 10,
          growthRate: g,
          perpetualGrowth: g,
          discountRate: wacc,
          terminalDiscountRate: wacc,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.endOfYear,
        }),
        netDebt: debt,
        sharesOutstanding: 100,
      }).unwrap();
      equity = firm.equityValue;
    }

    const shareholder = DcfCalculator.equityFromFirm({
      baseProfit: 1000,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: g,
        perpetualGrowth: g,
        discountRate: wacc,
        terminalDiscountRate: wacc,
        returnOnCapital: 0.0,
        cashTiming: CashTiming.endOfYear,
      }),
      netDebt: debt,
      sharesOutstanding: 100,
      costOfDebt: kd,
      taxRate: tax,
      equityDiscountRate: ke,
      terminalEquityDiscountRate: ke,
    }).unwrap();

    const divergence = shareholder.fairValuePerShare / firm!.fairValuePerShare - 1;
    // Trava a ordem de grandeza, não o número: o que importa é que a
    // divergência existe e é material, e que ela some no teste anterior.
    expect(Math.abs(divergence), 'sem alavancagem constante a identidade não fecha').toBeGreaterThan(0.01);
    expect(Math.abs(divergence), 'e o desvio é de poucos por cento, não de método').toBeLessThan(0.1);
  });

  it('recusa quando o Ke de equilíbrio não supera o crescimento', () => {
    const r = DcfCalculator.equityFromFirm({
      baseProfit: 100,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: 0.06,
        perpetualGrowth: 0.119,
        discountRate: 0.14,
        terminalDiscountRate: 0.12,
        returnOnCapital: 0.0,
        cashTiming: CashTiming.endOfYear,
      }),
      netDebt: 100,
      sharesOutstanding: 10,
      costOfDebt: 0.11,
      taxRate: 0.3,
      equityDiscountRate: 0.14,
      terminalEquityDiscountRate: 0.12,
    });
    expect(r.isErr).toBe(true);
  });
});

describe('o juro e o rendimento do caixa seguem a curva (item B24)', () => {
  const a = new DcfAssumptions({
    projectionYears: 5,
    growthRate: 0.03,
    perpetualGrowth: 0.03,
    discountRate: 0.12,
    terminalDiscountRate: 0.12,
    returnOnCapital: 0.0,
    cashTiming: CashTiming.endOfYear,
  });
  const run = (o: { kd?: number[]; cash?: number[]; kdInf?: number; cashInf?: number } = {}): Result<DcfOutcome> =>
    DcfCalculator.equityFromFirm({
      baseProfit: 1000,
      assumptions: a,
      netDebt: 2000,
      sharesOutstanding: 100,
      costOfDebt: 0.12,
      taxRate: 0.34,
      equityDiscountRate: 0.15,
      terminalEquityDiscountRate: 0.15,
      cash: 500,
      cashYield: 0.1,
      costOfDebtPath: o.kd ?? null,
      cashYieldPath: o.cash ?? null,
      terminalCostOfDebt: o.kdInf ?? null,
      terminalCashYield: o.cashInf ?? null,
    });

  it('caminho constante é a taxa única', () => {
    const single = run().unwrap().equityValue;
    const path = run({
      kd: new Array<number>(5).fill(0.12),
      cash: new Array<number>(5).fill(0.1),
      kdInf: 0.12,
      cashInf: 0.1,
    }).unwrap().equityValue;
    expectClose(path, single, 1e-6);
  });

  it('juro mais alto no caminho baixa o capital próprio', () => {
    const single = run().unwrap().equityValue;
    const high = run({
      kd: [0.15, 0.14, 0.13, 0.12, 0.12],
      cash: new Array<number>(5).fill(0.1),
      kdInf: 0.12,
      cashInf: 0.1,
    }).unwrap().equityValue;
    expect(high).toBeLessThan(single);
  });

  it('o terminal usa a taxa de equilíbrio, e não a do ano 1', () => {
    const single = run().unwrap().equityValue;
    const lowTerminal = run({ kdInf: 0.09 }).unwrap().equityValue;
    expect(lowTerminal).toBeGreaterThan(single);
  });

  it('caminho de tamanho errado é recusado', () => {
    expect(run({ kd: [0.12, 0.12] }).isErr).toBe(true);
  });
});
