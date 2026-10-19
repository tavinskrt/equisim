// O retorno esperado da carteira e a âncora que faltava.
//
// **O defeito.** `ExpectedReturn.crossSection` estimava
// `E[R_i] = CDI + z_i·prêmio`, com `z` sendo o potencial padronizado
// robustamente. O ativo **mediano** da seção recebia exatamente o CDI — de
// modo que uma carteira de ações centrada na seção esperava a renda fixa, e o
// prêmio de risco aparecia só como dispersão, nunca como nível.
//
// **A correção.** A âncora passa a ser o custo de capital próprio do ativo:
// `E[R_i] = Ke_i + z_i·prêmio`. O mediano recebe `Rf + β_i·prêmio`, que é o
// retorno esperado incondicional dele.
//
// Uso:
//   dart run tool/retorno_esperado.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(2)}%';

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final prior = await ResolveBetaPrior.call(
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: _today,
    );

    final valuations = <Ticker, ValuationResult>{};
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final prep = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
        betaPrior: prior,
      );
      if (prep.isErr) continue;
      final r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isOk) valuations[ticker] = r.unwrap();
    }
    stderr.writeln('');

    final upsides = {
      for (final e in valuations.entries) e.key: e.value.upside,
    };
    final kes = {
      for (final e in valuations.entries)
        if (e.value.diagnostics != null)
          e.key: e.value.diagnostics!.costOfEquity,
    };

    final withCdi = ExpectedReturn.crossSection(
      upsides: upsides,
      spotRiskFree: anchors.currentRiskFreeRate,
    );
    final withKe = ExpectedReturn.crossSection(
      upsides: upsides,
      spotRiskFree: anchors.currentRiskFreeRate,
      costOfEquity: kes,
    );

    final output = [
      for (final t in upsides.keys)
        {
          'ticker': t.value,
          'potencial': upsides[t],
          'custoDoCapitalProprio': kes[t],
          'esperadoNoCdi': withCdi[t]!.expected,
          'esperadoNoKe': withKe[t]!.expected,
          'z': withKe[t]!.z,
          'ancoradoNoKe': withKe[t]!.anchoredOnCostOfEquity,
          'pisado': withKe[t]!.floored,
        }
    ];
    File('docs/validacao/retorno_esperado.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );

    stdout.writeln('\n=== RETORNO ESPERADO TRANSVERSAL — '
        '${upsides.length} ativos ===\n');
    stdout.writeln('  CDI corrente: ${_pc(anchors.currentRiskFreeRate)}');
    final kesL = kes.values.toList();
    stdout.writeln('  custo do capital próprio: mediana='
        '${_pc(_median(kesL)!)}  n=${kesL.length}');

    for (final caseTicker in [
      ('âncora no CDI (antes)', 'esperadoNoCdi'),
      ('âncora no Ke (agora)', 'esperadoNoKe'),
    ]) {
      final v = [
        for (final e in output) (e[caseTicker.$2] as num).toDouble()
      ]..sort();
      stdout.writeln('  ${caseTicker.$1.padRight(24)} '
          'p10=${_pc(v[(v.length * 0.1).floor()])}  '
          'mediana=${_pc(_median(v)!)}  '
          'p90=${_pc(v[(v.length * 0.9).floor()])}');
    }

    final floored = output.where((e) => e['pisado'] == true).length;
    stdout.writeln('  pisados em zero: $floored');
    final withoutKe = output.where((e) => e['ancoradoNoKe'] != true).length;
    stdout.writeln('  sem Ke, ancorados no CDI: $withoutKe');

    // O que isso faz com uma carteira igualmente ponderada do universo.
    final cdiMean = [
      for (final e in output) (e['esperadoNoCdi'] as num).toDouble()
    ].reduce((a, b) => a + b) /
        output.length;
    final keMean = [
      for (final e in output) (e['esperadoNoKe'] as num).toDouble()
    ].reduce((a, b) => a + b) /
        output.length;
    stdout.writeln('\n-- carteira igualmente ponderada do universo --');
    stdout.writeln('  antes: ${_pc(cdiMean)}   agora: ${_pc(keMean)}   '
        'diferença: ${_pc(keMean - cdiMean)}');
    stdout.writeln('  o CDI é ${_pc(anchors.currentRiskFreeRate)}: antes a '
        'carteira de ações esperava '
        '${cdiMean < anchors.currentRiskFreeRate ? "MENOS" : "mais"} que a '
        'renda fixa');

    stderr.writeln('\nescrito docs/validacao/retorno_esperado.json');
  } finally {
    await ctx.dispose();
  }
}
