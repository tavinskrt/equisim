import '../entities/dividend_event.dart';
import '../entities/price_series.dart';
import '../tax/tax_policy.dart';
import '../value_objects/date_range.dart';

/// Série de retorno total construída pelo próprio domínio.
class TotalReturnSeries {
  final List<DateTime> dates;

  /// Índice de retorno total, com base 1,0 na primeira data.
  final List<double> index;

  /// Proventos brutos por ação acumulados no período.
  final double grossDividendsPerShare;

  /// Imposto retido por ação acumulado no período.
  final double withheldTaxPerShare;

  const TotalReturnSeries({
    required this.dates,
    required this.index,
    required this.grossDividendsPerShare,
    required this.withheldTaxPerShare,
  });

  bool get isEmpty => index.isEmpty;

  /// Retorno acumulado do período, em fração.
  double get totalReturn => index.length < 2 ? 0.0 : index.last / index.first - 1.0;

  /// Retornos diários simples.
  List<double> get dailyReturns {
    final out = <double>[];
    for (var i = 1; i < index.length; i++) {
      if (index[i - 1] > 0) out.add(index[i] / index[i - 1] - 1.0);
    }
    return out;
  }
}

/// Constrói séries de retorno total a partir de preço + proventos + tributação.
///
/// Esta é a **fonte única de verdade** de retorno no domínio: alimenta backtest,
/// dividend yield, beta, correlação e volatilidade. O `adjustedClose` da fonte
/// não é usado em cálculo por subajustar proventos brasileiros.
abstract final class TotalReturnEngine {
  /// Simula uma posição inicial de uma ação, reinvestindo cada provento
  /// líquido de imposto no fechamento da data de pagamento.
  ///
  /// O direito ao provento é apurado pela posição vigente na **data-ex**;
  /// o caixa entra e é reinvestido na **data de pagamento**.
  static TotalReturnSeries build({
    required PriceSeries prices,
    required List<DividendEvent> dividends,
    required TaxPolicy taxPolicy,
    DateRange? range,
  }) {
    final points = range == null
        ? prices.points
        : prices.points.where((p) => range.contains(p.date)).toList();

    if (points.isEmpty) {
      return const TotalReturnSeries(
        dates: [],
        index: [],
        grossDividendsPerShare: 0,
        withheldTaxPerShare: 0,
      );
    }

    final first = points.first.date;
    final last = points.last.date;

    // Somente eventos cuja data-ex cai dentro do período simulado: proventos
    // com data-ex anterior pertencem a quem detinha a ação antes do início.
    final relevant = dividends
        .where((d) => !d.exDate.isBefore(first) && !d.exDate.isAfter(last))
        .toList()
      ..sort((a, b) => a.exDate.compareTo(b.exDate));

    // Posição com direito a cada provento, apurada na data-ex.
    final entitlement = <int, double>{};
    final paid = <int>{};

    var shares = 1.0;
    final startPrice = points.first.close;
    var gross = 0.0;
    var withheld = 0.0;

    final dates = <DateTime>[];
    final index = <double>[];

    for (final point in points) {
      final today = point.date;

      // 1) Registra o direito para eventos cuja data-ex já passou.
      for (var i = 0; i < relevant.length; i++) {
        if (entitlement.containsKey(i)) continue;
        if (!relevant[i].exDate.isAfter(today)) {
          entitlement[i] = shares;
        }
      }

      // 2) Credita e reinveste eventos cuja data de pagamento já chegou.
      for (var i = 0; i < relevant.length; i++) {
        if (paid.contains(i)) continue;
        final event = relevant[i];
        if (event.paymentDate.isAfter(today)) continue;
        final held = entitlement[i];
        if (held == null) continue;

        final net = taxPolicy.netAmount(event) * held;
        gross += event.amountPerShare * held;
        withheld += taxPolicy.withheldAmount(event) * held;

        if (point.close > 0 && net > 0) {
          shares += net / point.close;
        }
        paid.add(i);
      }

      dates.add(today);
      index.add(shares * point.close / startPrice);
    }

    return TotalReturnSeries(
      dates: dates,
      index: index,
      grossDividendsPerShare: gross,
      withheldTaxPerShare: withheld,
    );
  }
}
