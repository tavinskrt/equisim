// O aviso do custo da dívida descreve a regra que a conta aplica (item B32).
//
// Até 27/09/2026 ele dizia a regra de antes das decisões 31 e 130: o observado
// «fora da faixa defensável» e o adotado «por alavancagem», mesmo com o
// observado dentro da faixa e o prêmio vindo da cobertura.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');

/// Dívida bruta de 4.000 e EBIT de 1.800 no primeiro exercício, crescendo 5%
/// ao ano; [juro] é a despesa financeira, constante.
List<FundamentalsSnapshot> _serie(double juro) {
  final out = <FundamentalsSnapshot>[];
  var e = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(2025 - i, 12, 31),
      totalRevenue: 10000 * e,
      ebit: 1800 * e,
      ebitda: 2400 * e,
      netIncome: 900 * e,
      incomeBeforeTax: 1300 * e,
      incomeTaxExpense: -400 * e,
      interestExpense: juro,
      earningsPerShare: 0.9 * e,
      cash: 200,
      shortTermDebt: 1000,
      longTermDebt: 3000,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 6.0 * e,
      operatingCashFlow: 2000 * e,
      nopat: 1188 * e,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    ));
    e *= 1.05;
  }
  return out;
}

String? _aviso(double juro) {
  final r = ValuationCascade.evaluate(ValuationInputs(
    ticker: _ticker,
    asOf: DateTime(2026, 9, 9),
    fundamentals: _serie(juro),
    marketPrice: 12.0,
    capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
    declaredTerminalRiskFreeRate: 0.094,
  ));
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  final avisos = r.unwrap().warnings
      .where((w) => w.startsWith('O custo da dívida implícito'));
  return avisos.isEmpty ? null : avisos.single;
}

void main() {
  test('observado dentro da faixa: a cobertura fala, e o aviso diz que o '
      'prêmio veio dela', () {
    // 960 ÷ 4.000 = 24%, dentro de [14%, 24%]; a cobertura de 3,4x dá 2,4
    // p.p., e a alavancagem de 0,9x, 1,3 p.p.
    final w = _aviso(960)!;
    expect(w, contains('deu 24.0% a.a., e o adotado é 16.4% a.a.'));
    expect(w, contains('dentro da faixa defensável de 14.0% a 24.0%'));
    expect(w, contains('o da cobertura, de 2.4%'));
    expect(w, isNot(contains('fora da faixa')));
  });

  test('observado fora da faixa: a cobertura sai, e o prêmio é o da '
      'alavancagem', () {
    // 400 ÷ 4.000 = 10%, abaixo da taxa livre de risco.
    final w = _aviso(400)!;
    expect(w, contains('deu 10.0% a.a., e o adotado é 15.3% a.a.'));
    expect(w, contains('fora da faixa defensável de 14.0% a 24.0%'));
    expect(w, contains('prêmio é o da alavancagem de 0.88x'));
    expect(w, contains('de 1.3%'));
  });

  test('observado perto do adotado não gera aviso', () {
    // 16,4% observado contra 16,4% adotado.
    expect(_aviso(656), isNull);
  });
}
