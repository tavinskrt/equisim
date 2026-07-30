import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';
import '../models/fii.dart';
import '../models/dividend.dart';
import '../models/corporate_event.dart';
import '../models/exceptions.dart';

/// Serviço responsável por realizar as chamadas de rede à API brapi.dev (v2).
class StockService {
  static List<String>? _cachedStockTickers;
  static List<String>? _cachedFiiTickers;

  /// Método padrão de requisição GET à API brapi.dev com tratamento de autenticação e erros.
  Future<dynamic> _getRequest(String endpoint) async {
    final token = dotenv.env['BRAPI_TOKEN'] ??
        dotenv.env['BOLSAI_API_KEY'] ??
        dotenv.env['BRAPI_API_KEY'];
    final baseUrl = dotenv.env['BRAPI_BASE_URL'] ?? 'https://brapi.dev/api';

    var url = Uri.parse('$baseUrl$endpoint');
    if (kIsWeb) {
      url = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent('$baseUrl$endpoint')}');
    }
    debugPrint('🔗 Requisitando URL Brapi: $url');

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }

    try {
      final response = await http.get(
        url,
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      debugPrint('📊 Código de Status HTTP: ${response.statusCode}');

      switch (response.statusCode) {
        case 200:
          return jsonDecode(response.body);
        case 401:
          throw AuthenticationException(
            message: 'Token de API da brapi.dev inválido, ausente ou não autorizado para este ativo.',
            originalError: response.body,
          );
        case 404:
        case 422:
          throw NotFoundException(
            message: 'Ativo não encontrado na brapi.dev.',
            originalError: response.body,
          );
        case 429:
          throw ServerException(
            message: 'Limite de requisições excedido na brapi.dev. Aguarde um momento.',
            originalError: response.body,
          );
        case 500:
        case 502:
        case 503:
          throw ServerException(
            message: 'Servidor brapi.dev indisponível no momento. Tente novamente mais tarde.',
            originalError: response.body,
          );
        default:
          throw ServerException(
            message: 'Erro HTTP inesperado ${response.statusCode}: ${response.body}',
            originalError: response.body,
          );
      }
    } on http.ClientException catch (e) {
      debugPrint('❌ Erro HTTP de rede: $e');
      throw NetworkException(
        message: 'Erro de conexão com a brapi.dev: ${e.message}',
        originalError: e,
      );
    } on TimeoutException catch (e) {
      debugPrint('❌ Tempo limite de requisição esgotado: $e');
      throw TimeoutException(
        originalError: e,
      );
    } catch (e) {
      debugPrint('❌ Erro inesperado ao realizar chamada HTTP: $e');
      rethrow;
    }
  }

  /// Extrai a lista de objetos 'results' da resposta padrão da brapi.dev.
  List<dynamic> _extractResults(dynamic data) {
    if (data is Map<String, dynamic> && data.containsKey('results')) {
      final res = data['results'];
      if (res is List) return res;
    }
    return [];
  }

  /// Busca o histórico de preços completo de um determinado ticker via /v2/stocks/historical.
  Future<List<StockPrice>> fetchStocksPrice(String ticker, {int limit = 3000}) async {
    try {
      final data = await _getRequest('/v2/stocks/historical?symbols=$ticker&range=10y&interval=1d');
      final results = _extractResults(data);
      if (results.isEmpty) {
        throw ValidationException(
          message: 'Nenhum dado de cotação disponível para o ativo $ticker.',
        );
      }

      final firstResult = results.first as Map<String, dynamic>;
      final resultData = firstResult['data'] as Map<String, dynamic>? ?? firstResult;
      final prices = (resultData['historicalDataPrice'] ?? resultData['prices']) as List<dynamic>?;

      if (prices == null || prices.isEmpty) {
        throw ValidationException(
          message: 'Nenhum histórico de cotações encontrado para $ticker.',
        );
      }

      return prices
          .map((item) => StockPrice.fromJson(item as Map<String, dynamic>))
          .toList();
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar cotações históricas de $ticker: $e',
        originalError: e,
      );
    }
  }

  /// Busca os fundamentos completos de uma Ação corporativa da B3 na brapi.dev.
  Future<StockFundamentals> fetchStockFundamentals(String ticker) async {
    try {
      final Map<String, dynamic> mergedData = {};

      // Busca indicadores estatísticos
      try {
        final statsData = await _getRequest('/v2/stocks/statistics?symbols=$ticker&mode=current');
        final results = _extractResults(statsData);
        if (results.isNotEmpty) {
          final item = results.first as Map<String, dynamic>;
          final itemData = item['data'] as Map<String, dynamic>? ?? item;
          mergedData.addAll(itemData);
        }
      } catch (e) {
        debugPrint('⚠️ Aviso: estatísticas de $ticker não retornadas: $e');
      }

      // Busca dados financeiros (receita, lucro, dividas, margens)
      try {
        final finData = await _getRequest('/v2/stocks/financial-data?symbols=$ticker&mode=current');
        final results = _extractResults(finData);
        if (results.isNotEmpty) {
          final item = results.first as Map<String, dynamic>;
          final itemData = item['data'] as Map<String, dynamic>? ?? item;
          mergedData.addAll(itemData);
        }
      } catch (e) {
        debugPrint('⚠️ Aviso: dados financeiros de $ticker não retornados: $e');
      }

      // Busca snapshot de cotação complementar
      try {
        final quoteData = await _getRequest('/v2/stocks/quote?symbols=$ticker');
        final results = _extractResults(quoteData);
        if (results.isNotEmpty) {
          final item = results.first as Map<String, dynamic>;
          final itemData = item['data'] as Map<String, dynamic>? ?? item;
          mergedData.addAll(itemData);
        }
      } catch (e) {
        debugPrint('⚠️ Aviso: cotação atual de $ticker não retornada: $e');
      }

      if (mergedData.isEmpty) {
        throw ValidationException(
          message: 'Fundamentos de ação indisponíveis para $ticker.',
        );
      }

      return StockFundamentals.fromJson(mergedData);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar fundamentos de $ticker: $e',
        originalError: e,
      );
    }
  }

  /// Busca os fundamentos completos de um Fundo Imobiliário (FII).
  Future<FiiFundamentals> fetchFiiFundamentals(String ticker) async {
    try {
      final Map<String, dynamic> mergedData = {'ticker': ticker, 'symbol': ticker};

      // Tenta buscar o endpoint especializado de indicadores de FIIs
      try {
        final fiiData = await _getRequest('/v2/fii/indicators?symbols=$ticker');
        final results = _extractResults(fiiData);
        if (results.isNotEmpty) {
          final item = results.first as Map<String, dynamic>;
          final itemData = item['data'] as Map<String, dynamic>? ?? item;
          mergedData.addAll(itemData);
        }
      } catch (e) {
        debugPrint('⚠️ Endpoint /v2/fii/indicators indisponível ou restrito para $ticker, usando fallback de stocks: $e');
      }

      // Fallback para cotação e estatísticas básicas de ativos da brapi
      if (!mergedData.containsKey('closePrice') && !mergedData.containsKey('regularMarketPrice')) {
        try {
          final quoteData = await _getRequest('/v2/stocks/quote?symbols=$ticker');
          final results = _extractResults(quoteData);
          if (results.isNotEmpty) {
            final item = results.first as Map<String, dynamic>;
            final itemData = item['data'] as Map<String, dynamic>? ?? item;
            mergedData.addAll(itemData);
          }
        } catch (e) {
          debugPrint('⚠️ Falha ao buscar cotação de fallback do FII $ticker: $e');
        }

        try {
          final statsData = await _getRequest('/v2/stocks/statistics?symbols=$ticker&mode=current');
          final results = _extractResults(statsData);
          if (results.isNotEmpty) {
            final item = results.first as Map<String, dynamic>;
            final itemData = item['data'] as Map<String, dynamic>? ?? item;
            mergedData.addAll(itemData);
          }
        } catch (e) {
          debugPrint('⚠️ Falha ao buscar estatísticas de fallback do FII $ticker: $e');
        }
      }

      return FiiFundamentals.fromJson(mergedData);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar fundamentos do FII $ticker: $e',
        originalError: e,
      );
    }
  }

  /// Busca o histórico completo de dividendos de um determinado ativo via /v2/stocks/dividends ou /v2/fii/dividends.
  Future<DividendHistory> fetchDividends(String ticker, {int limit = 10}) async {
    List<dynamic>? dividendsList;

    List<dynamic>? extractDividendsList(dynamic data) {
      if (data is! Map<String, dynamic>) return null;
      List<dynamic>? found;
      if (data.containsKey('results') && data['results'] is List) {
        final results = data['results'] as List;
        if (results.isNotEmpty && results.first is Map<String, dynamic>) {
          final firstResult = results.first as Map<String, dynamic>;
          final resultData = firstResult['data'] as Map<String, dynamic>? ?? firstResult;
          found = (resultData['cashDividends'] ??
              resultData['dividends'] ??
              resultData['payments'] ??
              resultData['earnings']) as List<dynamic>?;
        }
      }
      found ??= (data['cashDividends'] ??
          data['dividends'] ??
          data['payments'] ??
          data['earnings']) as List<dynamic>?;
      return (found != null && found.isNotEmpty) ? found : null;
    }

    // 1) Busca via endpoint de dividendos de ações /v2/stocks/dividends
    try {
      final data = await _getRequest('/v2/stocks/dividends?symbols=$ticker');
      dividendsList = extractDividendsList(data);
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar /v2/stocks/dividends para $ticker: $e');
    }

    // 2) Caso não encontre dividendos em stocks, tenta via /v2/fii/dividends
    if (dividendsList == null || dividendsList.isEmpty) {
      try {
        final fiiData = await _getRequest('/v2/fii/dividends?symbols=$ticker');
        dividendsList = extractDividendsList(fiiData);
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar /v2/fii/dividends para $ticker: $e');
      }
    }

    if (dividendsList == null || dividendsList.isEmpty) {
      return DividendHistory(
        dividends: [],
        totalAnnualDividend: 0,
        averageDividend: 0,
      );
    }

    try {
      final dividends = dividendsList
          .map((item) => Dividend.fromJson(item as Map<String, dynamic>))
          .where((d) => d.value > 0 && d.paymentDate.isNotEmpty)
          .toList();

      return DividendHistory.fromDividends(dividends);
    } catch (e) {
      debugPrint('⚠️ Erro ao estruturar histórico de dividendos de $ticker: $e');
      return DividendHistory(
        dividends: [],
        totalAnnualDividend: 0,
        averageDividend: 0,
      );
    }
  }

  /// Busca a lista de eventos corporativos (desdobramentos e bonificações) de um ticker.
  Future<List<CorporateEvent>> fetchCorporateEvents(String ticker) async {
    try {
      final data = await _getRequest('/v2/stocks/dividends?symbols=$ticker');
      final results = _extractResults(data);
      if (results.isEmpty) return [];

      final firstResult = results.first as Map<String, dynamic>;
      final resultData = firstResult['data'] as Map<String, dynamic>? ?? firstResult;
      final stockDividends = resultData['stockDividends'] as List<dynamic>?;
      if (stockDividends == null || stockDividends.isEmpty) {
        return [];
      }

      return stockDividends
          .map((item) => CorporateEvent.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar eventos corporativos de $ticker: $e');
      return [];
    }
  }

  static const List<String> _stockUnitsWhitelist = [
    'ALUP11', 'BPAC11', 'CPLE11', 'ENGI11', 'JALL11', 'KLBN11', 'PPLA11',
    'RNEW11', 'SANB11', 'SAPR11', 'TAEE11', 'UNIP11'
  ];

  /// Busca o histórico de renomeações de tickers para correção de ativos migrados da B3.
  Future<Map<String, dynamic>?> fetchTickerHistory(String ticker) async {
    try {
      final data = await _getRequest('/v2/tickers/resolve?symbol=$ticker');
      final results = _extractResults(data);
      if (results.isNotEmpty) {
        final item = results.first as Map<String, dynamic>;
        final String resolved = item['symbol'] as String? ?? ticker;
        final bool changed = item['changed'] as bool? ?? false;
        if (changed && resolved != ticker) {
          return {
            'old_ticker': ticker,
            'current_ticker': resolved,
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar resolução de ticker para $ticker: $e');
      return null;
    }
  }

  /// Busca todos os tickers de Ações da B3 via /v2/tickers.
  Future<List<String>> fetchAllStockTickers() async {
    if (_cachedStockTickers != null) {
      return _cachedStockTickers!;
    }
    try {
      final data = await _getRequest('/v2/tickers?type=stock&limit=1000');
      final results = _extractResults(data);

      final stockFormat = RegExp(r'^[A-Z]{4}(3|4|5|6|7|8|11)$');

      final tickers = results
          .map((item) => (item['symbol'] as String? ?? ''))
          .where((t) => t.isNotEmpty && !t.contains(' '))
          .map((t) => t.trim().toUpperCase())
          .where((t) {
            if (!stockFormat.hasMatch(t)) return false;
            if (t.endsWith('11')) {
              return _stockUnitsWhitelist.contains(t);
            }
            return true;
          })
          .toList();

      // Fallback para tickers principais em caso de ambiente sem token ou resposta vazia
      if (tickers.isEmpty) {
        tickers.addAll(['PETR4', 'VALE3', 'MGLU3', 'ITUB4', 'BBAS3', 'BBDC4', 'WEGE3']);
      }

      tickers.sort();
      _cachedStockTickers = tickers.toSet().toList();
      return _cachedStockTickers!;
    } catch (e) {
      debugPrint('⚠️ Falha ao carregar lista de ações da brapi.dev: $e');
      return ['PETR4', 'VALE3', 'MGLU3', 'ITUB4', 'BBAS3', 'BBDC4', 'WEGE3'];
    }
  }

  /// Busca todos os tickers de Fundos Imobiliários da B3 via /v2/tickers.
  Future<List<String>> fetchAllFiiTickers() async {
    if (_cachedFiiTickers != null) {
      return _cachedFiiTickers!;
    }
    try {
      final data = await _getRequest('/v2/tickers?type=fund&subType=fii&limit=1000');
      final results = _extractResults(data);

      final fiiFormat = RegExp(r'^[A-Z]{4}11$');

      final tickers = results
          .map((item) => (item['symbol'] as String? ?? ''))
          .where((t) => t.isNotEmpty && !t.contains(' '))
          .map((t) => t.trim().toUpperCase())
          .where((t) => fiiFormat.hasMatch(t))
          .toList();

      // Fallback para FIIs principais no sandbox / sem token
      if (tickers.isEmpty) {
        tickers.addAll(['MXRF11', 'HGLG11', 'XPML11', 'KNCR11', 'BCSC11']);
      }

      tickers.sort();
      _cachedFiiTickers = tickers.toSet().toList();
      return _cachedFiiTickers!;
    } catch (e) {
      debugPrint('⚠️ Falha ao carregar lista de FIIs da brapi.dev: $e');
      return ['MXRF11', 'HGLG11', 'XPML11', 'KNCR11', 'BCSC11'];
    }
  }
}