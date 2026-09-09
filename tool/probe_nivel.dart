// De onde vem o nível: decompõe os motores do preço justo no universo.
import 'dart:convert';
import 'dart:io';
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main() async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime.utc(2026, 9, 9);
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: today,
    )).getOrElse(MarketAnchors.fallback2026);
    stdout.writeln('Rf corrente=${(anchors.currentRiskFreeRate*100).toStringAsFixed(2)}%  '
        'Rf estrutural=${(anchors.riskFreeCagr*100).toStringAsFixed(2)}%  '
        'IPCA=${(anchors.inflationCagr*100).toStringAsFixed(2)}%  '
        'teto nominal g=${(anchors.nominalEconomyGrowth*100).toStringAsFixed(2)}%');

    final universe = (await ctx.fundamentals.universe()).unwrap();
    final linhas = <Map<String, dynamic>>[];
    var n = 0;
    for (final t in universe) {
      if (++n % 25 == 0) stdout.write('  $n/${universe.length}\r');
      final prep = await PrepareValuationInputs.call(
        ticker: t, prices: ctx.prices, fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark, riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today, perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr, projectionYears: 10);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final r = ValuationCascade.evaluate(inputs);
      if (r.isErr) continue;
      final v = r.unwrap();
      final d = v.diagnostics;
      linhas.add({
        'ticker': t.value,
        'razao': v.marketPrice.reais > 0 ? v.fairValue.reais / v.marketPrice.reais : null,
        'potencial': v.upside,
        'crescimentoIdentificado': d?.growthIdentified,
        'ressalvas': d?.caveats.map((c) => c.name).toList(),
        'pesoTerminal': d?.terminalShare,
        'fatorBase': d?.baseFactor,
        'desconto': v.discountRate,
        'beta': inputs.capm.beta,
        'moat': d?.moatApplied,
      });
    }
    stdout.writeln('');
    File('docs/validacao/nivel.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(linhas));
    stdout.writeln('Gravado: docs/validacao/nivel.json (${linhas.length})');
  } finally { await ctx.dispose(); }
}
