import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../shared/ui_kit.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'manual_copy.dart';
import 'manual_valuation_page.dart';
import 'saved_valuations.dart';

/// **Seus valuations salvos** do ativo (decisão 150): o que o usuário
/// confirmou na edição, com as premissas e o resultado de cada um.
///
/// Fica logo abaixo do preço do motor porque é com ele que se compara: o
/// preço justo do motor é o validado, e estes são a opinião do usuário em cada
/// dia em que ele confirmou uma. Os números são os **do dia da confirmação** —
/// o preço de mercado e o preço do motor também —, e não uma conta refeita.
///
/// Sem valuation salvo para o ativo, o cartão não aparece: o convite para
/// criar um já está no botão "Editar valuation".
class SavedValuationsCard extends ConsumerWidget {
  /// A avaliação do motor exibida na tela, para reabrir um valuation salvo
  /// sobre a conta congelada de hoje.
  final ValuationResult result;

  /// Declara o cartão.
  const SavedValuationsCard({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedValuationsProvider);
    final c = context.fin;
    final t = context.finType;

    if (saved.hasError && !saved.hasValue) {
      return Padding(
        padding: const EdgeInsets.only(top: FinSpace.md),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: 'Seus valuations salvos'),
              const Gap.sm(),
              Text(
                'Não foi possível carregar os seus valuations salvos agora. '
                'Os que você confirmar continuam indo ao painel de logs.',
                style: t.bodySm.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final records = [
      for (final r in saved.value ?? const <ManualValuationRecord>[])
        if (r.ticker == result.ticker) r,
    ];
    if (records.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: FinSpace.md),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Seus valuations salvos',
              subtitle:
                  '${records.length} confirmado(s) na edição, do mais '
                  'recente ao mais antigo. Cada um também está no painel de '
                  'logs.',
            ),
            const Gap.sm(),
            for (final (i, record) in records.indexed) ...[
              if (i > 0) Divider(height: FinSpace.md, color: c.border),
              _SavedTile(record: record, result: result),
            ],
          ],
        ),
      ),
    );
  }
}

/// Um valuation salvo: o resumo à vista, as premissas e o resultado ao abrir.
class _SavedTile extends ConsumerWidget {
  final ManualValuationRecord record;
  final ValuationResult result;

  const _SavedTile({required this.record, required this.result});

  static final _stamp = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fin;
    final t = context.finType;
    final o = record.outcome;
    final upside = record.upside;
    final delta = record.engineDelta;
    final changed = record.changedFields;
    final manual = result.manual;
    // O lucro de partida é NOPAT numa via e lucro líquido na outra: reabrir
    // numa via diferente da do registro poria o número no campo errado.
    final canReopen = manual != null && manual.lane == record.lane;

    final summary = [
      _stamp.format(record.savedAt),
      if (upside != null)
        // Interpolação única: strings adjacentes numa lista enganam a leitura.
        '${Fmt.percent(upside, decimals: 1, signed: true)} sobre o mercado de ${Fmt.money(record.marketPrice)}',
      '${delta >= 0 ? '+' : '−'}${Fmt.money(delta.abs())} contra o motor',
    ].join(' · ');

    // Material transparente, e não o cartão direto: o `ListTile` do
    // `ExpansionTile` pinta a tinta do toque no Material mais próximo, e o
    // fundo do cartão a esconderia — o framework acusa isso em depuração.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        // Sem as linhas que o `ExpansionTile` desenha ao abrir: o cartão já tem
        // os divisores entre os registros.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: FinSpace.sm),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          iconColor: c.textSecondary,
          collapsedIconColor: c.textSecondary,
          title: Text(
            '${Fmt.money(o.fairValuePerShare)} por ação',
            style: t.titleSm.copyWith(color: c.textPrimary),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Gap.xs(),
              Text(summary, style: t.caption.copyWith(color: c.textSecondary)),
              const Gap.xs(),
              Text(
                changed.isEmpty
                    ? 'Nenhum campo trocado: o preço do motor naquele dia.'
                    : 'Você trocou: ${[for (final f in changed) ManualCopy.label(f, record.lane).toLowerCase()].join(', ')}.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
            ],
          ),
          children: [
            _Section(title: 'Seus números', rows: _inputs(record)),
            const Gap.md(),
            _Section(title: 'O resultado', rows: _outputs(record)),
            if (o.notices.isNotEmpty) ...[
              const Gap.sm(),
              for (final n in o.notices)
                Padding(
                  padding: const EdgeInsets.only(bottom: FinSpace.xs),
                  child: NoticeBanner(message: ManualCopy.warning(n)),
                ),
            ],
            const Gap.sm(),
            Wrap(
              spacing: FinSpace.sm,
              runSpacing: FinSpace.xs,
              children: [
                TextButton.icon(
                  onPressed: canReopen
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ManualValuationPage(
                              result: result,
                              initial: record.premises,
                            ),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Reabrir na edição'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(context, ref),
                  style: TextButton.styleFrom(foregroundColor: c.negative),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Apagar'),
                ),
              ],
            ),
            if (!canReopen)
              Text(
                'A avaliação de hoje mudou de via: os números deste valuation '
                'não cabem nos campos dela.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar este valuation?'),
        content: const Text(
          'Ele sai dos seus valuations salvos e não volta. O registro que ele '
          'deixou no painel de logs desta sessão continua lá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(savedValuationsProvider.notifier)
        .remove(record.id);
    final failure = removed.failureOrNull;
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(failure.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// As premissas confirmadas, como a tela de edição as escreve.
  static List<(String, String)> _inputs(ManualValuationRecord r) {
    final p = r.premises;
    final lane = r.lane;
    String label(ManualField f) => ManualCopy.label(f, lane);
    return [
      (label(ManualField.baseProfit), _millions(p.baseProfit)),
      (
        label(ManualField.growth),
        '${Fmt.percent(p.growth)} no ano 1, '
            '${p.growthPath == ManualGrowthPath.constant ? 'constante nos 10 anos' : 'caindo até a perpetuidade'}',
      ),
      (label(ManualField.perpetualGrowth), Fmt.percent(p.perpetualGrowth)),
      (
        label(ManualField.discountRate),
        '${Fmt.percent(p.discountRate)} no ano 1, '
            '${p.ratePath == ManualRatePath.constant ? 'uma taxa só' : 'seguindo a curva'}',
      ),
      if (p.reinvestment == ManualReinvestment.byReturn)
        (label(ManualField.returnOnCapital), Fmt.percent(p.returnOnCapital))
      else
        (label(ManualField.retention), Fmt.percent(p.retention, decimals: 1)),
      (
        label(ManualField.terminalReturn),
        p.terminalReturn == null
            ? 'igual à taxa'
            : Fmt.percent(p.terminalReturn!),
      ),
    ];
  }

  /// O resultado guardado, na ordem da ponte da tela de edição.
  static List<(String, String)> _outputs(ManualValuationRecord r) {
    final o = r.outcome;
    final upside = r.upside;
    return [
      ('Valor presente dos 10 anos', _millions(o.explicitPresentValue)),
      ('Valor presente da perpetuidade', _millions(o.terminalPresentValue)),
      if (o.minorityInterest > 0)
        ('− Minoritários das controladas', _millions(-o.minorityInterest)),
      if (o.postStatementCapital > 0)
        (
          '+ Ações emitidas depois do balanço',
          _millions(o.postStatementCapital),
        ),
      ('Valor do patrimônio (VPL)', _millions(o.equityValue)),
      ('Seu preço justo por ação', Fmt.money(o.fairValuePerShare)),
      ('Preço justo do motor naquele dia', Fmt.money(r.engineFairValue)),
      ('Preço de mercado naquele dia', Fmt.money(r.marketPrice)),
      if (upside != null)
        ('Seu potencial', Fmt.percent(upside, decimals: 1, signed: true)),
      ('Avaliação do motor de', Fmt.date.format(r.engineAsOf)),
    ];
  }

  static String _millions(double v) =>
      '${v < 0 ? '−' : ''}R\$ ${Fmt.ratio(v.abs() / 1e6, decimals: 1)} mi';
}

class _Section extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = context.finType;
    final c = context.fin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.caption.copyWith(color: c.textSecondary)),
        const Gap.xs(),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: FinSpace.xs),
            child: LabelValueRow(label: label, value: value),
          ),
      ],
    );
  }
}
