/// Código de negociação de uma ação da B3.
///
/// O universo é definido por `/v2/tickers?type=stock`, que já exclui fundos
/// (verificado: 781 ações contra 332 FIIs, interseção vazia). Não há, portanto,
/// inferência de classe a partir do sufixo — Units como `TAEE11` são ações.
class Ticker implements Comparable<Ticker> {
  final String value;

  const Ticker._(this.value);

  static final RegExp _pattern = RegExp(r'^[A-Z]{4}\d{1,2}$');

  /// Normaliza e valida. Lança [FormatException] em entrada inválida.
  factory Ticker.parse(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (!_pattern.hasMatch(normalized)) {
      throw FormatException('Ticker inválido: "$raw"');
    }
    return Ticker._(normalized);
  }

  /// Retorna `null` em vez de lançar — para entrada de usuário.
  static Ticker? tryParse(String raw) {
    try {
      return Ticker.parse(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  int compareTo(Ticker other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is Ticker && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
