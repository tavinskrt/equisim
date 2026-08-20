import 'dart:math' as math;

import '../../failures/failure.dart';
import '../../failures/result.dart';
import '../../value_objects/money.dart';

/// Movimentação externa de capital, datada.
///
/// Convenção de sinal: aporte é **negativo** (saída do bolso do investidor),
/// resgate e valor final são **positivos**. É a convenção da TIR.
class CashFlow {
  final DateTime date;
  final Money amount;

  CashFlow({required DateTime date, required this.amount})
      : date = DateTime(date.year, date.month, date.day);

  @override
  String toString() => '${date.toIso8601String().substring(0, 10)}: $amount';
}

/// Pregões por ano, base de anualização.
const int tradingDaysPerYear = 252;

abstract final class Returns {
  /// **Retorno ponderado pelo tempo (TWR)**.
  ///
  /// Neutraliza o efeito do cronograma de aportes: é a métrica correta para
  /// comparar a qualidade de duas composições de carteira, porque não premia
  /// nem pune a carteira por ter recebido dinheiro em momento favorável.
  ///
  /// Para cada período, `r = (V_t − F_t) / V_{t−1} − 1`, onde `F_t` é o fluxo
  /// externo aportado no período `t` e `V_t` é o valor ao final dele.
  ///
  /// Usar CAGR sobre capital aportado no lugar disto é o erro clássico: trata
  /// 120 aportes mensais como se fossem um único investimento no dia 1.
  static double timeWeighted({
    required List<double> values,
    required List<double> externalFlows,
  }) {
    if (values.length < 2) return 0.0;
    if (values.length != externalFlows.length) {
      throw ArgumentError('values e externalFlows devem ter o mesmo tamanho.');
    }

    var compounded = 1.0;
    for (var i = 1; i < values.length; i++) {
      final previous = values[i - 1];
      if (previous <= 0) continue;
      final periodReturn = (values[i] - externalFlows[i]) / previous - 1.0;
      compounded *= 1.0 + periodReturn;
    }
    return compounded - 1.0;
  }

  /// Índice de retorno total normalizado em base 100, a partir dos valores da
  /// carteira e dos fluxos externos. É a curva que deve alimentar volatilidade
  /// e drawdown — a curva bruta de patrimônio salta no dia do aporte e
  /// contaminaria as duas métricas.
  static List<double> timeWeightedIndex({
    required List<double> values,
    required List<double> externalFlows,
    double base = 100.0,
  }) {
    if (values.isEmpty) return const [];
    final out = <double>[base];
    var level = base;
    for (var i = 1; i < values.length; i++) {
      final previous = values[i - 1];
      if (previous > 0) {
        final periodReturn = (values[i] - externalFlows[i]) / previous - 1.0;
        level *= 1.0 + periodReturn;
      }
      out.add(level);
    }
    return out;
  }

  /// Converte um retorno acumulado em taxa anual composta.
  static double annualize(double totalReturn, double years) {
    if (years <= 0) return 0.0;
    final growth = 1.0 + totalReturn;
    if (growth <= 0) return -1.0;
    return math.pow(growth, 1.0 / years).toDouble() - 1.0;
  }

  /// **Taxa interna de retorno de fluxos datados (XIRR)**.
  ///
  /// É o retorno efetivo do investidor: pondera cada real pelo tempo em que
  /// ficou investido. É o número a confrontar com a rentabilidade requerida
  /// da meta.
  ///
  /// Resolve `Σ CF_i / (1+r)^(d_i/365) = 0` por Newton-Raphson com bisseção
  /// de resguardo.
  static Result<double> extendedIrr(
    List<CashFlow> flows, {
    double guess = 0.1,
    double tolerance = 1e-9,
    int maxIterations = 200,
  }) {
    if (flows.length < 2) {
      return const Err(InsufficientData('XIRR exige ao menos dois fluxos.'));
    }

    final hasPositive = flows.any((f) => f.amount.cents > 0);
    final hasNegative = flows.any((f) => f.amount.cents < 0);
    if (!hasPositive || !hasNegative) {
      return const Err(InvalidInput(
        'XIRR exige ao menos um fluxo positivo e um negativo.',
      ));
    }

    final sorted = [...flows]..sort((a, b) => a.date.compareTo(b.date));
    final origin = sorted.first.date;
    final years = sorted
        .map((f) => f.date.difference(origin).inDays / 365.0)
        .toList(growable: false);
    final amounts =
        sorted.map((f) => f.amount.reais).toList(growable: false);

    double npv(double rate) {
      var total = 0.0;
      for (var i = 0; i < amounts.length; i++) {
        total += amounts[i] / math.pow(1.0 + rate, years[i]);
      }
      return total;
    }

    // Newton-Raphson.
    var rate = guess;
    for (var iteration = 0; iteration < maxIterations; iteration++) {
      if (rate <= -1.0) break;
      var value = 0.0;
      var derivative = 0.0;
      for (var i = 0; i < amounts.length; i++) {
        final discount = math.pow(1.0 + rate, years[i]).toDouble();
        value += amounts[i] / discount;
        derivative -= years[i] * amounts[i] / (discount * (1.0 + rate));
      }
      if (value.abs() < tolerance) return Ok(rate);
      if (derivative.abs() < 1e-14) break;
      final next = rate - value / derivative;
      if (!next.isFinite) break;
      if ((next - rate).abs() < tolerance) return Ok(next);
      rate = next;
    }

    // Bisseção de resguardo quando Newton diverge.
    return _bisect(npv, -0.9999, 100.0, tolerance, maxIterations);
  }

  static Result<double> _bisect(
    double Function(double) f,
    double lo,
    double hi,
    double tolerance,
    int maxIterations,
  ) {
    var low = lo;
    var high = hi;
    var fLow = f(low);
    final fHigh = f(high);
    if (fLow.isNaN || fHigh.isNaN || fLow * fHigh > 0) {
      return const Err(ComputationFailure(
        'Não foi possível isolar a raiz: a função não muda de sinal no intervalo.',
      ));
    }
    for (var i = 0; i < maxIterations; i++) {
      final mid = (low + high) / 2.0;
      final fMid = f(mid);
      if (fMid.abs() < tolerance || (high - low) / 2.0 < tolerance) {
        return Ok(mid);
      }
      if (fLow * fMid < 0) {
        high = mid;
      } else {
        low = mid;
        fLow = fMid;
      }
    }
    return Ok((low + high) / 2.0);
  }
}
