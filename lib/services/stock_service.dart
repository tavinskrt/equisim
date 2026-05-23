import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';
import '../models/fii.dart';
import '../models/dividend.dart';
import '../models/corporate_event.dart';
import '../models/exceptions.dart';

class StockService {
  static List<String>? _cachedStockTickers;
  static List<String>? _cachedFiiTickers;

  // Método padrão para fazer requisições GET à API.
  Future<dynamic> _getRequest(String endpoint) async {
    final apiKey = dotenv.env['BOLSAI_API_KEY'];
    final baseUrl = dotenv.env['BOLSAI_BASE_URL'] ?? 'https://api.usebolsai.com/api/v1';

    if (apiKey == null || apiKey.isEmpty) {
      throw AuthenticationException(
        message: 'API KEY não configurada. Verifique o arquivo .env',
      );
    }
    
    var url = Uri.parse('$baseUrl$endpoint');
    if (kIsWeb) {
      url = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent('$baseUrl$endpoint')}');
    }
    debugPrint('🔗 URL requisição: $url');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-API-Key': apiKey,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('📊 Status code: ${response.statusCode}');
      
      switch (response.statusCode) {
        case 200:
          return jsonDecode(response.body);
        case 401:
          throw AuthenticationException(
            message: 'API KEY inválida ou expirada',
            originalError: response.body,
          );
        case 404:
        case 422:
          throw NotFoundException(
            message: 'Ticker não encontrado',
            originalError: response.body,
          );
        case 500:
        case 502:
        case 503:
          throw ServerException(
            message: 'Servidor indisponível. Tente novamente mais tarde',
            originalError: response.body,
          );
        default:
          throw ServerException(
            message: 'Erro HTTP ${response.statusCode}: ${response.body}',
            originalError: response.body,
          );
      }
    } on http.ClientException catch (e) {
      debugPrint('❌ Erro na requisição: $e');
      throw NetworkException(
        message: 'Erro de conexão: ${e.message}',
        originalError: e,
      );
    } on TimeoutException catch (e) {
      debugPrint('❌ Timeout: $e');
      throw TimeoutException(
        originalError: e,
      );
    } catch (e) {
      debugPrint('❌ Erro genérico: $e');
      rethrow;
    }
  }

  // Método específico para buscar o histórico de preços de um ticker.
  Future<List<StockPrice>> fetchStocksPrice(String ticker, {int limit = 3000}) async {
    try {
      final data = await _getRequest('/stocks/$ticker/history?limit=$limit');
      final prices = data['prices'] as List<dynamic>?;
      if (prices == null || prices.isEmpty) {
        throw ValidationException(
          message: 'Nenhum dado disponível para o ticker $ticker',
        );
      }

      return prices
          .map((item) => StockPrice.fromJson(item as Map<String, dynamic>))
          .toList();
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar dados: $e',
        originalError: e,
      );
    }
  }

  // Método específico para buscar fundamentos COMPLETOS de um ticker.
  Future<StockFundamentals> fetchStockFundamentals(String ticker) async {
    try {
      final data = await _getRequest('/fundamentals/$ticker');
      
      if (data == null) {
        throw ValidationException(
          message: 'Dados de fundamentos não disponíveis para $ticker',
        );
      }

      return StockFundamentals.fromJson(data);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar fundamentos: $e',
        originalError: e,
      );
    }
  }

  // Método específico para buscar fundamentos de um Fundo Imobiliário (FII).
  Future<FiiFundamentals> fetchFiiFundamentals(String ticker) async {
    try {
      final data = await _getRequest('/fiis/$ticker');
      
      if (data == null) {
        throw ValidationException(
          message: 'Dados de FII não disponíveis para $ticker',
        );
      }

      return FiiFundamentals.fromJson(data);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar fundamentos de FII: $e',
        originalError: e,
      );
    }
  }

  // Método para buscar dividendos históricos
  Future<DividendHistory> fetchDividends(String ticker, {int limit = 10}) async {
    List<dynamic>? dividendsList;
    try {
      final data = await _getRequest('/dividends/$ticker?years=$limit');
      dividendsList = (data['payments'] ?? data['dividends'] ?? data['payments_history']) as List<dynamic>?;
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar dividendos padrão para $ticker: $e');
    }

    if (dividendsList == null || dividendsList.isEmpty) {
      try {
        final fiiLimit = (limit * 12).clamp(1, 120);
        final fiiData = await _getRequest('/fiis/$ticker/history?limit=$fiiLimit');
        dividendsList = fiiData['history'] as List<dynamic>?;
      } catch (e) {
        debugPrint('⚠️ Não foi possível buscar do endpoint de FII para $ticker: $e');
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
          .toList();

      return DividendHistory.fromDividends(dividends);
    } catch (e) {
      debugPrint('⚠️ Erro ao processar dividendos para $ticker: $e');
      return DividendHistory(
        dividends: [],
        totalAnnualDividend: 0,
        averageDividend: 0,
      );
    }
  }

  // Método específico para buscar eventos corporativos (splits e inplits) de um ticker.
  Future<List<CorporateEvent>> fetchCorporateEvents(String ticker) async {
    try {
      final data = await _getRequest('/stocks/$ticker/corporate-events');
      final events = data['events'] as List<dynamic>?;
      if (events == null || events.isEmpty) {
        return [];
      }
      return events
          .map((item) => CorporateEvent.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar eventos corporativos para $ticker: $e');
      return [];
    }
  }

  /// Busca todos os tickers de Ações da B3 com paginação e cache local.
  Future<List<String>> fetchAllStockTickers() async {
    if (_cachedStockTickers != null) {
      return _cachedStockTickers!;
    }
    try {
      // Busca a primeira leva (limite máximo permitido é 5000)
      final data = await _getRequest('/stocks/?limit=5000');
      final tickers = List<String>.from(data['tickers'] ?? []);
      final total = data['total'] as int? ?? 0;

      if (total > tickers.length) {
        // Busca o restante das levas com offset
        int offset = tickers.length;
        while (offset < total) {
          final nextData = await _getRequest('/stocks/?limit=5000&offset=$offset');
          final nextTickers = List<String>.from(nextData['tickers'] ?? []);
          if (nextTickers.isEmpty) break;
          tickers.addAll(nextTickers);
          offset += nextTickers.length;
        }
      }

      // Remove tickers inválidos (ex: com espaço) e filtra pra manter consistência
      final cleanTickers = tickers
          .where((t) => t.isNotEmpty && !t.contains(' '))
          .map((t) => t.trim().toUpperCase())
          .toList();

      cleanTickers.sort();
      _cachedStockTickers = cleanTickers;
      return _cachedStockTickers!;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar tickers de ações: $e');
      return [];
    }
  }

  /// Busca todos os tickers de FIIs da B3 com cache local.
  Future<List<String>> fetchAllFiiTickers() async {
    if (_cachedFiiTickers != null) {
      return _cachedFiiTickers!;
    }
    try {
      final data = await _getRequest('/fiis/?limit=1000');
      final List<dynamic> fiisList = data['fiis'] ?? [];
      final tickers = fiisList
          .map((item) => item['ticker'] as String? ?? '')
          .where((t) => t.isNotEmpty && !t.contains(' '))
          .map((t) => t.trim().toUpperCase())
          .toList();

      tickers.sort();
      _cachedFiiTickers = tickers;
      return _cachedFiiTickers!;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar tickers de FIIs: $e');
      return [];
    }
  }
}