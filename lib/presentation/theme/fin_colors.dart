import 'package:flutter/material.dart';

/// Direcao de uma grandeza financeira.
///
/// Existe para que a cor seja escolhida por significado, e nao por um
/// `value > 0 ? verde : vermelho` reescrito em cada tela. Substitui a funcao
/// global `signedColor(double, bool)` do kit antigo.
enum FinTrend { positive, negative, neutral, caution, pending, blocked }

/// Registro dos tokens que PINTAM TEXTO.
///
/// Serve a um proposito unico e importante: o `switch` sobre este enum e
/// exaustivo, entao acrescentar um valor aqui **quebra a compilacao** de
/// [FinColors.ink] e do mapa de pisos no teste de contraste ate que os dois
/// sejam atualizados. E o mecanismo que impede uma cor de texto nova de entrar
/// sem medicao -- o defeito que colocou o verde de lucro em 2,71:1 sobre
/// branco na paleta anterior.
///
/// Cor de MARCA e de SUPERFICIE nao entra aqui: ela nao carrega texto.
enum FinInkToken {
  textPrimary,
  textSecondary,
  textTertiary,
  positive,
  negative,
  caution,
  pending,
  blocked,
}

/// Paleta do produto, exposta como extensao de tema.
///
/// **Duas familias, com regras distintas.** Superficie e texto mudam com o
/// tema; marca e estado financeiro carregam significado -- lucro, perda,
/// ressalva -- e nao podem inverter junto com o fundo.
///
/// A separacao que a paleta anterior nao tinha: `brand` e `positive` sao
/// tokens DISTINTOS, ainda que da mesma familia cromatica. Antes eram a mesma
/// constante, o que impedia afinar o contraste do lucro sem mexer na
/// identidade visual.
@immutable
class FinColors extends ThemeExtension<FinColors> {
  // --- Superficies ---

  /// Fundo da tela.
  final Color canvas;

  /// Fundo de cartao.
  final Color surface;

  /// Superficie acima do cartao: menu, dialogo, item em arrasto.
  final Color surfaceRaised;

  /// Superficie rebaixada: cabecalho de tabela, campo, barra de esqueleto.
  final Color surfaceSunken;

  /// Contorno de cartao e de campo.
  final Color border;

  /// Contorno de enfase, um degrau acima de [border].
  final Color borderStrong;

  /// Linha divisoria. O menor contraste da paleta: separa sem competir.
  final Color divider;

  // --- Texto ---

  /// Leitura principal: titulos e valores.
  final Color textPrimary;

  /// Apoio: rotulos, unidades, cabecalho de coluna.
  final Color textSecondary;

  /// Metadado que NAO altera decisao: data de referencia, base de calculo,
  /// nome do modelo.
  ///
  /// E o unico token de texto que fica em AA e nao em AAA. A restricao de uso
  /// e o que torna isso aceitavel: valor monetario, percentual e estado nunca
  /// usam este token.
  final Color textTertiary;

  /// Texto sobre preenchimento de marca.
  final Color textOnBrand;

  // --- Estado financeiro ---

  /// Ganho, potencial acima de zero.
  final Color positive;

  /// Perda, drawdown.
  final Color negative;

  /// O numero existe, mas nao deve ser lido como precisao.
  ///
  /// Separado de [negative] de proposito: vermelho ja significa perda nesta
  /// interface, e pintar de vermelho um upside de +447% diria a coisa errada.
  final Color caution;

  /// Liquidando, aguardando cotacao.
  final Color pending;

  /// Bloqueado, ou dado ausente.
  final Color blocked;

  /// Fundo tonal de [positive]. Da um segundo canal alem do matiz.
  final Color positiveSurface;

  /// Fundo tonal de [negative].
  final Color negativeSurface;

  /// Fundo tonal de [caution].
  final Color cautionSurface;

  /// Fundo tonal de [pending].
  final Color pendingSurface;

  // --- Marca ---

  /// Verde da identidade. **Preenchimento e icone apenas.**
  ///
  /// Contraste como texto NAO e garantido, e por isso ele nao aparece em
  /// [FinInkToken]. Para numero positivo use [positive].
  final Color brand;

  /// Fundo tonal da marca.
  final Color brandSurface;

  /// Declara a paleta.
  const FinColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnBrand,
    required this.positive,
    required this.negative,
    required this.caution,
    required this.pending,
    required this.blocked,
    required this.positiveSurface,
    required this.negativeSurface,
    required this.cautionSurface,
    required this.pendingSurface,
    required this.brand,
    required this.brandSurface,
  });

  /// Resolve um token de tinta.
  ///
  /// O `switch` e exaustivo: token novo em [FinInkToken] nao compila ate ser
  /// resolvido aqui.
  Color ink(FinInkToken token) => switch (token) {
        FinInkToken.textPrimary => textPrimary,
        FinInkToken.textSecondary => textSecondary,
        FinInkToken.textTertiary => textTertiary,
        FinInkToken.positive => positive,
        FinInkToken.negative => negative,
        FinInkToken.caution => caution,
        FinInkToken.pending => pending,
        FinInkToken.blocked => blocked,
      };

  /// Toda superficie sobre a qual [token] pode ser pintado.
  ///
  /// O teste de contraste itera esta lista, e nao um fundo unico. Medir so
  /// contra branco esconde o caso real: sobre [surfaceSunken] a razao cai
  /// cerca de 12%, e foi assim que a paleta anterior passou a impressao de
  /// estar em AAA quando nao estava.
  List<Color> surfacesFor(FinInkToken token) => <Color>[
        canvas,
        surface,
        surfaceSunken,
        // Estado tambem aparece sobre a propria pastilha tonal, que e o par
        // mais apertado da paleta: fundo e tinta compartilham o matiz.
        switch (token) {
          FinInkToken.positive => positiveSurface,
          FinInkToken.negative => negativeSurface,
          FinInkToken.caution => cautionSurface,
          FinInkToken.pending => pendingSurface,
          _ => surface,
        },
      ];

  /// Cor de texto para uma direcao.
  ///
  /// [FinTrend.neutral] resolve para [textPrimary], e nao para uma cor
  /// apagada: um valor sem direcao -- patrimonio final, quantidade de ativos,
  /// ou uma variacao exatamente zero -- continua sendo uma MEDIDA, e medida se
  /// le na tinta principal. A de-enfase pertence a [FinTrend.blocked], que
  /// significa ausencia de dado.
  Color forTrend(FinTrend trend) => switch (trend) {
        FinTrend.positive => positive,
        FinTrend.negative => negative,
        FinTrend.caution => caution,
        FinTrend.pending => pending,
        FinTrend.blocked => blocked,
        FinTrend.neutral => textPrimary,
      };

  /// Fundo tonal para uma direcao.
  Color surfaceForTrend(FinTrend trend) => switch (trend) {
        FinTrend.positive => positiveSurface,
        FinTrend.negative => negativeSurface,
        FinTrend.caution => cautionSurface,
        FinTrend.pending => pendingSurface,
        FinTrend.neutral || FinTrend.blocked => surfaceSunken,
      };

  /// Paleta clara.
  ///
  /// As razoes anotadas sao o PIOR caso entre as superficies de
  /// [surfacesFor], nao a medida contra branco -- que e otimista em cerca de
  /// meio ponto. Alterar um valor sem remedir faz
  /// `test/presentation/contrast_test.dart` falhar, que e o ponto.
  static const light = FinColors(
    canvas: Color(0xFFF4F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEEF1F5),
    border: Color(0xFFDCE3E9),
    borderStrong: Color(0xFFC3CDD6),
    divider: Color(0xFFE8ECF1),
    textPrimary: Color(0xFF0E1621), // 16,04:1  AAA
    textSecondary: Color(0xFF435261), //  7,08:1  AAA
    textTertiary: Color(0xFF55636F), //  5,45:1  AA  -- so metadado
    textOnBrand: Color(0xFFFFFFFF),
    positive: Color(0xFF0A6E52), //  5,38:1  AA
    negative: Color(0xFF98201A), //  7,01:1  AAA
    caution: Color(0xFF6F4800), //  7,12:1  AAA
    pending: Color(0xFF3E5AA8), //  5,59:1  AA
    blocked: Color(0xFF5A5F6B), //  5,64:1  AA
    positiveSurface: Color(0xFFE4F1EC),
    negativeSurface: Color(0xFFFBE9E7),
    cautionSurface: Color(0xFFFBF0DC),
    pendingSurface: Color(0xFFE9EEF9),
    brand: Color(0xFF00B37E),
    brandSurface: Color(0xFFE4F1EC),
  );

  /// Paleta escura.
  static const dark = FinColors(
    canvas: Color(0xFF0B1116),
    surface: Color(0xFF121A22),
    surfaceRaised: Color(0xFF18222B),
    surfaceSunken: Color(0xFF0E161D),
    border: Color(0xFF26313A),
    borderStrong: Color(0xFF36434D),
    divider: Color(0xFF1D262E),
    textPrimary: Color(0xFFE8EEF4), // 15,02:1  AAA
    textSecondary: Color(0xFFA6B4C2), //  8,30:1  AAA
    textTertiary: Color(0xFF7C8C9C), //  5,09:1  AA  -- so metadado
    textOnBrand: Color(0xFF04231A),
    positive: Color(0xFF3DD8A4), //  8,36:1  AAA
    negative: Color(0xFFFF8B7E), //  7,51:1  AAA
    caution: Color(0xFFF2B544), //  8,73:1  AAA
    pending: Color(0xFF8FB4FF), //  8,15:1  AAA
    blocked: Color(0xFF9AA5B1), //  7,01:1  AAA
    positiveSurface: Color(0xFF122A24),
    negativeSurface: Color(0xFF2C1614),
    cautionSurface: Color(0xFF2A2011),
    pendingSurface: Color(0xFF141D2E),
    brand: Color(0xFF00CC8F),
    brandSurface: Color(0xFF122A24),
  );

  /// A paleta e fechada.
  ///
  /// Variacao vem de [light] e [dark], nao de ajuste no ponto de uso: um
  /// `copyWith` funcional aqui seria a porta de entrada de volta para os 62
  /// literais de cor que o sistema veio substituir.
  @override
  FinColors copyWith() => this;

  /// Troca de tema e discreta, nao interpolada.
  ///
  /// Interpolar canal a canal produziria, no meio da transicao, pares de cor
  /// que nunca foram medidos -- e portanto quadros em que o contraste cai
  /// abaixo do piso. Trocar de uma vez, no ponto medio, evita isso.
  @override
  FinColors lerp(ThemeExtension<FinColors>? other, double t) =>
      other is FinColors ? (t < 0.5 ? this : other) : this;

  /// Igualdade por valor, e nao por identidade.
  ///
  /// Nao e detalhe: `ThemeData ==` compara as extensoes com `mapEquals`, que
  /// delega ao `==` de cada uma. Sem isto, dois temas estruturalmente iguais
  /// comparariam diferente, e **toda reconstrucao de tema propagaria rebuild
  /// para a arvore inteira** -- num aplicativo cujas telas carregam
  /// `BackdropFilter` e graficos, isso custa caro.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FinColors &&
        other.canvas == canvas &&
        other.surface == surface &&
        other.surfaceRaised == surfaceRaised &&
        other.surfaceSunken == surfaceSunken &&
        other.border == border &&
        other.borderStrong == borderStrong &&
        other.divider == divider &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textTertiary == textTertiary &&
        other.textOnBrand == textOnBrand &&
        other.positive == positive &&
        other.negative == negative &&
        other.caution == caution &&
        other.pending == pending &&
        other.blocked == blocked &&
        other.positiveSurface == positiveSurface &&
        other.negativeSurface == negativeSurface &&
        other.cautionSurface == cautionSurface &&
        other.pendingSurface == pendingSurface &&
        other.brand == brand &&
        other.brandSurface == brandSurface;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
        canvas,
        surface,
        surfaceRaised,
        surfaceSunken,
        border,
        borderStrong,
        divider,
        textPrimary,
        textSecondary,
        textTertiary,
        textOnBrand,
        positive,
        negative,
        caution,
        pending,
        blocked,
        positiveSurface,
        negativeSurface,
        cautionSurface,
        pendingSurface,
        brand,
        brandSurface,
      ]);
}
