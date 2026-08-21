/// Código de negociação de uma ação da B3.
///
/// O universo é definido por `/v2/tickers?type=stock`, que já exclui fundos
/// (verificado: 781 ações contra 332 FIIs, interseção vazia). Não há, portanto,
/// inferência de classe a partir do sufixo — Units como `TAEE11` são ações.
class Ticker implements Comparable<Ticker> {
  final String value;

  const Ticker._(this.value);

  /// Raiz de quatro caracteres iniciada por letra, seguida do código da classe.
  ///
  /// A raiz aceita dígitos porque a B3 os usa: **B3SA3**, a própria bolsa, tem
  /// "3" na segunda posição. Um padrão de quatro letras a excluiria da lista de
  /// ativos — foi o que aconteceu na primeira versão.
  ///
  /// Tickers do mercado fracionário (`PETR4F`) são rejeitados naturalmente,
  /// porque o sufixo não é dígito. Isso é desejado: representam o mesmo ativo
  /// e, admitidos, permitiriam montar uma carteira com PETR4 e PETR4F como se
  /// fossem empresas distintas.
  static final RegExp _pattern = RegExp(r'^[A-Z][A-Z0-9]{3}\d{1,2}$');

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
