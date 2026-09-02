import 'package:equisim_core/equisim_core.dart';

/// Conversão entre o domínio e o formato de documento do Firestore.
///
/// Separado do repositório de propósito: serialização é lógica pura e merece
/// teste próprio, sem precisar de um Firestore de mentira. É onde moram as
/// decisões que preservam a integridade dos dados na ida e na volta.
abstract final class PortfolioStudyCodec {
  /// Serializa as posições de uma carteira.
  ///
  /// Grava apenas o que não é derivável: identidade, peso e rótulos. Setor e
  /// subsetor são **omitidos** quando ausentes, em vez de gravados como nulo,
  /// para que a volta os reconstrua como [Sector.unknown] sem ambiguidade.
  ///
  /// - [portfolio]: carteira a serializar.
  ///
  /// Retorna uma lista de documentos, um por posição. Identidade da carteira
  /// (`id`, `name`, `kind`) fica fora — é do documento que a contém.
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

  /// Reconstrói a carteira a partir do documento gravado.
  ///
  /// - [raw]: valor cru do campo de posições. Aceita qualquer coisa.
  /// - [id], [name], [kind]: identidade, que vem do documento que as contém.
  ///
  /// **Tolerante e silencioso**: entradas que não sejam mapa, com ticker
  /// inválido ou sem peso são **descartadas**, e um [raw] que não seja lista
  /// devolve carteira vazia. Nunca lança.
  ///
  /// A consequência é que uma carteira gravada com dado corrompido volta menor
  /// do que foi salva, sem pesos somando 100% — `Portfolio.hasValidWeights`
  /// passa a ser `false`, e é por esse caminho que a inconsistência aparece,
  /// não por exceção aqui.
  ///
  /// Pesos são travados em `[0, 1]` na volta, o que impede
  /// [Weight.fraction] de lançar sobre valor corrompido.
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

  /// Reconstrói a meta a partir do documento gravado.
  ///
  /// - [raw]: valor cru do campo de meta.
  ///
  /// Devolve `null` quando [raw] não é mapa ou não traz `months` — o prazo é o
  /// único campo sem padrão defensável. Valores monetários ausentes voltam como
  /// zero, o que produz uma meta que `RequiredReturnSolver.solve` recusa com
  /// [InvalidInput], em vez de uma meta silenciosamente errada.
  ///
  /// **Usa `FinancialGoal.unvalidated` de propósito.** O documento pode ter
  /// sido gravado antes de `FinancialGoal.create` existir, e recusar a leitura
  /// aqui apagaria da tela um estudo que o usuário salvou. O plano defeituoso
  /// atravessa e é recusado no ponto em que vira número, com o motivo à vista.
  static FinancialGoal? decodeGoal(dynamic raw) {
    if (raw is! Map) return null;
    final months = (raw['months'] as num?)?.toInt();
    if (months == null) return null;
    return FinancialGoal.unvalidated(
      initialContribution: Money((raw['initialCents'] as num?)?.toInt() ?? 0),
      monthlyContribution: Money((raw['monthlyCents'] as num?)?.toInt() ?? 0),
      months: months,
      targetWealth: Money((raw['targetCents'] as num?)?.toInt() ?? 0),
    );
  }
}
