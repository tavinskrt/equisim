/// Modelo para armazenamento dos dados e indicadores fundamentalistas de Fundos Imobiliários (FIIs).
class FiiFundamentals {
  final String ticker;
  final String name;
  final String referenceDate;
  final double closePrice;
  final double bookValuePerShare; // VPA (Valor Patrimonial por Ação)
  final double pvp; // P/VP (Preço sobre Valor Patrimonial)
  final double dyield; // Dividend Yield anualizado acumulado nos últimos 12 meses
  final double netAssetValue; // Patrimônio Líquido total do Fundo
  final double sharesOutstanding; // Quantidade total de cotas emitidas
  final String segment; // Segmento de atuação (ex: Logística, Shoppings, Híbrido, etc.)
  final double vacancyPct; // Taxa de vacância do portfólio de imóveis
  final double delinquencyPct; // Taxa de inadimplência média do Fundo

  FiiFundamentals({
    required this.ticker,
    required this.name,
    required this.referenceDate,
    required this.closePrice,
    required this.bookValuePerShare,
    required this.pvp,
    required this.dyield,
    required this.netAssetValue,
    required this.sharesOutstanding,
    required this.segment,
    required this.vacancyPct,
    required this.delinquencyPct,
  });

  /// Instancia os fundamentos de FII a partir do JSON da API brapi.dev ou legada.
  factory FiiFundamentals.fromJson(Map<String, dynamic> json) {
    double parsePct(dynamic val, dynamic fallback) {
      if (val != null && val is num) {
        final d = val.toDouble();
        return (d.abs() <= 1.0 && d != 0.0) ? d * 100.0 : d;
      }
      if (fallback != null && fallback is num) {
        return fallback.toDouble();
      }
      return 0.0;
    }

    return FiiFundamentals(
      ticker: json['symbol'] ?? json['ticker'] ?? '',
      name: json['name'] ?? json['shortName'] ?? json['longName'] ?? '',
      referenceDate: json['referenceDate'] ?? json['reference_date'] ?? '',
      closePrice: (json['regularMarketPrice'] as num?)?.toDouble() ??
          (json['closePrice'] as num?)?.toDouble() ??
          (json['close_price'] as num?)?.toDouble() ?? 0.0,
      bookValuePerShare: (json['bookValuePerShare'] as num?)?.toDouble() ??
          (json['bookValue'] as num?)?.toDouble() ??
          (json['book_value_per_share'] as num?)?.toDouble() ?? 0.0,
      pvp: (json['priceToNav'] as num?)?.toDouble() ??
          (json['priceToBook'] as num?)?.toDouble() ??
          (json['pvp'] as num?)?.toDouble() ?? 0.0,
      dyield: parsePct(json['dividendYield12m'] ?? json['dividendYield'], json['dividend_yield_ttm']),
      netAssetValue: (json['netAssetValue'] as num?)?.toDouble() ?? (json['net_asset_value'] as num?)?.toDouble() ?? 0.0,
      sharesOutstanding: (json['sharesOutstanding'] as num?)?.toDouble() ?? (json['shares_outstanding'] as num?)?.toDouble() ?? 0.0,
      segment: json['segmentoAtuacao'] ?? json['segmentType'] ?? json['segment'] ?? '',
      vacancyPct: parsePct(json['vacancyPct'] ?? json['vacancia'], json['vacancy_pct']),
      delinquencyPct: parsePct(json['delinquencyPct'], json['delinquency_pct']),
    );
  }
}
