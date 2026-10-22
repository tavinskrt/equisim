// D7 — o efeito da ponte completa, isolado do dado novo.
//
// **O confundidor.** A [decisão 49](../docs/decisoes/049-a-ponte-devolve-o-que-nao-e-do-controlador.md)
// acrescentou dois campos ao cache, e a migração invalidou a chave de
// fundamentos — de modo que a rodada seguinte trouxe **todos** os campos
// frescos da fonte, não só os dois. Comparar contra o relatório anterior
// mediria a correção somada ao que a fonte mudou desde então.
//
// A separação é feita aqui: o mesmo ativo, na mesma série recém-buscada, é
// avaliado duas vezes — uma com os dois termos e outra com eles zerados, que é
// exatamente o comportamento de antes da decisão 49.
//
// Uso:
//   dart run tool/ponte.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

/// A mesma série, sem os dois termos da ponte.
///
/// Reproduz o motor de antes da decisão 49 **sobre o dado de agora**, que é o
/// que torna a comparação uma medida da correção e não da atualização.
List<FundamentalsSnapshot> _withoutTerms(List<FundamentalsSnapshot> series) => [
      for (final s in series)
        FundamentalsSnapshot(
          ticker: s.ticker,
          fiscalPeriodEnd: s.fiscalPeriodEnd,
          totalRevenue: s.totalRevenue,
          ebit: s.ebit,
          ebitda: s.ebitda,
          netIncome: s.netIncome,
          incomeBeforeTax: s.incomeBeforeTax,
          incomeTaxExpense: s.incomeTaxExpense,
          interestExpense: s.interestExpense,
          earningsPerShare: s.earningsPerShare,
          cash: s.cash,
          shortTermInvestments: s.shortTermInvestments,
          shortTermDebt: s.shortTermDebt,
          longTermDebt: s.longTermDebt,
          totalStockholderEquity: s.totalStockholderEquity,
          bookValuePerShare: s.bookValuePerShare,
          operatingCashFlow: s.operatingCashFlow,
          investmentCashFlow: s.investmentCashFlow,
          freeCashFlow: s.freeCashFlow,
          nopat: s.nopat,
          propertyPlantEquipment: s.propertyPlantEquipment,
          intangibleAssets: s.intangibleAssets,
          totalCurrentAssets: s.totalCurrentAssets,
          currentLiabilities: s.currentLiabilities,
          realizedShareCapital: s.realizedShareCapital,
          profitReserves: s.profitReserves,
          sharesOutstanding: s.sharesOutstanding,
          sharesOutstandingAsOf: s.sharesOutstandingAsOf,
          marketCap: s.marketCap,
          enterpriseToEbitda: s.enterpriseToEbitda,
          // Os dois que a decisão 49 introduziu ficam de fora.
        ),
    ];

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1)}%';

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

    final output = <Map<String, dynamic>>[];
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
      final inputs = prep.unwrap();

      final withTerms = ValuationCascade.evaluate(inputs);
      final withoutTermsResult = ValuationCascade.evaluate(ValuationInputs(
        ticker: inputs.ticker,
        asOf: inputs.asOf,
        fundamentals: _withoutTerms(inputs.fundamentals),
        marketPrice: inputs.marketPrice,
        capm: inputs.capm,
        marginOfSafety: inputs.marginOfSafety,
        projectionYears: inputs.projectionYears,
        perpetualGrowthCap: inputs.perpetualGrowthCap,
        sectorKey: inputs.sectorKey,
        industry: inputs.industry,
        inflation: inputs.inflation,
        declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
        prices: inputs.prices,
        isDistressed: inputs.isDistressed,
        unleveredBeta: inputs.unleveredBeta,
      ));

      final last = PointInTimeView(inputs.asOf)
          .published(inputs.fundamentals)
          .lastOrNull;
      final marketValue = inputs.marketPrice *
          (last?.sharesOutstanding ?? double.nan);

      output.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'via': withTerms.isOk ? withTerms.unwrap().model.name : null,
        'justoCom': withTerms.isOk ? withTerms.unwrap().fairValue.reais : null,
        'justoSem': withoutTermsResult.isOk ? withoutTermsResult.unwrap().fairValue.reais : null,
        'minoritarios': last?.minorityInterest,
        'equivalencia': last?.equityIncomeResult,
        'ebit': last?.ebit,
        'valorDeMercado': marketValue.isFinite ? marketValue : null,
      });
    }
    stderr.writeln('');

    File('docs/validacao/ponte.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output);
    stderr.writeln('\nescrito docs/validacao/ponte.json (${output.length})');
  } finally {
    await ctx.dispose();
  }
}

void _printReport(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== D7 — A PONTE COMPLETA — ${l.length} ativos ===\n');

  final withMinority = l
      .where((e) =>
          e['minoritarios'] != null && (e['minoritarios'] as num).abs() > 0)
      .length;
  final withEquityMethod = l
      .where((e) =>
          e['equivalencia'] != null && (e['equivalencia'] as num) > 0)
      .length;
  stdout.writeln('-- quantos têm cada termo --');
  stdout.writeln('  com participação de não controladores: $withMinority');
  stdout.writeln('  com equivalência patrimonial positiva: $withEquityMethod');

  final weight = [
    for (final e in l)
      if (e['equivalencia'] != null &&
          e['ebit'] != null &&
          (e['ebit'] as num) > 0 &&
          (e['equivalencia'] as num) > 0)
        ((e['equivalencia'] as num) / (e['ebit'] as num)).toDouble()
  ];
  if (weight.isNotEmpty) {
    weight.sort();
    stdout.writeln('  equivalência ÷ EBIT: mediana=${_pc(_median(weight)!)}  '
        'máx=${_pc(weight.last)}  (n=${weight.length})');
    stdout.writeln('  acima de 20% do EBIT: '
        '${weight.where((x) => x > 0.20).length}');
  }

  final changes = <({String ticker, double delta})>[];
  var evaluatedWith = 0;
  var evaluatedWithout = 0;
  for (final e in l) {
    final withInput = e['justoCom'] as num?;
    final without = e['justoSem'] as num?;
    if (withInput != null && withInput > 0) evaluatedWith++;
    if (without != null && without > 0) evaluatedWithout++;
    if (withInput == null || without == null || without <= 0 || withInput <= 0) continue;
    final d = withInput / without - 1;
    if (d.abs() > 0.005) {
      changes.add((ticker: e['ticker'] as String, delta: d.toDouble()));
    }
  }
  changes.sort((a, b) => a.delta.compareTo(b.delta));

  stdout.writeln('\n-- o efeito da correção, na mesma série --');
  stdout.writeln('  avaliados com os termos: $evaluatedWith   '
      'sem eles: $evaluatedWithout');
  stdout.writeln('  preços justos alterados além de 0,5%: '
      '${changes.length}');
  if (changes.isNotEmpty) {
    final ds = [for (final v in changes) v.delta];
    stdout.writeln('  variação mediana dos alterados: '
        '${_pc(_median(ds)!)}');
    stdout.writeln('  caem: ${ds.where((d) => d < 0).length}   '
        'sobem: ${ds.where((d) => d > 0).length}');
    stdout.writeln('  as maiores quedas:');
    for (final v in changes.take(6)) {
      stdout.writeln('    ${v.ticker.padRight(7)} ${_pc(v.delta).padLeft(9)}');
    }
    stdout.writeln('  as maiores altas:');
    for (final v in changes.reversed.take(6)) {
      stdout.writeln('    ${v.ticker.padRight(7)} ${_pc(v.delta).padLeft(9)}');
    }
  }

  // O tamanho dos minoritários contra o valor de mercado, que é a régua da
  // materialidade: 24,1% na CSNA3 quando a sonda mediu.
  final ratios = [
    for (final e in l)
      if (e['minoritarios'] != null &&
          e['valorDeMercado'] != null &&
          (e['valorDeMercado'] as num) > 0 &&
          (e['minoritarios'] as num) > 0)
        (
          e['ticker'] as String,
          ((e['minoritarios'] as num) / (e['valorDeMercado'] as num)).toDouble()
        )
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (ratios.isNotEmpty) {
    stdout.writeln('\n-- não controladores ÷ valor de mercado --');
    stdout.writeln('  mediana=${_pc(_median([
          for (final r in ratios) r.$2
        ])!)}   acima de 10%: ${ratios.where((r) => r.$2 > 0.10).length}');
    for (final r in ratios.take(8)) {
      stdout.writeln('    ${r.$1.padRight(7)} ${_pc(r.$2).padLeft(7)}');
    }
  }
}
