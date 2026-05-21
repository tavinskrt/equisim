import '../models/stock.dart';
import '../models/fii.dart';
import '../models/dividend.dart';
import '../models/exceptions.dart';
import '../services/stock_service.dart';
import '../services/fii_service.dart';
import 'base_controller.dart';

/// Controller responsável pela lógica de busca e gerenciamento de ativos (ações e FIIs)
class AssetController extends BaseController {
  final StockService _stockService = StockService();
  final FiiService _fiiService = FiiService();

  List<StockPrice> _stockPrices = [];
  List<FiiPrice> _fiiPrices = [];
  StockFundamentals? _stockFundamentals;
  FiiFundamentals? _fiiFundamentals;
  DividendHistory? _stockDividendHistory;
  DividendHistory? _fiiDividendHistory;

  List<StockPrice> get stockPrices => _stockPrices;
  List<FiiPrice> get fiiPrices => _fiiPrices;
  StockFundamentals? get stockFundamentals => _stockFundamentals;
  FiiFundamentals? get fiiFundamentals => _fiiFundamentals;
  DividendHistory? get stockDividendHistory => _stockDividendHistory;
  DividendHistory? get fiiDividendHistory => _fiiDividendHistory;

  Future<void> _setLoadingAndClearError(Future<void> Function() action) async {
    clearError();
    setLoading(true);
    try {
      await action();
    } finally {
      setLoading(false);
    }
  }

  void _handleError(dynamic e) {
    if (e is NetworkException) {
      setError('🌐 ${e.message}');
    } else if (e is AuthenticationException) {
      setError('🔐 ${e.message}');
    } else if (e is NotFoundException) {
      setError('❌ ${e.message}');
    } else if (e is ValidationException) {
      setError('⚠️ ${e.message}');
    } else if (e is TimeoutException) {
      setError('⏱️ ${e.message}');
    } else if (e is AppException) {
      setError('❌ ${e.message}');
    } else {
      setError('❌ Erro desconhecido: $e');
    }
  }

  /// Busca histórico de preços de ações
  Future<void> fetchStockPrices(
    String ticker, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trimmedTicker = ticker.trim().toUpperCase();

    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker de ação');
      return;
    }

    await _setLoadingAndClearError(() async {
      try {
        _stockPrices = await _stockService.fetchStocksPrice(
          trimmedTicker,
          startDate: startDate,
          endDate: endDate,
        );
      } catch (e) {
        _handleError(e);
      }
    });
  }

  /// Busca fundamentos de ações
  Future<void> fetchStockFundamentals(String ticker) async {
    final trimmedTicker = ticker.trim().toUpperCase();

    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker de ação');
      return;
    }

    await _setLoadingAndClearError(() async {
      try {
        _stockFundamentals = await _stockService.fetchStockFundamentals(trimmedTicker);
      } catch (e) {
        _handleError(e);
      }
    });
  }

  /// Busca dividendos de ações
  Future<void> fetchStockDividends(
    String ticker, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trimmedTicker = ticker.trim().toUpperCase();

    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker de ação');
      return;
    }

    await _setLoadingAndClearError(() async {
      try {
        _stockDividendHistory = await _stockService.fetchDividends(
          trimmedTicker,
          startDate: startDate,
          endDate: endDate,
        );
      } catch (e) {
        _handleError(e);
      }
    });
  }

  /// Busca histórico de preços de FIIs
  Future<void> fetchFiiPrices(
    String ticker, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trimmedTicker = ticker.trim().toUpperCase();

    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker de FII');
      return;
    }

    await _setLoadingAndClearError(() async {
      try {
        _fiiPrices = await _fiiService.fetchFiiPriceHistory(
          trimmedTicker,
          startDate: startDate,
          endDate: endDate,
        );
      } catch (e) {
        _handleError(e);
      }
    });
  }

  /// Busca fundamentos de FIIs
  Future<void> fetchFiiFundamentals(String ticker) async {
    final trimmedTicker = ticker.trim().toUpperCase();

    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker de FII');
      return;
    }

    await _setLoadingAndClearError(() async {
      try {
        _fiiFundamentals = await _fiiService.fetchFiiFundamentals(trimmedTicker);
      } catch (e) {
        _handleError(e);
      }
    });
  }

  /// Busca dividendos de FIIs
  Future<void> fetchFiiDividends(
    String ticker, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trimmedTicker = ticker.trim().toUpperCase();

    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker de FII');
      return;
    }

    await _setLoadingAndClearError(() async {
      try {
        _fiiDividendHistory = await _fiiService.fetchFiiDividends(
          trimmedTicker,
          startDate: startDate,
          endDate: endDate,
        );
      } catch (e) {
        _handleError(e);
      }
    });
  }

  /// Limpa histórico de preços de ações
  void clearStockPrices() {
    _stockPrices = [];
    notifyListeners();
  }

  /// Limpa histórico de preços de FIIs
  void clearFiiPrices() {
    _fiiPrices = [];
    notifyListeners();
  }

  /// Limpa todos os dados de ativos
  void clearAll() {
    _stockPrices = [];
    _fiiPrices = [];
    _stockFundamentals = null;
    _fiiFundamentals = null;
    _stockDividendHistory = null;
    _fiiDividendHistory = null;
    notifyListeners();
  }
}
