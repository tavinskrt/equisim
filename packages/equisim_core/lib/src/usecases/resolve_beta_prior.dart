/// Resolve o prior transversal do beta a partir do universo.
library;

import '../repositories/repositories.dart';
import '../services/metrics/beta.dart';
import '../services/metrics/beta_shrinkage.dart';
import '../services/valuation/capital_base.dart';
import '../services/valuation/growth_guards.dart';
import '../services/valuation/inference.dart';
import '../time/point_in_time_view.dart';
import '../value_objects/date_range.dart';
import '../value_objects/ticker.dart';

/// Um ativo já medido, para compor o prior.
///
/// É a entrada mínima do agregador, e existe para que ele seja **puro**: quem
/// vai à rede é o chamador, e a estatística transversal fica testável sem
/// nenhum repositório.
class BetaObservation {
  /// Beta observado na regressão.
  final double leveredBeta;

  /// Chave do setor, ou `null`.
  final String? sectorKey;

  /// Dívida bruta sobre valor de mercado do capital próprio.
  final double debtToEquity;

  /// Alíquota estrutural do ativo.
  final double taxRate;

  const BetaObservation({
    required this.leveredBeta,
    required this.sectorKey,
    required this.debtToEquity,
    required this.taxRate,
  });
}

/// Monta o [BetaPrior] do universo.
///
/// **Por que é um passo separado.** A cascata avalia um ativo por vez e é pura.
/// Mediana setorial e dispersão transversal só existem depois de varrer o
/// universo, e chegam como insumo — o mesmo arranjo de `ResolveMarketAnchors`.
abstract final class ResolveBetaPrior {
  /// Pares mínimos para a mediana de um setor ser usada.
  ///
  /// **Três, e é pouco de propósito.** O prior é usado com peso baixo — 0,98
  /// do estimador individual na mediana do universo —, de modo que exigir
  /// amostra grande apenas trocaria mediana setorial por mediana do universo
  /// sem mudar quase nada. O que importa é haver **algum** grupo, e a medição
  /// de 10/09/2026 mostra 14 setores com três ou mais e 95 dos 363 papéis sem.
  static const int minimumPeers = 3;

  /// Agrega observações já medidas num prior. **Puro.**
  ///
  /// Devolve `null` sem observação utilizável — caso em que o chamador segue
  /// com a regressão crua, que é o comportamento anterior.
  static BetaPrior? fromObservations(List<BetaObservation> observations) {
    final desalavancados = <String?, List<double>>{};
    final todosU = <double>[];
    final todosL = <double>[];

    for (final o in observations) {
      if (!o.leveredBeta.isFinite) continue;
      todosL.add(o.leveredBeta);
      final u = BetaShrinkage.unlever(
        leveredBeta: o.leveredBeta,
        debtToEquity: o.debtToEquity,
        taxRate: o.taxRate,
      );
      if (u == null || !u.isFinite) continue;
      todosU.add(u);
      final k = o.sectorKey?.trim();
      (desalavancados[(k == null || k.isEmpty) ? null : k] ??= []).add(u);
    }

    final universo = Inference.median(todosU);
    if (universo == null || !universo.isFinite) return null;

    final porSetor = <String, double>{};
    for (final e in desalavancados.entries) {
      final k = e.key;
      if (k == null || e.value.length < minimumPeers) continue;
      final m = Inference.median(e.value);
      if (m != null && m.isFinite) porSetor[k] = m;
    }

    // Dispersão do prior: robusta, sobre os betas **alavancados**, que é a
    // escala em que o encolhimento compara precisões. Recuo para 0,5 quando a
    // amostra colapsa — valor próximo do medido (0,53) e conservador, porque
    // dispersão maior dá mais peso ao estimador individual.
    final dispersao = Inference.scaledMad(todosL);

    return BetaPrior(
      unleveredBySector: Map.unmodifiable(porSetor),
      unleveredUniverse: universo,
      dispersion:
          (dispersao != null && dispersao.isFinite && dispersao > 0)
              ? dispersao
              : 0.5,
    );
  }

  /// Varre o universo e devolve o prior. Vai à rede.
  ///
  /// - [tickers]: universo a percorrer.
  /// - [windowYears]: janela do beta, alinhada com `PrepareValuationInputs`.
  ///
  /// Ativo que falhe em qualquer etapa é **pulado**, não interrompe: o prior é
  /// estatística de grupo, e um papel a menos não a invalida.
  static Future<BetaPrior?> call({
    required List<Ticker> tickers,
    required PriceRepository prices,
    required FundamentalsRepository fundamentals,
    required BenchmarkRepository benchmark,
    required DateTime asOf,
    int windowYears = 5,
  }) async {
    final janela = DateRange(
      DateTime(asOf.year - windowYears, asOf.month, asOf.day),
      asOf,
    );
    final indiceRes = await benchmark.ibovespa(janela);
    if (indiceRes.isErr) return null;
    final indice = indiceRes.unwrap();
    final view = PointInTimeView(asOf);

    final observacoes = <BetaObservation>[];
    for (final t in tickers) {
      final serieRes = await prices.daily(t, janela);
      if (serieRes.isErr) continue;
      final pontos = serieRes
          .unwrap()
          .points
          .where((p) => janela.contains(p.date))
          .toList();
      if (pontos.length < 2) continue;

      final estimativa = BetaCalculator.estimate(
        returns: BetaCalculator.alignReturns(
          assetDates: [for (final p in pontos) p.date],
          assetIndex: [for (final p in pontos) p.close],
          marketDates: indice.dates,
          marketIndex: indice.points.map((p) => p.close).toList(),
        ),
      );
      if (estimativa.isErr) continue;

      final histRes = await fundamentals.history(t);
      if (histRes.isErr) continue;
      final pub = view.published(histRes.unwrap());
      if (pub.isEmpty) continue;
      final ultimo = pub.last;
      final equity = ultimo.marketCap;
      if (equity == null || equity <= 0) continue;

      final perfil = await fundamentals.profile(t);
      final chave = perfil.isOk ? perfil.unwrap().sector.key.trim() : '';

      observacoes.add(BetaObservation(
        leveredBeta: estimativa.unwrap().beta,
        sectorKey: chave.isEmpty ? null : chave,
        debtToEquity: ultimo.totalDebt / equity,
        taxRate: CapitalSeries.structuralTaxRate(
              pub,
              statutoryRate: ValuationParameters.statutoryTaxRate,
            ) ??
            ValuationParameters.statutoryTaxRate,
      ));
    }

    return fromObservations(observacoes);
  }
}
