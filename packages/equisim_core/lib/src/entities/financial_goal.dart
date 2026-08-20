import 'dart:math' as math;

import '../value_objects/money.dart';

/// Plano patrimonial declarado pelo usuário.
///
/// Os quatro parâmetros definem a carteira: aporte inicial, aporte mensal,
/// prazo e valor desejado ao final. A rentabilidade necessária é **derivada**
/// deles, não informada.
class FinancialGoal {
  /// V₀ — aporte inicial.
  final Money initialContribution;

  /// PMT — aporte mensal.
  final Money monthlyContribution;

  /// n — prazo em meses.
  final int months;

  /// V_f — patrimônio desejado ao final.
  final Money targetWealth;

  const FinancialGoal({
    required this.initialContribution,
    required this.monthlyContribution,
    required this.months,
    required this.targetWealth,
  });

  double get years => months / 12.0;

  /// Capital que o próprio investidor aporta ao longo do plano, sem
  /// rendimento algum.
  Money get totalContributed =>
      initialContribution + monthlyContribution * months;

  /// A meta é atingível apenas com os aportes, sem qualquer rentabilidade.
  bool get reachableWithoutReturn => targetWealth <= totalContributed;
}

/// Rentabilidade requerida para o plano.
class RequiredReturn {
  /// Taxa mensal, em fração.
  final double monthly;

  /// Iterações consumidas pelo solver.
  final int iterations;

  /// `true` quando a raiz veio da bisseção de resguardo, não de Newton.
  final bool usedBisection;

  const RequiredReturn({
    required this.monthly,
    required this.iterations,
    this.usedBisection = false,
  });

  /// Taxa anual equivalente: `(1 + i)¹² − 1`.
  double get annual => math.pow(1 + monthly, 12).toDouble() - 1;

  /// Taxa semestral equivalente.
  double get semiAnnual => math.pow(1 + annual, 0.5).toDouble() - 1;
}
