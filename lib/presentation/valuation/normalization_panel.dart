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
  late bool _aberto;

  @override
  void initState() {
    super.initState();
    _aberto = switch (widget.normalization.outcome) {
      BaseNormalizationOutcome.paraCima ||
      BaseNormalizationOutcome.paraBaixo ||
      BaseNormalizationOutcome.reconstruida =>
        true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final n = widget.normalization;
    final teste = NormalizationCopy.teste(n);
    final conta = NormalizationCopy.conta(n);
    final avisos = NormalizationCopy.avisos(n);
    final tendencia = switch (n.outcome) {
      BaseNormalizationOutcome.paraCima => FinTrend.positive,
      BaseNormalizationOutcome.paraBaixo => FinTrend.negative,
      BaseNormalizationOutcome.travadaPelaSaude ||
      BaseNormalizationOutcome.reconstruida =>
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
              onTap: () => setState(() => _aberto = !_aberto),
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
                            NormalizationCopy.pergunta(n),
                            style: t.bodySm.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Gap.xs(),
                          _Selo(
                            texto: NormalizationCopy.selo(n),
                            tendencia: tendencia,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _aberto ? Icons.expand_less : Icons.expand_more,
                      color: c.textSecondary,
                      semanticLabel: _aberto ? 'Recolher' : 'Expandir',
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_aberto)
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
                    NormalizationCopy.resposta(n),
                    style: t.bodySm.copyWith(color: c.textPrimary),
                  ),
                  const Gap.sm(),
                  Text(
                    NormalizationCopy.regra(n),
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                  if (n.cycleWindow.isNotEmpty && n.latestReturn != null) ...[
                    const Gap.md(),
                    _BarrasDoCiclo(n: n),
                  ],
                  if (teste != null) ...[
                    const Gap.md(),
                    Text(teste, style: t.caption.copyWith(color: c.textPrimary)),
                  ],
                  if (conta != null) ...[
                    const Gap.sm(),
                    Text(conta, style: t.caption.copyWith(color: c.textPrimary)),
                  ],
                  for (final aviso in avisos) ...[
                    const Gap.sm(),
                    NoticeBanner(message: aviso),
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
class _Selo extends StatelessWidget {
  final String texto;
  final FinTrend tendencia;

  const _Selo({required this.texto, required this.tendencia});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final cor = c.forTrend(tendencia);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.sm,
        vertical: FinSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceForTrend(tendencia),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        style: context.finType.caption.copyWith(
          color: cor,
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
class _BarrasDoCiclo extends StatelessWidget {
  final BaseNormalization n;

  const _BarrasDoCiclo({required this.n});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final tipico = n.cycleReturn;
    final ultimo = n.latestReturn!;
    final valores = [
      for (final p in n.cycleWindow) p.value,
      ultimo,
      ?tipico,
    ];
    // As colunas de rótulo crescem com a fonte: em 2,0x, `2024` e `13,2%` não
    // cabem nas larguras de 1,0x.
    final escala = MediaQuery.textScalerOf(context).scale(1);
    final lo = valores.fold(0.0, (a, b) => a < b ? a : b);
    final hi = valores.fold(lo + 1e-9, (a, b) => a > b ? a : b) * 1.08;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    Widget fila(String rotulo, double valor, {required bool destaque}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: FinSpace.xs),
        child: Row(
          children: [
            SizedBox(
              width: 40 * escala,
              child: Text(
                rotulo,
                style: (destaque ? t.captionNum.copyWith(
                  fontWeight: FontWeight.w700,
                ) : t.captionNum).copyWith(
                  color: destaque ? c.textPrimary : c.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, k) {
                  final w = k.maxWidth;
                  final zero = pos(0) * w;
                  final ponta = pos(valor) * w;
                  final esquerda = zero < ponta ? zero : ponta;
                  final largura = (ponta - zero).abs().clamp(2.0, w);
                  return SizedBox(
                    height: 14,
                    child: Stack(
                      children: [
                        Positioned(
                          left: esquerda,
                          width: largura,
                          top: 2,
                          bottom: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: destaque
                                  ? c.brand
                                  : valor < 0
                                      ? c.negative.withValues(alpha: 0.6)
                                      : c.borderStrong,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if (tipico != null)
                          Positioned(
                            left: (pos(tipico) * w - 1).clamp(0.0, w - 2),
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
              width: 52 * escala,
              child: Text(
                Fmt.percent(valor, decimals: 1),
                textAlign: TextAlign.right,
                style: t.captionNum.copyWith(
                  color: destaque ? c.textPrimary : c.textSecondary,
                  fontWeight: destaque ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final retornoNome = NormalizationCopy.retorno(n.lane);
    return Semantics(
      label: 'O $retornoNome de cada ano: '
          '${[for (final p in n.cycleWindow) '${p.year}, ${Fmt.percent(p.value, decimals: 1)}'].join('; ')}; '
          'último exercício, ${n.latestYear}, ${Fmt.percent(ultimo, decimals: 1)}; '
          'típico, ${tipico == null ? 'sem medida' : Fmt.percent(tipico, decimals: 1)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${retornoNome[0].toUpperCase()}${retornoNome.substring(1)}, ano '
              'a ano',
              style: t.caption.copyWith(color: c.textSecondary),
            ),
            const Gap.xs(),
            for (final p in n.cycleWindow)
              fila('${p.year}', p.value, destaque: false),
            const Gap.xs(),
            fila('${n.latestYear}', ultimo, destaque: true),
            const Gap.xs(),
            Wrap(
              spacing: FinSpace.md,
              runSpacing: FinSpace.xxs,
              children: [
                _Legenda(cor: c.borderStrong, texto: 'anos do ciclo'),
                _Legenda(cor: c.brand, texto: 'último exercício'),
                if (tipico != null)
                  _Legenda(
                    cor: c.positive,
                    texto: 'típico (mediana): ${Fmt.percent(tipico, decimals: 1)}',
                    linha: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  final Color cor;
  final String texto;
  final bool linha;

  const _Legenda({required this.cor, required this.texto, this.linha = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: linha ? 2 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(linha ? 0 : 2),
            ),
          ),
          const Gap.xs(axis: Axis.horizontal),
          Flexible(
            child: Text(
              texto,
              style: context.finType.caption.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ),
        ],
      );
}
