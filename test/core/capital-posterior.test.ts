// O capital emitido depois do balanço entra no patrimônio da ponte (item B28).
//
// O patrimônio vem do último balanço publicado, e o divisor é a contagem que
// forma a cotação de hoje. Uma emissão entre as duas datas estava na contagem e
// não no patrimônio: o preço justo por papel saía subavaliado na proporção do
// capital captado.
import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  FundamentalsSnapshot,
  type JsonObject,
  Money,
  ScenarioBand,
  ShareIssue,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
  type ValuationResult,
} from '../../src/core';
import { day, evaluateAudited, expectClose } from './helpers';

const ticker = Ticker.parse('ABCD3');

const year = (y: number, scale: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(y, 12, 31),
    totalRevenue: 10000 * scale,
    ebit: 1800 * scale,
    ebitda: 2400 * scale,
    netIncome: 900 * scale,
    incomeBeforeTax: 1300 * scale,
    incomeTaxExpense: -400 * scale,
    interestExpense: 400,
    earningsPerShare: 0.9 * scale,
    cash: 200,
    shortTermDebt: 1000,
    longTermDebt: 3000,
    totalStockholderEquity: 6000 * scale,
    bookValuePerShare: 6.0 * scale,
    operatingCashFlow: 2000 * scale,
    nopat: 1188 * scale,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 1000,
    marketCap: 12000,
  });

function series(): FundamentalsSnapshot[] {
  const out: FundamentalsSnapshot[] = [];
  let scale = 1.0;
  for (let i = 12; i >= 0; i--) {
    out.push(year(2025 - i, scale));
    scale *= 1.05;
  }
  return out;
}

const inputs = (issuances: ShareIssue[] = [], bank = false): ValuationInputs =>
  new ValuationInputs({
    ticker,
    asOf: day(2026, 9, 9),
    fundamentals: series(),
    marketPrice: 12.0,
    capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
    declaredTerminalRiskFreeRate: 0.094,
    sectorKey: bank ? 'financeiro' : null,
    industry: bank ? 'Intermediários Financeiros / Bancos' : null,
    shareIssues: issuances,
  });

function evaluate(i: ValuationInputs): ValuationResult {
  const r = ValuationCascade.evaluate(i);
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap();
}

/** O papel da contagem que forma a cotação: `VM ÷ P` = 12.000 ÷ 12. */
const shares = 1000.0;

const issue = (y: number, m: number, d: number, reais: number, n: number, declared = true): ShareIssue =>
  new ShareIssue({ date: day(y, m, d), amount: Money.fromReais(reais), shares: n, declared });

const after = issue(2026, 4, 15, 1200, 100);

describe('a via da firma', () => {
  it('sem emissão, nada muda', () => {
    const a = evaluate(inputs());
    const b = evaluate(inputs([]));
    expectClose(b.fairValue.reais, a.fairValue.reais, 1e-9);
    expect(a.diagnostics!.postStatementCapital).toBeNull();
  });

  it('a emissão depois do balanço soma capital ÷ papéis ao preço justo', () => {
    const without = evaluate(inputs());
    const withInput = evaluate(inputs([after]));
    expect(withInput.model).toBe(ValuationModel.dcfFcff);
    // O preço justo é arredondado ao centavo no resultado.
    expectClose(withInput.fairValue.reais, without.fairValue.reais + 1200 / shares, 0.011);
    expectClose(withInput.diagnostics!.postStatementCapital!, 1200, 1e-9);
    expect(withInput.warnings.some((w) => w.includes('emitiu ações') && w.includes('31/12/2025'))).toBe(true);
  });

  it('a emissão antes do balanço já está nele, e a posterior à data não existia', () => {
    const without = evaluate(inputs());
    for (const outside of [issue(2025, 12, 31, 1200, 100), issue(2025, 6, 1, 1200, 100), issue(2026, 9, 10, 1200, 100)]) {
      const r = evaluate(inputs([outside]));
      expectClose(r.fairValue.reais, without.fairValue.reais, 1e-9, outside.date.toString());
      expect(r.diagnostics!.postStatementCapital).toBeNull();
    }
  });

  it('emissão sem valor ou sem ação não entra', () => {
    const without = evaluate(inputs());
    const r = evaluate(inputs([issue(2026, 3, 1, 0, 100), issue(2026, 3, 1, 500, 0), issue(2026, 3, 1, -5, 1)]));
    expectClose(r.fairValue.reais, without.fairValue.reais, 1e-9);
  });

  it('variação de capital sem declaração não entra, e é avisada', () => {
    // Desde 2023 o FRE não declara emissão por emissão: a variação do
    // capital não separa emissão de bonificação ou de troca de ações numa
    // reorganização, e somá-la erraria por fatores inteiros.
    const without = evaluate(inputs());
    const r = evaluate(inputs([issue(2026, 5, 19, 1200, 100, false)]));
    expectClose(r.fairValue.reais, without.fairValue.reais, 1e-9);
    expect(r.diagnostics!.postStatementCapital).toBeNull();
    expect(r.warnings.some((w) => w.includes('não foi somada') && w.includes('subavaliado em até'))).toBe(true);
  });

  it('o cenário base continua sendo o preço justo', () => {
    const withInput = evaluate(inputs([after]));
    const base = withInput.discreteScenarios?.get(ScenarioBand.base);
    expect(base).toBeDefined();
    expectClose(base!.reais, withInput.fairValue.reais, 0.011);
  });

  it('o rastro mostra o capital do balanço e soma o novo num passo seu', () => {
    const { ev } = evaluateAudited(inputs([after]));
    const steps = ev.calculations.flatMap((t) => t.intermediateSteps);
    expect(steps.some((p) => p.startsWith('Passo 4b'))).toBe(true);
    expect(Array.isArray(ev.inputPayload['shareIssues'])).toBe(true);
    const diag = ev.outputPayload['diagnostics'] as JsonObject;
    expectClose(diag['postStatementCapital'] as number, 1200, 1e-6);
  });
});

it('a via do acionista soma o mesmo por papel', () => {
  // O banco do teste da Porta 1: lucro de 12% sobre o patrimônio, sem dívida.
  const bank = (): FundamentalsSnapshot[] => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let y = 2012; y <= 2025; y++) {
      const profit = 0.12 * pl;
      pl += profit;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(y, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: y === 2012 ? null : profit,
          nopat: profit,
          ebit: profit * 1.4,
          longTermDebt: 0,
          marketCap: 20000,
        }),
      );
    }
    return points;
  };

  const run = (issuances: ShareIssue[]): ValuationResult =>
    evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 6, 30),
        fundamentals: bank(),
        marketPrice: 20.0,
        capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
        sectorKey: 'financeiro',
        industry: 'Intermediários Financeiros / Bancos',
        shareIssues: issuances,
      }),
    );

  const without = run([]);
  const withInput = run([after]);
  expect(withInput.model).toBe(ValuationModel.dcfEarnings);
  // `VM ÷ P` = 20.000 ÷ 20 = 1.000 papéis.
  expectClose(withInput.fairValue.reais, without.fairValue.reais + 1200 / 1000, 0.011);
  expectClose(withInput.diagnostics!.postStatementCapital!, 1200, 1e-9);
});
