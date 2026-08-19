import 'package:flutter/material.dart';
import '../services/stock_service.dart';

/// Controlador da tela inicial.
///
/// Reduzido na Fase 0 ao mínimo necessário para manter o shell da aplicação
/// funcional e verificar a conectividade com a brapi. O formulário de simulação
/// do escopo antigo (uma ação × um FII, valuation binário) foi removido.
///
/// Será substituído por providers Riverpod na Fase 3, quando entrar a
/// construção da dupla carteira.
class HomeController extends ChangeNotifier {
  final StockService _stockService = StockService();

  List<String> availableStocks = [];
  bool isLoadingTickers = false;
  String? loadError;

  HomeController() {
    loadTickers();
  }

  /// Carrega o universo de ações da B3 e serve de verificação de conectividade.
  Future<void> loadTickers() async {
    isLoadingTickers = true;
    loadError = null;
    notifyListeners();
    try {
      availableStocks = await _stockService.fetchAllStockTickers();
      debugPrint('✅ Universo carregado: ${availableStocks.length} ações.');
    } catch (e) {
      loadError = 'Não foi possível carregar o universo de ativos.';
      debugPrint('⚠️ Erro ao carregar tickers: $e');
    } finally {
      isLoadingTickers = false;
      notifyListeners();
    }
  }
}
