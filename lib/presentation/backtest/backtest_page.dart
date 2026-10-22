import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/balance_summary_card.dart';
import '../components/fin_amount.dart';
import '../export/csv_export.dart';
import '../shared/charts.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import '../valuation/valuation_providers.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'backtest_providers.dart';

/// Diz, quando é o caso, que a janela simulada não cobre o prazo da meta.
///
/// Devolve `null` quando não há o que dizer — sem meta, ou com janela que já
/// alcança o prazo inteiro. Aviso que aparece sempre deixa de ser aviso: o
/// leitor aprende a saltá-lo antes de chegar ao caso em que ele importa.
///
/// O prazo é arredondado **para cima**. Uma meta de 66 meses não é coberta
/// por uma janela de cinco anos, e truncar para 5 diria exatamente que é.
String? _horizonNotice(BacktestSettings settings, FinancialGoal? goal) {
  if (goal == null) return null;

  final window = settings.windowYears;
  final term = (goal.months / 12).ceil();
  if (window >= term) return null;

  // "A janela", e nao "a janela simulada": a simulada pode ser MENOR que a
  // pedida quando algum ativo não tem histórico desde o início, e aí dizer que
  // ela cobre cinco anos exageraria a cobertura. O encurtamento tem faixa
  // própria; esta aqui fala do parâmetro, que é o que o leitor acabou de ver.
  final warning =
      'A janela cobre $window dos $term anos da meta. Compare a '
      'RENTABILIDADE, não o patrimônio: o valor final abaixo acumula só parte '
      'do plano de aportes, não o prazo inteiro.';

  if (term <= BacktestSettings.maxWindowYears) return warning;

  return '$warning A fonte de cotações entrega no máximo '
      '${BacktestSettings.maxWindowYears} anos, então nenhuma posição do '
      'controle alcança o prazo da meta.';
}

/// Tela de análise histórica: Principal contra Reserva sob o mesmo plano.
class BacktestPage extends ConsumerWidget {
  const BacktestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparison = ref.watch(comparisonProvider);
    final settings = ref.watch(backtestSettingsProvider);
    final study = ref.watch(studyProvider).study;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(FinSpace.lg),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: _SettingsCard(
                  settings: settings,
                  goal: study.goal,
                ),
              ),
              const SliverToBoxAdapter(child: Gap.md()),
              // O descasamento de horizonte é ressalva do PARÂMETRO, não do
              // resultado: aparece mesmo enquanto a simulação roda, porque é
              // ele que decide como o número que vem abaixo deve ser lido.
              if (_horizonNotice(settings, study.goal) case final warning?) ...[
                SliverToBoxAdapter(
                  child: NoticeBanner(
                    icon: Icons.straighten,
                    message: warning,
                  ),
                ),
                const SliverToBoxAdapter(child: Gap.md()),
              ],
              comparison.when(
                loading: () =>
                    const SliverToBoxAdapter(child: _ComparisonSkeleton()),
                error: (error, _) => SliverToBoxAdapter(
                  child: GlassCard(
                    child: EmptyState(
                      icon: Icons.error_outline,
                      title: 'Falha na simulação',
                      message: '$error',
                    ),
                  ),
                ),
                data: (result) {
                  if (result == null) {
                    return SliverToBoxAdapter(
                      child: GlassCard(
                        child: EmptyState(
                          icon: Icons.timeline,
                          title: 'Nada a simular ainda',
                          message:
                              'Monte a carteira Principal e defina o plano de '
                              'aportes na aba Meta.',
                        ),
                      ),
                    );
                  }
                  return _ComparisonBody(
                    result: result,
                    studyName: study.name,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  final BacktestSettings settings;

  /// Plano da aba Meta, quando já existe. Entra aqui para que a janela seja
  /// declarada **contra o prazo da meta** em vez de sozinha: sem a segunda
  /// linha, "5 anos" não tem com o que ser comparado e o leitor supõe que a
  /// simulação percorre o plano inteiro.
  final FinancialGoal? goal;

  const _SettingsCard({
    required this.settings,
    required this.goal,
  });

  static DateTime _windowStart(int years) {
    final today = DateTime.now();
    return DateTime(today.year - years, today.month, today.day);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(backtestSettingsProvider.notifier);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Parâmetros da simulação',
            subtitle: 'Sem rebalanceamento: os pesos derivam com o mercado',
          ),
          const Gap.sm(),
          LabelValueRow(label: 'Janela', value: '${settings.windowYears} anos'),
          // O prazo da meta, logo abaixo e no MESMO formato em que a aba Meta
          // o escreve. Empilhados, os dois horizontes se comparam sem que o
          // leitor precise guardar um deles na cabeça ao trocar de aba.
          if (goal != null)
            LabelValueRow(
              label: 'Prazo da meta',
              value: Fmt.months(goal!.months),
            ),
          Text(
            'Quanto tempo de história a simulação percorre, contado de hoje '
            'para trás. Com ${settings.windowYears} anos, o plano de aportes '
            'começa em ${Fmt.date.format(_windowStart(settings.windowYears))} '
            'e vai até hoje. Janelas maiores incluem mais ciclos de mercado; '
            'em compensação, exigem que todos os ativos das duas carteiras já '
            'negociassem naquela data — quando algum não negociava, a janela '
            'é encurtada até o primeiro pregão dele.',
            style: context.finType.caption.copyWith(
              color: context.fin.textTertiary,
            ),
          ),
          Slider(
            value: settings.windowYears.toDouble(),
            min: BacktestSettings.minWindowYears.toDouble(),
            max: BacktestSettings.maxWindowYears.toDouble(),
            divisions:
                BacktestSettings.maxWindowYears -
                BacktestSettings.minWindowYears,
            activeColor: context.fin.brand,
            onChanged: (value) => notifier.setWindowYears(value.round()),
          ),
        ],
      ),
    );
  }
}

/// Espaço reservado enquanto a simulação roda.
///
/// Substitui um indicador solto com 48 dp de padding. O problema dele não era
/// a aparência: a área ocupada era uma fração da tela final, então ao chegar o
/// resultado o conteúdo abaixo saltava dezenas de pixels de uma vez.
///
/// A altura aqui aproxima a do primeiro bloco real — cabeçalho, gráfico e
/// cartão de métricas —, de modo que a troca seja preenchimento, não empurrão.
class _ComparisonSkeleton extends StatefulWidget {
  const _ComparisonSkeleton();

  @override
  State<_ComparisonSkeleton> createState() => _ComparisonSkeletonState();
}

class _ComparisonSkeletonState extends State<_ComparisonSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    final reduced = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (!reduced) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return Semantics(
      label: 'Simulando as carteiras',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.45, end: 0.85).animate(_pulse),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(160, 12),
                const Gap.md(),
                // Mesma altura declarada do `Base100Chart`, que e o que ocupa
                // este lugar quando o resultado chega.
                bar(double.infinity, 240),
                const Gap.lg(),
                bar(120, 12),
                const Gap.sm(),
                bar(double.infinity, 64),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparisonBody extends ConsumerWidget {
  final PortfolioComparison result;
  final String studyName;

  const _ComparisonBody({
    required this.result,
    required this.studyName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principal = result.principal;
    final reserve = result.reserve;
    final correlation = ref.watch(correlationProvider);

    if (principal == null && reserve == null) {
      return SliverToBoxAdapter(
        child: GlassCard(
          child: EmptyState(
            icon: Icons.cloud_off,
            title: 'Sem dados de mercado',
            // Dizer o motivo poupa a caçada: quase sempre é um ativo sem
            // cotação no período, e o nome dele está na mensagem da falha.
            message:
                result.principalFailure ??
                result.reserveFailure ??
                'Não foi possível carregar as cotações do período.',
          ),
        ),
      );
    }

    final reference = principal ?? reserve!;
    // As duas carteiras compartilham a janela, então qualquer uma serve de
    // eixo; cada curva ainda leva as próprias datas, para que nenhuma seja
    // desenhada fora de lugar caso um pregão falte a uma delas.
    final axis = <DateTime>{...?principal?.dates, ...?reserve?.dates}.toList()
      ..sort();

    // `SliverList.list`, e nao `Column`: os oito cartoes abaixo carregam
    // graficos e `BackdropFilter`, e como filho unico de um `ListView` eles
    // inflavam todos de uma vez, visiveis ou nao. Como sliver, so os que
    // entram na viewport viram elemento.
    return SliverList.list(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Evolução comparada',
                subtitle: 'Base 100 · ${reference.effectivePeriod}',
                trailing: IconButton(
                  tooltip: 'Exportar CSV',
                  icon: Icon(
                    Icons.download_outlined,
                    size: 19,
                    color: context.fin.brand,
                  ),
                  onPressed: () => exportComparisonCsv(
                    context: context,
                    studyName: studyName,
                    result: result,
                  ),
                ),
              ),
              const Gap.md(),
              Base100Chart(
                dates: axis,
                series: [
                  if (principal != null)
                    ChartSeries(
                      label: 'Principal',
                      values: principal.base100,
                      dates: principal.dates,
                      color: context.fin.brand,
                    ),
                  if (reserve != null)
                    ChartSeries(
                      label: 'Reserva',
                      values: reserve.base100,
                      dates: reserve.dates,
                      color: context.fin.reserve,
                    ),
                ],
              ),
              if (result.twrGap != null) ...[
                const Gap.md(),
                NoticeBanner(
                  icon: Icons.compare_arrows,
                  trend: result.twrGap! >= 0
                      ? FinTrend.positive
                      : FinTrend.negative,
                  // `Fmt.ratio`, e nao `toStringAsFixed`: este ultimo ignora
                  // locale e emite ponto decimal, entao a frase saia com
                  // "76.2 pontos percentuais" ao lado de metricas em "76,2".
                  message: result.twrGap! >= 0
                      ? 'A Principal rendeu '
                            '${Fmt.ratio(result.twrGap!, decimals: 1)} '
                            'pontos percentuais a mais que a Reserva no período.'
                      : 'A Reserva teria rendido '
                            '${Fmt.ratio(result.twrGap!.abs(), decimals: 1)} '
                            'pontos percentuais a mais que a Principal no '
                            'período.',
                ),
              ],
            ],
          ),
        ),
        if (result.windowWasShortened) ...[
          const Gap.md(),
          NoticeBanner(
            icon: Icons.event_busy_outlined,
            message: _shortenedWindowMessage(result),
          ),
        ],
        if (principal == null && result.principalFailure != null) ...[
          const Gap.md(),
          NoticeBanner(
            trend: FinTrend.negative,
            icon: Icons.error_outline,
            message: 'Principal não simulada — ${result.principalFailure}',
          ),
        ],
        if (reserve == null && result.reserveFailure != null) ...[
          const Gap.md(),
          NoticeBanner(
            trend: FinTrend.negative,
            icon: Icons.error_outline,
            message: 'Reserva não simulada — ${result.reserveFailure}',
          ),
        ],
        if (reference.warnings.isNotEmpty) ...[
          const Gap.md(),
          for (final warning in reference.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: FinSpace.sm),
              child: NoticeBanner(message: warning),
            ),
        ],
        if (principal != null) ...[
          const Gap.md(),
          _GoalConfrontationCard(principal: principal, reserve: reserve),
        ],
        // COM AS DUAS carteiras, um cartão comparativo; com uma só, o painel
        // de sempre. A comparação lado a lado é o que a tela existe para
        // fazer, mas ela não tem sentido com uma coluna — e o painel de uma
        // carteira já resolve esse caso há tempo, medido em contraste e em
        // estouro. Manter os dois caminhos custa menos que forçar um layout
        // de comparação a fingir que compara.
        if (principal != null && reserve != null) ...[
          const Gap.md(),
          _SideBySidePortfolios(principal: principal, reserve: reserve),
        ] else ...[
          if (principal != null) ...[
            const Gap.md(),
            _MetricsCard(
              title: 'Carteira Principal',
              outcome: principal,
            ),
          ],
          if (reserve != null) ...[
            const Gap.md(),
            _MetricsCard(
              title: 'Carteira Reserva',
              outcome: reserve,
            ),
            const Gap.sm(),
            const _HypotheticalReserve(),
          ],
        ],
        const Gap.md(),
        _PerAssetCard(principal: principal, reserve: reserve),
        if (result.riskReturn.isNotEmpty) ...[
          const Gap.md(),
          _RiskReturnCard(result: result),
        ],
        correlation.maybeWhen(
          data: (data) => data == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: FinSpace.md),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: 'Correlação entre os ativos',
                          subtitle:
                              'Verde indica menor co-movimento — diversificação',
                        ),
                        const Gap.md(),
                        CorrelationHeatmap(
                          tickers: data.tickers,
                          matrix: data.matrix,
                        ),
                      ],
                    ),
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Explica, em uma frase, por que a janela pedida não pôde ser usada inteira.
String _shortenedWindowMessage(PortfolioComparison result) {
  final limiting = result.limitingTicker;
  final start = Fmt.date.format(result.window.start);
  final requested = Fmt.date.format(result.requestedWindow.start);

  final culprit = limiting == null
      ? 'nem todos os ativos tinham cotação'
      : '${limiting.value} só tem cotação a partir dessa data';

  return 'Janela encurtada: a simulação começa em $start, e não em '
      '$requested, porque $culprit. As duas carteiras usam a mesma janela — '
      'é o que mantém o cronograma de aportes idêntico e torna o TWR '
      'comparável. Reduza a janela para descartar o ativo como restrição.';
}

/// Confronto entre a rentabilidade que a meta EXIGE e a que a janela simulada
/// de fato ENTREGOU.
///
/// É o cartão que faltava para a aba fechar sobre a Meta. O glossário do XIRR,
/// logo abaixo, sempre disse que "é este o número a confrontar com a meta" — e
/// o confronto não existia em tela alguma: quem confrontava era a aba Meta, e
/// não com o XIRR, e sim com o retorno esperado derivado do valuation.
///
/// **Projeção e evidência respondem à mesma pergunta com autoridades
/// diferentes**, e as duas importam. Lá, o que a avaliação implica; aqui, o
/// que a composição entregou. Por isso este cartão repete os rótulos daquele
/// — `Exigido`, `Realizado`, `Folga` — em vez de inventar vocabulário: é a
/// mesma grandeza, medida de outro jeito.
///
/// **Confronta TAXAS, nunca patrimônios.** A janela simulada quase sempre é
/// mais curta que o prazo da meta, e taxas anualizadas se comparam entre
/// períodos de durações diferentes enquanto patrimônios não. Projetar o alvo
/// sobre a janela seria aritmética nova, e aritmética nova mora no núcleo.
class _GoalConfrontationCard extends ConsumerWidget {
  /// Resultado da carteira **Principal**. É contra ela que a meta é avaliada,
  /// como já faz `goalAlignmentProvider` na aba Meta.
  final BacktestOutcome principal;

  /// Resultado da Reserva, quando houve. Rende uma linha subordinada: a
  /// pergunta "e se eu tivesse montado a outra?" é a razão de a aba existir.
  final BacktestOutcome? reserve;

  const _GoalConfrontationCard({required this.principal, required this.reserve});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verdict = ref.watch(goalFeasibilityProvider);

    return verdict.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (v) {
        // Taxa ausente é meta que o solver não resolveu. A aba Meta já
        // explica o porquê; repetir aqui um travessão sem contexto só ocuparia
        // espaço.
        final requiredText = v?.requiredAnnualRate;
        if (requiredText == null || !requiredText.isFinite) {
          return const SizedBox.shrink();
        }
        final realized = principal.metrics.moneyWeightedReturn;
        final margin = realized == null ? null : (realized - requiredText) * 100;

        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                // **"Realizado", e não "frente à meta"** (lente `tela`,
                // 22/09/2026). A tela de Meta tem um cartão de mesmo nome que
                // mostra o **esperado** — projeção —, e este mostra o
                // **realizado** da simulação. Dois blocos de layout parecido,
                // mesmo título e naturezas opostas: quem lê +78% aqui e +15%
                // lá não tem como saber que um é passado e o outro é
                // promessa.
                title: 'O realizado frente à meta',
                subtitle: 'No período simulado · ${principal.effectivePeriod}',
              ),
              const Gap.md(),
              MetricTileRow(
                tiles: [
                  MetricTile(
                    label: Lexicon.requiredText,
                    value: Fmt.percent(requiredText),
                    hint: Lexicon.requiredPerYear,
                  ),
                  MetricTile(
                    label: Lexicon.realized,
                    value: realized == null
                        ? '—'
                        : Fmt.percent(realized, signed: true),
                    hint: Lexicon.realizedXirr,
                    trend: FinAmount.trendOf(realized),
                  ),
                  MetricTile(
                    label: Lexicon.margin,
                    value: margin == null ? '—' : Fmt.points(margin),
                    trend: FinAmount.trendOf(margin),
                  ),
                ],
              ),
              const Gap.sm(),
              Text(
                'O exigido vem do plano da aba Meta. O realizado é o XIRR da '
                'janela simulada, só de preço — a simulação não distribui '
                'provento —: o que esta composição entregou no passado, e não '
                'o que ela promete para o prazo da meta.',
                style: context.finType.caption.copyWith(
                  color: context.fin.textTertiary,
                ),
              ),
              if (reserve != null) ...[
                const Gap.sm(),
                Builder(
                  builder: (context) {
                    final alternative = reserve!.metrics.moneyWeightedReturn;
                    if (alternative == null) return const SizedBox.shrink();
                    final alternativeMargin = (alternative - requiredText) * 100;
                    // Sem ponto final: `Fmt.points` termina em "p.p.", e a
                    // abreviação já carrega o ponto que fecha a frase.
                    return Text(
                      'A Reserva, sob os mesmos aportes, teria rendido '
                      '${Fmt.percent(alternative, signed: true)} ao ano — '
                      'folga de ${Fmt.points(alternativeMargin)}',
                      style: context.finType.caption.copyWith(
                        color: context.fin.textSecondary,
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Glossário dos indicadores do cartão de métricas.
///
/// Mora fora do widget porque as duas carteiras exibem exatamente os mesmos
/// números: texto duplicado é convite para as duas explicações divergirem.
const List<HintEntry> _metricsGlossary = [
  HintEntry(
    'Patrimônio final',
    'Quanto a carteira valeria ao fim do período: as posições a preço de '
        'mercado mais o caixa que sobrou. Abaixo do valor vêm o aportado e o '
        'alocado — a diferença entre o patrimônio e o aportado é o ganho.',
  ),
  HintEntry(
    'Aportado × alocado',
    'O aportado é o dinheiro que o investidor disponibilizou, e é o número '
        'que ele já conhece. O alocado é quanto disso virou ação, depois de '
        'cada aporte ser dividido pelos pesos da carteira. A diferença é o '
        'caixa: a sobra que não completou mais uma ação inteira e espera o '
        'aporte seguinte — nada se perde, e ela conta no patrimônio.',
  ),
  HintEntry(
    'TWR — retorno ponderado pelo tempo',
    'Rentabilidade da composição, neutra ao cronograma de aportes. É por ele '
        'que Principal e Reserva se comparam: as duas recebem os mesmos '
        'aportes nas mesmas datas, então o que sobra de diferença é a escolha '
        'dos ativos.',
  ),
  HintEntry(
    'XIRR — retorno ponderado pelo dinheiro',
    'A rentabilidade que o investidor de fato obteve, porque considera quanto '
        'entrou e em que data. É este o número a confrontar com a meta.',
  ),
  HintEntry(
    'CAGR',
    'O TWR convertido em taxa média ao ano. Serve para comparar janelas de '
        'durações diferentes na mesma unidade.',
  ),
  HintEntry(
    'Volatilidade',
    'Desvio-padrão dos retornos diários, anualizado. Mede oscilação, não '
        'perda: uma carteira pode balançar muito e ainda terminar acima.',
  ),
  HintEntry(
    'Máx. drawdown',
    'A maior queda do topo ao fundo dentro do período. Responde quanto o '
        'investidor teria visto sumir no pior trecho.',
  ),
  HintEntry(
    'Sharpe',
    'Retorno acima do CDI dividido pela volatilidade total — quanto de prêmio '
        'cada unidade de oscilação entregou.',
  ),
  HintEntry(
    'Sortino',
    'Como o Sharpe, mas só a oscilação de queda entra na conta: não penaliza '
        'a volatilidade que trabalhou a favor.',
  ),
  HintEntry(
    'Calmar',
    'Retorno anualizado dividido pelo máximo drawdown — prêmio por unidade da '
        'pior queda enfrentada.',
  ),
];

/// Glossário das colunas do cartão de desempenho por ativo.
const List<HintEntry> _perAssetGlossary = [
  HintEntry(
    'alvo → atual',
    'O peso estipulado quando o ativo entrou e o peso que ele tem ao fim do '
        'período. A simulação não rebalanceia: quem sobe passa a pesar mais '
        'sozinho.',
  ),
  HintEntry(
    'Deriva (p.p.)',
    'A distância entre os dois pesos, em pontos percentuais. Positiva quando o '
        'ativo ganhou espaço na carteira, negativa quando perdeu.',
  ),
  HintEntry(
    'Cotas · destinado',
    'Quantas cotas a simulação acumulou no ativo — ações ou cotas de fundo — '
        'e quanto capital ele recebeu dos aportes. A quantidade é INTEIRA: '
        'cada aporte compra o que couber em lotes de uma, ao preço do dia, e a '
        'sobra fica no caixa do ativo esperando o aporte seguinte.',
  ),
  HintEntry(
    'Retorno',
    'Quanto o capital destinado àquele ativo rendeu no período, contando a '
        'posição a mercado mais o caixa dela. É retorno de PREÇO: a simulação '
        'não distribui provento. Como as duas carteiras rodam na mesma janela '
        'e sob o mesmo cronograma de aportes, os retornos são comparáveis '
        'entre Principal e Reserva.',
  ),
  HintEntry(
    'Por que ele difere do gráfico do ativo',
    'Este número mede o que o SEU dinheiro fez, não o que o preço fez. Com '
        'aporte mensal, quem cai e volta rende — o aporte comprou barato no '
        'meio —, e quem sobe e volta perde. Dois ativos que começam e terminam '
        'no mesmo preço, um em vale e outro em pico, chegam aqui a 56,5 pontos '
        'percentuais de distância. As duas leituras são verdadeiras e '
        'respondem a perguntas diferentes; esta responde a que importa para a '
        'troca entre carteiras, porque é o dinheiro que de fato seguiu este '
        'cronograma.',
  ),
];

/// Ressalva sobre o que o patrimônio da Reserva significa.
///
/// A palavra "Reserva" muda de sentido entre as telas, e é aqui que a troca
/// machuca. Na tela de estudo ela é **banco de candidatos** — ativos que
/// talvez entrem na Principal. Na simulação ela é **carteira paralela
/// completa**, recebendo os mesmos aportes, porque é isso que mantém o
/// cronograma idêntico e torna o TWR comparável.
///
/// Sem dizê-lo onde o número aparece, ler "Carteira Reserva · R$ 1.193,66"
/// como dinheiro que se teria é imediato — e é falso.
class _HypotheticalReserve extends StatelessWidget {
  const _HypotheticalReserve();

  @override
  Widget build(BuildContext context) => Text(
    'A Reserva é um banco de candidatos; aqui ela é simulada como carteira '
    'inteira, sob os mesmos aportes da Principal. É o que torna a comparação '
    'possível — e faz do patrimônio dela um valor hipotético.',
    style: context.finType.caption.copyWith(color: context.fin.textTertiary),
  );
}

/// Uma carteira na comparação: o nome que a identifica e a cor do selo.
typedef _Column = ({String name, Color color});

/// Nome da carteira sob o ponto colorido dela.
///
/// Um widget só para os dois lugares que o desenham — o cabeçalho das tabelas
/// comparativas e o grupo do cartão de desempenho por ativo. Eram duas cópias
/// do mesmo `Row`, e o ponto saía com diâmetro literal em cada uma.
class _PortfolioBadge extends StatelessWidget {
  final String name;

  /// Cor do ponto **e do texto**. Pinta tinta, então vem do token medido em
  /// contraste, nunca da variante de marca.
  final Color color;

  /// Encosta o conteúdo na direita, para o selo alinhar com a coluna de
  /// números que ele encabeça.
  final bool alignRight;

  const _PortfolioBadge({
    required this.name,
    required this.color,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: alignRight
        ? MainAxisAlignment.end
        : MainAxisAlignment.start,
    children: [
      Container(
        // `FinSpace.sm`, e não um literal: o projeto anda numa grade de 4 dp,
        // e diâmetro solto é a porta por onde a grade se perde.
        width: FinSpace.sm,
        height: FinSpace.sm,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const Gap.xs(axis: Axis.horizontal),
      Flexible(
        child: Text(
          name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.finType.caption.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ),
    ],
  );
}

/// O valor de uma carteira numa linha da comparação.
typedef _Cell = ({String text, FinTrend trend});

/// Uma linha da comparação: o indicador, sua ressalva, e um valor por carteira.
///
/// [highlight] marca a grandeza principal do cartão. Sem ele todas as linhas
/// dividiriam o mesmo peso tipográfico, e o patrimônio final se leria com a
/// mesma voz do índice de Calmar — o defeito que o `BalanceSummaryCard` foi
/// construído para resolver, reintroduzido pela porta da tabela.
typedef _Row = ({
  String label,
  String? note,
  bool highlight,
  List<_Cell> cells,
});

/// Tabela de indicadores com uma coluna por carteira.
///
/// Existe porque comparar era rolar. Com um cartão por carteira, conferir o
/// Sharpe da Principal contra o da Reserva obrigava a percorrer oito métricas
/// e um cabeçalho no caminho — a lente `tela` registrou o percurso como
/// tensão. Em coluna, a mesma comparação é um movimento de olho.
///
/// **O cabeçalho de coluna não é decoração.** Sem o selo colorido repetindo o
/// nome da carteira, o leitor precisa lembrar a ordem em que elas aparecem —
/// e patrimônio é exatamente o tipo de número que se atribui à carteira
/// errada.
///
/// Largura MEDIDA do conteúdo, e queda para blocos empilhados quando não cabe.
/// Uma tabela numérica densa não sobrevive a 320 dp sob escala de texto 2,0x
/// em nenhuma disposição lado a lado: dois valores de `R$ 1.300,62` sozinhos
/// passam da largura da tela. Empilhar devolve o percurso antigo, que é ruim —
/// mas truncar o número seria pior, e estourar o layout, inaceitável.
class _ComparisonTable extends StatelessWidget {
  final List<_Column> columns;
  final List<_Row> rows;

  const _ComparisonTable({required this.columns, required this.rows});

  static const double _gap = FinSpace.sm;

  @override
  Widget build(BuildContext context) {
    final t = context.finType;
    final c = context.fin;

    final labelStyle = t.caption.copyWith(color: c.textSecondary);
    final noteStyle = t.caption.copyWith(color: c.textTertiary);
    final valueStyle = t.numSm;
    // A linha em destaque pinta em `numMd`, e a coluna precisa caber o mais
    // largo dos DOIS papéis -- medir só o menor truncaria justamente o número
    // que se quis destacar.
    final highlightStyle = t.numMd;
    final badgeStyle = t.caption.copyWith(
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );

    // Largura do rótulo: o mais largo entre indicador e ressalva. É PISO, não
    // teto -- a coluna recebe o que sobra e o texto quebra em duas linhas se
    // precisar; o que a medida garante é que ela nunca comece apertada demais
    // para caber uma palavra.
    var labelWidth = 0.0;
    for (final row in rows) {
      final r = FinAmount.measure(context, row.label, labelStyle);
      if (r > labelWidth) labelWidth = r;
      final note = row.note;
      if (note != null) {
        final n = FinAmount.measure(context, note, noteStyle);
        if (n > labelWidth) labelWidth = n;
      }
    }

    // Largura do valor: o mais largo da tabela inteira, e não da coluna. Medir
    // por coluna daria larguras diferentes para grandezas iguais, e a
    // comparação depende justamente de os dois números começarem no mesmo x.
    var valueWidth = 0.0;
    for (final row in rows) {
      final style = row.highlight ? highlightStyle : valueStyle;
      for (final cell in row.cells) {
        final v = FinAmount.measure(context, cell.text, style);
        if (v > valueWidth) valueWidth = v;
      }
    }
    for (final column in columns) {
      // O selo ocupa a coluna como qualquer valor: ponto, respiro e nome.
      final w =
          FinAmount.measure(context, column.name.toUpperCase(), badgeStyle) +
          FinSpace.sm +
          FinSpace.xs;
      if (w > valueWidth) valueWidth = w;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth = labelWidth + columns.length * (valueWidth + _gap);
        if (requiredWidth > constraints.maxWidth) {
          return _stacked();
        }
        return _sideBySide(
          labelWidth: labelWidth,
          valueWidth: valueWidth,
          labelStyle: labelStyle,
          noteStyle: noteStyle,
          valueStyle: valueStyle,
          highlightStyle: highlightStyle,
        );
      },
    );
  }

  Widget _sideBySide({
    required double labelWidth,
    required double valueWidth,
    required TextStyle labelStyle,
    required TextStyle noteStyle,
    required TextStyle valueStyle,
    required TextStyle highlightStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: labelWidth),
            for (final column in columns) ...[
              const Gap.sm(axis: Axis.horizontal),
              SizedBox(
                width: valueWidth,
                child: _PortfolioBadge(
                  name: column.name,
                  color: column.color,
                  alignRight: true,
                ),
              ),
            ],
            // A sobra fica DEPOIS das colunas, não dentro do rótulo. Com o
            // rótulo flexível, os 1024 dp da tela larga entravam todos entre o
            // nome do indicador e o número dele, e a linha deixava de se ler
            // como linha.
            const Spacer(),
          ],
        ),
        const Gap.sm(),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FinSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  // Medida, e não flexível: ver o `Spacer` do cabeçalho.
                  width: labelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.label, style: labelStyle),
                      if (row.note case final note?)
                        Text(note, style: noteStyle),
                    ],
                  ),
                ),
                for (final cell in row.cells) ...[
                  const Gap.sm(axis: Axis.horizontal),
                  SizedBox(
                    width: valueWidth,
                    // O `Align` não é decorativo: `FinAmount` embrulha o texto
                    // num `AnimatedSwitcher`, que CENTRALIZA o filho na caixa
                    // recebida. Sem ele, "2,86" ficava centrado sob "14,68" e
                    // a vírgula decimal dançava de uma linha para a outra --
                    // que é exatamente o que a cifra tabular existe para
                    // impedir.
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FinAmount(
                        text: cell.text,
                        style: row.highlight ? highlightStyle : valueStyle,
                        trend: cell.trend,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
              ],
            ),
          ),
      ],
    );
  }

  /// Uma carteira de cada vez, quando a largura não sustenta as colunas.
  ///
  /// `LabelValueRow` de propósito: ele não estoura em largura nenhuma, porque
  /// o valor desce de linha em vez de disputar espaço com o rótulo.
  Widget _stacked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) const Gap.md(),
          _PortfolioBadge(name: columns[i].name, color: columns[i].color),
          const Gap.xs(),
          for (final row in rows)
            LabelValueRow(
              label: row.label,
              value: row.cells[i].text,
              trend: row.cells[i].trend,
            ),
        ],
      ],
    );
  }
}

/// Percentual de uma métrica como célula da comparação.
_Cell _pct(double value, {bool signed = false, FinTrend? trend}) => (
  text: Fmt.percent(value, signed: signed),
  trend: trend ?? (signed ? FinAmount.trendOf(value) : FinTrend.neutral),
);

/// Razão adimensional como célula da comparação.
_Cell _ratio(double value) => (text: Fmt.ratio(value), trend: FinTrend.neutral);

/// Dinheiro como célula da comparação.
_Cell _money(double reais, {FinTrend trend = FinTrend.neutral}) => (
  text: Fmt.money(reais),
  trend: trend,
);

/// Indicadores das duas carteiras em colunas, no lugar de um cartão para cada.
///
/// Só entra em cena com as DUAS simuladas. Ver a justificativa no ponto de uso.
class _SideBySidePortfolios extends StatelessWidget {
  final BacktestOutcome principal;
  final BacktestOutcome reserve;

  const _SideBySidePortfolios({required this.principal, required this.reserve});

  @override
  Widget build(BuildContext context) {
    final portfolios = [principal, reserve];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Carteiras lado a lado',
            subtitle:
                'Mesma janela e mesmos aportes — só a composição difere',
            trailing: HintIcon(
              title: 'Indicadores das duas carteiras',
              intro:
                  'Todos se referem à janela simulada. As duas carteiras '
                  'recebem aportes idênticos nas mesmas datas — só a '
                  'composição difere, então o que sobra de diferença entre '
                  'as colunas é a escolha dos ativos.',
              entries: _metricsGlossary,
            ),
          ),
          const Gap.md(),
          _ComparisonTable(
            columns: [
              (name: 'Principal', color: context.fin.brand),
              (name: 'Reserva', color: context.fin.reserve),
            ],
            rows: [
              (
                label: 'Patrimônio final',
                highlight: true,
                note: 'posições mais caixa',
                cells: [
                  for (final o in portfolios) _money(o.finalValue.reais),
                ],
              ),
              (
                label: 'Aportado',
                highlight: false,
                note: 'capital do investidor',
                cells: [
                  for (final o in portfolios) _money(o.totalContributed.reais),
                ],
              ),
              (
                label: 'Alocado',
                highlight: false,
                note: 'do aportado, o que virou ação',
                cells: [
                  for (final o in portfolios) _money(o.totalAllocated.reais),
                ],
              ),
              (
                label: 'Custos',
                highlight: false,
                note: 'tarifa da B3 nas compras',
                cells: [
                  for (final o in portfolios) _money(o.transactionCosts.reais),
                ],
              ),
              (
                label: 'Em caixa',
                highlight: false,
                note: 'sobra à espera do próximo aporte',
                cells: [
                  for (final o in portfolios) _money(o.residualCash.reais),
                ],
              ),
              (
                label: 'TWR',
                highlight: false,
                note: 'da composição',
                cells: [
                  for (final o in portfolios)
                    _pct(o.metrics.timeWeightedReturn, signed: true),
                ],
              ),
              (
                label: 'XIRR',
                highlight: false,
                note: 'retorno do investidor',
                cells: [
                  for (final o in portfolios)
                    o.metrics.moneyWeightedReturn == null
                        ? (text: '—', trend: FinTrend.blocked)
                        : _pct(o.metrics.moneyWeightedReturn!, signed: true),
                ],
              ),
              (
                label: 'CAGR',
                highlight: false,
                note: null,
                cells: [
                  for (final o in portfolios) _pct(o.metrics.cagr, signed: true),
                ],
              ),
              (
                label: 'Volatilidade',
                highlight: false,
                note: 'anualizada',
                cells: [for (final o in portfolios) _pct(o.metrics.volatility)],
              ),
              (
                label: 'Máx. drawdown',
                highlight: false,
                note: null,
                cells: [
                  for (final o in portfolios)
                    _pct(o.metrics.maxDrawdown, trend: FinTrend.negative),
                ],
              ),
              (
                label: 'Sharpe',
                highlight: false,
                note: 'vs CDI observado',
                cells: [for (final o in portfolios) _ratio(o.metrics.sharpe)],
              ),
              (
                label: 'Sortino',
                highlight: false,
                note: null,
                cells: [for (final o in portfolios) _ratio(o.metrics.sortino)],
              ),
              (
                label: 'Calmar',
                highlight: false,
                note: null,
                cells: [for (final o in portfolios) _ratio(o.metrics.calmar)],
              ),
            ],
          ),
          const Gap.md(),
          const _HypotheticalReserve(),
        ],
      ),
    );
  }
}

/// Legenda de capital sob o patrimônio: o que entrou e o que virou ação.
///
/// Os dois juntos porque o aportado sozinho não responde nada — é o valor que
/// o próprio investidor estipulou na aba Meta, e ele já o conhece antes de
/// abrir a tela. O que a simulação acrescenta é quanto desse dinheiro o motor
/// conseguiu transformar em ação depois de dividir cada aporte pelos pesos da
/// carteira e comprar em lotes inteiros.
///
/// **O caixa só é nomeado acima de um real.** Ele é a sobra que não completou
/// mais uma ação e espera o aporte seguinte, e escrever "R$ 0,40 em caixa" ao
/// lado de um patrimônio de seis dígitos transformaria troco em fato
/// econômico. Acima de um real o número passa a dizer algo — que a carteira
/// tem papel caro diante do aporte — e o leitor precisa vê-lo.
///
/// **Nunca é negativo, e nunca some.** A divisão de cada aporte distribui o
/// resto e a fatia de um ativo sem cotação no dia fica no caixa dele, de modo
/// que aportado = alocado + custos + caixa exatamente — a tarifa da B3 sai do
/// caixa antes da compra (item C4).
String _capitalCaption(BacktestOutcome outcome) {
  final base =
      'aportado ${Fmt.money(outcome.totalContributed.reais)} · '
      'alocado ${Fmt.money(outcome.totalAllocated.reais)} · '
      'custos ${Fmt.money(outcome.transactionCosts.reais)}';

  final cash = outcome.residualCash;
  if (cash.cents < 100) return base;

  return '$base — ${Fmt.money(cash.reais)} em caixa';
}

/// Indicadores de uma carteira na janela simulada.
///
/// O patrimônio final passou a ser a grandeza principal do cartão, em `numLg`,
/// com o aportado e o alocado logo abaixo; as nove métricas restantes ficam em
/// `numMd`. Antes as dez dividiam o mesmo tamanho, o que obrigava o leitor a
/// procurar qual delas era o número que importa.
class _MetricsCard extends StatelessWidget {
  final String title;
  final BacktestOutcome outcome;

  const _MetricsCard({
    required this.title,
    required this.outcome,
  });

  @override
  Widget build(BuildContext context) {
    final m = outcome.metrics;

    return GlassCard(
      child: BalanceSummaryCard(
        label: title,
        balance: Fmt.money(outcome.finalValue.reais),
        balanceSemantics:
            'Patrimônio final ${Fmt.money(outcome.finalValue.reais)}',
        caption: _capitalCaption(outcome),
        changeLabel: Fmt.percent(m.timeWeightedReturn, signed: true),
        changeTrend: FinAmount.trendOf(m.timeWeightedReturn),
        trailing: HintIcon(
          title: 'Indicadores da $title',
          intro:
              'Todos se referem à janela simulada. As duas carteiras '
              'recebem aportes idênticos nas mesmas datas — só a '
              'composição difere.',
          entries: _metricsGlossary,
        ),
        metrics: [
          BalanceMetric(
            label: 'XIRR',
            value: m.moneyWeightedReturn == null
                ? '—'
                : Fmt.percent(m.moneyWeightedReturn!, signed: true),
            hint: 'retorno do investidor',
            trend: FinAmount.trendOf(m.moneyWeightedReturn),
          ),
          BalanceMetric(
            label: 'CAGR',
            value: Fmt.percent(m.cagr, signed: true),
            trend: FinAmount.trendOf(m.cagr),
          ),
          BalanceMetric(
            label: 'Volatilidade',
            value: Fmt.percent(m.volatility),
            hint: 'anualizada',
          ),
          BalanceMetric(
            label: 'Máx. drawdown',
            value: Fmt.percent(m.maxDrawdown),
            trend: FinTrend.negative,
          ),
          BalanceMetric(
            label: 'Sharpe',
            value: Fmt.ratio(m.sharpe),
            hint: 'vs CDI observado',
          ),
          BalanceMetric(label: 'Sortino', value: Fmt.ratio(m.sortino)),
          BalanceMetric(label: 'Calmar', value: Fmt.ratio(m.calmar)),
        ],
      ),
    );
  }
}

/// Desempenho individual dos ativos das **duas** carteiras.
///
/// A Reserva existe para abastecer a Principal, e a troca só se decide com os
/// dois desempenhos à vista ao mesmo tempo. Num cartão só, ordenados por
/// retorno, o pior ativo detido fica no fim da primeira lista e o melhor
/// candidato no topo da segunda — as duas linhas que interessam ficam
/// encostadas uma na outra.
///
/// A comparação entre carteiras se sustenta porque ambas rodam na mesma janela
/// e sob o mesmo cronograma de aportes; sem isso os retornos por ativo
/// mediriam períodos diferentes.
class _PerAssetCard extends StatelessWidget {
  final BacktestOutcome? principal;
  final BacktestOutcome? reserve;

  const _PerAssetCard({
    required this.principal,
    required this.reserve,
  });

  /// Ativos da carteira, do melhor para o pior retorno no período.
  static List<AssetPerformance> _ranked(BacktestOutcome? outcome) {
    if (outcome == null) return const [];
    return outcome.perAsset.values.toList()
      ..sort((a, b) => b.totalReturn.compareTo(a.totalReturn));
  }

  @override
  Widget build(BuildContext context) {
    final principalAssets = _ranked(principal);
    final reserveAssets = _ranked(reserve);
    if (principalAssets.isEmpty && reserveAssets.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasBoth = principalAssets.isNotEmpty && reserveAssets.isNotEmpty;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Desempenho por ativo',
            subtitle: hasBoth
                ? 'Do melhor ao pior retorno em cada carteira'
                : 'A deriva de peso é sinal de decisão, não defeito',
            trailing: HintIcon(
              title: 'Desempenho por ativo',
              intro:
                  'Cada linha é um ativo dentro da sua carteira, do melhor '
                  'ao pior retorno no período. A Reserva guarda candidatos a '
                  'entrar na Principal: com as duas listas ordenadas, o pior '
                  'ativo detido fica no fim da primeira e o melhor candidato '
                  'no topo da segunda.',
              entries: _perAssetGlossary,
            ),
          ),
          const Gap.sm(),
          if (principalAssets.isNotEmpty)
            _AssetGroup(
              label: 'Principal',
              color: context.fin.brand,
              assets: principalAssets,
            ),
          if (hasBoth) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FinSpace.sm),
              child: Divider(height: 1, color: context.fin.divider),
            ),
            // A frase mora ENTRE os grupos porque é a junção que ela descreve.
            // Acima ou abaixo do cartão, ela viraria comentário geral; aqui,
            // aponta para as duas linhas que o leitor tem diante dos olhos.
            _AdjacentPair(
              worstHolding: principalAssets.last,
              bestCandidate: reserveAssets.first,
            ),
            const Gap.sm(),
          ],
          if (reserveAssets.isNotEmpty)
            _AssetGroup(
              label: 'Reserva',
              // Este `color` pinta TEXTO -- o rotulo do grupo. Por isso vem do
              // token medido em contraste, e nao da variante de marca.
              color: context.fin.reserve,
              assets: reserveAssets,
            ),
        ],
      ),
    );
  }
}

/// Nomeia, em texto, o par que a ordenação das duas listas põe lado a lado.
///
/// O cartão ordena cada carteira do melhor ao pior retorno, e o comentário que
/// justifica esse arranjo diz o motivo: assim o **pior ativo detido** fica no
/// fim da primeira lista e o **melhor candidato** no topo da segunda, encostados
/// um no outro. A adjacência era intencional e ficava implícita — quem não lesse
/// o glossário via duas listas ordenadas, não um par.
///
/// **Não promete resultado.** A simulação roda a Principal como ela é; nenhuma
/// carteira trocada foi calculada. O que se afirma é a distância entre dois
/// retornos observados, e a ressalva diz isso com todas as letras — um número
/// que parece conselho é pior que número nenhum.
class _AdjacentPair extends StatelessWidget {
  /// Último da Principal na ordenação: o pior retorno entre os detidos.
  final AssetPerformance worstHolding;

  /// Primeiro da Reserva: o melhor retorno entre os candidatos.
  final AssetPerformance bestCandidate;

  const _AdjacentPair({
    required this.worstHolding,
    required this.bestCandidate,
  });

  static String _pct(double v) => Fmt.percent(v, decimals: 1, signed: true);

  @override
  Widget build(BuildContext context) {
    final difference =
        (bestCandidate.totalReturn - worstHolding.totalReturn) * 100;

    // Candidato que não superou ninguém também é resposta, e das úteis: diz
    // que não há troca sugerida pelo período. Silenciar aqui faria a frase
    // aparecer só quando conveniente, e uma observação que só fala a favor
    // deixa de ser observação.
    final sentence = difference > 0
        ? 'No encontro das duas listas: ${worstHolding.ticker.value} é o pior '
              'retorno da Principal (${_pct(worstHolding.totalReturn)}) e '
              '${bestCandidate.ticker.value} o melhor da Reserva '
              '(${_pct(bestCandidate.totalReturn)}) — '
              '${Fmt.points(difference)} de diferença.'
        : 'Nenhum candidato da Reserva superou o pior ativo da Principal no '
              'período: ${worstHolding.ticker.value} rendeu '
              '${_pct(worstHolding.totalReturn)} e '
              '${bestCandidate.ticker.value}, o melhor da Reserva, '
              '${_pct(bestCandidate.totalReturn)}.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sentence,
          style: context.finType.caption.copyWith(
            color: context.fin.textSecondary,
          ),
        ),
        const Gap.xs(),
        Text(
          'A simulação não roda a carteira trocada — a distância é o que os '
          'retornos do período dizem, não recomendação de troca.',
          style: context.finType.caption.copyWith(
            color: context.fin.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Os ativos de uma carteira sob o selo colorido dela.
class _AssetGroup extends StatelessWidget {
  final String label;
  final Color color;
  final List<AssetPerformance> assets;

  const _AssetGroup({
    required this.label,
    required this.color,
    required this.assets,
  });

  /// Largura da coluna de ticker e da coluna de valor, medidas do conteudo
  /// real deste grupo sob a escala de texto corrente.
  ///
  /// Substitui as constantes `width: 62` e `width: 74`. Largura em pixel
  /// logico alinha em 1,0x e trunca em 1,3x: um `-1.234,5%` pede cerca de
  /// 81 dp contra os 74 que havia, e o corte nao produz aviso nenhum -- dentro
  /// de um `SizedBox` nao aparece a listra de overflow.
  ///
  /// Medir do conteudo, e nao de uma amostra chutada, e o que mantem a coluna
  /// justa: ela cresce exatamente o quanto o maior valor da lista precisa.
  ({double ticker, double value}) _columnWidths(BuildContext context) {
    final tickerStyle = context.finType.bodySm.copyWith(
      fontWeight: FontWeight.w600,
    );
    final valueStyle = context.finType.numSm;
    // `numSm`, e nao `caption`: a deriva e um numero, e numero nesta coluna
    // precisa de cifra tabular como o retorno logo acima -- senao as duas
    // linhas empilhadas desalinham a virgula entre si.
    final driftStyle = context.finType.numSm;

    var ticker = 0.0;
    var value = 0.0;

    for (final asset in assets) {
      final t = FinAmount.measure(context, asset.ticker.value, tickerStyle);
      if (t > ticker) ticker = t;

      // A coluna carrega dois textos empilhados; ela precisa caber o mais
      // largo dos dois, nao so o retorno.
      final r = FinAmount.measure(
        context,
        Fmt.percent(asset.totalReturn, decimals: 1, signed: true),
        valueStyle,
      );
      if (r > value) value = r;

      final d = FinAmount.measure(context, Fmt.points(asset.drift), driftStyle);
      if (d > value) value = d;
    }

    return (ticker: ticker + FinSpace.sm, value: value + FinSpace.xs);
  }

  /// Largura mínima para a coluna do meio significar alguma coisa.
  ///
  /// Ela carrega os pesos e a barra de deriva. Abaixo disto a barra deixa de
  /// comunicar proporção e vira um risco colorido — melhor empilhar.
  static const double _middleMinimum = FinSpace.xxxl;

  @override
  Widget build(BuildContext context) {
    final widths = _columnWidths(context);

    // A disposição é decidida UMA VEZ, no grupo, e não por linha: linhas
    // vizinhas em disposições diferentes destruiriam a coluna que as larguras
    // medidas existem para manter.
    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth =
            widths.ticker + FinSpace.sm + widths.value + _middleMinimum;
        final stacked = requiredWidth > constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PortfolioBadge(name: label, color: color),
            for (final asset in assets)
              _AssetRow(
                asset: asset,
                tickerWidth: widths.ticker,
                valueWidth: widths.value,
                stacked: stacked,
              ),
          ],
        );
      },
    );
  }
}

/// Uma linha de ativo: peso-alvo contra peso-corrente e o retorno do período.
///
/// **Duas disposições, e a segunda existe por defeito medido.** Em três
/// colunas, as duas laterais têm largura medida e o miolo é `Expanded` — então
/// quando as laterais somadas passam da largura disponível o miolo colapsa a
/// zero e a linha estoura, sem que nada na tela diga que há conteúdo escondido.
/// Acontecia em 320 dp @ 1,3x (7 px) e em 390 dp @ 2,0x (65 px), e ficou
/// invisível até a matriz de estouro passar a montar esta tela POPULADA.
///
/// Encolher as laterais não era saída: as duas carregam número, e número
/// truncado que parece completo é pior que número nenhum. Empilhar é o que
/// preserva os dois dígitos e a barra ao mesmo tempo.
class _AssetRow extends StatelessWidget {
  final AssetPerformance asset;

  /// Larguras medidas pelo grupo, iguais para todas as linhas dele.
  ///
  /// Vem de fora justamente para que sejam iguais: medir por linha alinharia
  /// cada uma consigo mesma e desalinharia a coluna.
  final double tickerWidth;
  final double valueWidth;

  /// Disposição escolhida pelo grupo. Ver a justificativa na classe.
  final bool stacked;

  const _AssetRow({
    required this.asset,
    required this.tickerWidth,
    required this.valueWidth,
    required this.stacked,
  });

  // As peças saem de métodos porque as DUAS disposições usam as mesmas. Se
  // cada uma montasse as suas, a primeira divergência entre elas passaria sem
  // ninguém notar — e a coluna medida deixaria de bater com o texto pintado.

  Widget _ticker(BuildContext context) => Text(
    asset.ticker.value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.finType.bodySm.copyWith(
      fontWeight: FontWeight.w600,
      color: context.fin.textPrimary,
    ),
  );

  Widget _weights(BuildContext context) => Text(
    // O alvo passa pelo formatador em vez de sair do `toString()` do
    // domínio: aquele usa `toStringAsFixed`, que ignora locale e escrevia
    // `100.00%` com PONTO ao lado de um `100,0%` com vírgula, na mesma frase.
    // Mesmo número de casas nos dois, também: dois pesos que se comparam
    // escritos em precisões diferentes convidam a ler deriva onde não há.
    'alvo ${Fmt.percent(asset.targetWeight.value, decimals: 1)} → '
    'atual ${Fmt.percent(asset.currentWeight, decimals: 1)}',
    style: context.finType.caption.copyWith(color: context.fin.textSecondary),
  );

  Widget _bar(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: asset.currentWeight.clamp(0.0, 1.0),
      minHeight: 4,
      backgroundColor: context.fin.divider,
      valueColor: AlwaysStoppedAnimation(
        asset.drift >= 0 ? context.fin.brand : context.fin.caution,
      ),
    ),
  );

  /// Quantas cotas a posição tem e quanto capital ela recebeu dos aportes.
  ///
  /// Peso responde "que fatia da carteira", e é o que a linha já dizia; esta
  /// responde "quanto disso existe" — quantidade e dinheiro, as duas grandezas
  /// que o investidor confere contra o extrato da corretora. Sem elas, um peso
  /// de 27% não diz se são trinta cotas ou três mil.
  ///
  /// **A quantidade é inteira**, como no extrato: cada aporte compra o que
  /// couber em lotes de uma ao preço do dia. O dinheiro ao lado é o que foi
  /// DESTINADO ao ativo, e não o que virou posição — a diferença está no caixa
  /// dele, esperando o aporte seguinte.
  Widget _position(BuildContext context) => Text(
    '${asset.shares} cotas · '
    '${Fmt.money(asset.invested.reais)} destinados',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.finType.caption.copyWith(color: context.fin.textTertiary),
  );

  Widget _returnRate(BuildContext context) => FinAmount(
    text: Fmt.percent(asset.totalReturn, decimals: 1, signed: true),
    style: context.finType.numSm,
    trend: FinAmount.trendOf(asset.totalReturn),
  );

  Widget _drift(BuildContext context) => Text(
    Fmt.points(asset.drift),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    // `numSm` e o mesmo papel usado para medir a coluna em `_columnWidths`;
    // divergir aqui faria a medida mentir.
    style: context.finType.numSm.copyWith(color: context.fin.textTertiary),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: FinSpace.sm),
    child: stacked ? _asStack(context) : _asColumns(context),
  );

  /// Três colunas: ticker, pesos com a barra, e os dois números à direita.
  Widget _asColumns(BuildContext context) => Row(
    children: [
      SizedBox(width: tickerWidth, child: _ticker(context)),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _weights(context),
            const Gap.xs(),
            _bar(context),
            const Gap.xs(),
            _position(context),
          ],
        ),
      ),
      const Gap.sm(axis: Axis.horizontal),
      SizedBox(
        width: valueWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [_returnRate(context), _drift(context)],
        ),
      ),
    ],
  );

  /// O mesmo conteúdo em três faixas, quando a largura não sustenta colunas.
  ///
  /// Cada faixa põe o texto num `Expanded` e o número na largura natural dele:
  /// assim é sempre o TEXTO que cede, e o número — que é o dado — sai inteiro
  /// em qualquer largura.
  Widget _asStack(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: _ticker(context)),
          const Gap.sm(axis: Axis.horizontal),
          _returnRate(context),
        ],
      ),
      const Gap.xs(),
      Row(
        children: [
          Expanded(child: _weights(context)),
          const Gap.sm(axis: Axis.horizontal),
          _drift(context),
        ],
      ),
      const Gap.xs(),
      _bar(context),
      const Gap.xs(),
      _position(context),
    ],
  );
}

class _RiskReturnCard extends StatelessWidget {
  final PortfolioComparison result;

  const _RiskReturnCard({required this.result});

  bool _has(RiskReturnKind kind) =>
      result.riskReturn.any((point) => point.kind == kind);

  @override
  Widget build(BuildContext context) {
    final points = <RiskReturnDot>[
      for (final p in result.riskReturn)
        (
          label: p.label,
          risk: p.risk,
          ret: p.ret,
          color: switch (p.kind) {
            RiskReturnKind.principal => context.fin.brand,
            RiskReturnKind.reserve => context.fin.reserve,
            RiskReturnKind.principalAsset => context.fin.textSecondary,
            RiskReturnKind.reserveAsset => context.fin.reserveMuted,
          },
          highlight: p.isPortfolio,
        ),
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Risco × retorno',
            subtitle:
                'Cada ativo das duas carteiras e as próprias '
                'carteiras, anualizados em ${result.window}',
          ),
          const Gap.md(),
          RiskReturnScatter(
            points: points,
            assetLegend: [
              if (_has(RiskReturnKind.principalAsset))
                (
                  label: 'Ativos da Principal',
                  color: context.fin.textSecondary,
                ),
              if (_has(RiskReturnKind.reserveAsset))
                (label: 'Ativos da Reserva', color: context.fin.reserveMuted),
            ],
          ),
        ],
      ),
    );
  }
}
