import 'dart:math' as math;

/// Fluxo-base de um DCF, depois do tratamento de exercício atípico.
class BaseFlow {
  /// Valor efetivamente usado como ponto de partida da projeção.
  final double value;

  /// Valor do exercício mais recente, antes de qualquer tratamento.
  final double observed;

  /// Mediana da amostra, quando houve amostra utilizável.
  final double? median;

  /// Exercícios considerados na mediana.
  final int periodsUsed;

  /// `true` quando o exercício mais recente saiu da banda e foi aparado.
  final bool winsorized;

  const BaseFlow({
    required this.value,
    required this.observed,
    required this.median,
    required this.periodsUsed,
    this.winsorized = false,
  });

  /// Quantas vezes o exercício observado supera a mediana.
  double? get deviationFactor =>
      (median == null || median == 0) ? null : observed / median!;
}

/// Normaliza o fluxo-base de uma perpetuidade.
///
/// **O problema.** O valor terminal de um DCF é uma perpetuidade, e ela é
/// construída sobre o fluxo de **um único exercício**. Quando esse exercício é
/// atípico, o erro não fica contido: ele multiplica o valor inteiro da empresa.
/// Medido em 21/08/2026, a SAPR11 registrou caixa operacional de R$ 7,06 bi
/// contra EBITDA de R$ 2,34 bi — um fluxo livre 9,5× a mediana de cinco
/// exercícios —, e o preço justo saía em R$ 182 contra uma cotação de R$ 33.
///
/// **O tratamento.** Winsorização clássica: o exercício mais recente é aparado
/// para dentro de uma banda em torno da mediana da amostra, em vez de
/// substituído por ela. A diferença importa — substituir pela mediana
/// descartaria a informação de tendência, enquanto aparar preserva a direção e
/// só limita a magnitude.
///
/// **O que não faz.** Não ressuscita modelo: a decisão sobre qual modelo se
/// aplica continua sendo tomada sobre o exercício observado. E não aparta nada
/// quando a mediana é não positiva — aí a empresa queima caixa no ano típico,
/// e a fragilidade da perpetuidade é o próprio fato a reportar, não algo a
/// corrigir com aritmética.
abstract final class BaseFlowNormalizer {
  /// Exercícios da amostra. Cinco cobrem um ciclo curto sem envelhecer a base.
  static const int defaultWindow = 5;

  /// Meia-largura da banda, em fração da mediana.
  ///
  /// Meia mediana para cada lado deixa passar a variação normal de um negócio
  /// cíclico e pega o exercício que destoa de fato.
  static const double defaultTolerance = 0.5;

  /// [series] em ordem cronológica; o último elemento é o exercício-base.
  static BaseFlow normalize(
    List<double> series, {
    int window = defaultWindow,
    double tolerance = defaultTolerance,
  }) {
    if (series.isEmpty) {
      return const BaseFlow(
        value: 0,
        observed: 0,
        median: null,
        periodsUsed: 0,
      );
    }

    final observed = series.last;
    final sample =
        series.length <= window ? series : series.sublist(series.length - window);

    // Amostra curta demais não sustenta mediana: dois pontos não distinguem
    // exercício atípico de tendência.
    if (sample.length < 3) {
      return BaseFlow(
        value: observed,
        observed: observed,
        median: null,
        periodsUsed: sample.length,
      );
    }

    final median = _medianOf(sample);
    if (median <= 0) {
      return BaseFlow(
        value: observed,
        observed: observed,
        median: median,
        periodsUsed: sample.length,
      );
    }

    final lower = median * (1 - tolerance);
    final upper = median * (1 + tolerance);
    final clamped = math.min(math.max(observed, lower), upper);

    return BaseFlow(
      value: clamped,
      observed: observed,
      median: median,
      periodsUsed: sample.length,
      winsorized: (clamped - observed).abs() > 1e-9,
    );
  }

  static double _medianOf(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
