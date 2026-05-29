import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';
import '../models/fii.dart';
import '../models/dividend.dart';
import '../models/corporate_event.dart';
import '../models/exceptions.dart';

/// Serviço responsável por realizar as chamadas de rede à API Bolsai.
class StockService {
  static List<String>? _cachedStockTickers;
  static List<String>? _cachedFiiTickers;

  /// Método padrão de requisição GET à API Bolsai com tratamento robusto de erros.
  Future<dynamic> _getRequest(String endpoint) async {
    final apiKey = dotenv.env['BOLSAI_API_KEY'];
    final baseUrl = dotenv.env['BOLSAI_BASE_URL'] ?? 'https://api.usebolsai.com/api/v1';

    if (apiKey == null || apiKey.isEmpty) {
      throw AuthenticationException(
        message: 'Chave de API não configurada. Verifique o arquivo .env.',
      );
    }
    
    var url = Uri.parse('$baseUrl$endpoint');
    if (kIsWeb) {
      url = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent('$baseUrl$endpoint')}');
    }
    debugPrint('🔗 Requisitando URL: $url');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-API-Key': apiKey,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('📊 Código de Status HTTP: ${response.statusCode}');
      
      switch (response.statusCode) {
        case 200:
          return jsonDecode(response.body);
        case 401:
          throw AuthenticationException(
            message: 'Chave de API inválida ou expirada.',
            originalError: response.body,
          );
        case 404:
        case 422:
          throw NotFoundException(
            message: 'Ativo não encontrado.',
            originalError: response.body,
          );
        case 500:
        case 502:
        case 503:
          throw ServerException(
            message: 'Servidor indisponível no momento. Tente novamente mais tarde.',
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
        message: 'Erro de conexão com o servidor: ${e.message}',
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

  /// Busca o histórico de preços completo de um determinado ticker.
  Future<List<StockPrice>> fetchStocksPrice(String ticker, {int limit = 3000}) async {
    try {
      final data = await _getRequest('/stocks/$ticker/history?limit=$limit');
      final prices = data['prices'] as List<dynamic>?;
      if (prices == null || prices.isEmpty) {
        throw ValidationException(
          message: 'Nenhum dado de cotação disponível para o ativo $ticker.',
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

  /// Busca os fundamentos completos de uma Ação corporativa da B3.
  Future<StockFundamentals> fetchStockFundamentals(String ticker) async {
    try {
      final data = await _getRequest('/fundamentals/$ticker');
      
      if (data == null) {
        throw ValidationException(
          message: 'Fundamentos de ação indisponíveis para $ticker.',
        );
      }

      return StockFundamentals.fromJson(data);
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
      final data = await _getRequest('/fiis/$ticker');
      
      if (data == null) {
        throw ValidationException(
          message: 'Dados fundamentais do FII indisponíveis para $ticker.',
        );
      }

      return FiiFundamentals.fromJson(data);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar fundamentos do FII $ticker: $e',
        originalError: e,
      );
    }
  }

  /// Busca o histórico completo de dividendos de um determinado ativo.
  Future<DividendHistory> fetchDividends(String ticker, {int limit = 10}) async {
    List<dynamic>? dividendsList;
    try {
      final data = await _getRequest('/dividends/$ticker?years=$limit');
      dividendsList = (data['payments'] ?? data['dividends'] ?? data['payments_history']) as List<dynamic>?;
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar dividendos corporativos para $ticker: $e');
    }

    if (dividendsList == null || dividendsList.isEmpty) {
      try {
        final fiiDistData = await _getRequest('/fiis/$ticker/distributions?years=$limit');
        dividendsList = (fiiDistData['payments'] ?? fiiDistData['dividends'] ?? fiiDistData['distributions'] ?? fiiDistData['payments_history']) as List<dynamic>?;
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar distribuições de FII para $ticker: $e');
      }
    }

    if (dividendsList == null || dividendsList.isEmpty) {
      try {
        final fiiLimit = (limit * 12).clamp(1, 240);
        final fiiData = await _getRequest('/fiis/$ticker/history?limit=$fiiLimit');
        dividendsList = fiiData['history'] as List<dynamic>?;
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar histórico de cotações FII para $ticker: $e');
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
      debugPrint('⚠️ Erro ao estruturar histórico de dividendos de $ticker: $e');
      return DividendHistory(
        dividends: [],
        totalAnnualDividend: 0,
        averageDividend: 0,
      );
    }
  }

  /// Busca a lista de eventos corporativos (splits e inplits) de um ticker.
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
      debugPrint('⚠️ Erro ao buscar desdobramentos/grupamentos históricos de $ticker: $e');
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
      final data = await _getRequest('/stocks/$ticker/ticker-history');
      return data as Map<String, dynamic>?;
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao buscar histórico de alteração de ticker para $ticker: $e',
        originalError: e,
       );
    }
  }

  /// Busca todos os tickers de Ações da B3 com paginação dinâmica e cache local.
  Future<List<String>> fetchAllStockTickers() async {
    if (_cachedStockTickers != null) {
      return _cachedStockTickers!;
    }
    try {
      final data = await _getRequest('/stocks/?limit=5000');
      final tickers = List<String>.from(data['tickers'] ?? []);
      final total = data['total'] as int? ?? 0;

      if (total > tickers.length) {
        int offset = tickers.length;
        while (offset < total) {
          final nextData = await _getRequest('/stocks/?limit=5000&offset=$offset');
          final nextTickers = List<String>.from(nextData['tickers'] ?? []);
          if (nextTickers.isEmpty) break;
          tickers.addAll(nextTickers);
          offset += nextTickers.length;
        }
      }

      final stockFormat = RegExp(r'^[A-Z]{4}(3|4|5|6|7|8|11)$');

      final cleanTickers = tickers
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

      cleanTickers.sort();
      _cachedStockTickers = cleanTickers;
      return _cachedStockTickers!;
    } catch (e) {
      debugPrint('⚠️ Falha crítica ao processar lista geral de ações: $e');
      return [];
    }
  }

  /// Busca todos os tickers de Fundos Imobiliários da B3 com cache local.
  Future<List<String>> fetchAllFiiTickers() async {
    if (_cachedFiiTickers != null) {
      return _cachedFiiTickers!;
    }
    try {
      final data = await _getRequest('/fiis/?limit=1000');
      final List<dynamic> fiisList = data['fiis'] ?? [];
      
      final fiiFormat = RegExp(r'^[A-Z]{4}11$');

      final tickers = fiisList
          .map((item) => item['ticker'] as String? ?? '')
          .where((t) => t.isNotEmpty && !t.contains(' '))
          .map((t) => t.trim().toUpperCase())
          .where((t) => fiiFormat.hasMatch(t))
          .toList();

      tickers.sort();
      _cachedFiiTickers = tickers;
      return _cachedFiiTickers!;
    } catch (e) {
      debugPrint('⚠️ Falha crítica ao processar lista geral de FIIs: $e');
      return [];
    }
  }
}