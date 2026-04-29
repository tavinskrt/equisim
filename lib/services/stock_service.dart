import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';
import '../models/exceptions.dart';

class StockService {
  // Método padrão para fazer requisições GET à API.
  Future<dynamic> _getRequest(String endpoint) async {
    final apiKey = dotenv.env['BOLSAI_API_KEY'];
    final baseUrl = dotenv.env['BOLSAI_BASE_URL'] ?? 'https://api.usebolsai.com/api/v1';

    if (apiKey == null || apiKey.isEmpty) {
      throw AuthenticationException(
        message: 'API KEY não configurada. Verifique o arquivo .env',
      );
    }
    
    final url = Uri.parse('$baseUrl$endpoint');
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
  Future<List<StockPrice>> fetchStocksPrice(String ticker) async {
    try {
      final data = await _getRequest('/stocks/$ticker/history?limit=2');
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

  // Método específico para buscar o histórico de fundamentos de um ticker.
  Future<List<StockFundamentals>> fetchStocksFundamentals(String ticker) async {
    try {
      final data = await _getRequest('/fundamentals/$ticker/history?limit=2');
      final indicadores = data['history'] as List<dynamic>?;
      if (indicadores == null || indicadores.isEmpty) {
        throw ValidationException(
          message: 'Nenhum dado de fundamentos disponível para $ticker',
        );
      }

      return indicadores
          .map((item) => StockFundamentals.fromJson(item as Map<String, dynamic>))
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


}