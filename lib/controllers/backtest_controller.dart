import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/backtest.dart';
import '../services/backtest_engine.dart';
import '../services/backtest_history_service.dart';

/// Controlador responsável pelo gerenciamento de estado das simulações de backtest e histórico.
class BacktestController extends ChangeNotifier {
  final BacktestHistoryService _historyService = BacktestHistoryService();
  bool _isLoading = false;
  BacktestResult? _lastResult;
  List<Map<String, dynamic>> _savedBacktests = [];
  bool _loadingHistory = false;

  /// Retorna se há um backtest ativo sendo processado em segundo plano.
  bool get isLoading => _isLoading;

  /// Retorna o último resultado de simulação gerado.
  BacktestResult? get lastResult => _lastResult;

  /// Retorna a lista de backtests salvos no histórico do usuário.
  List<Map<String, dynamic>> get savedBacktests => _savedBacktests;

  /// Retorna se o histórico está sendo carregado do Firestore.
  bool get loadingHistory => _loadingHistory;

  /// Executa o processamento do backtest histórico assincronamente e salva no Firestore.
  Future<bool> executeBacktest(BacktestConfig config) async {
    if (_isLoading) return false;
    _isLoading = true;
    notifyListeners();

    try {
      final engine = BacktestEngine();
      final result = await engine.runBacktest(config);
      _lastResult = result;

      // Salva no Firebase de forma compacta e segura se o usuário estiver logado
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _historyService.saveBacktest(user.uid, result);
        // Atualiza a lista local em segundo plano
        fetchHistory();
      }

      return true;
    } catch (e) {
      debugPrint('Falha ao processar simulação de backtest: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Recupera o histórico de simulações do usuário logado do Firestore.
  Future<void> fetchHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _savedBacktests = [];
      notifyListeners();
      return;
    }

    _loadingHistory = true;
    notifyListeners();

    try {
      _savedBacktests = await _historyService.getHistory(user.uid);
    } catch (e) {
      debugPrint('Falha ao buscar histórico de backtests: $e');
    } finally {
      _loadingHistory = false;
      notifyListeners();
    }
  }

  /// Exclui um backtest específico do histórico no Firestore e da lista local.
  Future<bool> deleteBacktest(String backtestId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await _historyService.deleteBacktest(backtestId, user.uid);
      // Otimista: remove localmente para resposta rápida na interface
      _savedBacktests.removeWhere((bt) => bt['id'] == backtestId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Falha ao deletar backtest do histórico: $e');
      return false;
    }
  }

  /// Limpa o histórico do último resultado armazenado localmente.
  void clearResult() {
    _lastResult = null;
    notifyListeners();
  }
}