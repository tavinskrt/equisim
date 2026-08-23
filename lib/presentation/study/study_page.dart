import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/portfolio_repository.dart';
import '../../di/providers.dart';
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

    final anchors = ref.watch(marketAnchorsProvider);

    double? weightedUpside;
    var coverage = 0.0;
    if (expected.hasValue && expected.value!.isNotEmpty) {
      weightedUpside = ExpectedReturn.forPortfolio(
        portfolio: state.study.principal,
        valuations: expected.value!,
        netDividendYields: yields.valueOrNull ?? const {},
        horizonMonths: settings.convergenceHorizonMonths,
      );
      coverage = ExpectedReturn.coverage(
        portfolio: state.study.principal,
        valuations: expected.value!,
      );
    }

    // Referência de plausibilidade: o retorno histórico do próprio mercado.
    // Um "esperado" muito acima dele não é promessa de desempenho, é sinal de
    // que alguma avaliação da carteira está esticada.
    final marketCagr =
        anchors.valueOrNull?.marketCagr ?? MarketAnchors.fallback2026.marketCagr;
    final isImplausible =
        weightedUpside != null && weightedUpside > marketCagr * 3;

    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  // A chave amarra o campo ao estudo aberto: sem ela,
                  // `initialValue` só vale na primeira construção e o nome de
                  // um estudo carregado do Firestore nunca apareceria aqui.
                  key: ValueKey(state.study.id ?? '__novo__'),
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
              IconButton(
                tooltip: 'Estudos salvos',
                icon: Icon(Icons.folder_open_outlined,
                    size: 19, color: AppColors.textSecondary(isLight)),
                onPressed: () => showSavedStudies(context, isLight: isLight),
              ),
              state.isSaving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: state.study.id == null
                          ? 'Salvar estudo'
                          : 'Salvar alterações',
                      icon: Icon(Icons.save_outlined,
                          size: 19, color: AppColors.primary),
                      onPressed: () => _save(context, ref),
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
                  label: 'Esperado da carteira',
                  value: weightedUpside == null
                      ? '—'
                      : Fmt.percent(weightedUpside, decimals: 1, signed: true),
                  // O rótulo antigo dizia "ao ano, em 12 meses" e omitia a
                  // premissa que sustenta o número: que o mercado fecha toda a
                  // diferença até o preço justo dentro do horizonte. Com 12
                  // meses a anualização não faz nada, e o valor é literalmente
                  // o upside médio somado ao dividend yield.
                  hint: weightedUpside == null
                      ? null
                      : 'se o preço justo for alcançado em '
                          '${settings.convergenceHorizonMonths} meses · '
                          '${Fmt.percent(coverage, decimals: 0)} da carteira '
                          'avaliada',
                  valueColor: weightedUpside == null
                      ? null
                      : (isImplausible
                          ? (isLight
                              ? AppColors.warning
                              : AppColors.warningDark)
                          : signedColor(weightedUpside, isLight)),
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
          if (isImplausible) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              isLight: isLight,
              icon: Icons.warning_amber_rounded,
              color: isLight ? AppColors.warning : AppColors.warningDark,
              message: 'O esperado da carteira está em '
                  '${Fmt.percent(weightedUpside, decimals: 0, signed: true)}, '
                  'contra ${Fmt.percent(marketCagr, decimals: 1)} a.a. do '
                  'Ibovespa no histórico. Não leia como projeção: é a média '
                  'ponderada da distância até o preço justo, e basta um ativo '
                  'com avaliação esticada para dominá-la. Os marcados com ⚠ '
                  'na lista são os candidatos.',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref.read(studyProvider.notifier).save();
    // O erro já vira SnackBar no `ref.listen` da StudyPage; aqui só falta a
    // confirmação do caminho feliz, que sem isto era silenciosa e deixava a
    // dúvida de ter salvo ou não.
    if (!saved) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Estudo salvo. Abra em "Estudos salvos" quando voltar.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }
}

/// Folha dos estudos gravados no Firestore.
///
/// Salvar sem poder reabrir não resolveria o problema que motivou a
/// funcionalidade — remontar carteiras de nove ativos a cada sessão.
Future<void> showSavedStudies(
  BuildContext context, {
  required bool isLight,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isLight ? Colors.white : const Color(0xFF13224E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _SavedStudiesSheet(isLight: isLight),
  );
}

class _SavedStudiesSheet extends ConsumerWidget {
  final bool isLight;

  const _SavedStudiesSheet({required this.isLight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studies = ref.watch(savedStudiesProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                isLight: isLight,
                title: 'Estudos salvos',
                subtitle: 'Abrir recarrega as duas carteiras e a meta',
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Novo'),
                  onPressed: () {
                    ref.read(studyProvider.notifier).startNew();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: studies.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => EmptyState(
                    isLight: isLight,
                    icon: Icons.error_outline,
                    title: 'Não foi possível listar',
                    message: '$error',
                  ),
                  data: (list) => list.isEmpty
                      ? EmptyState(
                          isLight: isLight,
                          icon: Icons.folder_off_outlined,
                          title: 'Nenhum estudo salvo',
                          message: 'Monte as carteiras e toque no disquete '
                              'para guardar este estudo.',
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: AppColors.divider(isLight),
                          ),
                          itemBuilder: (_, i) => _SavedStudyTile(
                            study: list[i],
                            isLight: isLight,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedStudyTile extends ConsumerWidget {
  final PortfolioStudy study;
  final bool isLight;

  const _SavedStudyTile({required this.study, required this.isLight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatedAt = study.updatedAt;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        study.name,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(isLight),
        ),
      ),
      subtitle: Text(
        '${study.principal.length} na Principal · '
        '${study.reserva.length} na Reserva'
        '${updatedAt == null ? '' : ' · ${Fmt.date.format(updatedAt)}'}',
        style: TextStyle(fontSize: 10.5, color: AppColors.textMuted(isLight)),
      ),
      trailing: IconButton(
        tooltip: 'Excluir',
        icon: Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
        onPressed: () => _confirmDelete(context, ref),
      ),
      onTap: () {
        ref.read(studyProvider.notifier).load(study);
        Navigator.of(context).pop();
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final id = study.id;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir estudo'),
        content: Text('"${study.name}" será removido definitivamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Excluir', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(studyProvider.notifier).deleteSaved(id);
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
                    HintIcon(
                      isLight: isLight,
                      title: 'Colunas desta lista',
                      intro: 'O potencial vem do valuation de cada ativo, '
                          'recalculado a cada abertura da tela.',
                      entries: const [
                        HintEntry(
                          'Peso',
                          'Fatia do aporte destinada ao ativo. Não há '
                              'rebalanceamento: o peso define para onde vai '
                              'cada aporte, e a partir daí a posição deriva '
                              'com o mercado.',
                        ),
                        HintEntry(
                          'Potencial',
                          'Distância entre a cotação e o preço justo estimado '
                              'pelo modelo, em percentual, com o preço justo '
                              'logo abaixo. É a discordância entre o modelo e '
                              'o mercado — não um retorno previsto, e sem '
                              'prazo para se realizar.',
                        ),
                        HintEntry(
                          'Marca ⚠',
                          'Potencial acima de 100% em qualquer direção, ou '
                              'avaliação com ressalvas. Costuma indicar '
                              'exercício-base atípico, crescimento no teto da '
                              'banda de sanidade ou demonstrativo incompleto. '
                              'Toque no ativo para ver as premissas.',
                        ),
                      ],
                    ),
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
              else ...[
                _AssetColumnHeader(isLight: isLight),
                ...portfolio.entries.values.map(
                  (entry) => _AssetRow(
                    entry: entry,
                    isPrincipal: isPrincipal,
                    isLight: isLight,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Larguras das colunas numéricas da lista de ativos.
///
/// Fixas de propósito: é o que mantém peso e potencial alinhados de uma linha
/// para a outra, e o que impede um "+447%" de empurrar o resto da linha.
const double _weightColumnWidth = 52;
const double _upsideColumnWidth = 78;

/// Cabeçalho das colunas numéricas.
///
/// Antes havia dois números empilhados no canto direito, sem rótulo nenhum:
/// não dava para saber que o de cima era o peso e o de baixo a distância até o
/// preço justo. Nomear a coluna uma vez custa uma linha e resolve.
class _AssetColumnHeader extends StatelessWidget {
  final bool isLight;

  const _AssetColumnHeader({required this.isLight});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 9,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted(isLight),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
      child: Row(
        children: [
          const SizedBox(width: 22),
          Expanded(child: Text('ATIVO', style: style)),
          SizedBox(
            width: _weightColumnWidth,
            child: Text('PESO', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _upsideColumnWidth,
            child: Text('POTENCIAL', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 32),
        ],
      ),
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

  /// Acima disto o número deixa de ser estimativa e vira sintoma.
  ///
  /// Um preço justo ao dobro ou à metade do preço de mercado não sai de uma
  /// discordância de premissas: sai de um fluxo-base atípico, de um
  /// crescimento no teto da banda ou de um demonstrativo incompleto. A linha
  /// continua mostrando o número medido — esconder seria pior —, mas marcado,
  /// para não ser lido como precisão.
  static const double _outlierThreshold = 1.0;

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
    final isOutlier = upside != null && upside.abs() >= _outlierThreshold;
    final hasWarnings = valuation != null && valuation.warnings.isNotEmpty;

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
            SizedBox(
              width: _weightColumnWidth,
              child: Text(
                entry.weight.toString(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(isLight),
                ),
              ),
            ),
            SizedBox(
              width: _upsideColumnWidth,
              child: isLoading
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: AppColors.textMuted(isLight),
                        ),
                      ),
                    )
                  : _UpsideCell(
                      upside: upside,
                      fairValue: valuation?.fairValue.reais,
                      model: valuation?.model,
                      isOutlier: isOutlier,
                      hasWarnings: hasWarnings,
                      isLight: isLight,
                    ),
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

/// A célula de potencial: o número, o preço justo que o originou e a marca de
/// ressalva.
///
/// Mostrar o preço justo embaixo é o que transforma "+447%" de número solto em
/// afirmação verificável — o leitor compara com a cotação que já conhece e
/// decide sozinho se acredita.
class _UpsideCell extends StatelessWidget {
  final double? upside;
  final double? fairValue;
  final ValuationModel? model;
  final bool isOutlier;
  final bool hasWarnings;
  final bool isLight;

  const _UpsideCell({
    required this.upside,
    required this.fairValue,
    required this.model,
    required this.isOutlier,
    required this.hasWarnings,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final value = upside;
    if (value == null) {
      return Text(
        '—',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted(isLight),
        ),
      );
    }

    final color = isOutlier
        ? (isLight ? AppColors.warning : AppColors.warningDark)
        : signedColor(value, isLight);

    return Tooltip(
      message: _tooltip(value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOutlier || hasWarnings) ...[
                Icon(Icons.warning_amber_rounded, size: 11, color: color),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  Fmt.percent(value, decimals: 0, signed: true),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (fairValue != null)
            Text(
              'justo ${Fmt.money(fairValue!)}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: AppColors.textMuted(isLight),
              ),
            ),
        ],
      ),
    );
  }

  String _tooltip(double value) {
    final buffer = StringBuffer()
      ..write('Distância entre o preço de mercado e o preço justo estimado')
      ..write(model == null ? '' : ' por ${model!.label}')
      ..write('. Não é previsão de retorno: só se realiza se o mercado '
          'convergir para essa estimativa, e não há prazo para isso.');
    if (isOutlier) {
      buffer.write('\n\nDiferença acima de 100%: quase sempre vem de um '
          'exercício-base atípico ou de demonstrativo incompleto. Toque para '
          'ver as premissas e os avisos.');
    } else if (hasWarnings) {
      buffer.write('\n\nEsta avaliação tem ressalvas. Toque para lê-las.');
    }
    return buffer.toString();
  }
}

