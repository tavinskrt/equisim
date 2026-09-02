import '../failures/failure.dart';
import '../failures/result.dart';

/// Duas séries de retorno que **não podem** ter comprimentos diferentes.
///
/// Existe para tirar a conferência de dimensão de dentro do cálculo. Antes,
/// `BetaCalculator.estimate` recebia duas listas soltas e abria com um `if`
/// comparando `length` — validação de estrutura no meio de aritmética, e um
/// caminho de erro que só disparava em tempo de execução. Aqui a paridade é
/// garantida na construção: quem tem um [PairedReturns] em mãos já sabe que as
/// duas pontas casam.
///
/// A regra vale para o **comprimento**, não para o conteúdo: o valor de cada
/// posição segue sendo responsabilidade de quem pareou por data.
class PairedReturns {
  /// Retornos do ativo, na ordem em que foram pareados.
  final List<double> asset;

  /// Retornos do índice, alinhados a [asset] posição a posição.
  final List<double> market;

  const PairedReturns._(this.asset, this.market);

  /// Par vazio. Ponto de partida de quem acumula, e resposta natural de um
  /// pareamento sem data em comum.
  static const PairedReturns empty = PairedReturns._([], []);

  /// Constrói o par a partir de duas séries prontas.
  ///
  /// - [asset], [market]: retornos já pareados por data.
  ///
  /// Devolve [InvalidInput] quando os comprimentos divergem — é o único jeito
  /// de construir um par inválido, e ele é fechado aqui em vez de adiante.
  static Result<PairedReturns> of({
    required List<double> asset,
    required List<double> market,
  }) {
    if (asset.length != market.length) {
      return Err(InvalidInput(
        'Séries de retorno com tamanhos diferentes (${asset.length} × '
        '${market.length}); pareie por data antes.',
      ));
    }
    return Ok(PairedReturns._(
      List<double>.unmodifiable(asset),
      List<double>.unmodifiable(market),
    ));
  }

  /// Quantidade de pares.
  int get length => asset.length;

  /// `true` quando nenhum par sobreviveu ao pareamento.
  bool get isEmpty => asset.isEmpty;
}

/// Acumulador de [PairedReturns], um par por vez.
///
/// É o caminho de quem produz as duas pontas no mesmo laço — o pareamento por
/// data, por exemplo. Acrescentar os dois números numa chamada só é o que
/// torna o desalinhamento **inexprimível**, em vez de detectável depois.
class PairedReturnsBuilder {
  final List<double> _asset = [];
  final List<double> _market = [];

  /// Acrescenta um par de retornos do mesmo período.
  void add({required double asset, required double market}) {
    _asset.add(asset);
    _market.add(market);
  }

  /// Fecha o acumulado. As listas são copiadas: alterar o construtor depois
  /// não afeta o par devolvido.
  PairedReturns build() => PairedReturns._(
        List<double>.unmodifiable(_asset),
        List<double>.unmodifiable(_market),
      );
}

/// Trajetória de patrimônio com os fluxos externos de cada período.
///
/// Mesma disciplina de [PairedReturns], para o par que alimenta TWR: o
/// patrimônio de cada período e o aporte que entrou nele viajam juntos. Antes
/// eram duas listas soltas — `Returns.timeWeighted` lançava `ArgumentError` se
/// divergissem (o único `throw` de validação num pacote que devolve [Result]),
/// e `Returns.timeWeightedIndex` nem isso: uma lista de fluxos mais curta
/// estourava com `RangeError` no meio da iteração.
class WealthPath {
  /// Patrimônio ao fim de cada período, em ordem cronológica.
  final List<double> values;

  /// Fluxo externo entrado em cada período, alinhado a [values].
  ///
  /// **Aporte é positivo aqui** — convenção oposta à de `CashFlow`, porque a
  /// fórmula do TWR subtrai o fluxo do valor final do período.
  final List<double> externalFlows;

  const WealthPath._(this.values, this.externalFlows);

  /// Trajetória vazia.
  static const WealthPath empty = WealthPath._([], []);

  /// Constrói a partir de duas séries prontas.
  ///
  /// Devolve [InvalidInput] quando os comprimentos divergem.
  static Result<WealthPath> of({
    required List<double> values,
    required List<double> externalFlows,
  }) {
    if (values.length != externalFlows.length) {
      return Err(InvalidInput(
        'Patrimônio e fluxos externos com tamanhos diferentes '
        '(${values.length} × ${externalFlows.length}).',
      ));
    }
    return Ok(WealthPath._(
      List<double>.unmodifiable(values),
      List<double>.unmodifiable(externalFlows),
    ));
  }

  /// Quantidade de períodos.
  int get length => values.length;

  /// `true` quando não há período algum.
  bool get isEmpty => values.isEmpty;
}

/// Acumulador de [WealthPath], um período por vez.
class WealthPathBuilder {
  final List<double> _values = [];
  final List<double> _flows = [];

  /// Fecha um período com o patrimônio apurado e o fluxo que entrou nele.
  void add({required double value, required double externalFlow}) {
    _values.add(value);
    _flows.add(externalFlow);
  }

  /// Patrimônio do último período fechado. Lança [StateError] se nenhum foi.
  double get last => _values.last;

  /// Quantos períodos já foram fechados.
  int get length => _values.length;

  /// Fecha o acumulado, copiando as listas.
  WealthPath build() => WealthPath._(
        List<double>.unmodifiable(_values),
        List<double>.unmodifiable(_flows),
      );
}
