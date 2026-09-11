import '../failures/failure.dart';
import '../failures/result.dart';
import '../value_objects/ticker.dart';
import '../value_objects/weight.dart';
import 'asset.dart';

/// Papel da carteira na dupla gestão.
enum PortfolioKind {
  /// Portfólio vigente.
  principal('Principal'),

  /// Candidatos a substituição.
  reserva('Reserva');

  final String label;
  const PortfolioKind(this.label);
}

/// Posição de um ativo dentro da carteira.
///
/// A carteira é definida por **pesos**, não por lotes: o peso é o que o
/// usuário estipula, e a contagem de ações é resultado da simulação, não
/// entrada dela — `PortfolioBacktest` converte cada fatia de aporte em ações
/// inteiras ao preço do dia.
class PortfolioEntry {
  /// Ativo posicionado.
  final Asset asset;

  /// Peso **estipulado** na constituição, não o peso corrente de mercado. A
  /// deriva entre os dois é apurada pelo backtest, não guardada aqui.
  final Weight weight;

  /// Declara a posição.
  const PortfolioEntry({required this.asset, required this.weight});

  /// Atalho para `asset.ticker` — é por ele que a carteira indexa.
  Ticker get ticker => asset.ticker;

  /// Atalho para `asset.sector`, usado pela análise de concentração.
  Sector get sector => asset.sector;

  /// Devolve uma cópia com outro peso, preservando o ativo.
  ///
  /// A entrada é imutável; reequiponderar é reconstruir, não mutar.
  PortfolioEntry withWeight(Weight w) =>
      PortfolioEntry(asset: asset, weight: w);
}

/// Carteira de ações com pesos estipulados.
///
/// **Não há rebalanceamento**: os pesos definem a alocação de cada aporte, mas
/// nunca são restaurados depois. Os pesos correntes derivam com o mercado, e
/// essa deriva é informação útil — não defeito a corrigir.
class Portfolio {
  /// Identificador estável, usado para persistir e correlacionar.
  final String id;

  /// Nome de exibição, editável pelo usuário.
  final String name;

  /// Papel na dupla gestão: Principal ou Reserva.
  final PortfolioKind kind;

  /// Posições indexadas por ativo. **Imutável** — todo método de alteração
  /// devolve uma carteira nova.
  final Map<Ticker, PortfolioEntry> entries;

  /// Teto de ativos por carteira.
  ///
  /// **É regra de produto, e por isso mora aqui** (decisão 59). A ferramenta
  /// estuda carteira concentrada: acima de quinze ativos o alerta de
  /// concentração setorial deixa de discriminar e a comparação entre Principal
  /// e Reserva perde o sentido de "duas teses", que é o que a tela existe para
  /// confrontar.
  ///
  /// A lente `nucleo` a apontou como limite de interface vazado para o
  /// domínio, e a conferência mostrou o contrário: **a interface só exibe o
  /// contador**, e quem recusa o décimo sexto ativo são as fábricas daqui. Um
  /// teto que a apresentação apenas mostra e o domínio impõe é regra de
  /// domínio com justificativa mal escrita — o que mudou foi a justificativa.
  static const int maxAssets = 15;

  /// Constrói a carteira congelando o mapa de posições.
  ///
  /// **Não valida** teto de ativos nem soma de pesos — quem valida são as
  /// fábricas [Portfolio.equalWeighted] e [Portfolio.weighted], que devolvem
  /// [Result]. Este construtor é o caminho interno usado por elas e pelos
  /// métodos de alteração, que já sabem que o estado é consistente.
  Portfolio({
    required this.id,
    required this.name,
    required this.kind,
    required Map<Ticker, PortfolioEntry> entries,
  }) : entries = Map.unmodifiable(entries);

  /// `true` quando não há nenhum ativo.
  bool get isEmpty => entries.isEmpty;

  /// Quantidade de ativos. Limitada a [maxAssets] pelas fábricas.
  int get length => entries.length;

  /// Ativos em ordem alfabética.
  ///
  /// A ordenação é o que torna determinístico o resultado de [Weights.equal],
  /// que absorve o resíduo no primeiro elemento — sem ordem estável, o ativo
  /// que recebe o resíduo mudaria entre execuções.
  ///
  /// Constrói e ordena a cada chamada: O(n log n).
  List<Ticker> get tickers => entries.keys.toList()..sort();

  /// Pesos estipulados, em ordem de iteração do mapa.
  Iterable<Weight> get weights => entries.values.map((e) => e.weight);

  /// `true` quando os pesos somam 100% dentro da tolerância de
  /// [Weights.sumsToOne]. Uma carteira vazia é inválida por este critério.
  bool get hasValidWeights => Weights.sumsToOne(weights);

  /// Cria uma carteira equiponderada, validando o teto de ativos.
  ///
  /// - [id], [name], [kind]: identidade da carteira.
  /// - [assets]: ativos a incluir, sem duplicatas.
  ///
  /// Devolve [InvalidInput] para lista vazia, para mais de [maxAssets] ativos,
  /// ou quando dois ativos compartilham o mesmo ticker — a duplicata é barrada
  /// explicitamente porque o mapa a colapsaria em silêncio, produzindo uma
  /// carteira menor do que a pedida.
  static Result<Portfolio> equalWeighted({
    required String id,
    required String name,
    required PortfolioKind kind,
    required List<Asset> assets,
  }) {
    if (assets.isEmpty) {
      return const Err(InvalidInput('A carteira precisa de ao menos um ativo.'));
    }
    if (assets.length > maxAssets) {
      return Err(InvalidInput(
        'Limite de $maxAssets ativos por carteira excedido '
        '(${assets.length} informados).',
      ));
    }
    final duplicates = <Ticker>{};
    for (final a in assets) {
      if (!duplicates.add(a.ticker)) {
        return Err(InvalidInput('Ativo duplicado: ${a.ticker}'));
      }
    }

    final byTicker = {for (final a in assets) a.ticker: a};
    final weights = Weights.equal(assets.map((a) => a.ticker).toList());
    return Ok(Portfolio(
      id: id,
      name: name,
      kind: kind,
      entries: {
        for (final entry in weights.entries)
          entry.key: PortfolioEntry(
            asset: byTicker[entry.key]!,
            weight: entry.value,
          ),
      },
    ));
  }

  /// Cria com pesos customizados, exigindo soma igual a 100%.
  ///
  /// - [id], [name], [kind]: identidade da carteira.
  /// - [allocation]: peso em fração por ativo. Deve somar 1,0 com folga de
  ///   `1e-6`.
  ///
  /// Devolve [InvalidInput] para alocação vazia, acima de [maxAssets], ou com
  /// soma fora da tolerância — neste caso com `field: 'weights'`, para a
  /// interface destacar o campo certo.
  ///
  /// Ativos distintos com o mesmo ticker colapsam aqui **sem erro**, ao
  /// contrário de [Portfolio.equalWeighted]: o mapa é indexado por [Asset], e
  /// só a chave do resultado usa o ticker.
  static Result<Portfolio> weighted({
    required String id,
    required String name,
    required PortfolioKind kind,
    required Map<Asset, double> allocation,
  }) {
    if (allocation.isEmpty) {
      return const Err(InvalidInput('A carteira precisa de ao menos um ativo.'));
    }
    if (allocation.length > maxAssets) {
      return Err(InvalidInput(
        'Limite de $maxAssets ativos por carteira excedido.',
      ));
    }
    final total = allocation.values.fold<double>(0.0, (a, b) => a + b);
    if ((total - 1.0).abs() > 1e-6) {
      return Err(InvalidInput(
        'Os pesos devem somar 100%; somam ${(total * 100).toStringAsFixed(2)}%.',
        actual: total,
        field: 'weights',
      ));
    }
    return Ok(Portfolio(
      id: id,
      name: name,
      kind: kind,
      entries: {
        for (final e in allocation.entries)
          e.key.ticker:
              PortfolioEntry(asset: e.key, weight: Weight.fraction(e.value)),
      },
    ));
  }

  /// Redistribui os pesos igualmente entre os ativos atuais.
  ///
  /// Devolve uma carteira nova; a original permanece intacta. Sobre carteira
  /// vazia devolve uma cópia vazia.
  Portfolio equalize() {
    final weights = Weights.equal(tickers);
    return Portfolio(
      id: id,
      name: name,
      kind: kind,
      entries: {
        for (final entry in entries.entries)
          entry.key: entry.value.withWeight(weights[entry.key]!),
      },
    );
  }

  /// Remove um ativo e reequipondera o restante.
  ///
  /// - [ticker]: ativo a remover.
  ///
  /// Devolve [InvalidInput] se o ativo não estiver na carteira. Remover o
  /// último ativo devolve uma carteira **vazia**, não uma falha — quem chama
  /// decide se isso é aceitável no seu contexto.
  ///
  /// A reequiponderação **descarta os pesos customizados** dos ativos que
  /// ficam: todos voltam a ser iguais.
  Result<Portfolio> remove(Ticker ticker) {
    if (!entries.containsKey(ticker)) {
      return Err(InvalidInput('Ativo $ticker não está na carteira.'));
    }
    final remaining = Map<Ticker, PortfolioEntry>.from(entries)..remove(ticker);
    if (remaining.isEmpty) {
      return Ok(Portfolio(id: id, name: name, kind: kind, entries: const {}));
    }
    final weights = Weights.equal(remaining.keys.toList()..sort());
    return Ok(Portfolio(
      id: id,
      name: name,
      kind: kind,
      entries: {
        for (final entry in remaining.entries)
          entry.key: entry.value.withWeight(weights[entry.key]!),
      },
    ));
  }

  /// Adiciona um ativo e reequipondera.
  ///
  /// - [asset]: ativo a incluir.
  ///
  /// Devolve [InvalidInput] se o ativo já estiver presente ou se a carteira já
  /// tiver [maxAssets] ativos. Como [remove], **descarta pesos customizados**:
  /// a carteira resultante é equiponderada.
  Result<Portfolio> add(Asset asset) {
    if (entries.containsKey(asset.ticker)) {
      return Err(InvalidInput('${asset.ticker} já está na carteira.'));
    }
    if (entries.length >= maxAssets) {
      return Err(InvalidInput(
        'Limite de $maxAssets ativos por carteira atingido.',
      ));
    }
    final updated = Map<Ticker, PortfolioEntry>.from(entries);
    updated[asset.ticker] =
        PortfolioEntry(asset: asset, weight: Weight.zero);
    final weights = Weights.equal(updated.keys.toList()..sort());
    return Ok(Portfolio(
      id: id,
      name: name,
      kind: kind,
      entries: {
        for (final entry in updated.entries)
          entry.key: entry.value.withWeight(weights[entry.key]!),
      },
    ));
  }
}
