import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_colors.dart';
import '../components/balance_summary_card.dart';
import '../components/fin_amount.dart';
import '../export/csv_export.dart';
import '../shared/charts.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'backtest_providers.dart';


/// Tela de análise histórica: Principal contra Reserva sob o mesmo plano.
class BacktestPage extends ConsumerWidget {
  const BacktestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = ref.watch(isLightModeProvider);
    final comparison = ref.watch(comparisonProvider);
    final settings = ref.watch(backtestSettingsProvider);
    final study = ref.watch(studyProvider).study;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsCard(settings: settings, isLight: isLight),
        const SizedBox(height: 12),
        comparison.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => GlassCard(
            child: EmptyState(
              icon: Icons.error_outline,
              title: 'Falha na simulação',
              message: '$error',
            ),
          ),
          data: (result) {
            if (result == null) {
              return GlassCard(
                child: EmptyState(
                  icon: Icons.timeline,
                  title: 'Nada a simular ainda',
                  message:
                      'Monte a carteira Principal e defina o plano de '
                      'aportes na aba Meta.',
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
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  final BacktestSettings settings;
  final bool isLight;

  const _SettingsCard({required this.settings, required this.isLight});

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
          const SizedBox(height: 10),
          LabelValueRow(
            label: 'Janela',
            value: '${settings.windowYears} anos',
          ),
          Text(
            'Quanto tempo de história a simulação percorre, contado de hoje '
            'para trás. Com ${settings.windowYears} anos, o plano de aportes '
            'começa em ${Fmt.date.format(_windowStart(settings.windowYears))} '
            'e vai até hoje. Janelas maiores incluem mais ciclos de mercado; '
            'em compensação, exigem que todos os ativos das duas carteiras já '
            'negociassem naquela data — quando algum não negociava, a janela '
            'é encurtada até o primeiro pregão dele.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: AppColors.textMuted(isLight),
            ),
          ),
          Slider(
            value: settings.windowYears.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: AppColors.primary,
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
              activeThumbColor: AppColors.primary,
              title: Text(
                'Aplicar IR sobre JCP',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textPrimary(isLight),
                ),
              ),
              subtitle: Text(
                'Desligue para ver quanto a tributação custou no período',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textMuted(isLight),
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
      return GlassCard(
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
      );
    }

    final reference = principal ?? reserva!;
    // As duas carteiras compartilham a janela, então qualquer uma serve de
    // eixo; cada curva ainda leva as próprias datas, para que nenhuma seja
    // desenhada fora de lugar caso um pregão falte a uma delas.
    final axis = <DateTime>{...?principal?.dates, ...?reserva?.dates}.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    color: AppColors.primary,
                  ),
                  onPressed: () => exportComparisonCsv(
                    context: context,
                    studyName: studyName,
                    result: result,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Base100Chart(
                isLight: isLight,
                dates: axis,
                series: [
                  if (principal != null)
                    ChartSeries(
                      label: 'Principal',
                      values: principal.base100,
                      dates: principal.dates,
                      color: AppColors.primary,
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
                const SizedBox(height: 12),
                NoticeBanner(
                  icon: Icons.compare_arrows,
                  trend: result.twrGap! >= 0
                      ? FinTrend.positive
                      : FinTrend.negative,
                  message: result.twrGap! >= 0
                      ? 'A Principal rendeu ${result.twrGap!.toStringAsFixed(1)} '
                            'pontos percentuais a mais que a Reserva no período.'
                      : 'A Reserva teria rendido '
                            '${result.twrGap!.abs().toStringAsFixed(1)} pontos '
                            'percentuais a mais que a Principal no período.',
                ),
              ],
            ],
          ),
        ),
        if (result.windowWasShortened) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            icon: Icons.event_busy_outlined,
            message: _shortenedWindowMessage(result),
          ),
        ],
        if (principal == null && result.principalFailure != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            trend: FinTrend.negative,
            icon: Icons.error_outline,
            message: 'Principal não simulada — ${result.principalFailure}',
          ),
        ],
        if (reserva == null && result.reservaFailure != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            trend: FinTrend.negative,
            icon: Icons.error_outline,
            message: 'Reserva não simulada — ${result.reservaFailure}',
          ),
        ],
        if (reference.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final warning in reference.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NoticeBanner(message: warning),
            ),
        ],
        if (principal != null) ...[
          const SizedBox(height: 12),
          _MetricsCard(
            title: 'Carteira Principal',
            outcome: principal,
            isLight: isLight,
          ),
          const SizedBox(height: 12),
          _DividendsCard(
            portfolioLabel: 'Principal',
            outcome: principal,
            isLight: isLight,
          ),
        ],
        if (reserva != null) ...[
          const SizedBox(height: 12),
          _MetricsCard(
            title: 'Carteira Reserva',
            outcome: reserva,
            isLight: isLight,
          ),
          const SizedBox(height: 12),
          _DividendsCard(
            portfolioLabel: 'Reserva',
            outcome: reserva,
            isLight: isLight,
          ),
        ],
        const SizedBox(height: 12),
        _PerAssetCard(principal: principal, reserva: reserva, isLight: isLight),
        if (result.riskReturn.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RiskReturnCard(result: result, isLight: isLight),
        ],
        correlation.maybeWhen(
          data: (data) => data == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: 'Correlação entre os ativos',
                          subtitle:
                              'Verde indica menor co-movimento — diversificação',
                        ),
                        const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(label: 'Bruto', value: Fmt.money(gross)),
              ),
              Expanded(
                child: MetricTile(
                  label: 'IR retido',
                  value: Fmt.money(tax),
                  trend: tax > 0 ? FinTrend.negative : FinTrend.neutral,
                  hint: gross > 0
                      ? '${(tax / gross * 100).toStringAsFixed(1)}% do bruto'
                      : null,
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Líquido reinvestido',
                  value: Fmt.money(net),
                  trend: FinTrend.positive,
                ),
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
          const SizedBox(height: 10),
          if (principalAssets.isNotEmpty)
            _AssetGroup(
              isLight: isLight,
              label: 'Principal',
              color: AppColors.primary,
              assets: principalAssets,
            ),
          if (hasBoth)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.divider(isLight)),
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
    final driftStyle = context.finType.caption;

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

      final d = FinAmount.measure(
        context,
        '${asset.drift >= 0 ? '+' : ''}'
        '${asset.drift.toStringAsFixed(1)} p.p.',
        driftStyle,
      );
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
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: color,
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
      padding: const EdgeInsets.symmetric(vertical: 7),
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
                color: AppColors.textPrimary(isLight),
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
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary(isLight),
                  ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: asset.currentWeight.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppColors.divider(isLight),
                    valueColor: AlwaysStoppedAnimation(
                      asset.drift >= 0
                          ? AppColors.primary
                          : context.fin.caution,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
                  '${asset.drift >= 0 ? '+' : ''}'
                  '${asset.drift.toStringAsFixed(1)} p.p.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // `caption` e o mesmo papel usado para medir a coluna em
                  // `_columnWidths`; divergir aqui faria a medida mentir.
                  style: context.finType.caption.copyWith(
                    color: AppColors.textMuted(isLight),
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
            RiskReturnKind.principal => AppColors.primary,
            RiskReturnKind.reserva => context.fin.reserva,
            RiskReturnKind.principalAsset => AppColors.textSecondary(isLight),
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
          const SizedBox(height: 12),
          RiskReturnScatter(
            isLight: isLight,
            points: points,
            assetLegend: [
              if (_has(RiskReturnKind.principalAsset))
                (
                  label: 'Ativos da Principal',
                  color: AppColors.textSecondary(isLight),
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
