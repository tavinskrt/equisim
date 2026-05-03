class StockPrice {
  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  StockPrice({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory StockPrice.fromJson(Map<String, dynamic> json) {
    return StockPrice(
      date: json['trade_date'] ?? json['date'] ?? '',
      open: (json['open'] as num?)?.toDouble() ?? 0.0,
      high: (json['high'] as num?)?.toDouble() ?? 0.0,
      low: (json['low'] as num?)?.toDouble() ?? 0.0,
      close: (json['close'] as num?)?.toDouble() ?? 0.0,
      volume: (json['volume'] as num?)?.toInt() ?? 0,
    );
  }
}


class StockFundamentals {
  final double eps;
  final double lpa;
  final double vpa;
  final double pl;
  final double pbv;
  final double roe;
  final double roic;
  final double dyield;
  final double marketCap;
  final double liabilities;
  final double equity;
  final double revenue;
  final double netIncome;

  StockFundamentals({
    required this.eps,
    required this.lpa,
    required this.vpa,
    required this.pl,
    required this.pbv,
    required this.roe,
    required this.roic,
    required this.dyield,
    required this.marketCap,
    required this.liabilities,
    required this.equity,
    required this.revenue,
    required this.netIncome,
  });

  factory StockFundamentals.fromJson(Map<String, dynamic> json) {
    return StockFundamentals(
      eps: (json['eps'] as num?)?.toDouble() ?? 0.0,
      lpa: (json['lpa'] as num?)?.toDouble() ?? (json['eps'] as num?)?.toDouble() ?? 0.0,
      vpa: (json['vpa'] as num?)?.toDouble() ?? 0.0,
      pl: (json['pl'] as num?)?.toDouble() ?? 0.0,
      pbv: (json['pbv'] as num?)?.toDouble() ?? 0.0,
      roe: (json['roe'] as num?)?.toDouble() ?? 0.0,
      roic: (json['roic'] as num?)?.toDouble() ?? 0.0,
      dyield: (json['dividend_yield'] as num?)?.toDouble() ?? 0.0,
      marketCap: (json['market_cap'] as num?)?.toDouble() ?? 0.0,
      liabilities: (json['liabilities'] as num?)?.toDouble() ?? 0.0,
      equity: (json['equity'] as num?)?.toDouble() ?? 0.0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      netIncome: (json['net_income'] as num?)?.toDouble() ?? 0.0,
    );
  }
}