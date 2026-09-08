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

  final serieFirma = CapitalSeries.build(pub, ValuationLane.firm);
  final serieAcion = CapitalSeries.build(pub, ValuationLane.shareholder);

  // --- Contagem de ações: todas as fontes lado a lado ---
  final nCorrente = latest.sharesOutstanding;
  final nExercicio = latest.sharesOutstandingAsOf;
  final lucro = latest.netIncome;
  final lpa = latest.earningsPerShare;
  final nPorLpa =
      (lucro != null && lpa != null && lpa.abs() > 1e-9) ? lucro / lpa : null;
  final nPorMercado = (latest.marketCap != null && inputs.marketPrice > 0)
      ? latest.marketCap! / inputs.marketPrice
      : null;

  // --- Retornos: com e sem os exercícios de prejuízo ---
  // A série `returns` do núcleo descarta ano de lucro não positivo. Aqui a
  // mesma janela é reconstruída incluindo esses anos, para medir o viés.
  List<Map<String, dynamic>> retornosCompletos(CapitalSeries s) {
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

  final rFirmaTodos = retornosCompletos(serieFirma);
  final rFirmaUsados = serieFirma.returns;

  double? medianaDe(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  // Ciclo incluindo os anos descartados (retorno negativo entra como é).
  const w = ValuationParameters.cycleWindow;
  final comPrejuizo = <double>[];
  final naJanela = rFirmaTodos.where((e) => e['retorno'] != null).toList();
  if (naJanela.length >= 2) {
    final ini = naJanela.length - 1 - w;
    final janela = naJanela.sublist(ini < 0 ? 0 : ini, naJanela.length - 1);
    for (final e in janela) {
      comPrejuizo.add(e['retorno'] as double);
    }
  }

  final anoUltimoRetorno = rFirmaUsados.isEmpty ? null : rFirmaUsados.last.year;
  final anoUltimoExercicio = latest.fiscalPeriodEnd.year;

  final phi = GrowthGuards.externalCapitalRatio(serieFirma);
  final tend10 = GrowthGuards.trend(serieFirma, driftWindow: 10);
  final tend5 = GrowthGuards.trend(serieFirma, driftWindow: 5);
  final disp = GrowthGuards.dispersion(serieFirma);
  final queda = GrowthGuards.recentOperationalDecline(pub);

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
          debtValue: latest.totalDebt,
          interestCoverage: latest.interestCoverage,
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
    'anoUltimoExercicio': anoUltimoExercicio,
    // Ações
    'nCorrente': nCorrente,
    'nExercicio': nExercicio,
    'nPorLpa': nPorLpa,
    'nPorMercado': nPorMercado,
    'nConciliado': latest.reconciledShares,
    'nPonte': divisor?.count,
    'ponteOrigem': divisor?.source.name,
    'divergenciaPonte': divisor?.divergence,
    'adtv': adtv,
    'coberturaJuros': latest.interestCoverage,
    'discordam': latest.sharesDisagree,
    'marketCap': latest.marketCap,
    // Séries
    'pontosFirma': serieFirma.length,
    'pontosAcionista': serieAcion.length,
    'anoUltimoRetornoFirma': anoUltimoRetorno,
    'defasagemRetorno':
        anoUltimoRetorno == null ? null : anoUltimoExercicio - anoUltimoRetorno,
    'anosDescartadosPorPrejuizo':
        rFirmaTodos.where((e) => e['descartado'] == true).length,
    'roicAtual': serieFirma.latestReturn,
    'roicCiclo': serieFirma.cycleReturn(window: w),
    'roicCicloComPrejuizo': medianaDe(comPrejuizo),
    'retencaoMediana': serieFirma.medianRetention,
    // Guardas
    'phi': phi,
    'destoa': GrowthGuards.deviatesFromCycle(serieFirma),
    'tendencia10Domina': tend10?.dominates,
    'tendencia5Domina': tend5?.dominates,
    'tendenciaSignificante': tend10?.isSignificant,
    'tendenciaSlope': tend10?.slope,
    'tendenciaT': tend10?.tStatistic,
    'dominancia10': tend10?.dominance,
    'dominancia5': tend5?.dominance,
    'quedaTrienio': queda,
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
    final alvo =
        args.isEmpty ? universe : universe.where((t) => args.contains(t.value)).toList();

    final out = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in alvo) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${alvo.length}\r');
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
        final variante = ValuationInputs(
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
        final r = ValuationCascade.evaluate(variante);
        d['ok$n'] = r.isOk;
        d['motivo$n'] = r.isOk ? null : r.failureOrNull?.message;
        if (r.isOk) {
          final v = r.unwrap();
          d['fv$n'] = v.fairValue.reais;
          d['upside$n'] = v.upside;
          d['modelo$n'] = v.model.name;
          d['desconto$n'] = v.discountRate;
          d['avisos$n'] = v.warnings;
          d['ressalvas$n'] = [for (final c in v.diagnostics!.caveats) c.name];
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
