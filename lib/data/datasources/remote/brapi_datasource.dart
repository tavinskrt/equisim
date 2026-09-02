import 'package:equisim_core/equisim_core.dart';

import '../../dtos/brapi_dtos.dart';
import '../../network/api_client.dart';

/// Acesso aos endpoints da brapi.dev (v2).
///
/// Todos os caminhos aqui foram verificados contra a API real em 19/08/2026;
/// as formas de resposta irregulares estão tratadas em [BrapiJson].
class BrapiDatasource {
  final ApiClient client;

  BrapiDatasource(this.client);

  String _url(String path) => '${client.config.brapiBaseUrl}$path';

  // ------------------------------------------------------------- Cotações --

  /// Histórico diário de vários ativos em **uma** requisição.
  ///
  /// O lote foi medido em 3.460 ms contra 6.417 ms sequenciais para 10 ativos
  /// — 1,85× mais rápido — e consome 1 requisição em vez de 10, o que importa
  /// porque o limite da API é inobservável.
  Future<Result<Map<Ticker, PriceSeries>>> historicalBatch(
    List<Ticker> tickers, {
    String range = '10y',
  }) async {
    if (tickers.isEmpty) return const Ok({});

    final symbols = tickers.map((t) => t.value).join(',');
    final response = await client.getJson(
      _url('/v2/stocks/historical'),
      query: {'symbols': symbols, 'range': range, 'interval': '1d'},
      heavy: true, // ~2.500 pontos por ativo
    );

    return response.flatMap((body) {
      final results = BrapiJson.results(body);
      if (results.isEmpty) {
        return const Err(InsufficientData(
          'Nenhuma cotação retornada para os ativos solicitados.',
        ));
      }

      final out = <Ticker, PriceSeries>{};
      for (final entry in results) {
        if (entry is! Map<String, dynamic>) continue;
        final symbol = BrapiJson.asString(entry['symbol']) ??
            BrapiJson.asString(entry['requestedSymbol']);
        if (symbol == null) continue;
        final ticker = Ticker.tryParse(symbol);
        if (ticker == null) continue;

        final data = entry['data'];
        final raw = data is Map<String, dynamic>
            ? data['historicalDataPrice']
            : null;
        if (raw is! List) continue;

        final points = <PricePoint>[];
        for (final item in raw) {
          if (item is! Map<String, dynamic>) continue;
          final dto = BrapiPriceDto.fromJson(item);
          if (dto != null) points.add(dto.toDomain());
        }
        if (points.isNotEmpty) {
          out[ticker] = PriceSeries(ticker: ticker, points: points);
        }
      }

      if (out.isEmpty) {
        return const Err(InsufficientData(
          'A resposta não continha nenhuma série de preços utilizável.',
        ));
      }
      return Ok(out);
    });
  }

  /// Série do Ibovespa, pelo `close` — a mesma convenção usada nos ativos.
  Future<Result<PriceSeries>> ibovespa({String range = '10y'}) async {
    final response = await client.getJson(
      _url('/v2/stocks/historical'),
      query: {'symbols': '^BVSP', 'range': range, 'interval': '1d'},
      heavy: true,
    );

    return response.flatMap((body) {
      final data = BrapiJson.firstData(body);
      final raw = data?['historicalDataPrice'];
      if (raw is! List || raw.isEmpty) {
        return const Err(InsufficientData('Sem histórico do Ibovespa.'));
      }
      final points = <PricePoint>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final dto = BrapiPriceDto.fromJson(item);
        if (dto != null) points.add(dto.toDomain());
      }
      // ^BVSP não passa no formato de ticker da B3; usa-se um rótulo interno.
      return Ok(PriceSeries(ticker: Ticker.parse('IBOV11'), points: points));
    });
  }

  // ----------------------------------------------------------- Fundamentos --

  /// Fundamentos anuais consolidados dos quatro demonstrativos.
  ///
  /// A fonte só oferece granularidade **anual** (16 exercícios, 2010–2025);
  /// `mode=history&type=quarterly` também devolve anual. Limitação a declarar.
  Future<Result<List<FundamentalsSnapshot>>> fundamentalsHistory(
    Ticker ticker,
  ) async {
    const endpoints = [
      '/v2/stocks/statistics',
      '/v2/stocks/income-statement',
      '/v2/stocks/balance-sheet',
      '/v2/stocks/cash-flow',
    ];

    // Chave = fim do exercício; os quatro demonstrativos são fundidos por ela.
    final merged = <String, Map<String, dynamic>>{};
    var anySucceeded = false;

    for (final endpoint in endpoints) {
      final response = await client.getJson(
        _url(endpoint),
        query: {'symbols': ticker.value, 'mode': 'history'},
      );
      if (response.isErr) continue;
      anySucceeded = true;

      for (final item in BrapiJson.firstDataList(response.unwrap())) {
        if (item is! Map<String, dynamic>) continue;
        final endDate = BrapiJson.asString(item['endDate']);
        if (endDate == null) continue;
        final key = endDate.split('T').first;
        (merged[key] ??= <String, dynamic>{}).addAll(item);
      }
    }

    if (!anySucceeded) {
      return Err(InsufficientData(
        'Nenhum demonstrativo disponível para ${ticker.value}.',
      ));
    }

    // `sharesOutstanding`, `marketCap` e `enterpriseToEbitda` descrevem o
    // **hoje**, não o exercício; sem eles não há valor por ação nem múltiplo
    // de saída.
    final current = await client.getJson(
      _url('/v2/stocks/statistics'),
      query: {'symbols': ticker.value, 'mode': 'current'},
    );
    final currentData = current.isOk ? BrapiJson.firstData(current.unwrap()) : null;

    final snapshots = <FundamentalsSnapshot>[];
    for (final entry in merged.entries) {
      final date = BrapiJson.asDate(entry.key);
      if (date == null) continue;
      // O snapshot corrente vem **depois** e prevalece. As linhas anuais também
      // trazem esses três campos, e nelas o `marketCap` é calculado como
      // `ações × preço da unit` — o que o infla pelo fator da unit: SAPR11
      // aparecia com R$ 59,9 bi contra os R$ 10,1 bi reais, KLBN11 com R$ 117
      // bi contra R$ 23,0 bi (medido em 21/08/2026). Deixá-las sobrescrever
      // estragava o peso do equity no WACC e impedia identificar a unit.
      final fields = <String, dynamic>{
        ...entry.value,
        if (currentData?['sharesOutstanding'] != null)
          'sharesOutstanding': currentData!['sharesOutstanding'],
        if (currentData?['enterpriseToEbitda'] != null)
          'enterpriseToEbitda': currentData!['enterpriseToEbitda'],
        if (currentData?['marketCap'] != null)
          'marketCap': currentData!['marketCap'],
      };
      snapshots.add(
        BrapiFundamentalsDto(fiscalPeriodEnd: date, fields: fields)
            .toDomain(ticker),
      );
    }

    snapshots.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
    return Ok(snapshots);
  }

  // --------------------------------------------------------------- Perfil --

  Future<Result<Asset>> profile(Ticker ticker) async {
    final response = await client.getJson(
      _url('/v2/stocks/profile'),
      query: {'symbols': ticker.value},
    );
    return response.flatMap((body) {
      final data = BrapiJson.firstData(body);
      if (data == null) {
        return Err(InsufficientData('Perfil indisponível para ${ticker.value}.'));
      }
      return Ok(BrapiProfileDto.fromJson(data).toDomain(ticker));
    });
  }

  // -------------------------------------------------------------- Tickers --

  /// Universo de ações da B3.
  ///
  /// `type=stock` já exclui fundos — verificado: 781 ações contra 332 FIIs,
  /// interseção vazia. Não há whitelist manual de Units: a anterior excluía
  /// indevidamente IGTI11, ONCO11 e BRBI11.
  Future<Result<List<Ticker>>> universe() async {
    final response = await client.getJson(
      _url('/v2/tickers'),
      query: {'type': 'stock', 'limit': '1000'},
    );
    return response.map((body) {
      final tickers = <Ticker>{};
      for (final item in BrapiJson.results(body)) {
        final symbol = item is String
            ? item
            : (item is Map<String, dynamic>
                ? BrapiJson.asString(item['symbol'])
                : null);
        if (symbol == null) continue;
        final ticker = Ticker.tryParse(symbol);
        if (ticker != null) tickers.add(ticker);
      }
      return tickers.toList()..sort();
    });
  }

  /// Resolve renomeações (ex.: VVAR3 → VIIA3 → BHIA3).
  ///
  /// O parâmetro é `symbols` (plural). A implementação anterior usava `symbol`
  /// e recebia HTTP 400 silenciosamente, deixando a funcionalidade inoperante
  /// desde sempre.
  Future<Result<Ticker?>> resolve(Ticker ticker) async {
    final response = await client.getJson(
      _url('/v2/tickers/resolve'),
      query: {'symbols': ticker.value},
    );
    return response.map((body) {
      final results = BrapiJson.results(body);
      if (results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      final changed = first['changed'] == true;
      final resolved = BrapiJson.asString(first['symbol']);
      if (!changed || resolved == null) return null;
      final parsed = Ticker.tryParse(resolved);
      return parsed == ticker ? null : parsed;
    });
  }
}
