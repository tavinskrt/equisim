// O cenário de desconto alcança o período explícito na via do acionista com o
// custo de capital resolvido (item B36).
//
// O caminho de `Ke` resolvido ano a ano era copiado para o cenário sem o
// deslocamento, e o `+2 p.p.` do pessimista só chegava à perpetuidade: a AZEV4
// saía com o pessimista acima do otimista.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');

/// Companhia não financeira cujo resultado operacional é negativo na maioria
/// dos exercícios — a Porta 3 a manda para a via do acionista —, e cujo lucro
/// líquido é positivo e cresce.
List<FundamentalsSnapshot> _serie() {
  final out = <FundamentalsSnapshot>[];
  var e = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(2025 - i, 12, 31),
      totalRevenue: 10000 * e,
      ebit: -200 * e,
      ebitda: 300 * e,
      netIncome: 900 * e,
      incomeBeforeTax: 1200 * e,
      incomeTaxExpense: -300 * e,
      interestExpense: 50,
      earningsPerShare: 0.9 * e,
      cash: 2000 * e,
      shortTermDebt: 500,
      longTermDebt: 500,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 6.0 * e,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    ));
    // Crescimento que oscila em torno de 5%: série sem dispersão não deixa o
    // erro-padrão ser medido, e o motor recusa medir crescimento assim.
    e *= i.isEven ? 1.04 : 1.06;
  }
  return out;
}

ValuationInputs _insumos() => ValuationInputs(
      ticker: _ticker,
      asOf: DateTime(2026, 9, 9),
      fundamentals: _serie(),
      marketPrice: 12.0,
      capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
      declaredTerminalRiskFreeRate: 0.10,
      // Com o beta desalavancado o `Ke` é resolvido ano a ano (decisão 46).
      unleveredBeta: 0.9,
    );

/// Só o desconto se move, e de dois jeitos: o cenário inteiro, e só a taxa de
/// equilíbrio.
AssumptionSource Function(DcfAssumptions) _cenarios() => (c) =>
    DiscreteScenarios({
      ScenarioBand.bear: c.copyWith(
        discountRate: c.discountRate + 0.02,
        terminalDiscountRate: c.terminalDiscountRate + 0.02,
      ),
      ScenarioBand.base: c,
      ScenarioBand.bull: c.copyWith(
        terminalDiscountRate: c.terminalDiscountRate + 0.02,
      ),
    });

void main() {
  test('a premissa: o ativo vai para a via do acionista, com Ke resolvido', () {
    final r = ValuationCascade.evaluate(_insumos());
    expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
    expect(r.unwrap().model, ValuationModel.dcfEarnings);
    expect(
      r.unwrap().warnings.any((w) => w.contains('resolvido ano a ano')),
      isTrue,
    );
  });

  test('deslocar o desconto inteiro pesa mais que deslocar só a perpetuidade',
      () {
    final r = ValuationCascade.evaluate(_insumos(), scenarioBuilder: _cenarios())
        .unwrap();
    final inteiro = r.discreteScenarios![ScenarioBand.bear]!.reais;
    final soPerpetuidade = r.discreteScenarios![ScenarioBand.bull]!.reais;
    final base = r.discreteScenarios![ScenarioBand.base]!.reais;
    expect(soPerpetuidade, lessThan(base));
    expect(inteiro, lessThan(soPerpetuidade - 0.01),
        reason: 'o +2 p.p. do período explícito precisa chegar à conta');
  });

  test('o cenário base continua sendo o preço justo', () {
    final r = ValuationCascade.evaluate(_insumos()).unwrap();
    expect(r.discreteScenarios![ScenarioBand.base], r.fairValue);
  });
}
