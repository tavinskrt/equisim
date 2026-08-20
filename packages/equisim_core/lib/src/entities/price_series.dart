import '../value_objects/ticker.dart';

/// Cotação de fechamento de um pregão.
///
/// [close] vem ajustado por desdobramentos e grupamentos, mas **não** por
/// proventos (convenção Yahoo, verificada em BBAS3 15/04/2024 e WEGE3
/// 27/04/2021 — nenhuma descontinuidade nas datas-ex de split).
///
/// [adjustedClose] é série de retorno total, porém **subajusta proventos
/// brasileiros** — não deve ser usada em cálculo, apenas conferência.
class PricePoint {
  final DateTime date;
  final double close;
  final double? adjustedClose;

  PricePoint({
    required DateTime date,
    required this.close,
    this.adjustedClose,
  }) : date = DateTime(date.year, date.month, date.day);
}

/// Série histórica de preços de um ativo, ordenada cronologicamente.
class PriceSeries {
  final Ticker ticker;
  final List<PricePoint> points;

  PriceSeries({required this.ticker, required List<PricePoint> points})
      : points = List<PricePoint>.unmodifiable(
          <PricePoint>[...points]
            ..sort((PricePoint a, PricePoint b) => a.date.compareTo(b.date)),
        );

  bool get isEmpty => points.isEmpty;
  bool get isNotEmpty => points.isNotEmpty;
  DateTime get firstDate => points.first.date;
  DateTime get lastDate => points.last.date;

  /// Índice por data, construído sob demanda.
  late final Map<DateTime, double> _byDate = {
    for (final p in points) p.date: p.close,
  };

  double? closeOn(DateTime date) => _byDate[DateTime(date.year, date.month, date.day)];

  /// Último fechamento conhecido em ou antes de [date] — *forward fill*.
  ///
  /// Necessário porque pregões não coincidem perfeitamente entre ativos
  /// (leilões, suspensões, feriados regionais).
  double? closeAsOf(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    final direct = _byDate[target];
    if (direct != null) return direct;

    var lo = 0;
    var hi = points.length - 1;
    int? best;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (!points[mid].date.isAfter(target)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best == null ? null : points[best].close;
  }

  List<DateTime> get dates => points.map((p) => p.date).toList();
}
