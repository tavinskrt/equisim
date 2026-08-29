import 'dart:math' as math;

import 'returns.dart';

/// Estatísticas de risco de uma série de retornos.
///
/// Todas devem ser calculadas sobre a série **TWR neutralizada de aportes**,
/// nunca sobre a curva bruta de patrimônio: no dia do aporte a curva bruta dá
/// um salto que seria contabilizado como retorno de mercado, inflando a
/// volatilidade e suavizando artificialmente o drawdown.
class RiskMetrics {
  /// Desvio-padrão amostral anualizado, em fração.
  final double volatility;

  /// Pior queda de pico a vale, em fração negativa.
  final double maxDrawdown;

  /// (CAGR − taxa livre de risco) / volatilidade.
  final double sharpe;

  /// Como o Sharpe, mas penalizando apenas o desvio negativo.
  final double sortino;

  /// CAGR / |máximo drawdown|.
  final double calmar;

  /// Agrupa as estatísticas já apuradas. Para calculá-las a partir de uma
  /// série, use [RiskMetrics.fromIndex].
  const RiskMetrics({
    required this.volatility,
    required this.maxDrawdown,
    required this.sharpe,
    required this.sortino,
    required this.calmar,
  });

  static const RiskMetrics empty = RiskMetrics(
    volatility: 0,
    maxDrawdown: 0,
    sharpe: 0,
    sortino: 0,
    calmar: 0,
  );

  /// Calcula o conjunto a partir do índice TWR e do CAGR já apurado.
  ///
  /// [riskFreeRate] é a taxa livre de risco **anual** do período — deve vir do
  /// CDI observado, não de uma constante.
  factory RiskMetrics.fromIndex({
    required List<double> twrIndex,
    required double cagr,
    required double riskFreeRate,
    int periodsPerYear = tradingDaysPerYear,
  }) {
    if (twrIndex.length < 2) return RiskMetrics.empty;

    final periodReturns = <double>[];
    for (var i = 1; i < twrIndex.length; i++) {
      if (twrIndex[i - 1] > 0) {
        periodReturns.add(twrIndex[i] / twrIndex[i - 1] - 1.0);
      }
    }

    final vol = annualizedVolatility(periodReturns, periodsPerYear: periodsPerYear);
    final downside =
        annualizedDownsideDeviation(periodReturns, periodsPerYear: periodsPerYear);
    final mdd = maxDrawdownOf(twrIndex);

    final excess = cagr - riskFreeRate;
    return RiskMetrics(
      volatility: vol,
      maxDrawdown: mdd,
      sharpe: vol > 0 ? excess / vol : 0.0,
      sortino: downside > 0 ? excess / downside : 0.0,
      calmar: mdd < 0 ? cagr / mdd.abs() : 0.0,
    );
  }

  /// Desvio-padrão **amostral** (n−1) anualizado.
  ///
  /// A escolha por amostral é deliberada e uniforme em todo o pacote: a série
  /// observada é uma amostra do processo gerador, não a população.
  static double annualizedVolatility(
    List<double> periodReturns, {
    int periodsPerYear = tradingDaysPerYear,
  }) {
    if (periodReturns.length < 2) return 0.0;
    final mean =
        periodReturns.reduce((a, b) => a + b) / periodReturns.length;
    var sumSquares = 0.0;
    for (final r in periodReturns) {
      final d = r - mean;
      sumSquares += d * d;
    }
    final variance = sumSquares / (periodReturns.length - 1);
    return math.sqrt(variance) * math.sqrt(periodsPerYear.toDouble());
  }

  /// Semidesvio abaixo de [target], anualizado.
  ///
  /// Segue a definição de Sortino e Satchell:
  ///
  ///     DD = √( (1/N) · Σ min(rᵢ − alvo, 0)² )
  ///
  /// O divisor é o número **total** de observações, não a contagem de retornos
  /// negativos, e os desvios são medidos a partir do alvo, não da média dos
  /// negativos. As duas escolhas importam: dividir pela contagem de negativos
  /// infla o semidesvio de séries que caem pouco e raramente, invertendo a
  /// ordenação entre ativos.
  ///
  /// A conferência cruzada em Python expôs esse defeito na implementação
  /// anterior — que dividia por `(negativos − 1)` — com desvio de até 32%.
  static double annualizedDownsideDeviation(
    List<double> periodReturns, {
    double target = 0.0,
    int periodsPerYear = tradingDaysPerYear,
  }) {
    if (periodReturns.length < 2) return 0.0;
    var sumSquares = 0.0;
    for (final r in periodReturns) {
      final shortfall = r - target;
      if (shortfall < 0) sumSquares += shortfall * shortfall;
    }
    if (sumSquares <= 0) return 0.0;
    final variance = sumSquares / periodReturns.length;
    return math.sqrt(variance) * math.sqrt(periodsPerYear.toDouble());
  }

  /// Máximo drawdown, em fração negativa (−0,35 = queda de 35%).
  static double maxDrawdownOf(List<double> series) {
    if (series.isEmpty) return 0.0;
    var peak = series.first;
    var worst = 0.0;
    for (final value in series) {
      if (value > peak) peak = value;
      if (peak > 0) {
        final drawdown = (value - peak) / peak;
        if (drawdown < worst) worst = drawdown;
      }
    }
    return worst;
  }
}
