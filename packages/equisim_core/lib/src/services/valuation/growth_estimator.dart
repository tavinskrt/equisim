import 'dart:math' as math;

/// Limites do crescimento na perpetuidade.
///
/// **Banda de sanidade obrigatória.** Extrapolar 40% ao ano por perpetuidade
/// produz valores absurdos com aparência de precisão. O piso e o teto
/// transformam isso num limite declarado em vez de um número silenciosamente
/// errado.
abstract final class GrowthEstimator {
  /// Piso: uma empresa em perpetuidade não encolhe indefinidamente.
  static const double floorRate = -0.05;

  /// Crescimento na perpetuidade.
  ///
  /// Nunca deve superar o crescimento de longo prazo da economia: uma empresa
  /// crescendo acima do PIB para sempre acabaria maior que a economia inteira.
  ///
  /// **[economyGrowth] precisa estar na mesma unidade da taxa de desconto.**
  /// O desconto do valuation é nominal, porque sai do CDI; então o teto aqui
  /// é o crescimento **nominal** — real mais inflação, o valor que a aplicação
  /// deriva do IPCA observado.
  ///
  /// **O piso é [floorRate], e não zero** (decisão 56). O piso em zero afirmava
  /// que toda empresa em declínio volta a crescer zero em dez anos — e o
  /// projeto já tinha declarado onde fica o limite do encolhimento eterno:
  /// −5% ao ano, em [floorRate], com a razão escrita lá. O segundo piso tornava
  /// o primeiro inalcançável na perpetuidade.
  ///
  /// Com o terminal neutro da decisão 25 o crescimento perpétuo **não cria
  /// valor** — `ROIC_∞ = WACC` faz o terminal virar `fluxo/r` —, de modo que o
  /// papel dele aqui é ser o **alvo do decaimento** do período explícito. Com o
  /// piso em zero, uma empresa medida a −4,6% subia até zero ao longo de dez
  /// anos: uma recuperação que nada no dado sustenta.
  ///
  /// Medido em 11/09/2026: o piso mordia em 3 dos 127, e valia **23,4% na
  /// PCAR3**, 4,7% na BRAP4 e 2,3% na B3SA3.
  static double perpetual({
    required double explicitGrowth,
    required double economyGrowth,
  }) =>
      _confinar(math.min(explicitGrowth, economyGrowth), economyGrowth);

  /// Confina em `[floorRate, economyGrowth]`, com o teto tendo precedência.
  ///
  /// **`clamp` lança quando o piso passa o teto**, e passa quando a economia
  /// encolhe mais de 5% ao ano. É caminho implausível e é público: quem
  /// constrói premissas à mão alcança. Ali o teto vence — nenhuma empresa
  /// cresce acima da economia para sempre, e essa é a regra mais forte das
  /// duas.
  static double _confinar(double g, double teto) {
    if (teto <= floorRate) return teto;
    return g.clamp(floorRate, teto).toDouble();
  }
}
