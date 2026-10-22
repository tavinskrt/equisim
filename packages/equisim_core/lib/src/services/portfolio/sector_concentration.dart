import '../../entities/asset.dart';
import '../../entities/portfolio.dart';

/// Concentração observada em um setor.
class SectorExposure {
  /// Setor observado. Nunca é [Sector.unknown] — não classificados ficam fora
  /// da contagem de concentração.
  final Sector sector;

  /// Quantidade de ativos da carteira no setor.
  final int count;

  /// Soma dos pesos dos ativos do setor, em fração.
  final double weight;

  const SectorExposure({
    required this.sector,
    required this.count,
    required this.weight,
  });
}

/// Resultado da análise de concentração setorial.
class ConcentrationReport {
  /// Setores que atingiram ou superaram o limiar de alerta.
  final List<SectorExposure> concentrated;

  const ConcentrationReport({
    required this.concentrated,
  });

  /// `true` quando ao menos um setor atingiu o limiar. **Informativo**: não
  /// bloqueia operação alguma.
  bool get hasAlert => concentrated.isNotEmpty;
}

/// Analisa a distribuição setorial de uma carteira.
abstract final class SectorConcentration {
  /// A partir de dois ativos no mesmo setor, dispara alerta.
  static const int defaultThreshold = 2;

  /// Analisa a concentração setorial da carteira.
  ///
  /// O alerta é **informativo e não bloqueia a operação**: concentrar em um
  /// setor pode ser uma decisão deliberada do investidor. O papel do sistema é
  /// tornar o fato visível, não decidir por ele.
  ///
  /// - [portfolio]: carteira a analisar.
  /// - [threshold]: quantidade de ativos no mesmo setor a partir da qual o
  ///   alerta dispara. Padrão [defaultThreshold].
  ///
  /// O critério é **contagem de ativos, não soma de pesos**: dois ativos de
  /// 5% cada disparam, um único de 40% não. É deliberado — a concentração que
  /// interessa aqui é a de exposição a um mesmo choque setorial.
  ///
  /// Complexidade O(n log n), dominada pela ordenação das exposições.
  static ConcentrationReport analyze(
    Portfolio portfolio, {
    int threshold = defaultThreshold,
  }) {
    final counts = <Sector, int>{};
    final weights = <Sector, double>{};

    for (final entry in portfolio.entries.values) {
      final sector = entry.sector;
      if (sector.isUnknown) continue;
      counts[sector] = (counts[sector] ?? 0) + 1;
      weights[sector] = (weights[sector] ?? 0.0) + entry.weight.value;
    }

    final exposures = counts.entries
        .map((e) => SectorExposure(
              sector: e.key,
              count: e.value,
              weight: weights[e.key] ?? 0.0,
            ))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.weight.compareTo(a.weight);
      });

    return ConcentrationReport(
      concentrated: exposures.where((e) => e.count >= threshold).toList(),
    );
  }
}
