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
  static const List<String> kinds = ['Capital Integralizado', 'Capital Emitido'];

  /// Diferença a partir da qual a contagem de um formulário não é explicada
  /// pela série.
  static const double formMargin = 0.01;

  /// Monta a série de **uma** companhia.
  ///
  /// - [rows]: quadro de capital social, de qualquer número de formulários.
  /// - [events]: eventos de ações declarados, com a contagem depois.
  /// - [receivedOn]: data de recebimento de cada formulário, por
  ///   `ID_Documento`. Sem ela, o formulário não corrige a série.
  static ShareCountHistory fromFre(
    Iterable<Map<String, String>> rows, {
    Iterable<DeclaredShareEvent> events = const [],
    Map<String, DateTime> receivedOn = const {},
  }) {
    for (final kind in kinds) {
      final documents = _documents(rows, kind);
      if (documents.isEmpty) continue;
      return _build(documents, events, receivedOn);
    }
    return const ShareCountHistory._([]);
  }

  /// Formulários do [kind], cada referência na maior versão, em ordem.
  static List<_Document> _documents(
      Iterable<Map<String, String>> rows, String kind) {
    final byReference = <DateTime, _Document>{};
    for (final r in rows) {
      if (r['Tipo_Capital']?.trim() != kind) continue;
      final approval = _day(r['Data_Autorizacao_Aprovacao']);
      final reference = _day(r['Data_Referencia']);
      final version = int.tryParse(r['Versao'] ?? '') ?? 0;
      final total = double.tryParse(r['Quantidade_Total_Acoes'] ?? '');
      if (approval == null || reference == null) continue;
      if (total == null || !total.isFinite || total <= 0) continue;
      final current = byReference[reference];
      if (current == null || version > current.version) {
        byReference[reference] = _Document(
            reference, version, r['ID_Documento'] ?? '', [(approval, total)]);
      } else if (version == current.version) {
        current.capitals.add((approval, total));
      }
    }
    return byReference.values.toList()
      ..sort((a, b) => a.reference.compareTo(b.reference));
  }

  static ShareCountHistory _build(
    List<_Document> documents,
    Iterable<DeclaredShareEvent> events,
    Map<String, DateTime> receivedInputs,
  ) {
    final points = <ShareCountPoint>[];
    final approvals = <DateTime>[];
    for (final d in documents) {
      for (final (approval, total) in d.capitals) {
        if (approvals.any((a) => a.isAtSameMomentAs(approval))) continue;
        approvals.add(approval);
        points.add(ShareCountPoint(
            date: approval, total: total, source: ShareCountSource.capitalApproval));
      }
    }
    for (final e in events) {
      if (!(e.totalAfter > 0)) continue;
      points.add(ShareCountPoint(
          date: _utc(e.date), total: e.totalAfter, source: ShareCountSource.shareEvent));
    }
    _sort(points);

    for (final d in documents) {
      final received = receivedInputs[d.id];
      if (received == null) continue;
      // A contagem que o formulário diz vigente: a da aprovação mais recente.
      final last = d.capitals.reduce((a, b) => b.$1.isAfter(a.$1) ? b : a);
      final today = ShareCountHistory._(points).at(received);
      if (today != null &&
          (last.$2 / today.total - 1).abs() <= formMargin) {
        continue;
      }
      points.add(ShareCountPoint(
          date: _utc(received),
          total: last.$2,
          source: ShareCountSource.filingCorrection));
      _sort(points);
    }
    return ShareCountHistory._(List.unmodifiable(points));
  }

  /// Por data; na mesma data, aprovação antes de evento antes de correção —
  /// quem vem depois vale.
  static void _sort(List<ShareCountPoint> points) => points.sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.source.index.compareTo(b.source.index);
      });

  /// Contagem em vigor em [date], ou `null` antes do primeiro ponto.
  ShareCountPoint? at(DateTime date) {
    final d = _utc(date);
    ShareCountPoint? current;
    for (final p in points) {
      if (p.date.isAfter(d)) break;
      current = p;
    }
    return current;
  }

  static DateTime _utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static DateTime? _day(String? v) {
    if (v == null || v.length < 10) return null;
    return DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
  }
}

class _Document {
  final DateTime reference;
  final int version;
  final String id;
  final List<(DateTime, double)> capitals;
  _Document(this.reference, this.version, this.id, this.capitals);
}
