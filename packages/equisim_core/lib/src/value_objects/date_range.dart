/// Intervalo de datas fechado em ambas as pontas.
///
/// Ambas as pontas são **truncadas para o dia** na construção: hora, minuto e
/// fuso são descartados. É o que torna a comparação com datas de pregão e de
/// divulgação estável, sem depender de o chamador ter normalizado.
class DateRange {
  /// Primeiro dia do intervalo, à meia-noite local.
  final DateTime start;

  /// Último dia do intervalo, à meia-noite local. Pertence ao intervalo.
  final DateTime end;

  /// Constrói o intervalo truncando as duas datas para o dia.
  ///
  /// - [start]: data inicial. A componente de hora é descartada.
  /// - [end]: data final, inclusiva. A componente de hora é descartada.
  ///
  /// Lança [ArgumentError] se, **depois do truncamento**, `end` for anterior a
  /// `start`. Um intervalo de um único dia (`start == end`) é válido e tem
  /// [days] igual a zero.
  DateRange(DateTime start, DateTime end)
      : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Data final ($end) anterior à inicial ($start).');
    }
  }

  /// Dias decorridos entre as pontas.
  ///
  /// É a **diferença**, não a contagem de dias contidos: um intervalo de um
  /// único dia devolve `0`, e `01/01` a `02/01` devolve `1`.
  int get days => end.difference(start).inDays;

  /// Fração de anos, considerando anos bissextos.
  ///
  /// Usa 365,25 dias por ano — a média do ciclo de quatro anos. É a base de
  /// contagem de toda anualização do pacote, e está declarada aqui de propósito
  /// para que a escolha seja única e auditável em vez de repetida em cada
  /// serviço.
  double get years => days / 365.25;

  /// Diferença em meses de **calendário**, ignorando o dia do mês.
  ///
  /// Não é "meses inteiros decorridos". A conta é
  /// `(anoFim − anoInício)·12 + mêsFim − mêsInício`, então o dia não entra.
  /// Verificado: `31/01/2026 → 01/02/2026` devolve **1**, embora tenha passado
  /// um único dia; `01/01/2026 → 31/01/2026` devolve **0**, embora tenham
  /// passado trinta.
  ///
  /// Serve para rotular eixos e contar competências mensais. **Não use para
  /// prazo de meta** — ali o prazo é declarado pelo usuário em
  /// `FinancialGoal.months`, não derivado de um intervalo.
  int get months => (end.year - start.year) * 12 + end.month - start.month;

  /// `true` se [d] cai dentro do intervalo, com as duas pontas incluídas.
  ///
  /// [d] é truncada para o dia antes da comparação, então a hora informada
  /// é irrelevante.
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
