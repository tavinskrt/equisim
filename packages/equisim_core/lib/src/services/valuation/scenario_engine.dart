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
  /// Piso da faixa.
  final double min;

  /// Valor mais provável. Deve ficar em `[min, max]`.
  final double mode;

  /// Teto da faixa.
  final double max;

  /// Declara a faixa. **Não valida** `min ≤ mode ≤ max`: a violação não é
  /// detectada aqui, e sim em [sample], onde produz `NaN` pela raiz de número
  /// negativo. As faixas do pacote são construídas por
  /// [StochasticScenarios.around], que respeita a ordem por construção.
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

  /// `true` quando a faixa colapsou num único ponto e [sample] é constante.
  ///
  /// Comparação exata de `double` é correta aqui: o interesse é saber se as
  /// pontas são o **mesmo** valor — tipicamente por [TriangularRange.fixed] —,
  /// não se estão próximas. Uma faixa estreitíssima porém não degenerada
  /// continua sendo amostrada, e é isso que se quer.
  bool get isDegenerate => min == max;

  /// Amostragem por transformada inversa — determinística dado o gerador.
  ///
  /// - [rng]: gerador. Semeado por [ScenarioEngine.run], o que torna a
  ///   distribuição inteira reproduzível.
  ///
  /// Devolve [mode] sem consumir sorteio algum quando a faixa é degenerada —
  /// o que mantém o consumo de [rng] proporcional às faixas efetivamente
  /// aleatórias.
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
  /// Como esta fonte gera cenários.
  ///
  /// [ScenarioEngine.run] usa este valor para escolher o ramo de consolidação
  /// e, no modo discreto, faz **cast** para [DiscreteScenarios]. Implementações
  /// próprias que devolvam [ScenarioMode.discrete] sem estender aquela classe
  /// provocam [TypeError] em tempo de execução.
  ScenarioMode get mode;

  /// Premissas do cenário central, usadas como resultado principal.
  DcfAssumptions get base;

  /// Gera conjuntos de premissas a avaliar.
  ///
  /// - [samples]: quantidade desejada. Implementações discretas a ignoram e
  ///   devolvem seu conjunto fixo.
  /// - [rng]: gerador semeado, para que a rodada seja reproduzível.
  List<DcfAssumptions> draw(int samples, math.Random rng);
}

/// Três conjuntos fixos de premissas — Pessimista, Base e Otimista.
class DiscreteScenarios implements AssumptionSource {
  /// Premissas por faixa. **Precisa conter [ScenarioBand.base]** — [base]
  /// desreferencia essa chave e lança se ela faltar.
  final Map<ScenarioBand, DcfAssumptions> scenarios;

  /// Declara os cenários diretamente. Para derivá-los de um cenário central,
  /// use [DiscreteScenarios.around].
  const DiscreteScenarios(this.scenarios);

  /// Constrói as três faixas a partir de um cenário central, deslocando
  /// crescimento e desconto em direções opostas.
  ///
  /// **O deslocamento alcança as duas taxas de desconto.** Deslocar só a
  /// corrente deixava o valor terminal praticamente imóvel — ele desconta pela
  /// taxa de equilíbrio —, e o terminal responde por metade a quatro quintos do
  /// valor. Medido: com a taxa terminal congelada, a banda de um ativo típico
  /// ficava em −11,2% / +12,9%; deslocando as duas, ela vai a −19,8% / +30,9%.
  /// A banda apresentada afirmava uma precisão que o modelo não tem.
  ///
  /// - [center]: premissas do cenário Base, repassadas sem alteração.
  /// - [growthDelta]: deslocamento do crescimento explícito. Padrão 3 p.p.
  /// - [discountDelta]: deslocamento das taxas de desconto. Padrão 2 p.p.
  ///
  /// No cenário otimista a taxa **terminal** é limitada por baixo a
  /// `perpetualGrowth + DcfCalculator.minimumSpread`: é ela que entra no spread
  /// da perpetuidade, e o piso antes protegia a corrente — a taxa errada, que
  /// não participa daquele quociente.
  factory DiscreteScenarios.around(
    DcfAssumptions center, {
    double growthDelta = 0.03,
    double discountDelta = 0.02,
  }) =>
      DiscreteScenarios({
        ScenarioBand.bear: center.copyWith(
          growthRate: center.growthRate - growthDelta,
          discountRate: center.discountRate + discountDelta,
          terminalDiscountRate: center.terminalDiscountRate + discountDelta,
        ),
        ScenarioBand.base: center,
        ScenarioBand.bull: center.copyWith(
          growthRate: center.growthRate + growthDelta,
          // A taxa corrente desconta o período explícito e **não** participa do
          // quociente da perpetuidade: o piso que a prendia ao crescimento
          // perpétuo era restrição sem conteúdo, e travava o desconto do
          // cenário otimista acima do que o deslocamento pedia. Aqui basta
          // garantir que ela continue positiva, que é o que `_project` exige.
          discountRate: math.max(
            center.discountRate - discountDelta,
            DcfCalculator.minimumSpread,
          ),
          terminalDiscountRate: math.max(
            center.terminalDiscountRate - discountDelta,
            center.perpetualGrowth + DcfCalculator.minimumSpread,
          ),
        ),
      });

  @override
  ScenarioMode get mode => ScenarioMode.discrete;

  /// Premissas da faixa Base.
  ///
  /// Lança [TypeError] se [scenarios] não contiver [ScenarioBand.base].
  @override
  DcfAssumptions get base => scenarios[ScenarioBand.base]!;

  /// Devolve os três cenários fixos, **ignorando [samples] e [rng]**.
  ///
  /// Os dois parâmetros existem por imposição de [AssumptionSource.draw], que
  /// [StochasticScenarios] implementa sorteando. Aqui não há o que sortear: o
  /// conjunto é o que o chamador declarou. Consumir [rng] mesmo assim
  /// adiantaria o estado do gerador e faria o resultado depender do modo, o que
  /// quebraria a reprodutibilidade prometida por [ScenarioEngine.run].
  @override
  List<DcfAssumptions> draw(int samples, math.Random rng) =>
      scenarios.values.toList();
}

/// Premissas sorteadas de distribuições declaradas.
class StochasticScenarios implements AssumptionSource {
  @override
  final DcfAssumptions base;

  /// Faixa do crescimento explícito, em fração ao ano.
  final TriangularRange growth;

  /// Faixa da taxa de desconto, em fração ao ano.
  final TriangularRange discount;

  /// Faixa do crescimento na perpetuidade, em fração ao ano. Cada sorteio é
  /// truncado em [draw] para preservar a distância mínima até o desconto.
  final TriangularRange perpetual;

  /// Declara as faixas diretamente. Para derivá-las de um cenário central,
  /// use [StochasticScenarios.around].
  const StochasticScenarios({
    required this.base,
    required this.growth,
    required this.discount,
    required this.perpetual,
  });

  /// Faixas simétricas em torno do cenário central.
  ///
  /// - [center]: premissas do cenário Base.
  /// - [growthSpread]: meia-largura da faixa de crescimento. Padrão 4 p.p.
  /// - [discountSpread]: meia-largura da faixa de desconto. Padrão 2 p.p.
  /// - [perpetualSpread]: meia-largura da perpetuidade. Padrão 1 p.p.
  ///
  /// O piso da faixa perpétua é travado em zero: crescimento perpétuo negativo
  /// não é premissa defensável para uma empresa em continuidade.
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
      // O sorteio desloca as duas taxas pelo mesmo tanto: a de equilíbrio é a
      // que desconta a perpetuidade, e congelá-la deixaria de fora a parcela
      // que mais pesa no valor. O deslocamento é paralelo — a estrutura a termo
      // é premissa do modelo, não fonte de incerteza sorteada aqui.
      final deslocamento = r - base.discountRate;
      final rInf = base.terminalDiscountRate + deslocamento;
      final gp = perpetual.sample(rng);
      out.add(base.copyWith(
        growthRate: growth.sample(rng),
        discountRate: r,
        terminalDiscountRate: rInf,
        // Mantém a distância mínima contra a taxa **terminal**, que é a do
        // spread da perpetuidade: sorteios com r_inf ≤ g seriam descartados
        // pelo cálculo e enviesariam a distribuição para cima.
        perpetualGrowth: math.min(gp, rInf - DcfCalculator.minimumSpread),
      ));
    }
    return out;
  }
}

/// Resultado consolidado de uma rodada de cenários.
class ScenarioOutcome {
  /// Como os cenários foram gerados — determina qual de [discrete] e
  /// [distribution] está preenchido.
  final ScenarioMode mode;

  /// Valor por ação do cenário central.
  final double baseValue;

  /// Preenchido no modo discreto.
  final Map<ScenarioBand, double>? discrete;

  /// Preenchido no modo Monte Carlo.
  final ValueDistribution? distribution;

  /// Sorteios descartados por não produzirem valor válido.
  final int discarded;

  /// Agrupa o resultado já consolidado. Não calcula nada.
  const ScenarioOutcome({
    required this.mode,
    required this.baseValue,
    this.discrete,
    this.distribution,
    this.discarded = 0,
  });
}

/// Executa uma avaliação sobre um conjunto de cenários e consolida o resultado.
abstract final class ScenarioEngine {
  /// Executa a avaliação sobre todos os cenários da fonte.
  ///
  /// [valuate] recebe um conjunto de premissas e devolve o valor por ação.
  /// [seed] fixa o gerador: a mesma entrada produz sempre o mesmo resultado,
  /// requisito de reprodutibilidade.
  ///
  /// - [source]: fonte das premissas. Define o modo e, com ele, o formato do
  ///   resultado.
  /// - [valuate]: avaliação de um conjunto de premissas. Chamada uma vez para
  ///   o cenário central e depois uma vez por cenário sorteado.
  /// - [samples]: sorteios no modo Monte Carlo. Ignorado no modo discreto.
  ///   Padrão `10000`.
  /// - [seed]: semente do gerador. Padrão `42`.
  ///
  /// Propaga a falha de [valuate] sobre o cenário central — sem valor base não
  /// há resultado. Devolve [ComputationFailure] quando **nenhum** cenário
  /// produz valor válido; cenários individuais que falham apenas incrementam
  /// [ScenarioOutcome.discarded]. No modo Monte Carlo também são descartados os
  /// valores não finitos ou não positivos.
  ///
  /// Lança [TypeError] se [source] declarar [ScenarioMode.discrete] sem ser um
  /// [DiscreteScenarios] — o ramo discreto precisa do mapa de faixas, que não
  /// está na interface.
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
    for (final a in source.draw(samples, rng)) {
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
