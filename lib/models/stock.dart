/// Representa a cotação diária de fechamento e volume de negociação de um ativo.
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

  /// Instancia o histórico de preços diários a partir do JSON da API BolsaI.
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

/// Modelo para armazenamento dos dados e indicadores fundamentalistas de Ações da B3.
class StockFundamentals {
  final double eps; // LPA consolidado
  final double lpa; // LPA do TTM consolidado (Lucro Por Ação)
  final double vpa; // VPA consolidado (Valor Patrimonial por Ação)
  final double pl; // P/L (Preço sobre Lucro)
  final double pbv; // P/VP (Preço sobre Valor Patrimonial)
  final double roe; // ROE % (Retorno sobre Patrimônio Líquido)
  final double roic; // ROIC % (Retorno sobre Capital Investido)
  final double dyield; // Dividend Yield anualizado (%)
  final double marketCap; // Valor de mercado total da empresa
  final double liabilities; // Passivo total
  final double equity; // Patrimônio Líquido consolidado
  final double revenue; // Receita líquida anualizada
  final double netIncome; // Lucro líquido anualizado

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

  /// Instancia os fundamentos de ações a partir do JSON da API Bolsai.
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