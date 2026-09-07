import '../value_objects/money.dart';
import '../value_objects/ticker.dart';

/// Modelo efetivamente aplicado no cálculo.
///
/// O modelo **faz parte do resultado**, não é detalhe interno: cair
/// silenciosamente para um modelo inferior e apresentar o número como "preço
/// justo" esconde do usuário a qualidade da estimativa.
enum ValuationModel {
  /// Fluxo da firma, descontado ao WACC.
  ///
  /// `NOPAT × (1 − RI)`, com freio de reinvestimento — a decisão 25 estendeu à
  /// firma a correção que a 24 fizera só do lado do acionista.
  dcfFcff('DCF por fluxo da firma'),

  /// DCF sobre lucro distribuível, descontado ao Ke.
  ///
  /// É o modelo de desconto de dividendos da via do acionista: o fluxo é
  /// `LPA × (1 − b)`, e `1 − b` é o *payout*. O dividendo vem da identidade da
  /// retenção, não de dado publicado de provento — o que o mantém compatível com
  /// a decisão 23.
  dcfEarnings('DCF sobre lucro distribuível');

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
enum ScenarioMode {
  /// Três conjuntos fixos de premissas — Pessimista, Base e Otimista.
  /// Preenche `discreteScenarios` no resultado.
  discrete,

  /// Premissas sorteadas de distribuições triangulares declaradas.
  /// Preenche `distribution` no resultado.
  monteCarlo,
}

/// Faixas nomeadas apresentadas ao usuário.
enum ScenarioBand {
  /// Crescimento deslocado para baixo e desconto para cima.
  bear('Pessimista'),

  /// Premissas centrais. É o cenário cujo valor vira o preço justo.
  base('Base'),

  /// Crescimento deslocado para cima e desconto para baixo, respeitado o
  /// spread mínimo da perpetuidade.
  bull('Otimista');

  /// Rótulo de exibição, em português.
  final String label;

  const ScenarioBand(this.label);
}

/// Distribuição de valores justos produzida pelo motor de cenários.
class ValueDistribution {
  /// Valores por ação, ordenados crescentemente.
  final List<double> sortedValues;

  /// Envolve uma lista **já ordenada**. Não ordena nem copia — ordenar é
  /// responsabilidade de quem constrói, e `ScenarioEngine.run` o faz.
  /// Passar lista desordenada produz percentis errados em silêncio.
  const ValueDistribution(this.sortedValues);

  /// `true` quando nenhum cenário produziu valor válido.
  bool get isEmpty => sortedValues.isEmpty;

  /// Percentil por interpolação linear. [p] em [0, 1].
  ///
  /// - [p]: posição desejada, travada em `[0, 1]` — valores fora da faixa não
  ///   lançam, saem nas pontas.
  ///
  /// Devolve `0.0` para distribuição vazia, e o único elemento quando há
  /// apenas um. Complexidade O(1).
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

  /// Percentil 5 — borda pessimista da banda apresentada.
  double get p5 => percentile(0.05);

  /// Mediana. É o valor central apresentado no modo Monte Carlo, preferido à
  /// [mean] por não ser arrastado pela cauda direita da distribuição de preços.
  double get median => percentile(0.50);

  /// Percentil 95 — borda otimista da banda apresentada.
  double get p95 => percentile(0.95);

  /// Média aritmética. Devolve `0.0` para distribuição vazia. Complexidade
  /// O(n) — ao contrário dos percentis, não aproveita a ordenação.
  double get mean =>
      sortedValues.isEmpty
          ? 0.0
          : sortedValues.reduce((a, b) => a + b) / sortedValues.length;

  /// Proporção de cenários em que o valor justo supera [price].
  ///
  /// - [price]: preço de comparação, tipicamente a cotação de mercado.
  ///
  /// Devolve fração em `[0, 1]`, e `0.0` para distribuição vazia. A comparação
  /// é estrita: cenários exatamente iguais a [price] não contam.
  /// Complexidade O(n).
  double probabilityAbove(double price) {
    if (sortedValues.isEmpty) return 0.0;
    final count = sortedValues.where((v) => v > price).length;
    return count / sortedValues.length;
  }
}

/// Resultado de uma avaliação de valor intrínseco.
class ValuationResult {
  /// Ativo avaliado.
  final Ticker ticker;

  /// Data de referência da avaliação — define o recorte *point-in-time* dos
  /// fundamentos e o preço de mercado comparado.
  final DateTime asOf;

  /// Modelo que efetivamente produziu [fairValue]. **Faz parte do resultado**:
  /// um número vindo de múltiplos não tem a mesma qualidade de um vindo de
  /// FCFF, e omitir isso esconderia a diferença.
  final ValuationModel model;

  /// Preço justo por ação no cenário base.
  final Money fairValue;

  /// Preço de mercado na data de referência.
  final Money marketPrice;

  /// Margem de segurança aplicada sobre o preço justo, em fração.
  final double marginOfSafety;

  /// Como os cenários foram gerados. Determina qual de [discreteScenarios] e
  /// [distribution] está preenchido.
  final ScenarioMode mode;

  /// Preenchido no modo discreto.
  final Map<ScenarioBand, Money>? discreteScenarios;

  /// Preenchido no modo Monte Carlo.
  final ValueDistribution? distribution;

  /// Custo de capital efetivamente usado no desconto, em fração.
  final double discountRate;

  /// Avisos acumulados (dados faltantes, aproximações, quedas de modelo).
  final List<String> warnings;

  /// Agrupa o resultado já apurado. Não calcula nada — o cálculo vive em
  /// `ValuationCascade.evaluate`.
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
  ///
  /// É o limiar de compra: só abaixo dele o ativo é considerado descontado.
  /// Herda o arredondamento de [Money.operator *].
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

  /// `true` quando o preço de mercado está em ou abaixo de [safetyPrice].
  ///
  /// Comparação exata entre inteiros de centavos, e **inclusiva** na borda:
  /// preço igual ao de segurança conta como descontado.
  bool get isUndervalued => marketPrice <= safetyPrice;
}
