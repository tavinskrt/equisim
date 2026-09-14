/// Contagem de ações por data, do Formulário de Referência (item A3.4).
library;

/// De onde veio um ponto da série.
enum ShareCountSource {
  /// Aprovação de capital, pela contagem da primeira declaração dela.
  capitalApproval,

  /// Desdobramento, grupamento ou bonificação declarado, pela contagem depois.
  shareEvent,

  /// Contagem de um formulário que a série não explicava, datada no
  /// recebimento dele — evento de ações que o formulário não declarou.
  filingCorrection,
}

/// Uma contagem de ações que vale a partir de [date].
class ShareCountPoint {
  /// A partir de quando a contagem vale.
  final DateTime date;

  /// Ações do capital, somadas as classes.
  final double total;

  /// De onde veio.
  final ShareCountSource source;

  /// Declara o ponto.
  const ShareCountPoint({
    required this.date,
    required this.total,
    required this.source,
  });
}

/// Um evento de ações declarado no FRE: a contagem depois dele.
typedef DeclaredShareEvent = ({DateTime date, double totalAfter});

/// A contagem de ações de uma companhia ao longo do tempo.
///
/// **De onde vem.** O quadro de capital social do FRE (item 17.1) declara, em
/// cada formulário, o capital **integralizado** com a data de aprovação e a
/// quantidade de ações. É a peça que falta para o backtest exercitar a ponte
/// por papel (limitações §3.5): a contagem oficial da B3 é de hoje e só de
/// emissor listado, e a coorte de 2015 com uma companhia que saiu da bolsa em
/// 2019 precisa da contagem de 2015.
///
/// **Três camadas, porque a data de aprovação não conta tudo.** Um grupamento
/// muda a contagem **sem** aprovar capital novo: o formulário seguinte repete a
/// data de aprovação antiga com a contagem nova. Ler a declaração mais recente
/// levaria a contagem de depois do grupamento para antes dele — a CPFL
/// Transmissão, com grupamento de 40 para 1 em 2016, saía com P/VPA de 0,01 de
/// 2010 a 2015. Por isso:
///
/// 1. cada aprovação de capital vale pela contagem da **primeira** declaração
///    dela, que é a da época;
/// 2. cada evento de ações declarado entra na data dele, com a contagem de
///    depois;
/// 3. um formulário cuja contagem a série não explica entra na data de
///    recebimento — o evento não declarado aconteceu antes dela.
class ShareCountHistory {
  /// Pontos em ordem de data.
  final List<ShareCountPoint> points;

  const ShareCountHistory._(this.points);

  /// Tipo de capital lido, em ordem de preferência: o integralizado é o que
  /// tem ação emitida e paga; o emitido é o recuo do formulário novo.
  static const List<String> tipos = ['Capital Integralizado', 'Capital Emitido'];

  /// Diferença a partir da qual a contagem de um formulário não é explicada
  /// pela série.
  static const double folgaDoFormulario = 0.01;

  /// Monta a série de **uma** companhia.
  ///
  /// - [linhas]: quadro de capital social, de qualquer número de formulários.
  /// - [events]: eventos de ações declarados, com a contagem depois.
  /// - [receivedOn]: data de recebimento de cada formulário, por
  ///   `ID_Documento`. Sem ela, o formulário não corrige a série.
  static ShareCountHistory fromFre(
    Iterable<Map<String, String>> linhas, {
    Iterable<DeclaredShareEvent> events = const [],
    Map<String, DateTime> receivedOn = const {},
  }) {
    for (final tipo in tipos) {
      final documentos = _documentos(linhas, tipo);
      if (documentos.isEmpty) continue;
      return _montar(documentos, events, receivedOn);
    }
    return const ShareCountHistory._([]);
  }

  /// Formulários do [tipo], cada referência na maior versão, em ordem.
  static List<_Documento> _documentos(
      Iterable<Map<String, String>> linhas, String tipo) {
    final porReferencia = <DateTime, _Documento>{};
    for (final r in linhas) {
      if (r['Tipo_Capital']?.trim() != tipo) continue;
      final aprovacao = _dia(r['Data_Autorizacao_Aprovacao']);
      final referencia = _dia(r['Data_Referencia']);
      final versao = int.tryParse(r['Versao'] ?? '') ?? 0;
      final total = double.tryParse(r['Quantidade_Total_Acoes'] ?? '');
      if (aprovacao == null || referencia == null) continue;
      if (total == null || !total.isFinite || total <= 0) continue;
      final atual = porReferencia[referencia];
      if (atual == null || versao > atual.versao) {
        porReferencia[referencia] = _Documento(
            referencia, versao, r['ID_Documento'] ?? '', [(aprovacao, total)]);
      } else if (versao == atual.versao) {
        atual.capitais.add((aprovacao, total));
      }
    }
    return porReferencia.values.toList()
      ..sort((a, b) => a.referencia.compareTo(b.referencia));
  }

  static ShareCountHistory _montar(
    List<_Documento> documentos,
    Iterable<DeclaredShareEvent> eventos,
    Map<String, DateTime> recebidos,
  ) {
    final pontos = <ShareCountPoint>[];
    final aprovacoes = <DateTime>[];
    for (final d in documentos) {
      for (final (aprovacao, total) in d.capitais) {
        if (aprovacoes.any((a) => a.isAtSameMomentAs(aprovacao))) continue;
        aprovacoes.add(aprovacao);
        pontos.add(ShareCountPoint(
            date: aprovacao, total: total, source: ShareCountSource.capitalApproval));
      }
    }
    for (final e in eventos) {
      if (!(e.totalAfter > 0)) continue;
      pontos.add(ShareCountPoint(
          date: _utc(e.date), total: e.totalAfter, source: ShareCountSource.shareEvent));
    }
    _ordenar(pontos);

    for (final d in documentos) {
      final recebido = recebidos[d.id];
      if (recebido == null) continue;
      // A contagem que o formulário diz vigente: a da aprovação mais recente.
      final ultima = d.capitais.reduce((a, b) => b.$1.isAfter(a.$1) ? b : a);
      final hoje = ShareCountHistory._(pontos).at(recebido);
      if (hoje != null &&
          (ultima.$2 / hoje.total - 1).abs() <= folgaDoFormulario) {
        continue;
      }
      pontos.add(ShareCountPoint(
          date: _utc(recebido),
          total: ultima.$2,
          source: ShareCountSource.filingCorrection));
      _ordenar(pontos);
    }
    return ShareCountHistory._(List.unmodifiable(pontos));
  }

  /// Por data; na mesma data, aprovação antes de evento antes de correção —
  /// quem vem depois vale.
  static void _ordenar(List<ShareCountPoint> pontos) => pontos.sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.source.index.compareTo(b.source.index);
      });

  /// Contagem em vigor em [data], ou `null` antes do primeiro ponto.
  ShareCountPoint? at(DateTime data) {
    final d = _utc(data);
    ShareCountPoint? vigente;
    for (final p in points) {
      if (p.date.isAfter(d)) break;
      vigente = p;
    }
    return vigente;
  }

  static DateTime _utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static DateTime? _dia(String? v) {
    if (v == null || v.length < 10) return null;
    return DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
  }
}

class _Documento {
  final DateTime referencia;
  final int versao;
  final String id;
  final List<(DateTime, double)> capitais;
  _Documento(this.referencia, this.versao, this.id, this.capitais);
}
