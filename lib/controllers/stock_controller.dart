import '../models/stock.dart';
import '../models/exceptions.dart';
import '../services/stock_service.dart';
import 'base_controller.dart';

/// Controller responsável pela lógica de busca e gerenciamento de ações
class StockController extends BaseController {
  final StockService _stockService = StockService();
  
  List<StockPrice> _stocks = [];
  
  List<StockPrice> get stocks => _stocks;

  /// Busca ações pelo ticker
  Future<void> fetchStocks(String ticker) async {
    final trimmedTicker = ticker.trim().toUpperCase();
    
    if (trimmedTicker.isEmpty) {
      setError('Por favor, digite um ticker');
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
      setError('❌ Erro desconhecido: $e');
      setLoading(false);
    }
  }

  /// Limpa a lista de ações
  void clearStocks() {
    _stocks = [];
    notifyListeners();
  }
}
