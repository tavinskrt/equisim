/// Calendário de dias úteis do mercado brasileiro, para taxas na base 252.
///
/// **Por que existe.** A taxa dos títulos prefixados é efetiva anual na base de
/// 252 dias úteis: `PU = 1000 ÷ (1 + taxa)^(du ÷ 252)`. Medir o prazo em dias
/// corridos e dividir por 365,25 descasa prazo e taxa — pouco no prazo longo,
/// e bastante no curto, onde um Carnaval inteiro cabe no vértice.
///
/// **Conferido contra o preço.** O arquivo do Tesouro Direto traz taxa e PU de
/// cada título, e o `du` implícito sai de `252 · ln(1000 ÷ PU) ÷ ln(1 + taxa)`.
/// Em 14/09/2026, sobre as 19.171 cotações de LTN desde 2010, o `du` deste
/// calendário bateu **ao dia em 99,13%**. O que sobra é fronteira de vigência
/// de feriado e dia atípico de pregão.
///
/// **Duas regras que a conferência ensinou**, e sem as quais a taxa de acerto
/// era de 83,9%:
///
/// 1. **O calendário é o conhecido na data.** O Dia da Consciência Negra virou
///    feriado nacional pela Lei 14.759, de 21/12/2023. Quem precificava em 2022
///    não o descontava dos anos futuros — e a diferença crescia com o prazo, de
///    um dia por ano de vencimento depois de 2024. [knownAt] reproduz isso.
/// 2. **O prazo conta da liquidação**, no dia útil seguinte à data-base, e a
///    liquidação não acontece em 24/12 nem em 31/12 — dias úteis no calendário
///    nacional, mas sem liquidação na B3.
///
/// Só feriados **nacionais**, que são os que o calendário da ANBIMA usa para
/// título público. Feriado estadual e municipal não entra.
library;

/// Dias úteis no calendário nacional.
abstract final class BrazilianCalendar {
  /// A partir de quando o 20 de novembro é feriado conhecido.
  ///
  /// A lei é de 21/12/2023; o preço do Tesouro de 22/12/2023 ainda não o
  /// descontava, e o de 26/12/2023 já.
  static final DateTime conscienciaNegraConhecidaDesde = DateTime.utc(2023, 12, 26);

  /// Domingo de Páscoa, pelo algoritmo anônimo do calendário gregoriano.
  static DateTime easter(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final mes = (h + l - 7 * m + 114) ~/ 31;
    final dia = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime.utc(year, mes, dia);
  }

  static final Map<int, Set<int>> _porAno = {};
  static final Map<int, Set<int>> _porAnoSemConscienciaNegra = {};

  static int _chave(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime _dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static Set<int> _feriados(int ano, {required bool comConscienciaNegra}) {
    final cache =
        comConscienciaNegra ? _porAno : _porAnoSemConscienciaNegra;
    return cache.putIfAbsent(ano, () {
      final p = easter(ano);
      DateTime rel(int dias) => DateTime.utc(p.year, p.month, p.day + dias);
      return {
        _chave(DateTime.utc(ano, 1, 1)), // Confraternização Universal
        _chave(rel(-48)), // Carnaval, segunda
        _chave(rel(-47)), // Carnaval, terça
        _chave(rel(-2)), // Sexta-feira da Paixão
        _chave(DateTime.utc(ano, 4, 21)), // Tiradentes
        _chave(DateTime.utc(ano, 5, 1)), // Dia do Trabalho
        _chave(rel(60)), // Corpus Christi
        _chave(DateTime.utc(ano, 9, 7)), // Independência
        _chave(DateTime.utc(ano, 10, 12)), // Nossa Senhora Aparecida
        _chave(DateTime.utc(ano, 11, 2)), // Finados
        _chave(DateTime.utc(ano, 11, 15)), // Proclamação da República
        if (comConscienciaNegra && ano >= 2024)
          _chave(DateTime.utc(ano, 11, 20)), // Consciência Negra
        _chave(DateTime.utc(ano, 12, 25)), // Natal
      };
    });
  }

  /// `true` quando [day] é dia útil no calendário conhecido em [knownAt].
  ///
  /// Sem [knownAt], vale o calendário de hoje.
  static bool isBusinessDay(DateTime day, {DateTime? knownAt}) {
    final d = _dia(day);
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      return false;
    }
    final comConscienciaNegra = knownAt == null ||
        !_dia(knownAt).isBefore(conscienciaNegraConhecidaDesde);
    return !_feriados(d.year, comConscienciaNegra: comConscienciaNegra)
        .contains(_chave(d));
  }

  /// Dias úteis em `[from, to)` — o primeiro conta, o último não.
  ///
  /// Zero quando [to] não é posterior a [from].
  static int businessDaysBetween(
    DateTime from,
    DateTime to, {
    DateTime? knownAt,
  }) {
    final inicio = _dia(from);
    final fim = _dia(to);
    var n = 0;
    for (var d = inicio;
        d.isBefore(fim);
        d = DateTime.utc(d.year, d.month, d.day + 1)) {
      if (isBusinessDay(d, knownAt: knownAt)) n++;
    }
    return n;
  }

  /// Liquidação de um título público negociado em [tradeDate]: o dia útil
  /// seguinte, pulando 24/12 e 31/12, em que a B3 não liquida.
  static DateTime treasurySettlement(DateTime tradeDate) {
    var d = _dia(tradeDate);
    do {
      d = DateTime.utc(d.year, d.month, d.day + 1);
    } while (!isBusinessDay(d, knownAt: tradeDate) ||
        (d.month == 12 && (d.day == 24 || d.day == 31)));
    return d;
  }
}
