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
          Slider(
            value: settings.windowYears.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: AppColors.primary,
            onChanged: (value) => notifier.setWindowYears(value.round()),
          ),
          SwitchListTile(
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
          message: 'Não foi possível carregar as cotações do período.',
        ),
      );
    }

    final reference = principal ?? reserva!;

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
                dates: reference.dates,
                series: [
                  if (principal != null)
                    ChartSeries(
                      label: 'Principal',
                      values: principal.base100,
                      color: AppColors.primary,
                    ),
                  if (reserva != null)
                    ChartSeries(
                      label: 'Reserva',
                      values: reserva.base100,
                      color: const Color(0xFF3B82F6),
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
        if (reference.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final warning in reference.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NoticeBanner(isLight: isLight, message: warning),
            ),
        ],
        const SizedBox(height: 12),
        if (principal != null)
          _MetricsCard(
            title: 'Carteira Principal',
            outcome: principal,
            isLight: isLight,
          ),
        if (reserva != null) ...[
          const SizedBox(height: 12),
          _MetricsCard(
            title: 'Carteira Reserva',
            outcome: reserva,
            isLight: isLight,
          ),
        ],
        if (principal != null) ...[
          const SizedBox(height: 12),
          _DividendsCard(outcome: principal, isLight: isLight),
          const SizedBox(height: 12),
          _PerAssetCard(outcome: principal, isLight: isLight),
          const SizedBox(height: 12),
          _RiskReturnCard(outcome: principal, isLight: isLight),
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
          SectionHeader(isLight: isLight, title: title),
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
  final BacktestOutcome outcome;
  final bool isLight;

  const _DividendsCard({required this.outcome, required this.isLight});

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
            title: 'Proventos no período',
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

/// Desempenho individual, com peso-alvo contra peso-corrente.
class _PerAssetCard extends StatelessWidget {
  final BacktestOutcome outcome;
  final bool isLight;

  const _PerAssetCard({required this.outcome, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final assets = outcome.perAsset.values.toList()
      ..sort((a, b) => b.totalReturn.compareTo(a.totalReturn));

    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Desempenho por ativo',
            subtitle: 'A deriva de peso é sinal de decisão, não defeito',
          ),
          const SizedBox(height: 10),
          for (final asset in assets)
            Padding(
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
            ),
        ],
      ),
    );
  }
}

class _RiskReturnCard extends StatelessWidget {
  final BacktestOutcome outcome;
  final bool isLight;

  const _RiskReturnCard({required this.outcome, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final points = <({String label, double risk, double ret, bool highlight})>[
      (
        label: 'Carteira',
        risk: outcome.metrics.volatility * 100,
        ret: outcome.metrics.cagr * 100,
        highlight: true,
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
            subtitle: 'Volatilidade e retorno anualizados da carteira',
          ),
          const SizedBox(height: 12),
          RiskReturnScatter(points: points, isLight: isLight),
        ],
      ),
    );
  }
}
