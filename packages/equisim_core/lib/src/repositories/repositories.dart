import 'dart:math' as math;

import '../entities/asset.dart';
import '../entities/dividend_event.dart';
import '../entities/fundamentals.dart';
import '../entities/price_series.dart';
import '../failures/result.dart';
import '../value_objects/date_range.dart';
import '../value_objects/ticker.dart';

/// Série de taxas diárias (CDI, IPCA), já convertidas para fração.
class RateSeries {
  final List<DateTime> dates;

  /// Taxa do período correspondente, em fração (0.0004 = 0,04% no dia).
  final List<double> rates;

  const RateSeries({required this.dates, required this.rates});

  bool get isEmpty => rates.isEmpty;

  /// Fator acumulado do período: `Π(1 + rᵢ) − 1`.
  double get accumulated {
    var factor = 1.0;
    for (final r in rates) {
      factor *= 1 + r;
    }
    return factor - 1;
  }

  /// Taxa anual equivalente, dado o número de períodos por ano.
  double annualized({int periodsPerYear = 252}) {
    if (rates.isEmpty) return 0.0;
    final years = rates.length / periodsPerYear;
    if (years <= 0) return 0.0;
    final factor = 1 + accumulated;
    if (factor <= 0) return -1.0;
    return math.pow(factor, 1 / years).toDouble() - 1;
  }
}

/// Acesso a cotações.
abstract interface class PriceRepository {
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range);

  /// Busca em lote: uma requisição em vez de N.
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  );

  /// `adjustedClose` bruto da fonte — **apenas conferência**, nunca cálculo.
  /// A série subajusta proventos brasileiros; o retorno total de verdade é
  /// construído no domínio por `TotalReturnEngine`.
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker ticker, DateRange range);
}

/// Acesso a proventos.
abstract interface class DividendRepository {
  Future<Result<List<DividendEvent>>> history(Ticker ticker);

  Future<Result<Map<Ticker, List<DividendEvent>>>> historyBatch(
    List<Ticker> tickers,
  );

  /// Dividend yield dos últimos 12 meses publicado pela fonte.
  ///
  /// Usado como **portão de qualidade**: se divergir do DY calculado a partir
  /// do fluxo de eventos além da tolerância, o ativo é sinalizado em vez de
  /// reportar número errado em silêncio.
  Future<Result<double>> publishedTrailingYield(Ticker ticker);
}

/// Acesso a fundamentos. Devolve a série completa; o recorte temporal é
/// responsabilidade de `PointInTimeView`.
abstract interface class FundamentalsRepository {
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker);
  Future<Result<Asset>> profile(Ticker ticker);
  Future<Result<List<Ticker>>> universe();
}

/// Variáveis macroeconômicas.
abstract interface class MacroRepository {
  /// CDI diário (BCB SGS 12) — taxa livre de risco do CAPM e do Sharpe.
  Future<Result<RateSeries>> riskFreeDaily(DateRange range);

  /// IPCA mensal (BCB SGS 433) — retorno real.
  Future<Result<RateSeries>> inflationMonthly(DateRange range);
}

/// Índice de mercado, para Rm e para o cálculo local de beta.
abstract interface class BenchmarkRepository {
  Future<Result<PriceSeries>> ibovespa(DateRange range);
}
