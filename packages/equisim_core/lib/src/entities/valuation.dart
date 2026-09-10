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

/// Por que a estimativa perdeu confiança.
///
/// Cada item é um **fato medido** no caminho do cálculo, não um julgamento: a
/// cascata já os apura para decidir a conta, e antes eles só existiam diluídos
/// no texto dos avisos. Estruturá-los é o que permite ao consumidor ponderar o
/// preço justo em vez de tratar todos como igualmente firmes.
enum ValuationCaveat {
  /// O valor terminal responde por mais que
  /// [ValuationDiagnostics.terminalShareLimit] do total: o número é sobretudo
  /// premissa, e a parte apoiada em exercício observado decide pouco.
  terminalPesado('o valor terminal domina o preço justo'),

  /// A taxa de crescimento não veio do próprio ativo — foi a âncora de
  /// inflação ou a ausência de crescimento.
  crescimentoNaoIdentificado('o crescimento não é identificável no histórico'),

  /// As duas contagens de papéis publicadas divergem além de uma ação
  /// societária plausível, e a escolha do divisor foi por conservadorismo.
  escalaIncerta('a base societária publicada é ambígua'),

  /// Um único exercício foi multiplicado por mais de
  /// [ValuationDiagnostics.baseFactorLimit] para virar o fluxo-base.
  baseNormalizadaForte('a base depende de forte correção de um só exercício'),

  /// A avaliação começou na via da firma e migrou para a do acionista.
  viaMigrada('a via de avaliação mudou no meio do cálculo'),

  /// O capital próprio responde por pouco do valor da firma, e o preço por
  /// papel é resíduo de subtração entre números próximos.
  ///
  /// **A ressalva de custo da dívida estimado saiu deste conjunto**, e a
  /// medição é o motivo: ela disparava em 469 das 821 avaliações do backtest —
  /// 57% —, porque a classificação sintética passou a ser o **método** pela
  /// decisão 31, e não mais um recuo. Ressalva que vale para a maioria não
  /// distingue nada; a substituição continua declarada nos avisos, que é onde
  /// ela informa.
  ponteFragil('o preço por papel é resíduo de uma subtração frágil');

  final String label;
  const ValuationCaveat(this.label);
}

/// Fatos medidos que qualificam o preço justo.
///
/// **Por que existe.** Um preço justo cujo valor terminal responde por 85% do
/// total, cuja taxa veio da inflação e cujo divisor é ambíguo não é o mesmo
/// objeto que um apoiado em crescimento identificado e escala conciliada — e,
/// até aqui, os dois chegavam à tela como um número só, com a diferença
/// espalhada em texto corrido. Para decisão patrimonial isso não basta: a
/// carteira precisa poder ponderar pela firmeza da estimativa.
///
/// Tudo aqui já era apurado pela cascata. O que muda é que passa a sair com o
/// resultado, em forma que a máquina lê.
class ValuationDiagnostics {
  /// Parcela do preço justo explicada pelo valor terminal, em fração.
  final double terminalShare;

  /// Participação do capital próprio no valor da firma. `1.0` na via do
  /// acionista, que não tem ponte.
  final double equityShare;

  /// Fator de normalização aplicado ao exercício-base.
  final double baseFactor;

  /// `true` quando a taxa de crescimento saiu do próprio histórico.
  final bool growthIdentified;

  /// `true` quando a perpetuidade preserva excedente de retorno.
  final bool moatApplied;

  /// Custo de capital de equilíbrio — a taxa que desconta a perpetuidade.
  ///
  /// [ValuationResult.discountRate] é a taxa do **primeiro ano**, e desde a
  /// estrutura a termo da decisão 31 as duas não coincidem: a taxa decai
  /// linearmente do CDI corrente até esta ao longo da projeção. Com o terminal
  /// respondendo pela maior parte do valor, era esta que faltava sair — e ela
  /// é também a referência contra a qual o excedente de retorno se mede.
  final double terminalDiscountRate;

  /// Ressalvas medidas, na ordem em que a cascata as apura.
  final List<ValuationCaveat> caveats;

  const ValuationDiagnostics({
    required this.terminalShare,
    required this.equityShare,
    required this.baseFactor,
    required this.growthIdentified,
    required this.moatApplied,
    required this.terminalDiscountRate,
    this.caveats = const [],
  });

  /// Acima disto, o valor terminal domina e a estimativa é rebaixada.
  ///
  /// **80%, e o corte tem origem.** A decisão 25 fixou a projeção explícita em
  /// dez anos justamente porque, com cinco, o terminal carregava de 63,5% a
  /// 80,0% do preço justo e "a parte da conta apoiada em dado observado decidia
  /// pouco". O limiar é o topo daquela faixa: acima dele, o horizonte de dez
  /// anos não conseguiu o que foi escolhido para conseguir.
  static const double terminalShareLimit = 0.80;

  /// Acima disto, um único exercício move demais a avaliação inteira.
  ///
  /// **2,0x, e é metade da autoridade que a saturação permite.** A decisão 28
  /// confinou o fator em `[0,33; 3,00]` dizendo que acima de 3x "a normalização
  /// deixaria de corrigir um exercício para inventar uma empresa". O corte aqui
  /// não proíbe nada — apenas marca que, passando de 2x, o preço justo passou a
  /// depender mais da mediana do ciclo que do exercício observado.
  static const double baseFactorLimit = 2.0;

  /// Abaixo disto a ponte é frágil, embora ainda acima do corte que faz migrar.
  ///
  /// **35%, contra os 20% que reprovam.** A pós-condição da via da firma migra
  /// abaixo de 20%; entre 20% e 35% ela não migra e o preço por papel já é
  /// resíduo de uma subtração com amplificação de três a cinco vezes. A faixa
  /// entre os dois cortes é onde o número sai sem aviso nenhum, e é ela que
  /// esta ressalva cobre.
  static const double fragileEquityShare = 0.35;

  /// **Não existe nota de confiança aqui, e a ausência é medida.**
  ///
  /// A primeira versão destes diagnósticos trazia uma nota ordinal — alta,
  /// média, baixa — derivada da contagem de ressalvas. A validação preditiva da
  /// decisão 32 a desmentiu: no horizonte de 36 meses, o grupo **sem ressalva
  /// alguma** teve coeficiente de informação de **−0,007**, positivo em 2 de 5
  /// coortes, enquanto o grupo com uma ou duas ressalvas teve **0,206**,
  /// positivo em 5 de 5. A nota ordenava ao contrário do que prometia.
  ///
  /// A explicação plausível — não medida — é que o ativo sem ressalva é o
  /// estável e previsível, que é justamente o que o mercado já precifica bem;
  /// a discordância informativa aparece onde o modelo faz algo que o preço não
  /// fez. Seja qual for a causa, apresentar uma nota que ordena ao contrário
  /// seria falsa precisão num número destinado a decisão patrimonial.
  ///
  /// O que fica são os **fatos**: eles descrevem o que a conta fez, e isso
  /// continua verdadeiro e continua útil. O que saiu foi a promessa de que eles
  /// medem confiabilidade.
  bool get hasCaveats => caveats.isNotEmpty;
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

  /// Fatos medidos que qualificam o preço justo. `null` só quando o resultado
  /// é montado à mão, fora da cascata.
  final ValuationDiagnostics? diagnostics;

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
    this.diagnostics,
  });

  /// Ressalvas estruturadas do cálculo, vazias quando não há diagnóstico.
  List<ValuationCaveat> get caveats =>
      diagnostics?.caveats ?? const <ValuationCaveat>[];

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
