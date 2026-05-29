import 'package:flutter/foundation.dart';
import '../models/backtest.dart';
import '../services/backtest_engine.dart';

/// Controlador responsável pelo gerenciamento de estado das simulações de backtest.
class BacktestController extends ChangeNotifier {
  bool _isLoading = false;
  BacktestResult? _lastResult;

  /// Retorna se há um backtest ativo sendo processado em segundo plano.
  bool get isLoading => _isLoading;

  /// Retorna o último resultado de simulação gerado.
  BacktestResult? get lastResult => _lastResult;

  /// Executa o processamento do backtest histórico assincronamente.
  Future<bool> executeBacktest(BacktestConfig config) async {
    _isLoading = true;
    notifyListeners();

    try {
      final engine = BacktestEngine();
      final result = await engine.runBacktest(config);
      _lastResult = result;
      return true;
    } catch (e) {
      debugPrint('Falha ao processar simulação de backtest: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpa o histórico do último resultado armazenado localmente.
  void clearResult() {
    _lastResult = null;
    notifyListeners();
  }
}