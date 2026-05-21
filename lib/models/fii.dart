class FiiPrice {
  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  FiiPrice({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory FiiPrice.fromJson(Map<String, dynamic> json) {
    return FiiPrice(
      date: json['trade_date'] ?? json['date'] ?? '',
      open: (json['open'] as num?)?.toDouble() ?? 0.0,
      high: (json['high'] as num?)?.toDouble() ?? 0.0,
      low: (json['low'] as num?)?.toDouble() ?? 0.0,
      close: (json['close'] as num?)?.toDouble() ?? 0.0,
      volume: (json['volume'] as num?)?.toInt() ?? 0,
    );
  }
}

class FiiFundamentals {
  final double dividendYield;
  final double netAssetValue;
  final double ffoYield;
  final double vacancyRate;
  final double marketCap;
  final double equity;
  final double revenue;
  final double netIncome;

  FiiFundamentals({
    required this.dividendYield,
    required this.netAssetValue,
    required this.ffoYield,
    required this.vacancyRate,
    required this.marketCap,
    required this.equity,
    required this.revenue,
    required this.netIncome,
  });

  factory FiiFundamentals.fromJson(Map<String, dynamic> json) {
    return FiiFundamentals(
      dividendYield: (json['dividend_yield'] as num?)?.toDouble() ??
          (json['dyield'] as num?)?.toDouble() ?? 0.0,
      netAssetValue: (json['net_asset_value'] as num?)?.toDouble() ??
          (json['vpa'] as num?)?.toDouble() ?? 0.0,
      ffoYield: (json['ffo_yield'] as num?)?.toDouble() ?? 0.0,
      vacancyRate: (json['vacancy_rate'] as num?)?.toDouble() ??
          (json['vacancia'] as num?)?.toDouble() ?? 0.0,
      marketCap: (json['market_cap'] as num?)?.toDouble() ?? 0.0,
      equity: (json['equity'] as num?)?.toDouble() ?? 0.0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      netIncome: (json['net_income'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
