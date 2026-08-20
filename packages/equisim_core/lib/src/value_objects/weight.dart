import 'ticker.dart';

/// Peso de alocação normalizado no intervalo [0, 1].
class Weight implements Comparable<Weight> {
  final double value;

  const Weight._(this.value);

  /// Tolerância para comparação de soma. Um conjunto de pesos vindo de divisão
  /// (1/3 + 1/3 + 1/3) nunca soma exatamente 1,0 em ponto flutuante.
  static const double tolerance = 1e-9;

  factory Weight.fraction(double v) {
    if (v.isNaN || v < -tolerance || v > 1 + tolerance) {
      throw ArgumentError('Peso fora de [0,1]: $v');
    }
    return Weight._(v.clamp(0.0, 1.0));
  }

  factory Weight.percent(double pct) => Weight.fraction(pct / 100.0);

  static const Weight zero = Weight._(0.0);
  static const Weight one = Weight._(1.0);

  double get percent => value * 100.0;

  @override
  int compareTo(Weight other) => value.compareTo(other.value);

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
  static bool sumsToOne(Iterable<Weight> weights, {double epsilon = 1e-6}) {
    final total = weights.fold<double>(0.0, (a, w) => a + w.value);
    return (total - 1.0).abs() < epsilon;
  }

  static double sum(Iterable<Weight> weights) =>
      weights.fold<double>(0.0, (a, w) => a + w.value);

  /// Distribui 1,0 igualmente entre [tickers].
  ///
  /// O resíduo da divisão inexata é absorvido pelo primeiro elemento, de modo
  /// que a soma resultante é exatamente 1,0 e a carteira nunca fica com sobra
  /// ou falta de alocação.
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
