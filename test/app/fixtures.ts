/**
 * Estado **populado** para montar as telas cheias — a porta do
 * `test/ui/populated_state.dart`.
 *
 * Uma captura de tela vazia não é só inútil para a crítica de direção visual:
 * é enganosa, porque leva a concluir que a interface está limpa quando o
 * conteúdo nunca apareceu. As fábricas aqui são determinísticas — a mesma
 * entrada dá sempre a mesma tela — e nada vai à rede.
 */
import {
  Asset,
  type BacktestOutcome,
  CapmInputs,
  ContributionPlan,
  DateRange,
  DateTime,
  FeasibilityLevel,
  FeasibilityReason,
  FeasibilityVerdict,
  FinancialGoal,
  FundamentalsSnapshot,
  GoalAlignment,
  MarketAnchors,
  Money,
  Portfolio,
  PortfolioBacktest,
  PortfolioKind,
  PricePoint,
  PriceSeries,
  RequiredReturn,
  ScenarioBand,
  ScenarioMode,
  Sector,
  Ticker,
  TransactionCosts,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
  ValuationResult,
} from '../../src/core';
import { PortfolioComparison } from '../../src/app/backtest';

export function assetOf(symbol: string, sector = 'financeiro'): Asset {
  return new Asset({ ticker: Ticker.parse(symbol), name: symbol, sector: Sector.fromKey(sector, { label: sector }) });
}

const range = new DateRange(DateTime.local(2024, 1, 1), DateTime.local(2024, 12, 31));

/** Série diária sintética: um pregão por dia útil a partir de [start]. */
export function seriesOf(symbol: string, start: DateTime, closes: readonly number[]): PriceSeries {
  const points: PricePoint[] = [];
  let date = start;
  for (const close of closes) {
    while (date.weekday === 6 || date.weekday === 7) date = DateTime.local(date.year, date.month, date.day + 1);
    points.push(new PricePoint({ date, close }));
    date = DateTime.local(date.year, date.month, date.day + 1);
  }
  return new PriceSeries({ ticker: Ticker.parse(symbol), points });
}

/** Backtest de uma carteira de um ativo só, sem custo — cem cotas exatas a R$ 10,00. */
export function outcomeOf(symbol: string, closes: readonly number[]): BacktestOutcome {
  const start = DateTime.local(2024, 1, 1);
  const portfolio = Portfolio.equalWeighted({
    id: symbol,
    name: symbol,
    kind: PortfolioKind.principal,
    assets: [assetOf(symbol)],
  }).unwrap();
  return PortfolioBacktest.run({
    portfolio,
    prices: new Map([[Ticker.parse(symbol), seriesOf(symbol, start, closes)]]),
    plan: new ContributionPlan({ initial: new Money(100000), monthly: Money.zero }),
    range: new DateRange(start, DateTime.local(2024, 12, 31)),
    costs: TransactionCosts.none,
  }).unwrap();
}

export function comparisonOf(args: { principal?: BacktestOutcome | null; reserve?: BacktestOutcome | null }): PortfolioComparison {
  return new PortfolioComparison({
    window: range,
    requestedWindow: range,
    principal: args.principal ?? null,
    reserve: args.reserve ?? null,
  });
}

/**
 * Série de 120 pregões com tendência e ondulação, em **centavos inteiros**:
 * a onda dá forma ao gráfico, e o determinismo deixa a captura comparável.
 */
export function curve(start: number, end: number, n = 120): number[] {
  const startCents = Math.round(start * 100);
  const endCents = Math.round(end * 100);
  const step = (endCents - startCents) / (n - 1);
  return Array.from({ length: n }, (_, i) => {
    const trend = startCents + step * i;
    const wave = (i % 17) * 11 - (i % 7) * 19;
    return (Math.round(trend) + wave) / 100.0;
  });
}

/**
 * Uma avaliação **de verdade**, saída da cascata (decisão 147): a edição do
 * valuation precisa da conta congelada, que só existe no resultado da cascata.
 *
 * - [firm]: via da firma (operacional) ou do acionista (operacional negativo).
 * - [shock]: multiplica o lucro do último exercício; abaixo de 1 o último ano
 *   destoa para baixo e o motor normaliza a base **para cima**.
 */
export function cascadeValuation(options: { firm?: boolean; shock?: number } = {}): ValuationResult {
  const firm = options.firm ?? true;
  const shock = options.shock ?? 1.0;
  const ticker = Ticker.parse(firm ? 'WEGE3' : 'ITUB4');
  const series: FundamentalsSnapshot[] = [];
  let e = 1.0;
  for (let i = 12; i >= 0; i--) {
    const y = 2025 - i;
    const k = i === 0 ? shock : 1.0;
    series.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: DateTime.local(y, 12, 31),
        totalRevenue: 10000e6 * e,
        ebit: (firm ? 1800e6 * k : -200e6) * e,
        ebitda: (firm ? 2400e6 : 300e6) * e,
        netIncome: 900e6 * e * (firm ? 1.0 : k),
        incomeBeforeTax: (firm ? 1300e6 : 1200e6) * e,
        incomeTaxExpense: (firm ? -400e6 : -300e6) * e,
        interestExpense: firm ? 400e6 : 50e6,
        earningsPerShare: 0.9 * e * (firm ? 1.0 : k),
        cash: firm ? 200e6 : 2000e6 * e,
        shortTermDebt: firm ? 1000e6 : 500e6,
        longTermDebt: firm ? 3000e6 : 500e6,
        totalStockholderEquity: 6000e6 * e,
        bookValuePerShare: 6.0 * e,
        operatingCashFlow: firm ? 2000e6 * e : null,
        nopat: firm ? 1188e6 * e * k : null,
        sharesOutstanding: 1000e6,
        sharesOutstandingAsOf: 1000e6,
        marketCap: 12000e6,
      }),
    );
    e *= i % 2 === 0 ? 1.04 : 1.06;
  }
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: DateTime.local(2026, 9, 9),
      fundamentals: series,
      marketPrice: 12.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
      declaredTerminalRiskFreeRate: 0.1,
      unleveredBeta: firm ? 0.8 : 0.9,
    }),
  );
  if (r.isErr) throw new Error(`a fixture da cascata não avaliou: ${r.failureOrNull!.message}`);
  return r.unwrap();
}

/** Avaliação com os três cenários discretos e a conta congelada da cascata. */
export function valuationOf(symbol: string, fairValue = 42.8, market = 33.15): ValuationResult {
  return new ValuationResult({
    ticker: Ticker.parse(symbol),
    asOf: DateTime.local(2024, 12, 31),
    model: ValuationModel.dcfEarnings,
    fairValue: Money.fromReais(fairValue),
    marketPrice: Money.fromReais(market),
    discountRate: 0.132,
    marginOfSafety: 0.2,
    mode: ScenarioMode.discrete,
    discreteScenarios: new Map([
      [ScenarioBand.bear, Money.fromReais(fairValue * 0.72)],
      [ScenarioBand.base, Money.fromReais(fairValue)],
      [ScenarioBand.bull, Money.fromReais(fairValue * 1.31)],
    ]),
    warnings: [],
    priceVolatility: 0.42,
    manual: cascadeValuation().manual,
  });
}

/** Veredito `demanding`: exercita o alerta e os números sem bloquear a tela. */
export function feasibility(): FeasibilityVerdict {
  return new FeasibilityVerdict({
    level: FeasibilityLevel.demanding,
    reason: FeasibilityReason.aboveMarket,
    requiredAnnualRate: 0.184,
    anchors: MarketAnchors.fallback2026,
  });
}

export function alignment(): GoalAlignment {
  return new GoalAlignment({
    required: new RequiredReturn({ monthly: 0.0142 }),
    expectedReturn: 0.1495,
    valuationCoverage: 0.75,
  });
}

/** Meta de demonstração: dez anos contra a janela padrão de cinco, de propósito. */
export const demoGoal = FinancialGoal.unvalidated({
  initialContribution: new Money(1000000),
  monthlyContribution: new Money(100000),
  months: 120,
  targetWealth: new Money(50000000),
});

/** A carteira de demonstração, com setores distintos. */
export const demoPortfolio: readonly (readonly [string, string])[] = [
  ['PETR4', 'energia'],
  ['VALE3', 'materiais'],
  ['ITUB4', 'financeiro'],
  ['WEGE3', 'industrial'],
];
