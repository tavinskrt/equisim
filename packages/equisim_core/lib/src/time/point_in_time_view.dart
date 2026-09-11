import '../entities/fundamentals.dart';

/// Recorte temporal que impede o uso de informação ainda não publicada.
///
/// Um balanço encerrado em 31/12/2025 não estava disponível ao público em
/// 15/01/2026 — a divulgação à CVM leva meses. Consultar a série completa e
/// filtrar "na mão" funciona até alguém esquecer; por isso o filtro vive aqui,
/// e o motor recebe esta visão em vez da série bruta.
///
/// No Escopo B o valuation é prospectivo (calculado para hoje) e o backtest não
/// toma decisões, então o risco de look-ahead é bem menor do que seria numa
/// simulação de decisões passadas. A barreira é mantida por ser barata e por
/// cobrir o caso real de "qual exercício já foi divulgado nesta data".
class PointInTimeView {
  /// Data de referência da análise.
  final DateTime asOf;

  /// Defasagem **presumida** entre o encerramento do exercício e sua
  /// divulgação, usada apenas quando o exercício não traz a data real.
  ///
  /// Deixou de ser a regra em 11/09/2026: onde há `FundamentalsSnapshot.
  /// receiptDate` — o `DT_RECEB` da CVM —, a publicidade é **observada**, e
  /// esta defasagem não é consultada.
  final Duration publicationLag;

  PointInTimeView(DateTime asOf, {this.publicationLag = defaultLag})
      : asOf = DateTime(asOf.year, asOf.month, asOf.day);

  /// 90 dias — parâmetro declarado da metodologia, sujeito a análise
  /// de sensibilidade.
  ///
  /// **É conservador, e agora se sabe quanto.** A conferência de 11/09/2026
  /// sobre o `DT_RECEB` da CVM mediu defasagem real com mediana de **78 dias**
  /// no documento anual — p90 em 90, máximo em 472 — e de **40 dias** no
  /// trimestral. Presumir 90 atrasa o anual em 12 dias na mediana e o
  /// trimestral em 50.
  static const Duration defaultLag = Duration(days: 90);

  /// Data-limite de encerramento de exercício **presumido** público em [asOf].
  ///
  /// Vale só para exercício sem data de recebimento. Ver [isPublished].
  DateTime get cutoff => asOf.subtract(publicationLag);

  /// Verdadeiro se o exercício já era público na data de referência.
  ///
  /// **Prefere a data observada.** Com `receiptDate` preenchido, a pergunta é
  /// direta — o documento já tinha sido recebido em [asOf]? — e a defasagem
  /// presumida não entra na conta. Sem ela, recua para [cutoff].
  ///
  /// A diferença não é cosmética: um exercício encerrado em 31/12 e recebido
  /// em 19/02 é público desde fevereiro, e a presunção de 90 dias só o
  /// admitiria em 31/03. Numa coorte de 31/03 isso é a diferença entre avaliar
  /// com o exercício mais recente e avaliar com o anterior.
  bool isPublished(FundamentalsSnapshot snapshot) {
    final recebido = snapshot.receiptDate;
    if (recebido != null) return !_depoisDe(recebido, asOf);
    return !_depoisDe(snapshot.fiscalPeriodEnd, cutoff);
  }

  /// `a` é um dia civil posterior a `b`?
  ///
  /// **Compara ano, mês e dia, e nunca instantes.** As datas deste domínio
  /// chegam de origens diferentes — a de recebimento vem de `DT_RECEB`, a de
  /// encerramento vem da série de fundamentos —, e um `DateTime` local e um
  /// UTC do mesmo dia civil são instantes distintos. Comparar com `isAfter`
  /// faria a publicidade de um exercício depender do fuso da máquina, que é
  /// o mesmo defeito que a contagem de pregões de `MarketLeverage` corrigiu.
  static bool _depoisDe(DateTime a, DateTime b) {
    if (a.year != b.year) return a.year > b.year;
    if (a.month != b.month) return a.month > b.month;
    return a.day > b.day;
  }

  /// Subconjunto já divulgado, em ordem cronológica.
  List<FundamentalsSnapshot> published(List<FundamentalsSnapshot> all) =>
      all.where(isPublished).toList()
        ..sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));

  /// Exercício mais recente já divulgado, ou `null` se nenhum.
  FundamentalsSnapshot? latestPublished(List<FundamentalsSnapshot> all) {
    final visible = published(all);
    return visible.isEmpty ? null : visible.last;
  }

  /// Os [n] exercícios mais recentes já divulgados, do mais antigo ao mais novo.
  List<FundamentalsSnapshot> latestPublishedRange(
    List<FundamentalsSnapshot> all,
    int n,
  ) {
    final visible = published(all);
    if (visible.length <= n) return visible;
    return visible.sublist(visible.length - n);
  }
}
