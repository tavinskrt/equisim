import 'dart:io';
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: _hoje,
    )).getOrElse(MarketAnchors.fallback2026);
    for (final nome in ['SAPR11', 'BPAC11', 'KLBN11', 'SANB11', 'SAPR4']) {
      final ticker = Ticker.parse(nome);
      final prep = await PrepareValuationInputs.call(
        ticker: ticker, prices: ctx.prices, fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark, riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _hoje, perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr, projectionYears: 10,
      );
      if (prep.isErr) { stdout.writeln('$nome: ${prep.failureOrNull?.message}'); continue; }
      final inputs = prep.unwrap();
      final view = PointInTimeView(_hoje);
      final pub = view.published(inputs.fundamentals);
      final latest = pub.last;
      final u = ValuationCascade.quotedUnitRatio(
        sharesOutstanding: latest.sharesOutstanding,
        marketCap: latest.marketCap,
        marketPrice: inputs.marketPrice,
      );
      final q = ValuationCascade.quotedShares(
        latest: latest, marketPrice: inputs.marketPrice,
        sharesPerQuote: u, published: pub,
      );
      final r = ValuationCascade.evaluate(inputs);
      final res = r.isOk ? r.unwrap() : null;
      stdout.writeln('$nome  preço R\$ ${inputs.marketPrice.toStringAsFixed(2)}'
          '${res == null ? "  (recusado: ${r.failureOrNull?.message})" : "  justo R\$ ${res.fairValue}  potencial ${(res.upside * 100).toStringAsFixed(1)}%"}');
      stdout.writeln('   u=${u.toStringAsFixed(0)}  fonte=${q?.source.label}  '
          'N=${q?.count.toStringAsFixed(0)}  '
          'mercado=${q?.fromMarketCap?.toStringAsFixed(0)}  '
          'balanço=${q?.fromStatements?.toStringAsFixed(0)}  '
          'diverge=${q?.diverge}');
    }
  } finally { await ctx.dispose(); }
}
