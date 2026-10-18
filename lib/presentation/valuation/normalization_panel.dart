import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';

import '../shared/ui_kit.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'normalization_copy.dart';

/// **Por que o motor normalizou o lucro de partida — ou não —, e em que
/// direção.**
///
/// Pedido do orientador em 14/10/2026: entender o porquê das normalizações, e
/// não retirá-las. O painel responde com os números do ativo: o retorno do
/// último exercício contra o típico, os anos que formam o típico, o teste que
/// decidiu, a conta e as travas que pesaram. Tudo sai de [BaseNormalization],
/// que guarda o que a cascata usou — nada aqui recalcula a guarda.
///
/// Abre expandido quando o motor partiu de outro lucro que não o publicado:
/// é aí que a pergunta aparece.
class NormalizationPanel extends StatefulWidget {
  /// A decisão da normalização.
  final BaseNormalization normalization;

  /// Declara o painel.
  const NormalizationPanel({super.key, required this.normalization});

  @override
  State<NormalizationPanel> createState() => _NormalizationPanelState();
}

class _NormalizationPanelState extends State<NormalizationPanel> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = switch (widget.normalization.outcome) {
      BaseNormalizationOutcome.upward ||
      BaseNormalizationOutcome.downward ||
      BaseNormalizationOutcome.rebuilt =>
        true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final n = widget.normalization;
    final test = NormalizationCopy.test(n);
    final account = NormalizationCopy.account(n);
    final warnings = NormalizationCopy.warnings(n);
    final trend = switch (n.outcome) {
      BaseNormalizationOutcome.upward => FinTrend.positive,
      BaseNormalizationOutcome.downward => FinTrend.negative,
      BaseNormalizationOutcome.healthLocked ||
      BaseNormalizationOutcome.rebuilt =>
        FinTrend.caution,
      _ => FinTrend.neutral,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `Material` transparente: o respingo do toque precisa de um
          // `Material` acima, e o `GlassCard` interpõe um fundo próprio.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(FinSpace.md),
                child: Row(
                  children: [
                    Icon(Icons.insights_outlined, size: 18, color: c.positive),
                    const Gap.sm(axis: Axis.horizontal),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            NormalizationCopy.question(n),
                            style: t.bodySm.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Gap.xs(),
                          _Badge(
                            text: NormalizationCopy.badge(n),
                            trend: trend,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: c.textSecondary,
                      semanticLabel: _open ? 'Recolher' : 'Expandir',
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FinSpace.md,
                0,
                FinSpace.md,
                FinSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    NormalizationCopy.answer(n),
                    style: t.bodySm.copyWith(color: c.textPrimary),
                  ),
                  const Gap.sm(),
                  Text(
                    NormalizationCopy.rule(n),
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                  if (n.cycleWindow.isNotEmpty && n.latestReturn != null) ...[
                    const Gap.md(),
                    _CycleBars(n: n),
                  ],
                  if (test != null) ...[
                    const Gap.md(),
                    Text(test, style: t.caption.copyWith(color: c.textPrimary)),
                  ],
                  if (account != null) ...[
                    const Gap.sm(),
                    Text(account, style: t.caption.copyWith(color: c.textPrimary)),
                  ],
                  for (final warning in warnings) ...[
                    const Gap.sm(),
                    NoticeBanner(message: warning),
                  ],
                  const Gap.sm(),
                  Text(
                    'Discorda do motor? Digite o lucro que quiser no campo '
                    'acima — ou use o do último exercício.',
                    style: t.caption.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// O selo do resultado da normalização, na cor da direção.
class _Badge extends StatelessWidget {
  final String text;
  final FinTrend trend;

  const _Badge({required this.text, required this.trend});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final color = c.forTrend(trend);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.sm,
        vertical: FinSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceForTrend(trend),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: context.finType.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Os anos que formam o retorno típico, e o último exercício, em barras com o
/// típico marcado.
///
/// Uma fila por ano, e não um gráfico de colunas: a fila aguenta 320 dp sob
/// fonte ampliada sem cortar rótulo, e cada ano diz o próprio número.
class _CycleBars extends StatelessWidget {
  final BaseNormalization n;

  const _CycleBars({required this.n});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final typical = n.cycleReturn;
    final last = n.latestReturn!;
    final values = [
      for (final p in n.cycleWindow) p.value,
      last,
      ?typical,
    ];
    // As colunas de rótulo crescem com a fonte: em 2,0x, `2024` e `13,2%` não
    // cabem nas larguras de 1,0x.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final lo = values.fold(0.0, (a, b) => a < b ? a : b);
    final hi = values.fold(lo + 1e-9, (a, b) => a > b ? a : b) * 1.08;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    Widget tableRow(String label, double value, {required bool highlight}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: FinSpace.xs),
        child: Row(
          children: [
            SizedBox(
              width: 40 * scale,
              child: Text(
                label,
                style: (highlight ? t.captionNum.copyWith(
                  fontWeight: FontWeight.w700,
                ) : t.captionNum).copyWith(
                  color: highlight ? c.textPrimary : c.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, k) {
                  final w = k.maxWidth;
                  final zero = pos(0) * w;
                  final tip = pos(value) * w;
                  final left = zero < tip ? zero : tip;
                  final width = (tip - zero).abs().clamp(2.0, w);
                  return SizedBox(
                    height: 14,
                    child: Stack(
                      children: [
                        Positioned(
                          left: left,
                          width: width,
                          top: 2,
                          bottom: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: highlight
                                  ? c.brand
                                  : value < 0
                                      ? c.negative.withValues(alpha: 0.6)
                                      : c.borderStrong,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if (typical != null)
                          Positioned(
                            left: (pos(typical) * w - 1).clamp(0.0, w - 2),
                            width: 2,
                            top: 0,
                            bottom: 0,
                            child: ColoredBox(color: c.positive),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Gap.sm(axis: Axis.horizontal),
            SizedBox(
              width: 52 * scale,
              child: Text(
                Fmt.percent(value, decimals: 1),
                textAlign: TextAlign.right,
                style: t.captionNum.copyWith(
                  color: highlight ? c.textPrimary : c.textSecondary,
                  fontWeight: highlight ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final returnName = NormalizationCopy.returnRate(n.lane);
    return Semantics(
      label: 'O $returnName de cada ano: '
          '${[for (final p in n.cycleWindow) '${p.year}, ${Fmt.percent(p.value, decimals: 1)}'].join('; ')}; '
          'último exercício, ${n.latestYear}, ${Fmt.percent(last, decimals: 1)}; '
          'típico, ${typical == null ? 'sem medida' : Fmt.percent(typical, decimals: 1)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${returnName[0].toUpperCase()}${returnName.substring(1)}, ano '
              'a ano',
              style: t.caption.copyWith(color: c.textSecondary),
            ),
            const Gap.xs(),
            for (final p in n.cycleWindow)
              tableRow('${p.year}', p.value, highlight: false),
            const Gap.xs(),
            tableRow('${n.latestYear}', last, highlight: true),
            const Gap.xs(),
            Wrap(
              spacing: FinSpace.md,
              runSpacing: FinSpace.xxs,
              children: [
                _Legend(color: c.borderStrong, text: 'anos do ciclo'),
                _Legend(color: c.brand, text: 'último exercício'),
                if (typical != null)
                  _Legend(
                    color: c.positive,
                    text: 'típico (mediana): ${Fmt.percent(typical, decimals: 1)}',
                    row: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  final bool row;

  const _Legend({required this.color, required this.text, this.row = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: row ? 2 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(row ? 0 : 2),
            ),
          ),
          const Gap.xs(axis: Axis.horizontal),
          Flexible(
            child: Text(
              text,
              style: context.finType.caption.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ),
        ],
      );
}
