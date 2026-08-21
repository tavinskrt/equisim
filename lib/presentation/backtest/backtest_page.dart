import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_colors.dart';
import '../export/csv_export.dart';
import '../shared/charts.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import 'backtest_providers.dart';

/// Azul da Reserva, o contraponto ao verde da Principal em toda a tela.
const Color _reservaColor = Color(0xFF3B82F6);

/// Tom mais claro para os **ativos** da Reserva na dispersão: mantém a família
/// de cor da carteira sem competir com o ponto da própria carteira.
const Color _reservaAssetColor = Color(0xFF60A5FA);

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
            isLight: isLight,
            child: EmptyState(
              isLight: isLight,
              icon: Icons.error_outline,
              title: 'Falha na simulação',
              message: '$error',
            ),
          ),
          data: (result) {
            if (result == null) {
              return GlassCard(
                isLight: isLight,
                child: EmptyState(
                  isLight: isLight,
                  icon: Icons.timeline,
                  title: 'Nada a simular ainda',
                  message: 'Monte a carteira Principal e defina o plano de '
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
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Parâmetros da simulação',
            subtitle: 'Sem rebalanceamento: os pesos derivam com o mercado',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Janela',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(isLight),
                ),
              ),
              const Spacer(),
              Text(
                '${settings.windowYears} anos',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(isLight),
                ),
              ),
            ],
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
        isLight: isLight,
        child: EmptyState(
          isLight: isLight,
          icon: Icons.cloud_off,
          title: 'Sem dados de mercado',
          // Dizer o motivo poupa a caçada: quase sempre é um ativo sem
          // cotação no período, e o nome dele está na mensagem da falha.
          message: result.principalFailure ??
              result.reservaFailure ??
              'Não foi possível carregar as cotações do período.',
        ),
      );
    }

    final reference = principal ?? reserva!;
    // As duas carteiras compartilham a janela, então qualquer uma serve de
    // eixo; cada curva ainda leva as próprias datas, para que nenhuma seja
    // desenhada fora de lugar caso um pregão falte a uma delas.
    final axis = <DateTime>{
      ...?principal?.dates,
      ...?reserva?.dates,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          isLight: isLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                isLight: isLight,
                title: 'Evolução comparada',
                subtitle: 'Base 100 · ${reference.effectivePeriod}',
                trailing: IconButton(
                  tooltip: 'Exportar CSV',
                  icon: Icon(Icons.download_outlined,
                      size: 19, color: AppColors.primary),
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
                      color: _reservaColor,
                    ),
                ],
              ),
              if (result.twrGap != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(
                  isLight: isLight,
                  icon: Icons.compare_arrows,
                  color: result.twrGap! >= 0
                      ? AppColors.primary
                      : AppColors.danger,
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
            isLight: isLight,
            icon: Icons.event_busy_outlined,
            message: _shortenedWindowMessage(result),
          ),
        ],
        if (principal == null && result.principalFailure != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            isLight: isLight,
            color: AppColors.danger,
            icon: Icons.error_outline,
            message: 'Principal não simulada — ${result.principalFailure}',
          ),
        ],
        if (reserva == null && result.reservaFailure != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            isLight: isLight,
            color: AppColors.danger,
            icon: Icons.error_outline,
            message: 'Reserva não simulada — ${result.reservaFailure}',
          ),
        ],
        if (reference.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final warning in reference.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NoticeBanner(isLight: isLight, message: warning),
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
        _PerAssetCard(
          principal: principal,
          reserva: reserva,
          isLight: isLight,
        ),
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
                    isLight: isLight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          isLight: isLight,
                          title: 'Correlação entre os ativos',
                          subtitle:
                              'Verde indica menor co-movimento — diversificação',
                        ),
                        const SizedBox(height: 12),
                        CorrelationHeatmap(
                          tickers: data.tickers,
                          matrix: data.matrix,
                          isLight: isLight,
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
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: title,
            trailing: HintIcon(
              isLight: isLight,
              title: 'Indicadores da $title',
              intro: 'Todos se referem à janela simulada. As duas carteiras '
                  'recebem aportes idênticos nas mesmas datas — só a '
                  'composição difere.',
              entries: _metricsGlossary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              MetricTile(
                isLight: isLight,
                label: 'Patrimônio final',
                value: Fmt.money(outcome.finalValue.reais),
                hint: 'aportado ${Fmt.money(outcome.totalContributed.reais)}',
              ),
              MetricTile(
                isLight: isLight,
                label: 'TWR',
                value: Fmt.percent(m.timeWeightedReturn, signed: true),
                hint: 'neutraliza aportes',
                valueColor: signedColor(m.timeWeightedReturn, isLight),
              ),
              MetricTile(
                isLight: isLight,
                label: 'XIRR',
                value: m.moneyWeightedReturn == null
                    ? '—'
                    : Fmt.percent(m.moneyWeightedReturn!, signed: true),
                hint: 'retorno do investidor',
                valueColor: m.moneyWeightedReturn == null
                    ? null
                    : signedColor(m.moneyWeightedReturn!, isLight),
              ),
              MetricTile(
                isLight: isLight,
                label: 'CAGR',
                value: Fmt.percent(m.cagr, signed: true),
                valueColor: signedColor(m.cagr, isLight),
              ),
              MetricTile(
                isLight: isLight,
                label: 'Volatilidade',
                value: Fmt.percent(m.volatility),
                hint: 'anualizada',
              ),
              MetricTile(
                isLight: isLight,
                label: 'Máx. drawdown',
                value: Fmt.percent(m.maxDrawdown),
                valueColor: AppColors.danger,
              ),
              MetricTile(
                isLight: isLight,
                label: 'Sharpe',
                value: Fmt.ratio(m.sharpe),
                hint: 'vs CDI observado',
              ),
              MetricTile(
                isLight: isLight,
                label: 'Sortino',
                value: Fmt.ratio(m.sortino),
              ),
              MetricTile(
                isLight: isLight,
                label: 'Calmar',
                value: Fmt.ratio(m.calmar),
              ),
              MetricTile(
                isLight: isLight,
                label: 'DY líquido',
                value: Fmt.percent(m.netDividendYield),
                hint: 'após IR',
              ),
            ],
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
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Proventos no período — $portfolioLabel',
            subtitle: 'JCP sofre 15% de IRRF; dividendo é isento',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Bruto',
                  value: Fmt.money(gross),
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'IR retido',
                  value: Fmt.money(tax),
                  valueColor: tax > 0 ? AppColors.danger : null,
                  hint: gross > 0
                      ? '${(tax / gross * 100).toStringAsFixed(1)}% do bruto'
                      : null,
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Líquido reinvestido',
                  value: Fmt.money(net),
                  valueColor: AppColors.primary,
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
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Desempenho por ativo',
            subtitle: hasBoth
                ? 'Do melhor ao pior retorno em cada carteira'
                : 'A deriva de peso é sinal de decisão, não defeito',
            trailing: HintIcon(
              isLight: isLight,
              title: 'Desempenho por ativo',
              intro: 'Cada linha é um ativo dentro da sua carteira, do melhor '
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
              label: 'Principal',
              color: AppColors.primary,
              assets: principalAssets,
              isLight: isLight,
            ),
          if (hasBoth)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.divider(isLight)),
            ),
          if (reservaAssets.isNotEmpty)
            _AssetGroup(
              label: 'Reserva',
              color: _reservaColor,
              assets: reservaAssets,
              isLight: isLight,
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

  @override
  Widget build(BuildContext context) {
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
        for (final asset in assets) _AssetRow(asset: asset, isLight: isLight),
      ],
    );
  }
}

/// Uma linha de ativo: peso-alvo contra peso-corrente e o retorno do período.
class _AssetRow extends StatelessWidget {
  final AssetPerformance asset;
  final bool isLight;

  const _AssetRow({required this.asset, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              asset.ticker.value,
              style: TextStyle(
                fontSize: 12.5,
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
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.percent(asset.totalReturn, decimals: 1, signed: true),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: signedColor(asset.totalReturn, isLight),
                  ),
                ),
                Text(
                  '${asset.drift >= 0 ? '+' : ''}'
                  '${asset.drift.toStringAsFixed(1)} p.p.',
                  style: TextStyle(
                    fontSize: 9.5,
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
            RiskReturnKind.reserva => _reservaColor,
            RiskReturnKind.principalAsset =>
              AppColors.textSecondary(isLight),
            RiskReturnKind.reservaAsset => _reservaAssetColor,
          },
          highlight: p.isPortfolio,
        ),
    ];

    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Risco × retorno',
            subtitle: 'Cada ativo das duas carteiras e as próprias '
                'carteiras, anualizados em ${result.window}',
          ),
          const SizedBox(height: 12),
          RiskReturnScatter(
            points: points,
            isLight: isLight,
            assetLegend: [
              if (_has(RiskReturnKind.principalAsset))
                (
                  label: 'Ativos da Principal',
                  color: AppColors.textSecondary(isLight)
                ),
              if (_has(RiskReturnKind.reservaAsset))
                (label: 'Ativos da Reserva', color: _reservaAssetColor),
            ],
          ),
        ],
      ),
    );
  }
}
