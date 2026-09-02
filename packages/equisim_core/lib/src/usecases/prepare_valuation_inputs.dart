import '../entities/price_series.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
import '../repositories/repositories.dart';
import '../services/metrics/beta.dart';
import '../services/valuation/cost_of_capital.dart';
import '../services/valuation/growth_estimator.dart';
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

  /// Busca fundamentos e cotações e monta os insumos da cascata.
  ///
  /// - [ticker]: ativo a preparar.
  /// - [prices], [fundamentals], [benchmark]: repositórios.
  /// - [riskFreeRate]: taxa livre de risco **anual corrente**, não a média
  ///   histórica — o desconto olha para frente.
  /// - [asOf]: data de referência. Sem ela, usa o relógio do sistema; informe-a
  ///   sempre que o resultado precisar ser reproduzível.
  /// - [marketPremium], [marginOfSafety], [projectionYears],
  ///   [perpetualGrowthCap]: parâmetros declarados do modelo.
  ///
  /// Propaga a falha do histórico de fundamentos e a de cotações; devolve
  /// [InsufficientData] quando a série de preços vem vazia na janela.
  ///
  /// **Falha do índice não interrompe**: o beta cai para 1,0, registrado em
  /// [BetaSource.manual].
  static Future<Result<ValuationInputs>> call({
    required Ticker ticker,
    required PriceRepository prices,
    required FundamentalsRepository fundamentals,
    required BenchmarkRepository benchmark,
    required double riskFreeRate,
    DateTime? asOf,
    double marketPremium = CapmInputs.defaultMarketPremium,
    double marginOfSafety = 0.0,
    int projectionYears = 5,
    double perpetualGrowthCap = GrowthEstimator.realEconomyGrowth,
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

    final beta = await _estimateBeta(
      series: series,
      benchmark: benchmark,
      window: window,
    );

    return Ok(ValuationInputs(
      ticker: ticker,
      asOf: today,
      fundamentals: historyResult.unwrap(),
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
  /// Os dois lados da regressão são séries de **preço de fechamento**: o ativo
  /// pelo `close` — que o domínio não ajusta por provento —, o índice pela
  /// própria cotação. O `adjustedClose` da fonte segue fora de cálculo, por
  /// subajustar proventos brasileiros (ver auditoria §0.4).
  ///
  /// A convenção não é simétrica: o Ibovespa é índice de retorno total por
  /// construção, e o `close` do ativo não. O efeito sobre o beta é de segunda
  /// ordem — ele mede covariância de variações, não nível —, e a assimetria
  /// fica declarada aqui em vez de escondida.
  ///
  /// Sem série de mercado utilizável, adota-se β = 1: a alternativa seria
  /// recusar a avaliação inteira por causa de um único parâmetro, e um beta
  /// neutro é premissa transparente — que fica registrada em [BetaSource].
  static Future<({double beta, BetaSource source})> _estimateBeta({
    required PriceSeries series,
    required BenchmarkRepository benchmark,
    required DateRange window,
  }) async {
    final marketResult = await benchmark.ibovespa(window);
    if (marketResult.isErr) return (beta: 1.0, source: BetaSource.manual);

    final market = marketResult.unwrap();
    if (market.points.length < 30) {
      return (beta: 1.0, source: BetaSource.manual);
    }

    final assetPoints =
        series.points.where((p) => window.contains(p.date)).toList();
    if (assetPoints.length < 2) {
      return (beta: 1.0, source: BetaSource.manual);
    }

    final aligned = BetaCalculator.alignReturns(
      assetDates: [for (final p in assetPoints) p.date],
      assetIndex: [for (final p in assetPoints) p.close],
      marketDates: market.dates,
      marketIndex: market.points.map((p) => p.close).toList(),
    );

    final estimate = BetaCalculator.estimate(returns: aligned);

    return estimate.fold(
      (value) => (beta: value.beta, source: BetaSource.computed),
      (_) => (beta: 1.0, source: BetaSource.manual),
    );
  }
}
