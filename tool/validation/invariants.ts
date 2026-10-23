import {
  Asset,
  ContributionPlan,
  DateRange,
  DateTime,
  FinancialGoal,
  Money,
  Portfolio,
  PortfolioBacktest,
  PortfolioKind,
  type PriceSeries,
  RequiredReturnSolver,
  Returns,
  str,
  Ticker,
  WealthPath,
  Weights,
} from '../../src/core';
import { num2, pct, type ValidationContext } from './context';

/** Resultado de uma verificação de invariante. */
export interface InvariantCheck {
  /** Nome da identidade verificada, como aparece no relatório. */
  readonly name: string;
  /** `true` quando a identidade se sustentou dentro da tolerância. */
  readonly passed: boolean;
  /**
   * Os números medidos e a tolerância aplicada. É o que permite conferir a
   * verificação em vez de acreditar nela.
   */
  readonly detail: string;
}

const singleAsset = (ticker: Ticker) =>
  Portfolio.equalWeighted({ id: 'p', name: 'P', kind: PortfolioKind.principal, assets: [new Asset({ ticker, name: ticker.value })] }).unwrap();

/**
 * Verificações de consistência interna do motor.
 *
 * **Por que estas e não um oráculo externo.** O plano original previa validar
 * o motor contra o `adjustedClose` da fonte. A auditoria mostrou que aquela
 * série ajusta proventos por um critério que diverge do fluxo publicado em
 * até 38,5%, o que a inviabiliza como referência (ver `PLANO_ARQUITETURA.md`
 * §0.4). O domínio não modela provento algum desde a decisão 023, e a
 * comparação deixou de fazer sentido também por esse lado.
 *
 * As invariantes abaixo substituem o oráculo descartado. Não dependem de
 * nenhuma fonte externa de verdade: são identidades matemáticas que o motor
 * **precisa** satisfazer. Uma falha aqui é prova de defeito, não indício.
 */
export const Invariants = {
  /**
   * Executa todas as invariantes e devolve um resultado por identidade.
   *
   * - [ctx]: contexto com a camada de dados do aplicativo.
   *
   * **Nunca lança e nunca interrompe no primeiro erro**: uma identidade que
   * falha vira `InvariantCheck` com `passed` falso, e as demais continuam. Um
   * relatório parcial esconderia se o defeito é isolado ou generalizado.
   *
   * As três últimas verificações são puramente aritméticas e dispensam rede;
   * as demais consomem dados reais e dependem do que o cache ou a fonte
   * entregam.
   */
  async runAll(ctx: ValidationContext, sample: readonly string[] = ['PETR4', 'ITUB4', 'WEGE3']): Promise<InvariantCheck[]> {
    const checks: InvariantCheck[] = [];
    const today = DateTime.now();
    const window = new DateRange(DateTime.local(today.year - 3, today.month, today.day), today);

    for (const symbol of sample) {
      const ticker = Ticker.parse(symbol);
      const priceResult = await ctx.prices.daily(ticker, window);
      if (priceResult.isErr) continue;
      const series = priceResult.unwrap();

      checks.push(capitalIsConserved(ticker, series, window), lumpSumXirrMatchesCagr(ticker, series, window), perAssetSumsToPortfolio(ticker, series, window));
    }

    checks.push(contributionsDoNotInflateTwr(), weightsAlwaysSumToOne(), requiredRateRoundTrip());
    return checks;
  },

  /**
   * Formata os resultados como relatório Markdown.
   *
   * - [checks]: saída de [runAll].
   *
   * Não decide nada: quem interpreta reprovação é o chamador.
   */
  report(checks: readonly InvariantCheck[]): string {
    const passed = checks.filter((c) => c.passed).length;
    const lines = [
      '# Invariantes do motor',
      '',
      `Gerado em ${DateTime.now().toIso8601String().slice(0, 19)}.`,
      '',
      'Estas verificações não dependem de fonte externa de verdade: são identidades que o motor precisa satisfazer. Substituem o ' +
        'oráculo `adjustedClose` descartado na auditoria (§0.4), que se mostrou inconsistente com o fluxo de proventos publicado em até ' +
        '38,5%. O domínio não modela provento desde a decisão 023.',
      '',
      `**Resultado: ${passed} de ${checks.length} aprovadas.**`,
      '',
      '| Invariante | Situação | Detalhe |',
      '|---|---|---|',
      ...checks.map((check) => `| ${check.name} | ${check.passed ? '✅' : '❌'} | ${check.detail} |`),
    ];
    return `${lines.join('\n')}\n`;
  },
};

/**
 * Nenhum centavo aportado desaparece: o que cada ativo recebeu soma o
 * aportado, e o que virou ação mais o caixa reconstitui o mesmo total.
 *
 * É a identidade mais forte disponível desde que a simulação passou a
 * comprar em lotes inteiros. Ela cobre de uma vez as duas formas de perder
 * dinheiro na alocação — resto de divisão não distribuído e fatia de ativo
 * sem cotação no dia — e é exata: opera em centavos inteiros, sem
 * tolerância.
 */
function capitalIsConserved(ticker: Ticker, series: PriceSeries, window: DateRange): InvariantCheck {
  const backtest = PortfolioBacktest.run({
    portfolio: singleAsset(ticker),
    prices: new Map([[ticker, series]]),
    plan: new ContributionPlan({
      initial: new Money(1000000), // R$ 10.000
      monthly: new Money(50000), // R$ 500
    }),
    range: window,
  });

  const name = `${ticker.value}: aportado ≡ alocado + caixa`;
  if (backtest.isErr) return { name, passed: false, detail: `backtest falhou: ${backtest.failureOrNull!.message}` };

  const outcome = backtest.unwrap();
  let allocated = 0;
  for (const asset of outcome.perAsset.values()) allocated += asset.invested.cents;
  const contributed = outcome.totalContributed.cents;
  const reconstituted = outcome.totalAllocated.cents + outcome.residualCash.cents;

  return {
    name,
    passed: allocated === contributed && reconstituted === contributed,
    detail:
      `aportado ${contributed}¢ · destinado ${allocated}¢ · alocado ${outcome.totalAllocated.cents}¢ + ` +
      `caixa ${outcome.residualCash.cents}¢ = ${reconstituted}¢`,
  };
}

/**
 * Com um único aporte no início e nenhum depois, a taxa interna dos fluxos
 * tem de coincidir com o CAGR — as duas medidas convergem quando não há
 * cronograma de aportes a diferenciar.
 */
function lumpSumXirrMatchesCagr(ticker: Ticker, series: PriceSeries, window: DateRange): InvariantCheck {
  const result = PortfolioBacktest.run({
    portfolio: singleAsset(ticker),
    prices: new Map([[ticker, series]]),
    plan: new ContributionPlan({ initial: new Money(1000000), monthly: Money.zero }),
    range: window,
  });

  const name = `${ticker.value}: aporte único ⇒ XIRR ≡ CAGR`;
  if (result.isErr) return { name, passed: false, detail: result.failureOrNull!.message };

  const metrics = result.unwrap().metrics;
  const xirr = metrics.moneyWeightedReturn;
  if (xirr === null) return { name, passed: false, detail: 'XIRR não convergiu' };

  const gap = Math.abs(xirr - metrics.cagr);
  return { name, passed: gap < 0.005, detail: `XIRR ${pct(xirr)} · CAGR ${pct(metrics.cagr)} · diferença ${pct(gap, 4)}` };
}

/**
 * A soma dos valores finais por ativo tem de reproduzir o patrimônio da
 * carteira. Detecta perda ou duplicação de capital na consolidação.
 */
function perAssetSumsToPortfolio(ticker: Ticker, series: PriceSeries, window: DateRange): InvariantCheck {
  const result = PortfolioBacktest.run({
    portfolio: singleAsset(ticker),
    prices: new Map([[ticker, series]]),
    plan: new ContributionPlan({ initial: new Money(500000), monthly: new Money(50000) }),
    range: window,
  });

  const name = `${ticker.value}: Σ ativos ≡ patrimônio da carteira`;
  if (result.isErr) return { name, passed: false, detail: result.failureOrNull!.message };

  const outcome = result.unwrap();
  // O caixa entra na soma: ele é patrimônio da carteira tanto quanto a
  // posição, e deixá-lo de fora faria a identidade falhar por construção.
  let sum = 0;
  for (const asset of outcome.perAsset.values()) sum += asset.finalValue.reais + asset.cash.reais;
  const gap = Math.abs(sum - outcome.finalValue.reais);

  return {
    name,
    passed: gap < 0.05,
    detail: `Σ ${num2(sum, 2)} · carteira ${num2(outcome.finalValue.reais, 2)} · diferença ${num2(gap, 4)}`,
  };
}

/**
 * Aporte que entra e não é investido não pode virar retorno.
 *
 * É a defesa contra o defeito mais comum em simuladores de carteira, e o
 * que motivou trocar CAGR sobre capital aportado por TWR.
 */
function contributionsDoNotInflateTwr(): InvariantCheck {
  const twr = Returns.timeWeighted(WealthPath.of({ values: [100, 10100, 10100], externalFlows: [100, 10000, 0] }).unwrap());
  return {
    name: 'Aporte não é confundido com retorno',
    passed: Math.abs(twr) < 1e-12,
    detail: `carteira parada que recebe R$ 10.000 rende ${pct(twr)} (esperado 0,00%)`,
  };
}

/**
 * A soma dos pesos tem de ser exatamente 1,0 para qualquer quantidade de
 * ativos, inclusive as que produzem dízima na divisão.
 */
function weightsAlwaysSumToOne(): InvariantCheck {
  const failures: number[] = [];
  for (let n = 1; n <= Portfolio.maxAssets; n++) {
    const tickers = Array.from({ length: n }, (_, i) => Ticker.parse(`AAAA${i}`));
    const sum = Weights.sum(Weights.equal(tickers).values());
    if (Math.abs(sum - 1.0) > 1e-12) failures.push(n);
  }
  return {
    name: 'Pesos equiponderados somam exatamente 100%',
    passed: failures.length === 0,
    detail: failures.length === 0 ? `verificado de 1 a ${Portfolio.maxAssets} ativos` : `falhou com [${failures.join(', ')}] ativos`,
  };
}

/**
 * A taxa resolvida, realimentada na equação de valor futuro, tem de
 * reproduzir a meta.
 */
function requiredRateRoundTrip(): InvariantCheck {
  const cases = [
    { initial: 10000.0, monthly: 1000.0, months: 120, target: 300000.0 },
    { initial: 0.0, monthly: 500.0, months: 60, target: 40000.0 },
    { initial: 50000.0, monthly: 0.0, months: 36, target: 80000.0 },
  ];

  const errors: string[] = [];
  for (const c of cases) {
    const goal = FinancialGoal.unvalidated({
      initialContribution: Money.fromReais(c.initial),
      monthlyContribution: Money.fromReais(c.monthly),
      months: c.months,
      targetWealth: Money.fromReais(c.target),
    });
    const solved = RequiredReturnSolver.solve(goal);
    if (solved.isErr) {
      errors.push(`${str(c.target)}: ${solved.failureOrNull!.message}`);
      continue;
    }
    const fv = RequiredReturnSolver.futureValue({ rate: solved.unwrap().monthly, initial: c.initial, monthly: c.monthly, months: c.months });
    const gap = Math.abs(fv - c.target);
    if (gap > 0.01) errors.push(`${str(c.target)}: erro de ${num2(gap)}`);
  }

  return {
    name: 'Rentabilidade requerida reproduz a meta (ida e volta)',
    passed: errors.length === 0,
    detail: errors.length === 0 ? `${cases.length} casos com erro abaixo de R$ 0,01` : errors.join(' · '),
  };
}
