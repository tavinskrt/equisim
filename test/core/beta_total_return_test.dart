import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('TAEE3');

/// Pregões de segunda a sexta, de [start] a [end].
List<DateTime> _tradingDays(DateTime start, DateTime end) => [
      for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1))
        if (d.weekday <= DateTime.friday) d,
    ];

class _Prices implements PriceRepository {
  final PriceSeries series;
  _Prices(this.series);

  @override
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range) async =>
      Ok(series);

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
          List<Ticker> tickers, DateRange range) async =>
      Ok({_ticker: series});

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker ticker, DateRange range) async =>
      Ok(series);
}

class _Index implements BenchmarkRepository {
  final PriceSeries series;
  _Index(this.series);

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async => Ok(series);
}

class _Fundamentals implements FundamentalsRepository {
  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async => Ok([
        FundamentalsSnapshot(
            ticker: t, fiscalPeriodEnd: DateTime(2024, 12, 31), netIncome: 10),
      ]);

  @override
  Future<Result<Asset>> profile(Ticker t) async =>
      const Err(InsufficientData('sem perfil'));

  @override
  Future<Result<List<Ticker>>> universe() async => Ok([_ticker]);
}

void main() {
  test('com os proventos da B3, o beta sai do retorno total — decisão 89',
      () async {
    // O ativo anda exatamente com o índice, e paga 4% nos dias de alta forte.
    // Pelo fechamento, a queda da data ex coincide com a alta do mercado e
    // derruba o beta; pelo retorno total, ele é 1.
    final days = _tradingDays(DateTime(2021, 1, 4), DateTime(2025, 12, 30));
    final market = <double>[1000];
    final asset = <double>[50];
    final dividends = <CashDividend>[];
    for (var i = 1; i < days.length; i++) {
      final m = 0.012 * math.sin(i * 0.7) + 0.004 * math.cos(i * 1.3);
      market.add(market[i - 1] * (1 + m));
      final ex = m > 0.013 && i % 3 == 0;
      if (ex) {
        final d = asset[i - 1] * 0.04;
        dividends.add(CashDividend(
          shareClass: 'ON',
          kind: CashDividendKind.dividend,
          lastDateWithRights: DateTime.utc(days[i - 1].year, days[i - 1].month, days[i - 1].day),
          exDate: DateTime.utc(days[i].year, days[i].month, days[i].day),
          amount: d,
          closeWithRights: asset[i - 1],
        ));
        asset.add(asset[i - 1] * (1 + m) - d);
      } else {
        asset.add(asset[i - 1] * (1 + m));
      }
    }
    expect(dividends.length, greaterThan(20),
        reason: 'o cenário precisa de datas ex suficientes para medir algo');

    PriceSeries series(List<double> v) => PriceSeries(ticker: _ticker, points: [
          for (var i = 0; i < days.length; i++)
            PricePoint(date: days[i], close: v[i]),
        ]);

    Future<ValuationInputs> prepare(List<CashDividend>? d) async =>
        (await PrepareValuationInputs.call(
          ticker: _ticker,
          prices: _Prices(series(asset)),
          fundamentals: _Fundamentals(),
          benchmark: _Index(series(market)),
          riskFreeRate: 0.10,
          asOf: DateTime(2025, 12, 31),
          dividends: d,
        ))
            .unwrap();

    final price = await prepare(null);
    final total = await prepare(dividends);

    expect(total.capm.beta, closeTo(1.0, 1e-9));
    expect(total.dividendsInBeta, dividends.length);
    expect(price.dividendsInBeta, 0);
    expect(price.capm.beta, lessThan(0.99),
        reason: 'pelo fechamento, a data ex entra como risco');
  });
}
