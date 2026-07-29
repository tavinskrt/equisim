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

  /// Instancia o histórico de preços diários a partir do JSON da API brapi.dev ou legada.
  factory StockPrice.fromJson(Map<String, dynamic> json) {
    String dateStr = '';
    final rawDate = json['date'] ?? json['trade_date'];
    if (rawDate is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(rawDate * 1000, isUtc: true);
      dateStr = dt.toIso8601String().split('T')[0];
    } else if (rawDate is String) {
      dateStr = rawDate;
    }

    return StockPrice(
      date: dateStr,
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

  /// Instancia os fundamentos de ações a partir do JSON da API brapi.dev ou legada.
  factory StockFundamentals.fromJson(Map<String, dynamic> json) {
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

    final double epsVal = (json['earningsPerShare'] as num?)?.toDouble() ??
        (json['trailingEps'] as num?)?.toDouble() ??
        (json['eps'] as num?)?.toDouble() ?? 0.0;

    final double vpaVal = (json['bookValue'] as num?)?.toDouble() ??
        (json['vpa'] as num?)?.toDouble() ?? 0.0;

    final double shares = (json['sharesOutstanding'] as num?)?.toDouble() ?? 0.0;
    final double calculatedEquity = vpaVal > 0 && shares > 0 ? vpaVal * shares : 0.0;

    return StockFundamentals(
      eps: epsVal,
      lpa: (json['lpa'] as num?)?.toDouble() ?? epsVal,
      vpa: vpaVal,
      pl: (json['trailingPE'] as num?)?.toDouble() ?? (json['pl'] as num?)?.toDouble() ?? 0.0,
      pbv: (json['priceToBook'] as num?)?.toDouble() ?? (json['pbv'] as num?)?.toDouble() ?? 0.0,
      roe: parsePct(json['returnOnEquity'], json['roe']),
      roic: parsePct(json['returnOnAssets'], json['roic']),
      dyield: parsePct(json['dividendYield'], json['dividend_yield']),
      marketCap: (json['marketCap'] as num?)?.toDouble() ?? (json['market_cap'] as num?)?.toDouble() ?? 0.0,
      liabilities: (json['totalDebt'] as num?)?.toDouble() ?? (json['liabilities'] as num?)?.toDouble() ?? 0.0,
      equity: (json['equity'] as num?)?.toDouble() ?? calculatedEquity,
      revenue: (json['totalRevenue'] as num?)?.toDouble() ?? (json['revenue'] as num?)?.toDouble() ?? 0.0,
      netIncome: (json['netIncomeToCommon'] as num?)?.toDouble() ?? (json['net_income'] as num?)?.toDouble() ?? 0.0,
    );
  }
}