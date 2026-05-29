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

  /// Instancia os fundamentos de FII a partir do JSON da API Bolsai.
  factory FiiFundamentals.fromJson(Map<String, dynamic> json) {
    return FiiFundamentals(
      ticker: json['ticker'] ?? '',
      name: json['name'] ?? '',
      referenceDate: json['reference_date'] ?? '',
      closePrice: (json['close_price'] as num?)?.toDouble() ?? 0.0,
      bookValuePerShare: (json['book_value_per_share'] as num?)?.toDouble() ?? 0.0,
      pvp: (json['pvp'] as num?)?.toDouble() ?? 0.0,
      dyield: (json['dividend_yield_ttm'] as num?)?.toDouble() ?? 0.0,
      netAssetValue: (json['net_asset_value'] as num?)?.toDouble() ?? 0.0,
      sharesOutstanding: (json['shares_outstanding'] as num?)?.toDouble() ?? 0.0,
      segment: json['segment'] ?? '',
      vacancyPct: (json['vacancy_pct'] as num?)?.toDouble() ?? 0.0,
      delinquencyPct: (json['delinquency_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
