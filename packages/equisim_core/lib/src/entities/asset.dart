import '../value_objects/ticker.dart';

/// Setor econômico conforme a taxonomia da fonte de dados.
///
/// Não é GICS nem a classificação setorial oficial da B3 — é a taxonomia
/// própria do provedor, em português. Deve ser declarado na metodologia.
class Sector implements Comparable<Sector> {
  /// Chave estável (ex.: `energia`), usada para agrupar.
  final String key;

  /// Rótulo de exibição (ex.: `Energia`).
  final String label;

  const Sector({required this.key, required this.label});

  factory Sector.fromKey(String key, {String? label}) =>
      Sector(key: key.trim().toLowerCase(), label: label ?? key.trim());

  static const Sector unknown = Sector(key: '', label: 'Não classificado');

  bool get isUnknown => key.isEmpty;

  @override
  int compareTo(Sector other) => label.compareTo(other.label);

  @override
  bool operator ==(Object other) => other is Sector && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => label;
}

/// Ação negociada na B3.
class Asset {
  final Ticker ticker;
  final String name;
  final Sector sector;
  final String? industry;

  const Asset({
    required this.ticker,
    required this.name,
    this.sector = Sector.unknown,
    this.industry,
  });

  @override
  bool operator ==(Object other) => other is Asset && other.ticker == ticker;

  @override
  int get hashCode => ticker.hashCode;

  @override
  String toString() => '${ticker.value} ($name)';
}
