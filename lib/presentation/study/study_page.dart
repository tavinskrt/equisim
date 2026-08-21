import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_colors.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../valuation/valuation_page.dart';
import '../valuation/valuation_providers.dart';
import 'asset_picker.dart';
import 'study_notifier.dart';

/// Tela da dupla carteira.
///
/// O gesto central é arrastar um ativo entre Principal e Reserva. Como o
/// recálculo de pesos, concentração e retorno esperado custa microssegundos,
/// tudo responde no mesmo quadro do gesto — sem carregamento, sem espera.
class StudyPage extends ConsumerWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = ref.watch(isLightModeProvider);
    final state = ref.watch(studyProvider);
    final concentration = ref.watch(concentrationProvider);

    ref.listen(studyProvider, (previous, next) {
      final error = next.lastError;
      if (error != null && error != previous?.lastError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(studyProvider.notifier).clearError();
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 820;

        final principal = _PortfolioColumn(
          portfolio: state.study.principal,
          isPrincipal: true,
          isLight: isLight,
        );
        final reserva = _PortfolioColumn(
          portfolio: state.study.reserva,
          isPrincipal: false,
          isLight: isLight,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StudyHeader(isLight: isLight),
            const SizedBox(height: 12),
            if (concentration.hasAlert) ...[
              NoticeBanner(
                isLight: isLight,
                icon: Icons.account_balance_outlined,
                message: _concentrationMessage(concentration),
              ),
              const SizedBox(height: 12),
            ],
            if (isWide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: principal),
                    const SizedBox(width: 12),
                    Expanded(child: reserva),
                  ],
                ),
              )
            else ...[
              principal,
              const SizedBox(height: 12),
              reserva,
            ],
          ],
        );
      },
    );
  }

  static String _concentrationMessage(ConcentrationReport report) {
    final parts = report.concentrated
        .map((e) =>
            '${e.sector.label} (${e.count} ativos, ${Fmt.percent(e.weight, decimals: 0)})')
        .join(' · ');
    return 'Concentração setorial na carteira Principal: $parts. '
        'É um aviso, não um impedimento.';
  }
}

class _StudyHeader extends ConsumerWidget {
  final bool isLight;
  const _StudyHeader({required this.isLight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyProvider);
    final expected = ref.watch(portfolioValuationsProvider);
    final yields = ref.watch(netDividendYieldsProvider);
    final settings = ref.watch(valuationSettingsProvider);

    double? weightedUpside;
    if (expected.hasValue && expected.value!.isNotEmpty) {
      weightedUpside = ExpectedReturn.forPortfolio(
        portfolio: state.study.principal,
        valuations: expected.value!,
        netDividendYields: yields.valueOrNull ?? const {},
        horizonMonths: settings.convergenceHorizonMonths,
      );
    }

    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: state.study.name,
                  onChanged: ref.read(studyProvider.notifier).rename,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(isLight),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Nome do estudo',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted(isLight)),
                  ),
                ),
              ),
              state.isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Salvar estudo',
                      icon: Icon(Icons.save_outlined,
                          size: 19, color: AppColors.primary),
                      onPressed: () =>
                          ref.read(studyProvider.notifier).save(),
                    ),
            ],
          ),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Ativos na Principal',
                  value: '${state.study.principal.length}'
                      ' / ${Portfolio.maxAssets}',
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Retorno esperado',
                  value: weightedUpside == null
                      ? '—'
                      : Fmt.percent(weightedUpside, decimals: 1, signed: true),
                  hint: 'ao ano, em ${settings.convergenceHorizonMonths} meses',
                  valueColor: weightedUpside == null
                      ? null
                      : signedColor(weightedUpside, isLight),
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Reserva',
                  value: '${state.study.reserva.length}',
                  hint: 'candidatos',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Coluna de uma carteira, que é ao mesmo tempo alvo de soltura.
class _PortfolioColumn extends ConsumerWidget {
  final Portfolio portfolio;
  final bool isPrincipal;
  final bool isLight;

  const _PortfolioColumn({
    required this.portfolio,
    required this.isPrincipal,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<Ticker>(
      onWillAcceptWithDetails: (details) =>
          !portfolio.entries.containsKey(details.data),
      onAcceptWithDetails: (details) => ref
          .read(studyProvider.notifier)
          .swap(ticker: details.data, toPrincipal: isPrincipal),
      builder: (context, candidates, rejected) {
        final isHovered = candidates.isNotEmpty;
        return GlassCard(
          isLight: isLight,
          borderColor: isHovered
              ? AppColors.primary
              : (isPrincipal
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                isLight: isLight,
                title: isPrincipal ? 'Carteira Principal' : 'Carteira Reserva',
                subtitle: isPrincipal
                    ? 'Portfólio vigente'
                    : 'Candidatos a substituição',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (portfolio.length > 1)
                      IconButton(
                        tooltip: 'Equiponderar',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.balance,
                            size: 17, color: AppColors.textSecondary(isLight)),
                        onPressed: () => ref
                            .read(studyProvider.notifier)
                            .equalize(onPrincipal: isPrincipal),
                      ),
                    IconButton(
                      tooltip: 'Adicionar ativo',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.add_circle_outline,
                          size: 19, color: AppColors.primary),
                      onPressed: () => showAssetPicker(
                        context,
                        toPrincipal: isPrincipal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (portfolio.isEmpty)
                SizedBox(
                  height: 150,
                  child: EmptyState(
                    isLight: isLight,
                    icon: isHovered
                        ? Icons.download_outlined
                        : Icons.inbox_outlined,
                    title: isHovered ? 'Solte aqui' : 'Nenhum ativo',
                    message: isPrincipal
                        ? 'Adicione ativos ou arraste da Reserva.'
                        : 'Guarde aqui os candidatos a entrar na Principal.',
                  ),
                )
              else
                ...portfolio.entries.values.map(
                  (entry) => _AssetRow(
                    entry: entry,
                    isPrincipal: isPrincipal,
                    isLight: isLight,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Linha de um ativo — arrastável para a outra carteira.
class _AssetRow extends ConsumerWidget {
  final PortfolioEntry entry;
  final bool isPrincipal;
  final bool isLight;

  const _AssetRow({
    required this.entry,
    required this.isPrincipal,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuation = ref.watch(valuationProvider(entry.ticker));

    final content = _rowContent(context, ref, valuation.valueOrNull,
        isLoading: valuation.isLoading);

    return Draggable<Ticker>(
      data: entry.ticker,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF13224E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary),
            ),
            child: Text(
              entry.ticker.value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(isLight),
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      child: content,
    );
  }

  Widget _rowContent(
    BuildContext context,
    WidgetRef ref,
    ValuationResult? valuation, {
    required bool isLoading,
  }) {
    final upside = valuation?.upside;

    return InkWell(
      onTap: valuation == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ValuationPage(ticker: entry.ticker),
                ),
              ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.drag_indicator,
                size: 16, color: AppColors.textMuted(isLight)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.ticker.value,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(isLight),
                    ),
                  ),
                  Text(
                    entry.sector.isUnknown
                        ? 'Setor não classificado'
                        : entry.sector.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted(isLight),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.weight.toString(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(isLight),
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: AppColors.textMuted(isLight),
                    ),
                  )
                else
                  Text(
                    upside == null
                        ? '—'
                        : Fmt.percent(upside, decimals: 1, signed: true),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: upside == null
                          ? AppColors.textMuted(isLight)
                          : signedColor(upside, isLight),
                    ),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'Remover',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close,
                  size: 15, color: AppColors.textMuted(isLight)),
              onPressed: () => ref
                  .read(studyProvider.notifier)
                  .removeAsset(entry.ticker, fromPrincipal: isPrincipal),
            ),
          ],
        ),
      ),
    );
  }
}
