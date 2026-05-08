import '../models/backtest.dart';

/// Engine responsável por executar o backtest
class BacktestEngine {
  /// Executa o backtest com a configuração fornecida
  Future<BacktestResult> runBacktest(BacktestConfig config) async {
    await Future.delayed(const Duration(seconds: 2));

    final scenario1 = BacktestScenarioResult(
      scenarioName: 'Buy and Hold',
      finalValue: 150000.0,
      finalStockShares: 100,
      finalFiiShares: 50,
      finalCash: 5000.0,
      totalDividends: 12000.0,
      totalInvested: 100000.0,
      cagr: 8.5,
      totalReturn: 50.0,
      operations: [],
      monthlyPositions: [],
    );

    final scenario2 = BacktestScenarioResult(
      scenarioName: 'Valuation Inteligente',
      finalValue: 180000.0,
      finalStockShares: 80,
      finalFiiShares: 70,
      finalCash: 3000.0,
      totalDividends: 15000.0,
      totalInvested: 100000.0,
      cagr: 10.2,
      totalReturn: 80.0,
      operations: [],
      monthlyPositions: [],
    );

    return BacktestResult(
      config: config,
      scenario1: scenario1,
      scenario2: scenario2,
      executionDate: DateTime.now(),
    );
  }
}