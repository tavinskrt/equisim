/// Modelo para dados de Fundos Imobiliários (FIIs)
class FiiFundamentals {
  final String ticker;
  final String name;
  final String referenceDate;
  final double closePrice;
  final double bookValuePerShare; // VPA
  final double pvp; // P/VP
  final double dyield; // Dividend Yield anualizado
  final double netAssetValue; // Patrimônio Líquido
  final double sharesOutstanding; // Quantidade de cotas
  final String segment; // Segmento (ex: Logística, Shopping, etc.)
  final double vacancyPct; // Taxa de vacância
  final double delinquencyPct; // Taxa de inadimplência

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
