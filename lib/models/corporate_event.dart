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

  /// Instancia o objeto a partir da resposta JSON da API Bolsai.
  factory CorporateEvent.fromJson(Map<String, dynamic> json) {
    return CorporateEvent(
      date: DateTime.parse(json['date'] ?? json['trade_date'] ?? ''),
      type: json['type'] ?? '',
      ratioFrom: (json['ratio_from'] as num?)?.toInt() ?? 1,
      ratioTo: (json['ratio_to'] as num?)?.toInt() ?? 1,
      description: json['description'] ?? '',
      factor: (json['factor'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
