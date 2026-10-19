/// Por que o lucro de partida foi normalizado — ou não —, e em que direção.
library;

import 'capital_base.dart';
import '../../audit/wire_keyed.dart';

/// O que a normalização fez com o lucro de partida.
///
/// Cada valor responde à pergunta de quem lê a avaliação: **o motor partiu do
/// lucro publicado, ou de outro, e por quê?**
enum BaseNormalizationOutcome implements WireKeyed {
  /// O último exercício rendeu **menos** que o retorno típico da empresa — a
  /// mediana do ciclo —, e destoou o bastante: a base subiu até o lucro que a
  /// empresa teria rendendo o típico.
  upward('paraCima'),

  /// O último exercício rendeu **mais** que o típico, e destoou o bastante: a
  /// base desceu até o lucro que a empresa teria rendendo o típico.
  downward('paraBaixo'),

  /// O último exercício está dentro do normal da empresa: a base é o lucro
  /// publicado.
  withinNormal('dentroDoNormal'),

  /// Destoou, mas o retorno tem tendência que domina a reversão ao ciclo: o
  /// último exercício é lido como o novo patamar, e a base é o publicado.
  trend('tendencia'),

  /// Subiria, mas o lucro ou o EBITDA caiu mais da metade em três anos: a
  /// empresa mudou de patamar, e a base fica no publicado.
  healthLocked('travadaPelaSaude'),

  /// O último exercício deu prejuízo: não há fator a aplicar, e a base é o
  /// retorno típico sobre o capital de hoje (decisão 53).
  rebuilt('reconstruida'),

  /// Sem ciclo medível — série curta, ou ciclo que não é positivo —: a base é o
  /// publicado.
  noCycle('semCiclo'),

  /// Fator imposto de fora, por varredura de diagnóstico.
  imposed('imposta');

  const BaseNormalizationOutcome(this.key);

  /// Chave gravada nas saídas — pacote de dados, rastro de auditoria,
  /// relatório. É dado, e não nome de código: renomear o valor não a muda.
  @override
  final String key;
}

/// **A decisão da normalização do lucro de partida, com tudo o que a decidiu**
/// (Saída 1 da Porta 2).
///
/// O motor não parte do lucro do último exercício quando ele destoa do retorno
/// típico da empresa: um ano só pode estar num pico ou num vale, e o preço justo
/// é proporcional ao lucro de partida. Ele compara o retorno sobre o capital do
/// último exercício com a mediana dos oito anteriores e, quando os dois
/// destoam, parte do lucro que a empresa de hoje teria rendendo a mediana:
///
/// ```
/// fator = retorno típico ÷ retorno do último exercício   (entre 0,33 e 3)
/// base  = lucro do último exercício × fator
/// ```
///
/// **Existe para explicar, e não para decidir.** Cada campo é o valor que a
/// cascata já usou — nada aqui recalcula a guarda —, e o rastro de auditoria e
/// a tela de edição do valuation leem daqui o porquê e a direção.
class BaseNormalization {
  /// Via da avaliação: retorno sobre o capital investido na da firma, sobre o
  /// patrimônio na do acionista.
  final ValuationLane lane;

  /// Ano e retorno do último exercício, ou `null` sem retorno medível.
  final int? latestYear;
  final double? latestReturn;

  /// Os exercícios cuja mediana é o retorno típico: os oito anteriores ao
  /// último, ou menos quando a série é mais curta.
  final List<({int year, double value})> cycleWindow;

  /// O retorno típico — a mediana de [cycleWindow] —, ou `null` sem ciclo.
  final double? cycleReturn;

  /// O último exercício sobre o típico, ou `null` sem ciclo positivo.
  final double? ratio;

  /// A distância entre os dois, em desvios robustos da janela.
  final double? robustZ;

  /// `true` quando o último exercício destoa do típico (Guarda 3): a razão sai
  /// de `[0,75; 1,33]` ou a distância passa de 1,5 desvio robusto.
  final bool deviates;

  /// A tendência do retorno (Guarda 1): inclinação em fração ao ano, `t` de
  /// Newey-West e o crítico, ou `null` quando a série não a sustenta.
  final double? trendSlope;
  final double? trendT;
  final double? trendCriticalT;

  /// `true` quando a tendência é significante e domina a reversão ao ciclo.
  final bool trendDominates;

  /// `true` em commodity e cíclico pesado, onde a reversão ao ciclo tem
  /// precedência sobre a tendência (decisão 28).
  final bool cyclicalPrecedence;

  /// Queda do lucro ou do EBITDA no triênio, em fração, ou `null` sem medida.
  final double? operationalDecline;

  /// `true` quando a queda impediu a base de subir (decisões 28 e 29).
  final bool healthCapped;

  /// `true` quando a queda passou do limite, mas o setor é cíclico e está
  /// isento da trava (decisão 30).
  final bool healthExempt;

  /// O fator que a razão pedia, antes dos limites.
  final double rawFactor;

  /// O fator aplicado ao lucro do último exercício.
  final double factor;

  /// `true` quando o fator bruto saiu de `[0,33; 3]` e foi limitado.
  final bool saturated;

  /// `true` quando a base foi reconstruída do ciclo (decisão 53), e a fração
  /// positiva da janela que a autorizou.
  final bool rebuilt;
  final double? rebuiltPositiveShare;

  /// `true` quando o fator foi imposto de fora.
  final bool imposed;

  /// Lucro do último exercício, em reais, sem a normalização: `NOPAT` na via
  /// da firma, lucro líquido na do acionista. `null` quando não é medível.
  final double? publishedProfit;

  /// O lucro de partida que a cascata usou, em reais.
  final double? baseProfit;

  /// Declara a decisão. Quem a monta é a cascata, na Saída 1.
  const BaseNormalization({
    required this.lane,
    this.latestYear,
    this.latestReturn,
    this.cycleWindow = const [],
    this.cycleReturn,
    this.ratio,
    this.robustZ,
    this.deviates = false,
    this.trendSlope,
    this.trendT,
    this.trendCriticalT,
    this.trendDominates = false,
    this.cyclicalPrecedence = false,
    this.operationalDecline,
    this.healthCapped = false,
    this.healthExempt = false,
    this.rawFactor = 1.0,
    this.factor = 1.0,
    this.saturated = false,
    this.rebuilt = false,
    this.rebuiltPositiveShare,
    this.imposed = false,
    this.publishedProfit,
    this.baseProfit,
  });

  /// O que a normalização fez, pela ordem em que a cascata decide.
  BaseNormalizationOutcome get outcome {
    if (imposed) return BaseNormalizationOutcome.imposed;
    if (rebuilt) return BaseNormalizationOutcome.rebuilt;
    final current = latestReturn;
    final cycle = cycleReturn;
    if (current == null || cycle == null || cycle <= 0 || current <= 0) {
      return BaseNormalizationOutcome.noCycle;
    }
    if (!deviates) return BaseNormalizationOutcome.withinNormal;
    if (trendDominates && !cyclicalPrecedence) {
      return BaseNormalizationOutcome.trend;
    }
    if (healthCapped) return BaseNormalizationOutcome.healthLocked;
    if (factor > 1) return BaseNormalizationOutcome.upward;
    if (factor < 1) return BaseNormalizationOutcome.downward;
    return BaseNormalizationOutcome.withinNormal;
  }

  /// O primeiro e o último ano da janela do ciclo, ou `null` sem janela.
  ({int first, int last})? get windowYears => cycleWindow.isEmpty
      ? null
      : (first: cycleWindow.first.year, last: cycleWindow.last.year);
}
