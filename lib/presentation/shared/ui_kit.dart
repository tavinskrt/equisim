import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/fin_amount.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';

/// Formatadores compartilhados.
abstract final class Fmt {
  /// Moeda em pt-BR por extenso: `R$ 1.234,56`.
  static final currency = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  /// Moeda abreviada: `R$ 1,2 mi`. Para eixo de gráfico e espaço estreito.
  static final compactCurrency = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  /// Data por extenso: `31/12/2026`.
  static final date = DateFormat('dd/MM/yyyy');

  /// Data curta para eixo temporal: `12/26`.
  static final shortDate = DateFormat('MM/yy');

  /// Formata um valor **em reais** — não em centavos.
  ///
  /// Converta com `Money.reais` antes de chamar; passar centavos produz um
  /// número cem vezes maior sem qualquer aviso.
  static String money(double value) => currency.format(value);

  /// Formatadores decimais em pt-BR, um por número de casas.
  ///
  /// Existe porque `toStringAsFixed` **ignora locale**: ele sempre emite ponto
  /// como separador decimal, mesmo com o `intl` configurado em pt_BR. Isso
  /// produzia `14.41%` onde a convenção brasileira pede `14,41%` — defeito que
  /// aparecia em todas as telas de métricas.
  ///
  /// O cache evita reconstruir o formatador a cada quadro: estes métodos são
  /// chamados de dentro de `build`.
  static final Map<int, NumberFormat> _decimals = {};

  static NumberFormat _decimalFormat(int digits) => _decimals.putIfAbsent(
    digits,
    () => NumberFormat.decimalPatternDigits(
      locale: 'pt_BR',
      decimalDigits: digits,
    ),
  );

  /// Percentual a partir de fração, com sinal explícito quando pedido.
  ///
  /// - [fraction]: valor em fração (`0.155` vira `15,50%`).
  /// - [decimals]: casas decimais. Padrão `2`.
  /// - [signed]: prefixa `+` nos positivos. Negativos já trazem o próprio
  ///   sinal; o zero nunca recebe prefixo.
  ///
  /// Valor não finito vira `—`: `NumberFormat` não lança nesse caso, ele
  /// devolve `NaN` ou `∞`, e exibir isso ao investidor é pior que admitir a
  /// ausência do dado.
  static String percent(
    double fraction, {
    int decimals = 2,
    bool signed = false,
  }) {
    final value = fraction * 100;
    if (!value.isFinite) return '—';
    final sign = signed && value > 0 ? '+' : '';
    return '$sign${_decimalFormat(decimals).format(value)}%';
  }

  /// Número adimensional — múltiplo, beta, índice de Sharpe.
  static String ratio(double value, {int decimals = 2}) =>
      value.isFinite ? _decimalFormat(decimals).format(value) : '—';
}

/// Cartão translúcido — a linguagem visual herdada do projeto anterior.
///
/// O efeito de vidro depende de haver variação atrás: sobre cor perfeitamente
/// chapada o desfoque não tem o que borrar. É [ScreenBackground] que fornece
/// essa variação.
class GlassCard extends StatelessWidget {
  /// Conteúdo do cartão.
  final Widget child;

  /// Espaçamento interno.
  final EdgeInsetsGeometry padding;

  /// Contorno alternativo, para destacar estado. Sem ele, usa a borda padrão
  /// da paleta.
  final Color? borderColor;

  /// Declara o cartão.
  const GlassCard({
    super.key,
    required this.child,
    this.padding = FinSpace.cardPadding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    // `RepaintBoundary` aqui, e nao no ponto de uso, porque a garantia precisa
    // ser LOCAL ao componente.
    //
    // `ListView` ja envolve os filhos DIRETOS em fronteira de repintura
    // (`addRepaintBoundaries` e `true` por padrao), mas um cartao aninhado --
    // como os de dentro de `_ComparisonBody`, na tela de backtest -- fica sob
    // a fronteira do irmao mais externo e repinta junto com ele. Sem isto,
    // rolar a tela reprocessa o desfoque de seis ou sete cartoes por quadro,
    // e o alvo web deste projeto e onde mais custa.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor ?? c.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Título de seção com ação opcional à direita.
class SectionHeader extends StatelessWidget {
  /// Título da seção. É renderizado em **caixa alta** pelo widget; passe-o na
  /// grafia normal.
  final String title;

  /// Linha de apoio sob o título.
  final String? subtitle;

  /// Widget alinhado à direita — tipicamente um botão ou um [HintIcon].
  final Widget? trailing;

  /// Declara o cabeçalho.
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: t.label.copyWith(color: c.textSecondary),
              ),
              if (subtitle != null) ...[
                const Gap.xs(),
                Text(
                  subtitle!,
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Métrica destacada: rótulo, valor e explicação curta.
class MetricTile extends StatelessWidget {
  /// Nome da métrica.
  final String label;

  /// Valor **já formatado**. Use [Fmt] — o widget não formata nada, o que
  /// mantém a decisão de unidade e casas decimais no ponto de uso.
  final String value;

  /// Nota de rodapé: base de cálculo, janela, ressalva.
  final String? hint;

  /// Direção da grandeza, que escolhe a cor do valor.
  ///
  /// Substituiu o antigo `valueColor: Color?`, que obrigava cada ponto de uso
  /// a resolver a cor por conta própria — e era por onde `AppColors.primary`,
  /// reprovado em contraste, chegava a todo número positivo da interface.
  final FinTrend trend;

  /// Declara o bloco de métrica.
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.trend = FinTrend.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.caption.copyWith(color: c.textSecondary)),
        const Gap.xs(),
        // O valor passa por `FinAmount`: é o que garante cifra tabular, de modo
        // que a vírgula decimal não dança de uma métrica para a outra.
        FinAmount(
          text: value,
          style: t.numMd,
          trend: trend,
          align: TextAlign.left,
        ),
        if (hint != null) ...[
          const Gap.xs(),
          Text(hint!, style: t.caption.copyWith(color: c.textTertiary)),
        ],
      ],
    );
  }
}

/// Faixa de aviso não bloqueante.
///
/// Usada para concentração setorial e para a queda de modelo de avaliação:
/// informa sem impedir, porque as duas situações podem ser decisões
/// conscientes do investidor.
class NoticeBanner extends StatelessWidget {
  /// Texto do aviso, já formulado para o usuário final.
  final String message;

  /// Ícone à esquerda.
  final IconData icon;

  /// Direção do aviso, que escolhe a cor e o fundo tonal.
  ///
  /// Substituiu o antigo `color: Color`, cujo valor-padrão era um âmbar
  /// (`#F59E0B`) que a paleta não conhecia — nem `warning` nem `warningDark`.
  /// Era um literal que ninguém podia corrigir de um lugar só.
  final FinTrend trend;

  /// Declara a faixa de aviso.
  const NoticeBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.trend = FinTrend.caution,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final accent = c.forTrend(trend);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.md,
        vertical: FinSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceForTrend(trend),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: accent),
          const Gap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: context.finType.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio com orientação do próximo passo.
class EmptyState extends StatelessWidget {
  /// Ícone ilustrativo.
  final IconData icon;

  /// Título curto do estado vazio.
  final String title;

  /// Explicação do que falta e de como preencher.
  final String message;

  /// Ação sugerida — o botão que resolve o vazio.
  final Widget? action;

  /// Declara o estado vazio.
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FinSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: c.textTertiary),
            const Gap.md(),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.titleSm.copyWith(color: c.textPrimary),
            ),
            const Gap.sm(),
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.bodyMd.copyWith(color: c.textSecondary),
            ),
            if (action != null) ...[const Gap.lg(), action!],
          ],
        ),
      ),
    );
  }
}

/// Fundo padrão das telas, com os círculos decorativos da identidade visual.
///
/// O degradê agora percorre `canvas -> surfaceSunken -> canvas`, e não mais o
/// azul-marinho ao verde-petróleo da paleta anterior. É uma atenuação
/// deliberada: os dois tons já passam pelo teste de contraste, o que o par
/// antigo não garantia, e o resultado é a variação mínima de que o
/// [GlassCard] precisa para ter o que desfocar — sem o degradê competir com os
/// números.
class ScreenBackground extends StatelessWidget {
  /// Conteúdo da tela.
  final Widget child;

  /// Declara o fundo. Envolva a tela inteira com ele.
  const ScreenBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.canvas, c.surfaceSunken, c.canvas],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Os dois círculos não mudam com a rolagem nem com o conteúdo. Sem a
          // fronteira, eles repintam a cada quadro junto com a lista.
          RepaintBoundary(
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned(
                    top: -100,
                    right: -60,
                    child: _Halo(color: c.brand.withValues(alpha: 0.07)),
                  ),
                  Positioned(
                    bottom: -40,
                    left: -80,
                    child: _Halo(
                      size: 220,
                      color: c.brand.withValues(alpha: 0.05),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Círculo decorativo do fundo.
class _Halo extends StatelessWidget {
  final double size;
  final Color color;

  const _Halo({this.size = 260, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// Verbete de glossário: o rótulo tal como aparece no cartão e o que ele diz.
class HintEntry {
  /// Termo explicado — o jargão como aparece na tela.
  final String term;

  /// Definição em linguagem corrente.
  final String description;

  /// Declara o verbete.
  const HintEntry(this.term, this.description);
}

/// Ícone de ajuda que abre o glossário dos indicadores de um cartão.
///
/// Os números destas telas decidem troca de ativo, e cada um responde a uma
/// pergunta diferente: TWR compara composições, XIRR mede o que o investidor
/// levou. Ler um pelo outro leva à decisão errada, e o verbete a um toque de
/// distância custa menos que a nota de rodapé que ninguém lê.
class HintIcon extends StatelessWidget {
  /// Título do painel de ajuda.
  final String title;

  /// Frase de abertura, quando o conjunto de verbetes precisa de contexto.
  final String? intro;

  /// Verbetes exibidos, na ordem em que aparecem.
  final List<HintEntry> entries;

  /// Declara o ícone de ajuda.
  const HintIcon({
    super.key,
    required this.title,
    required this.entries,
    this.intro,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'O que significa cada indicador',
      // 48 dp explícitos: `VisualDensity.compact` encolheria o alvo para 40.
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.help_outline,
        size: 17,
        color: context.fin.textSecondary,
      ),
      onPressed: () => _openGlossary(context),
    );
  }

  void _openGlossary(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: c.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.border),
          ),
          title: Text(title, style: t.titleSm.copyWith(color: c.textPrimary)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (intro != null) ...[
                    Text(
                      intro!,
                      style: t.bodySm.copyWith(color: c.textSecondary),
                    ),
                    const Gap.md(),
                  ],
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FinSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.term,
                            // `positive` e não `brand`: este é texto, e a cor
                            // de marca não tem contraste garantido para texto.
                            style: t.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.positive,
                            ),
                          ),
                          const Gap.xs(),
                          Text(
                            entry.description,
                            style: t.caption.copyWith(color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Entendi',
                style: t.bodyMd.copyWith(color: c.positive),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
