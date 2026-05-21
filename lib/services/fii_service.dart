import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/fii.dart';
import '../models/dividend.dart';
import '../models/exceptions.dart';

class FiiService {
  Future<dynamic> _getRequest(String endpoint) async {
    final apiKey = dotenv.env['BOLSAI_API_KEY'];
    final baseUrl = dotenv.env['BOLSAI_BASE_URL'] ?? 'https://api.usebolsai.com/api/v1';

    if (apiKey == null || apiKey.isEmpty) {
      throw AuthenticationException(
        message: 'API KEY não configurada. Verifique o arquivo .env',
      );
    }

    final url = Uri.parse('$baseUrl$endpoint');
    debugPrint('🔗 URL requisição FII: $url');

    try {
      final response = await http.get(
        url,
        headers: {
          'X-API-Key': apiKey,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      debugPrint('📊 Status code: ${response.statusCode}');
      debugPrint('📝 Response body: ${response.body}');

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
      debugPrint('❌ Erro na requisição FII: $e');
      throw NetworkException(
        message: 'Erro de conexão: ${e.message}',
        originalError: e,
      );
    } on TimeoutException catch (e) {
      debugPrint('❌ Timeout FII: $e');
      throw TimeoutException(
        originalError: e,
      );
    } catch (e) {
      debugPrint('❌ Erro genérico FII: $e');
      rethrow;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _buildEndpoint(String path, Map<String, String> queryParameters) {
    final query = Uri(queryParameters: queryParameters).query;
    return '$path?$query';
  }

  int _calculateMonthLimit(DateTime startDate, DateTime endDate) {
    final months = (endDate.year - startDate.year) * 12 + endDate.month - startDate.month + 1;
    return months.clamp(1, 120);
  }

  int _calculateYearsLimit(DateTime startDate, DateTime endDate) {
    final days = endDate.difference(startDate).inDays;
    final years = (days / 365.25).ceil();
    return years.clamp(1, 10);
  }

  Future<List<FiiPrice>> fetchFiiPriceHistory(
    String ticker, {
    DateTime? startDate,
    DateTime? endDate,
    int limit = 120,
  }) async {
    final queryParams = <String, String>{'limit': limit.toString()};

    if (startDate != null) {
      queryParams['from'] = _formatDate(startDate);
    }
    if (endDate != null) {
      queryParams['to'] = _formatDate(endDate);
    }
    if (startDate != null && endDate != null) {
      queryParams['limit'] = _calculateMonthLimit(startDate, endDate).toString();
    }

    final endpoint = _buildEndpoint('/fiis/$ticker/history', queryParams);
    final data = await _getRequest(endpoint);
    final prices = _extractPriceEntries(data);

    if (prices.isEmpty) {
      throw ValidationException(
        message: 'Nenhum dado de preço disponível para o FII $ticker',
      );
    }

    return prices
        .map((item) => FiiPrice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<FiiFundamentals> fetchFiiFundamentals(String ticker) async {
    try {
      final data = await _getRequest('/fiis/$ticker');
      if (data == null) {
        throw ValidationException(
          message: 'Dados de fundamentos não disponíveis para $ticker',
        );
      }
      return FiiFundamentals.fromJson(data);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(
        message: 'Erro ao processar fundamentos do FII: $e',
        originalError: e,
      );
    }
  }

  Future<DividendHistory> fetchFiiDividends(
    String ticker, {
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    try {
      final effectiveLimit =
          startDate != null && endDate != null ? _calculateYearsLimit(startDate, endDate) : limit;
      final data = await _getRequest('/dividends/$ticker?years=$effectiveLimit');
      final dividendsList = _extractDividendEntries(data);
      if (dividendsList.isEmpty) {
        return DividendHistory(dividends: [], totalAnnualDividend: 0, averageDividend: 0);
      }

      final dividends = dividendsList
          .map((item) => Dividend.fromJson(item as Map<String, dynamic>))
          .toList();

      return DividendHistory.fromDividends(dividends);
    } on AppException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Aviso ao buscar dividendos FII: $e');
      return DividendHistory(dividends: [], totalAnnualDividend: 0, averageDividend: 0);
    }
  }

  List<dynamic> _extractPriceEntries(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      if (data['prices'] is List) return data['prices'] as List<dynamic>;
      if (data['data'] is List) return data['data'] as List<dynamic>;
      if (data['results'] is List) return data['results'] as List<dynamic>;
      for (final value in data.values) {
        if (value is List) return value;
        if (value is Map<String, dynamic>) {
          final nested = _extractPriceEntries(value);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return [];
  }

  List<dynamic> _extractDividendEntries(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      if (data['dividends'] is List) return data['dividends'] as List<dynamic>;
      if (data['data'] is List) return data['data'] as List<dynamic>;
      if (data['items'] is List) return data['items'] as List<dynamic>;
      if (data['results'] is List) return data['results'] as List<dynamic>;
      for (final value in data.values) {
        if (value is List) return value;
        if (value is Map<String, dynamic>) {
          final nested = _extractDividendEntries(value);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return [];
  }
}
