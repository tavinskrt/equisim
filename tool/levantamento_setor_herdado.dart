// Mede o efeito da correção proposta pela lente `rumo`: quando o perfil vem
// nulo (papéis PN e unit), herdar setor e subsetor do ticker ON da mesma raiz.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

String raiz(String t) => t.replaceAll(RegExp(r'(3|4|5|6|10|11)$'), '');

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime(2026, 9, 9);
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: today,
    )).getOrElse(MarketAnchors.fallback2026);

    final universe = (await ctx.fundamentals.universe()).unwrap();
    final linhas = <Map<String, dynamic>>[];
    var n = 0;

    for (final ticker in universe) {
      if (++n % 25 == 0) stdout.write('  $n / ${universe.length}\r');

      final prep = await PrepareValuationInputs.call(
        ticker: ticker, prices: ctx.prices, fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark, riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today, perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr, projectionYears: 10,
      );
      if (prep.isErr) continue;
      var inputs = prep.unwrap();
      if (inputs.sectorKey != null && inputs.sectorKey!.isNotEmpty) continue;

      // Herda do ON da mesma raiz.
      final on = Ticker.parse('${raiz(ticker.value)}3');
      final perfilOn = await ctx.fundamentals.profile(on);
      final herdadoSetor =
          perfilOn.isOk ? perfilOn.unwrap().sector.key.toLowerCase() : null;
      final herdadaIndustria = perfilOn.isOk ? perfilOn.unwrap().industry : null;

      final antes = ValuationCascade.evaluate(inputs);
      final depois = ValuationCascade.evaluate(ValuationInputs(
        ticker: inputs.ticker, asOf: inputs.asOf,
        fundamentals: inputs.fundamentals, marketPrice: inputs.marketPrice,
        capm: inputs.capm, marginOfSafety: inputs.marginOfSafety,
        projectionYears: inputs.projectionYears,
        perpetualGrowthCap: inputs.perpetualGrowthCap,
        sectorKey: herdadoSetor, industry: herdadaIndustria,
        inflation: inputs.inflation,
        declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
        prices: inputs.prices, isDistressed: inputs.isDistressed,
      ));

      linhas.add({
        'ticker': ticker.value,
        'on': on.value,
        'setorHerdado': herdadoSetor,
        'industriaHerdada': herdadaIndustria,
        'antes': antes.isOk
            ? {'via': antes.unwrap().model.label, 'justo': antes.unwrap().fairValue.reais,
               'potencial': antes.unwrap().upside,
               'fator': antes.unwrap().diagnostics?.baseFactor}
            : {'recusa': antes.failureOrNull?.message},
        'depois': depois.isOk
            ? {'via': depois.unwrap().model.label, 'justo': depois.unwrap().fairValue.reais,
               'potencial': depois.unwrap().upside,
               'fator': depois.unwrap().diagnostics?.baseFactor}
            : {'recusa': depois.failureOrNull?.message},
      });
    }
    stdout.writeln('');
    File('docs/validacao/setor_herdado.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(linhas));
    stdout.writeln('Gravado: docs/validacao/setor_herdado.json (${linhas.length} afetados)');
  } finally {
    await ctx.dispose();
  }
}
