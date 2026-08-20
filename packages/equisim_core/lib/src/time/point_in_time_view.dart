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

  /// Defasagem entre o encerramento do exercício e sua divulgação pública.
  final Duration publicationLag;

  PointInTimeView(DateTime asOf, {this.publicationLag = defaultLag})
      : asOf = DateTime(asOf.year, asOf.month, asOf.day);

  /// 90 dias — parâmetro declarado da metodologia, sujeito a análise
  /// de sensibilidade.
  static const Duration defaultLag = Duration(days: 90);

  /// Data-limite de encerramento de exercício considerado público em [asOf].
  DateTime get cutoff => asOf.subtract(publicationLag);

  /// Verdadeiro se o exercício já era público na data de referência.
  bool isPublished(FundamentalsSnapshot snapshot) =>
      !snapshot.fiscalPeriodEnd.isAfter(cutoff);

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
