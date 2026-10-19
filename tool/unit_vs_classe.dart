// A unit e a classe que a compõe têm de concordar.
//
// Uma unit é uma cesta de ações da mesma empresa. O potencial apurado para ela
// e o apurado para a classe que a compõe descrevem o mesmo negócio, e só podem
// divergir pelo ágio entre ON e PN dentro da cesta — nunca por uma ordem de
// grandeza. **É o teste que nenhuma peça isolada faz**: a razão de unidade só
// se verifica confrontando dois tickers.
//
// Uso:
//   dart run tool/unit_vs_classe.dart
import 'dart:io';
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: _today,
    )).getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();

    // Agrupa por raiz de quatro letras.
    final byRoot = <String, List<Ticker>>{};
    for (final t in universe) {
      final root = t.value.length >= 4 ? t.value.substring(0, 4) : t.value;
      byRoot.putIfAbsent(root, () => []).add(t);
    }
    final withUnit = {
      for (final e in byRoot.entries)
        if (e.value.any((t) => t.value.endsWith('11')) && e.value.length > 1)
          e.key: e.value
    };

    final cache = <Ticker, double?>{};
    Future<double?> upside(Ticker t) async {
      if (cache.containsKey(t)) return cache[t];
      final prep = await PrepareValuationInputs.call(
        ticker: t, prices: ctx.prices, fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark, riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _today, perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr, projectionYears: 10,
      );
      double? v;
      if (prep.isOk) {
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (r.isOk) v = r.unwrap().upside;
      }
      cache[t] = v;
      return v;
    }

    stdout.writeln('== ${withUnit.length} raízes com unit e ao menos outra classe ==\n');
    var largestGap = 0.0;
    String? worst;
    for (final root in withUnit.keys.toList()..sort()) {
      final tickers = withUnit[root]!..sort();
      final unit = tickers.firstWhere((t) => t.value.endsWith('11'));
      final unitUpside = await upside(unit);
      final row = StringBuffer('  $root: ');
      for (final t in tickers) {
        final p = await upside(t);
        row.write('${t.value}=${p == null ? "—" : "${(p * 100).toStringAsFixed(1)}%"}  ');
      }
      if (unitUpside != null) {
        for (final t in tickers) {
          if (t == unit) continue;
          final p = await upside(t);
          if (p == null) continue;
          final gap = (p - unitUpside).abs();
          if (gap > largestGap) { largestGap = gap; worst = '$root (${t.value} contra ${unit.value})'; }
        }
      }
      stdout.writeln(row.toString().trimRight());
    }
    stdout.writeln('\n  maior distância unit↔classe: '
        '${(largestGap * 100).toStringAsFixed(1)} p.p. em ${worst ?? "—"}');
  } finally { await ctx.dispose(); }
}
