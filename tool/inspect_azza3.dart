import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main(List<String> args) async {
  final tickerStr = args.isNotEmpty ? args.first : 'AZZA3';
  final ticker = Ticker.parse(tickerStr);
  final ctx = ValidationContext.create(outputDir: 'docs/validacao', verbose: false);

  try {
    final today = DateTime(2026, 9, 4);
    final anchorsResult = await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    );
    final anchors = anchorsResult.getOrElse(MarketAnchors.fallback2026);

    print('=== MARKET ANCHORS ===');
    print('CDI Corrente (Rf): ${anchors.currentRiskFreeRate}');
    print('CDI Estrutural (Rf_inf): ${anchors.riskFreeCagr}');
    print('IPCA: ${anchors.inflationCagr}');
    print('PIB Real: ${anchors.realEconomyGrowth}');
    print('Teto Nominal: ${anchors.nominalEconomyGrowth}');

    final auditEvents = <AuditEvent>[];
    AuditRecorder.attach((e) => auditEvents.add(e));

    print('\n=== PREPARING VALUATION INPUTS FOR $tickerStr ===');
    final prepResult = await PrepareValuationInputs.call(
      ticker: ticker,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      riskFreeRate: anchors.currentRiskFreeRate,
      asOf: today,
      perpetualGrowthCap: anchors.nominalEconomyGrowth,
      inflation: anchors.inflationCagr,
      terminalRiskFreeRate: anchors.riskFreeCagr,
    );

    if (prepResult.isErr) {
      print('FAILED to prepare inputs: ${prepResult.failureOrNull?.message}');
      return;
    }

    final inputs = prepResult.unwrap();
    print('Market Price: ${inputs.marketPrice}');
    print('Sector Key: ${inputs.sectorKey}');
    print('Industry: ${inputs.industry}');
    print('Beta: ${inputs.capm.beta} (${inputs.capm.betaSource})');
    print('Ke: ${inputs.capm.costOfEquity}');
    print('Fundamentals periods: ${inputs.fundamentals.length}');

    print('\n--- SNAPSHOTS DETAIL ---');
    for (final s in inputs.fundamentals) {
      final y = s.fiscalPeriodEnd.year;
      print('Year $y:');
      print('  NetIncome: ${s.netIncome}, EBIT: ${s.ebit}, EBITDA: ${s.ebitda}, NOPAT: ${s.nopat}, NOPAT_derived: ${s.nopatOrDerived}');
      print('  TotalDebt: ${s.totalDebt}, TotalCash: ${s.totalCash}, NetDebt: ${s.netDebt}');
      print('  SharesOut: ${s.sharesOutstanding}, SharesAsOf: ${s.sharesOutstandingAsOf}, Reconciled: ${s.reconciledShares}');
      print('  MarketCap: ${s.marketCap}, BVPS: ${s.bookValuePerShare}');
      print('  EquityBookValue (PL): ${s.equityBookValue}, InvestedCapital: ${s.investedCapital}');
    }

    print('\n--- CAPITAL SERIES VIA FIRM ---');
    final seriesFirm = CapitalSeries.build(inputs.fundamentals, ValuationLane.firm);
    print('Firm Points count: ${seriesFirm.points.length}');
    for (final p in seriesFirm.points) {
      print('  ${p.year}: base=${p.base}, profit=${p.profit}');
    }
    print('Annual Variations: ${seriesFirm.annualVariations}');
    print('Returns: ${seriesFirm.returns.map((r) => '${r.year}: ${(r.value * 100).toStringAsFixed(2)}%').toList()}');
    print('Retentions: ${seriesFirm.retentions.map((b) => (b * 100).toStringAsFixed(1) + '%').toList()}');
    print('Latest Return: ${seriesFirm.latestReturn}');
    print('Cycle Return (w=8): ${seriesFirm.cycleReturn(window: ValuationParameters.cycleWindow)}');
    print('Median Retention: ${seriesFirm.medianRetention}');

    print('\n--- GUARDS EVALUATION ---');
    final trend = GrowthGuards.trend(seriesFirm);
    print('Trend: slope=${trend?.slope}, t=${trend?.tStatistic}, tc=${trend?.criticalT}, dominance=${trend?.dominance}, dominates=${trend?.dominates}');
    final phi = GrowthGuards.externalCapitalRatio(seriesFirm);
    print('Phi (external capital): $phi');
    final destoa = GrowthGuards.deviatesFromCycle(seriesFirm);
    print('Deviates from cycle: $destoa');
    final queda = GrowthGuards.recentOperationalDecline(inputs.fundamentals);
    print('Recent Operational Decline: $queda');
    final disp = GrowthGuards.dispersion(seriesFirm);
    print('Dispersion: isIdentified=${disp?.isIdentified}, gMed=${disp?.medianGrowth}, gReg=${disp?.regressionGrowth}, se=${disp?.stdError}, failure=${disp?.failure}');
    final fundable = GrowthGuards.anchorIsFundable(
      inflation: inputs.inflation,
      cycleReturn: seriesFirm.cycleReturn(window: ValuationParameters.cycleWindow),
      observedRetention: seriesFirm.medianRetention,
    );
    print('Anchor is fundable: $fundable');

    print('\n================ RESULTS SUMMARY ================');
    final evalResult = ValuationCascade.evaluate(inputs);
    if (evalResult.isErr) {
      print('EVALUATION 10y FAILED: ${evalResult.failureOrNull?.message}');
    } else {
      final res = evalResult.unwrap();
      print('10-YEAR PROJECTION (Cascade default):');
      print('  Model: ${res.model.label}');
      print('  Fair Value: R\$ ${res.fairValue.reais.toStringAsFixed(2)}');
      print('  Market Price: R\$ ${res.marketPrice.reais.toStringAsFixed(2)}');
      print('  Upside: ${(res.upside * 100).toStringAsFixed(2)}%');
      print('  Discount Rate: ${(res.discountRate * 100).toStringAsFixed(2)}%');
      print('  Warnings:');
      for (final w in res.warnings) print('    * $w');
    }

    final inputs5 = ValuationInputs(
      ticker: inputs.ticker,
      asOf: inputs.asOf,
      fundamentals: inputs.fundamentals,
      marketPrice: inputs.marketPrice,
      capm: inputs.capm,
      marginOfSafety: inputs.marginOfSafety,
      projectionYears: 5,
      perpetualGrowthCap: inputs.perpetualGrowthCap,
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
      inflation: inputs.inflation,
      declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
      prices: inputs.prices,
      isDistressed: inputs.isDistressed,
    );
    final evalResult5 = ValuationCascade.evaluate(inputs5);
    if (evalResult5.isErr) {
      print('EVALUATION 5y FAILED: ${evalResult5.failureOrNull?.message}');
    } else {
      final res5 = evalResult5.unwrap();
      print('\n5-YEAR PROJECTION (ValuationSettings in Flutter App UI!):');
      print('  Model: ${res5.model.label}');
      print('  Fair Value: R\$ ${res5.fairValue.reais.toStringAsFixed(2)}');
      print('  Market Price: R\$ ${res5.marketPrice.reais.toStringAsFixed(2)}');
      print('  Upside: ${(res5.upside * 100).toStringAsFixed(2)}%');
      print('  Discount Rate: ${(res5.discountRate * 100).toStringAsFixed(2)}%');
      print('  Warnings:');
      for (final w in res5.warnings) print('    * $w');
    }

    print('\n=== AUDIT EVENTS LOG (${auditEvents.length} events) ===');
    for (final e in auditEvents) {
      print('EVENT endpoint: ${e.endpoint}');
      print('  outputPayload: ${e.outputPayload}');
      for (final c in e.calculations) {
        print('  CALC [${c.formulaName}]: finalValue=${c.finalValue} ${c.unit}');
        print('    vars: ${c.mappedVariables}');
        print('    steps: ${c.intermediateSteps}');
      }
    }
  } finally {
    AuditRecorder.detach();
    await ctx.dispose();
  }
}
