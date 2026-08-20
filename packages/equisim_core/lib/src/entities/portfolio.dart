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
/// A carteira é definida por **pesos**, não por lotes: o backtest normaliza em
/// base 100 e a alocação é percentual, de modo que contagem inteira de ações
/// não faz parte do modelo.
class PortfolioEntry {
  final Asset asset;
  final Weight weight;

  const PortfolioEntry({required this.asset, required this.weight});

  Ticker get ticker => asset.ticker;
  Sector get sector => asset.sector;

  PortfolioEntry withWeight(Weight w) =>
      PortfolioEntry(asset: asset, weight: w);
}

/// Carteira de ações com pesos estipulados.
///
/// **Não há rebalanceamento**: os pesos definem a alocação de cada aporte, mas
/// nunca são restaurados depois. Os pesos correntes derivam com o mercado, e
/// essa deriva é informação útil — não defeito a corrigir.
class Portfolio {
  final String id;
  final String name;
  final PortfolioKind kind;
  final Map<Ticker, PortfolioEntry> entries;

  /// Teto de ativos por carteira. Acima disso a interface de arrastar e soltar
  /// degrada e o alerta de concentração setorial perde utilidade prática.
  static const int maxAssets = 15;

  Portfolio({
    required this.id,
    required this.name,
    required this.kind,
    required Map<Ticker, PortfolioEntry> entries,
  }) : entries = Map.unmodifiable(entries);

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;
  List<Ticker> get tickers => entries.keys.toList()..sort();
  Iterable<Weight> get weights => entries.values.map((e) => e.weight);

  bool get hasValidWeights => Weights.sumsToOne(weights);

  /// Cria uma carteira equiponderada, validando o teto de ativos.
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
