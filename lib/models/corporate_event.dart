/// Representa um evento corporativo ocorrido na B3 (Split ou Inplit).
class CorporateEvent {
  final DateTime date;
  final String type; // 'SPLIT' ou 'INPLIT'
  final int ratioFrom;
  final int ratioTo;
  final String description;
  final double factor;

  CorporateEvent({
    required this.date,
    required this.type,
    required this.ratioFrom,
    required this.ratioTo,
    required this.description,
    required this.factor,
  });

  /// Instancia o objeto a partir da resposta JSON da API brapi.dev ou legada.
  factory CorporateEvent.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] ?? json['approvedOn'] ?? json['lastDatePrior'] ?? json['trade_date'];
    DateTime parsedDate;
    if (rawDate is String && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return CorporateEvent(
      date: parsedDate,
      type: json['type'] ?? json['label'] ?? '',
      ratioFrom: (json['ratioFrom'] as num?)?.toInt() ?? (json['ratio_from'] as num?)?.toInt() ?? 1,
      ratioTo: (json['ratioTo'] as num?)?.toInt() ?? (json['ratio_to'] as num?)?.toInt() ?? 1,
      description: json['description'] ?? json['remarks'] ?? '',
      factor: (json['factor'] as num?)?.toDouble() ?? (json['factor_rate'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
