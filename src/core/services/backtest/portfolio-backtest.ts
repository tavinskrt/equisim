import type { Portfolio } from '../../entities/portfolio';
import type { PriceSeries } from '../../entities/price-series';
import { InsufficientData, InvalidInput } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import type { DateTime } from '../../lang/date-time';
import { compareNum, floor, intDiv, isNegative } from '../../lang/num';
import { DateRange } from '../../value-objects/date-range';
import { Money } from '../../value-objects/money';
import { WealthPathBuilder } from '../../value-objects/paired-series';
import type { Ticker } from '../../value-objects/ticker';
import type { Weight } from '../../value-objects/weight';
import { CashFlow, Returns } from '../metrics/returns';
import { RiskMetrics } from '../metrics/risk-metrics';

/** Cronograma de aportes do plano. */
export class ContributionPlan {
  /** Aporte inicial (V₀). */
  readonly initial: Money;

  /** Aporte mensal (PMT). */
  readonly monthly: Money;

  /**
   * Dia do mês do aporte.
   *
   * **Dia que não existe no mês não perde o aporte** (lente `nucleo`,
   * 21/09/2026): o aporte sai no primeiro pregão a partir do dia pedido e,
   * se o mês acabar antes — fevereiro com dia 30, ou dia 31 caindo em fim de
   * semana —, no **último pregão do mês**. Perder calado o aporte de
   * fevereiro falseava o patrimônio e o TWR de toda simulação com dia acima
   * de 28.
   */
  readonly contributionDay: number;

  /** Declara o cronograma. */
  constructor(args: { initial: Money; monthly: Money; contributionDay?: number }) {
    this.initial = args.initial;
    this.monthly = args.monthly;
    this.contributionDay = args.contributionDay ?? 5;
  }

  /** `true` quando há aporte mensal estritamente positivo. */
  get hasMonthly(): boolean {
    return this.monthly.isPositive;
  }
}

/** Desempenho individual de um ativo dentro da carteira. */
export class AssetPerformance {
  /** Ativo a que este desempenho se refere. */
  readonly ticker: Ticker;

  /** Peso estipulado na constituição da carteira. */
  readonly targetWeight: Weight;

  /**
   * Peso corrente ao final do período — difere do alvo porque **não há
   * rebalanceamento**, e essa deriva é sinal de decisão, não defeito.
   */
  readonly currentWeight: number;

  /**
   * Retorno do ativo no período, apurado sobre [invested] contra o valor de
   * mercado da posição **mais** o caixa que sobrou dela.
   *
   * Deixar o caixa de fora puniria o ativo por dinheiro que continua sendo
   * dele e vale exatamente o que custou.
   */
  readonly totalReturn: number;

  /**
   * Capital destinado ao ativo ao longo do período, tenha ele virado posição
   * ou ficado em caixa. A soma sobre os ativos reconstitui
   * [BacktestOutcome.totalContributed] exatamente.
   */
  readonly invested: Money;

  /** Valor de mercado da posição no último pregão do período. */
  readonly finalValue: Money;

  /**
   * Caixa do ativo ao final: o que sobrou de cada aporte por não completar
   * mais uma ação inteira, acumulado e reaplicado nos aportes seguintes.
   */
  readonly cash: Money;

  /**
   * Quantidade de papéis ao final. **Inteira**: a simulação compra lotes de
   * uma ação, como a corretora faz, e nunca fraciona.
   */
  readonly shares: number;

  /** Agrupa o desempenho já apurado. */
  constructor(args: {
    ticker: Ticker;
    targetWeight: Weight;
    currentWeight: number;
    totalReturn: number;
    invested: Money;
    finalValue: Money;
    cash: Money;
    shares: number;
  }) {
    this.ticker = args.ticker;
    this.targetWeight = args.targetWeight;
    this.currentWeight = args.currentWeight;
    this.totalReturn = args.totalReturn;
    this.invested = args.invested;
    this.finalValue = args.finalValue;
    this.cash = args.cash;
    this.shares = args.shares;
  }

  /** Diferença entre peso corrente e alvo, em pontos percentuais. */
  get drift(): number {
    return (this.currentWeight - this.targetWeight.value) * 100;
  }
}

/**
 * Conjunto de métricas de desempenho de uma carteira.
 *
 * Todas as métricas de risco são apuradas sobre a série **TWR em base 100**
 * (`BacktestOutcome.base100`), nunca sobre a curva bruta de patrimônio — ver
 * [RiskMetrics] para o motivo.
 */
export class PerformanceMetrics {
  /**
   * Retorno acumulado do período, neutralizado de aportes (TWR).
   *
   * É **a** métrica para comparar duas composições de carteira: não premia
   * nem pune a carteira pelo cronograma de aportes. Para o retorno que o
   * investidor efetivamente obteve, use [moneyWeightedReturn].
   */
  readonly timeWeightedReturn: number;

  /**
   * XIRR — retorno efetivo do investidor, o número a confrontar com a meta.
   *
   * `null` quando a taxa não pôde ser isolada: menos de dois fluxos, ausência
   * de fluxo positivo ou negativo, ou falha de convergência do solver.
   */
  readonly moneyWeightedReturn: number | null;

  /** CAGR derivado do TWR, anualizado sobre o período efetivo em base 365,25. */
  readonly cagr: number;

  /** Desvio-padrão amostral anualizado dos retornos diários, em fração. */
  readonly volatility: number;

  /** Pior queda de pico a vale da série TWR, em fração **negativa**. */
  readonly maxDrawdown: number;

  /** (CAGR − taxa livre de risco) / volatilidade. Zero quando a volatilidade é nula. */
  readonly sharpe: number;

  /** Como [sharpe], mas dividido apenas pelo semidesvio negativo. */
  readonly sortino: number;

  /** CAGR / |máximo drawdown|. Zero quando não houve drawdown. */
  readonly calmar: number;

  /**
   * Agrupa as métricas já apuradas. Não calcula nada — o cálculo vive em
   * [PortfolioBacktest.run].
   */
  constructor(args: {
    timeWeightedReturn: number;
    moneyWeightedReturn: number | null;
    cagr: number;
    volatility: number;
    maxDrawdown: number;
    sharpe: number;
    sortino: number;
    calmar: number;
  }) {
    this.timeWeightedReturn = args.timeWeightedReturn;
    this.moneyWeightedReturn = args.moneyWeightedReturn;
    this.cagr = args.cagr;
    this.volatility = args.volatility;
    this.maxDrawdown = args.maxDrawdown;
    this.sharpe = args.sharpe;
    this.sortino = args.sortino;
    this.calmar = args.calmar;
  }
}

/**
 * Custo de transação das compras da simulação (item C4).
 *
 * **Tudo em inteiro.** A tarifa é proporcional ao valor negociado e vem em
 * partes por milhão — 300 é 0,030% —, para que `valor × tarifa` seja conta de
 * inteiros e o arredondamento seja um só, meio para cima, no centavo. A
 * corretagem é fixa por ordem executada, e só é cobrada quando a ordem compra
 * ao menos uma ação.
 */
export class TransactionCosts {
  /** Tarifa sobre o valor negociado, em partes por milhão. */
  readonly feePartsPerMillion: number;

  /** Corretagem por ordem executada. */
  readonly brokeragePerOrder: Money;

  /** Declara os custos. Os dois precisam ser não negativos. */
  constructor(args: { feePartsPerMillion?: number; brokeragePerOrder?: Money } = {}) {
    this.feePartsPerMillion = args.feePartsPerMillion ?? 0;
    this.brokeragePerOrder = args.brokeragePerOrder ?? Money.zero;
  }

  /** Sem custo — a simulação de antes do item C4, para comparação. */
  static readonly none = new TransactionCosts();

  /**
   * Tarifa da B3 para ações à vista, pessoa física: negociação de 0,005% e
   * liquidação de 0,025%. Corretagem zero, que é o que as corretoras de varejo
   * cobram em ações desde 2019.
   *
   * **É o padrão da simulação.** O spread de compra e venda não entra: a
   * simulação compra ao fechamento, e o investidor que manda ordem a mercado
   * paga meio spread a mais — medido nas coortes em 0,4% a 1,7% por ponta,
   * conforme a liquidez (`docs/validacao/custos_transacao.md`). Aqui ele é
   * declarado, e não somado: um único número para todas as carteiras seria
   * falsa precisão.
   */
  static readonly b3 = new TransactionCosts({ feePartsPerMillion: 300 });

  /** Tarifa, em centavos, sobre [tradedCents] negociados — meio para cima. */
  feeCents(tradedCents: number): number {
    return intDiv(tradedCents * this.feePartsPerMillion + 500000, 1000000);
  }

  /** Custo total de uma ordem de [tradedCents]: tarifa e corretagem. */
  orderCents(tradedCents: number): number {
    return tradedCents <= 0 ? 0 : this.feeCents(tradedCents) + this.brokeragePerOrder.cents;
  }
}

/** Resultado da simulação de uma carteira. */
export class BacktestOutcome {
  /**
   * Período **efetivamente** simulado, que pode ser mais curto que o pedido
   * quando algum ativo não tem histórico desde o início. O encurtamento é
   * registrado em [warnings].
   */
  readonly effectivePeriod: DateRange;

  /**
   * Calendário mestre: união dos pregões de todos os ativos, ordenado.
   * Alinhado posição a posição com [wealth] e [base100].
   */
  readonly dates: readonly DateTime[];

  /**
   * Patrimônio dia a dia — posições marcadas a mercado **mais** o caixa —,
   * incluindo os aportes.
   *
   * Somar o caixa é o que garante que nenhum centavo aportado desapareça da
   * curva enquanto espera para completar uma ação inteira.
   */
  readonly wealth: readonly number[];

  /**
   * Índice TWR em base 100 — é esta a curva que alimenta risco, porque a
   * curva de patrimônio salta no dia do aporte.
   */
  readonly base100: readonly number[];

  /** Capital aportado no período, somando inicial e mensais. */
  readonly totalContributed: Money;

  /**
   * Capital que virou posição: o valor pago pelas ações efetivamente
   * compradas, e portanto `totalContributed − transactionCosts −
   * residualCash` por construção.
   */
  readonly totalAllocated: Money;

  /**
   * Tarifa e corretagem pagas nas compras (item C4).
   *
   * Sai do caixa de cada ativo antes da compra, e por isso a identidade
   * `aportado = alocado + custos + caixa` fecha ao centavo.
   */
  readonly transactionCosts: Money;

  /** Patrimônio no último pregão: posições a mercado mais [residualCash]. */
  readonly finalValue: Money;

  /**
   * Caixa parado ao final da simulação, somado sobre os ativos.
   *
   * É a fração de cada aporte que não completou mais uma ação inteira. Ela
   * fica disponível para o aporte seguinte, então o saldo ao final é sempre
   * menor que a soma dos preços unitários da carteira — um valor alto
   * significa papel caro diante do aporte, não capital perdido.
   */
  readonly residualCash: Money;

  /** Métricas consolidadas de retorno e risco. */
  readonly metrics: PerformanceMetrics;

  /** Desempenho por ativo, indexado por ticker. */
  readonly perAsset: ReadonlyMap<Ticker, AssetPerformance>;

  /** Avisos: séries encurtadas ou ativos sem dados no período. */
  readonly warnings: readonly string[];

  /** Agrupa o resultado já simulado. */
  constructor(args: {
    effectivePeriod: DateRange;
    dates: readonly DateTime[];
    wealth: readonly number[];
    base100: readonly number[];
    totalContributed: Money;
    totalAllocated: Money;
    transactionCosts: Money;
    finalValue: Money;
    residualCash: Money;
    metrics: PerformanceMetrics;
    perAsset: ReadonlyMap<Ticker, AssetPerformance>;
    warnings?: readonly string[];
  }) {
    this.effectivePeriod = args.effectivePeriod;
    this.dates = args.dates;
    this.wealth = args.wealth;
    this.base100 = args.base100;
    this.totalContributed = args.totalContributed;
    this.totalAllocated = args.totalAllocated;
    this.transactionCosts = args.transactionCosts;
    this.finalValue = args.finalValue;
    this.residualCash = args.residualCash;
    this.metrics = args.metrics;
    this.perAsset = args.perAsset;
    this.warnings = args.warnings ?? [];
  }
}

/**
 * Cotação em centavos inteiros.
 *
 * **É a única forma do preço dentro do motor.** Comprar, marcar a mercado e
 * consolidar usam este valor, nunca o `double` original: com posição
 * inteira, `quantidade × centavos` é exato, e o patrimônio deixa de
 * acumular erro de representação ao longo de milhares de pregões.
 *
 * O arredondamento para o centavo é a convenção do BRL e da própria fonte,
 * que publica cotação com duas casas. Uma série que traga mais casas — como
 * um índice — é arredondada aqui, e o desvio fica abaixo de meio centavo
 * por papel.
 */
function priceInCents(price: number): number {
  return Money.fromReais(price).cents;
}

/**
 * O maior número de ações a [priceCents] que, somado ao custo da ordem,
 * cabe em [available].
 *
 * Parte da estimativa fechada `(caixa − corretagem) ÷ (preço·(1 + tarifa))`
 * e a corrige para os dois lados: o arredondamento da tarifa pode deixar a
 * estimativa uma ação acima ou abaixo do limite.
 */
function affordable(available: number, priceCents: number, c: TransactionCosts): number {
  const total = (q: number): number => q * priceCents + c.orderCents(q * priceCents);
  const free = available - c.brokeragePerOrder.cents;
  if (free < priceCents) return 0;
  let q = intDiv(free * 1000000, priceCents * (1000000 + c.feePartsPerMillion));
  while (total(q + 1) <= available) {
    q++;
  }
  while (q > 0 && total(q) > available) {
    q--;
  }
  return q;
}

/**
 * Reparte [totalCents] entre [weights] **distribuindo o resto**.
 *
 * Cada destino recebe o piso de `magnitude × peso`, e os centavos que
 * sobram vão um a um aos maiores restos fracionários — empate resolvido
 * pela ordem da carteira, para que a mesma entrada produza sempre a mesma
 * saída. A soma do resultado é exatamente [totalCents], o que `Money.times`
 * aplicado peso a peso não garante.
 *
 * Opera na **magnitude** e reaplica o sinal ao final: a divisão truncada e o
 * módulo são assimétricos em torno de zero, e repartir um valor negativo
 * diretamente inventaria um centavo.
 */
function splitCents(totalCents: number, weights: readonly number[]): number[] {
  const n = weights.length;
  const out = new Array<number>(n).fill(0);
  if (n === 0 || totalCents === 0) return out;

  const sign = isNegative(totalCents) ? -1 : 1;
  const magnitude = Math.abs(totalCents);

  const fractions = new Array<number>(n).fill(0.0);
  let distributed = 0;
  for (let i = 0; i < n; i++) {
    const exact = magnitude * weights[i]!;
    const f = floor(exact);
    out[i] = f;
    fractions[i] = exact - f;
    distributed += f;
  }

  const order = Array.from({ length: n }, (_, i) => i).sort((a, b) => {
    const byFraction = compareNum(fractions[b]!, fractions[a]!);
    return byFraction !== 0 ? byFraction : compareNum(a, b);
  });

  let leftover = magnitude - distributed;
  for (let k = 0; leftover > 0; k++) {
    out[order[k % n]!]! += 1;
    leftover--;
  }

  if (sign < 0) {
    for (let i = 0; i < n; i++) {
      out[i] = -out[i]!;
    }
  }
  return out;
}

/**
 * Distribui [amount] entre os ativos segundo os **pesos estipulados** e
 * compra o que couber em ações inteiras.
 *
 * Deliberadamente ignora os pesos correntes: corrigir a deriva aqui seria
 * rebalancear, e a estratégia não rebalanceia.
 *
 * A fatia de cada ativo entra no **caixa dele**, e a compra consome desse
 * caixa o maior número de ações cujo valor **mais o custo da ordem** caiba
 * nele (item C4). O que sobra fica lá e participa do aporte seguinte —
 * inclusive a fatia inteira de um ativo sem cotação no dia, que assim não se
 * perde. É essa acumulação que faz `Σ AssetPerformance.invested` reconstituir
 * o aportado sem perda.
 */
function allocate(args: {
  amount: Money;
  portfolio: Portfolio;
  prices: ReadonlyMap<Ticker, PriceSeries>;
  date: DateTime;
  shares: Map<Ticker, number>;
  investedCents: Map<Ticker, number>;
  cashCents: Map<Ticker, number>;
  costCents: Map<Ticker, number>;
  costs: TransactionCosts;
}): void {
  const { amount, portfolio, prices, date, shares, investedCents, cashCents, costCents, costs } = args;
  if (amount.cents === 0) return;

  const entries = [...portfolio.entries.values()];
  const slices = splitCents(
    amount.cents,
    entries.map((e) => e.weight.value),
  );

  for (let i = 0; i < entries.length; i++) {
    const ticker = entries[i]!.ticker;
    investedCents.set(ticker, investedCents.get(ticker)! + slices[i]!);
    cashCents.set(ticker, cashCents.get(ticker)! + slices[i]!);

    const price = prices.get(ticker)!.closeAsOf(date);
    if (price === null || price <= 0) continue;
    const pc = priceInCents(price);
    if (pc <= 0) continue;

    const available = cashCents.get(ticker)!;
    if (available <= 0) continue;
    const quantity = affordable(available, pc, costs);
    if (quantity <= 0) continue;
    const traded = quantity * pc;
    const cost = costs.orderCents(traded);
    shares.set(ticker, shares.get(ticker)! + quantity);
    costCents.set(ticker, costCents.get(ticker)! + cost);
    cashCents.set(ticker, available - traded - cost);
  }
}

/**
 * Simula a evolução de uma carteira com pesos estipulados.
 *
 * **Não há rebalanceamento de espécie alguma.** O aporte inicial e cada aporte
 * mensal são distribuídos segundo os percentuais estipulados; a partir daí
 * cada posição segue sua própria variação e os pesos derivam com o mercado.
 *
 * **Não há proventos.** A simulação responde a uma pergunta só — como a
 * carteira montada teria se comportado no passado —, e a resposta é o preço
 * de fechamento. Dividendo, JCP e a tributação deles saíram do modelo junto
 * com a fração de ação; ver `docs/decisoes/023-remocao-de-proventos.md`.
 */
export const PortfolioBacktest = {
  /**
   * Simula a carteira no período e consolida retorno e risco.
   *
   * - [portfolio]: carteira com pesos que somem 100%.
   * - [prices]: cotações por ativo. **Todos** os ativos da carteira precisam
   *   estar presentes e não vazios.
   * - [plan]: cronograma de aportes. Exige inicial ou mensal positivo.
   * - [range]: janela desejada. Pode ser encurtada — ver
   *   [BacktestOutcome.effectivePeriod].
   * - [riskFreeRate]: taxa livre de risco **anual** para Sharpe e Sortino.
   *   Padrão `0.0`, que produz Sharpe igual ao CAGR sobre a volatilidade.
   * - [costs]: custo de transação das compras. Padrão [TransactionCosts.b3],
   *   a tarifa da B3 — a simulação sem custo era otimista por construção
   *   (limitações, §2.5).
   *
   * Devolve [InvalidInput] para carteira vazia, pesos que não somam 100% ou
   * plano sem aporte; [InsufficientData] quando falta cotação de algum ativo,
   * quando nenhum ativo tem histórico no período, ou quando sobram menos de
   * dois pregões.
   *
   * Complexidade **O(d · a)**, com `d` pregões e `a` ativos.
   */
  run(args: {
    portfolio: Portfolio;
    prices: ReadonlyMap<Ticker, PriceSeries>;
    plan: ContributionPlan;
    range: DateRange;
    riskFreeRate?: number;
    costs?: TransactionCosts;
  }): Result<BacktestOutcome> {
    const { portfolio, prices, plan, range } = args;
    const riskFreeRate = args.riskFreeRate ?? 0.0;
    const costs = args.costs ?? TransactionCosts.b3;
    if (portfolio.isEmpty) {
      return err(new InvalidInput('Carteira vazia.'));
    }
    if (!portfolio.hasValidWeights) {
      return err(new InvalidInput('Os pesos da carteira não somam 100%.'));
    }
    if (plan.initial.cents <= 0 && !plan.hasMonthly) {
      return err(new InvalidInput('É necessário ao menos um aporte inicial ou mensal.'));
    }

    const warnings: string[] = [];

    // --- Calendário mestre -------------------------------------------------
    // Cada ativo tem seus próprios pregões; a união com forward fill evita que
    // um leilão ou suspensão isolada derrube um dia inteiro da simulação.
    const tickers = portfolio.tickers;
    const missing = tickers.filter((t) => {
      const series = prices.get(t);
      return series === undefined || series.isEmpty;
    });
    if (missing.length > 0) {
      return err(new InsufficientData(`Sem cotações para: ${missing.map((t) => t.value).join(', ')}.`));
    }

    let latestStart: DateTime | null = null;
    for (const ticker of tickers) {
      const firstDate = prices.get(ticker)!.firstDate;
      if (latestStart === null || firstDate.isAfter(latestStart)) {
        latestStart = firstDate;
      }
    }

    const effectiveStart = latestStart!.isAfter(range.start) ? latestStart! : range.start;
    if (effectiveStart.isAfter(range.end)) {
      return err(new InsufficientData('Nenhum ativo possui cotação dentro do período solicitado.'));
    }
    if (effectiveStart.isAfter(range.start)) {
      warnings.push(
        `Período encurtado para ${new DateRange(effectiveStart, range.end).toString()}: ` +
          'nem todos os ativos possuem histórico desde o início solicitado.',
      );
    }

    // Conjunto de datas com a igualdade do Dart: mesmo instante e mesma
    // marcação de UTC. A primeira ocorrência é a que fica, como no `Set`.
    const calendar = new Map<string, DateTime>();
    for (const ticker of tickers) {
      for (const point of prices.get(ticker)!.points) {
        if (!point.date.isBefore(effectiveStart) && !point.date.isAfter(range.end)) {
          if (!calendar.has(point.date.key)) calendar.set(point.date.key, point.date);
        }
      }
    }
    const dates = [...calendar.values()].sort((a, b) => a.compareTo(b));
    if (dates.length < 2) {
      return err(new InsufficientData('Período com menos de dois pregões: simulação impossível.'));
    }

    // --- Estado ------------------------------------------------------------
    // Posição inteira, capital destinado e caixa em espera, todos por ativo.
    const shares = new Map<Ticker, number>();
    const investedCents = new Map<Ticker, number>();
    const cashCents = new Map<Ticker, number>();
    const costCents = new Map<Ticker, number>();
    for (const t of tickers) {
      shares.set(t, 0);
      investedCents.set(t, 0);
      cashCents.set(t, 0);
      costCents.set(t, 0);
    }

    // Acumulador, e não duas listas paralelas: patrimônio e fluxo do dia
    // entram numa chamada só, então não há como desalinhá-los.
    const path = new WealthPathBuilder();
    const cashFlows: CashFlow[] = [];

    let lastContributionKey = '';
    let totalContributedCents = 0;

    // --- Simulação ---------------------------------------------------------
    for (let i = 0; i < dates.length; i++) {
      const today = dates[i]!;
      let flowToday = 0;

      // 1) Aporte inicial no primeiro pregão.
      if (i === 0 && plan.initial.isPositive) {
        allocate({
          amount: plan.initial,
          portfolio,
          prices,
          date: today,
          shares,
          investedCents,
          cashCents,
          costCents,
          costs,
        });
        flowToday += plan.initial.cents;
        totalContributedCents += plan.initial.cents;
        cashFlows.push(new CashFlow({ date: today, amount: plan.initial.negate() }));
        lastContributionKey = `${today.year}-${today.month}`;
      }

      // 2) Aporte mensal no primeiro pregão a partir do dia estipulado —
      // ou no último pregão do mês, quando o dia pedido não chega a existir
      // nele. Sem o segundo caso, dia 30 perde fevereiro **em silêncio**.
      if (plan.hasMonthly) {
        const key = `${today.year}-${today.month}`;
        const lastOfMonth = i + 1 >= dates.length || dates[i + 1]!.month !== today.month;
        if (key !== lastContributionKey && (today.day >= plan.contributionDay || lastOfMonth)) {
          allocate({
            amount: plan.monthly,
            portfolio,
            prices,
            date: today,
            shares,
            investedCents,
            cashCents,
            costCents,
            costs,
          });
          flowToday += plan.monthly.cents;
          totalContributedCents += plan.monthly.cents;
          cashFlows.push(new CashFlow({ date: today, amount: plan.monthly.negate() }));
          lastContributionKey = key;
        }
      }

      // 3) Marcação a mercado, somando o caixa que ainda não virou posição.
      //
      // Tudo em **centavos inteiros**, e não em reais: com posição inteira e
      // preço em centavos, `quantidade × preço` é exato, e a soma sobre os
      // ativos não acumula erro de representação dia após dia. Só o total do
      // dia vira número de ponto flutuante, uma vez, na fronteira da série.
      let positionCents = 0;
      let cashCentsToday = 0;
      for (const ticker of tickers) {
        const price = prices.get(ticker)!.closeAsOf(today);
        if (price !== null) {
          positionCents += shares.get(ticker)! * priceInCents(price);
        }
        cashCentsToday += cashCents.get(ticker)!;
      }

      path.add({
        value: (positionCents + cashCentsToday) / 100.0,
        externalFlow: flowToday / 100.0,
      });
    }

    // --- Consolidação ------------------------------------------------------
    const wealthPath = path.build();
    const wealth = wealthPath.values;
    const finalValue = Money.fromReais(wealth[wealth.length - 1]!);
    const totalContributed = new Money(totalContributedCents);
    const lastDate = dates[dates.length - 1]!;
    if (finalValue.isPositive) {
      cashFlows.push(new CashFlow({ date: lastDate, amount: finalValue }));
    }

    const base100 = Returns.timeWeightedIndex(wealthPath);
    const twr = Returns.timeWeighted(wealthPath);

    const effectiveRange = new DateRange(dates[0]!, lastDate);
    const years = effectiveRange.years;
    const cagr = Returns.annualize(twr, years);

    const xirr = Returns.extendedIrr(cashFlows).valueOrNull;

    const risk = RiskMetrics.fromIndex({ twrIndex: base100, cagr, riskFreeRate });

    const perAsset = new Map<Ticker, AssetPerformance>();
    let residualCashCents = 0;
    let totalCostCents = 0;
    for (const c of costCents.values()) totalCostCents = totalCostCents + c;
    const finalWealthCents = finalValue.cents;
    for (const entry of portfolio.entries.values()) {
      const ticker = entry.ticker;
      const price = prices.get(ticker)!.closeAsOf(lastDate) ?? 0.0;
      // Mesma aritmética inteira da marcação diária: `Σ finalValue + Σ cash`
      // reconstitui o patrimônio final ao centavo, sem tolerância.
      const endValue = new Money(shares.get(ticker)! * priceInCents(price));
      const invested = new Money(investedCents.get(ticker)!);
      const cash = new Money(cashCents.get(ticker)!);
      residualCashCents += cash.cents;

      perAsset.set(
        ticker,
        new AssetPerformance({
          ticker,
          targetWeight: entry.weight,
          currentWeight: finalWealthCents > 0 ? endValue.cents / finalWealthCents : 0.0,
          totalReturn: invested.isPositive ? (endValue.cents + cash.cents - invested.cents) / invested.cents : 0.0,
          invested,
          finalValue: endValue,
          cash,
          shares: shares.get(ticker)!,
        }),
      );
    }

    const residualCash = new Money(residualCashCents);

    return ok(
      new BacktestOutcome({
        effectivePeriod: effectiveRange,
        dates,
        wealth,
        base100,
        totalContributed,
        totalAllocated: totalContributed.minus(new Money(totalCostCents)).minus(residualCash),
        transactionCosts: new Money(totalCostCents),
        finalValue,
        residualCash,
        metrics: new PerformanceMetrics({
          timeWeightedReturn: twr,
          moneyWeightedReturn: xirr,
          cagr,
          volatility: risk.volatility,
          maxDrawdown: risk.maxDrawdown,
          sharpe: risk.sharpe,
          sortino: risk.sortino,
          calmar: risk.calmar,
        }),
        perAsset,
        warnings,
      }),
    );
  },
};
