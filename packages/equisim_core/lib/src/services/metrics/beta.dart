import 'dart:math' as math;

import '../../failures/failure.dart';
import '../../failures/result.dart';

/// Beta estimado localmente, com a janela declarada junto do valor.
///
/// O beta publicado pela fonte é descartado de propósito: sua janela e seu
/// índice de referência não são documentados, o que é incompatível com
/// reprodutibilidade acadêmica. Calcular custa menos de 1 ms.
class BetaEstimate {
  final double beta;

  /// Coeficiente de correlação de Pearson com o mercado.
  final double correlation;

  /// Quantidade de observações pareadas usadas.
  final int observations;

  const BetaEstimate({
    required this.beta,
    required this.correlation,
    required this.observations,
  });

  @override
  String toString() =>
      'β=${beta.toStringAsFixed(4)} (ρ=${correlation.toStringAsFixed(3)}, n=$observations)';
}

abstract final class BetaCalculator {
  /// β = Cov(R_ativo, R_mercado) / Var(R_mercado).
  ///
  /// As séries devem estar pareadas por data — use [alignReturns] antes.
  static Result<BetaEstimate> estimate({
    required List<double> assetReturns,
    required List<double> marketReturns,
    int minimumObservations = 30,
  }) {
    if (assetReturns.length != marketReturns.length) {
      return const Err(InvalidInput(
        'Séries de retorno com tamanhos diferentes; pareie por data antes.',
      ));
    }
    final n = assetReturns.length;
    if (n < minimumObservations) {
      return Err(InsufficientData(
        'Beta exige ao menos $minimumObservations observações; recebidas $n.',
      ));
    }

    final meanAsset = assetReturns.reduce((a, b) => a + b) / n;
    final meanMarket = marketReturns.reduce((a, b) => a + b) / n;

    var covariance = 0.0;
    var marketVariance = 0.0;
    var assetVariance = 0.0;
    for (var i = 0; i < n; i++) {
      final da = assetReturns[i] - meanAsset;
      final dm = marketReturns[i] - meanMarket;
      covariance += da * dm;
      marketVariance += dm * dm;
      assetVariance += da * da;
    }
    covariance /= n - 1;
    marketVariance /= n - 1;
    assetVariance /= n - 1;

    if (marketVariance <= 0) {
      return const Err(ComputationFailure(
        'Variância do mercado nula: série de referência constante.',
      ));
    }

    final beta = covariance / marketVariance;
    final denominator = math.sqrt(assetVariance * marketVariance);
    final correlation = denominator > 0 ? covariance / denominator : 0.0;

    return Ok(BetaEstimate(
      beta: beta,
      correlation: correlation,
      observations: n,
    ));
  }

  /// Pareia duas séries datadas pelas datas em comum e devolve os retornos.
  static ({List<double> asset, List<double> market}) alignReturns({
    required List<DateTime> assetDates,
    required List<double> assetIndex,
    required List<DateTime> marketDates,
    required List<double> marketIndex,
  }) {
    final marketByDate = <DateTime, double>{};
    for (var i = 0; i < marketDates.length; i++) {
      marketByDate[marketDates[i]] = marketIndex[i];
    }

    final pairedAsset = <double>[];
    final pairedMarket = <double>[];
    double? previousAsset;
    double? previousMarket;

    for (var i = 0; i < assetDates.length; i++) {
      final marketValue = marketByDate[assetDates[i]];
      if (marketValue == null) continue;
      final assetValue = assetIndex[i];
      if (previousAsset != null &&
          previousMarket != null &&
          previousAsset > 0 &&
          previousMarket > 0) {
        pairedAsset.add(assetValue / previousAsset - 1.0);
        pairedMarket.add(marketValue / previousMarket - 1.0);
      }
      previousAsset = assetValue;
      previousMarket = marketValue;
    }

    return (asset: pairedAsset, market: pairedMarket);
  }

  /// Matriz de correlação entre séries de retorno pareadas.
  static List<List<double>> correlationMatrix(List<List<double>> returns) {
    final k = returns.length;
    final matrix = List.generate(k, (_) => List<double>.filled(k, 0.0));
    for (var i = 0; i < k; i++) {
      for (var j = i; j < k; j++) {
        final rho = _pearson(returns[i], returns[j]);
        matrix[i][j] = rho;
        matrix[j][i] = rho;
      }
    }
    return matrix;
  }

  static double _pearson(List<double> x, List<double> y) {
    final n = math.min(x.length, y.length);
    if (n < 2) return 0.0;
    var meanX = 0.0;
    var meanY = 0.0;
    for (var i = 0; i < n; i++) {
      meanX += x[i];
      meanY += y[i];
    }
    meanX /= n;
    meanY /= n;

    var sxy = 0.0;
    var sxx = 0.0;
    var syy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - meanX;
      final dy = y[i] - meanY;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
    }
    final denominator = math.sqrt(sxx * syy);
    return denominator > 0 ? sxy / denominator : 0.0;
  }
}
