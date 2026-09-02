import 'dart:math' as math;

import '../../entities/financial_goal.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';

/// Resolve a rentabilidade necessária para um plano com aportes mensais.
///
/// **Não existe forma fechada.** A fórmula `(V_f/V₀)^(1/t) − 1` só vale quando
/// não há aportes; com PMT ≠ 0 ela ignora todo o capital adicionado ao longo do
/// caminho e superestima grosseiramente a taxa exigida.
///
/// A equação correta é o valor futuro de uma série uniforme:
///
///     V_f = V₀(1+i)ⁿ + PMT · [((1+i)ⁿ − 1) / i]
///
/// `i` não pode ser isolado algebricamente, então é resolvido numericamente.
abstract final class RequiredReturnSolver {
  static const double _tolerance = 1e-12;
  static const int _maxIterations = 200;

  /// Limite inferior de busca: −99,99% ao mês.
  static const double _lowerBound = -0.9999;

  /// Limite superior: 100% ao mês. Acima disso a meta é absurda por
  /// qualquer critério.
  static const double _upperBound = 1.0;

  /// Valor futuro do plano a uma taxa mensal [rate].
  ///
  /// Trata o limite `i → 0` explicitamente: o fator de anuidade
  /// `((1+i)ⁿ − 1)/i` tende a `n`, mas a expressão direta divide por zero.
  static double futureValue({
    required double rate,
    required double initial,
    required double monthly,
    required int months,
  }) {
    if (rate.abs() < 1e-12) {
      return initial + monthly * months;
    }
    final growth = math.pow(1 + rate, months).toDouble();
    return initial * growth + monthly * (growth - 1) / rate;
  }

  /// Resolve a taxa mensal requerida.
  ///
  /// Newton-Raphson com bisseção de resguardo: Newton converge em 4–6
  /// iterações no caso típico, mas pode divergir com aportes grandes em
  /// relação ao inicial; a bisseção garante a resposta porque a função é
  /// monotônica crescente em `i`.
  ///
  /// **As guardas de entrada continuam aqui de propósito**, mesmo depois de
  /// `FinancialGoal.create` fechar as mesmas invariantes na construção:
  /// `FinancialGoal.unvalidated` existe e é o caminho da desserialização, de
  /// modo que uma meta gravada antes daquela fábrica pode chegar aqui
  /// inconsistente. Elas são a segunda linha, não a única — e são a razão de
  /// este método devolver [Result].
  static Result<RequiredReturn> solve(FinancialGoal goal) {
    final valid = FinancialGoal.create(
      initialContribution: goal.initialContribution,
      monthlyContribution: goal.monthlyContribution,
      months: goal.months,
      targetWealth: goal.targetWealth,
    );
    if (valid.isErr) return Err(valid.failureOrNull!);

    final v0 = goal.initialContribution.reais;
    final pmt = goal.monthlyContribution.reais;
    final n = goal.months;
    final target = goal.targetWealth.reais;

    double f(double rate) =>
        futureValue(rate: rate, initial: v0, monthly: pmt, months: n) - target;

    // Newton-Raphson com derivada numérica central: a derivada analítica do
    // fator de anuidade é instável perto de i = 0, e a numérica é suficiente
    // dado que a função é suave.
    var rate = 0.01;
    for (var i = 0; i < _maxIterations; i++) {
      final value = f(rate);
      if (value.abs() < _tolerance) {
        return Ok(RequiredReturn(monthly: rate, iterations: i));
      }
      const h = 1e-7;
      final derivative = (f(rate + h) - f(rate - h)) / (2 * h);
      if (derivative.abs() < 1e-14 || !derivative.isFinite) break;
      final next = rate - value / derivative;
      if (!next.isFinite || next <= _lowerBound || next > _upperBound) break;
      if ((next - rate).abs() < _tolerance) {
        return Ok(RequiredReturn(monthly: next, iterations: i));
      }
      rate = next;
    }

    // Bisseção: a função é monotônica crescente, então basta que troque
    // de sinal no intervalo.
    var low = _lowerBound;
    var high = _upperBound;
    final fLow = f(low);
    final fHigh = f(high);

    if (fLow > 0) {
      // Mesmo com perda quase total o patrimônio supera a meta: só ocorre
      // com meta abaixo do próprio aporte, já tratado como taxa nula.
      return Ok(const RequiredReturn(monthly: 0.0, iterations: 0));
    }
    if (fHigh < 0) {
      return Err(ComputationFailure(
        'Meta inatingível: nem 100% ao mês durante ${goal.months} meses '
        'alcança ${goal.targetWealth}.',
      ));
    }

    for (var i = 0; i < _maxIterations; i++) {
      final mid = (low + high) / 2;
      final fMid = f(mid);
      if (fMid.abs() < _tolerance || (high - low) / 2 < _tolerance) {
        return Ok(RequiredReturn(
          monthly: mid,
          iterations: i,
          usedBisection: true,
        ));
      }
      if (fMid < 0) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return Ok(RequiredReturn(
      monthly: (low + high) / 2,
      iterations: _maxIterations,
      usedBisection: true,
    ));
  }
}
