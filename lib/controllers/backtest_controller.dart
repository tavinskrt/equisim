import 'package:flutter/foundation.dart';
import '../models/backtest.dart';
import '../services/backtest_engine.dart';

/// Controller para gerenciar o estado do backtest
class BacktestController extends ChangeNotifier {
  bool _isLoading = false;
  BacktestResult? _lastResult;

  /// Indica se um backtest está em execução
  bool get isLoading => _isLoading;

  /// Último resultado de backtest executado
  BacktestResult? get lastResult => _lastResult;

  /// Executa um backtest com a configuração fornecida
  Future<bool> executeBacktest(BacktestConfig config) async {
    _isLoading = true;
    notifyListeners();

    try {
      final engine = BacktestEngine();
      final result = await engine.runBacktest(config);
      _lastResult = result;
      return true;
    } catch (e) {
      debugPrint('Erro ao executar backtest: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpa o último resultado
  void clearResult() {
    _lastResult = null;
    notifyListeners();
  }
}