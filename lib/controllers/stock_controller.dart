import '../models/stock.dart';
import '../models/exceptions.dart';
import '../services/stock_service.dart';
import 'base_controller.dart';

/// Controlador responsável pelo fluxo de pesquisa e dados das cotações.
class StockController extends BaseController {
  final StockService _stockService = StockService();
  
  List<StockPrice> _stocks = [];
  
  List<StockPrice> get stocks => _stocks;

  /// Realiza a busca histórica de preços de um ativo pelo seu ticker correspondente.
  Future<void> fetchStocks(String ticker) async {
    final trimmedTicker = ticker.trim().toUpperCase();
    
    if (trimmedTicker.isEmpty) {
      setError('Por favor, informe o ticker do ativo.');
      return;
    }

    clearError();
    setLoading(true);

    try {
      _stocks = await _stockService.fetchStocksPrice(trimmedTicker);
      setLoading(false);
    } on NetworkException catch (e) {
      setError('🌐 ${e.message}');
      setLoading(false);
    } on AuthenticationException catch (e) {
      setError('🔐 ${e.message}');
      setLoading(false);
    } on NotFoundException catch (e) {
      setError('❌ ${e.message}');
      setLoading(false);
    } on ValidationException catch (e) {
      setError('⚠️ ${e.message}');
      setLoading(false);
    } on TimeoutException catch (e) {
      setError('⏱️ ${e.message}');
      setLoading(false);
    } on AppException catch (e) {
      setError('❌ ${e.message}');
      setLoading(false);
    } catch (e) {
      setError('❌ Ocorreu um erro inesperado: $e');
      setLoading(false);
    }
  }

  /// Limpa a lista de cotações de ativos carregada em cache.
  void clearStocks() {
    _stocks = [];
    notifyListeners();
  }
}