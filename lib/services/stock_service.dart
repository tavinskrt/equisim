import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stock.dart';

class StockService {
  Future<List<Stock>> fetchStocks(String ticker) async {
    final apiKey = dotenv.env['BOLSAI_API_KEY'];
    final baseUrl = dotenv.env['BOLSAI_BASE_URL'] ?? 'https://api.usebolsai.com/api/v1';

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API KEY não configurada');
    }

    final url = Uri.parse('$baseUrl/stocks/$ticker/history?limit=100');

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

    final data = jsonDecode(response.body);
    final prices = data['prices'] as List<dynamic>?;

    if (prices == null || prices.isEmpty) {
      throw Exception('Sem dados');
    }

    return prices
        .map((item) => Stock.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}