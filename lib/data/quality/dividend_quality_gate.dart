import 'package:equisim_core/equisim_core.dart';

/// Situação do controle de qualidade dos proventos de um ativo.
enum DividendQuality {
  /// Fluxo de eventos bate com o DY publicado pela fonte.
  consistent,

  /// Divergência acima da tolerância: usar com ressalva.
  divergent,

  /// Não foi possível comparar (sem DY publicado ou sem preço).
  unverified,
}

/// Resultado da conferência.
class DividendQualityReport {
  final Ticker ticker;
  final DividendQuality status;
  final double? computedYield;
  final double? publishedYield;
  final double? deviation;
  final String message;

  const DividendQualityReport({
    required this.ticker,
    required this.status,
    required this.message,
    this.computedYield,
    this.publishedYield,
    this.deviation,
  });

  bool get isTrustworthy => status != DividendQuality.divergent;
}

/// Confere o fluxo de proventos contra o dividend yield publicado pela fonte.
///
/// **Por que este portão existe.** Durante a auditoria, o fluxo de eventos foi
/// reconciliado contra o `adjustedClose` e as duas fontes divergiram em até
/// 38,5% (BBAS3). Investigando, o fluxo de `cashDividends` se mostrou
/// consistente com o próprio DY publicado pela API — o que diverge é o
/// `adjustedClose` do Yahoo, que subajusta proventos brasileiros, sobretudo
/// JCP. Isso inviabilizou o oráculo de validação originalmente previsto.
///
/// A conferência que **funciona** é esta, e vira verificação de runtime: se o
/// DY calculado a partir dos eventos divergir do publicado além da tolerância,
/// o ativo é sinalizado em vez de produzir número errado em silêncio.
///
/// Tolerância padrão de 1 ponto percentual: o campo `dividendYield` da fonte
/// vem arredondado em duas casas decimais (0,03 · 0,06 · 0,08), então casar
/// além disso é impossível por construção.
abstract final class DividendQualityGate {
  static const double defaultToleranceInFraction = 0.01;

  /// Soma dos proventos com data-ex nos últimos 12 meses.
  static double trailingTwelveMonths(
    List<DividendEvent> events,
    DateTime asOf,
  ) {
    final floor = DateTime(asOf.year - 1, asOf.month, asOf.day);
    var total = 0.0;
    for (final event in events) {
      if (event.exDate.isAfter(floor) && !event.exDate.isAfter(asOf)) {
        total += event.amountPerShare;
      }
    }
    return total;
  }

  static DividendQualityReport check({
    required Ticker ticker,
    required List<DividendEvent> events,
    required double? currentPrice,
    required double? publishedYield,
    required DateTime asOf,
    double tolerance = defaultToleranceInFraction,
  }) {
    if (currentPrice == null || currentPrice <= 0) {
      return DividendQualityReport(
        ticker: ticker,
        status: DividendQuality.unverified,
        message: 'Sem preço corrente para calcular o dividend yield.',
      );
    }
    if (publishedYield == null) {
      return DividendQualityReport(
        ticker: ticker,
        status: DividendQuality.unverified,
        message: 'A fonte não publica dividend yield para ${ticker.value}.',
      );
    }

    final ttm = trailingTwelveMonths(events, asOf);
    final computed = ttm / currentPrice;
    final deviation = (computed - publishedYield).abs();

    if (deviation <= tolerance) {
      return DividendQualityReport(
        ticker: ticker,
        status: DividendQuality.consistent,
        computedYield: computed,
        publishedYield: publishedYield,
        deviation: deviation,
        message: 'DY calculado ${_pct(computed)} confere com o publicado '
            '${_pct(publishedYield)}.',
      );
    }

    return DividendQualityReport(
      ticker: ticker,
      status: DividendQuality.divergent,
      computedYield: computed,
      publishedYield: publishedYield,
      deviation: deviation,
      message: 'DY calculado ${_pct(computed)} diverge do publicado '
          '${_pct(publishedYield)} em ${_pct(deviation)}. Os proventos de '
          '${ticker.value} podem estar incompletos ou duplicados na fonte.',
    );
  }

  static String _pct(double fraction) =>
      '${(fraction * 100).toStringAsFixed(2)}%';
}
