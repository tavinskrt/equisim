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
  static const Map<String, int> _meses = {
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

  static final RegExp _diaMesAno =
      RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?!\d)');
  static final RegExp _mesNomeAno = RegExp(
      r'\b(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|'
      r'outubro|novembro|dezembro|jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|'
      r'dez)\s*(?:de|/)\s*(\d{4})\b');
  static final RegExp _mesAno = RegExp(r'(?<![\d./-])(\d{1,2})/(\d{4})\b');
  static final RegExp _ano = RegExp(r'(?<![\d./-])((?:19|20)\d{2})(?![\d./-])');
  static final RegExp _aPartir =
      RegExp(r'(\d{1,3})\s*anos?\s*,?\s*(?:contados\s*)?a\s*partir');

  /// Fim do contrato descrito por [duracao], ou `null` quando o texto não dá
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
  static DateTime? endOf(String? duracao) {
    if (duracao == null) return null;
    var texto = _normalizar(duracao);
    if (texto.isEmpty || texto.contains('indeterminad')) return null;

    // "prorrogável", "prorrogação" e a abreviação "Prorr." do formulário.
    final prorroga = texto.indexOf('prorr');
    if (prorroga >= 0) texto = texto.substring(0, prorroga);

    final datas = <({int pos, DateTime data})>[];
    for (final m in _diaMesAno.allMatches(texto)) {
      final d = _data(int.parse(m.group(3)!), int.parse(m.group(2)!),
          int.parse(m.group(1)!));
      if (d != null) datas.add((pos: m.start, data: d));
    }
    for (final m in _mesNomeAno.allMatches(texto)) {
      final d = _fimDoMes(int.parse(m.group(2)!), _meses[m.group(1)!]!);
      if (d != null) datas.add((pos: m.start, data: d));
    }
    for (final m in _mesAno.allMatches(texto)) {
      final d = _fimDoMes(int.parse(m.group(2)!), int.parse(m.group(1)!));
      if (d != null) datas.add((pos: m.start, data: d));
    }

    final aPartir = _aPartir.firstMatch(texto);
    if (aPartir != null) {
      final inicio = datas.where((d) => d.pos > aPartir.start).toList();
      if (inicio.isEmpty) return null;
      final i = inicio.first.data;
      return DateTime.utc(i.year + int.parse(aPartir.group(1)!), i.month, i.day);
    }

    if (datas.isEmpty) {
      for (final m in _ano.allMatches(texto)) {
        datas.add((pos: m.start, data: DateTime.utc(int.parse(m.group(1)!), 12, 31)));
      }
    }
    if (datas.isEmpty) return null;
    datas.sort((a, b) => a.pos.compareTo(b.pos));
    return datas.last.data;
  }

  /// Resumo das concessões de uma companhia num documento.
  ///
  /// - [duracoes]: a coluna `Duracao` de cada concessão do documento.
  /// - [referencia]: data de referência do documento. Contrato que já tinha
  ///   acabado nela não conta — o FRE repete contrato vencido e renovado com o
  ///   prazo antigo, como a distribuição da Cemig "até fevereiro de 2016" no
  ///   formulário de 2019.
  ///
  /// [end] é a **mediana** dos fins vigentes. Sem peso por contrato no FRE, a
  /// mediana é a leitura que um contrato pequeno e extremo não arrasta.
  static ({DateTime? end, int contratos, int lidos, int vigentes}) summarize(
      Iterable<String?> duracoes, DateTime referencia) {
    var contratos = 0;
    var lidos = 0;
    final vigentes = <DateTime>[];
    for (final d in duracoes) {
      contratos++;
      final fim = endOf(d);
      if (fim == null) continue;
      lidos++;
      if (fim.isAfter(referencia)) vigentes.add(fim);
    }
    if (vigentes.isEmpty) {
      return (end: null, contratos: contratos, lidos: lidos, vigentes: 0);
    }
    vigentes.sort();
    // Mediana baixa com número par: a data tem de ser uma das observadas.
    final mediana = vigentes[(vigentes.length - 1) ~/ 2];
    return (
      end: mediana,
      contratos: contratos,
      lidos: lidos,
      vigentes: vigentes.length,
    );
  }

  static DateTime? _data(int ano, int mes, int dia) {
    final a = ano < 100 ? 2000 + ano : ano;
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31 || a < 1900 || a > 2200) {
      return null;
    }
    final d = DateTime.utc(a, mes, dia);
    // `DateTime` normaliza 31/02 para março; data que não existe é recusada.
    return d.month == mes ? d : null;
  }

  static DateTime? _fimDoMes(int ano, int mes) {
    if (mes < 1 || mes > 12 || ano < 1900 || ano > 2200) return null;
    return DateTime.utc(ano, mes + 1, 0);
  }

  /// Minúsculas, sem acento. O FRE mistura "Março", "MARCO" e "março".
  static String _normalizar(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const para = 'aaaaaeeeeiiiiooooouuuuc';
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
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
  static const int versao = 1;

  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _data(Object? v) {
    if (v is! String || v.length < 10) return null;
    final p = v.substring(0, 10).split('-');
    if (p.length != 3) return null;
    final a = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (a == null || m == null || d == null) return null;
    return DateTime.utc(a, m, d);
  }

  /// O pacote inteiro.
  static Map<String, Object> encode(Map<String, ConcessionTerm> prazos,
          {required DateTime geradoEm}) =>
      {
        'versao': versao,
        'geradoEm': _dia(geradoEm),
        'tickers': {
          for (final e in prazos.entries)
            e.key: {
              'fim': _dia(e.value.end),
              'contratos': e.value.contracts,
              'lidos': e.value.parsed,
              'vigentes': e.value.active,
              'referencia': _dia(e.value.reference),
            },
        },
      };

  /// Lê o pacote. Versão desconhecida devolve mapa vazio.
  static Map<String, ConcessionTerm> decode(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return const {};
    final tickers = pacote['tickers'];
    if (tickers is! Map<String, dynamic>) return const {};
    final out = <String, ConcessionTerm>{};
    for (final e in tickers.entries) {
      final v = e.value;
      if (v is! Map<String, dynamic>) continue;
      final fim = _data(v['fim']);
      final ref = _data(v['referencia']);
      if (fim == null || ref == null) continue;
      out[e.key] = ConcessionTerm(
        end: fim,
        contracts: (v['contratos'] as num?)?.toInt() ?? 0,
        parsed: (v['lidos'] as num?)?.toInt() ?? 0,
        active: (v['vigentes'] as num?)?.toInt() ?? 0,
        reference: ref,
      );
    }
    return out;
  }
}
