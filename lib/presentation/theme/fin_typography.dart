import 'package:flutter/material.dart';

/// Escala tipografica do produto.
///
/// Onze papeis substituem os 20 tamanhos que a base tinha, oito deles
/// fracionarios. So inteiros, com piso em 11 px: meio pixel nao e um degrau
/// perceptivel de hierarquia, e `10 / 10.5` existia apenas porque alguem
/// empurrou o numero ate caber.
///
/// **A familia `num*` e o ponto do arquivo.** Os quatro papeis numericos
/// carregam [FontFeature.tabularFigures] e sao os UNICOS autorizados a exibir
/// dinheiro, percentual ou razao. Sem isso o `1` e mais estreito que o `8` e a
/// virgula decimal se desloca de uma linha para a outra em qualquer coluna
/// alinhada a direita.
@immutable
class FinTypography extends ThemeExtension<FinTypography> {
  /// Titulo de tela vazia.
  final TextStyle displayLg;

  /// Nome de carteira, cabecalho de pagina.
  final TextStyle titleLg;

  /// Titulo de cartao.
  final TextStyle titleSm;

  /// Texto corrente, mensagem de estado vazio.
  final TextStyle bodyMd;

  /// Ticker, setor, linha de apoio.
  final TextStyle bodySm;

  /// Rotulo de metrica e cabecalho de coluna. Vai em caixa alta no ponto de
  /// uso; o `letterSpacing` ja compensa isso.
  final TextStyle label;

  /// Metadado: data, base de calculo, ressalva.
  final TextStyle caption;

  /// Saldo principal. Tabular.
  final TextStyle numHero;

  /// Patrimonio final, valor de destaque. Tabular.
  final TextStyle numLg;

  /// Metrica secundaria: TWR, XIRR, Sharpe. Tabular.
  final TextStyle numMd;

  /// Celula de tabela: peso, potencial, retorno. Tabular.
  final TextStyle numSm;

  /// Declara a escala.
  const FinTypography({
    required this.displayLg,
    required this.titleLg,
    required this.titleSm,
    required this.bodyMd,
    required this.bodySm,
    required this.label,
    required this.caption,
    required this.numHero,
    required this.numLg,
    required this.numMd,
    required this.numSm,
  });

  /// Algarismos de largura fixa.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Familia tipografica do produto.
  ///
  /// `null` de proposito: nenhuma fonte esta declarada em `pubspec.yaml`, e
  /// nomear uma que nao foi empacotada produz **fallback silencioso** -- o
  /// texto simplesmente sai em outra fonte, sem aviso e sem falha de teste.
  ///
  /// Com `null`, cada plataforma usa a propria (Roboto no Android, SF no iOS,
  /// Segoe UI no Windows), e as tres tem `tnum`, entao o alinhamento tabular
  /// funciona hoje. Empacotar uma fonte depois -- para ter largura de digito
  /// identica tambem na web -- e trocar esta constante e adicionar o asset.
  static const String? _family = null;

  /// Escala padrao.
  factory FinTypography.standard() {
    return const FinTypography(
      displayLg: TextStyle(
        fontFamily: _family,
        fontSize: 34,
        height: 1.10,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLg: TextStyle(
        fontFamily: _family,
        fontSize: 20,
        height: 1.20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSm: TextStyle(
        fontFamily: _family,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      bodyMd: TextStyle(
        fontFamily: _family,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodySm: TextStyle(
        fontFamily: _family,
        fontSize: 13,
        height: 1.40,
        fontWeight: FontWeight.w400,
      ),
      label: TextStyle(
        fontFamily: _family,
        fontSize: 12,
        height: 1.30,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.96,
      ),
      caption: TextStyle(
        fontFamily: _family,
        fontSize: 11,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      numHero: TextStyle(
        fontFamily: _family,
        fontSize: 34,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        fontFeatures: _tabular,
      ),
      numLg: TextStyle(
        fontFamily: _family,
        fontSize: 22,
        height: 1.10,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        fontFeatures: _tabular,
      ),
      numMd: TextStyle(
        fontFamily: _family,
        fontSize: 16,
        height: 1.20,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
      ),
      numSm: TextStyle(
        fontFamily: _family,
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
      ),
    );
  }

  /// Todos os papeis numericos, na ordem da escala.
  ///
  /// Existe para o teste: um papel `num*` novo que nao carregue
  /// [FontFeature.tabularFigures] falha aqui em vez de desalinhar uma coluna
  /// em producao meses depois.
  List<TextStyle> get numericStyles => <TextStyle>[
    numHero,
    numLg,
    numMd,
    numSm,
  ];

  /// Todos os papeis de texto corrente, na ordem da escala.
  List<TextStyle> get proseStyles => <TextStyle>[
    displayLg,
    titleLg,
    titleSm,
    bodyMd,
    bodySm,
    label,
    caption,
  ];

  @override
  FinTypography copyWith({
    TextStyle? displayLg,
    TextStyle? titleLg,
    TextStyle? titleSm,
    TextStyle? bodyMd,
    TextStyle? bodySm,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? numHero,
    TextStyle? numLg,
    TextStyle? numMd,
    TextStyle? numSm,
  }) {
    return FinTypography(
      displayLg: displayLg ?? this.displayLg,
      titleLg: titleLg ?? this.titleLg,
      titleSm: titleSm ?? this.titleSm,
      bodyMd: bodyMd ?? this.bodyMd,
      bodySm: bodySm ?? this.bodySm,
      label: label ?? this.label,
      caption: caption ?? this.caption,
      numHero: numHero ?? this.numHero,
      numLg: numLg ?? this.numLg,
      numMd: numMd ?? this.numMd,
      numSm: numSm ?? this.numSm,
    );
  }

  @override
  FinTypography lerp(ThemeExtension<FinTypography>? other, double t) {
    if (other is! FinTypography) return this;
    return FinTypography(
      displayLg: TextStyle.lerp(displayLg, other.displayLg, t)!,
      titleLg: TextStyle.lerp(titleLg, other.titleLg, t)!,
      titleSm: TextStyle.lerp(titleSm, other.titleSm, t)!,
      bodyMd: TextStyle.lerp(bodyMd, other.bodyMd, t)!,
      bodySm: TextStyle.lerp(bodySm, other.bodySm, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      numHero: TextStyle.lerp(numHero, other.numHero, t)!,
      numLg: TextStyle.lerp(numLg, other.numLg, t)!,
      numMd: TextStyle.lerp(numMd, other.numMd, t)!,
      numSm: TextStyle.lerp(numSm, other.numSm, t)!,
    );
  }

  /// Igualdade por valor. Ver a justificativa em `FinColors.operator ==`:
  /// sem ela, toda reconstrucao de tema propaga rebuild para a arvore inteira.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FinTypography &&
        other.displayLg == displayLg &&
        other.titleLg == titleLg &&
        other.titleSm == titleSm &&
        other.bodyMd == bodyMd &&
        other.bodySm == bodySm &&
        other.label == label &&
        other.caption == caption &&
        other.numHero == numHero &&
        other.numLg == numLg &&
        other.numMd == numMd &&
        other.numSm == numSm;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    displayLg,
    titleLg,
    titleSm,
    bodyMd,
    bodySm,
    label,
    caption,
    numHero,
    numLg,
    numMd,
    numSm,
  ]);
}
