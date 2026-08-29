import 'package:flutter/material.dart';

import '../theme/fin_colors.dart';
import '../theme/fin_theme.dart';

/// Exibe um valor financeiro ja formatado.
///
/// Unico ponto da interface autorizado a pintar dinheiro, percentual ou razao
/// **em celula ou slot de metrica**. Concentra quatro decisoes que se erram uma
/// vez por tela quando ficam espalhadas: cifras tabulares, cor por
/// significado, mascara de privacidade e a leitura para o leitor de tela.
///
/// Numero embutido em frase -- `'aportado R$ 40.000'`, `'CDI 10,5% a.a.'` --
/// **nao** passa por aqui: cifra tabular existe para alinhar coluna, e dentro
/// de um paragrafo ela nao tem o que alinhar. Esses casos seguem como
/// interpolacao de `Fmt` dentro de um `Text` comum.
///
/// [text] chega **pronto**. Use `Fmt.money` / `Fmt.percent` / `Fmt.ratio`:
/// manter a decisao de unidade e de casas decimais no ponto de uso e
/// deliberado, porque so quem chama sabe se o numero esta em reais ou em
/// centavos.
class FinAmount extends StatelessWidget {
  /// Valor ja formatado.
  final String text;

  /// Deve vir da familia `num*` de `FinTypography` -- e ela que carrega
  /// `FontFeature.tabularFigures`.
  final TextStyle style;

  /// Direcao, que escolhe a cor.
  final FinTrend trend;

  /// Oculta o valor preservando a largura da caixa.
  ///
  /// A troca e animada porque um valor que aparece sem transicao parece outro
  /// valor, e nao o mesmo revelado.
  final bool masked;

  /// Leitura para o leitor de tela.
  ///
  /// Sob mascara o texto visivel e `••••••`, que nao se le em voz alta -- sem
  /// isto a tela fica muda para quem depende dele.
  final String? semanticsLabel;

  /// Alinhamento. Padrao a direita, que e como coluna de numero se le.
  final TextAlign align;

  /// Declara o valor.
  const FinAmount({
    super.key,
    required this.text,
    required this.style,
    this.trend = FinTrend.neutral,
    this.masked = false,
    this.semanticsLabel,
    this.align = TextAlign.right,
  });

  /// Escolhe a direcao a partir do numero, com zero em neutro.
  ///
  /// Zero **nao** e ganho. Pintar de verde uma variacao nula diz ao investidor
  /// que houve alta onde nao houve nada.
  ///
  /// Valor nulo ou nao finito vira [FinTrend.blocked], pelo mesmo motivo que
  /// `Fmt.percent` devolve travessao: admitir a ausencia do dado e melhor que
  /// exibir `NaN` colorido de verde.
  static FinTrend trendOf(num? value) {
    if (value == null) return FinTrend.blocked;
    if (value is double && !value.isFinite) return FinTrend.blocked;
    if (value > 0) return FinTrend.positive;
    if (value < 0) return FinTrend.negative;
    return FinTrend.neutral;
  }

  /// Largura que [sample] ocupa em [style] sob a escala de texto corrente.
  ///
  /// Substitui a largura de coluna declarada em constante. A coluna passa a
  /// ser dimensionada pelo maior valor que pode conter, medido na escala que o
  /// usuario escolheu: alinha em 1,0x e continua alinhando em 2,0x, onde uma
  /// largura fixa truncaria.
  ///
  /// Usa `maxIntrinsicWidth`, e NAO `width`. A diferenca e o defeito inteiro:
  /// `TextPainter.width` devolve a largura da linha depois do layout, que ja
  /// vem arredondada para baixo, enquanto `maxIntrinsicWidth` e a largura que
  /// o texto realmente pede para nao quebrar. Medido neste repositorio para
  /// `-1.234,5%` em `numSm`: `width` da 117,0 e a intrinseca e 119,25 -- uma
  /// coluna dimensionada pelo primeiro trunca o proprio valor que a mediu.
  ///
  /// O `ceil` fecha a fracao restante: largura de caixa e comparada com
  /// tolerancia de ponto flutuante, e sobrar um pixel custa menos que truncar
  /// um numero.
  static double measure(BuildContext context, String sample, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: resolveStyle(context, style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textWidthBasis: TextWidthBasis.parent,
      maxLines: 1,
    )..layout();
    final width = painter.maxIntrinsicWidth;
    painter.dispose();
    return width.ceilToDouble();
  }

  /// O estilo com que o widget [Text] REALMENTE pinta [style] neste contexto.
  ///
  /// Existe porque medir o estilo cru mente. `Text` nao usa o estilo recebido
  /// como veio: quando `inherit` e `true` -- o padrao -- ele o mescla sobre o
  /// `DefaultTextStyle` ambiente, e depois aplica negrito de acessibilidade se
  /// o sistema pedir. Uma medida que ignore os dois passos devolve menos que a
  /// largura pintada, e a coluna dimensionada por ela trunca.
  ///
  /// Medido neste repositorio: para `-1.234,5%` em `numSm`, o estilo cru media
  /// 117 px e o pintado ocupava 119,25 -- 2,25 px de diferenca, suficiente
  /// para comer um digito.
  static TextStyle resolveStyle(BuildContext context, TextStyle style) {
    var effective = style;
    if (style.inherit) {
      effective = DefaultTextStyle.of(context).style.merge(style);
    }
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return effective;
  }

  /// Texto exibido sob mascara.
  static const String maskedText = '••••••';

  @override
  Widget build(BuildContext context) {
    final resolved = style.copyWith(color: context.fin.forTrend(trend));

    return Semantics(
      label: semanticsLabel ?? (masked ? 'Valor oculto' : null),
      excludeSemantics: semanticsLabel != null || masked,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Text(
          masked ? maskedText : text,
          key: ValueKey<String>(masked ? '#masked' : text),
          textAlign: align,
          maxLines: 1,
          // Reticencias como REDE DE SEGURANCA, nao como solucao.
          //
          // A solucao e medir a coluna com `measure`, e onde isso e feito o
          // overflow nunca ocorre. Mas onde a largura ainda e constante -- e
          // ha lugares assim ate a coluna medida chegar a todas as listas --
          // o padrao `TextOverflow.clip` corta o numero SEM marca nenhuma:
          // dentro de um `SizedBox` nao aparece a listra amarela, que so
          // surge quando um `RenderFlex` estoura. O usuario le "1.2" no lugar
          // de "1.234%" e nao tem como saber que falta digito.
          //
          // Numero truncado que PARECE completo e pior que numero visivelmente
          // truncado: as reticencias ao menos dizem que ha mais ali.
          overflow: TextOverflow.ellipsis,
          style: resolved,
        ),
      ),
    );
  }
}
