import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';

class StockService {
  // Método padrão para fazer requisições GET à API.
  Future<dynamic> _getRequest(String endpoint) async {
    final apiKey = dotenv.env['BOLSAI_API_KEY'];
    final baseUrl = dotenv.env['BOLSAI_BASE_URL'] ?? 'https://api.usebolsai.com/api/v1';

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API KEY não configurada');
    }
    final url = Uri.parse('$baseUrl$endpoint');
    final response = await http.get(
      url,
      headers: {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  // Método específico para buscar o histórico de preços de um ticker.
  Future<List<Stock>> fetchStocks(String ticker) async {
    final data = await _getRequest('/stocks/$ticker/history?limit=2');
    final prices = data['prices'] as List<dynamic>?;

    if (prices == null || prices.isEmpty) {
      throw Exception('Sem dados');
    }

    return prices
        .map((item) => Stock.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  
}