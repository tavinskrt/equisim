// O aviso das contagens discordantes diz a contagem que a ponte usou
// (item B40).
//
// O texto dizia sempre «a ponte por papel usa a implícita no valor de
// mercado», e desde a decisão 83 o divisor pode ser a contagem oficial da B3:
// na SAPR11 o aviso nomeava as 103.850.066 do valor de mercado ao lado de uma
// ponte de 302.241.104.
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('CONT3');

/// As duas contagens publicadas discordam por 3x: 1.000 correntes contra 3.000
/// do exercício. O valor de mercado, a R$ 10, implica 3.000.
FundamentalsSnapshot _ano(int y, double e) => FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * e,
      ebit: 1400 * e,
      ebitda: 1900 * e,
      netIncome: 700 * e,
      incomeBeforeTax: 1000 * e,
      incomeTaxExpense: -300 * e,
      interestExpense: 120,
      earningsPerShare: 0.7 * e / 3,
      cash: 500,
      shortTermDebt: 400,
      longTermDebt: 1600,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 2.0 * e,
      nopat: 924 * e,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 3000,
      marketCap: 30000,
    );

ValuationResult _avaliar({OfficialShareCount? oficial}) {
  final r = ValuationCascade.evaluate(ValuationInputs(
    ticker: _ticker,
    asOf: DateTime(2026, 9, 9),
    fundamentals: [
      for (var i = 15; i >= 0; i--)
        _ano(2025 - i, math.pow(1.05, 15 - i).toDouble()),
    ],
    marketPrice: 10.0,
    capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
    declaredTerminalRiskFreeRate: 0.094,
    officialShares: oficial,
  ));
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

String _aviso(ValuationResult v) =>
    v.warnings.singleWhere((w) => w.contains('As duas contagens de ações'));

void main() {
  test('com a contagem oficial adotada, o aviso nomeia a oficial', () {
    final v = _avaliar(
        oficial: OfficialShareCount(total: 3000, asOf: DateTime(2026, 9, 1)));
    final aviso = _aviso(v);
    expect(aviso, contains('contagem oficial da B3'));
    expect(aviso, isNot(contains('implícita no valor de mercado')));
    expect(aviso, contains('3000 papéis'));
  });

  test('sem a oficial, o aviso nomeia a que a ponte usou', () {
    final aviso = _aviso(_avaliar());
    expect(aviso, contains('a ponte por papel usa a implícita no valor'));
    expect(aviso, contains('3000 papéis'));
  });
}
