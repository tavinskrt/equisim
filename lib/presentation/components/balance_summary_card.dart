import 'package:flutter/material.dart';

import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'fin_amount.dart';

/// Uma metrica secundaria do cartao.
@immutable
class BalanceMetric {
  /// Nome curto. Renderizado em caixa alta pelo widget; passe na grafia normal.
  final String label;

  /// Valor **ja formatado** por `Fmt`.
  final String value;

  /// Base de calculo ou ressalva. Vai em `textTertiary`, que e AA e portanto
  /// restrito a informacao que nao altera decisao.
  final String? hint;

  /// Direcao, para a cor semantica.
  final FinTrend trend;

  /// Se o valor some sob a mascara de privacidade.
  ///
  /// Um indice de Sharpe nao revela patrimonio; um "aportado R$ 40.000"
  /// revela. Marcar por metrica evita esconder o que nao precisa ser escondido.
  final bool sensitive;

  /// Declara a metrica.
  const BalanceMetric({
    required this.label,
    required this.value,
    this.hint,
    this.trend = FinTrend.neutral,
    this.sensitive = false,
  });
}

/// Cartao de grandeza principal com metricas de apoio.
///
/// Tres grandezas em tres pesos, e a hierarquia e a mensagem: o valor domina,
/// a variacao o qualifica, as metricas o explicam.
///
/// Substitui o arranjo anterior, em que dez metricas dividiam o mesmo
/// `fontSize` dentro de um `Wrap` -- patrimonio final e indice de Calmar com o
/// mesmo peso, obrigando o leitor a procurar o numero que importa. Pior: o
/// `Wrap` alinhava por largura intrinseca, entao "R$ 1.234.567,89" e "0,84"
/// ocupavam espacos diferentes e as linhas nao batiam entre si.
class BalanceSummaryCard extends StatelessWidget {
  /// Rotulo do cartao.
  final String label;

  /// Grandeza principal, ja formatada.
  final String balance;

  /// Leitura da grandeza principal para leitor de tela, sem abreviacao.
  final String balanceSemantics;

  /// Nota sob a grandeza principal: base, janela, aporte acumulado.
  final String? caption;

  /// Variacao do periodo, ja formatada, e a direcao dela.
  final String? changeLabel;
  final FinTrend changeTrend;

  /// Metricas de apoio.
  final List<BalanceMetric> metrics;

  /// Oculta a grandeza principal e as metricas marcadas como sensiveis.
  final bool masked;

  /// Alterna a mascara. Sem ele, o botao nao aparece.
  final VoidCallback? onToggleMask;

  /// Acao do canto superior direito -- tipicamente o glossario.
  final Widget? trailing;

  /// Declara o cartao.
  const BalanceSummaryCard({
    super.key,
    required this.label,
    required this.balance,
    required this.balanceSemantics,
    this.caption,
    this.changeLabel,
    this.changeTrend = FinTrend.neutral,
    this.metrics = const <BalanceMetric>[],
    this.masked = false,
    this.onToggleMask,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          label: label,
          masked: masked,
          onToggleMask: onToggleMask,
          trailing: trailing,
        ),
        const Gap.md(),

        // A grandeza principal e o unico elemento que muda a cada recalculo.
        // Isolada, ela repinta sozinha em vez de arrastar o cartao inteiro.
        RepaintBoundary(
          child: FinAmount(
            text: balance,
            style: t.numLg,
            masked: masked,
            semanticsLabel: masked ? 'Valor oculto' : balanceSemantics,
            align: TextAlign.left,
          ),
        ),

        if (changeLabel != null) ...[
          const Gap.sm(),
          _ChangePill(text: changeLabel!, trend: changeTrend),
        ],

        if (caption != null) ...[
          const Gap.sm(),
          Text(
            caption!,
            style: t.caption.copyWith(color: c.textTertiary),
          ),
        ],

        if (metrics.isNotEmpty) ...[
          const Gap.lg(),
          Divider(height: 1, thickness: 1, color: c.divider),
          const Gap.lg(),
          _MetricGrid(metrics: metrics, masked: masked),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String label;
  final bool masked;
  final VoidCallback? onToggleMask;
  final Widget? trailing;

  const _Header({
    required this.label,
    required this.masked,
    this.onToggleMask,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: context.finType.label.copyWith(color: c.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onToggleMask != null)
          IconButton(
            onPressed: onToggleMask,
            tooltip: masked ? 'Mostrar valores' : 'Ocultar valores',
            // 48 dp explicitos: este botao e tocado em publico, as pressas.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            icon: Icon(
              masked ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: c.textSecondary,
            ),
          ),
        ?trailing,
      ],
    );
  }
}

/// Variacao do periodo, em pastilha da cor do estado.
///
/// A pastilha existe porque cor sozinha nao e informacao acessivel: o fundo
/// tonal e a seta dao dois canais alem do matiz, o que mantem a leitura para
/// daltonismo de eixo vermelho-verde -- o mais comum, e exatamente o eixo em
/// que lucro e perda se opoem nesta interface.
class _ChangePill extends StatelessWidget {
  final String text;
  final FinTrend trend;

  const _ChangePill({required this.text, required this.trend});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    final icon = switch (trend) {
      FinTrend.positive => Icons.arrow_upward_rounded,
      FinTrend.negative => Icons.arrow_downward_rounded,
      FinTrend.caution => Icons.warning_amber_rounded,
      FinTrend.pending => Icons.schedule_rounded,
      FinTrend.blocked => Icons.remove_rounded,
      FinTrend.neutral => Icons.horizontal_rule_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.sm,
        // `xxs` e nao `xs`: com 4 dp a pastilha fica alta demais em relacao ao
        // texto que ela envolve. E o caso de ajuste optico para o qual o meio
        // passo existe.
        vertical: FinSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceForTrend(trend),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.forTrend(trend)),
          const Gap.xs(axis: Axis.horizontal),
          // `Flexible`: sob 2,0x o texto cresce e a pastilha precisa ceder em
          // vez de estourar a linha.
          Flexible(
            child: FinAmount(
              text: text,
              style: context.finType.numMd,
              trend: trend,
              align: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grade cujo numero de colunas vem da largura disponivel **e** da escala de
/// texto do usuario.
///
/// A largura de cada celula e CALCULADA, nao intrinseca: e o que faz as
/// colunas baterem de uma linha para a outra. Um `Wrap` comum deixa cada item
/// com a largura do proprio conteudo, e a grade se desmancha.
class _MetricGrid extends StatelessWidget {
  final List<BalanceMetric> metrics;
  final bool masked;

  const _MetricGrid({required this.metrics, required this.masked});

  /// Largura minima confortavel de uma celula, sob a escala corrente.
  ///
  /// Medida do conteudo REAL: o maior valor e o maior rotulo desta grade. Uma
  /// amostra chutada erraria nos dois sentidos -- sobraria espaco numa tela de
  /// razoes curtas e faltaria numa de patrimonio de sete digitos.
  double _cellWidth(BuildContext context) {
    final t = context.finType;
    var largest = 0.0;

    for (final m in metrics) {
      final value = FinAmount.measure(context, m.value, t.numMd);
      if (value > largest) largest = value;

      final label = FinAmount.measure(
        context,
        m.label.toUpperCase(),
        t.label,
      );
      if (label > largest) largest = label;
    }

    return largest + FinSpace.sm;
  }

  @override
  Widget build(BuildContext context) {
    final cell = _cellWidth(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        // O `clamp` inferior em 1 e o que impede a divisao por zero quando a
        // celula medida e mais larga que a tela -- caso real em 320 dp sob
        // 2,0x, onde um patrimonio de sete digitos nao cabe em coluna alguma.
        final columns = ((available + FinSpace.xl) / (cell + FinSpace.xl))
            .floor()
            .clamp(1, 4);

        final itemWidth =
            (available - FinSpace.xl * (columns - 1)) / columns;

        return Wrap(
          spacing: FinSpace.xl,
          runSpacing: FinSpace.lg,
          children: [
            for (final m in metrics)
              SizedBox(
                width: itemWidth,
                child: _MetricCell(metric: m, masked: masked && m.sensitive),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  final BalanceMetric metric;
  final bool masked;

  const _MetricCell({required this.metric, required this.masked});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          metric.label.toUpperCase(),
          style: t.label.copyWith(color: c.textSecondary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const Gap.xs(),
        FinAmount(
          text: metric.value,
          style: t.numMd,
          trend: metric.trend,
          masked: masked,
          align: TextAlign.left,
        ),
        if (metric.hint != null) ...[
          const Gap.xs(),
          Text(
            metric.hint!,
            style: t.caption.copyWith(color: c.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
