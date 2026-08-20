import '../../entities/dividend_event.dart';
import '../../entities/portfolio.dart';
import '../../entities/price_series.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';
import '../../tax/tax_policy.dart';
import '../../value_objects/date_range.dart';
import '../../value_objects/money.dart';
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

  const ContributionPlan({
    required this.initial,
    required this.monthly,
    this.contributionDay = 5,
  });

  static const ContributionPlan none = ContributionPlan(
    initial: Money.zero,
    monthly: Money.zero,
  );

  bool get hasMonthly => monthly.isPositive;
}

/// Desempenho individual de um ativo dentro da carteira.
class AssetPerformance {
  final Ticker ticker;

  /// Peso estipulado na constituição da carteira.
  final Weight targetWeight;

  /// Peso corrente ao final do período — difere do alvo porque **não há
  /// rebalanceamento**, e essa deriva é sinal de decisão, não defeito.
  final double currentWeight;

  /// Retorno total do ativo no período (preço + proventos líquidos).
  final double totalReturn;

  /// Capital alocado ao ativo ao longo do período.
  final Money invested;

  final Money finalValue;
  final Money grossDividends;
  final Money withheldTax;
  final double shares;

  const AssetPerformance({
    required this.ticker,
    required this.targetWeight,
    required this.currentWeight,
    required this.totalReturn,
    required this.invested,
    required this.finalValue,
    required this.grossDividends,
    required this.withheldTax,
    required this.shares,
  });

  /// Diferença entre peso corrente e alvo, em pontos percentuais.
  double get drift => (currentWeight - targetWeight.value) * 100;
}

/// Conjunto de métricas de desempenho de uma carteira.
class PerformanceMetrics {
  /// Retorno acumulado da série TWR.
  final double accumulatedReturn;

  /// TWR — neutraliza aportes. Métrica correta para **comparar composições**.
  final double timeWeightedReturn;

  /// XIRR — retorno efetivo do investidor, o número a confrontar com a meta.
  final double? moneyWeightedReturn;

  /// CAGR derivado do TWR.
  final double cagr;

  final double volatility;
  final double maxDrawdown;
  final double sharpe;
  final double sortino;
  final double calmar;

  /// Proventos líquidos de imposto sobre o patrimônio médio, ao ano.
  final double netDividendYield;

  const PerformanceMetrics({
    required this.accumulatedReturn,
    required this.timeWeightedReturn,
    required this.moneyWeightedReturn,
    required this.cagr,
    required this.volatility,
    required this.maxDrawdown,
    required this.sharpe,
    required this.sortino,
    required this.calmar,
    required this.netDividendYield,
  });
}

/// Resultado da simulação de uma carteira.
class BacktestOutcome {
  final DateRange effectivePeriod;
  final List<DateTime> dates;

  /// Patrimônio bruto dia a dia, incluindo os aportes.
  final List<double> wealth;

  /// Índice TWR em base 100 — é esta a curva que alimenta risco, porque a
  /// curva de patrimônio salta no dia do aporte.
  final List<double> base100;

  final List<CashFlow> cashFlows;
  final Money totalContributed;
  final Money finalValue;
  final Money grossDividends;
  final Money withheldTax;
  final PerformanceMetrics metrics;
  final Map<Ticker, AssetPerformance> perAsset;

  /// Avisos: séries encurtadas, ativos sem dados, datas de pagamento estimadas.
  final List<String> warnings;

  const BacktestOutcome({
    required this.effectivePeriod,
    required this.dates,
    required this.wealth,
    required this.base100,
    required this.cashFlows,
    required this.totalContributed,
    required this.finalValue,
    required this.grossDividends,
    required this.withheldTax,
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
/// Proventos são creditados pela posição vigente na data-ex, líquidos de
/// imposto conforme a [TaxPolicy], e reinvestidos no próprio ativo pagador na
/// data de pagamento.
abstract final class PortfolioBacktest {
  static Result<BacktestOutcome> run({
    required Portfolio portfolio,
    required Map<Ticker, PriceSeries> prices,
    required Map<Ticker, List<DividendEvent>> dividends,
    required ContributionPlan plan,
    required DateRange range,
    TaxPolicy taxPolicy = TaxPolicy.brasil,
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
    final shares = <Ticker, double>{for (final t in portfolio.tickers) t: 0.0};
    final investedCents = <Ticker, int>{
      for (final t in portfolio.tickers) t: 0
    };
    final grossByTicker = <Ticker, double>{
      for (final t in portfolio.tickers) t: 0.0
    };
    final taxByTicker = <Ticker, double>{
      for (final t in portfolio.tickers) t: 0.0
    };

    // Proventos elegíveis, com a posição apurada na data-ex.
    final events = <_PendingDividend>[];
    var estimatedPaymentDates = 0;
    for (final ticker in portfolio.tickers) {
      for (final event in dividends[ticker] ?? const <DividendEvent>[]) {
        if (event.exDate.isBefore(effectiveStart)) continue;
        if (event.exDate.isAfter(range.end)) continue;
        events.add(_PendingDividend(event));
        if (event.paymentDateEstimated) estimatedPaymentDates++;
      }
    }
    events.sort((a, b) => a.event.exDate.compareTo(b.event.exDate));
    if (estimatedPaymentDates > 0) {
      warnings.add(
        '$estimatedPaymentDates provento(s) com data de pagamento estimada '
        'pela fonte: o momento do reinvestimento pode variar alguns dias.',
      );
    }

    final wealth = <double>[];
    final flows = <double>[];
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
          );
          flowToday += plan.monthly.cents;
          totalContributedCents += plan.monthly.cents;
          cashFlows.add(CashFlow(date: today, amount: -plan.monthly));
          lastContributionKey = key;
        }
      }

      // 3) Direito a provento apurado na data-ex.
      for (final pending in events) {
        if (pending.entitlement != null) continue;
        if (!pending.event.exDate.isAfter(today)) {
          pending.entitlement = shares[pending.event.ticker] ?? 0.0;
        }
      }

      // 4) Crédito e reinvestimento na data de pagamento.
      for (final pending in events) {
        if (pending.paid) continue;
        final held = pending.entitlement;
        if (held == null) continue;
        if (pending.event.paymentDate.isAfter(today)) continue;

        final ticker = pending.event.ticker;
        final price = prices[ticker]!.closeAsOf(today);
        final netPerShare = taxPolicy.netAmount(pending.event);

        grossByTicker[ticker] =
            grossByTicker[ticker]! + pending.event.amountPerShare * held;
        taxByTicker[ticker] =
            taxByTicker[ticker]! + taxPolicy.withheldAmount(pending.event) * held;

        if (price != null && price > 0 && netPerShare > 0 && held > 0) {
          shares[ticker] = shares[ticker]! + (netPerShare * held) / price;
        }
        pending.paid = true;
      }

      // 5) Marcação a mercado.
      var value = 0.0;
      for (final ticker in portfolio.tickers) {
        final price = prices[ticker]!.closeAsOf(today);
        if (price != null) value += shares[ticker]! * price;
      }

      wealth.add(value);
      flows.add(flowToday / 100.0);
    }

    // --- Consolidação ------------------------------------------------------
    final finalValue = Money.fromReais(wealth.last);
    final totalContributed = Money(totalContributedCents);
    if (finalValue.isPositive) {
      cashFlows.add(CashFlow(date: dates.last, amount: finalValue));
    }

    final base100 =
        Returns.timeWeightedIndex(values: wealth, externalFlows: flows);
    final twr = Returns.timeWeighted(values: wealth, externalFlows: flows);

    final effectiveRange = DateRange(dates.first, dates.last);
    final years = effectiveRange.years;
    final cagr = Returns.annualize(twr, years);

    final xirr = Returns.extendedIrr(cashFlows).valueOrNull;

    final risk = RiskMetrics.fromIndex(
      twrIndex: base100,
      cagr: cagr,
      riskFreeRate: riskFreeRate,
    );

    var totalGross = 0.0;
    var totalTax = 0.0;
    for (final ticker in portfolio.tickers) {
      totalGross += grossByTicker[ticker]!;
      totalTax += taxByTicker[ticker]!;
    }

    final averageWealth = wealth.isEmpty
        ? 0.0
        : wealth.reduce((a, b) => a + b) / wealth.length;
    final netDividends = totalGross - totalTax;
    final netDy = (averageWealth > 0 && years > 0)
        ? (netDividends / averageWealth) / years
        : 0.0;

    final perAsset = <Ticker, AssetPerformance>{};
    for (final entry in portfolio.entries.values) {
      final ticker = entry.ticker;
      final price = prices[ticker]!.closeAsOf(dates.last) ?? 0.0;
      final endValue = shares[ticker]! * price;
      final invested = Money(investedCents[ticker]!);
      final assetGross = grossByTicker[ticker]!;
      final assetTax = taxByTicker[ticker]!;

      perAsset[ticker] = AssetPerformance(
        ticker: ticker,
        targetWeight: entry.weight,
        currentWeight: wealth.last > 0 ? endValue / wealth.last : 0.0,
        totalReturn: invested.isPositive
            ? (endValue - invested.reais) / invested.reais
            : 0.0,
        invested: invested,
        finalValue: Money.fromReais(endValue),
        grossDividends: Money.fromReais(assetGross),
        withheldTax: Money.fromReais(assetTax),
        shares: shares[ticker]!,
      );
    }

    return Ok(BacktestOutcome(
      effectivePeriod: effectiveRange,
      dates: dates,
      wealth: wealth,
      base100: base100,
      cashFlows: cashFlows,
      totalContributed: totalContributed,
      finalValue: finalValue,
      grossDividends: Money.fromReais(totalGross),
      withheldTax: Money.fromReais(totalTax),
      metrics: PerformanceMetrics(
        accumulatedReturn: twr,
        timeWeightedReturn: twr,
        moneyWeightedReturn: xirr,
        cagr: cagr,
        volatility: risk.volatility,
        maxDrawdown: risk.maxDrawdown,
        sharpe: risk.sharpe,
        sortino: risk.sortino,
        calmar: risk.calmar,
        netDividendYield: netDy,
      ),
      perAsset: perAsset,
      warnings: warnings,
    ));
  }

  /// Distribui [amount] entre os ativos segundo os **pesos estipulados**.
  ///
  /// Deliberadamente ignora os pesos correntes: corrigir a deriva aqui seria
  /// rebalancear, e a estratégia não rebalanceia.
  static void _allocate({
    required Money amount,
    required Portfolio portfolio,
    required Map<Ticker, PriceSeries> prices,
    required DateTime date,
    required Map<Ticker, double> shares,
    required Map<Ticker, int> investedCents,
  }) {
    for (final entry in portfolio.entries.values) {
      final ticker = entry.ticker;
      final price = prices[ticker]!.closeAsOf(date);
      if (price == null || price <= 0) continue;
      final slice = amount * entry.weight.value;
      shares[ticker] = shares[ticker]! + slice.reais / price;
      investedCents[ticker] = investedCents[ticker]! + slice.cents;
    }
  }
}

class _PendingDividend {
  final DividendEvent event;
  double? entitlement;
  bool paid = false;
  _PendingDividend(this.event);
}
