/// O prazo das outorgas, lido do Formulário de Referência da CVM (item A6).
library;

/// Fim de contrato de concessão a partir do texto livre do Formulário de
/// Referência.
///
/// O quadro de ativos intangíveis do FRE (item 9.1.b) lista cada concessão com
/// uma coluna `Duracao` **em texto livre**: "até julho/2045", "De 11/08/2017 até
/// 11/08/2047", "30 anos, a partir de 03/2019", "2028, prorrogável até 2058",
/// "Prazo indeterminado". Não há campo de data, e não há peso por contrato.
///
/// **O que o prazo corta.** O terminal neutro que a decisão 50 impõe a toda
/// concessão recusa o valor do capital novo, mas mantém para sempre o excedente
/// do capital existente. O contrato que acaba paga esse excedente só até o fim
/// e devolve o capital — pela amortização, pela indenização do não amortizado
/// ou por renovação ao custo de capital. Onde o capital rende exatamente o
/// custo dele, o prazo não muda nada. Ver `DcfAssumptions.contractYearsAfterHorizon`
/// e a decisão 88.
abstract final class FreConcessionTerm {
  static const Map<String, int> _months = {
    'janeiro': 1, 'jan': 1,
    'fevereiro': 2, 'fev': 2,
    'marco': 3, 'mar': 3,
    'abril': 4, 'abr': 4,
    'maio': 5, 'mai': 5,
    'junho': 6, 'jun': 6,
    'julho': 7, 'jul': 7,
    'agosto': 8, 'ago': 8,
    'setembro': 9, 'set': 9,
    'outubro': 10, 'out': 10,
    'novembro': 11, 'nov': 11,
    'dezembro': 12, 'dez': 12,
  };

  static final RegExp _dayMonthYear =
      RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?!\d)');
  static final RegExp _monthNameYear = RegExp(
      r'\b(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|'
      r'outubro|novembro|dezembro|jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|'
      r'dez)\s*(?:de|/)\s*(\d{4})\b');
  static final RegExp _monthYear = RegExp(r'(?<![\d./-])(\d{1,2})/(\d{4})\b');
  static final RegExp _year = RegExp(r'(?<![\d./-])((?:19|20)\d{2})(?![\d./-])');
  static final RegExp _startingFrom =
      RegExp(r'(\d{1,3})\s*anos?\s*,?\s*(?:contados\s*)?a\s*partir');

  /// Fim do contrato descrito por [duration], ou `null` quando o texto não dá
  /// uma data absoluta.
  ///
  /// Recusa, e não adivinha: "Prazo indeterminado", "Vide item 9.1", e prazo
  /// relativo sem início ("6 anos") devolvem `null`.
  ///
  /// - "N anos, a partir de <data>" soma N anos ao início.
  /// - Com "prorrogável", vale o prazo **antes** da prorrogação: é o que o
  ///   contrato garante hoje, e a renovação refaz a tarifa.
  /// - Havendo várias datas — "de X a Y" —, vale a última.
  /// - Mês sem dia é o último dia do mês; ano sozinho, 31 de dezembro.
  static DateTime? endOf(String? duration) {
    if (duration == null) return null;
    var text = _normalize(duration);
    if (text.isEmpty || text.contains('indeterminad')) return null;

    // "prorrogável", "prorrogação" e a abreviação "Prorr." do formulário.
    final renewalIndex = text.indexOf('prorr');
    if (renewalIndex >= 0) text = text.substring(0, renewalIndex);

    final dates = <({int pos, DateTime date})>[];
    for (final m in _dayMonthYear.allMatches(text)) {
      final d = _date(int.parse(m.group(3)!), int.parse(m.group(2)!),
          int.parse(m.group(1)!));
      if (d != null) dates.add((pos: m.start, date: d));
    }
    for (final m in _monthNameYear.allMatches(text)) {
      final d = _endOfMonth(int.parse(m.group(2)!), _months[m.group(1)!]!);
      if (d != null) dates.add((pos: m.start, date: d));
    }
    for (final m in _monthYear.allMatches(text)) {
      final d = _endOfMonth(int.parse(m.group(2)!), int.parse(m.group(1)!));
      if (d != null) dates.add((pos: m.start, date: d));
    }

    final startingFrom = _startingFrom.firstMatch(text);
    if (startingFrom != null) {
      final start = dates.where((d) => d.pos > startingFrom.start).toList();
      if (start.isEmpty) return null;
      final i = start.first.date;
      return DateTime.utc(i.year + int.parse(startingFrom.group(1)!), i.month, i.day);
    }

    if (dates.isEmpty) {
      for (final m in _year.allMatches(text)) {
        dates.add((pos: m.start, date: DateTime.utc(int.parse(m.group(1)!), 12, 31)));
      }
    }
    if (dates.isEmpty) return null;
    dates.sort((a, b) => a.pos.compareTo(b.pos));
    return dates.last.date;
  }

  /// Resumo das concessões de uma companhia num documento.
  ///
  /// - [durations]: a coluna `Duracao` de cada concessão do documento.
  /// - [reference]: data de referência do documento. Contrato que já tinha
  ///   acabado nela não conta — o FRE repete contrato vencido e renovado com o
  ///   prazo antigo, como a distribuição da Cemig "até fevereiro de 2016" no
  ///   formulário de 2019.
  ///
  /// [end] é a **mediana** dos fins vigentes. Sem peso por contrato no FRE, a
  /// mediana é a leitura que um contrato pequeno e extremo não arrasta.
  static ({DateTime? end, int contracts, int readCount, int inForceCount}) summarize(
      Iterable<String?> durations, DateTime reference) {
    var contracts = 0;
    var readCount = 0;
    final inForceEnds = <DateTime>[];
    for (final d in durations) {
      contracts++;
      final end = endOf(d);
      if (end == null) continue;
      readCount++;
      if (end.isAfter(reference)) inForceEnds.add(end);
    }
    if (inForceEnds.isEmpty) {
      return (end: null, contracts: contracts, readCount: readCount, inForceCount: 0);
    }
    inForceEnds.sort();
    // Mediana baixa com número par: a data tem de ser uma das observadas.
    final median = inForceEnds[(inForceEnds.length - 1) ~/ 2];
    return (
      end: median,
      contracts: contracts,
      readCount: readCount,
      inForceCount: inForceEnds.length,
    );
  }

  static DateTime? _date(int year, int month, int day) {
    final a = year < 100 ? 2000 + year : year;
    if (month < 1 || month > 12 || day < 1 || day > 31 || a < 1900 || a > 2200) {
      return null;
    }
    final d = DateTime.utc(a, month, day);
    // `DateTime` normaliza 31/02 para março; data que não existe é recusada.
    return d.month == month ? d : null;
  }

  static DateTime? _endOfMonth(int year, int month) {
    if (month < 1 || month > 12 || year < 1900 || year > 2200) return null;
    return DateTime.utc(year, month + 1, 0);
  }

  /// Minúsculas, sem acento. O FRE mistura "Março", "MARCO" e "março".
  static String _normalize(String s) {
    const accented = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const plain = 'aaaaaeeeeiiiiooooouuuuc';
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      final i = accented.indexOf(c);
      b.write(i >= 0 ? plain[i] : c);
    }
    return b.toString().trim();
  }
}

/// O prazo lido para um ativo, com o que sustenta a leitura.
class ConcessionTerm {
  /// Mediana dos fins das outorgas vigentes.
  final DateTime end;

  /// Concessões listadas no documento.
  final int contracts;

  /// Delas, com data de fim legível.
  final int parsed;

  /// Delas, ainda vigentes na data de referência do documento.
  final int active;

  /// Data de referência do Formulário de Referência lido.
  final DateTime reference;

  /// Declara o prazo.
  const ConcessionTerm({
    required this.end,
    required this.contracts,
    required this.parsed,
    required this.active,
    required this.reference,
  });
}

/// Formato do pacote de prazos, para empacotar no aplicativo (item A6).
///
/// Mora no núcleo pela mesma razão do `CvmDocumentCodec`: a ferramenta que
/// grava e o repositório que lê precisam concordar sobre o formato.
abstract final class ConcessionTermsCodec {
  /// Versão do formato.
  static const int version = 1;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _date(Object? v) {
    if (v is! String || v.length < 10) return null;
    final p = v.substring(0, 10).split('-');
    if (p.length != 3) return null;
    final a = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (a == null || m == null || d == null) return null;
    return DateTime.utc(a, m, d);
  }

  /// O pacote inteiro.
  static Map<String, Object> encode(Map<String, ConcessionTerm> terms,
          {required DateTime generatedAt}) =>
      {
        'versao': version,
        'geradoEm': _day(generatedAt),
        'tickers': {
          for (final e in terms.entries)
            e.key: {
              'fim': _day(e.value.end),
              'contratos': e.value.contracts,
              'lidos': e.value.parsed,
              'vigentes': e.value.active,
              'referencia': _day(e.value.reference),
            },
        },
      };

  /// Lê o pacote. Versão desconhecida devolve mapa vazio.
  static Map<String, ConcessionTerm> decode(Map<String, dynamic> package) {
    if (package['versao'] != version) return const {};
    final tickers = package['tickers'];
    if (tickers is! Map<String, dynamic>) return const {};
    final out = <String, ConcessionTerm>{};
    for (final e in tickers.entries) {
      final v = e.value;
      if (v is! Map<String, dynamic>) continue;
      final end = _date(v['fim']);
      final ref = _date(v['referencia']);
      if (end == null || ref == null) continue;
      out[e.key] = ConcessionTerm(
        end: end,
        contracts: (v['contratos'] as num?)?.toInt() ?? 0,
        parsed: (v['lidos'] as num?)?.toInt() ?? 0,
        active: (v['vigentes'] as num?)?.toInt() ?? 0,
        reference: ref,
      );
    }
    return out;
  }
}
