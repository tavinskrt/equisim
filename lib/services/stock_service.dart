import 'dart:async' as async;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';
import '../models/dividend.dart';
import '../models/exceptions.dart';

/// Serviço de acesso à API brapi.dev (v2).
///
/// ATENÇÃO — código de transição. Esta classe sobrevive apenas até a Fase 2,
/// quando será substituída por `BrapiDatasource` (Dio + interceptors + DTOs +
/// cache Drift), conforme `PLANO_ARQUITETURA.md` §6. Mantida aqui para que a
/// aplicação continue com acesso a dados durante as Fases 0 e 1.
///
/// Universo restrito a AÇÕES: o Escopo B não envolve FIIs.
class StockService {
  static List<String>? _cachedStockTickers;

  /// Requisição GET padrão à brapi.dev, com autenticação e tratamento de erros.
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
    } on async.TimeoutException catch (e) {
      // Precisa ser a exceção do dart:async — é ela que Future.timeout() lança.
      debugPrint('❌ Tempo limite de requisição esgotado: $e');
      throw RequestTimeoutException(originalError: e);
    } catch (e) {
      debugPrint('❌ Erro inesperado ao realizar chamada HTTP: $e');
      rethrow;
    }
  }

  /// Extrai a lista `results` da resposta padrão da brapi.dev.
  List<dynamic> _extractResults(dynamic data) {
    if (data is Map<String, dynamic> && data.containsKey('results')) {
      final res = data['results'];
      if (res is List) return res;
    }
    return [];
  }

  /// Busca o histórico de preços diários de um ticker.
  ///
  /// O campo `close` da brapi já vem ajustado por desdobramentos e grupamentos,
  /// mas NÃO por proventos (verificado — ver `PLANO_ARQUITETURA.md` §0.3a).
  /// É a série correta para combinar com o fluxo de dividendos.
  Future<List<StockPrice>> fetchStocksPrice(String ticker, {String range = '10y'}) async {
    try {
      final data = await _getRequest('/v2/stocks/historical?symbols=$ticker&range=$range&interval=1d');
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

  /// Busca os fundamentos correntes de uma ação da B3.
  Future<StockFundamentals> fetchStockFundamentals(String ticker) async {
    try {
      final Map<String, dynamic> mergedData = {};

      // Indicadores estatísticos
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

      // Dados financeiros (receita, lucro, dívidas, margens)
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

      // Snapshot de cotação complementar
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
          message: 'Fundamentos indisponíveis para $ticker.',
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

  /// Busca o histórico de proventos de uma ação.
  ///
  /// Cada evento carrega `label` (JCP / DIVIDENDO / RENDIMENTO), necessário para
  /// a política fiscal — JCP sofre 15% de IRRF na fonte.
  Future<DividendHistory> fetchDividends(String ticker) async {
    List<dynamic>? dividendsList;

    try {
      final data = await _getRequest('/v2/stocks/dividends?symbols=$ticker');
      if (data is Map<String, dynamic>) {
        final results = _extractResults(data);
        if (results.isNotEmpty && results.first is Map<String, dynamic>) {
          final firstResult = results.first as Map<String, dynamic>;
          final resultData = firstResult['data'] as Map<String, dynamic>? ?? firstResult;
          dividendsList = resultData['cashDividends'] as List<dynamic>?;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar proventos de $ticker: $e');
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
      debugPrint('⚠️ Erro ao estruturar histórico de proventos de $ticker: $e');
      return DividendHistory(
        dividends: [],
        totalAnnualDividend: 0,
        averageDividend: 0,
      );
    }
  }

  /// Resolve renomeações de ticker na B3 (ex.: VVAR3 → VIIA3 → BHIA3).
  ///
  /// O parâmetro é `symbols` (plural). A versão anterior usava `symbol`, o que
  /// devolvia HTTP 400 silenciosamente e deixava a funcionalidade inoperante.
  Future<Map<String, dynamic>?> fetchTickerHistory(String ticker) async {
    try {
      final data = await _getRequest('/v2/tickers/resolve?symbols=$ticker');
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
      debugPrint('⚠️ Erro ao resolver ticker $ticker: $e');
      return null;
    }
  }

  /// Busca todos os tickers de ações da B3.
  ///
  /// `type=stock` já exclui fundos: verificado em 19/08/2026, 781 ações contra
  /// 332 FIIs, com interseção vazia. A whitelist manual de Units que existia
  /// aqui foi removida — ela excluía indevidamente IGTI11, ONCO11 e BRBI11 e
  /// mantinha 5 tickers que a API não lista mais.
  Future<List<String>> fetchAllStockTickers() async {
    if (_cachedStockTickers != null) {
      return _cachedStockTickers!;
    }
    try {
      final data = await _getRequest('/v2/tickers?type=stock&limit=1000');
      final results = _extractResults(data);

      final tickers = results
          .map((item) => item is String ? item : (item['symbol'] as String? ?? ''))
          .where((t) => t.isNotEmpty && !t.contains(' '))
          .map((t) => t.trim().toUpperCase())
          .toSet()
          .toList()
        ..sort();

      if (tickers.isEmpty) {
        return _fallbackTickers;
      }

      _cachedStockTickers = tickers;
      return _cachedStockTickers!;
    } catch (e) {
      debugPrint('⚠️ Falha ao carregar lista de ações da brapi.dev: $e');
      return _fallbackTickers;
    }
  }

  /// Conjunto mínimo para ambientes sem token ou sem rede.
  static const List<String> _fallbackTickers = [
    'PETR4', 'VALE3', 'ITUB4', 'BBAS3', 'BBDC4', 'WEGE3', 'ABEV3'
  ];
}
