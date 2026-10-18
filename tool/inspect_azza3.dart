import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';
import 'package:equisim/presentation/shared/domain_copy.dart';

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

    stdout.writeln('=== MARKET ANCHORS ===');
    stdout.writeln('CDI Corrente (Rf): ${anchors.currentRiskFreeRate}');
    stdout.writeln('CDI Estrutural (Rf_inf): ${anchors.riskFreeCagr}');
    stdout.writeln('IPCA: ${anchors.inflationCagr}');
    stdout.writeln('PIB Real: ${anchors.realEconomyGrowth}');
    stdout.writeln('Teto Nominal: ${anchors.nominalEconomyGrowth}');

    final auditEvents = <AuditEvent>[];
    AuditRecorder.attach(auditEvents.add);

    stdout.writeln('\n=== PREPARING VALUATION INPUTS FOR $tickerStr ===');
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
      stdout.writeln('FAILED to prepare inputs: ${prepResult.failureOrNull?.message}');
      return;
    }

    final inputs = prepResult.unwrap();
    stdout.writeln('Market Price: ${inputs.marketPrice}');
    stdout.writeln('Sector Key: ${inputs.sectorKey}');
    stdout.writeln('Industry: ${inputs.industry}');
    stdout.writeln('Beta: ${inputs.capm.beta} (${inputs.capm.betaSource})');
    stdout.writeln('Ke: ${inputs.capm.costOfEquity}');
    stdout.writeln('Fundamentals periods: ${inputs.fundamentals.length}');

    stdout.writeln('\n--- SNAPSHOTS DETAIL ---');
    for (final s in inputs.fundamentals) {
      final y = s.fiscalPeriodEnd.year;
      stdout.writeln('Year $y:');
      stdout.writeln('  NetIncome: ${s.netIncome}, EBIT: ${s.ebit}, EBITDA: ${s.ebitda}, NOPAT: ${s.nopat}, NOPAT_derived: ${s.nopatOrDerived}');
      stdout.writeln('  TotalDebt: ${s.totalDebt}, TotalCash: ${s.totalCash}, NetDebt: ${s.netDebt}');
      stdout.writeln('  SharesOut: ${s.sharesOutstanding}, SharesAsOf: ${s.sharesOutstandingAsOf}, Reconciled: ${s.reconciledShares}');
      stdout.writeln('  MarketCap: ${s.marketCap}, BVPS: ${s.bookValuePerShare}');
      stdout.writeln('  EquityBookValue (PL): ${s.equityBookValue}, InvestedCapital: ${s.investedCapital}');
    }

    stdout.writeln('\n--- CAPITAL SERIES VIA FIRM ---');
    final seriesFirm = CapitalSeries.build(inputs.fundamentals, ValuationLane.firm);
    stdout.writeln('Firm Points count: ${seriesFirm.points.length}');
    for (final p in seriesFirm.points) {
      stdout.writeln('  ${p.year}: base=${p.base}, profit=${p.profit}');
    }
    stdout.writeln('Annual Variations: ${seriesFirm.annualVariations}');
    stdout.writeln('Returns: ${seriesFirm.returns.map((r) => '${r.year}: ${(r.value * 100).toStringAsFixed(2)}%').toList()}');
    stdout.writeln('Retentions: ${seriesFirm.retentions.map((b) => '${(b * 100).toStringAsFixed(1)}%').toList()}');
    stdout.writeln('Latest Return: ${seriesFirm.latestReturn}');
    stdout.writeln('Cycle Return (w=8): ${seriesFirm.cycleReturn(window: ValuationParameters.cycleWindow)}');
    stdout.writeln('Median Retention: ${seriesFirm.medianRetention}');

    stdout.writeln('\n--- GUARDS EVALUATION ---');
    final trend = GrowthGuards.trend(seriesFirm);
    stdout.writeln('Trend: slope=${trend?.slope}, t=${trend?.tStatistic}, tc=${trend?.criticalT}, dominance=${trend?.dominance}, dominates=${trend?.dominates}');
    final phi = GrowthGuards.externalCapitalRatio(seriesFirm);
    stdout.writeln('Phi (external capital): $phi');
    final destoa = GrowthGuards.deviatesFromCycle(seriesFirm);
    stdout.writeln('Deviates from cycle: $destoa');
    final queda = GrowthGuards.recentOperationalDecline(inputs.fundamentals);
    stdout.writeln('Recent Operational Decline: $queda');
    final disp = GrowthGuards.dispersion(seriesFirm);
    stdout.writeln('Dispersion: isIdentified=${disp?.isIdentified}, gMed=${disp?.medianGrowth}, gReg=${disp?.regressionGrowth}, se=${disp?.stdError}, failure=${disp?.failure}');
    final fundable = GrowthGuards.anchorIsFundable(
      inflation: inputs.inflation,
      cycleReturn: seriesFirm.cycleReturn(window: ValuationParameters.cycleWindow),
      observedRetention: seriesFirm.medianRetention,
    );
    stdout.writeln('Anchor is fundable: $fundable');

    stdout.writeln('\n================ RESULTS SUMMARY ================');
    final evalResult = ValuationCascade.evaluate(inputs);
    if (evalResult.isErr) {
      stdout.writeln('EVALUATION 10y FAILED: ${evalResult.failureOrNull?.message}');
    } else {
      final res = evalResult.unwrap();
      stdout.writeln('10-YEAR PROJECTION (Cascade default):');
      stdout.writeln('  Model: ${res.model.rotulo}');
      stdout.writeln('  Fair Value: R\$ ${res.fairValue.reais.toStringAsFixed(2)}');
      stdout.writeln('  Market Price: R\$ ${res.marketPrice.reais.toStringAsFixed(2)}');
      stdout.writeln('  Upside: ${(res.upside * 100).toStringAsFixed(2)}%');
      stdout.writeln('  Discount Rate: ${(res.discountRate * 100).toStringAsFixed(2)}%');
      stdout.writeln('  Warnings:');
      for (final w in res.warnings) {
        stdout.writeln('    * $w');
      }
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
      stdout.writeln('EVALUATION 5y FAILED: ${evalResult5.failureOrNull?.message}');
    } else {
      final res5 = evalResult5.unwrap();
      stdout.writeln('\n5-YEAR PROJECTION (ValuationSettings in Flutter App UI!):');
      stdout.writeln('  Model: ${res5.model.rotulo}');
      stdout.writeln('  Fair Value: R\$ ${res5.fairValue.reais.toStringAsFixed(2)}');
      stdout.writeln('  Market Price: R\$ ${res5.marketPrice.reais.toStringAsFixed(2)}');
      stdout.writeln('  Upside: ${(res5.upside * 100).toStringAsFixed(2)}%');
      stdout.writeln('  Discount Rate: ${(res5.discountRate * 100).toStringAsFixed(2)}%');
      stdout.writeln('  Warnings:');
      for (final w in res5.warnings) {
        stdout.writeln('    * $w');
      }
    }

    stdout.writeln('\n=== AUDIT EVENTS LOG (${auditEvents.length} events) ===');
    for (final e in auditEvents) {
      stdout.writeln('EVENT endpoint: ${e.endpoint}');
      stdout.writeln('  outputPayload: ${e.outputPayload}');
      for (final c in e.calculations) {
        stdout.writeln('  CALC [${c.formulaName}]: finalValue=${c.finalValue} ${c.unit}');
        stdout.writeln('    vars: ${c.mappedVariables}');
        stdout.writeln('    steps: ${c.intermediateSteps}');
      }
    }
  } finally {
    AuditRecorder.detach();
    await ctx.dispose();
  }
}
