import { describe, expect, it } from 'vitest';

import { Duration, FundamentalsSnapshot, PointInTimeView, Ticker } from '../../src/core';
import { day, expectClose } from './helpers';

const petr = Ticker.parse('PETR4');

const snapshotFor = (year: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({ ticker: petr, fiscalPeriodEnd: day(year, 12, 31), earningsPerShare: year - 2000.0 });

const at2025 = (fields: Partial<ConstructorParameters<typeof FundamentalsSnapshot>[0]>): FundamentalsSnapshot =>
  new FundamentalsSnapshot({ ticker: petr, fiscalPeriodEnd: day(2025, 12, 31), ...fields });

describe('PointInTimeView', () => {
  const history = [snapshotFor(2023), snapshotFor(2024), snapshotFor(2025)];

  it('exercício recém-encerrado ainda não é público', () => {
    // Em 15/01/2026 o balanço de 31/12/2025 não foi divulgado à CVM.
    const view = new PointInTimeView(day(2026, 1, 15));
    const visibleOnes = view.published(history);
    expect(visibleOnes.length).toBeGreaterThan(0);
    expect(visibleOnes[visibleOnes.length - 1]!.fiscalPeriodEnd.year).toBe(2024);
  });

  it('após a defasagem de 90 dias o exercício passa a ser visível', () => {
    const view = new PointInTimeView(day(2026, 6, 30));
    const visible = view.published(history);
    expect(visible[visible.length - 1]!.fiscalPeriodEnd.year).toBe(2025);
  });

  it('defasagem é parâmetro declarado e altera o recorte', () => {
    const withoutLag = new PointInTimeView(day(2026, 1, 15), { publicationLag: Duration.zero });
    const visible = withoutLag.published(history);
    expect(visible[visible.length - 1]!.fiscalPeriodEnd.year).toBe(2025);
  });

  it('devolve nada quando nenhum exercício era público', () => {
    const view = new PointInTimeView(day(2020, 1, 1));
    expect(view.published(history)).toEqual([]);
  });

  it('o recorte respeita a barreira', () => {
    const view = new PointInTimeView(day(2026, 1, 15));
    const range = view.published(history);
    expect(range.length).toBe(2);
    expect(range[range.length - 1]!.fiscalPeriodEnd.year).toBe(2024);
    expect(range.every((s) => view.isPublished(s))).toBe(true);
  });
});

describe('Fundamentos derivados', () => {
  it('D&A sai de EBITDA menos EBIT', () => {
    expectClose(at2025({ ebit: 100, ebitda: 140 }).depreciationAndAmortization!, 40, 1e-12);
  });

  it('alíquota efetiva é limitada para conter exercícios atípicos', () => {
    // **A fonte grava a despesa com sinal negativo.** Conferido pela
    // identidade no cache: lucro líquido = lucro antes + incomeTaxExpense.
    // O teste seguia a convenção oposta, e passava porque `effectiveTaxRate`
    // tirava o módulo — os dois erros se cancelavam, e o cancelamento
    // escondia que crédito tributário virava imposto a pagar.
    expectClose(at2025({ incomeBeforeTax: 1000, incomeTaxExpense: -340 }).effectiveTaxRate!, 0.34, 1e-12);
    expect(at2025({ incomeBeforeTax: 100, incomeTaxExpense: -900 }).effectiveTaxRate).toBe(0.5);
  });

  it('crédito tributário produz alíquota nula, não imposto a pagar', () => {
    // Campo positivo é crédito. Com o módulo, isto devolvia 0,20 e cobrava
    // imposto de quem recuperou imposto.
    expect(at2025({ incomeBeforeTax: 1000, incomeTaxExpense: 200 }).effectiveTaxRate).toBe(0.0);
  });

  it('prejuízo antes de impostos não produz alíquota', () => {
    expect(at2025({ incomeBeforeTax: -500, incomeTaxExpense: 10 }).effectiveTaxRate).toBeNull();
  });

  it('dívida líquida desconta caixa e aplicações', () => {
    const snapshot = at2025({ shortTermDebt: 200, longTermDebt: 800, cash: 300, shortTermInvestments: 100 });
    expect(snapshot.totalDebt).toBe(1000);
    expect(snapshot.totalCash).toBe(400);
    expect(snapshot.netDebt).toBe(600);
  });

  it('custo da dívida implícito', () => {
    expectClose(at2025({ shortTermDebt: 200, longTermDebt: 800, interestExpense: 110 }).costOfDebt!, 0.11, 1e-12);
  });

  it('campos ausentes devolvem nulo em vez de zero silencioso', () => {
    const isEmptyValue = at2025({});
    expect(isEmptyValue.depreciationAndAmortization).toBeNull();
    expect(isEmptyValue.effectiveTaxRate).toBeNull();
    expect(isEmptyValue.costOfDebt).toBeNull();
  });
});
