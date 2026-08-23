import '../entities/dividend_event.dart';
import '../entities/price_series.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
import '../repositories/repositories.dart';
import '../services/metrics/beta.dart';
import '../services/total_return_engine.dart';
import '../services/valuation/cost_of_capital.dart';
import '../services/valuation/growth_estimator.dart';
import '../tax/tax_policy.dart';
import '../value_objects/date_range.dart';
import '../value_objects/ticker.dart';
import 'compute_valuation.dart';

/// Reúne, a partir dos repositórios, tudo o que a cascata de avaliação precisa.
///
/// Fica separado de [ValuationCascade] de propósito: aqui há espera por rede,
/// ali há apenas aritmética. A separação é o que permite testar a decisão de
/// modelo exaustivamente sem nenhuma dependência externa, e executá-la dentro
/// de uma isolate.
abstract final class PrepareValuationInputs {
  /// Janela usada para estimar o beta.
  static const int betaWindowYears = 5;

  static Future<Result<ValuationInputs>> call({
    required Ticker ticker,
    required PriceRepository prices,
    required DividendRepository dividends,
    required FundamentalsRepository fundamentals,
    required BenchmarkRepository benchmark,
    required double riskFreeRate,
    DateTime? asOf,
    double marketPremium = CapmInputs.defaultMarketPremium,
    double marginOfSafety = 0.0,
    int projectionYears = 5,
    double perpetualGrowthCap = GrowthEstimator.realEconomyGrowth,
    TaxPolicy taxPolicy = TaxPolicy.brasil,
  }) async {
    final today = asOf ?? DateTime.now();
    final window = DateRange(
      DateTime(today.year - betaWindowYears, today.month, today.day),
      today,
    );

    final historyResult = await fundamentals.history(ticker);
    if (historyResult.isErr) return Err(historyResult.failureOrNull!);

    final priceResult = await prices.daily(ticker, window);
    if (priceResult.isErr) return Err(priceResult.failureOrNull!);

    final series = priceResult.unwrap();
    if (series.isEmpty) {
      return Err(InsufficientData(
        'Sem cotações de ${ticker.value} na janela de análise.',
        subject: ticker.value,
      ));
    }

    final dividendResult = await dividends.history(ticker);
    final events = dividendResult.getOrElse(const <DividendEvent>[]);

    final beta = await _estimateBeta(
      ticker: ticker,
      series: series,
      events: events,
      benchmark: benchmark,
      window: window,
      taxPolicy: taxPolicy,
    );

    return Ok(ValuationInputs(
      ticker: ticker,
      asOf: today,
      fundamentals: historyResult.unwrap(),
      dividends: events,
      marketPrice: series.points.last.close,
      capm: CapmInputs(
        riskFreeRate: riskFreeRate,
        beta: beta.beta,
        marketPremium: marketPremium,
        betaSource: beta.source,
      ),
      marginOfSafety: marginOfSafety,
      projectionYears: projectionYears,
      perpetualGrowthCap: perpetualGrowthCap,
    ));
  }

  /// Estima o beta contra o Ibovespa.
  ///
  /// O retorno do ativo é construído pelo motor de retorno total do próprio
  /// domínio — `close` mais proventos líquidos —, não pelo `adjustedClose` da
  /// fonte, que subajusta proventos brasileiros (ver auditoria §0.4). O índice
  /// dispensa esse tratamento: já é de retorno total por construção.
  ///
  /// Sem série de mercado utilizável, adota-se β = 1: a alternativa seria
  /// recusar a avaliação inteira por causa de um único parâmetro, e um beta
  /// neutro é premissa transparente — que fica registrada em [BetaSource].
  static Future<({double beta, BetaSource source})> _estimateBeta({
    required Ticker ticker,
    required PriceSeries series,
    required List<DividendEvent> events,
    required BenchmarkRepository benchmark,
    required DateRange window,
    required TaxPolicy taxPolicy,
  }) async {
    final marketResult = await benchmark.ibovespa(window);
    if (marketResult.isErr) return (beta: 1.0, source: BetaSource.manual);

    final market = marketResult.unwrap();
    if (market.points.length < 30) {
      return (beta: 1.0, source: BetaSource.manual);
    }

    final assetTotalReturn = TotalReturnEngine.build(
      prices: series,
      dividends: events,
      taxPolicy: taxPolicy,
      range: window,
    );
    if (assetTotalReturn.isEmpty) {
      return (beta: 1.0, source: BetaSource.manual);
    }

    final aligned = BetaCalculator.alignReturns(
      assetDates: assetTotalReturn.dates,
      assetIndex: assetTotalReturn.index,
      marketDates: market.dates,
      marketIndex: market.points.map((p) => p.close).toList(),
    );

    final estimate = BetaCalculator.estimate(
      assetReturns: aligned.asset,
      marketReturns: aligned.market,
    );

    return estimate.fold(
      (value) => (beta: value.beta, source: BetaSource.computed),
      (_) => (beta: 1.0, source: BetaSource.manual),
    );
  }

  /// Dividend yield líquido de imposto dos últimos doze meses.
  ///
  /// Entra no retorno esperado da carteira: o acionista ganha apreciação
  /// **mais** provento, e o provento entra líquido porque a política fiscal
  /// é modelada.
  static double netTrailingYield({
    required List<DividendEvent> events,
    required double currentPrice,
    required DateTime asOf,
    TaxPolicy taxPolicy = TaxPolicy.brasil,
  }) {
    if (currentPrice <= 0) return 0.0;
    final floor = DateTime(asOf.year - 1, asOf.month, asOf.day);
    var net = 0.0;
    for (final event in events) {
      if (event.exDate.isAfter(floor) && !event.exDate.isAfter(asOf)) {
        net += taxPolicy.netAmount(event);
      }
    }
    return net / currentPrice;
  }
}
