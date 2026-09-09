// Mede quanto cada trava conservadora vale no NÍVEL mediano do universo.
//
// Uso: dart run tool/levantamento_travas.dart <trava>
//   base     nada alterado (controle)
//   premio   prêmio de risco 5,50 -> 2,83 p.p. (o ex post da decisão 32)
//   ancora   crescimento não identificado ancora no teto nominal, não na inflação
//   spot     desconto parte da Rf estrutural, sem decaimento a partir do CDI spot
//   teto     teto do crescimento perpétuo deixa de vincular
//   moat     (exige patch dos parâmetros de moat)
//   piso     (exige patch de baseFactorFloor)
import 'dart:convert';
import 'dart:io';
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main(List<String> args) async {
  final trava = args.isNotEmpty ? args.first : 'base';
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime.utc(2026, 9, 9);
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: today,
    )).getOrElse(MarketAnchors.fallback2026);

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
      final i = prep.unwrap();

      // Cada trava é uma variação de insumo sobre os mesmos fundamentos.
      final capm = (trava == 'premio' || trava == 'tudo')
          ? CapmInputs(
              riskFreeRate: trava == 'tudo'
                  ? anchors.riskFreeCagr
                  : i.capm.riskFreeRate,
              beta: i.capm.beta,
              marketPremium: 0.0283, betaSource: i.capm.betaSource,
              premiumSource: i.capm.premiumSource)
          : trava == 'spot'
              ? CapmInputs(
                  riskFreeRate: anchors.riskFreeCagr, beta: i.capm.beta,
                  marketPremium: i.capm.marketPremium,
                  betaSource: i.capm.betaSource,
                  premiumSource: i.capm.premiumSource)
              : i.capm;

      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: i.ticker, asOf: i.asOf, fundamentals: i.fundamentals,
        marketPrice: i.marketPrice, capm: capm,
        marginOfSafety: i.marginOfSafety, projectionYears: i.projectionYears,
        perpetualGrowthCap:
            trava == 'teto' ? 1.0 : i.perpetualGrowthCap,
        sectorKey: i.sectorKey, industry: i.industry,
        inflation: trava == 'ancora' ? anchors.nominalEconomyGrowth : i.inflation,
        declaredTerminalRiskFreeRate: i.declaredTerminalRiskFreeRate,
        prices: i.prices, isDistressed: i.isDistressed));
      if (r.isErr) continue;
      final v = r.unwrap();
      if (v.marketPrice.reais <= 0) continue;
      linhas.add({
        'ticker': t.value,
        'razao': v.fairValue.reais / v.marketPrice.reais,
        'potencial': v.upside,
      });
    }
    stdout.writeln('');
    File('docs/validacao/trava_$trava.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(linhas));
    stdout.writeln('trava=$trava  n=${linhas.length}');
  } finally { await ctx.dispose(); }
}
