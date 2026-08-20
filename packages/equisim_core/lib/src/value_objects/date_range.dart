/// Intervalo de datas fechado em ambas as pontas.
class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange(DateTime start, DateTime end)
      : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Data final ($end) anterior à inicial ($start).');
    }
  }

  int get days => end.difference(start).inDays;

  /// Fração de anos, considerando anos bissextos.
  double get years => days / 365.25;

  /// Meses inteiros decorridos.
  int get months => (end.year - start.year) * 12 + end.month - start.month;

  bool contains(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      '${_fmt(start)} a ${_fmt(end)}';

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
