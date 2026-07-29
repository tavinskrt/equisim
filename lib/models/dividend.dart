/// Representa o pagamento individual de um dividendo ou rendimento (FII).
class Dividend {
  final String exDate;
  final String paymentDate;
  final double value;
  final String type; // COM (Comum) ou EX (Ex-dividendos)

  String get date => paymentDate;

  Dividend({
    required this.exDate,
    required this.paymentDate,
    required this.value,
    required this.type,
  });

  /// Instancia o dividendo a partir do JSON retornado pela API brapi.dev ou legada.
  factory Dividend.fromJson(Map<String, dynamic> json) {
    String formatDate(dynamic raw) {
      if (raw == null) return '';
      if (raw is String) {
        if (raw.contains('T')) {
          return raw.split('T')[0];
        }
        return raw;
      }
      return raw.toString();
    }

    final String ex = formatDate(json['lastDatePrior'] ?? json['ex_date'] ?? json['date'] ?? json['payment_date'] ?? json['reference_date']);
    final String pay = formatDate(json['paymentDate'] ?? json['payment_date'] ?? json['date'] ?? json['ex_date'] ?? json['reference_date']);
    final double val = (json['rate'] as num?)?.toDouble() ??
        (json['value_per_share'] as num?)?.toDouble() ??
        (json['value'] as num?)?.toDouble() ?? 0.0;
    final String t = json['label'] ?? json['type'] ?? 'COM';

    return Dividend(
      exDate: ex,
      paymentDate: pay,
      value: val,
      type: t,
    );
  }
}

/// Representa o resumo consolidado do histórico de dividendos de um determinado ativo.
class DividendHistory {
  final List<Dividend> dividends;
  final double totalAnnualDividend;
  final double averageDividend;

  DividendHistory({
    required this.dividends,
    required this.totalAnnualDividend,
    required this.averageDividend
  });

  /// Cria um sumário de dividendos a partir de uma lista bruta de lançamentos.
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
