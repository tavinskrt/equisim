import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/stock_service.dart';
import '../models/exceptions.dart';

class HomeController extends ChangeNotifier {
  String stockTicker = '';
  String fiiTicker = '';
  DateTime? startDate;
  DateTime? endDate;
  String aporte = '';
  String valuation = 'graham'; // 'graham', 'bazin', 'lynch'
  String margem = '20'; // default margem de segurança de Graham (20%)
  int diaCompra = 5; // default dia 5
  bool considerarReinvestimento = true; // default ativo

  List<String> allStocks = [];
  List<String> allFiis = [];
  bool isLoadingTickers = false;

  String? stockError;
  String? fiiError;
  String? renamedMessage;

  void clearRenamedMessage() {
    renamedMessage = null;
  }

  HomeController() {
    loadTickers();
  }

  bool _isFetchingDates = false;
  bool get isFetchingDates => _isFetchingDates;

  void setStockTicker(String value) {
    stockTicker = value.toUpperCase().trim();
    notifyListeners();
    _checkAndUpdateDates();
  }

  void setFiiTicker(String value) {
    fiiTicker = value.toUpperCase().trim();
    notifyListeners();
    _checkAndUpdateDates();
  }

  void setStartDate(DateTime date) {
    startDate = date;
    notifyListeners();
  }

  void setEndDate(DateTime date) {
    endDate = date;
    notifyListeners();
  }

  void setAporte(String value) {
    String num = value.replaceAll(RegExp(r'\D'), '');
    if (num.isEmpty) {
      aporte = '';
    } else {
      int cents = int.parse(num);
      double val = cents / 100;
      final formatCurrency = NumberFormat.currency(locale: "pt_BR", symbol: "");
      aporte = formatCurrency.format(val).trim();
    }
    notifyListeners();
  }

  void setValuation(String methodId) {
    valuation = methodId;
    notifyListeners();
  }

  void setMargem(String value) {
    String raw = value.replaceAll(RegExp(r'\D'), '');
    if (raw.isNotEmpty) {
      int m = int.parse(raw);
      if (m > 100) return;
      margem = m.toString();
    } else {
      margem = '';
    }
    notifyListeners();
  }

  void setDiaCompra(int day) {
    if (day >= 1 && day <= 28) {
      diaCompra = day;
      notifyListeners();
    }
  }

  void setConsiderarReinvestimento(bool value) {
    considerarReinvestimento = value;
    notifyListeners();
  }

  // Getters auxiliares para conversão de tipos
  double get doubleAporte {
    final cleaned = aporte.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }

  double get doubleMargem {
    return double.tryParse(margem) ?? 0.0;
  }

  bool get isValid {
    if (stockTicker.isEmpty || fiiTicker.isEmpty) return false;
    if (startDate == null || endDate == null) return false;
    if (doubleAporte <= 0) return false;
    
    // Período máximo de 10 anos atrás comparando com hoje
    final now = DateTime.now();
    final tenYearsAgo = DateTime(now.year - 10, now.month, now.day);
    if (startDate!.isBefore(tenYearsAgo)) return false;
    if (startDate!.isAfter(endDate!)) return false;

    if (valuation == 'graham' && doubleMargem <= 0) return false;

    return true;
  }

  /// Retorna mensagem de erro se a validação falhar
  String? getValidationError() {
    if (stockTicker.isEmpty) return 'Informe o ticker da Ação.';
    if (fiiTicker.isEmpty) return 'Informe o ticker do FII.';
    if (startDate == null) return 'Selecione a Data Inicial.';
    if (endDate == null) return 'Selecione a Data Final.';
    if (doubleAporte <= 0) return 'Informe o valor do Aporte Mensal.';
    
    final now = DateTime.now();
    final tenYearsAgo = DateTime(now.year - 10, now.month, now.day);
    if (startDate!.isBefore(tenYearsAgo)) {
      return 'A data inicial não pode ser superior a 10 anos atrás.';
    }
    if (startDate!.isAfter(endDate!)) {
      return 'A data inicial deve ser anterior à data final.';
    }

    if (valuation == 'graham' && doubleMargem <= 0) {
      return 'Informe uma Margem de Segurança válida.';
    }
    return null;
  }

  Future<void> _checkAndUpdateDates() async {
    if (stockTicker.length < 5 || fiiTicker.length < 5) return;

    final currentStock = stockTicker;
    final currentFii = fiiTicker;
    String resolvedStock = currentStock;
    String resolvedFii = currentFii;

    _isFetchingDates = true;
    stockError = null;
    fiiError = null;
    notifyListeners();

    try {
      final stockService = StockService();

      // 1. Validar histórico do Stock
      try {
        final history = await stockService.fetchTickerHistory(currentStock);
        if (history != null) {
          final currentTicker = history['current_ticker'] as String?;
          if (currentTicker != null && currentTicker != currentStock) {
            resolvedStock = currentTicker;
            renamedMessage = "O ativo '$currentStock' foi renomeado para '$currentTicker' e atualizado automaticamente.";
            stockTicker = currentTicker;
            notifyListeners();
          }
        }
      } on NotFoundException {
        stockError = "Ação não encontrada ou inexistente.";
        _isFetchingDates = false;
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('Erro ao validar histórico de stock: $e');
      }

      // 2. Validar FII
      try {
        await stockService.fetchFiiFundamentals(currentFii);
      } on NotFoundException {
        fiiError = "FII não encontrado ou inexistente.";
        _isFetchingDates = false;
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('Erro ao validar FII: $e');
      }

      // Se o usuário mudou o ticker no meio do caminho para algo diferente do resolvido, ignora
      if ((stockTicker != currentStock && stockTicker != resolvedStock) ||
          (fiiTicker != currentFii && fiiTicker != resolvedFii)) {
        return;
      }

      final results = await Future.wait([
        stockService.fetchStocksPrice(resolvedStock),
        stockService.fetchStocksPrice(resolvedFii),
      ]);

      if ((stockTicker != currentStock && stockTicker != resolvedStock) ||
          (fiiTicker != currentFii && fiiTicker != resolvedFii)) {
        return;
      }

      final stockPrices = results[0];
      final fiiPrices = results[1];

      if (stockPrices.isEmpty || fiiPrices.isEmpty) return;

      stockPrices.sort((a, b) => a.date.compareTo(b.date));
      fiiPrices.sort((a, b) => a.date.compareTo(b.date));

      final stockCreationDate = DateTime.parse(stockPrices.first.date);
      final fiiCreationDate = DateTime.parse(fiiPrices.first.date);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tenYearsAgo = DateTime(now.year - 10, now.month, now.day);

      final stockClamped = stockCreationDate.isBefore(tenYearsAgo) ? tenYearsAgo : stockCreationDate;
      final fiiClamped = fiiCreationDate.isBefore(tenYearsAgo) ? tenYearsAgo : fiiCreationDate;

      final calculatedStartDate = stockClamped.isAfter(fiiClamped) ? stockClamped : fiiClamped;

      startDate = calculatedStartDate;
      endDate = today;
    } catch (e) {
      debugPrint('Error fetching ticker dates: $e');
      if (e.toString().contains('NotFoundException') || e.toString().contains('não encontrado')) {
        stockError = "Erro ao buscar dados históricos do ativo.";
      }
    } finally {
      if ((stockTicker == currentStock || stockTicker == resolvedStock) &&
          (fiiTicker == currentFii || fiiTicker == resolvedFii)) {
        _isFetchingDates = false;
        notifyListeners();
      }
    }
  }

  /// Carrega os tickers de Ações e FIIs em background usando Future.wait para paralelismo.
  Future<void> loadTickers() async {
    isLoadingTickers = true;
    notifyListeners();
    try {
      final stockService = StockService();
      final results = await Future.wait([
        stockService.fetchAllStockTickers(),
        stockService.fetchAllFiiTickers(),
      ]);
      allStocks = results[0];
      allFiis = results[1];
      debugPrint('✅ Tickers carregados em background! Ações: ${allStocks.length}, FIIs: ${allFiis.length}');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar tickers em background: $e');
    } finally {
      isLoadingTickers = false;
      notifyListeners();
    }
  }
}
