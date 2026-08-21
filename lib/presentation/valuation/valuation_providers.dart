import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/isolate/valuation_runner.dart';
import '../../di/providers.dart';
import '../study/study_notifier.dart';

/// Preferências de avaliação escolhidas pelo usuário.
class ValuationSettings {
  /// Alterna entre as três faixas nomeadas e a distribuição sorteada.
  ///
  /// Os dois modos compartilham o mesmo caminho de código: a troca é
  /// configuração, não refatoração — o que permite decidir qual apresentar
  /// depois de ver os dois funcionando.
  final bool monteCarlo;

  final int samples;
  final double marginOfSafety;
  final int projectionYears;

  /// Prazo em que se assume a convergência do preço ao valor justo.
  ///
  /// Sem ele, comparar "+40% de upside" com "12% ao ano" seria erro de
  /// unidade: um é total, o outro é por período.
  final int convergenceHorizonMonths;

  final double marketPremium;

  const ValuationSettings({
    this.monteCarlo = false,
    this.samples = 10000,
    this.marginOfSafety = 0.0,
    this.projectionYears = 5,
    this.convergenceHorizonMonths = ExpectedReturn.defaultHorizonMonths,
    this.marketPremium = CapmInputs.defaultMarketPremium,
  });

  ValuationSettings copyWith({
    bool? monteCarlo,
    int? samples,
    double? marginOfSafety,
    int? projectionYears,
    int? convergenceHorizonMonths,
    double? marketPremium,
  }) =>
      ValuationSettings(
        monteCarlo: monteCarlo ?? this.monteCarlo,
        samples: samples ?? this.samples,
        marginOfSafety: marginOfSafety ?? this.marginOfSafety,
        projectionYears: projectionYears ?? this.projectionYears,
        convergenceHorizonMonths:
            convergenceHorizonMonths ?? this.convergenceHorizonMonths,
        marketPremium: marketPremium ?? this.marketPremium,
      );
}

class ValuationSettingsNotifier extends Notifier<ValuationSettings> {
  @override
  ValuationSettings build() => const ValuationSettings();

  void setMonteCarlo(bool enabled) =>
      state = state.copyWith(monteCarlo: enabled);
  void setMarginOfSafety(double margin) =>
      state = state.copyWith(marginOfSafety: margin.clamp(0.0, 0.9));
  void setProjectionYears(int years) =>
      state = state.copyWith(projectionYears: years.clamp(1, 20));
  void setConvergenceHorizon(int months) =>
      state = state.copyWith(convergenceHorizonMonths: months.clamp(1, 120));
  void setMarketPremium(double premium) =>
      state = state.copyWith(marketPremium: premium.clamp(0.0, 0.20));
}

final valuationSettingsProvider =
    NotifierProvider<ValuationSettingsNotifier, ValuationSettings>(
  ValuationSettingsNotifier.new,
);

/// Avaliação de um ativo isolado.
final valuationProvider =
    FutureProvider.family<ValuationResult?, Ticker>((ref, ticker) async {
  final settings = ref.watch(valuationSettingsProvider);
  final riskFree = await ref.watch(riskFreeRateProvider.future);

  final inputs = await PrepareValuationInputs.call(
    ticker: ticker,
    prices: ref.watch(priceRepositoryProvider),
    dividends: ref.watch(dividendRepositoryProvider),
    fundamentals: ref.watch(fundamentalsRepositoryProvider),
    benchmark: ref.watch(benchmarkRepositoryProvider),
    riskFreeRate: riskFree,
    marketPremium: settings.marketPremium,
    marginOfSafety: settings.marginOfSafety,
    projectionYears: settings.projectionYears,
  );
  if (inputs.isErr) return null;

  final result = await ValuationRunner.run(ValuationRequest(
    inputs: inputs.unwrap(),
    monteCarlo: settings.monteCarlo,
    samples: settings.samples,
  ));
  return result.valueOrNull;
});

/// Avaliações de todos os ativos da carteira Principal.
///
/// Com teto de 15 ativos e ~2,6 ms por avaliação, a execução sequencial custa
/// dezenas de milissegundos. Paralelizar exigiria um pool de isolates e cópia
/// de payload por ativo — complexidade sem ganho nesta escala.
final portfolioValuationsProvider =
    FutureProvider<Map<Ticker, ValuationResult>>((ref) async {
  final study = ref.watch(studyProvider).study;
  final tickers = study.principal.tickers;
  if (tickers.isEmpty) return const {};

  final out = <Ticker, ValuationResult>{};
  for (final ticker in tickers) {
    final valuation = await ref.watch(valuationProvider(ticker).future);
    if (valuation != null) out[ticker] = valuation;
  }
  return out;
});

/// Dividend yield líquido de imposto, por ativo da carteira Principal.
final netDividendYieldsProvider =
    FutureProvider<Map<Ticker, double>>((ref) async {
  final study = ref.watch(studyProvider).study;
  final dividendRepository = ref.watch(dividendRepositoryProvider);
  final priceRepository = ref.watch(priceRepositoryProvider);
  final today = DateTime.now();
  final window = DateRange(
    DateTime(today.year - 1, today.month, today.day),
    today,
  );

  final out = <Ticker, double>{};
  for (final ticker in study.principal.tickers) {
    final events = await dividendRepository.history(ticker);
    final prices = await priceRepository.daily(ticker, window);
    if (events.isErr || prices.isErr) continue;
    final series = prices.unwrap();
    if (series.isEmpty) continue;

    out[ticker] = PrepareValuationInputs.netTrailingYield(
      events: events.unwrap(),
      currentPrice: series.points.last.close,
      asOf: today,
    );
  }
  return out;
});

/// Situação da carteira frente à meta patrimonial.
final goalAlignmentProvider = FutureProvider<GoalAlignment?>((ref) async {
  final study = ref.watch(studyProvider).study;
  final goal = study.goal;
  if (goal == null || study.principal.isEmpty) return null;

  final settings = ref.watch(valuationSettingsProvider);
  final anchors = await ref.watch(marketAnchorsProvider.future);
  final valuations = await ref.watch(portfolioValuationsProvider.future);
  final yields = await ref.watch(netDividendYieldsProvider.future);

  final result = EvaluateGoalAlignment.call(
    portfolio: study.principal,
    goal: goal,
    valuations: valuations,
    netDividendYields: yields,
    anchors: anchors,
    horizonMonths: settings.convergenceHorizonMonths,
  );
  return result.valueOrNull;
});

/// Viabilidade da meta, independente das avaliações.
///
/// Separado do alinhamento de propósito: o usuário precisa do aviso de meta
/// irreal **enquanto digita** os parâmetros, antes de escolher qualquer ativo.
final goalFeasibilityProvider =
    FutureProvider<FeasibilityVerdict?>((ref) async {
  final goal = ref.watch(studyProvider).study.goal;
  if (goal == null) return null;

  final anchors = await ref.watch(marketAnchorsProvider.future);
  final required = RequiredReturnSolver.solve(goal);
  if (required.isErr) {
    return FeasibilityVerdict(
      level: FeasibilityLevel.unrealistic,
      requiredAnnualRate: double.infinity,
      anchors: anchors,
      message: required.failureOrNull!.message,
    );
  }

  return GoalFeasibility.assess(
    required: required.unwrap(),
    anchors: anchors,
    goal: goal,
  );
});
