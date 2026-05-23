/// Modelo para dados de dividendos
class Dividend {
  final String exDate;
  final String paymentDate;
  final double value;
  final String type; // COM ou EX

  String get date => paymentDate;

  Dividend({
    required this.exDate,
    required this.paymentDate,
    required this.value,
    required this.type,
  });

  factory Dividend.fromJson(Map<String, dynamic> json) {
    final String ex = json['ex_date'] ?? json['date'] ?? json['payment_date'] ?? json['reference_date'] ?? '';
    final String pay = json['payment_date'] ?? json['date'] ?? json['ex_date'] ?? json['reference_date'] ?? '';
    return Dividend(
      exDate: ex,
      paymentDate: pay,
      value: (json['value_per_share'] as num?)?.toDouble() ?? 
             (json['value'] as num?)?.toDouble() ?? 0.0,
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

