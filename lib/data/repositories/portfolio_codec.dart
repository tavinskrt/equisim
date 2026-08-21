import 'package:equisim_core/equisim_core.dart';

/// Conversão entre o domínio e o formato de documento do Firestore.
///
/// Separado do repositório de propósito: serialização é lógica pura e merece
/// teste próprio, sem precisar de um Firestore de mentira. É onde moram as
/// decisões que preservam a integridade dos dados na ida e na volta.
abstract final class PortfolioStudyCodec {
  static List<Map<String, dynamic>> encodePortfolio(Portfolio portfolio) => [
        for (final entry in portfolio.entries.values)
          {
            'ticker': entry.ticker.value,
            'weight': entry.weight.value,
            'name': entry.asset.name,
            if (!entry.sector.isUnknown) ...{
              'sectorKey': entry.sector.key,
              'sectorLabel': entry.sector.label,
            },
            if (entry.asset.industry != null) 'industry': entry.asset.industry,
          }
      ];

  static Portfolio decodePortfolio(
    dynamic raw, {
    required String id,
    required String name,
    required PortfolioKind kind,
  }) {
    final entries = <Ticker, PortfolioEntry>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final ticker = Ticker.tryParse((item['ticker'] as String?) ?? '');
        if (ticker == null) continue;
        final weight = (item['weight'] as num?)?.toDouble();
        if (weight == null) continue;
        final sectorKey = item['sectorKey'] as String?;
        entries[ticker] = PortfolioEntry(
          asset: Asset(
            ticker: ticker,
            name: (item['name'] as String?) ?? ticker.value,
            sector: sectorKey == null
                ? Sector.unknown
                : Sector.fromKey(
                    sectorKey,
                    label: (item['sectorLabel'] as String?) ?? sectorKey,
                  ),
            industry: item['industry'] as String?,
          ),
          weight: Weight.fraction(weight.clamp(0.0, 1.0)),
        );
      }
    }
    return Portfolio(id: id, name: name, kind: kind, entries: entries);
  }

  /// Valores monetários viajam em **centavos inteiros**, como no domínio.
  /// Serializar reais em ponto flutuante reintroduziria exatamente o erro de
  /// arredondamento que o tipo `Money` existe para eliminar.
  static Map<String, dynamic> encodeGoal(FinancialGoal goal) => {
        'initialCents': goal.initialContribution.cents,
        'monthlyCents': goal.monthlyContribution.cents,
        'months': goal.months,
        'targetCents': goal.targetWealth.cents,
      };

  static FinancialGoal? decodeGoal(dynamic raw) {
    if (raw is! Map) return null;
    final months = (raw['months'] as num?)?.toInt();
    if (months == null) return null;
    return FinancialGoal(
      initialContribution: Money((raw['initialCents'] as num?)?.toInt() ?? 0),
      monthlyContribution: Money((raw['monthlyCents'] as num?)?.toInt() ?? 0),
      months: months,
      targetWealth: Money((raw['targetCents'] as num?)?.toInt() ?? 0),
    );
  }
}
