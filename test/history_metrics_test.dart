import 'package:flutter_test/flutter_test.dart';
import 'package:equisim/services/backtest_history_service.dart';

void main() {
  group('RiskMetrics Unit Tests', () {
    test('Calculates Max Drawdown correctly', () {
      // Curva determinística:
      // Inicia em 100
      // Atinge pico de 120
      // Cai para 90 (Queda de 25% em relação ao pico 120)
      // Sobe para 110
      // Cai para 80 (Queda de 33.33% em relação ao pico 120)
      // Recupera para 100
      final List<double> values = [100.0, 120.0, 90.0, 110.0, 80.0, 100.0];

      final metrics = RiskMetrics.calculate(values, 10.0);

      // Max Drawdown esperado é -33.333% (pior queda em relação ao pico de 120)
      expect(metrics.maxDrawdown, closeTo(-33.333, 0.01));
    });

    test('Zero volatility handles flat curve correctly', () {
      final List<double> values = [100.0, 100.0, 100.0, 100.0];

      final metrics = RiskMetrics.calculate(values, 0.0);

      expect(metrics.volatility, equals(0.0));
      expect(metrics.sharpe, equals(0.0));
      expect(metrics.maxDrawdown, equals(0.0));
    });

    test('Calculates Volatility and Sharpe ratio under standard growth', () {
      // Curva de crescimento com alguma volatilidade
      final List<double> values = [100.0, 102.0, 101.0, 104.0, 103.0, 107.0];
      final double cagr = 15.0; // 15% CAGR

      final metrics = RiskMetrics.calculate(values, cagr);

      // Volatilidade deve ser positiva
      expect(metrics.volatility, greaterThan(0.0));
      
      // Sharpe deve ser calculado de acordo com a fórmula: (cagr - 6.0) / volatility
      final double expectedSharpe = (cagr - 6.0) / metrics.volatility;
      expect(metrics.sharpe, closeTo(expectedSharpe, 0.001));
      
      // Max Drawdown deve ser -0.98% (queda de 102 para 101) e -0.96% (queda de 104 para 103)
      // Pior queda: de 102 para 101 -> (101 - 102) / 102 = -0.98%
      expect(metrics.maxDrawdown, closeTo(-0.980, 0.01));
    });
  });
}
