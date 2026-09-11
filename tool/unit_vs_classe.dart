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

final _hoje = DateTime(2026, 9, 4);

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: _hoje,
    )).getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();

    // Agrupa por raiz de quatro letras.
    final porRaiz = <String, List<Ticker>>{};
    for (final t in universe) {
      final raiz = t.value.length >= 4 ? t.value.substring(0, 4) : t.value;
      porRaiz.putIfAbsent(raiz, () => []).add(t);
    }
    final comUnit = {
      for (final e in porRaiz.entries)
        if (e.value.any((t) => t.value.endsWith('11')) && e.value.length > 1)
          e.key: e.value
    };

    final cache = <Ticker, double?>{};
    Future<double?> potencial(Ticker t) async {
      if (cache.containsKey(t)) return cache[t];
      final prep = await PrepareValuationInputs.call(
        ticker: t, prices: ctx.prices, fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark, riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _hoje, perpetualGrowthCap: anchors.nominalEconomyGrowth,
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

    stdout.writeln('== ${comUnit.length} raízes com unit e ao menos outra classe ==\n');
    var maiorGap = 0.0;
    String? pior;
    for (final raiz in comUnit.keys.toList()..sort()) {
      final tickers = comUnit[raiz]!..sort();
      final unit = tickers.firstWhere((t) => t.value.endsWith('11'));
      final pu = await potencial(unit);
      final linha = StringBuffer('  $raiz: ');
      for (final t in tickers) {
        final p = await potencial(t);
        linha.write('${t.value}=${p == null ? "—" : "${(p * 100).toStringAsFixed(1)}%"}  ');
      }
      if (pu != null) {
        for (final t in tickers) {
          if (t == unit) continue;
          final p = await potencial(t);
          if (p == null) continue;
          final gap = (p - pu).abs();
          if (gap > maiorGap) { maiorGap = gap; pior = '$raiz (${t.value} contra ${unit.value})'; }
        }
      }
      stdout.writeln(linha.toString().trimRight());
    }
    stdout.writeln('\n  maior distância unit↔classe: '
        '${(maiorGap * 100).toStringAsFixed(1)} p.p. em ${pior ?? "—"}');
  } finally { await ctx.dispose(); }
}
