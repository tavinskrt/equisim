import '../value_objects/money.dart';
import '../value_objects/ticker.dart';

/// Modelo efetivamente aplicado no cálculo.
///
/// O modelo **faz parte do resultado**, não é detalhe interno: cair
/// silenciosamente para um modelo inferior e apresentar o número como "preço
/// justo" esconde do usuário a qualidade da estimativa.
enum ValuationModel {
  /// Fluxo de caixa livre para a firma, descontado ao WACC.
  dcfFcff('DCF por FCFF'),

  /// DCF simplificado sobre lucro por ação, descontado ao Ke.
  dcfEarnings('DCF simplificado (LPA)'),

  /// Modelo de crescimento de Gordon sobre dividendos.
  gordonGrowth('Gordon (dividendos)'),

  /// Múltiplo setorial — último recurso.
  multiples('Múltiplos');

  final String label;
  const ValuationModel(this.label);
}

/// Método de cálculo do valor terminal.
enum TerminalValueMethod {
  /// Perpetuidade de Gordon.
  gordon('Perpetuidade de Gordon'),

  /// Múltiplo de saída sobre EBITDA.
  exitMultiple('Múltiplo de saída (EV/EBITDA)');

  final String label;
  const TerminalValueMethod(this.label);
}

/// Como os cenários foram gerados.
enum ScenarioMode { discrete, monteCarlo }

/// Faixas nomeadas apresentadas ao usuário.
enum ScenarioBand {
  bear('Pessimista'),
  base('Base'),
  bull('Otimista');

  final String label;
  const ScenarioBand(this.label);
}

/// Distribuição de valores justos produzida pelo motor de cenários.
class ValueDistribution {
  /// Valores por ação, ordenados crescentemente.
  final List<double> sortedValues;

  const ValueDistribution(this.sortedValues);

  bool get isEmpty => sortedValues.isEmpty;

  /// Percentil por interpolação linear. [p] em [0, 1].
  double percentile(double p) {
    if (sortedValues.isEmpty) return 0.0;
    if (sortedValues.length == 1) return sortedValues.first;
    final position = p.clamp(0.0, 1.0) * (sortedValues.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sortedValues[lower];
    final fraction = position - lower;
    return sortedValues[lower] * (1 - fraction) + sortedValues[upper] * fraction;
  }

  double get p5 => percentile(0.05);
  double get median => percentile(0.50);
  double get p95 => percentile(0.95);

  double get mean =>
      sortedValues.isEmpty
          ? 0.0
          : sortedValues.reduce((a, b) => a + b) / sortedValues.length;

  /// Proporção de cenários em que o valor justo supera [price].
  double probabilityAbove(double price) {
    if (sortedValues.isEmpty) return 0.0;
    final count = sortedValues.where((v) => v > price).length;
    return count / sortedValues.length;
  }
}

/// Resultado de uma avaliação de valor intrínseco.
class ValuationResult {
  final Ticker ticker;
  final DateTime asOf;
  final ValuationModel model;

  /// Preço justo por ação no cenário base.
  final Money fairValue;

  /// Preço de mercado na data de referência.
  final Money marketPrice;

  /// Margem de segurança aplicada sobre o preço justo, em fração.
  final double marginOfSafety;

  final ScenarioMode mode;

  /// Preenchido no modo discreto.
  final Map<ScenarioBand, Money>? discreteScenarios;

  /// Preenchido no modo Monte Carlo.
  final ValueDistribution? distribution;

  /// Custo de capital efetivamente usado no desconto, em fração.
  final double discountRate;

  /// Avisos acumulados (dados faltantes, aproximações, quedas de modelo).
  final List<String> warnings;

  const ValuationResult({
    required this.ticker,
    required this.asOf,
    required this.model,
    required this.fairValue,
    required this.marketPrice,
    required this.discountRate,
    this.marginOfSafety = 0.0,
    this.mode = ScenarioMode.discrete,
    this.discreteScenarios,
    this.distribution,
    this.warnings = const [],
  });

  /// Preço justo já descontado da margem de segurança.
  Money get safetyPrice => fairValue * (1.0 - marginOfSafety);

  /// Valorização total esperada até o preço justo, em fração.
  ///
  /// Atenção: é um número **total**, sem prazo. Para comparar com uma taxa
  /// requerida anual é preciso anualizá-lo por um horizonte de convergência
  /// declarado — ver `ExpectedReturn.annualizedFromUpside`.
  double get upside {
    if (marketPrice.cents <= 0) return 0.0;
    return (fairValue.reais - marketPrice.reais) / marketPrice.reais;
  }

  bool get isUndervalued => marketPrice <= safetyPrice;
}
