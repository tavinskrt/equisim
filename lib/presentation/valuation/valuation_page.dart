import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_colors.dart';
import '../shared/charts.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import 'valuation_providers.dart';

/// Detalhe da avaliação de um ativo.
class ValuationPage extends ConsumerWidget {
  final Ticker ticker;
  const ValuationPage({super.key, required this.ticker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = ref.watch(isLightModeProvider);
    final valuation = ref.watch(valuationProvider(ticker));

    return Scaffold(
      body: ScreenBackground(
        isLight: isLight,
        child: SafeArea(
          child: Column(
            children: [
              _Header(ticker: ticker, isLight: isLight),
              Expanded(
                child: valuation.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => EmptyState(
                    isLight: isLight,
                    icon: Icons.error_outline,
                    title: 'Falha na avaliação',
                    message: '$error',
                  ),
                  data: (result) => result == null
                      ? EmptyState(
                          isLight: isLight,
                          icon: Icons.help_outline,
                          title: 'Não foi possível avaliar',
                          message:
                              'Os dados disponíveis para ${ticker.value} não '
                              'sustentam nenhum modelo de avaliação.',
                        )
                      : _ValuationBody(result: result, isLight: isLight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Ticker ticker;
  final bool isLight;
  const _Header({required this.ticker, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back,
                size: 20, color: AppColors.textPrimary(isLight)),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            ticker.value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(isLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuationBody extends ConsumerWidget {
  final ValuationResult result;
  final bool isLight;

  const _ValuationBody({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(valuationSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PriceCard(result: result, isLight: isLight),
        const SizedBox(height: 12),
        _ModelCard(result: result, isLight: isLight),
        const SizedBox(height: 12),
        _ScenarioCard(
          result: result,
          settings: settings,
          isLight: isLight,
        ),
        const SizedBox(height: 12),
        _SensitivityCard(result: result, isLight: isLight),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            isLight: isLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  isLight: isLight,
                  title: 'Ressalvas',
                  subtitle: 'A qualidade da estimativa faz parte do resultado',
                ),
                const SizedBox(height: 10),
                for (final warning in result.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NoticeBanner(
                      isLight: isLight,
                      message: warning,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  final ValuationResult result;
  final bool isLight;
  const _PriceCard({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Preço de mercado',
                  value: Fmt.money(result.marketPrice.reais),
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Preço justo',
                  value: Fmt.money(result.fairValue.reais),
                  hint: 'cenário base',
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Upside',
                  value: Fmt.percent(result.upside, decimals: 1, signed: true),
                  hint: 'total, sem prazo',
                  valueColor: signedColor(result.upside, isLight),
                ),
              ),
            ],
          ),
          if (result.marginOfSafety > 0) ...[
            const Divider(height: 20),
            Text(
              'Com margem de segurança de '
              '${Fmt.percent(result.marginOfSafety, decimals: 0)}, o preço de '
              'compra seria ${Fmt.money(result.safetyPrice.reais)} — '
              '${result.isUndervalued ? 'já atingido' : 'ainda não atingido'}.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary(isLight),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ValuationResult result;
  final bool isLight;
  const _ModelCard({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Modelo aplicado',
            subtitle: 'Escolhido pelo que os dados sustentam',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Método',
                  value: result.model.label,
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Taxa de desconto',
                  value: Fmt.percent(result.discountRate),
                  hint: result.model == ValuationModel.dcfFcff
                      ? 'WACC'
                      : 'custo do capital próprio',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cenários: três faixas nomeadas ou distribuição sorteada.
///
/// O alternador existe porque os dois modos compartilham o mesmo caminho de
/// código — trocar é configuração, não refatoração.
class _ScenarioCard extends ConsumerWidget {
  final ValuationResult result;
  final ValuationSettings settings;
  final bool isLight;

  const _ScenarioCard({
    required this.result,
    required this.settings,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Cenários',
            subtitle: settings.monteCarlo
                ? '${settings.samples} sorteios de premissas'
                : 'Três conjuntos fixos de premissas',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Monte Carlo',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(isLight),
                  ),
                ),
                Switch(
                  value: settings.monteCarlo,
                  activeThumbColor: AppColors.primary,
                  onChanged: ref
                      .read(valuationSettingsProvider.notifier)
                      .setMonteCarlo,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (result.distribution != null)
            _DistributionView(
              distribution: result.distribution!,
              marketPrice: result.marketPrice.reais,
              isLight: isLight,
            )
          else if (result.discreteScenarios != null)
            _DiscreteView(
              scenarios: result.discreteScenarios!,
              isLight: isLight,
            )
          else
            Text(
              'Apenas o cenário base pôde ser calculado.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary(isLight),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscreteView extends StatelessWidget {
  final Map<ScenarioBand, Money> scenarios;
  final bool isLight;

  const _DiscreteView({required this.scenarios, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final band in ScenarioBand.values)
          if (scenarios[band] != null)
            Expanded(
              child: MetricTile(
                isLight: isLight,
                label: band.label,
                value: Fmt.money(scenarios[band]!.reais),
                valueColor: switch (band) {
                  ScenarioBand.bear => AppColors.danger,
                  ScenarioBand.base => AppColors.textPrimary(isLight),
                  ScenarioBand.bull => AppColors.primary,
                },
              ),
            ),
      ],
    );
  }
}

class _DistributionView extends StatelessWidget {
  final ValueDistribution distribution;
  final double marketPrice;
  final bool isLight;

  const _DistributionView({
    required this.distribution,
    required this.marketPrice,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final probability = distribution.probabilityAbove(marketPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: MetricTile(
                isLight: isLight,
                label: 'P5',
                value: Fmt.money(distribution.p5),
                hint: 'pessimista',
                valueColor: AppColors.danger,
              ),
            ),
            Expanded(
              child: MetricTile(
                isLight: isLight,
                label: 'Mediana',
                value: Fmt.money(distribution.median),
              ),
            ),
            Expanded(
              child: MetricTile(
                isLight: isLight,
                label: 'P95',
                value: Fmt.money(distribution.p95),
                hint: 'otimista',
                valueColor: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        NoticeBanner(
          isLight: isLight,
          icon: Icons.casino_outlined,
          color: probability > 0.5 ? AppColors.primary : AppColors.danger,
          message: 'Em ${Fmt.percent(probability, decimals: 0)} dos cenários '
              'o preço justo supera o preço de mercado atual '
              '(${Fmt.money(marketPrice)}).',
        ),
      ],
    );
  }
}

/// Sensibilidade: qual premissa mais move o preço justo.
class _SensitivityCard extends StatelessWidget {
  final ValuationResult result;
  final bool isLight;

  const _SensitivityCard({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final scenarios = result.discreteScenarios;
    final distribution = result.distribution;

    final bars = <({String label, double low, double high})>[];
    if (scenarios != null &&
        scenarios[ScenarioBand.bear] != null &&
        scenarios[ScenarioBand.bull] != null) {
      bars.add((
        label: 'Crescimento\ne desconto',
        low: scenarios[ScenarioBand.bear]!.reais,
        high: scenarios[ScenarioBand.bull]!.reais,
      ));
    }
    if (distribution != null) {
      bars.add((
        label: 'Faixa\nsorteada',
        low: distribution.p5,
        high: distribution.p95,
      ));
    }

    if (bars.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Sensibilidade',
            subtitle: 'Quanto o preço justo se move com as premissas',
          ),
          const SizedBox(height: 12),
          TornadoChart(
            bars: bars,
            baseValue: result.fairValue.reais,
            isLight: isLight,
          ),
          const SizedBox(height: 8),
          Text(
            'A linha central é o cenário base '
            '(${Fmt.money(result.fairValue.reais)}).',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textMuted(isLight),
            ),
          ),
        ],
      ),
    );
  }
}
