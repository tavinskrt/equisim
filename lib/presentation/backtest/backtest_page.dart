import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/balance_summary_card.dart';
import '../components/fin_amount.dart';
import '../export/csv_export.dart';
import '../shared/charts.dart';
import '../shared/theme_bridge.dart';
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

  final janela = settings.windowYears;
  final prazo = (goal.months / 12).ceil();
  if (janela >= prazo) return null;

  // "A janela", e nao "a janela simulada": a simulada pode ser MENOR que a
  // pedida quando algum ativo não tem histórico desde o início, e aí dizer que
  // ela cobre cinco anos exageraria a cobertura. O encurtamento tem faixa
  // própria; esta aqui fala do parâmetro, que é o que o leitor acabou de ver.
  final aviso =
      'A janela cobre $janela dos $prazo anos da meta. Compare a '
      'RENTABILIDADE, não o patrimônio: o valor final abaixo acumula só parte '
      'do plano de aportes, não o prazo inteiro.';

  if (prazo <= BacktestSettings.maxWindowYears) return aviso;

  return '$aviso A fonte de cotações entrega no máximo '
      '${BacktestSettings.maxWindowYears} anos, então nenhuma posição do '
      'controle alcança o prazo da meta.';
}

/// Tela de análise histórica: Principal contra Reserva sob o mesmo plano.
class BacktestPage extends ConsumerWidget {
  const BacktestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = ref.watch(isLightModeProvider);
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
                  isLight: isLight,
                ),
              ),
              const SliverToBoxAdapter(child: Gap.md()),
              // O descasamento de horizonte é ressalva do PARÂMETRO, não do
              // resultado: aparece mesmo enquanto a simulação roda, porque é
              // ele que decide como o número que vem abaixo deve ser lido.
              if (_horizonNotice(settings, study.goal) case final aviso?) ...[
                SliverToBoxAdapter(
                  child: NoticeBanner(
                    icon: Icons.straighten,
                    message: aviso,
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
                    isLight: isLight,
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

  final bool isLight;

  const _SettingsCard({
    required this.settings,
    required this.goal,
    required this.isLight,
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
          // O tile pinta fundo e respingo de tinta no `Material` mais
          // próximo, e o `GlassCard` interpõe um fundo próprio entre os dois:
          // sem este `Material` transparente o respingo fica invisível e o
          // framework acusa em tempo de execução.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: settings.applyTaxes,
              activeThumbColor: context.fin.brand,
              title: Text(
                'Aplicar IR sobre JCP',
                style: context.finType.bodySm.copyWith(
                  color: context.fin.textPrimary,
                ),
              ),
              subtitle: Text(
                'Desligue para ver quanto a tributação custou no período',
                style: context.finType.caption.copyWith(
                  color: context.fin.textTertiary,
                ),
              ),
              onChanged: notifier.setApplyTaxes,
            ),
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
    final reduzido = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (!reduzido) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    Widget barra(double largura, double altura) => Container(
      width: largura,
      height: altura,
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
                barra(160, 12),
                const Gap.md(),
                // Mesma altura declarada do `Base100Chart`, que e o que ocupa
                // este lugar quando o resultado chega.
                barra(double.infinity, 240),
                const Gap.lg(),
                barra(120, 12),
                const Gap.sm(),
                barra(double.infinity, 64),
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
  final bool isLight;

  const _ComparisonBody({
    required this.result,
    required this.studyName,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principal = result.principal;
    final reserva = result.reserva;
    final correlation = ref.watch(correlationProvider);

    if (principal == null && reserva == null) {
      return SliverToBoxAdapter(
        child: GlassCard(
          child: EmptyState(
            icon: Icons.cloud_off,
            title: 'Sem dados de mercado',
            // Dizer o motivo poupa a caçada: quase sempre é um ativo sem
            // cotação no período, e o nome dele está na mensagem da falha.
            message:
                result.principalFailure ??
                result.reservaFailure ??
                'Não foi possível carregar as cotações do período.',
          ),
        ),
      );
    }

    final reference = principal ?? reserva!;
    // As duas carteiras compartilham a janela, então qualquer uma serve de
    // eixo; cada curva ainda leva as próprias datas, para que nenhuma seja
    // desenhada fora de lugar caso um pregão falte a uma delas.
    final axis = <DateTime>{...?principal?.dates, ...?reserva?.dates}.toList()
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
                isLight: isLight,
                dates: axis,
                series: [
                  if (principal != null)
                    ChartSeries(
                      label: 'Principal',
                      values: principal.base100,
                      dates: principal.dates,
                      color: context.fin.brand,
                    ),
                  if (reserva != null)
                    ChartSeries(
                      label: 'Reserva',
                      values: reserva.base100,
                      dates: reserva.dates,
                      color: context.fin.reserva,
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
        if (reserva == null && result.reservaFailure != null) ...[
          const Gap.md(),
          NoticeBanner(
            trend: FinTrend.negative,
            icon: Icons.error_outline,
            message: 'Reserva não simulada — ${result.reservaFailure}',
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
          _GoalConfrontationCard(principal: principal, reserva: reserva),
          const Gap.md(),
          _MetricsCard(
            title: 'Carteira Principal',
            outcome: principal,
            isLight: isLight,
          ),
          const Gap.md(),
          _DividendsCard(
            portfolioLabel: 'Principal',
            outcome: principal,
            isLight: isLight,
          ),
        ],
        if (reserva != null) ...[
          const Gap.md(),
          _MetricsCard(
            title: 'Carteira Reserva',
            outcome: reserva,
            isLight: isLight,
          ),
          const Gap.md(),
          _DividendsCard(
            portfolioLabel: 'Reserva',
            outcome: reserva,
            isLight: isLight,
          ),
        ],
        const Gap.md(),
        _PerAssetCard(principal: principal, reserva: reserva, isLight: isLight),
        if (result.riskReturn.isNotEmpty) ...[
          const Gap.md(),
          _RiskReturnCard(result: result, isLight: isLight),
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
                          isLight: isLight,
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
  final BacktestOutcome? reserva;

  const _GoalConfrontationCard({required this.principal, required this.reserva});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verdict = ref.watch(goalFeasibilityProvider);

    return verdict.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (v) {
        // Taxa não finita é meta que o solver não resolveu. A aba Meta já
        // explica o porquê; repetir aqui um travessão sem contexto só ocuparia
        // espaço.
        if (v == null || !v.requiredAnnualRate.isFinite) {
          return const SizedBox.shrink();
        }

        final exigido = v.requiredAnnualRate;
        final realizado = principal.metrics.moneyWeightedReturn;
        final folga = realizado == null ? null : (realizado - exigido) * 100;

        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'A carteira frente à meta',
                subtitle: 'No período simulado · ${principal.effectivePeriod}',
              ),
              const Gap.md(),
              MetricTileRow(
                tiles: [
                  MetricTile(
                    label: Lexico.exigido,
                    value: Fmt.percent(exigido),
                    hint: Lexico.exigidoAoAno,
                  ),
                  MetricTile(
                    label: Lexico.realizado,
                    value: realizado == null
                        ? '—'
                        : Fmt.percent(realizado, signed: true),
                    hint: Lexico.realizadoXirr,
                    trend: FinAmount.trendOf(realizado),
                  ),
                  MetricTile(
                    label: Lexico.folga,
                    value: folga == null ? '—' : Fmt.points(folga),
                    trend: FinAmount.trendOf(folga),
                  ),
                ],
              ),
              const Gap.sm(),
              Text(
                'O exigido vem do plano da aba Meta. O realizado é o XIRR da '
                'janela simulada — o que esta composição entregou no passado, '
                'não o que ela promete para o prazo da meta.',
                style: context.finType.caption.copyWith(
                  color: context.fin.textTertiary,
                ),
              ),
              if (reserva != null) ...[
                const Gap.sm(),
                Builder(
                  builder: (context) {
                    final alternativa = reserva!.metrics.moneyWeightedReturn;
                    if (alternativa == null) return const SizedBox.shrink();
                    final folgaAlternativa = (alternativa - exigido) * 100;
                    // Sem ponto final: `Fmt.points` termina em "p.p.", e a
                    // abreviação já carrega o ponto que fecha a frase.
                    return Text(
                      'A Reserva, sob os mesmos aportes, teria rendido '
                      '${Fmt.percent(alternativa, signed: true)} ao ano — '
                      'folga de ${Fmt.points(folgaAlternativa)}',
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
    'Quanto a carteira valeria ao fim do período, com os proventos já '
        'reinvestidos. Abaixo do valor vem o total aportado — a diferença '
        'entre os dois é o ganho.',
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
  HintEntry(
    'DY líquido',
    'Proventos já descontados de IR sobre o patrimônio médio, ao ano. É o '
        'fluxo de caixa gerado pela carteira, separado da valorização.',
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
    'Retorno total',
    'Quanto o capital alocado naquele ativo rendeu no período — preço mais '
        'proventos reinvestidos. Como as duas carteiras rodam na mesma janela '
        'e sob o mesmo cronograma de aportes, os retornos são comparáveis '
        'entre Principal e Reserva.',
  ),
];

/// Indicadores de uma carteira na janela simulada.
///
/// O patrimônio final passou a ser a grandeza principal do cartão, em `numLg`,
/// com o aportado logo abaixo; as nove métricas restantes ficam em `numMd`.
/// Antes as dez dividiam o mesmo tamanho, o que obrigava o leitor a procurar
/// qual delas era o número que importa.
class _MetricsCard extends StatelessWidget {
  final String title;
  final BacktestOutcome outcome;
  final bool isLight;

  const _MetricsCard({
    required this.title,
    required this.outcome,
    required this.isLight,
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
        caption: 'aportado ${Fmt.money(outcome.totalContributed.reais)}',
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
          BalanceMetric(
            label: 'DY líquido',
            value: Fmt.percent(m.netDividendYield),
            hint: 'após IR',
          ),
        ],
      ),
    );
  }
}

/// Proventos separados em bruto, imposto retido e líquido.
class _DividendsCard extends StatelessWidget {
  /// Nome curto da carteira a que estes proventos pertencem.
  ///
  /// Com as duas carteiras na tela, um cartão sem dono é ambíguo — e proventos
  /// são exatamente o tipo de número que o leitor atribui à carteira errada.
  final String portfolioLabel;

  final BacktestOutcome outcome;
  final bool isLight;

  const _DividendsCard({
    required this.portfolioLabel,
    required this.outcome,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final gross = outcome.grossDividends.reais;
    final tax = outcome.withheldTax.reais;
    final net = gross - tax;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Proventos no período — $portfolioLabel',
            subtitle: 'JCP sofre 15% de IRRF; dividendo é isento',
          ),
          const Gap.md(),
          MetricTileRow(
            tiles: [
              MetricTile(label: 'Bruto', value: Fmt.money(gross)),
              MetricTile(
                label: 'IR retido',
                value: Fmt.money(tax),
                trend: tax > 0 ? FinTrend.negative : FinTrend.neutral,
                hint: gross > 0
                    ? '${Fmt.percent(tax / gross, decimals: 1)} do bruto'
                    : null,
              ),
              MetricTile(
                label: 'Líquido reinvestido',
                value: Fmt.money(net),
                trend: FinTrend.positive,
              ),
            ],
          ),
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
  final BacktestOutcome? reserva;
  final bool isLight;

  const _PerAssetCard({
    required this.principal,
    required this.reserva,
    required this.isLight,
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
    final reservaAssets = _ranked(reserva);
    if (principalAssets.isEmpty && reservaAssets.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasBoth = principalAssets.isNotEmpty && reservaAssets.isNotEmpty;

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
              isLight: isLight,
              label: 'Principal',
              color: context.fin.brand,
              assets: principalAssets,
            ),
          if (hasBoth)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FinSpace.sm),
              child: Divider(height: 1, color: context.fin.divider),
            ),
          if (reservaAssets.isNotEmpty)
            _AssetGroup(
              isLight: isLight,
              label: 'Reserva',
              // Este `color` pinta TEXTO -- o rotulo do grupo. Por isso vem do
              // token medido em contraste, e nao da variante de marca.
              color: context.fin.reserva,
              assets: reservaAssets,
            ),
        ],
      ),
    );
  }
}

/// Os ativos de uma carteira sob o selo colorido dela.
class _AssetGroup extends StatelessWidget {
  final String label;
  final Color color;
  final List<AssetPerformance> assets;
  final bool isLight;

  const _AssetGroup({
    required this.label,
    required this.color,
    required this.assets,
    required this.isLight,
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

  @override
  Widget build(BuildContext context) {
    final widths = _columnWidths(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const Gap.xs(axis: Axis.horizontal),
            Text(
              label.toUpperCase(),
              style: context.finType.caption.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        for (final asset in assets)
          _AssetRow(
            asset: asset,
            isLight: isLight,
            tickerWidth: widths.ticker,
            valueWidth: widths.value,
          ),
      ],
    );
  }
}

/// Uma linha de ativo: peso-alvo contra peso-corrente e o retorno do período.
class _AssetRow extends StatelessWidget {
  final AssetPerformance asset;
  final bool isLight;

  /// Larguras medidas pelo grupo, iguais para todas as linhas dele.
  ///
  /// Vem de fora justamente para que sejam iguais: medir por linha alinharia
  /// cada uma consigo mesma e desalinharia a coluna.
  final double tickerWidth;
  final double valueWidth;

  const _AssetRow({
    required this.asset,
    required this.isLight,
    required this.tickerWidth,
    required this.valueWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FinSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: tickerWidth,
            child: Text(
              asset.ticker.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.finType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: context.fin.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'alvo ${asset.targetWeight} → '
                  'atual ${Fmt.percent(asset.currentWeight, decimals: 1)}',
                  style: context.finType.caption.copyWith(
                    color: context.fin.textSecondary,
                  ),
                ),
                const Gap.xs(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: asset.currentWeight.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: context.fin.divider,
                    valueColor: AlwaysStoppedAnimation(
                      asset.drift >= 0
                          ? context.fin.brand
                          : context.fin.caution,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap.sm(axis: Axis.horizontal),
          SizedBox(
            width: valueWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FinAmount(
                  text: Fmt.percent(
                    asset.totalReturn,
                    decimals: 1,
                    signed: true,
                  ),
                  style: context.finType.numSm,
                  trend: FinAmount.trendOf(asset.totalReturn),
                ),
                Text(
                  Fmt.points(asset.drift),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // `numSm` e o mesmo papel usado para medir a coluna em
                  // `_columnWidths`; divergir aqui faria a medida mentir.
                  style: context.finType.numSm.copyWith(
                    color: context.fin.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskReturnCard extends StatelessWidget {
  final PortfolioComparison result;
  final bool isLight;

  const _RiskReturnCard({required this.result, required this.isLight});

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
            RiskReturnKind.reserva => context.fin.reserva,
            RiskReturnKind.principalAsset => context.fin.textSecondary,
            RiskReturnKind.reservaAsset => context.fin.reservaMuted,
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
            isLight: isLight,
            points: points,
            assetLegend: [
              if (_has(RiskReturnKind.principalAsset))
                (
                  label: 'Ativos da Principal',
                  color: context.fin.textSecondary,
                ),
              if (_has(RiskReturnKind.reservaAsset))
                (label: 'Ativos da Reserva', color: context.fin.reservaMuted),
            ],
          ),
        ],
      ),
    );
  }
}
