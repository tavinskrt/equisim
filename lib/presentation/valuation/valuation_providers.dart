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

  /// Sorteios de Monte Carlo. Também decide se a avaliação migra para outra
  /// isolate — ver `ValuationRunner.isolateThresholdSamples`.
  final int samples;

  /// Margem de segurança sobre o preço justo, em fração. Zero por padrão: a
  /// margem é decisão do investidor, não premissa do modelo.
  final double marginOfSafety;

  /// Anos de projeção explícita do DCF, antes da perpetuidade.
  final int projectionYears;

  /// Prazo em que se assume a convergência do preço ao valor justo.
  ///
  /// Sem ele, comparar "+40% de upside" com "12% ao ano" seria erro de
  /// unidade: um é total, o outro é por período.
  final int convergenceHorizonMonths;

  /// Prêmio de risco de mercado do CAPM, em fração ao ano.
  final double marketPremium;

  /// Declara os ajustes. **Só [monteCarlo] tem controle na interface**; os
  /// demais ficam nos padrões — parâmetros declarados do modelo, não
  /// configuráveis em tempo de execução.
  const ValuationSettings({
    this.monteCarlo = false,
    this.samples = 10000,
    this.marginOfSafety = 0.0,
    this.projectionYears = 5,
    this.convergenceHorizonMonths = ExpectedReturn.defaultHorizonMonths,
    this.marketPremium = CapmInputs.defaultMarketPremium,
  });

  /// Cópia com os campos informados substituídos.
  ValuationSettings copyWith({
    bool? monteCarlo,
    int? samples,
    double? marginOfSafety,
    int? projectionYears,
    int? convergenceHorizonMonths,
    double? marketPremium,
  }) => ValuationSettings(
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

  /// Alterna entre cenários discretos e Monte Carlo.
  ///
  /// É o **único** ajuste com controle na interface. Os demais campos de
  /// [ValuationSettings] são parâmetros declarados do modelo e ficam fixos nos
  /// respectivos padrões; os mutadores correspondentes existiam sem nenhum
  /// chamador e foram removidos na auditoria de código morto. Reintroduza-os
  /// junto do controle que os aciona.
  void setMonteCarlo(bool enabled) =>
      state = state.copyWith(monteCarlo: enabled);
}

final valuationSettingsProvider =
    NotifierProvider<ValuationSettingsNotifier, ValuationSettings>(
      ValuationSettingsNotifier.new,
    );

/// Avaliação de um ativo isolado.
final valuationProvider = FutureProvider.family<ValuationResult?, Ticker>((
  ref,
  ticker,
) async {
  final settings = ref.watch(valuationSettingsProvider);
  final anchors = await ref.watch(marketAnchorsProvider.future);

  final inputs = await PrepareValuationInputs.call(
    ticker: ticker,
    prices: ref.watch(priceRepositoryProvider),
    fundamentals: ref.watch(fundamentalsRepositoryProvider),
    benchmark: ref.watch(benchmarkRepositoryProvider),
    // CAPM olha para frente: a taxa livre de risco do desconto é a corrente,
    // não a média decenal usada para julgar a viabilidade da meta.
    riskFreeRate: anchors.currentRiskFreeRate,
    marketPremium: settings.marketPremium,
    marginOfSafety: settings.marginOfSafety,
    projectionYears: settings.projectionYears,
    // Desconto nominal exige crescimento perpétuo nominal. O teto sai do IPCA
    // observado, na mesma janela do CDI que forma a taxa livre de risco.
    perpetualGrowthCap: anchors.nominalEconomyGrowth,
  );
  if (inputs.isErr) return null;

  final result = await ValuationRunner.run(
    ValuationRequest(
      inputs: inputs.unwrap(),
      monteCarlo: settings.monteCarlo,
      samples: settings.samples,
    ),
  );
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

/// Situação da carteira frente à meta patrimonial.
final goalAlignmentProvider = FutureProvider<GoalAlignment?>((ref) async {
  final study = ref.watch(studyProvider).study;
  final goal = study.goal;
  if (goal == null || study.principal.isEmpty) return null;

  final settings = ref.watch(valuationSettingsProvider);
  final anchors = await ref.watch(marketAnchorsProvider.future);
  final valuations = await ref.watch(portfolioValuationsProvider.future);

  final result = EvaluateGoalAlignment.call(
    portfolio: study.principal,
    goal: goal,
    valuations: valuations,
    anchors: anchors,
    horizonMonths: settings.convergenceHorizonMonths,
  );
  return result.valueOrNull;
});

/// Viabilidade da meta, independente das avaliações.
///
/// Separado do alinhamento de propósito: o usuário precisa do aviso de meta
/// irreal **enquanto digita** os parâmetros, antes de escolher qualquer ativo.
final goalFeasibilityProvider = FutureProvider<FeasibilityVerdict?>((
  ref,
) async {
  final goal = ref.watch(studyProvider).study.goal;
  if (goal == null) return null;

  final anchors = await ref.watch(marketAnchorsProvider.future);
  final required = RequiredReturnSolver.solve(goal);
  if (required.isErr) return GoalFeasibility.unsolvable(anchors: anchors);

  return GoalFeasibility.assess(
    required: required.unwrap(),
    anchors: anchors,
    goal: goal,
  );
});
