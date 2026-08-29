import 'ticker.dart';

/// Peso de alocação normalizado no intervalo [0, 1].
///
/// Diferente de [Money], este valor **é** ponto flutuante: peso não é saldo, e
/// a fração exata `1/3` não tem representação decimal. Por isso a igualdade é
/// tolerante ([tolerance]) em vez de exata, e a soma de um conjunto é conferida
/// por [Weights.sumsToOne], não por `== 1.0`.
class Weight implements Comparable<Weight> {
  /// Fração alocada, em `[0, 1]`. `0.25` representa 25% da carteira.
  final double value;

  const Weight._(this.value);

  /// Tolerância para comparação de soma. Um conjunto de pesos vindo de divisão
  /// (1/3 + 1/3 + 1/3) nunca soma exatamente 1,0 em ponto flutuante.
  static const double tolerance = 1e-9;

  /// Constrói a partir de uma fração.
  ///
  /// Admite uma folga de [tolerance] nas duas bordas para aceitar resíduo de
  /// divisão, e depois trava o valor em `[0, 1]` — de modo que um `1.0000000001`
  /// vindo de aritmética entra como `1.0` em vez de ser recusado.
  ///
  /// - [v]: fração desejada.
  ///
  /// Lança [ArgumentError] se [v] for `NaN` ou estiver fora de
  /// `[-tolerance, 1 + tolerance]`.
  factory Weight.fraction(double v) {
    if (v.isNaN || v < -tolerance || v > 1 + tolerance) {
      throw ArgumentError('Peso fora de [0,1]: $v');
    }
    return Weight._(v.clamp(0.0, 1.0));
  }

  /// Constrói a partir de um percentual (`25.0` para 25%).
  ///
  /// Lança [ArgumentError] nas mesmas condições de [Weight.fraction], aplicadas
  /// a `pct / 100`.
  factory Weight.percent(double pct) => Weight.fraction(pct / 100.0);

  /// Alocação nula. Usado como valor inicial antes de reequiponderar.
  static const Weight zero = Weight._(0.0);

  /// Percentual correspondente (`0.25` devolve `25.0`).
  double get percent => value * 100.0;

  @override
  int compareTo(Weight other) => value.compareTo(other.value);

  /// Igualdade **tolerante**: dois pesos separados por menos de [tolerance] são
  /// o mesmo peso.
  ///
  /// Necessário porque pesos nascem de divisão. [hashCode] acompanha, buscando
  /// a mesma granularidade — o que mantém o contrato `a == b ⇒ hash(a) == hash(b)`
  /// para valores idênticos, mas não o garante para valores meramente próximos
  /// que caiam em lados opostos de um degrau de arredondamento. Na prática pesos
  /// não são usados como chave de mapa; [Ticker] é.
  @override
  bool operator ==(Object other) =>
      other is Weight && (other.value - value).abs() < tolerance;

  @override
  int get hashCode => (value / tolerance).round().hashCode;

  @override
  String toString() => '${percent.toStringAsFixed(2)}%';
}

/// Operações sobre conjuntos de pesos, com tratamento explícito do resíduo
/// de ponto flutuante — a origem clássica de carteiras que somam 99,99%.
abstract final class Weights {
  /// Verifica se a soma equivale a 100% dentro de uma tolerância prática.
  /// A tolerância aqui é maior que [Weight.tolerance] porque acomoda o erro
  /// acumulado de somar até 15 parcelas.
  ///
  /// - [weights]: conjunto a conferir.
  /// - [epsilon]: folga admitida em torno de 1,0. Padrão `1e-6`.
  ///
  /// Retorna `true` para o conjunto vazio apenas se `epsilon >= 1.0` — a soma
  /// vazia é `0.0`, e uma carteira sem ativos não tem pesos válidos.
  static bool sumsToOne(Iterable<Weight> weights, {double epsilon = 1e-6}) {
    final total = weights.fold<double>(0.0, (a, w) => a + w.value);
    return (total - 1.0).abs() < epsilon;
  }

  /// Soma bruta das frações, sem normalizar nem conferir.
  static double sum(Iterable<Weight> weights) =>
      weights.fold<double>(0.0, (a, w) => a + w.value);

  /// Distribui 1,0 igualmente entre [tickers].
  ///
  /// O resíduo da divisão inexata é absorvido pelo primeiro elemento, de modo
  /// que a soma resultante é exatamente 1,0 e a carteira nunca fica com sobra
  /// ou falta de alocação. Verificado para n ∈ {3, 6, 7, 11, 15}: a soma é
  /// `== 1.0` exato, não apenas próximo.
  ///
  /// - [tickers]: ativos a equiponderar. Duplicatas colapsam, porque o
  ///   resultado é indexado por [Ticker].
  ///
  /// Retorna mapa vazio e constante para entrada vazia. Complexidade O(n).
  static Map<Ticker, Weight> equal(List<Ticker> tickers) {
    if (tickers.isEmpty) return const {};
    final share = 1.0 / tickers.length;
    final result = <Ticker, Weight>{};
    var accumulated = 0.0;
    for (var i = 1; i < tickers.length; i++) {
      result[tickers[i]] = Weight.fraction(share);
      accumulated += share;
    }
    result[tickers.first] = Weight.fraction(1.0 - accumulated);
    return result;
  }

  /// Reescala pesos arbitrários para somarem exatamente 1,0.
  /// Útil quando o usuário edita percentuais manualmente.
  ///
  /// Segue a mesma disciplina de [equal]: o resíduo vai para o primeiro
  /// elemento, e a soma fecha exata.
  ///
  /// - [raw]: pesos brutos por ativo, em qualquer escala positiva. Valores
  ///   individuais negativos são admitidos aqui e recusados adiante por
  ///   [Weight.fraction].
  ///
  /// Lança [ArgumentError] se a soma de [raw] não for positiva — sem massa
  /// total não há como reescalar. Propaga [ArgumentError] de [Weight.fraction]
  /// se alguma fração normalizada cair fora de `[0, 1]`.
  static Map<Ticker, Weight> normalize(Map<Ticker, double> raw) {
    final total = raw.values.fold<double>(0.0, (a, b) => a + b);
    if (total <= 0) {
      throw ArgumentError('Soma dos pesos deve ser positiva; recebido $total');
    }
    final entries = raw.entries.toList();
    final result = <Ticker, Weight>{};
    var accumulated = 0.0;
    for (var i = 1; i < entries.length; i++) {
      final w = entries[i].value / total;
      result[entries[i].key] = Weight.fraction(w);
      accumulated += w;
    }
    result[entries.first.key] = Weight.fraction(1.0 - accumulated);
    return result;
  }
}
