import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('RequiredReturnSolver — sem aporte mensal (forma fechada conhecida)', () {
    test('dobrar o capital em 12 meses exige 2^(1/12) − 1', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1000),
        monthlyContribution: Money.zero,
        months: 12,
        targetWealth: Money.fromReais(2000),
      );
      final result = RequiredReturnSolver.solve(goal);
      expect(result.isOk, isTrue);
      // 2^(1/12) − 1 = 0,059463094359295...
      expect(result.unwrap().monthly, closeTo(0.0594630943592953, 1e-9));
    });
  });

  group('RequiredReturnSolver — com aporte mensal', () {
    test('caso conferível: PMT 100, n 12, alvo 1268,25 → 1% ao mês', () {
      // Valor futuro de série uniforme a 1% a.m.:
      // 100 × ((1,01¹² − 1)/0,01) = 1268,2503...
      // Equivale a TAXA(12; -100; 0; 1268,25) no Excel.
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.zero,
        monthlyContribution: Money.fromReais(100),
        months: 12,
        targetWealth: Money.fromReais(1268.25),
      );
      final result = RequiredReturnSolver.solve(goal);
      expect(result.isOk, isTrue);
      expect(result.unwrap().monthly, closeTo(0.01, 1e-5));
    });

    test('a forma fechada ingênua superestimaria grosseiramente a taxa', () {
      // Erro que o solver evita: tratar (Vf/V0)^(1/n) − 1 como resposta.
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(300000),
      );
      final result = RequiredReturnSolver.solve(goal);
      expect(result.isOk, isTrue);
      final correct = result.unwrap().monthly;

      // A fórmula sem aportes exigiria (300000/10000)^(1/120) − 1 ≈ 2,87% a.m.
      const naive = 0.0287;
      expect(correct, lessThan(naive / 2),
          reason: 'ignorar os aportes infla a taxa exigida em várias vezes');
    });

    test('solução satisfaz a equação de valor futuro (ida e volta)', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(5000),
        monthlyContribution: Money.fromReais(750),
        months: 84,
        targetWealth: Money.fromReais(120000),
      );
      final rate = RequiredReturnSolver.solve(goal).unwrap().monthly;
      final futureValue = RequiredReturnSolver.futureValue(
        rate: rate,
        initial: 5000,
        monthly: 750,
        months: 84,
      );
      expect(futureValue, closeTo(120000, 0.01));
    });

    test('taxa nula é tratada sem divisão por zero', () {
      final fv = RequiredReturnSolver.futureValue(
        rate: 0.0,
        initial: 1000,
        monthly: 100,
        months: 12,
      );
      expect(fv, closeTo(2200.0, 1e-9));
    });

    test('converte taxa mensal para anual e semestral', () {
      const required = RequiredReturn(monthly: 0.01, iterations: 3);
      expect(required.annual, closeTo(0.12682503, 1e-7));
      expect(required.semiAnnual, closeTo(0.0615201, 1e-6));
    });
  });

  group('RequiredReturnSolver — casos-limite', () {
    test('meta já coberta pelos próprios aportes', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1000),
        monthlyContribution: Money.fromReais(1000),
        months: 12,
        targetWealth: Money.fromReais(5000),
      );
      expect(goal.reachableWithoutReturn, isTrue);
      final result = RequiredReturnSolver.solve(goal);
      expect(result.isOk, isTrue);
      expect(result.unwrap().monthly, lessThanOrEqualTo(0.0));
    });

    test('meta impossível é reportada como falha, não como número absurdo', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1),
        monthlyContribution: Money.zero,
        months: 12,
        targetWealth: Money.fromReais(1000000000),
      );
      final result = RequiredReturnSolver.solve(goal);
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ComputationFailure>());
    });

    test('rejeita plano sem capital algum', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.zero,
        monthlyContribution: Money.zero,
        months: 12,
        targetWealth: Money.fromReais(1000),
      );
      expect(RequiredReturnSolver.solve(goal).isErr, isTrue);
    });

    test('rejeita prazo não positivo', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1000),
        monthlyContribution: Money.zero,
        months: 0,
        targetWealth: Money.fromReais(2000),
      );
      expect(RequiredReturnSolver.solve(goal).isErr, isTrue);
    });
  });

  group('GoalFeasibility — limiares ancorados em dados observados', () {
    const anchors = MarketAnchors.fallback2026; // CDI 9,40% · IBOV 11,26%

    FeasibilityVerdict verdictFor(double annualRate) {
      final monthly = _monthlyFromAnnual(annualRate);
      return GoalFeasibility.assess(
        required: RequiredReturn(monthly: monthly, iterations: 1),
        anchors: anchors,
      );
    }

    test('abaixo do CDI: avisa que a meta dispensa risco de mercado', () {
      final verdict = verdictFor(0.06);
      expect(verdict.level, FeasibilityLevel.riskFreeSufficient);
      expect(verdict.level, isNot(FeasibilityLevel.unrealistic));
      // O motivo, e não a frase: o texto é composto na apresentação desde que
      // o núcleo parou de montar prosa (ver `FeasibilityCopy`).
      expect(verdict.reason, FeasibilityReason.belowRiskFree);
    });

    test('entre CDI e Ibovespa: plausível', () {
      expect(verdictFor(0.105).level, FeasibilityLevel.plausible);
    });

    test('acima do Ibovespa: alerta sem bloquear', () {
      final verdict = verdictFor(0.18);
      expect(verdict.level, FeasibilityLevel.demanding);
      expect(verdict.level, FeasibilityLevel.demanding);
      expect(verdict.level, isNot(FeasibilityLevel.unrealistic));
    });

    test('acima de 2,5× o Ibovespa: bloqueia e cita o número', () {
      final verdict = verdictFor(0.40);
      expect(verdict.level, FeasibilityLevel.unrealistic);
      expect(verdict.level, FeasibilityLevel.unrealistic);
      expect(verdict.reason, FeasibilityReason.beyondAnyReference);
      // O múltiplo viaja apurado, para a tela citá-lo sem recalcular.
      expect(verdict.marketMultiple, closeTo(0.40 / 0.1126, 1e-9));
    });

    test('aportes que já bastam dispensam rentabilidade', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1000),
        monthlyContribution: Money.fromReais(1000),
        months: 12,
        targetWealth: Money.fromReais(5000),
      );
      final verdict = GoalFeasibility.assess(
        required: const RequiredReturn(monthly: 0.0, iterations: 0),
        anchors: anchors,
        goal: goal,
      );
      expect(verdict.level, FeasibilityLevel.riskFreeSufficient);
    });
  });
}

double _monthlyFromAnnual(double annual) {
  var lo = -0.5;
  var hi = 1.0;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    final candidate = RequiredReturn(monthly: mid, iterations: 0).annual;
    if (candidate < annual) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}
