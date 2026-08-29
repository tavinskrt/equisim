import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/app_colors.dart';
import '../components/fin_amount.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_theme.dart';

/// Formatadores compartilhados.
abstract final class Fmt {
  /// Moeda em pt-BR por extenso: `R$ 1.234,56`.
  static final currency =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  /// Moeda abreviada: `R$ 1,2 mi`. Para eixo de gráfico e espaço estreito.
  static final compactCurrency =
      NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$');

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
  static String percent(double fraction, {int decimals = 2, bool signed = false}) {
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
/// O efeito de vidro depende de o fundo atrás ser o gradiente de
/// [ScreenBackground]: sobre cor chapada o desfoque não tem o que borrar.
class GlassCard extends StatelessWidget {
  /// Conteúdo do cartão.
  final Widget child;

  /// Espaçamento interno.
  final EdgeInsetsGeometry padding;

  /// Tema corrente. Recebido por parâmetro, não lido do contexto, para manter
  /// o kit testável fora de uma árvore de tema completa.
  final bool isLight;

  /// Contorno alternativo, para destacar estado. Sem ele, usa
  /// `AppColors.surfaceBorder`.
  final Color? borderColor;

  /// Declara o cartão.
  const GlassCard({
    super.key,
    required this.child,
    required this.isLight,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.surface(isLight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor ?? AppColors.surfaceBorder(isLight),
            ),
          ),
          child: child,
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

  /// Tema corrente.
  final bool isLight;

  /// Declara o cabeçalho.
  const SectionHeader({
    super.key,
    required this.title,
    required this.isLight,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary(isLight),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(isLight),
                  ),
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

  /// Tema corrente.
  final bool isLight;

  /// Declara o bloco de métrica.
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.isLight,
    this.hint,
    this.trend = FinTrend.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary(isLight),
          ),
        ),
        const SizedBox(height: 2),
        // O valor passa por `FinAmount`: é o que garante cifra tabular, de modo
        // que a vírgula decimal não dança de uma métrica para a outra.
        FinAmount(
          text: value,
          style: context.finType.numMd,
          trend: trend,
          align: TextAlign.left,
        ),
        if (hint != null) ...[
          const SizedBox(height: 1),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 9.5,
              color: AppColors.textMuted(isLight),
            ),
          ),
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

  /// Cor do ícone e do contorno. Segue a semântica de [AppColors]:
  /// `danger` para falha, `warning` para número que pede ressalva.
  final Color color;

  /// Tema corrente.
  final bool isLight;

  /// Declara a faixa de aviso.
  const NoticeBanner({
    super.key,
    required this.message,
    required this.isLight,
    this.icon = Icons.info_outline,
    this.color = const Color(0xFFF59E0B),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textPrimary(isLight),
              ),
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

  /// Tema corrente.
  final bool isLight;

  /// Declara o estado vazio.
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.isLight,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.textMuted(isLight)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(isLight),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary(isLight),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Fundo padrão das telas, com os círculos decorativos da identidade visual.
class ScreenBackground extends StatelessWidget {
  /// Conteúdo da tela.
  final Widget child;

  /// Tema corrente.
  final bool isLight;

  /// Declara o fundo. Envolva a tela inteira com ele: é o que dá a
  /// [GlassCard] algo para desfocar.
  const ScreenBackground({
    super.key,
    required this.child,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(gradient: AppColors.backgroundGradient(isLight)),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
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

  /// Tema corrente.
  final bool isLight;

  /// Declara o ícone de ajuda.
  const HintIcon({
    super.key,
    required this.title,
    required this.entries,
    required this.isLight,
    this.intro,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'O que significa cada indicador',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        Icons.help_outline,
        size: 17,
        color: AppColors.textSecondary(isLight),
      ),
      onPressed: () => _openGlossary(context),
    );
  }

  void _openGlossary(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: isLight ? Colors.white : const Color(0xFF0D1E3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.surfaceBorder(isLight)),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(isLight),
            ),
          ),
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
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary(isLight),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.term,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.description,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: AppColors.textSecondary(isLight),
                            ),
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
              child: const Text(
                'Entendi',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

