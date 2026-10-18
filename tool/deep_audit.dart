// Diagnóstico profundo do motor de avaliação — instrumentação por ativo.
//
// Não altera o motor: lê os mesmos insumos que a cascata lê e expõe as
// grandezas intermediárias que o resultado não carrega, para que hipóteses de
// defeito sejam medidas em vez de supostas.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Map<String, dynamic> diagnose(ValuationInputs inputs) {
  final view = PointInTimeView(inputs.asOf);
  final pub = view.published(inputs.fundamentals);
  if (pub.isEmpty) return {'erro': 'sem exercicio publicado'};
  final latest = pub.last;

  final firmSeries = CapitalSeries.build(pub, ValuationLane.firm);
  final shareholderSeries = CapitalSeries.build(pub, ValuationLane.shareholder);

  // --- Contagem de ações: todas as fontes lado a lado ---
  final nCurrent = latest.sharesOutstanding;
  final nFiscalYear = latest.sharesOutstandingAsOf;
  final profit = latest.netIncome;
  final eps = latest.earningsPerShare;
  final nByEps =
      (profit != null && eps != null && eps.abs() > 1e-9) ? profit / eps : null;
  final nByMarket = (latest.marketCap != null && inputs.marketPrice > 0)
      ? latest.marketCap! / inputs.marketPrice
      : null;

  // --- Retornos: com e sem os exercícios de prejuízo ---
  // A série `returns` do núcleo descarta ano de lucro não positivo. Aqui a
  // mesma janela é reconstruída incluindo esses anos, para medir o viés.
  List<Map<String, dynamic>> completeReturns(CapitalSeries s) {
    final out = <Map<String, dynamic>>[];
    for (var i = 1; i < s.points.length; i++) {
      final a = s.points[i - 1], b = s.points[i];
      if (b.year - a.year != 1 || a.base <= 0) continue;
      final l = b.profit;
      out.add({
        'ano': b.year,
        'retorno': l == null ? null : l / a.base,
        'descartado': l == null || l <= 0,
      });
    }
    return out;
  }

  final allFirmReturns = completeReturns(firmSeries);
  final usedFirmReturns = firmSeries.returns;

  double? medianOf(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  // Ciclo incluindo os anos descartados (retorno negativo entra como é).
  const w = ValuationParameters.cycleWindow;
  final withLoss = <double>[];
  final inWindow = allFirmReturns.where((e) => e['retorno'] != null).toList();
  if (inWindow.length >= 2) {
    final start = inWindow.length - 1 - w;
    final window = inWindow.sublist(start < 0 ? 0 : start, inWindow.length - 1);
    for (final e in window) {
      withLoss.add(e['retorno'] as double);
    }
  }

  final lastReturnYear = usedFirmReturns.isEmpty ? null : usedFirmReturns.last.year;
  final lastFiscalYear = latest.fiscalPeriodEnd.year;

  final phi = GrowthGuards.externalCapitalRatio(firmSeries);
  final tend10 = GrowthGuards.trend(firmSeries, driftWindow: 10);
  final tend5 = GrowthGuards.trend(firmSeries, driftWindow: 5);
  final disp = GrowthGuards.dispersion(firmSeries);
  final decline = GrowthGuards.recentOperationalDecline(pub);

  final kd = latest.costOfDebt;
  final tax = latest.effectiveTaxRate;
  final capmT = inputs.capm.withRiskFree(inputs.terminalRiskFreeRate);
  final equityMkt = latest.marketCap;
  final coc = (latest.totalDebt > 0 && equityMkt != null && kd != null)
      ? CostOfCapital(
          capm: inputs.capm,
          costOfDebt: kd,
          taxRate: ValuationParameters.statutoryTaxRate,
          equityValue: equityMkt,
          // A líquida, como o motor (decisão 104).
          debtValue: latest.netDebt,
          interestCoverage: latest.interestCoverage,
          netDebtToEbitda: latest.netDebtToEbitda,
        )
      : null;

  final adtv = inputs.prices == null
      ? null
      : EligibilityGate.medianTradedValue(inputs.prices!);
  final divisor = ValuationCascade.quotedShares(
    latest: latest,
    marketPrice: inputs.marketPrice,
    sharesPerQuote: ValuationCascade.quotedUnitRatio(
      sharesOutstanding: latest.sharesOutstanding,
      marketCap: latest.marketCap,
      marketPrice: inputs.marketPrice,
    ),
  );

  return {
    'ticker': inputs.ticker.value,
    'preco': inputs.marketPrice,
    'setor': inputs.sectorKey,
    'industria': inputs.industry,
    'exerciciosPublicados': pub.length,
    'anoUltimoExercicio': lastFiscalYear,
    // Ações
    'nCorrente': nCurrent,
    'nExercicio': nFiscalYear,
    'nPorLpa': nByEps,
    'nPorMercado': nByMarket,
    'nConciliado': latest.reconciledShares,
    'nPonte': divisor?.count,
    'ponteOrigem': divisor?.source.name,
    'divergenciaPonte': divisor?.divergence,
    'adtv': adtv,
    'coberturaJuros': latest.interestCoverage,
    'alavancagem': latest.netDebtToEbitda,
    'discordam': latest.sharesDisagree,
    'marketCap': latest.marketCap,
    // Séries
    'pontosFirma': firmSeries.length,
    'pontosAcionista': shareholderSeries.length,
    'anoUltimoRetornoFirma': lastReturnYear,
    'defasagemRetorno':
        lastReturnYear == null ? null : lastFiscalYear - lastReturnYear,
    'anosDescartadosPorPrejuizo':
        allFirmReturns.where((e) => e['descartado'] == true).length,
    'roicAtual': firmSeries.latestReturn,
    'roicCiclo': firmSeries.cycleReturn(window: w),
    'roicCicloComPrejuizo': medianOf(withLoss),
    'retencaoMediana': firmSeries.medianRetention,
    // Guardas
    'phi': phi,
    'destoa': GrowthGuards.deviatesFromCycle(firmSeries),
    'tendencia10Domina': tend10?.dominates,
    'tendencia5Domina': tend5?.dominates,
    'tendenciaSignificante': tend10?.isSignificant,
    'tendenciaSlope': tend10?.slope,
    'tendenciaT': tend10?.tStatistic,
    'dominancia10': tend10?.dominance,
    'dominancia5': tend5?.dominance,
    'quedaTrienio': decline,
    'ciclicoPesado': CyclicalSectors.hasCyclePrecedence(
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    ),
    'crescIdentificado': disp?.isIdentified,
    'crescMediana': disp?.medianGrowth,
    'crescRegressao': disp?.regressionGrowth,
    'crescErroPadrao': disp?.stdError,
    'crescFalha': disp?.failure,
    // Custo de capital
    'beta': inputs.capm.beta,
    'betaOrigem': inputs.capm.betaSource.name,
    'rfCorrente': inputs.capm.riskFreeRate,
    'rfTerminal': inputs.terminalRiskFreeRate,
    'ke': inputs.capm.costOfEquity,
    'keTerminal': capmT.costOfEquity,
    'kdBruto': kd,
    'kdEfetivo': coc?.effectiveCostOfDebt,
    'kdConfinado': coc?.costOfDebtWasClamped,
    'aliquotaEfetiva': tax,
    'pesoDivida': coc?.debtShare,
    'wacc': coc?.wacc,
    'waccPiso': coc?.waccWasFloored,
    'dividaBruta': latest.totalDebt,
    'caixa': latest.totalCash,
    'dividaLiquida': latest.netDebt,
    'nopat': latest.nopatOrDerived,
    'nopatPublicado': latest.nopat,
    'ebit': latest.ebit,
    'ebitda': latest.ebitda,
    'lucroLiquido': latest.netIncome,
    'lpaPublicado': latest.earningsPerShare,
    'capitalInvestido': latest.investedCapital,
    'capitalInvestidoOper': latest.investedCapitalOperating,
    'patrimonio': latest.equityBookValue,
    'despesaFinanceira': latest.interestExpense,
  };
}

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime(2026, 9, 4);
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stderr.writeln('ancoras: rf=${anchors.currentRiskFreeRate} '
        'rfTerm=${anchors.riskFreeCagr} ipca=${anchors.inflationCagr} '
        'gNom=${anchors.nominalEconomyGrowth}');

    final universe = (await ctx.fundamentals.universe()).unwrap();
    final target =
        args.isEmpty ? universe : universe.where((t) => args.contains(t.value)).toList();

    final out = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in target) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${target.length}\r');
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
      if (prep.isErr) {
        out.add({'ticker': ticker.value, 'erro': prep.failureOrNull?.message});
        continue;
      }
      final inputs = prep.unwrap();
      final d = diagnose(inputs);
      for (final n in [10, 5]) {
        final variant = ValuationInputs(
          ticker: inputs.ticker,
          asOf: inputs.asOf,
          fundamentals: inputs.fundamentals,
          marketPrice: inputs.marketPrice,
          capm: inputs.capm,
          projectionYears: n,
          perpetualGrowthCap: inputs.perpetualGrowthCap,
          sectorKey: inputs.sectorKey,
          industry: inputs.industry,
          inflation: inputs.inflation,
          declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
          prices: inputs.prices,
          isDistressed: inputs.isDistressed,
        );
        final r = ValuationCascade.evaluate(variant);
        d['ok$n'] = r.isOk;
        d['motivo$n'] = r.isOk ? null : r.failureOrNull?.message;
        if (r.isOk) {
          final v = r.unwrap();
          d['fv$n'] = v.fairValue.reais;
          d['upside$n'] = v.upside;
          d['modelo$n'] = v.model.name;
          d['desconto$n'] = v.discountRate;
          d['avisos$n'] = v.warnings;
          d['ressalvas$n'] = [for (final c in v.diagnostics!.caveats) c.key];
          d['pesoTerminal$n'] = v.diagnostics!.terminalShare;
          d['equityShare$n'] = v.diagnostics!.equityShare;
          d['moat$n'] = v.diagnostics!.moatApplied;
        }
      }
      out.add(d);
    }
    File('docs/validacao/deep_audit.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    stderr.writeln('\nescrito docs/validacao/deep_audit.json (${out.length})');
  } finally {
    await ctx.dispose();
  }
}
