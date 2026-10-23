import { describe, expect, it } from 'vitest';

import {
  Asset,
  type BacktestOutcome,
  ContributionPlan,
  DateRange,
  type DateTime,
  Duration,
  InsufficientData,
  Money,
  Portfolio,
  PortfolioBacktest,
  PortfolioKind,
  PricePoint,
  PriceSeries,
  Sector,
  Ticker,
  TransactionCosts,
} from '../../src/core';
import { day, expectClose } from './helpers';

/**
 * Constrói uma série diária sintética a partir de uma lista de fechamentos,
 * um pregão por dia útil a partir de [start].
 */
const seriesOf = (symbol: string, start: DateTime, closes: readonly number[]): PriceSeries => {
  const points: PricePoint[] = [];
  let date = start;
  for (const close of closes) {
    while (date.weekday === 6 || date.weekday === 7) {
      date = date.add(new Duration({ days: 1 }));
    }
    points.push(new PricePoint({ date, close }));
    date = date.add(new Duration({ days: 1 }));
  }
  return new PriceSeries({ ticker: Ticker.parse(symbol), points });
};

const assetOf = (symbol: string, sectorKey = 'financeiro'): Asset =>
  new Asset({ ticker: Ticker.parse(symbol), name: symbol, sector: Sector.fromKey(sectorKey, { label: sectorKey }) });

const portfolioOf = (...symbols: string[]): Portfolio =>
  Portfolio.equalWeighted({
    id: 'p',
    name: 'Principal',
    kind: PortfolioKind.principal,
    assets: symbols.map((s) => assetOf(s)),
  }).unwrap();

const filled = (n: number, v: number): number[] => new Array<number>(n).fill(v);
const pricesOf = (entries: [string, PriceSeries][]): Map<Ticker, PriceSeries> =>
  new Map(entries.map(([s, p]) => [Ticker.parse(s), p]));
const sumCents = (values: Iterable<number>): number => {
  let total = 0;
  for (const v of values) total += v;
  return total;
};

const start = day(2024, 1, 1);

describe('PortfolioBacktest', () => {
  it('ativo único que dobra: patrimônio dobra e TWR é 100%', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4'),
      prices: pricesOf([['PETR4', seriesOf('PETR4', start, [10, 15, 20])]]),
      plan: new ContributionPlan({
        initial: new Money(100000), // R$ 1.000
        monthly: Money.zero,
      }),
      range: new DateRange(start, day(2024, 12, 31)),
    });

    expect(result.isOk).toBe(true);
    const outcome = result.unwrap();
    expectClose(outcome.finalValue.reais, 2000.0, 0.01);
    expectClose(outcome.metrics.timeWeightedReturn, 1.0, 1e-9);
    expectClose(outcome.base100[outcome.base100.length - 1], 200.0, 1e-6);
    // R$ 1.000 a R$ 10 compra exatamente 100 ações e não deixa troco.
    expect(outcome.perAsset.get(Ticker.parse('PETR4'))!.shares).toBe(100);
    expect(outcome.residualCash.cents).toBe(Money.zero.cents);
  });

  it('sem rebalanceamento, os pesos derivam com o mercado', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3'),
      prices: pricesOf([
        ['PETR4', seriesOf('PETR4', start, [10, 15, 20])],
        ['VALE3', seriesOf('VALE3', start, [10, 10, 10])],
      ]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: Money.zero }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    // R$ 500 em cada; PETR4 dobra para R$ 1.000, VALE3 fica em R$ 500.
    const petr = result.perAsset.get(Ticker.parse('PETR4'))!;
    const vale = result.perAsset.get(Ticker.parse('VALE3'))!;

    expectClose(petr.targetWeight.value, 0.5, 1e-9);
    expectClose(petr.currentWeight, 2 / 3, 1e-6);
    expectClose(vale.currentWeight, 1 / 3, 1e-6);
    expect(petr.drift).toBeGreaterThan(0);
    expect(vale.drift).toBeLessThan(0);
    expectClose(result.finalValue.reais, 1500.0, 0.01);
  });

  it('desempenho individual por ativo é reportado', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3'),
      prices: pricesOf([
        ['PETR4', seriesOf('PETR4', start, [10, 15, 20])],
        ['VALE3', seriesOf('VALE3', start, [10, 9, 8])],
      ]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: Money.zero }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    expectClose(result.perAsset.get(Ticker.parse('PETR4'))!.totalReturn, 1.0, 1e-6);
    expectClose(result.perAsset.get(Ticker.parse('VALE3'))!.totalReturn, -0.2, 1e-6);
  });

  it('aportes mensais entram no fluxo de caixa e no capital aportado', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4'),
      prices: pricesOf([['PETR4', seriesOf('PETR4', start, filled(120, 10.0))]]),
      plan: new ContributionPlan({
        initial: new Money(100000), // R$ 1.000
        monthly: new Money(50000), // R$ 500
        contributionDay: 5,
      }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    // Preço constante: patrimônio deve igualar exatamente o aportado.
    expectClose(result.finalValue.reais, result.totalContributed.reais, 0.01);
    // E o retorno tem de ser zero, apesar dos aportes.
    expectClose(result.metrics.timeWeightedReturn, 0.0, 1e-9);
  });

  // ----------------------------------------- Ações inteiras e caixa --

  it('compra em lotes inteiros e guarda a sobra em caixa', () => {
    // Preço de R$ 30 contra aporte de R$ 100: cabem 3 ações e sobram R$ 10.
    // No aporte seguinte o caixa acumulado passa a R$ 110, que compra mais 3
    // e deixa R$ 20 — é a acumulação que o modelo promete.
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4'),
      prices: pricesOf([['PETR4', seriesOf('PETR4', start, filled(120, 30.0))]]),
      plan: new ContributionPlan({
        initial: new Money(10000), // R$ 100
        monthly: new Money(10000), // R$ 100
        contributionDay: 5,
      }),
      range: new DateRange(start, day(2024, 4, 30)),
    }).unwrap();

    const petr = result.perAsset.get(Ticker.parse('PETR4'))!;
    // Quatro aportes de R$ 100 (janeiro entra pelo inicial; fevereiro, março
    // e abril pelo mensal) → R$ 400, que a R$ 30 dá 13 ações e R$ 10 de
    // caixa.
    expect(result.totalContributed.cents).toBe(40000);
    expect(petr.shares).toBe(13);
    expect(petr.cash.cents).toBe(1000);
    expect(result.residualCash.cents).toBe(1000);
    // Patrimônio = 13 × R$ 30 + R$ 10 de caixa = R$ 400, o aportado cheio.
    expect(result.finalValue.cents).toBe(40000);
  });

  it('a quantidade de ações é inteira em toda posição', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3', 'ITUB4'),
      prices: pricesOf([
        ['PETR4', seriesOf('PETR4', start, filled(120, 37.41))],
        ['VALE3', seriesOf('VALE3', start, filled(120, 8.03))],
        ['ITUB4', seriesOf('ITUB4', start, filled(120, 66.9))],
      ]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: new Money(50000), contributionDay: 5 }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    for (const asset of result.perAsset.values()) {
      // Inteira de fato — o `number` do JavaScript não garante isso pelo
      // tipo, como o `int` do Dart garantia —, nenhuma posição negativa, e o
      // caixa de cada ativo menor que uma ação: caixa maior significaria
      // compra que deixou de acontecer.
      expect(Number.isInteger(asset.shares)).toBe(true);
      expect(asset.shares).toBeGreaterThanOrEqual(0);
      expect(asset.cash.cents).toBeGreaterThanOrEqual(0);
    }
    expect(result.perAsset.get(Ticker.parse('PETR4'))!.cash.cents).toBeLessThan(3741);
    expect(result.perAsset.get(Ticker.parse('VALE3'))!.cash.cents).toBeLessThan(803);
    expect(result.perAsset.get(Ticker.parse('ITUB4'))!.cash.cents).toBeLessThan(6690);
  });

  it('o aportado se reparte inteiro entre os ativos, sem resíduo', () => {
    // Três ativos: os pesos de `equalWeighted` são 1/3, e a divisão em
    // centavos não fecha por conta própria. O motor distribui o resto, então
    // a soma das fatias tem de reconstituir o aporte EXATAMENTE.
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3', 'ITUB4'),
      prices: pricesOf(
        ['PETR4', 'VALE3', 'ITUB4'].map((s): [string, PriceSeries] => [s, seriesOf(s, start, filled(120, 10.0))]),
      ),
      plan: new ContributionPlan({
        initial: new Money(100000), // R$ 1.000
        monthly: new Money(50000), // R$ 500
        contributionDay: 5,
      }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    // Em CENTAVOS e com igualdade: o contrato é identidade, não aproximação.
    // `Money` é inteiro, então comparar por igualdade aqui é exato.
    const allocatedSum = sumCents([...result.perAsset.values()].map((a) => a.invested.cents));
    expect(allocatedSum).toBe(result.totalContributed.cents);

    // O alocado é o que virou ação; o resto está em caixa, e os dois juntos
    // reconstituem o aportado sem sobra nem falta.
    expect(result.totalAllocated.plus(result.residualCash).cents).toBe(result.totalContributed.cents);

    const cashSum = sumCents([...result.perAsset.values()].map((a) => a.cash.cents));
    expect(cashSum).toBe(result.residualCash.cents);
  });

  it('o patrimônio final é a soma exata das posições e do caixa', () => {
    // Em CENTAVOS e com igualdade. A marcação a mercado opera em aritmética
    // inteira — posição inteira vezes preço em centavos —, então esta
    // identidade não admite tolerância: qualquer folga aqui significaria
    // acúmulo de erro de ponto flutuante ao longo dos pregões.
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3', 'ITUB4'),
      prices: pricesOf([
        ['PETR4', seriesOf('PETR4', start, filled(120, 37.41))],
        ['VALE3', seriesOf('VALE3', start, filled(120, 8.03))],
        ['ITUB4', seriesOf('ITUB4', start, filled(120, 66.9))],
      ]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: new Money(50000), contributionDay: 5 }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    const sum = sumCents([...result.perAsset.values()].map((a) => a.finalValue.cents + a.cash.cents));
    expect(sum).toBe(result.finalValue.cents);
  });

  it('a fatia de ativo sem cotação no dia fica em caixa e é usada depois', () => {
    // VALE3 só começa a ser negociada dois dias depois. A fatia dela no
    // aporte inicial não some: espera no caixa e vira posição no primeiro
    // aporte em que há preço.
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3'),
      prices: pricesOf([
        ['PETR4', seriesOf('PETR4', start, filled(120, 10.0))],
        ['VALE3', seriesOf('VALE3', start.add(new Duration({ days: 40 })), filled(80, 10.0))],
      ]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: new Money(50000), contributionDay: 5 }),
      // A janela começa no primeiro pregão comum, então a simulação inteira
      // tem preço para os dois; o que se verifica é a identidade de capital.
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    expect(result.totalAllocated.plus(result.residualCash).cents).toBe(result.totalContributed.cents);
    expect(result.residualCash.cents).toBeGreaterThanOrEqual(0);
  });

  it('com um ativo só e preço divisor, não sobra caixa', () => {
    // Peso 1,0 não reparte, e R$ 1.000 e R$ 500 são múltiplos de R$ 10: a
    // sobra tem de ser exatamente zero. É a contraprova do teste acima —
    // sem ela, um caixa sistematicamente inflado passaria.
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4'),
      prices: pricesOf([['PETR4', seriesOf('PETR4', start, filled(120, 10.0))]]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: new Money(50000), contributionDay: 5 }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    expect(result.totalAllocated.cents).toBe(result.totalContributed.cents);
    expect(result.residualCash.cents).toBe(0);
  });

  it('encurta o período e avisa quando um ativo é mais novo', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4', 'VALE3'),
      prices: pricesOf([
        ['PETR4', seriesOf('PETR4', start, [10, 10, 10, 10, 10])],
        ['VALE3', seriesOf('VALE3', start.add(new Duration({ days: 2 })), [10, 10, 10])],
      ]),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: Money.zero }),
      range: new DateRange(start, day(2024, 12, 31)),
    }).unwrap();

    expect(result.warnings.length).toBeGreaterThan(0);
    expect(result.warnings[0]).toContain('Período encurtado');
  });

  it('rejeita carteira sem cotações', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4'),
      prices: new Map(),
      plan: new ContributionPlan({ initial: new Money(100000), monthly: Money.zero }),
      range: new DateRange(start, day(2024, 12, 31)),
    });
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('rejeita plano sem aporte algum', () => {
    const result = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio: portfolioOf('PETR4'),
      prices: pricesOf([['PETR4', seriesOf('PETR4', start, [10, 11])]]),
      plan: new ContributionPlan({ initial: Money.zero, monthly: Money.zero }),
      range: new DateRange(start, day(2024, 12, 31)),
    });
    expect(result.isErr).toBe(true);
  });
});

describe('O mês não perde o aporte por um dia que não existe nele', () => {
  // Lente `nucleo`, 21/09/2026. O aporte saía no primeiro pregão com
  // `dia >= contributionDay`. Com dia 30, fevereiro não tem pregão que
  // satisfaça a condição, e o aporte do mês sumia **em silêncio** — o
  // patrimônio e o TWR de toda a simulação saíam de um cronograma que
  // ninguém pediu.
  const portfolio = portfolioOf('PETR4');

  const contributions = (contributionDay: number): number => {
    // Ano bissexto de propósito: fevereiro de 2024 acaba no dia 29.
    const series = seriesOf('PETR4', day(2024, 1, 2), filled(90, 10.0));
    const r = PortfolioBacktest.run({
      costs: TransactionCosts.none,
      portfolio,
      prices: pricesOf([['PETR4', series]]),
      plan: new ContributionPlan({ initial: Money.zero, monthly: new Money(100000), contributionDay }),
      range: new DateRange(day(2024, 1, 2), day(2024, 4, 30)),
    });
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    return Math.trunc(r.unwrap().totalContributed.cents / 100000);
  };

  it('dia 5 e dia 30 aportam o mesmo número de vezes', () => {
    expect(contributions(30)).toBe(contributions(5));
  });

  it('nenhum mês da janela fica sem aporte', () => {
    // Janeiro, fevereiro, março e abril: quatro meses, quatro aportes.
    expect(contributions(30)).toBe(4);
    expect(contributions(31)).toBe(4);
  });
});

describe('custo de transação (item C4)', () => {
  // Um ativo a R$ 10,00, aporte inicial de R$ 1.000,00, sem mensal: sem
  // custo compraria 100 ações exatas; com a tarifa da B3 (0,030%), cem ações
  // custariam R$ 1.000,30, e a simulação compra 99.
  const t = Ticker.parse('ABCD3');
  const asset = new Asset({ ticker: t, name: 'ABCD', sector: Sector.unknown });
  const portfolio = Portfolio.equalWeighted({ id: 'p', name: 'P', kind: PortfolioKind.principal, assets: [asset] }).unwrap();
  const days: DateTime[] = [];
  for (let d = 2; d <= 31; d++) days.push(day(2024, 1, d));
  const prices = new Map([
    [t, new PriceSeries({ ticker: t, points: days.map((d) => new PricePoint({ date: d, close: 10.0 })) })],
  ]);
  const plan = new ContributionPlan({ initial: new Money(100000), monthly: Money.zero, contributionDay: 1 });
  const run = (c: TransactionCosts): BacktestOutcome =>
    PortfolioBacktest.run({
      portfolio,
      prices,
      plan,
      range: new DateRange(days[0]!, days[days.length - 1]!),
      costs: c,
    }).unwrap();

  it('a tarifa sai do caixa e a compra respeita o que sobra', () => {
    const r = run(TransactionCosts.b3);
    expect(r.perAsset.get(t)!.shares).toBe(99);
    // 99 × R$ 10,00 = R$ 990,00; tarifa de 0,030% = R$ 0,297 → R$ 0,30.
    expect(r.transactionCosts.cents).toBe(30);
    expect(r.totalAllocated.cents).toBe(99000);
    expect(r.residualCash.cents).toBe(970);
  });

  it('aportado = alocado + custos + caixa, ao centavo', () => {
    for (const c of [
      TransactionCosts.none,
      TransactionCosts.b3,
      new TransactionCosts({ feePartsPerMillion: 2500, brokeragePerOrder: new Money(490) }),
    ]) {
      const r = run(c);
      expect(
        r.totalAllocated.plus(r.transactionCosts).plus(r.residualCash).cents,
        `tarifa ${c.feePartsPerMillion} ppm, corretagem ${c.brokeragePerOrder.cents} centavos`,
      ).toBe(r.totalContributed.cents);
      expect(r.residualCash.cents).toBeGreaterThanOrEqual(0);
    }
  });

  it('sem custo, a simulação é a de antes do C4', () => {
    const r = run(TransactionCosts.none);
    expect(r.perAsset.get(t)!.shares).toBe(100);
    expect(r.transactionCosts.cents).toBe(0);
  });

  it('a corretagem só é cobrada em ordem que compra', () => {
    // R$ 1.000,00 de corretagem não deixa comprar nada — e não é cobrada.
    const r = run(new TransactionCosts({ brokeragePerOrder: new Money(100000) }));
    expect(r.perAsset.get(t)!.shares).toBe(0);
    expect(r.transactionCosts.cents).toBe(0);
    expect(r.residualCash.cents).toBe(100000);
  });

  it('a tarifa arredonda meio para cima no centavo', () => {
    const b3 = TransactionCosts.b3;
    expect(b3.feeCents(99000)).toBe(30); // 29,7 centavos
    expect(b3.feeCents(5000)).toBe(2); // 1,5 centavo
    expect(b3.feeCents(4999)).toBe(1); // 1,4997
    expect(b3.orderCents(0)).toBe(0);
  });
});
