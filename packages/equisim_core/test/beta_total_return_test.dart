import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('TAEE3');

/// Pregões de segunda a sexta, de [inicio] a [fim].
List<DateTime> _pregoes(DateTime inicio, DateTime fim) => [
      for (var d = inicio; !d.isAfter(fim); d = DateTime(d.year, d.month, d.day + 1))
        if (d.weekday <= DateTime.friday) d,
    ];

class _Precos implements PriceRepository {
  final PriceSeries serie;
  _Precos(this.serie);

  @override
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range) async =>
      Ok(serie);

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
          List<Ticker> tickers, DateRange range) async =>
      Ok({_ticker: serie});

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker ticker, DateRange range) async =>
      Ok(serie);
}

class _Indice implements BenchmarkRepository {
  final PriceSeries serie;
  _Indice(this.serie);

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async => Ok(serie);
}

class _Fundamentos implements FundamentalsRepository {
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
    final dias = _pregoes(DateTime(2021, 1, 4), DateTime(2025, 12, 30));
    final mercado = <double>[1000];
    final ativo = <double>[50];
    final proventos = <CashDividend>[];
    for (var i = 1; i < dias.length; i++) {
      final m = 0.012 * math.sin(i * 0.7) + 0.004 * math.cos(i * 1.3);
      mercado.add(mercado[i - 1] * (1 + m));
      final ex = m > 0.013 && i % 3 == 0;
      if (ex) {
        final d = ativo[i - 1] * 0.04;
        proventos.add(CashDividend(
          shareClass: 'ON',
          kind: CashDividendKind.dividendo,
          lastDateWithRights: DateTime.utc(dias[i - 1].year, dias[i - 1].month, dias[i - 1].day),
          exDate: DateTime.utc(dias[i].year, dias[i].month, dias[i].day),
          amount: d,
          closeWithRights: ativo[i - 1],
        ));
        ativo.add(ativo[i - 1] * (1 + m) - d);
      } else {
        ativo.add(ativo[i - 1] * (1 + m));
      }
    }
    expect(proventos.length, greaterThan(20),
        reason: 'o cenário precisa de datas ex suficientes para medir algo');

    PriceSeries serie(List<double> v) => PriceSeries(ticker: _ticker, points: [
          for (var i = 0; i < dias.length; i++)
            PricePoint(date: dias[i], close: v[i]),
        ]);

    Future<ValuationInputs> preparar(List<CashDividend>? d) async =>
        (await PrepareValuationInputs.call(
          ticker: _ticker,
          prices: _Precos(serie(ativo)),
          fundamentals: _Fundamentos(),
          benchmark: _Indice(serie(mercado)),
          riskFreeRate: 0.10,
          asOf: DateTime(2025, 12, 31),
          dividends: d,
        ))
            .unwrap();

    final preco = await preparar(null);
    final total = await preparar(proventos);

    expect(total.capm.beta, closeTo(1.0, 1e-9));
    expect(total.dividendsInBeta, proventos.length);
    expect(preco.dividendsInBeta, 0);
    expect(preco.capm.beta, lessThan(0.99),
        reason: 'pelo fechamento, a data ex entra como risco');
  });
}
