import 'dart:math' as math;

import '../../entities/fundamentals.dart';

/// Crescimento estimado a partir do histórico, com a origem declarada.
class GrowthEstimate {
  /// Taxa anual em fração.
  final double rate;

  /// Exercícios efetivamente usados.
  final int periodsUsed;

  /// Como o número foi obtido — entra nos avisos do resultado.
  final String basis;

  /// `true` quando o valor bruto foi limitado pela banda de sanidade.
  final bool clamped;

  /// Taxa antes da banda de sanidade, quando houve regressão.
  ///
  /// Existe para a auditoria: a diferença entre o bruto e o aplicado é
  /// exatamente o que a banda fez, e escondê-la tornaria o limite invisível
  /// para quem confere a conta.
  final double? rawRate;

  /// Inclinação da regressão log-linear, `b` em `ln(v) = a + b·t`.
  final double? slope;

  const GrowthEstimate({
    required this.rate,
    required this.periodsUsed,
    required this.basis,
    this.clamped = false,
    this.rawRate,
    this.slope,
  });
}

/// Estima crescimento a partir de séries de fundamentos.
///
/// Duas decisões deliberadas:
///
/// **Regressão sobre CAGR ponta a ponta.** O CAGR entre o primeiro e o último
/// exercício depende inteiramente de dois pontos, e um deles sendo atípico —
/// comum em commodities — o resultado desanda. A inclinação de uma regressão
/// log-linear usa todos os pontos.
///
/// **Banda de sanidade obrigatória.** Extrapolar 40% ao ano por perpetuidade
/// produz valores absurdos com aparência de precisão. A banda transforma isso
/// num aviso visível em vez de um número silenciosamente errado.
abstract final class GrowthEstimator {
  /// Piso: uma empresa em perpetuidade não encolhe indefinidamente.
  static const double floorRate = -0.05;

  /// Teto: acima disso a projeção deixa de ser defensável.
  static const double ceilingRate = 0.20;

  /// Usado quando não há histórico utilizável — próximo da inflação de longo
  /// prazo, portanto conservador.
  static const double fallbackRate = 0.04;

  /// Estima o crescimento anual de uma métrica ao longo dos exercícios.
  ///
  /// [selector] extrai a métrica de cada exercício; valores nulos ou não
  /// positivos são descartados, porque log de número não positivo não existe
  /// e um exercício de prejuízo não informa taxa de crescimento.
  static GrowthEstimate fromHistory(
    List<FundamentalsSnapshot> snapshots,
    double? Function(FundamentalsSnapshot) selector, {
    String metricName = 'métrica',
  }) {
    final points = <({double year, double value})>[];
    for (final snapshot in snapshots) {
      final value = selector(snapshot);
      if (value == null || value <= 0) continue;
      points.add((
        year: snapshot.fiscalPeriodEnd.year.toDouble(),
        value: value,
      ));
    }

    if (points.length < 3) {
      return const GrowthEstimate(
        rate: fallbackRate,
        periodsUsed: 0,
        basis: 'histórico insuficiente; adotado crescimento conservador de 4%',
      );
    }

    // Regressão log-linear: ln(v) = a + b·t, onde e^b − 1 é a taxa anual.
    final n = points.length;
    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
    for (final p in points) {
      final x = p.year;
      final y = math.log(p.value);
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
    }

    final denominator = n * sumXX - sumX * sumX;
    if (denominator.abs() < 1e-12) {
      return GrowthEstimate(
        rate: fallbackRate,
        periodsUsed: n,
        basis: 'exercícios sem dispersão temporal; adotado 4%',
      );
    }

    final slope = (n * sumXY - sumX * sumY) / denominator;
    final raw = math.exp(slope) - 1.0;

    if (!raw.isFinite) {
      return GrowthEstimate(
        rate: fallbackRate,
        periodsUsed: n,
        basis: 'regressão não convergiu; adotado 4%',
      );
    }

    final bounded = raw.clamp(floorRate, ceilingRate);
    final wasClamped = (bounded - raw).abs() > 1e-12;

    return GrowthEstimate(
      rate: bounded,
      periodsUsed: n,
      clamped: wasClamped,
      rawRate: raw,
      slope: slope,
      basis: wasClamped
          ? 'regressão de $metricName sobre $n exercícios indicou '
              '${(raw * 100).toStringAsFixed(1)}% a.a., limitado a '
              '${(bounded * 100).toStringAsFixed(1)}% pela banda de sanidade'
          : 'regressão de $metricName sobre $n exercícios',
    );
  }

  /// Crescimento **real** de longo prazo da economia brasileira.
  ///
  /// Não é o teto da perpetuidade: é a parcela real dele. O teto que entra no
  /// desconto precisa ser nominal — ver [perpetual] e
  /// `MarketAnchors.nominalEconomyGrowth`.
  @Deprecated("Substituída por MarketAnchors.realEconomyGrowth, medido do IBC-Br (decisão 25). Mantida só como padrão de quem constrói premissas à mão.")
  static const double realEconomyGrowth = 0.0145;

  /// Crescimento na perpetuidade.
  ///
  /// Nunca deve superar o crescimento de longo prazo da economia: uma empresa
  /// crescendo acima do PIB para sempre acabaria maior que a economia inteira.
  ///
  /// **[economyGrowth] precisa estar na mesma unidade da taxa de desconto.**
  /// O desconto do valuation é nominal, porque sai do CDI; então o teto aqui
  /// é o crescimento **nominal** — real mais inflação. O padrão preserva o
  /// comportamento antigo para quem chama sem informar, mas a aplicação passa
  /// o valor derivado do IPCA observado.
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
    double economyGrowth = realEconomyGrowth,
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
