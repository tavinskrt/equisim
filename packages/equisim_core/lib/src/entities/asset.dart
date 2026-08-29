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

  /// Declara o setor sem normalizar. Prefira [Sector.fromKey], que padroniza
  /// a chave.
  const Sector({required this.key, required this.label});

  /// Normaliza a chave para minúsculas sem espaços nas pontas.
  ///
  /// - [key]: chave bruta vinda da fonte.
  /// - [label]: rótulo de exibição. Sem ele, usa a chave original aparada —
  ///   preservando as maiúsculas que a chave normalizada perdeu.
  factory Sector.fromKey(String key, {String? label}) =>
      Sector(key: key.trim().toLowerCase(), label: label ?? key.trim());

  /// Setor ausente. Ativos assim entram na carteira mas ficam **fora** da
  /// análise de concentração, contabilizados em
  /// `ConcentrationReport.unclassifiedWeight`.
  static const Sector unknown = Sector(key: '', label: 'Não classificado');

  /// `true` para [Sector.unknown] e para qualquer setor de chave vazia.
  bool get isUnknown => key.isEmpty;

  /// Ordena por [label] — ordem de exibição —, enquanto [operator ==] compara
  /// por [key]. Dois setores de mesma chave e rótulos diferentes são iguais
  /// mas ordenam distinto; na prática a chave determina o rótulo.
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
///
/// **Identidade é o ticker.** Dois `Asset` com o mesmo ticker são o mesmo
/// ativo, ainda que nome e setor divirjam — o que permite substituir um ativo
/// sem perfil por um com perfil sem invalidar a carteira que o contém.
class Asset {
  /// Código de negociação. Identidade da entidade.
  final Ticker ticker;

  /// Razão social ou nome de pregão, como a fonte informa.
  final String name;

  /// Setor econômico. Padrão [Sector.unknown] quando o perfil não pôde ser
  /// resolvido — o ativo participa da carteira, mas não do alerta de
  /// concentração.
  final Sector sector;

  /// Subsetor, quando a fonte o informa. Não participa de cálculo algum.
  final String? industry;

  /// Declara o ativo. Só [ticker] e [name] são obrigatórios.
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
