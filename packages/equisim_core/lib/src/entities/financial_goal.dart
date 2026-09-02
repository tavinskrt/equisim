import 'dart:math' as math;

import '../failures/failure.dart';
import '../failures/result.dart';
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

  /// Declara o plano **sem conferir invariante alguma**.
  ///
  /// O nome é o aviso: quem chama isto assume a conferência. Existe para dois
  /// casos legítimos — desserializar documento gravado antes desta validação
  /// existir, e montar caso de teste deliberadamente inválido — e é `const`,
  /// o que [create] não pode ser.
  ///
  /// **No caminho normal, use [create].**
  const FinancialGoal.unvalidated({
    required this.initialContribution,
    required this.monthlyContribution,
    required this.months,
    required this.targetWealth,
  });

  /// Constrói o plano conferindo as invariantes que o tornam resolvível.
  ///
  /// - [initialContribution], [monthlyContribution]: aportes. Não podem ser
  ///   negativos, e não podem ser ambos zero — sem capital não há o que render.
  /// - [months]: prazo. Precisa de ao menos um mês.
  /// - [targetWealth]: patrimônio desejado. Precisa ser positivo.
  ///
  /// Devolve [InvalidInput] com o campo apontado em `field`, para a interface
  /// destacá-lo sem interpretar a mensagem.
  ///
  /// **Por que aqui e não só no solver.** A entidade circula por toda a
  /// aplicação — persistência, telas, alinhamento de meta —, e quem a recebe
  /// não tem como saber se ela passou por validação em algum ponto. Fechar a
  /// invariante na construção é o que dispensa cada consumidor de reconferir.
  static Result<FinancialGoal> create({
    required Money initialContribution,
    required Money monthlyContribution,
    required int months,
    required Money targetWealth,
  }) {
    if (months <= 0) {
      return const Err(InvalidInput(
        'O prazo deve ser de ao menos um mês.',
        field: 'months',
      ));
    }
    if (initialContribution.cents < 0 || monthlyContribution.cents < 0) {
      return const Err(InvalidInput(
        'Os aportes não podem ser negativos.',
        field: 'contribution',
      ));
    }
    if (targetWealth.cents <= 0) {
      return const Err(InvalidInput(
        'O valor desejado deve ser positivo.',
        field: 'targetWealth',
      ));
    }
    if (initialContribution.isZero && monthlyContribution.isZero) {
      return const Err(InvalidInput(
        'Sem aporte inicial nem mensal, não há capital para render.',
        field: 'contribution',
      ));
    }
    return Ok(FinancialGoal.unvalidated(
      initialContribution: initialContribution,
      monthlyContribution: monthlyContribution,
      months: months,
      targetWealth: targetWealth,
    ));
  }

  /// Prazo em anos, derivado de [months]. Fração exata, sem arredondar.
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

  /// Agrupa a taxa resolvida e o diagnóstico do solver.
  const RequiredReturn({
    required this.monthly,
    required this.iterations,
    this.usedBisection = false,
  });

  /// Taxa anual equivalente: `(1 + i)¹² − 1`.
  ///
  /// Conversão por **composição**, nunca por multiplicação: `i × 12` erra por
  /// dezenas de pontos percentuais nas taxas que uma meta agressiva exige.
  double get annual => math.pow(1 + monthly, 12).toDouble() - 1;

  /// Taxa semestral equivalente: `(1 + anual)^(1/2) − 1`, ou seja
  /// `(1 + mensal)⁶ − 1`.
  ///
  /// Também por composição. Existe para exibição em prazos intermediários;
  /// nenhum cálculo do pacote a consome.
  double get semiAnnual => math.pow(1 + annual, 0.5).toDouble() - 1;
}
