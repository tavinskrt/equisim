// Sensibilidade da distribuição de potencial ao prêmio de risco de mercado.
//
// O prêmio é o único insumo do CAPM que o motor **parametriza** em vez de
// medir, e as âncoras medem um valor bem diferente na mesma janela. Esta sonda
// mede quanto do nível da distribuição depende dessa escolha.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main() async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime(2026, 9, 4);
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    final medido = anchors.marketCagr - anchors.riskFreeCagr;
    final premios = <String, double>{
      'usado_5.50': CapmInputs.defaultMarketPremium,
      'medido': medido,
      'meio_4.00': 0.04,
      'damodaran_7.00': 0.07,
    };
    stderr.writeln('prêmio medido na janela: '
        '${(medido * 100).toStringAsFixed(2)} p.p.');

    final universe = (await ctx.fundamentals.universe()).unwrap();
    final out = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}\r');
      final prep = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      );
      if (prep.isErr) continue;
      final base = prep.unwrap();
      final linha = <String, dynamic>{
        'ticker': ticker.value,
        'beta': base.capm.beta,
      };
      for (final e in premios.entries) {
        final v = ValuationInputs(
          ticker: base.ticker,
          asOf: base.asOf,
          fundamentals: base.fundamentals,
          marketPrice: base.marketPrice,
          capm: CapmInputs(
            riskFreeRate: base.capm.riskFreeRate,
            beta: base.capm.beta,
            marketPremium: e.value,
            betaSource: base.capm.betaSource,
          ),
          projectionYears: 10,
          perpetualGrowthCap: base.perpetualGrowthCap,
          sectorKey: base.sectorKey,
          industry: base.industry,
          inflation: base.inflation,
          declaredTerminalRiskFreeRate: base.declaredTerminalRiskFreeRate,
          prices: base.prices,
          isDistressed: base.isDistressed,
        );
        final r = ValuationCascade.evaluate(v);
        linha[e.key] = r.isOk ? r.unwrap().upside : null;
      }
      out.add(linha);
    }
    File('docs/validacao/sensibilidade_premio.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    stderr.writeln('\nescrito docs/validacao/sensibilidade_premio.json');
  } finally {
    await ctx.dispose();
  }
}
