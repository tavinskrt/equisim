/// Resolve o prior transversal do beta a partir do universo.
library;

import '../repositories/repositories.dart';
import '../services/b3/cash_dividends.dart';
import '../services/metrics/beta.dart';
import '../services/metrics/beta_shrinkage.dart';
import '../services/metrics/market_leverage.dart';
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

  /// Dívida **líquida** sobre valor de mercado do capital próprio.
  ///
  /// A mesma régua da realavancagem e dos pesos do WACC (decisões 54 e 104).
  /// Este comentário dizia "bruta" e o chamador sempre passou a líquida —
  /// `FundamentalsSnapshot.debtToMarketEquity` —, o que fazia o registro
  /// descrever um motor que não existe.
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
    final unleveredBetas = <String?, List<double>>{};
    final allUnlevered = <double>[];
    final allLevered = <double>[];

    for (final o in observations) {
      if (!o.leveredBeta.isFinite) continue;
      allLevered.add(o.leveredBeta);
      final u = BetaShrinkage.unlever(
        leveredBeta: o.leveredBeta,
        debtToEquity: o.debtToEquity,
        taxRate: o.taxRate,
      );
      if (u == null || !u.isFinite) continue;
      allUnlevered.add(u);
      final k = o.sectorKey?.trim();
      (unleveredBetas[(k == null || k.isEmpty) ? null : k] ??= []).add(u);
    }

    final universe = Inference.median(allUnlevered);
    if (universe == null || !universe.isFinite) return null;

    final bySector = <String, double>{};
    for (final e in unleveredBetas.entries) {
      final k = e.key;
      if (k == null || e.value.length < minimumPeers) continue;
      final m = Inference.median(e.value);
      if (m != null && m.isFinite) bySector[k] = m;
    }

    // Dispersão do prior: robusta, sobre os betas **alavancados**, que é a
    // escala em que o encolhimento compara precisões. Recuo para 0,5 quando a
    // amostra colapsa — valor próximo do medido (0,53) e conservador, porque
    // dispersão maior dá mais peso ao estimador individual.
    final dispersion = Inference.scaledMad(allLevered);

    return BetaPrior(
      unleveredBySector: Map.unmodifiable(bySector),
      unleveredUniverse: universe,
      dispersion:
          (dispersion != null && dispersion.isFinite && dispersion > 0)
              ? dispersion
              : 0.5,
    );
  }

  /// Varre o universo e devolve o prior. Vai à rede.
  ///
  /// - [tickers]: universo a percorrer.
  /// - [windowYears]: janela do beta, alinhada com `PrepareValuationInputs`.
  /// - [dividendsFor]: proventos da classe de cada ativo. Presente, o beta de
  ///   cada observação sai do retorno total, como em `PrepareValuationInputs`
  ///   (decisão 89) — o prior e o beta que ele encolhe precisam da mesma régua.
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
    List<CashDividend> Function(Ticker)? dividendsFor,
  }) async {
    final window = DateRange(
      DateTime(asOf.year - windowYears, asOf.month, asOf.day),
      asOf,
    );
    final indexResult = await benchmark.ibovespa(window);
    if (indexResult.isErr) return null;
    final index = indexResult.unwrap();
    final view = PointInTimeView(asOf);

    final observations = <BetaObservation>[];
    for (final t in tickers) {
      final seriesResult = await prices.daily(t, window);
      if (seriesResult.isErr) continue;
      final points = seriesResult
          .unwrap()
          .points
          .where((p) => window.contains(p.date))
          .toList();
      if (points.length < 2) continue;

      final dates = [for (final p in points) p.date];
      final closes = [for (final p in points) p.close];
      final dividends = dividendsFor?.call(t);
      final estimate = BetaCalculator.estimate(
        returns: BetaCalculator.alignReturns(
          assetDates: dates,
          assetIndex: dividends == null || dividends.isEmpty
              ? closes
              : TotalReturnIndex.build(
                      dates: dates, closes: closes, dividends: dividends)
                  .index,
          marketDates: index.dates,
          marketIndex: index.points.map((p) => p.close).toList(),
        ),
      );
      if (estimate.isErr) continue;

      final historyResult = await fundamentals.history(t);
      if (historyResult.isErr) continue;
      final pub = view.published(historyResult.unwrap());
      if (pub.isEmpty) continue;
      final last = pub.last;
      final equity = last.marketCap;
      if (equity == null || equity <= 0) continue;

      final profile = await fundamentals.profile(t);
      final key = profile.isOk ? profile.unwrap().sector.key.trim() : '';

      observations.add(BetaObservation(
        leveredBeta: estimate.unwrap().beta,
        sectorKey: key.isEmpty ? null : key,
        // A mesma régua de [PrepareValuationInputs]: dívida líquida, medida na
        // janela em que o beta foi estimado. O prior é mediana de betas
        // desalavancados, e desalavancá-los por uma régua e realavancá-los por
        // outra desloca o setor inteiro. Ver [MarketLeverage.overWindow] e
        // [FundamentalsSnapshot.debtToMarketEquity].
        debtToEquity: MarketLeverage.overWindow(
              snapshots: pub,
              prices: points,
              window: window,
            ) ??
            last.debtToMarketEquity(equity) ??
            0.0,
        // A estatutária, pela mesma razão de [PrepareValuationInputs]: o
        // `(1 − τ)` de Hamada é escudo fiscal do juro, e a realavancagem o usa
        // cheio (decisão 55).
        taxRate: ValuationParameters.statutoryTaxRate,
      ));
    }

    return fromObservations(observations);
  }
}
