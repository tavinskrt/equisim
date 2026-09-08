import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

class AssetAuditResult {
  final String ticker;
  final String? sector;
  final String? industry;
  final String outcome10;
  final String outcome5;
  final double? price;
  final double? fv10;
  final double? fv5;
  final double? upside10;
  final double? upside5;
  final String? lane10;
  final String? lane5;
  final double? factor10;
  final double? factor5;
  final double? currentRoic;
  final double? cycleRoic;
  final double? phi;
  final double? wacc10;
  final double? wacc5;
  final double? equityShare;
  final double? netDebt;
  final double? shares;
  final List<String> warnings10;
  final List<String> warnings5;

  AssetAuditResult({
    required this.ticker,
    this.sector,
    this.industry,
    required this.outcome10,
    required this.outcome5,
    this.price,
    this.fv10,
    this.fv5,
    this.upside10,
    this.upside5,
    this.lane10,
    this.lane5,
    this.factor10,
    this.factor5,
    this.currentRoic,
    this.cycleRoic,
    this.phi,
    this.wacc10,
    this.wacc5,
    this.equityShare,
    this.netDebt,
    this.shares,
    required this.warnings10,
    required this.warnings5,
  });
}

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao', verbose: false);
  final today = DateTime(2026, 9, 4);

  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    )).getOrElse(MarketAnchors.fallback2026);

    final universeRes = await ctx.fundamentals.universe();
    if (universeRes.isErr) {
      print('Failed to load universe: ${universeRes.failureOrNull?.message}');
      return;
    }

    final universe = universeRes.unwrap();
    print('Loaded universe of ${universe.length} tickers.');

    final results = <AssetAuditResult>[];

    var processed = 0;
    for (final ticker in universe) {
      processed++;
      if (processed % 25 == 0) {
        stdout.write('  Processed $processed / ${universe.length} tickers...\r');
      }

      // Prepare 10y
      final prep10 = await PrepareValuationInputs.call(
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

      if (prep10.isErr) {
        results.add(AssetAuditResult(
          ticker: ticker.value,
          outcome10: prep10.failureOrNull?.message ?? 'Preparation failed',
          outcome5: prep10.failureOrNull?.message ?? 'Preparation failed',
          warnings10: [],
          warnings5: [],
        ));
        continue;
      }

      final in10 = prep10.unwrap();
      final in5 = ValuationInputs(
        ticker: in10.ticker,
        asOf: in10.asOf,
        fundamentals: in10.fundamentals,
        marketPrice: in10.marketPrice,
        capm: in10.capm,
        marginOfSafety: in10.marginOfSafety,
        projectionYears: 5,
        perpetualGrowthCap: in10.perpetualGrowthCap,
        sectorKey: in10.sectorKey,
        industry: in10.industry,
        inflation: in10.inflation,
        declaredTerminalRiskFreeRate: in10.declaredTerminalRiskFreeRate,
        prices: in10.prices,
        isDistressed: in10.isDistressed,
      );

      final eval10 = ValuationCascade.evaluate(in10);
      final eval5 = ValuationCascade.evaluate(in5);

      final seriesFirm = CapitalSeries.build(in10.fundamentals, ValuationLane.firm);
      final currentRoic = seriesFirm.latestReturn;
      final cycleRoic = seriesFirm.cycleReturn(window: ValuationParameters.cycleWindow);
      final phi = GrowthGuards.externalCapitalRatio(seriesFirm);

      final latest = in10.fundamentals.isNotEmpty ? in10.fundamentals.last : null;

      double? parseFactor(List<String> ws) {
        for (final w in ws) {
          final m = RegExp(r'fator de ([0-9.]+)x').firstMatch(w);
          if (m != null) return double.tryParse(m.group(1)!);
        }
        return 1.0;
      }

      results.add(AssetAuditResult(
        ticker: ticker.value,
        sector: in10.sectorKey,
        industry: in10.industry,
        outcome10: eval10.isOk ? 'OK' : (eval10.failureOrNull?.message ?? 'Err'),
        outcome5: eval5.isOk ? 'OK' : (eval5.failureOrNull?.message ?? 'Err'),
        price: in10.marketPrice,
        fv10: eval10.isOk ? eval10.unwrap().fairValue.reais : null,
        fv5: eval5.isOk ? eval5.unwrap().fairValue.reais : null,
        upside10: eval10.isOk ? eval10.unwrap().upside : null,
        upside5: eval5.isOk ? eval5.unwrap().upside : null,
        lane10: eval10.isOk ? eval10.unwrap().model.label : null,
        lane5: eval5.isOk ? eval5.unwrap().model.label : null,
        factor10: eval10.isOk ? parseFactor(eval10.unwrap().warnings) : null,
        factor5: eval5.isOk ? parseFactor(eval5.unwrap().warnings) : null,
        currentRoic: currentRoic,
        cycleRoic: cycleRoic,
        phi: phi,
        wacc10: eval10.isOk ? eval10.unwrap().discountRate : null,
        wacc5: eval5.isOk ? eval5.unwrap().discountRate : null,
        equityShare: null,
        netDebt: latest?.netDebt,
        shares: latest?.reconciledShares,
        warnings10: eval10.isOk ? eval10.unwrap().warnings : [],
        warnings5: eval5.isOk ? eval5.unwrap().warnings : [],
      ));
    }

    print('\n\nProcessed ${results.length} tickers.');

    // Save JSON of all results for analysis
    final jsonList = results.map((r) => {
      'ticker': r.ticker,
      'sector': r.sector,
      'industry': r.industry,
      'outcome10': r.outcome10,
      'outcome5': r.outcome5,
      'price': r.price,
      'fv10': r.fv10,
      'fv5': r.fv5,
      'upside10': r.upside10,
      'upside5': r.upside5,
      'lane10': r.lane10,
      'lane5': r.lane5,
      'factor10': r.factor10,
      'factor5': r.factor5,
      'currentRoic': r.currentRoic,
      'cycleRoic': r.cycleRoic,
      'phi': r.phi,
      'wacc10': r.wacc10,
      'wacc5': r.wacc5,
      'netDebt': r.netDebt,
      'shares': r.shares,
      'warnings10': r.warnings10,
      'warnings5': r.warnings5,
    }).toList();

    File('docs/validacao/audit_universe_comparison.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonList));

    print('Wrote audit_universe_comparison.json');

  } finally {
    await ctx.dispose();
  }
}
