import '../../entities/asset.dart';
import '../../entities/portfolio.dart';

/// Concentração observada em um setor.
class SectorExposure {
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
  final List<SectorExposure> exposures;

  /// Setores que atingiram ou superaram o limiar de alerta.
  final List<SectorExposure> concentrated;

  /// Fração do peso da carteira sem classificação setorial.
  final double unclassifiedWeight;

  const ConcentrationReport({
    required this.exposures,
    required this.concentrated,
    required this.unclassifiedWeight,
  });

  bool get hasAlert => concentrated.isNotEmpty;
}

abstract final class SectorConcentration {
  /// A partir de dois ativos no mesmo setor, dispara alerta.
  static const int defaultThreshold = 2;

  /// Analisa a concentração setorial da carteira.
  ///
  /// O alerta é **informativo e não bloqueia a operação**: concentrar em um
  /// setor pode ser uma decisão deliberada do investidor. O papel do sistema é
  /// tornar o fato visível, não decidir por ele.
  static ConcentrationReport analyze(
    Portfolio portfolio, {
    int threshold = defaultThreshold,
  }) {
    final counts = <Sector, int>{};
    final weights = <Sector, double>{};
    var unclassified = 0.0;

    for (final entry in portfolio.entries.values) {
      final sector = entry.sector;
      if (sector.isUnknown) {
        unclassified += entry.weight.value;
        continue;
      }
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
      exposures: exposures,
      concentrated: exposures.where((e) => e.count >= threshold).toList(),
      unclassifiedWeight: unclassified,
    );
  }
}
