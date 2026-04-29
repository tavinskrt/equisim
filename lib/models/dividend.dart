/// Modelo para dados de dividendos
class Dividend {
  final String date;
  final double value;
  final String type; // COM ou EX

  Dividend({
    required this.date,
    required this.value,
    required this.type,
  });

  factory Dividend.fromJson(Map<String, dynamic> json) {
    return Dividend(
      date: json['date'] ?? json['ex_date'] ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] ?? 'COM',
    );
  }
}

/// Sumário de histórico de dividendos
class DividendHistory {
  final List<Dividend> dividends;
  final double totalAnnualDividend;
  final double averageDividend;

  DividendHistory({
    required this.dividends,
    required this.totalAnnualDividend,
    required this.averageDividend
  });

  factory DividendHistory.fromDividends(List<Dividend> dividends) {
    if (dividends.isEmpty) {
      return DividendHistory(
        dividends: [],
        totalAnnualDividend: 0,
        averageDividend: 0
      );
    }

    final total = dividends.fold(0.0, (sum, d) => sum + d.value);
    final average = total / dividends.length;

    return DividendHistory(
      dividends: dividends,
      totalAnnualDividend: total,
      averageDividend: average
    );
  }
}

