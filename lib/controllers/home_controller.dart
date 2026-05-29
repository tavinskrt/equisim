import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/stock_service.dart';
import '../models/exceptions.dart';

/// Controlador que gerencia as interações, estados e validações na tela inicial da aplicação.
class HomeController extends ChangeNotifier {
  String stockTicker = '';
  String fiiTicker = '';
  DateTime? startDate;
  DateTime? endDate;
  String aporte = '';
  String valuation = 'graham'; // Estratégias disponíveis: 'graham', 'bazin', 'lynch'
  String margem = '20'; // Margem de segurança padrão para o cálculo de Graham (20%)
  int diaCompra = 5; // Dia do aporte mensal padrão (dia 5)
  bool considerarReinvestimento = true; // Se ativado, os dividendos recebidos são reinvestidos

  List<String> allStocks = [];
  List<String> allFiis = [];
  bool isLoadingTickers = false;

  String? stockError;
  String? fiiError;
  String? renamedMessage;

  /// Limpa a mensagem temporária de alteração de ticker.
  void clearRenamedMessage() {
    renamedMessage = null;
  }

  HomeController() {
    loadTickers();
  }

  bool _isFetchingDates = false;
  bool get isFetchingDates => _isFetchingDates;

  /// Define o ticker da Ação e aciona a busca de datas válidas de mercado.
  void setStockTicker(String value) {
    stockTicker = value.toUpperCase().trim();
    notifyListeners();
    _checkAndUpdateDates();
  }

  /// Define o ticker do FII e aciona a busca de datas válidas de mercado.
  void setFiiTicker(String value) {
    fiiTicker = value.toUpperCase().trim();
    notifyListeners();
    _checkAndUpdateDates();
  }

  /// Define a data de início da simulação.
  void setStartDate(DateTime date) {
    startDate = date;
    notifyListeners();
  }

  /// Define a data final da simulação.
  void setEndDate(DateTime date) {
    endDate = date;
    notifyListeners();
  }

  /// Define e formata monetariamente o valor do aporte mensal digitado.
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

  /// Define a estratégia de valuation selecionada pelo usuário.
  void setValuation(String methodId) {
    valuation = methodId;
    notifyListeners();
  }

  /// Define e valida a margem de segurança configurada.
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

  /// Define o dia do mês selecionado para compras e aportes.
  void setDiaCompra(int day) {
    if (day >= 1 && day <= 28) {
      diaCompra = day;
      notifyListeners();
    }
  }

  /// Define se os proventos mensais serão aplicados para aquisição de novos ativos.
  void setConsiderarReinvestimento(bool value) {
    considerarReinvestimento = value;
    notifyListeners();
  }

  /// Retorna o valor do aporte em formato numérico flutuante.
  double get doubleAporte {
    final cleaned = aporte.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }

  /// Retorna a margem de segurança em formato numérico flutuante.
  double get doubleMargem {
    return double.tryParse(margem) ?? 0.0;
  }

  /// Executa uma validação rápida de consistência dos dados do formulário.
  bool get isValid {
    if (stockTicker.isEmpty || fiiTicker.isEmpty) return false;
    if (startDate == null || endDate == null) return false;
    if (doubleAporte <= 0) return false;
    
    final now = DateTime.now();
    final tenYearsAgo = DateTime(now.year - 10, now.month, now.day);
    if (startDate!.isBefore(tenYearsAgo)) return false;
    if (startDate!.isAfter(endDate!)) return false;

    if (valuation == 'graham' && doubleMargem <= 0) return false;

    return true;
  }

  /// Valida as regras do formulário e retorna uma mensagem descritiva em caso de inconsistência.
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

  /// Busca as datas limites válidas com base no histórico de preços e criação de ambos os ativos informados.
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

      // Valida se o ativo foi renomeado (ex: VVAR3 -> VIIA3 -> BHIA3)
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
        debugPrint('Falha ao validar histórico da ação: $e');
      }

      // Valida se o fundo imobiliário é existente
      try {
        await stockService.fetchFiiFundamentals(currentFii);
      } on NotFoundException {
        fiiError = "FII não encontrado ou inexistente.";
        _isFetchingDates = false;
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('Falha ao validar FII: $e');
      }

      // Evita atualizações duplicadas se os inputs foram alterados durante a requisição
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

      // Define a data inicial ideal alinhando a listagem mais jovem de ambos os ativos
      final calculatedStartDate = stockClamped.isAfter(fiiClamped) ? stockClamped : fiiClamped;

      startDate = calculatedStartDate;
      endDate = today;
    } catch (e) {
      debugPrint('Falha crítica ao definir intervalos de datas: $e');
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

  /// Busca a lista total de tickers de ações e FIIs da B3 de forma paralela.
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
      debugPrint('✅ Tickers carregados com sucesso! Ações: ${allStocks.length}, FIIs: ${allFiis.length}');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar tickers do servidor: $e');
    } finally {
      isLoadingTickers = false;
      notifyListeners();
    }
  }
}
