import '../../entities/portfolio.dart';
import '../../entities/price_series.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';
import '../../value_objects/date_range.dart';
import '../../value_objects/money.dart';
import '../../value_objects/paired_series.dart';
import '../../value_objects/ticker.dart';
import '../../value_objects/weight.dart';
import '../metrics/returns.dart';
import '../metrics/risk_metrics.dart';

/// Cronograma de aportes do plano.
class ContributionPlan {
  /// Aporte inicial (V₀).
  final Money initial;

  /// Aporte mensal (PMT).
  final Money monthly;

  /// Dia do mês do aporte. Limitado a 28 para existir em todos os meses.
  final int contributionDay;

  /// Declara o cronograma. **Não valida** [contributionDay]; dias acima de 28
  /// simplesmente não ocorrem em fevereiro, e o aporte do mês é perdido.
  const ContributionPlan({
    required this.initial,
    required this.monthly,
    this.contributionDay = 5,
  });

  /// Plano sem aporte algum. Usado para simular a evolução de uma posição já
  /// constituída — recusado por [PortfolioBacktest.run], que exige capital.
  static const ContributionPlan none = ContributionPlan(
    initial: Money.zero,
    monthly: Money.zero,
  );

  /// `true` quando há aporte mensal estritamente positivo.
  bool get hasMonthly => monthly.isPositive;
}

/// Desempenho individual de um ativo dentro da carteira.
class AssetPerformance {
  /// Ativo a que este desempenho se refere.
  final Ticker ticker;

  /// Peso estipulado na constituição da carteira.
  final Weight targetWeight;

  /// Peso corrente ao final do período — difere do alvo porque **não há
  /// rebalanceamento**, e essa deriva é sinal de decisão, não defeito.
  final double currentWeight;

  /// Retorno do ativo no período, apurado sobre [invested] contra o valor de
  /// mercado da posição **mais** o caixa que sobrou dela.
  ///
  /// Deixar o caixa de fora puniria o ativo por dinheiro que continua sendo
  /// dele e vale exatamente o que custou.
  final double totalReturn;

  /// Capital destinado ao ativo ao longo do período, tenha ele virado posição
  /// ou ficado em caixa. A soma sobre os ativos reconstitui
  /// [BacktestOutcome.totalContributed] exatamente.
  final Money invested;

  /// Valor de mercado da posição no último pregão do período.
  final Money finalValue;

  /// Caixa do ativo ao final: o que sobrou de cada aporte por não completar
  /// mais uma ação inteira, acumulado e reaplicado nos aportes seguintes.
  final Money cash;

  /// Quantidade de papéis ao final. **Inteira**: a simulação compra lotes de
  /// uma ação, como a corretora faz, e nunca fraciona.
  final int shares;

  /// Agrupa o desempenho já apurado.
  const AssetPerformance({
    required this.ticker,
    required this.targetWeight,
    required this.currentWeight,
    required this.totalReturn,
    required this.invested,
    required this.finalValue,
    required this.cash,
    required this.shares,
  });

  /// Diferença entre peso corrente e alvo, em pontos percentuais.
  double get drift => (currentWeight - targetWeight.value) * 100;
}

/// Conjunto de métricas de desempenho de uma carteira.
///
/// Todas as métricas de risco são apuradas sobre a série **TWR em base 100**
/// (`BacktestOutcome.base100`), nunca sobre a curva bruta de patrimônio — ver
/// [RiskMetrics] para o motivo.
class PerformanceMetrics {
  /// Retorno acumulado do período, neutralizado de aportes (TWR).
  ///
  /// É **a** métrica para comparar duas composições de carteira: não premia
  /// nem pune a carteira pelo cronograma de aportes. Para o retorno que o
  /// investidor efetivamente obteve, use [moneyWeightedReturn].
  final double timeWeightedReturn;

  /// XIRR — retorno efetivo do investidor, o número a confrontar com a meta.
  ///
  /// `null` quando a taxa não pôde ser isolada: menos de dois fluxos, ausência
  /// de fluxo positivo ou negativo, ou falha de convergência do solver.
  final double? moneyWeightedReturn;

  /// CAGR derivado do TWR, anualizado sobre o período efetivo em base 365,25.
  final double cagr;

  /// Desvio-padrão amostral anualizado dos retornos diários, em fração.
  final double volatility;

  /// Pior queda de pico a vale da série TWR, em fração **negativa**.
  final double maxDrawdown;

  /// (CAGR − taxa livre de risco) / volatilidade. Zero quando a volatilidade
  /// é nula.
  final double sharpe;

  /// Como [sharpe], mas dividido apenas pelo semidesvio negativo.
  final double sortino;

  /// CAGR / |máximo drawdown|. Zero quando não houve drawdown.
  final double calmar;

  /// Agrupa as métricas já apuradas. Não calcula nada — o cálculo vive em
  /// [PortfolioBacktest.run].
  const PerformanceMetrics({
    required this.timeWeightedReturn,
    required this.moneyWeightedReturn,
    required this.cagr,
    required this.volatility,
    required this.maxDrawdown,
    required this.sharpe,
    required this.sortino,
    required this.calmar,
  });
}

/// Resultado da simulação de uma carteira.
class BacktestOutcome {
  /// Período **efetivamente** simulado, que pode ser mais curto que o pedido
  /// quando algum ativo não tem histórico desde o início. O encurtamento é
  /// registrado em [warnings].
  final DateRange effectivePeriod;

  /// Calendário mestre: união dos pregões de todos os ativos, ordenado.
  /// Alinhado posição a posição com [wealth] e [base100].
  final List<DateTime> dates;

  /// Patrimônio dia a dia — posições marcadas a mercado **mais** o caixa —,
  /// incluindo os aportes.
  ///
  /// Somar o caixa é o que garante que nenhum centavo aportado desapareça da
  /// curva enquanto espera para completar uma ação inteira.
  final List<double> wealth;

  /// Índice TWR em base 100 — é esta a curva que alimenta risco, porque a
  /// curva de patrimônio salta no dia do aporte.
  final List<double> base100;

  /// Fluxos datados na convenção da TIR: aportes negativos, e o valor final
  /// da carteira como último fluxo positivo.
  final List<CashFlow> cashFlows;

  /// Capital aportado no período, somando inicial e mensais.
  final Money totalContributed;

  /// Capital que virou posição: o custo de aquisição das ações efetivamente
  /// compradas, e portanto `totalContributed − residualCash` por construção.
  final Money totalAllocated;

  /// Patrimônio no último pregão: posições a mercado mais [residualCash].
  final Money finalValue;

  /// Caixa parado ao final da simulação, somado sobre os ativos.
  ///
  /// É a fração de cada aporte que não completou mais uma ação inteira. Ela
  /// fica disponível para o aporte seguinte, então o saldo ao final é sempre
  /// menor que a soma dos preços unitários da carteira — um valor alto
  /// significa papel caro diante do aporte, não capital perdido.
  final Money residualCash;

  /// Métricas consolidadas de retorno e risco.
  final PerformanceMetrics metrics;

  /// Desempenho por ativo, indexado por ticker.
  final Map<Ticker, AssetPerformance> perAsset;

  /// Avisos: séries encurtadas ou ativos sem dados no período.
  final List<String> warnings;

  /// Agrupa o resultado já simulado.
  const BacktestOutcome({
    required this.effectivePeriod,
    required this.dates,
    required this.wealth,
    required this.base100,
    required this.cashFlows,
    required this.totalContributed,
    required this.totalAllocated,
    required this.finalValue,
    required this.residualCash,
    required this.metrics,
    required this.perAsset,
    this.warnings = const [],
  });
}

/// Simula a evolução de uma carteira com pesos estipulados.
///
/// **Não há rebalanceamento de espécie alguma.** O aporte inicial e cada aporte
/// mensal são distribuídos segundo os percentuais estipulados; a partir daí
/// cada posição segue sua própria variação e os pesos derivam com o mercado.
///
/// **Não há proventos.** A simulação responde a uma pergunta só — como a
/// carteira montada teria se comportado no passado —, e a resposta é o preço
/// de fechamento. Dividendo, JCP e a tributação deles saíram do modelo junto
/// com a fração de ação; ver `docs/decisoes/023-remocao-de-proventos.md`.
abstract final class PortfolioBacktest {
  /// Simula a carteira no período e consolida retorno e risco.
  ///
  /// - [portfolio]: carteira com pesos que somem 100%.
  /// - [prices]: cotações por ativo. **Todos** os ativos da carteira precisam
  ///   estar presentes e não vazios.
  /// - [plan]: cronograma de aportes. Exige inicial ou mensal positivo.
  /// - [range]: janela desejada. Pode ser encurtada — ver
  ///   [BacktestOutcome.effectivePeriod].
  /// - [riskFreeRate]: taxa livre de risco **anual** para Sharpe e Sortino.
  ///   Padrão `0.0`, que produz Sharpe igual ao CAGR sobre a volatilidade.
  ///
  /// Devolve [InvalidInput] para carteira vazia, pesos que não somam 100% ou
  /// plano sem aporte; [InsufficientData] quando falta cotação de algum ativo,
  /// quando nenhum ativo tem histórico no período, ou quando sobram menos de
  /// dois pregões.
  ///
  /// Complexidade **O(d · a)**, com `d` pregões e `a` ativos.
  static Result<BacktestOutcome> run({
    required Portfolio portfolio,
    required Map<Ticker, PriceSeries> prices,
    required ContributionPlan plan,
    required DateRange range,
    double riskFreeRate = 0.0,
  }) {
    if (portfolio.isEmpty) {
      return const Err(InvalidInput('Carteira vazia.'));
    }
    if (!portfolio.hasValidWeights) {
      return const Err(InvalidInput('Os pesos da carteira não somam 100%.'));
    }
    if (plan.initial.cents <= 0 && !plan.hasMonthly) {
      return const Err(InvalidInput(
        'É necessário ao menos um aporte inicial ou mensal.',
      ));
    }

    final warnings = <String>[];

    // --- Calendário mestre -------------------------------------------------
    // Cada ativo tem seus próprios pregões; a união com forward fill evita que
    // um leilão ou suspensão isolada derrube um dia inteiro da simulação.
    final missing = portfolio.tickers
        .where((t) => prices[t] == null || prices[t]!.isEmpty)
        .toList();
    if (missing.isNotEmpty) {
      return Err(InsufficientData(
        'Sem cotações para: ${missing.map((t) => t.value).join(', ')}.',
      ));
    }

    DateTime? latestStart;
    for (final ticker in portfolio.tickers) {
      final first = prices[ticker]!.firstDate;
      if (latestStart == null || first.isAfter(latestStart)) {
        latestStart = first;
      }
    }

    final effectiveStart =
        latestStart!.isAfter(range.start) ? latestStart : range.start;
    if (effectiveStart.isAfter(range.end)) {
      return const Err(InsufficientData(
        'Nenhum ativo possui cotação dentro do período solicitado.',
      ));
    }
    if (effectiveStart.isAfter(range.start)) {
      warnings.add(
        'Período encurtado para ${DateRange(effectiveStart, range.end)}: '
        'nem todos os ativos possuem histórico desde o início solicitado.',
      );
    }

    final calendar = <DateTime>{};
    for (final ticker in portfolio.tickers) {
      for (final point in prices[ticker]!.points) {
        if (!point.date.isBefore(effectiveStart) &&
            !point.date.isAfter(range.end)) {
          calendar.add(point.date);
        }
      }
    }
    final dates = calendar.toList()..sort();
    if (dates.length < 2) {
      return const Err(InsufficientData(
        'Período com menos de dois pregões: simulação impossível.',
      ));
    }

    // --- Estado ------------------------------------------------------------
    // Posição inteira, capital destinado e caixa em espera, todos por ativo.
    final shares = <Ticker, int>{for (final t in portfolio.tickers) t: 0};
    final investedCents = <Ticker, int>{
      for (final t in portfolio.tickers) t: 0
    };
    final cashCents = <Ticker, int>{for (final t in portfolio.tickers) t: 0};

    // Acumulador, e não duas listas paralelas: patrimônio e fluxo do dia
    // entram numa chamada só, então não há como desalinhá-los.
    final path = WealthPathBuilder();
    final cashFlows = <CashFlow>[];

    var lastContributionKey = '';
    var totalContributedCents = 0;

    // --- Simulação ---------------------------------------------------------
    for (var i = 0; i < dates.length; i++) {
      final today = dates[i];
      var flowToday = 0;

      // 1) Aporte inicial no primeiro pregão.
      if (i == 0 && plan.initial.isPositive) {
        _allocate(
          amount: plan.initial,
          portfolio: portfolio,
          prices: prices,
          date: today,
          shares: shares,
          investedCents: investedCents,
          cashCents: cashCents,
        );
        flowToday += plan.initial.cents;
        totalContributedCents += plan.initial.cents;
        cashFlows.add(CashFlow(date: today, amount: -plan.initial));
        lastContributionKey = '${today.year}-${today.month}';
      }

      // 2) Aporte mensal no primeiro pregão a partir do dia estipulado.
      if (plan.hasMonthly) {
        final key = '${today.year}-${today.month}';
        if (key != lastContributionKey && today.day >= plan.contributionDay) {
          _allocate(
            amount: plan.monthly,
            portfolio: portfolio,
            prices: prices,
            date: today,
            shares: shares,
            investedCents: investedCents,
            cashCents: cashCents,
          );
          flowToday += plan.monthly.cents;
          totalContributedCents += plan.monthly.cents;
          cashFlows.add(CashFlow(date: today, amount: -plan.monthly));
          lastContributionKey = key;
        }
      }

      // 3) Marcação a mercado, somando o caixa que ainda não virou posição.
      //
      // Tudo em **centavos inteiros**, e não em reais: com posição inteira e
      // preço em centavos, `quantidade × preço` é exato, e a soma sobre os
      // ativos não acumula erro de representação dia após dia. Só o total do
      // dia vira `double`, uma vez, na fronteira da série.
      var positionCents = 0;
      var cashCentsToday = 0;
      for (final ticker in portfolio.tickers) {
        final price = prices[ticker]!.closeAsOf(today);
        if (price != null) {
          positionCents += shares[ticker]! * _priceInCents(price);
        }
        cashCentsToday += cashCents[ticker]!;
      }

      path.add(
        value: (positionCents + cashCentsToday) / 100.0,
        externalFlow: flowToday / 100.0,
      );
    }

    // --- Consolidação ------------------------------------------------------
    final wealthPath = path.build();
    final wealth = wealthPath.values;
    final finalValue = Money.fromReais(wealth.last);
    final totalContributed = Money(totalContributedCents);
    if (finalValue.isPositive) {
      cashFlows.add(CashFlow(date: dates.last, amount: finalValue));
    }

    final base100 = Returns.timeWeightedIndex(wealthPath);
    final twr = Returns.timeWeighted(wealthPath);

    final effectiveRange = DateRange(dates.first, dates.last);
    final years = effectiveRange.years;
    final cagr = Returns.annualize(twr, years);

    final xirr = Returns.extendedIrr(cashFlows).valueOrNull;

    final risk = RiskMetrics.fromIndex(
      twrIndex: base100,
      cagr: cagr,
      riskFreeRate: riskFreeRate,
    );

    final perAsset = <Ticker, AssetPerformance>{};
    var residualCashCents = 0;
    final finalWealthCents = finalValue.cents;
    for (final entry in portfolio.entries.values) {
      final ticker = entry.ticker;
      final price = prices[ticker]!.closeAsOf(dates.last) ?? 0.0;
      // Mesma aritmética inteira da marcação diária: `Σ finalValue + Σ cash`
      // reconstitui o patrimônio final ao centavo, sem tolerância.
      final endValue = Money(shares[ticker]! * _priceInCents(price));
      final invested = Money(investedCents[ticker]!);
      final cash = Money(cashCents[ticker]!);
      residualCashCents += cash.cents;

      perAsset[ticker] = AssetPerformance(
        ticker: ticker,
        targetWeight: entry.weight,
        currentWeight: finalWealthCents > 0
            ? endValue.cents / finalWealthCents
            : 0.0,
        totalReturn: invested.isPositive
            ? (endValue.cents + cash.cents - invested.cents) / invested.cents
            : 0.0,
        invested: invested,
        finalValue: endValue,
        cash: cash,
        shares: shares[ticker]!,
      );
    }

    final residualCash = Money(residualCashCents);

    return Ok(BacktestOutcome(
      effectivePeriod: effectiveRange,
      dates: dates,
      wealth: wealth,
      base100: base100,
      cashFlows: cashFlows,
      totalContributed: totalContributed,
      totalAllocated: totalContributed - residualCash,
      finalValue: finalValue,
      residualCash: residualCash,
      metrics: PerformanceMetrics(
        timeWeightedReturn: twr,
        moneyWeightedReturn: xirr,
        cagr: cagr,
        volatility: risk.volatility,
        maxDrawdown: risk.maxDrawdown,
        sharpe: risk.sharpe,
        sortino: risk.sortino,
        calmar: risk.calmar,
      ),
      perAsset: perAsset,
      warnings: warnings,
    ));
  }

  /// Distribui [amount] entre os ativos segundo os **pesos estipulados** e
  /// compra o que couber em ações inteiras.
  ///
  /// Deliberadamente ignora os pesos correntes: corrigir a deriva aqui seria
  /// rebalancear, e a estratégia não rebalanceia.
  ///
  /// A fatia de cada ativo entra no **caixa dele**, e a compra consome desse
  /// caixa o maior múltiplo inteiro do preço do dia. O que sobra fica lá e
  /// participa do aporte seguinte — inclusive a fatia inteira de um ativo sem
  /// cotação no dia, que assim não se perde. É essa acumulação que faz
  /// `Σ AssetPerformance.invested` reconstituir o aportado sem perda.
  static void _allocate({
    required Money amount,
    required Portfolio portfolio,
    required Map<Ticker, PriceSeries> prices,
    required DateTime date,
    required Map<Ticker, int> shares,
    required Map<Ticker, int> investedCents,
    required Map<Ticker, int> cashCents,
  }) {
    if (amount.cents == 0) return;

    final entries = portfolio.entries.values.toList();
    final slices = _splitCents(
      amount.cents,
      [for (final e in entries) e.weight.value],
    );

    for (var i = 0; i < entries.length; i++) {
      final ticker = entries[i].ticker;
      investedCents[ticker] = investedCents[ticker]! + slices[i];
      cashCents[ticker] = cashCents[ticker]! + slices[i];

      final price = prices[ticker]!.closeAsOf(date);
      if (price == null || price <= 0) continue;
      final priceCents = _priceInCents(price);
      if (priceCents <= 0) continue;

      final available = cashCents[ticker]!;
      if (available <= 0) continue;
      final quantity = available ~/ priceCents;
      if (quantity <= 0) continue;
      shares[ticker] = shares[ticker]! + quantity;
      cashCents[ticker] = available - quantity * priceCents;
    }
  }

  /// Cotação em centavos inteiros.
  ///
  /// **É a única forma do preço dentro do motor.** Comprar, marcar a mercado e
  /// consolidar usam este valor, nunca o `double` original: com posição
  /// inteira, `quantidade × centavos` é exato, e o patrimônio deixa de
  /// acumular erro de representação ao longo de milhares de pregões.
  ///
  /// O arredondamento para o centavo é a convenção do BRL e da própria fonte,
  /// que publica cotação com duas casas. Uma série que traga mais casas — como
  /// um índice — é arredondada aqui, e o desvio fica abaixo de meio centavo
  /// por papel.
  static int _priceInCents(double price) => Money.fromReais(price).cents;

  /// Reparte [totalCents] entre [weights] **distribuindo o resto**.
  ///
  /// Cada destino recebe o piso de `magnitude × peso`, e os centavos que
  /// sobram vão um a um aos maiores restos fracionários — empate resolvido
  /// pela ordem da carteira, para que a mesma entrada produza sempre a mesma
  /// saída. A soma do resultado é exatamente [totalCents], o que `Money.operator *`
  /// aplicado peso a peso não garante.
  ///
  /// Opera na **magnitude** e reaplica o sinal ao final: a divisão truncada e o
  /// módulo de Dart são assimétricos em torno de zero, e repartir um valor
  /// negativo diretamente inventaria um centavo.
  static List<int> _splitCents(int totalCents, List<double> weights) {
    final n = weights.length;
    final out = List<int>.filled(n, 0);
    if (n == 0 || totalCents == 0) return out;

    final sign = totalCents.isNegative ? -1 : 1;
    final magnitude = totalCents.abs();

    final fractions = List<double>.filled(n, 0.0);
    var distributed = 0;
    for (var i = 0; i < n; i++) {
      final exact = magnitude * weights[i];
      final floor = exact.floor();
      out[i] = floor;
      fractions[i] = exact - floor;
      distributed += floor;
    }

    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final byFraction = fractions[b].compareTo(fractions[a]);
        return byFraction != 0 ? byFraction : a.compareTo(b);
      });

    var leftover = magnitude - distributed;
    for (var k = 0; leftover > 0; k++) {
      out[order[k % n]] += 1;
      leftover--;
    }

    if (sign < 0) {
      for (var i = 0; i < n; i++) {
        out[i] = -out[i];
      }
    }
    return out;
  }
}
