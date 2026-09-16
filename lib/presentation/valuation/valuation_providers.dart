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
  ///
  /// **Dez, como o núcleo e como a decisão 25.** Estava em cinco aqui, contra
  /// dez em `ValuationInputs`, em `DcfAssumptions` e em todas as rodadas de
  /// validação fora da amostra — de modo que o número da tela nunca foi o
  /// número validado. Com cinco, o valor terminal carregava de 63,5% a 80,0%
  /// do preço justo, que é a razão registrada para a escolha de dez.
  ///
  /// A divergência não era só de peso terminal: até 07/09/2026 a Guarda 1 media
  /// a deriva da tendência **no horizonte**, e trocar 10 por 5 virava o veredito
  /// em 13 dos 120 avaliados — a AZZA3 saía de R$ 16,11 para R$ 57,48 na tela.
  /// A guarda foi corrigida para medir na janela do ciclo, e este campo voltou
  /// ao valor da decisão: as duas coisas eram necessárias.
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
    this.projectionYears = 10,
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
    // Âncora top-down da Saída 2, adotada quando o crescimento fundamental não
    // é identificável e a retenção observada a financia (decisão 25).
    inflation: anchors.inflationCagr,
    // Taxa livre de risco de cada ano e da perpetuidade: a curva dos
    // prefixados do Tesouro, que é o padrão (decisão 84). Sem curva recente, a
    // cascata recua para o decaimento do CDI corrente até a média decenal —
    // descontar fluxo perpétuo pela taxa de um dia casaria durações
    // incompatíveis — e o aviso da avaliação diz qual caminho foi usado.
    riskFreeCurve: await ref.watch(riskFreeCurveProvider.future),
    terminalRiskFreeRate: anchors.riskFreeCagr,
    // Contagem oficial da B3: o árbitro do divisor por papel (decisão 83).
    officialShares: await ref.watch(officialSharesProvider(ticker).future),
    isDistressed: (await ref.watch(distressedRegistryProvider.future))
        .contains(ticker.value),
    // Prazo da concessão, do Formulário de Referência: só encurta a projeção
    // quando o contrato acaba dentro dela (decisão 88).
    concessionEnd: await ref.watch(concessionEndProvider(ticker).future),
    // Proventos da B3: o beta sai do retorno total, que é a convenção do
    // Ibovespa do outro lado da regressão (decisão 89).
    dividends: await ref.watch(cashDividendsProvider(ticker).future),
  );
  if (inputs.isErr) return null;

  final result = await ValuationRunner.run(
    ValuationRequest(
      inputs: inputs.unwrap(),
      monteCarlo: settings.monteCarlo,
      samples: settings.samples,
    ),
  );
  final avaliado = result.valueOrNull;
  if (avaliado == null) return null;
  // O que a cascata não enxerga: a avaliação seguiu sem a CVM, ou com um
  // pacote defasado (item A1.10); ou sem curva, e por quê (decisão 86).
  // Nenhum número muda; a ressalva aparece.
  final notas = [
    await ref.watch(cvmCoverageNoteProvider(ticker).future),
    (await ref.watch(riskFreeCurveReadingProvider.future)).note,
  ].nonNulls.toList();
  return notas.isEmpty ? avaliado : avaliado.withWarnings(notas);
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

/// Os sinais transversais dos ativos da carteira Principal (item B1).
///
/// Book-to-market e lucro sobre o preço do último exercício publicado, pela
/// mesma conta que as coortes da validação fazem — ver
/// `TransversalSignals.of`. O potencial vem da avaliação, e não daqui.
final portfolioSignalsProvider =
    FutureProvider<Map<Ticker, TransversalSignals>>((ref) async {
  final tickers = ref.watch(studyProvider).study.principal.tickers;
  final fundamentos = ref.watch(fundamentalsRepositoryProvider);
  final out = <Ticker, TransversalSignals>{};
  for (final t in tickers) {
    final historico = await fundamentos.history(t);
    if (historico.isErr) continue;
    // O exercício publicado na data da avaliação, que o núcleo resolve.
    out[t] = TransversalSignals.fromHistory(historico.unwrap());
  }
  return out;
});

/// Situação da carteira frente à meta patrimonial.
final goalAlignmentProvider = FutureProvider<GoalAlignment?>((ref) async {
  final study = ref.watch(studyProvider).study;
  final goal = study.goal;
  if (goal == null || study.principal.isEmpty) return null;

  final anchors = await ref.watch(marketAnchorsProvider.future);
  final valuations = await ref.watch(portfolioValuationsProvider.future);
  // A ordenação do prêmio é a que a validação escolheu pela regra fixada antes
  // de medir (item B1); sem pacote, ou sem ordenação que passe, não há prêmio.
  final habilidade = await ref.watch(skillReadingProvider.future);
  final sinais = await ref.watch(portfolioSignalsProvider.future);

  // A seção transversal é a das avaliações carregadas, que aqui são as da
  // carteira. É estreita, e o resultado declara o tamanho — ver
  // `ExpectedReturn.crossSection`: quanto mais larga a seção, mais significativo
  // o escore, e medir uma carteira contra ela mesma a centra no CDI.
  final result = EvaluateGoalAlignment.call(
    portfolio: study.principal,
    goal: goal,
    valuations: valuations,
    anchors: anchors,
    ordering: habilidade?.premiumOrdering,
    signals: sinais,
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
