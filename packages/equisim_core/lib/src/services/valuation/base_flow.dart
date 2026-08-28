import 'dart:math' as math;

/// Um exercício da amostra que sustentou a mediana.
///
/// Existe para a auditoria: a mediana é o número que decide a banda, e uma
/// mediana apresentada sozinha é indistinguível de um chute. Quem confere a
/// conta precisa ver **quais** exercícios entraram na amostra, em que ano cada
/// um caiu e qual deles ficou no meio.
class BaseFlowPeriod {
  /// Rótulo do exercício — o ano fiscal, quando o chamador o informa.
  final String label;

  final double value;

  /// `true` para o exercício central da amostra (ou os dois centrais, quando
  /// a contagem é par): são estes que **definem** a mediana.
  final bool definesMedian;

  /// `true` para o exercício mais recente, o que a fórmula trata.
  final bool isObserved;

  const BaseFlowPeriod({
    required this.label,
    required this.value,
    this.definesMedian = false,
    this.isObserved = false,
  });
}

/// Fluxo-base de um DCF, depois do tratamento de exercício atípico.
class BaseFlow {
  /// Valor efetivamente usado como ponto de partida da projeção.
  final double value;

  /// Valor do exercício mais recente, antes de qualquer tratamento.
  final double observed;

  /// Mediana da amostra, quando houve amostra utilizável.
  final double? median;

  /// Exercícios considerados na mediana.
  final int periodsUsed;

  /// `true` quando o exercício mais recente saiu da banda e foi aparado.
  final bool winsorized;

  /// Tolerância efetivamente aplicada nesta normalização.
  final double tolerance;

  /// A amostra, em ordem cronológica, com o exercício central marcado.
  final List<BaseFlowPeriod> sample;

  const BaseFlow({
    required this.value,
    required this.observed,
    required this.median,
    required this.periodsUsed,
    this.winsorized = false,
    this.tolerance = BaseFlowNormalizer.defaultTolerance,
    this.sample = const [],
  });

  /// `true` quando a mediana sustenta uma banda relativa.
  ///
  /// A comparação é com a **borda** calculada pelo normalizador, não com zero:
  /// dinheiro em ponto flutuante não se compara com `==`, e uma mediana que é
  /// resíduo numérico passaria por `> 0` e produziria uma banda de largura
  /// desprezível — e, na divisão adiante, um fator astronômico.
  bool get hasBand => median != null && median! > _floor;

  /// Quantas vezes o exercício observado supera a mediana.
  double? get deviationFactor {
    if (!hasBand) return null;
    final factor = observed / median!;
    return factor.isFinite ? factor : null;
  }

  /// Borda inferior da banda, quando a banda existe.
  double? get lowerBound => hasBand ? median! * (1 - tolerance) : null;

  /// Borda superior da banda, quando a banda existe.
  double? get upperBound => hasBand ? median! * (1 + tolerance) : null;

  /// Piso de significância da mediana, relativo à escala da própria amostra.
  ///
  /// Relativo, e não absoluto, porque o normalizador é usado tanto sobre fluxo
  /// de caixa em bilhões quanto sobre lucro por papel em reais: um epsilon
  /// fixo estaria errado numa das duas escalas.
  double get _floor {
    if (sample.isEmpty) return 0;
    final escala = sample
        .map((p) => p.value.abs())
        .reduce((a, b) => a > b ? a : b);
    return escala * BaseFlowNormalizer.medianSignificance;
  }
}

/// Normaliza o fluxo-base de uma perpetuidade.
///
/// **O problema.** O valor terminal de um DCF é uma perpetuidade, e ela é
/// construída sobre o fluxo de **um único exercício**. Quando esse exercício é
/// atípico, o erro não fica contido: ele multiplica o valor inteiro da empresa.
/// Medido em 21/08/2026, a SAPR11 registrou caixa operacional de R$ 7,06 bi
/// contra EBITDA de R$ 2,34 bi — um fluxo livre 9,5× a mediana de cinco
/// exercícios —, e o preço justo saía em R$ 182 contra uma cotação de R$ 33.
///
/// **O tratamento.** Winsorização clássica: o exercício mais recente é aparado
/// para dentro de uma banda em torno da mediana da amostra, em vez de
/// substituído por ela. A diferença importa — substituir pela mediana
/// descartaria a informação de tendência, enquanto aparar preserva a direção e
/// só limita a magnitude.
///
/// **O que não faz.** Não ressuscita modelo: a decisão sobre qual modelo se
/// aplica continua sendo tomada sobre o exercício observado. E não aparta nada
/// quando a mediana é não positiva — aí a empresa queima caixa no ano típico,
/// e a fragilidade da perpetuidade é o próprio fato a reportar, não algo a
/// corrigir com aritmética.
abstract final class BaseFlowNormalizer {
  /// Exercícios da amostra. Cinco cobrem um ciclo curto sem envelhecer a base.
  static const int defaultWindow = 5;

  /// Meia-largura da banda, em fração da mediana.
  ///
  /// **Não é um critério de detecção de atípico — é um teto de política.** A
  /// justificativa completa, com os números medidos, está em
  /// `docs/validacao/normalizacao_fluxo_base.md`; o resumo é este:
  ///
  /// O valor da empresa é **exatamente proporcional** a este fluxo-base
  /// (`EV = F_0 · k`, com `k` função apenas de `r`, `g`, `g_inf` e `N`). Logo
  /// a meia-largura da banda é, literalmente, o quanto se autoriza um único
  /// exercício a mover a avaliação inteira: com `tau = 0,5`, no máximo 1,5×
  /// o que a empresa entrega num exercício típico.
  ///
  /// Medido sobre os 18 ativos das carteiras de teste (brapi, exercícios de
  /// 2010–2025; 151 janelas de cinco anos com mediana positiva), os critérios
  /// robustos clássicos implicariam bandas **mais largas**: `2·MAD/m` mediano
  /// dá `tau ≈ 0,80`, `3·MAD/m` dá `1,19`, e a cerca de Tukey dá `≈ 1,3`. O
  /// valor 0,5 fica perto do primeiro quartil desses critérios — é uma escolha
  /// deliberadamente conservadora, e apara 5 dos 11 ativos elegíveis ao FCFF.
  /// Afrouxar para 1,0 apararia 3; apertar para 0,3 apararia 8.
  static const double defaultTolerance = 0.5;

  /// Fração da maior magnitude da amostra abaixo da qual a mediana é tratada
  /// como não positiva.
  ///
  /// Existe porque `mediana > 0` não basta em ponto flutuante: uma mediana de
  /// `1e-16` num fluxo de bilhões passa no teste, gera uma banda de largura
  /// desprezível e faz o fator de desvio explodir. O corte é **relativo à
  /// escala da amostra**, para valer tanto em fluxo de caixa quanto em lucro
  /// por papel.
  static const double medianSignificance = 1e-9;

  /// [series] em ordem cronológica; o último elemento é o exercício-base.
  ///
  /// [labels] rotula cada elemento de [series] — o ano fiscal, tipicamente.
  /// Serve só para a auditoria e não participa de conta nenhuma; quando é
  /// omitido, ou tem comprimento diferente de [series], os rótulos saem como
  /// a posição relativa do exercício.
  static BaseFlow normalize(
    List<double> series, {
    List<String>? labels,
    int window = defaultWindow,
    double tolerance = defaultTolerance,
  }) {
    // `NaN` e `Infinity` não são exercícios ruins — são ausência de dado, e
    // entram aqui do mesmo jeito que um exercício não publicado: descartados.
    // Deixá-los passar seria pior que barrar: `NaN` derrota toda comparação
    // (`NaN <= x` é falso), então a mediana sairia positiva, a banda sairia
    // `NaN` e o fluxo-base chegaria contaminado à projeção, em silêncio. O
    // buraco na janela fica visível: a série deixa de ser contígua, e a
    // auditoria reporta a descontinuidade.
    final named = labels != null && labels.length == series.length;
    final finite = <double>[];
    final finiteLabels = <String>[];
    for (var i = 0; i < series.length; i++) {
      if (!series[i].isFinite) continue;
      finite.add(series[i]);
      if (named) finiteLabels.add(labels[i]);
    }

    if (finite.isEmpty) {
      return const BaseFlow(
        value: 0,
        observed: 0,
        median: null,
        periodsUsed: 0,
      );
    }

    final observed = finite.last;
    final start = finite.length <= window ? 0 : finite.length - window;
    final sample = finite.sublist(start);
    final names = [
      for (var i = 0; i < sample.length; i++)
        named ? finiteLabels[start + i] : 'T-${sample.length - 1 - i}',
    ];

    // Amostra curta demais não sustenta mediana: dois pontos não distinguem
    // exercício atípico de tendência.
    if (sample.length < 3) {
      return BaseFlow(
        value: observed,
        observed: observed,
        median: null,
        periodsUsed: sample.length,
        tolerance: tolerance,
        sample: _describe(sample, names, const {}),
      );
    }

    final periods = _describe(sample, names, _centralIndexes(sample));
    final median = _medianOf(sample);
    final escala = sample.map((v) => v.abs()).reduce(math.max);

    // Mediana não positiva — ou positiva apenas por resíduo numérico — não
    // autoriza banda: a empresa queima caixa no exercício típico, e essa
    // fragilidade é o fato a reportar, não algo a corrigir com aritmética.
    if (median <= escala * medianSignificance) {
      return BaseFlow(
        value: observed,
        observed: observed,
        median: median,
        periodsUsed: sample.length,
        tolerance: tolerance,
        sample: periods,
      );
    }

    final lower = median * (1 - tolerance);
    final upper = median * (1 + tolerance);
    final clamped = math.min(math.max(observed, lower), upper);

    return BaseFlow(
      value: clamped,
      observed: observed,
      median: median,
      periodsUsed: sample.length,
      winsorized: (clamped - observed).abs() > 1e-9,
      tolerance: tolerance,
      sample: periods,
    );
  }

  static List<BaseFlowPeriod> _describe(
    List<double> values,
    List<String> names,
    Set<int> central,
  ) =>
      [
        for (var i = 0; i < values.length; i++)
          BaseFlowPeriod(
            label: names[i],
            value: values[i],
            definesMedian: central.contains(i),
            isObserved: i == values.length - 1,
          ),
      ];

  /// Posições originais dos exercícios que ficam no meio da amostra ordenada.
  ///
  /// A marcação é feita pela **posição na ordenação**, não pelo valor: com
  /// exercícios repetidos, comparar por valor marcaria três ou quatro pontos e
  /// daria a entender que todos entraram na conta. Exatamente um ponto é
  /// marcado numa amostra ímpar, exatamente dois numa par.
  static Set<int> _centralIndexes(List<double> values) {
    final order = [for (var i = 0; i < values.length; i++) i]
      ..sort((a, b) => values[a].compareTo(values[b]));
    final middle = order.length ~/ 2;
    return order.length.isOdd
        ? {order[middle]}
        : {order[middle - 1], order[middle]};
  }

  static double _medianOf(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
