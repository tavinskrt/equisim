import 'dart:math' as math;

import '../../entities/valuation.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';
import 'dcf.dart';

/// Faixa triangular (mínimo, moda, máximo) para uma premissa.
///
/// A triangular é a escolha usual para julgamento de especialista: exige
/// apenas os três números que um analista sabe dizer, e não pressupõe
/// simetria como a normal.
class TriangularRange {
  final double min;
  final double mode;
  final double max;

  const TriangularRange({
    required this.min,
    required this.mode,
    required this.max,
  });

  /// Faixa degenerada: valor certo.
  const TriangularRange.fixed(double value)
      : min = value,
        mode = value,
        max = value;

  bool get isDegenerate => min == max;

  /// Amostragem por transformada inversa — determinística dado o gerador.
  double sample(math.Random rng) {
    if (isDegenerate) return mode;
    final u = rng.nextDouble();
    final span = max - min;
    final modeFraction = (mode - min) / span;
    if (u < modeFraction) {
      return min + math.sqrt(u * span * (mode - min));
    }
    return max - math.sqrt((1 - u) * span * (max - mode));
  }
}

/// Fonte de premissas para o motor de cenários.
///
/// As duas implementações compartilham o mesmo caminho de código de avaliação:
/// alternar entre cenários nomeados e Monte Carlo é troca de configuração, não
/// refatoração.
abstract class AssumptionSource {
  ScenarioMode get mode;

  /// Premissas do cenário central, usadas como resultado principal.
  DcfAssumptions get base;

  /// Gera [samples] conjuntos de premissas.
  List<DcfAssumptions> draw(int samples, math.Random rng);
}

/// Três conjuntos fixos de premissas — Pessimista, Base e Otimista.
class DiscreteScenarios implements AssumptionSource {
  final Map<ScenarioBand, DcfAssumptions> scenarios;

  const DiscreteScenarios(this.scenarios);

  /// Constrói as três faixas a partir de um cenário central, deslocando
  /// crescimento e desconto em direções opostas.
  factory DiscreteScenarios.around(
    DcfAssumptions center, {
    double growthDelta = 0.03,
    double discountDelta = 0.02,
  }) =>
      DiscreteScenarios({
        ScenarioBand.bear: center.copyWith(
          growthRate: center.growthRate - growthDelta,
          discountRate: center.discountRate + discountDelta,
        ),
        ScenarioBand.base: center,
        ScenarioBand.bull: center.copyWith(
          growthRate: center.growthRate + growthDelta,
          discountRate: math.max(
            center.discountRate - discountDelta,
            center.perpetualGrowth + DcfCalculator.minimumSpread,
          ),
        ),
      });

  @override
  ScenarioMode get mode => ScenarioMode.discrete;

  @override
  DcfAssumptions get base => scenarios[ScenarioBand.base]!;

  @override
  List<DcfAssumptions> draw(int samples, math.Random rng) =>
      scenarios.values.toList();
}

/// Premissas sorteadas de distribuições declaradas.
class StochasticScenarios implements AssumptionSource {
  @override
  final DcfAssumptions base;

  final TriangularRange growth;
  final TriangularRange discount;
  final TriangularRange perpetual;

  const StochasticScenarios({
    required this.base,
    required this.growth,
    required this.discount,
    required this.perpetual,
  });

  /// Faixas simétricas em torno do cenário central.
  factory StochasticScenarios.around(
    DcfAssumptions center, {
    double growthSpread = 0.04,
    double discountSpread = 0.02,
    double perpetualSpread = 0.01,
  }) =>
      StochasticScenarios(
        base: center,
        growth: TriangularRange(
          min: center.growthRate - growthSpread,
          mode: center.growthRate,
          max: center.growthRate + growthSpread,
        ),
        discount: TriangularRange(
          min: center.discountRate - discountSpread,
          mode: center.discountRate,
          max: center.discountRate + discountSpread,
        ),
        perpetual: TriangularRange(
          min: math.max(0.0, center.perpetualGrowth - perpetualSpread),
          mode: center.perpetualGrowth,
          max: center.perpetualGrowth + perpetualSpread,
        ),
      );

  @override
  ScenarioMode get mode => ScenarioMode.monteCarlo;

  @override
  List<DcfAssumptions> draw(int samples, math.Random rng) {
    final out = <DcfAssumptions>[];
    for (var i = 0; i < samples; i++) {
      final r = discount.sample(rng);
      final gp = perpetual.sample(rng);
      out.add(base.copyWith(
        growthRate: growth.sample(rng),
        discountRate: r,
        // Mantém a distância mínima: sorteios com r ≤ gp seriam descartados
        // pelo cálculo e enviesariam a distribuição para cima.
        perpetualGrowth: math.min(gp, r - DcfCalculator.minimumSpread),
      ));
    }
    return out;
  }
}

/// Resultado consolidado de uma rodada de cenários.
class ScenarioOutcome {
  final ScenarioMode mode;

  /// Valor por ação do cenário central.
  final double baseValue;

  /// Preenchido no modo discreto.
  final Map<ScenarioBand, double>? discrete;

  /// Preenchido no modo Monte Carlo.
  final ValueDistribution? distribution;

  /// Sorteios descartados por não produzirem valor válido.
  final int discarded;

  const ScenarioOutcome({
    required this.mode,
    required this.baseValue,
    this.discrete,
    this.distribution,
    this.discarded = 0,
  });
}

abstract final class ScenarioEngine {
  /// Executa a avaliação sobre todos os cenários da fonte.
  ///
  /// [valuate] recebe um conjunto de premissas e devolve o valor por ação.
  /// [seed] fixa o gerador: a mesma entrada produz sempre o mesmo resultado,
  /// requisito de reprodutibilidade.
  static Result<ScenarioOutcome> run({
    required AssumptionSource source,
    required Result<double> Function(DcfAssumptions) valuate,
    int samples = 10000,
    int seed = 42,
  }) {
    final baseResult = valuate(source.base);
    if (baseResult.isErr) return Err(baseResult.failureOrNull!);
    final baseValue = baseResult.unwrap();

    final rng = math.Random(seed);
    final assumptions = source.draw(samples, rng);

    if (source.mode == ScenarioMode.discrete) {
      final discreteSource = source as DiscreteScenarios;
      final results = <ScenarioBand, double>{};
      var discarded = 0;
      for (final entry in discreteSource.scenarios.entries) {
        final r = valuate(entry.value);
        if (r.isOk) {
          results[entry.key] = r.unwrap();
        } else {
          discarded++;
        }
      }
      if (results.isEmpty) {
        return const Err(ComputationFailure(
          'Nenhum cenário discreto produziu valor válido.',
        ));
      }
      return Ok(ScenarioOutcome(
        mode: ScenarioMode.discrete,
        baseValue: baseValue,
        discrete: results,
        discarded: discarded,
      ));
    }

    final values = <double>[];
    var discarded = 0;
    for (final a in assumptions) {
      final r = valuate(a);
      if (r.isOk) {
        final v = r.unwrap();
        if (v.isFinite && v > 0) {
          values.add(v);
        } else {
          discarded++;
        }
      } else {
        discarded++;
      }
    }

    if (values.isEmpty) {
      return const Err(ComputationFailure(
        'Nenhum sorteio produziu valor válido: revise as faixas de premissas.',
      ));
    }

    values.sort();
    return Ok(ScenarioOutcome(
      mode: ScenarioMode.monteCarlo,
      baseValue: baseValue,
      distribution: ValueDistribution(values),
      discarded: discarded,
    ));
  }
}
