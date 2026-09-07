import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/portfolio_repository.dart';
import '../../di/providers.dart';
import '../components/fin_amount.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
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
            backgroundColor: context.fin.negative,
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

        // Largura util DENTRO de um cartao, descontando o padding da lista, o
        // vao entre as duas colunas quando lado a lado, e o padding do proprio
        // GlassCard.
        //
        // Calculada aqui, e nao com um `LayoutBuilder` dentro da coluna, por um
        // motivo concreto: o layout largo envolve as duas em `IntrinsicHeight`,
        // e `LayoutBuilder` nao sabe reportar dimensao intrinseca -- a arvore
        // lanca em vez de renderizar.
        // Derivados dos MESMOS tokens que a arvore aplica logo abaixo. Com
        // literais, mudar `FinSpace.lg` moveria o padding real e deixaria esta
        // conta para tras -- a coluna passaria a ser calculada com uma largura
        // que nao existe mais.
        const listPadding = FinSpace.lg * 2;
        const cardPadding = FinSpace.lg * 2;
        const columnGap = FinSpace.md;
        final columnWidth = isWide
            ? (constraints.maxWidth - listPadding - columnGap) / 2 - cardPadding
            : constraints.maxWidth - listPadding - cardPadding;

        final principal = _PortfolioColumn(
          portfolio: state.study.principal,
          isPrincipal: true,
          isLight: isLight,
          columnWidth: columnWidth,
        );
        final reserva = _PortfolioColumn(
          portfolio: state.study.reserva,
          isPrincipal: false,
          isLight: isLight,
          columnWidth: columnWidth,
        );

        // `CustomScrollView`, e nao `ListView`: cada cartao vira um sliver proprio,
        // entao o framework so infla os que entram na viewport -- e cada um ganha a
        // fronteira de repintura que o `SliverList` adiciona.
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(FinSpace.lg),
              sliver: SliverList.list(
                children: [
                  _StudyHeader(isLight: isLight),
                  const Gap.md(),
                  if (concentration.hasAlert) ...[
                    NoticeBanner(
                      icon: Icons.account_balance_outlined,
                      message: _concentrationMessage(concentration),
                    ),
                    const Gap.md(),
                  ],
                  if (isWide)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: principal),
                          const Gap.md(axis: Axis.horizontal),
                          Expanded(child: reserva),
                        ],
                      ),
                    )
                  else ...[
                    principal,
                    const Gap.md(),
                    reserva,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _concentrationMessage(ConcentrationReport report) {
    final parts = report.concentrated
        .map(
          (e) =>
              '${e.sector.label} (${e.count} ativos, ${Fmt.percent(e.weight, decimals: 0)})',
        )
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
    final anchors = ref.watch(marketAnchorsProvider);

    // Estimador transversal, o mesmo do cartao de meta: `CDI_spot + z x premio`.
    // Duas telas que dizem "Esperado da carteira" nao podem mostrar numeros de
    // definicoes diferentes, e a anualizacao do potencial saiu das duas ao mesmo
    // tempo -- ver `ExpectedReturn.crossSection`.
    double? weightedUpside;
    var coverage = 0.0;
    if (expected.hasValue && expected.value!.isNotEmpty) {
      weightedUpside = ExpectedReturn.forPortfolioCrossSectional(
        portfolio: state.study.principal,
        valuations: expected.value!,
        spotRiskFree:
            (anchors.value ?? MarketAnchors.fallback2026).currentRiskFreeRate,
      );
      coverage = ExpectedReturn.coverage(
        portfolio: state.study.principal,
        valuations: expected.value!,
      );
    }

    // Referência de leitura: o próprio CDI à vista, que é a âncora do
    // estimador. Acima dele a carteira está descontada em relação aos pares
    // avaliados; abaixo, esticada. A antiga referência era o triplo do CAGR do
    // Ibovespa, e existia porque o número podia ser um upside cru de +209% —
    // com o escore confinado a dois desvios robustos isso não acontece mais, e
    // o aviso que descrevia aquela conta saiu junto com ela.
    final cdi =
        (anchors.value ?? MarketAnchors.fallback2026).currentRiskFreeRate;

    return GlassCard(
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
                  style: context.finType.titleSm.copyWith(
                    color: context.fin.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Nome do estudo',
                    hintStyle: TextStyle(color: context.fin.textTertiary),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Estudos salvos',
                icon: Icon(
                  Icons.folder_open_outlined,
                  size: 19,
                  color: context.fin.textSecondary,
                ),
                onPressed: () => showSavedStudies(context, isLight: isLight),
              ),
              state.isSaving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: FinSpace.md),
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
                      icon: Icon(
                        Icons.save_outlined,
                        size: 19,
                        color: context.fin.brand,
                      ),
                      onPressed: () => _save(context, ref),
                    ),
            ],
          ),
          const Divider(height: 18),
          MetricTileRow(
            tiles: [
              MetricTile(
                label: 'Ativos na Principal',
                value:
                    '${state.study.principal.length}'
                    ' / ${Portfolio.maxAssets}',
              ),
              MetricTile(
                label: Lexico.esperado,
                value: weightedUpside == null
                    ? '—'
                    : Fmt.percent(weightedUpside, decimals: 1, signed: true),
                // A premissa que sustenta o número precisa vir junto dele. Não
                // é mais "se o preço justo for alcançado em N meses": é o CDI
                // à vista mais o prêmio proporcional ao quanto a carteira está
                // descontada em relação aos pares avaliados.
                hint: weightedUpside == null
                    ? null
                    : 'CDI à vista + prêmio pelo desconto relativo · '
                          '${Fmt.percent(coverage, decimals: 0)} da carteira '
                          'avaliada',
                // O sinal é contra o CDI, não contra zero: o estimador é
                // sempre não negativo, e pintar de verde uma carteira que
                // espera menos que a renda fixa inverteria a leitura.
                trend: weightedUpside == null
                    ? FinTrend.neutral
                    : FinAmount.trendOf(weightedUpside - cdi),
              ),
              MetricTile(
                label: 'Reserva',
                value: '${state.study.reserva.length}',
                hint: 'candidatos',
              ),
            ],
          ),
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
Future<void> showSavedStudies(BuildContext context, {required bool isLight}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.fin.surfaceRaised,
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
          padding: const EdgeInsets.fromLTRB(
            FinSpace.lg,
            FinSpace.lg,
            FinSpace.lg,
            FinSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
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
              const Gap.sm(),
              Flexible(
                child: studies.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(FinSpace.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => EmptyState(
                    icon: Icons.error_outline,
                    title: 'Não foi possível listar',
                    message: '$error',
                  ),
                  data: (list) => list.isEmpty
                      ? EmptyState(
                          icon: Icons.folder_off_outlined,
                          title: 'Nenhum estudo salvo',
                          message:
                              'Monte as carteiras e toque no disquete '
                              'para guardar este estudo.',
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: context.fin.divider),
                          itemBuilder: (_, i) =>
                              _SavedStudyTile(study: list[i], isLight: isLight),
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
      // Com padding zerado o nome encostava na borda do card e aparecia
      // cortado. O nome do estudo e livre e pode ser longo, entao ele tambem
      // precisa de elipse: sem `maxLines`, o texto estoura em vez de truncar.
      contentPadding: const EdgeInsets.symmetric(horizontal: FinSpace.sm),
      title: Text(
        study.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.finType.bodySm.copyWith(
          color: context.fin.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${study.principal.length} na Principal · '
        '${study.reserva.length} na Reserva'
        '${updatedAt == null ? '' : ' · ${Fmt.date.format(updatedAt)}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.finType.caption.copyWith(
          color: context.fin.textTertiary,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Excluir',
        icon: Icon(Icons.delete_outline, size: 18, color: context.fin.negative),
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
            child: Text(
              'Excluir',
              style: TextStyle(color: context.fin.negative),
            ),
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

  /// Largura util dentro do cartao, ja descontados os paddings.
  final double columnWidth;

  const _PortfolioColumn({
    required this.portfolio,
    required this.isPrincipal,
    required this.isLight,
    required this.columnWidth,
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
        // Medidas uma vez por coluna, nao por linha: e o que garante que
        // todas as linhas compartilhem a mesma grade.
        final widths = _columnWidths(context);

        // Largura minima util para o nome do ativo. Abaixo disto o ticker vira
        // reticencias e a linha deixa de informar -- melhor descer os numeros
        // para uma segunda linha.
        const nomeMinimo = 96.0;
        final fixo =
            _dragColumnWidth +
            widths.weight +
            widths.upside +
            _removeColumnWidth;
        final compact = columnWidth - fixo < nomeMinimo;
        return GlassCard(
          borderColor: isHovered
              ? context.fin.brand
              : (isPrincipal
                    ? context.fin.brand.withValues(alpha: 0.35)
                    : null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: isPrincipal ? 'Carteira Principal' : 'Carteira Reserva',
                subtitle: isPrincipal
                    ? 'Portfólio vigente'
                    : 'Candidatos a substituição',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HintIcon(
                      title: 'Colunas desta lista',
                      intro:
                          'O potencial vem do valuation de cada ativo, '
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
                        // 48 dp explicitos em vez de `VisualDensity.compact`,
                        // que encolheria o alvo para 40x40. O padding zerado
                        // impede que os 48 virem 48 + padding.
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.balance,
                          size: 17,
                          color: context.fin.textSecondary,
                        ),
                        onPressed: () => ref
                            .read(studyProvider.notifier)
                            .equalize(onPrincipal: isPrincipal),
                      ),
                    IconButton(
                      tooltip: 'Adicionar ativo',
                      // Mesmos 48 dp dos botoes Equiponderar e Remover: o
                      // `VisualDensity.compact` sozinho encolheria o alvo
                      // para 40x40.
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: 19,
                        color: context.fin.brand,
                      ),
                      onPressed: () =>
                          showAssetPicker(context, toPrincipal: isPrincipal),
                    ),
                  ],
                ),
              ),
              const Gap.sm(),
              if (portfolio.isEmpty)
                // `minHeight`, e nao `height`: com altura travada em 150 dp o
                // `Column` do EmptyState estourava por 8 px assim que o texto
                // crescia -- e estourava em 1024 dp na escala padrao, ou seja
                // nao era questao de tela estreita. O minimo preserva a
                // presenca visual da coluna vazia sem impor teto ao conteudo.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 150),
                  child: EmptyState(
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
                _AssetColumnHeader(
                  isLight: isLight,
                  weightWidth: widths.weight,
                  upsideWidth: widths.upside,
                  compact: compact,
                ),
                ...portfolio.entries.values.map(
                  (entry) => _AssetRow(
                    isLight: isLight,
                    entry: entry,
                    isPrincipal: isPrincipal,
                    weightWidth: widths.weight,
                    upsideWidth: widths.upside,
                    compact: compact,
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
/// Medidas, não declaradas. O objetivo continua o mesmo — manter peso e
/// potencial alinhados de uma linha para a outra, e impedir que um "+447%"
/// empurre o resto da linha —, mas o instrumento mudou: constante em pixel
/// lógico alinha em 1,0× e trunca em 1,3×, porque não acompanha a fonte que o
/// usuário escolheu.
///
/// As amostras são o pior caso REAL de cada coluna, não o conteúdo corrente: o
/// potencial chega de um provider assíncrono, então dimensionar pelo que já
/// chegou faria a coluna saltar de largura conforme os valuations resolvessem.
/// Alca de arraste: icone de 16 dp mais o vao de 8 ate o nome.
const double _dragColumnWidth = 24;

/// Alvo de toque do botao de remover. 48 dp por ser acao destrutiva -- um
/// toque errado tira o ativo da carteira.
const double _removeColumnWidth = 48;

/// Estilo do rótulo de coluna.
///
/// Vive aqui, e não dentro do cabeçalho, porque [_columnWidths] precisa medir
/// exatamente o que [_AssetColumnHeader] desenha. Enquanto o estilo era local
/// ao `build`, a medida usava `numSm` e o desenho usava `caption` — e o
/// cabeçalho saía como "POTENCI…" numa largura de celular comum.
TextStyle _columnLabelStyle(BuildContext context) =>
    context.finType.caption.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: context.fin.textTertiary,
    );

/// Larguras das colunas numéricas.
///
/// A regra é medir **o mais largo que a coluna pode chegar a desenhar**, e não
/// uma amostra representativa. Medir amostra que não corresponde ao conteúdo
/// real foi a origem de três truncamentos simultâneos em 390 dp:
///
///   - peso media `100%` (4 caracteres) e desenhava `25,00%` (6), porque o
///     peso sai com duas casas decimais;
///   - potencial media `-1.000%` em `numSm` e desenhava `POTENCIAL` em
///     `caption` com espaçamento entre letras, que é mais largo;
///   - a mesma coluna ainda abriga `justo R$ …`, que nunca entrou na conta.
///
/// Os três cortavam justamente o número que a tela existe para mostrar. A
/// suíte de estouro não pegava nada disso porque exercita a tela vazia, onde
/// nenhuma dessas células chega a ser construída.
({double weight, double upside}) _columnWidths(BuildContext context) {
  final t = context.finType;
  final rotulo = _columnLabelStyle(context);

  double maiorDe(List<(String, TextStyle)> amostras) => amostras
      .map((a) => FinAmount.measure(context, a.$1, a.$2))
      .reduce(math.max);

  return (
    // A amostra vem do PRÓPRIO formatador que a célula usa, e não de um
    // literal: assim a medida não pode divergir do texto desenhado.
    weight:
        maiorDe([(Fmt.weightCeiling, t.numSm), ('PESO', rotulo)]) +
        FinSpace.xs,
    // A coluna empilha três conteúdos de larguras diferentes. O preço justo
    // usa uma amostra folgada para a B3 — acima disso a elipse volta, e é o
    // comportamento aceito: o percentual acima continua legível.
    upside:
        maiorDe([
          ('-1.000%', t.numSm),
          ('POTENCIAL', rotulo),
          // `captionNum`, o mesmo estilo que a celula desenha. Cifra tabular
          // muda a largura do digito, entao medir com `caption` erraria a
          // conta -- que e a divergencia entre medida e desenho que esta
          // funcao inteira existe para nao repetir.
          ('justo R\$ 9.999,99', t.captionNum),
        ]) +
        FinSpace.sm,
  );
}

/// Cabeçalho das colunas numéricas.
///
/// Antes havia dois números empilhados no canto direito, sem rótulo nenhum:
/// não dava para saber que o de cima era o peso e o de baixo a distância até o
/// preço justo. Nomear a coluna uma vez custa uma linha e resolve.
class _AssetColumnHeader extends StatelessWidget {
  final bool isLight;

  /// Larguras medidas pela coluna, iguais as das linhas abaixo.
  final double weightWidth;
  final double upsideWidth;

  /// No modo compacto nao ha colunas para rotular: os valores descem para uma
  /// segunda linha dentro de cada item, com rotulo proprio.
  final bool compact;

  const _AssetColumnHeader({
    required this.isLight,
    required this.weightWidth,
    required this.upsideWidth,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox.shrink();

    // O mesmo estilo que `_columnWidths` mediu. Declará-lo aqui de novo faria
    // medida e desenho divergirem outra vez.
    final style = _columnLabelStyle(context);

    return Padding(
      // `xs`, nao `xxs`: aqui e espacamento de layout entre o cabecalho e a
      // primeira linha, e o meio passo e reservado a ajuste optico dentro de
      // pastilha. Usa-lo aqui seria contornar a escala de 4 dp.
      padding: const EdgeInsets.only(
        left: FinSpace.xs,
        right: FinSpace.xs,
        bottom: FinSpace.xs,
      ),
      child: Row(
        children: [
          // As mesmas constantes que a linha usa, para que o rotulo caia
          // exatamente sobre a coluna que ele nomeia.
          const SizedBox(width: _dragColumnWidth),
          Expanded(child: Text('ATIVO', style: style)),
          SizedBox(
            width: weightWidth,
            child: Text(
              'PESO',
              style: style,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: upsideWidth,
            child: Text(
              'POTENCIAL',
              style: style,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: _removeColumnWidth),
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

  /// Larguras medidas pela coluna, iguais para todas as linhas dela.
  ///
  /// Vem de fora justamente para que sejam iguais: medir por linha alinharia
  /// cada uma consigo mesma e desalinharia a coluna inteira.
  final double weightWidth;
  final double upsideWidth;

  /// Quando as colunas medidas nao cabem ao lado do nome, os numeros descem
  /// para uma segunda linha.
  ///
  /// E o caso de 320 dp sob escala 2,0x: as colunas crescem com a fonte, como
  /// devem, e simplesmente nao ha largura para nome e numeros lado a lado.
  /// Antes isso nao aparecia porque a largura era constante e o texto truncava
  /// em silencio -- o numero saia errado sem que ninguem soubesse.
  final bool compact;

  const _AssetRow({
    required this.entry,
    required this.isPrincipal,
    required this.isLight,
    required this.weightWidth,
    required this.upsideWidth,
    required this.compact,
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

    final content = _rowContent(
      context,
      ref,
      valuation.value,
      isLoading: valuation.isLoading,
    );

    return Draggable<Ticker>(
      data: entry.ticker,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(FinSpace.md),
            decoration: BoxDecoration(
              color: context.fin.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.fin.brand),
            ),
            child: Text(
              entry.ticker.value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.fin.textPrimary,
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
        padding: const EdgeInsets.symmetric(
          vertical: FinSpace.sm,
          horizontal: FinSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: context.fin.textTertiary,
                ),
                const Gap.sm(axis: Axis.horizontal),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.ticker.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.finType.bodySm.copyWith(
                          fontWeight: FontWeight.bold,
                          color: context.fin.textPrimary,
                        ),
                      ),
                      Text(
                        entry.sector.isUnknown
                            ? 'Setor não classificado'
                            : entry.sector.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.finType.caption.copyWith(
                          color: context.fin.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  SizedBox(
                    width: weightWidth,
                    child: Text(
                      Fmt.weight(entry.weight.value),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.finType.numSm.copyWith(
                        color: context.fin.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: upsideWidth,
                    child: isLoading
                        ? _UpsideSkeleton(width: upsideWidth)
                        : _UpsideCell(
                            upside: upside,
                            fairValue: valuation?.fairValue.reais,
                            model: valuation?.model,
                            isOutlier: isOutlier,
                            hasWarnings: hasWarnings,
                            isLight: isLight,
                          ),
                  ),
                ],
                IconButton(
                  tooltip: 'Remover',
                  visualDensity: VisualDensity.compact,
                  // `VisualDensity.compact` encolhe o alvo de toque de 48x48 para
                  // 40x40. Aqui a restricao explicita devolve os 48 dp SEM crescer
                  // o icone: a acao e destrutiva -- um toque errado remove o ativo
                  // da carteira -- e errar por densidade visual sai caro demais.
                  // O padding zerado impede que os 48 dp virem 48 + padding.
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.close,
                    size: 15,
                    color: context.fin.textTertiary,
                  ),
                  onPressed: () => ref
                      .read(studyProvider.notifier)
                      .removeAsset(entry.ticker, fromPrincipal: isPrincipal),
                ),
              ],
            ),
            // Segunda linha do modo compacto. Os rotulos vem junto porque o
            // cabecalho de colunas some aqui, e peso e potencial sao os dois
            // percentuais -- sem rotulo, um passa pelo outro.
            //
            // `Wrap`, e nao `Row`: um `Text` de rotulo nao encolhe abaixo da
            // largura intrinseca dentro de uma `Row`, entao a linha estourava
            // em 320 dp. O `Wrap` quebra em duas linhas quando precisa, o que
            // e o comportamento certo aqui -- e nao ha o que truncar.
            if (compact)
              Padding(
                padding: const EdgeInsets.only(
                  left: _dragColumnWidth,
                  top: FinSpace.xs,
                ),
                child: Wrap(
                  spacing: FinSpace.md,
                  runSpacing: FinSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'peso',
                          style: context.finType.caption.copyWith(
                            color: context.fin.textTertiary,
                          ),
                        ),
                        const Gap.xs(axis: Axis.horizontal),
                        // `Flexible` pelo mesmo motivo do grupo ao lado: um
                        // `Text` nao encolhe abaixo da largura intrinseca
                        // dentro de uma `Row`, e em 320 dp sob 2,0x nem o par
                        // rotulo+valor cabe na faixa.
                        Flexible(
                          child: Text(
                            Fmt.weight(entry.weight.value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.finType.numSm.copyWith(
                              color: context.fin.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'potencial',
                          style: context.finType.caption.copyWith(
                            color: context.fin.textTertiary,
                          ),
                        ),
                        const Gap.xs(axis: Axis.horizontal),
                        // `Flexible`: dentro do `Wrap` esta `Row` recebe a
                        // largura da faixa, e a celula precisa poder ceder --
                        // sem isto ela impoe a largura intrinseca e estoura.
                        Flexible(
                          child: isLoading
                              ? _UpsideSkeleton(width: upsideWidth)
                              : _UpsideCell(
                                  upside: upside,
                                  fairValue: valuation?.fairValue.reais,
                                  model: valuation?.model,
                                  isOutlier: isOutlier,
                                  hasWarnings: hasWarnings,
                                  isLight: isLight,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Espaço reservado enquanto o valuation não chegou.
///
/// Substitui um `CircularProgressIndicator` de **9×9 px com traço de 1,4** que
/// ocupava esta célula. Ele falhava nas duas pontas: um ponto cinza tremendo
/// não diz o que está vindo, e ao sumir deslocava a linha, porque a altura
/// dele não era a do conteúdo final.
///
/// A geometria aqui vem do estilo real sob a escala corrente, então a linha
/// não salta quando o número chega.
class _UpsideSkeleton extends StatefulWidget {
  final double width;

  const _UpsideSkeleton({required this.width});

  @override
  State<_UpsideSkeleton> createState() => _UpsideSkeletonState();
}

class _UpsideSkeletonState extends State<_UpsideSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Respeita "reduzir movimento" do sistema: sem esta guarda o esqueleto
    // pulsa para quem pediu explicitamente que nada pulse.
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
    final t = context.finType;
    final scaler = MediaQuery.textScalerOf(context);

    final alturaValor = scaler.scale(t.numSm.fontSize!) * t.numSm.height!;
    final alturaNota = scaler.scale(t.caption.fontSize!) * t.caption.height!;

    return Semantics(
      label: 'Calculando o potencial',
      child: ExcludeSemantics(
        // Uma carteira com dez ativos por avaliar tem dez destes pulsando ao
        // mesmo tempo dentro de uma lista rolavel. Sem a fronteira, cada
        // oscilacao invalida a camada inteira e a rolagem perde quadros.
        child: RepaintBoundary(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 0.75).animate(_pulse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Barra(
                  width: widget.width * 0.6,
                  height: alturaValor,
                  color: c.surfaceSunken,
                ),
                const Gap.xs(),
                _Barra(
                  width: widget.width * 0.85,
                  height: alturaNota,
                  color: c.surfaceSunken,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _Barra({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
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
      return FinAmount(
        text: '—',
        style: context.finType.numSm,
        trend: FinTrend.blocked,
      );
    }

    // Potencial fora da banda vira ressalva, não perda: âmbar diz "olhe as
    // premissas antes de confiar", enquanto vermelho diria "caiu" — e um
    // upside de +447% não caiu.
    final trend = isOutlier ? FinTrend.caution : FinAmount.trendOf(value);
    final color = context.fin.forTrend(trend);

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
                const Gap.xs(axis: Axis.horizontal),
              ],
              Flexible(
                child: FinAmount(
                  text: Fmt.percent(value, decimals: 0, signed: true),
                  style: context.finType.numSm,
                  trend: trend,
                ),
              ),
            ],
          ),
          if (fairValue != null)
            Text(
              'justo ${Fmt.money(fairValue!)}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              // `captionNum`, nao `caption`: e dinheiro numa coluna alinhada a
              // direita, e sem cifra tabular a virgula decimal anda de uma
              // linha para a outra. Regra R18.
              style: context.finType.captionNum.copyWith(
                color: context.fin.textTertiary,
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
      ..write(
        '. Não é previsão de retorno: só se realiza se o mercado '
        'convergir para essa estimativa, e não há prazo para isso.',
      );
    if (isOutlier) {
      buffer.write(
        '\n\nDiferença acima de 100%: quase sempre vem de um '
        'exercício-base atípico ou de demonstrativo incompleto. Toque para '
        'ver as premissas e os avisos.',
      );
    } else if (hasWarnings) {
      buffer.write('\n\nEsta avaliação tem ressalvas. Toque para lê-las.');
    }
    return buffer.toString();
  }
}
