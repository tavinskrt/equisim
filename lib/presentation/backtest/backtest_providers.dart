import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../study/study_notifier.dart';

/// Parâmetros da simulação histórica.
class BacktestSettings {
  final int windowYears;
  final int contributionDay;

  /// Alterna entre proventos brutos e líquidos de IR.
  ///
  /// Existe para tornar o efeito fiscal **visível**: rodar os dois e comparar
  /// mostra quanto o IRRF sobre JCP custou no período, em vez de deixá-lo
  /// diluído num número só.
  final bool applyTaxes;

  const BacktestSettings({
    this.windowYears = 5,
    this.contributionDay = 5,
    this.applyTaxes = true,
  });

  BacktestSettings copyWith({
    int? windowYears,
    int? contributionDay,
    bool? applyTaxes,
  }) =>
      BacktestSettings(
        windowYears: windowYears ?? this.windowYears,
        contributionDay: contributionDay ?? this.contributionDay,
        applyTaxes: applyTaxes ?? this.applyTaxes,
      );

  TaxPolicy get taxPolicy => applyTaxes ? TaxPolicy.brasil : TaxPolicy.zero;
}

class BacktestSettingsNotifier extends Notifier<BacktestSettings> {
  @override
  BacktestSettings build() => const BacktestSettings();

  void setWindowYears(int years) =>
      state = state.copyWith(windowYears: years.clamp(1, 10));
  void setContributionDay(int day) =>
      state = state.copyWith(contributionDay: day.clamp(1, 28));
  void setApplyTaxes(bool value) => state = state.copyWith(applyTaxes: value);
}

final backtestSettingsProvider =
    NotifierProvider<BacktestSettingsNotifier, BacktestSettings>(
  BacktestSettingsNotifier.new,
);

/// Resultado comparativo das duas carteiras sob o mesmo plano de aportes.
class PortfolioComparison {
  final BacktestOutcome? principal;
  final BacktestOutcome? reserva;
  final DateRange window;

  const PortfolioComparison({
    required this.window,
    this.principal,
    this.reserva,
  });

  bool get hasBoth => principal != null && reserva != null;

  /// Diferença de retorno ponderado pelo tempo, em pontos percentuais.
  ///
  /// TWR é a métrica correta para esta comparação: neutraliza o cronograma de
  /// aportes, que é idêntico nas duas carteiras, e isola o que de fato difere
  /// — a composição.
  double? get twrGap => hasBoth
      ? (principal!.metrics.timeWeightedReturn -
              reserva!.metrics.timeWeightedReturn) *
          100
      : null;
}

/// Executa o backtest das duas carteiras com o mesmo plano de aportes.
final comparisonProvider = FutureProvider<PortfolioComparison?>((ref) async {
  final study = ref.watch(studyProvider).study;
  final settings = ref.watch(backtestSettingsProvider);
  final goal = study.goal;

  if (study.principal.isEmpty && study.reserva.isEmpty) return null;
  if (goal == null) return null;

  final today = DateTime.now();
  final window = DateRange(
    DateTime(today.year - settings.windowYears, today.month, today.day),
    today,
  );

  final prices = ref.watch(priceRepositoryProvider);
  final dividends = ref.watch(dividendRepositoryProvider);
  final riskFree = await ref.watch(riskFreeRateProvider.future);

  final tickers = <Ticker>{
    ...study.principal.tickers,
    ...study.reserva.tickers,
  }.toList();
  if (tickers.isEmpty) return null;

  // Um único lote para todos os ativos das duas carteiras.
  final priceResult = await prices.dailyBatch(tickers, window);
  if (priceResult.isErr) return PortfolioComparison(window: window);
  final priceMap = priceResult.unwrap();

  final dividendResult = await dividends.historyBatch(tickers);
  final dividendMap =
      dividendResult.getOrElse(const <Ticker, List<DividendEvent>>{});

  final plan = ContributionPlan(
    initial: goal.initialContribution,
    monthly: goal.monthlyContribution,
    contributionDay: settings.contributionDay,
  );

  BacktestOutcome? runFor(Portfolio portfolio) {
    if (portfolio.isEmpty) return null;
    final result = PortfolioBacktest.run(
      portfolio: portfolio,
      prices: priceMap,
      dividends: dividendMap,
      plan: plan,
      range: window,
      taxPolicy: settings.taxPolicy,
      riskFreeRate: riskFree,
    );
    return result.valueOrNull;
  }

  return PortfolioComparison(
    window: window,
    principal: runFor(study.principal),
    reserva: runFor(study.reserva),
  );
});

/// Matriz de correlação entre os ativos da carteira Principal.
///
/// Construída sobre a série de retorno total do próprio domínio, não sobre o
/// `adjustedClose` da fonte — que subajusta proventos brasileiros.
final correlationProvider = FutureProvider<
    ({List<Ticker> tickers, List<List<double>> matrix})?>((ref) async {
  final study = ref.watch(studyProvider).study;
  final tickers = study.principal.tickers;
  if (tickers.length < 2) return null;

  final settings = ref.watch(backtestSettingsProvider);
  final today = DateTime.now();
  final window = DateRange(
    DateTime(today.year - settings.windowYears, today.month, today.day),
    today,
  );

  final priceResult =
      await ref.watch(priceRepositoryProvider).dailyBatch(tickers, window);
  if (priceResult.isErr) return null;
  final priceMap = priceResult.unwrap();

  final dividendResult =
      await ref.watch(dividendRepositoryProvider).historyBatch(tickers);
  final dividendMap =
      dividendResult.getOrElse(const <Ticker, List<DividendEvent>>{});

  final available = tickers.where(priceMap.containsKey).toList();
  if (available.length < 2) return null;

  // Todas as séries pareadas pelo calendário comum: correlação sobre datas
  // desencontradas mediria ruído de calendário, não co-movimento.
  final common = <DateTime>{...priceMap[available.first]!.dates};
  for (final ticker in available.skip(1)) {
    common.retainAll(priceMap[ticker]!.dates);
  }
  final calendar = common.toList()..sort();
  if (calendar.length < 30) return null;

  final returns = <List<double>>[];
  for (final ticker in available) {
    final total = TotalReturnEngine.build(
      prices: priceMap[ticker]!,
      dividends: dividendMap[ticker] ?? const [],
      taxPolicy: settings.taxPolicy,
      range: window,
    );
    final byDate = <DateTime, double>{
      for (var i = 0; i < total.dates.length; i++)
        total.dates[i]: total.index[i],
    };

    final series = <double>[];
    double? previous;
    for (final date in calendar) {
      final value = byDate[date];
      if (value == null || value <= 0) continue;
      if (previous != null && previous > 0) series.add(value / previous - 1);
      previous = value;
    }
    returns.add(series);
  }

  return (
    tickers: available,
    matrix: BetaCalculator.correlationMatrix(returns),
  );
});
