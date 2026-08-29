import 'package:flutter/widgets.dart';

/// Grid de 4 dp. Sete degraus, e nada entre eles -- salvo [xxs].
///
/// Os 31 espacamentos distintos da base colapsam nestes: `7` vira [sm], `9` e
/// `10` viram [md], `13` e `14` viram [lg]. O efeito acumulado do que havia
/// antes era ritmo vertical irregular -- dois cartoes vizinhos respirando
/// diferente sem razao de conteudo para isso.
abstract final class FinSpace {
  /// Meio passo, FORA do grid.
  ///
  /// So para ajuste optico dentro de pastilha e chip, onde 4 dp de padding
  /// vertical deixa a caixa alta demais em relacao ao texto que ela envolve.
  ///
  /// **Nao e degrau de layout.** Separar blocos com ele desfaz o motivo de a
  /// escala existir: foi assim que os 31 valores anteriores nasceram, um
  /// ajuste fino de cada vez. Nao existe `Gap.xxs`, e a ausencia e a regra.
  static const double xxs = 2;

  /// Rotulo para valor, dentro de uma metrica.
  static const double xs = 4;

  /// Icone para texto; entre linhas de tabela.
  static const double sm = 8;

  /// Padding interno compacto; entre campos.
  static const double md = 12;

  /// Padding de cartao; entre cartoes.
  static const double lg = 16;

  /// Entre secoes dentro de um cartao.
  static const double xl = 24;

  /// Entre blocos de tela.
  static const double xxl = 32;

  /// Respiro de estado vazio; topo de tela.
  static const double xxxl = 48;

  /// Padding padrao de cartao.
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// Padding padrao de tela.
  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);

  /// Padding de linha de lista ou de tabela.
  static const EdgeInsets rowPadding =
      EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

/// Espacador do grid, no lugar de `SizedBox(height: 12)` e afins.
///
/// A diferenca e que este nao aceita numero solto: um valor fora da escala nao
/// tem construtor, entao nao compila.
///
/// **Nao existe `Gap.xxs`, e a ausencia e a regra.** [FinSpace.xxs] e ajuste
/// optico de padding dentro de uma caixa; separar dois blocos por 2 dp e o
/// tipo de decisao que produziu os 31 espacamentos que esta escala veio
/// substituir. Sem construtor, o atalho nao esta disponivel.
class Gap extends StatelessWidget {
  /// Medida do vao, sempre um passo de [FinSpace].
  final double size;

  /// Eixo em que o vao se abre.
  final Axis axis;

  /// Vao de 4 dp.
  const Gap.xs({super.key, this.axis = Axis.vertical}) : size = FinSpace.xs;

  /// Vao de 8 dp.
  const Gap.sm({super.key, this.axis = Axis.vertical}) : size = FinSpace.sm;

  /// Vao de 12 dp.
  const Gap.md({super.key, this.axis = Axis.vertical}) : size = FinSpace.md;

  /// Vao de 16 dp.
  const Gap.lg({super.key, this.axis = Axis.vertical}) : size = FinSpace.lg;

  /// Vao de 24 dp.
  const Gap.xl({super.key, this.axis = Axis.vertical}) : size = FinSpace.xl;

  /// Vao de 32 dp.
  const Gap.xxl({super.key, this.axis = Axis.vertical}) : size = FinSpace.xxl;

  @override
  Widget build(BuildContext context) =>
      axis == Axis.vertical ? SizedBox(height: size) : SizedBox(width: size);
}
