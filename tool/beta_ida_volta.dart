// A ida e a volta do beta não se cancelam.
//
// **O defeito.** O beta é desalavancado contra a dívida **bruta** sobre o valor
// de mercado, e realavancado contra a dívida **líquida** sobre o capital
// próprio que o modelo produz:
//
// ```
// β_U   = β_L / (1 + (1 − τ)·D_bruta/E_mercado)     ← prepare_valuation_inputs
// β_L,t = β_U · (1 + (1 − τ)·D_líquida/E_modelo)    ← levered_rates
// ```
//
// As duas contas usam alavancagens diferentes, de modo que o `β_L` que volta
// não é o que saiu. Numa empresa com caixa alto a diferença é o caixa inteiro:
// a ida divide por um fator grande e a volta multiplica por um pequeno.
//
// **O que isto mede.** O tamanho da distância entre as duas alavancagens e o
// que ela faz com o beta e com o custo do capital próprio.
//
// Uso:
//   dart run tool/beta_ida_volta.dart
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

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
String _pp(double v) => '${(v * 100).toStringAsFixed(2)} p.p.';

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
      final r = ValuationCascade.evaluate(inputs);
      if (r.isErr) continue;

      final pub = PointInTimeView(inputs.asOf)
          .published(inputs.fundamentals)
          .where((s) => s.hasIncomeStatement)
          .toList();
      if (pub.isEmpty) continue;
      final last = pub.last;
      final marketValue = last.marketCap;
      if (marketValue == null || marketValue <= 0) continue;

      final tau = CapitalSeries.structuralTaxRate(
            pub,
            statutoryRate: ValuationParameters.statutoryTaxRate,
          ) ??
          ValuationParameters.statutoryTaxRate;

      final grossDebtToEquity = last.totalDebt / marketValue;
      final netDebtToEquity = last.netDebt / marketValue;
      final grossFactor =
          BetaShrinkage.leverageFactor(debtToEquity: grossDebtToEquity, taxRate: tau);
      final netFactor =
          BetaShrinkage.leverageFactor(debtToEquity: netDebtToEquity, taxRate: tau);
      if (grossFactor == null || netFactor == null) continue;

      // O `Ke` do primeiro ano é afim no beta, de modo que a distância entre
      // os dois betas vira distância no custo do capital próprio pelo prêmio.
      final betaU = inputs.unleveredBeta;
      final betaL = inputs.capm.beta;

      // O peso do encolhimento, refeito aqui com os mesmos insumos: é ele que
      // diz quanto da decisão 40 chega ao preço. O beta cru vem de refazer a
      // regressão — `PrepareValuationInputs` devolve só o encolhido.
      ShrunkBeta? shrunk;
      BetaEstimate? raw;
      // A mesma janela em que o beta é estimado.
      final window = DateRange(
        DateTime(_today.year - PrepareValuationInputs.betaWindowYears,
            _today.month, _today.day),
        _today,
      );
      final seriesResult = await ctx.prices.daily(ticker, window);
      final marketResult = await ctx.benchmark.ibovespa(window);
      if (seriesResult.isOk && marketResult.isOk && prior != null) {
        final series = seriesResult.unwrap();
        final market = marketResult.unwrap();
        final points =
            series.points.where((p) => window.contains(p.date)).toList();
        if (points.length >= 2 && market.points.length >= 30) {
          final pair = BetaCalculator.alignReturns(
            assetDates: [for (final p in points) p.date],
            assetIndex: [for (final p in points) p.close],
            marketDates: market.dates,
            marketIndex: market.points.map((p) => p.close).toList(),
          );
          final est = BetaCalculator.estimate(returns: pair);
          if (est.isOk) {
            raw = est.unwrap();
            shrunk = BetaShrinkage.shrink(
              leveredBeta: raw.beta,
              standardError: raw.standardError,
              prior: prior,
              sectorKey: inputs.sectorKey,
              debtToEquity: netDebtToEquity,
              taxRate: tau,
            );
          }
        }
      }

      // --- A alavancagem ao longo da janela do beta ---------------------
      //
      // O beta é covariância de cinco anos; a alavancagem que o desalavanca é
      // a foto de hoje. Se a empresa desalavancou no período, a foto é menor
      // que a média e o `β_U` sai grande demais.
      final byYear = <Map<String, dynamic>>[];
      if (seriesResult.isOk) {
        final points = seriesResult.unwrap().points;
        for (final ex in pub) {
          if (!window.contains(ex.fiscalPeriodEnd)) continue;
          final shares = ex.sharesOutstandingAsOf;
          if (shares == null || shares <= 0) continue;
          // Preço do fechamento mais próximo do fim do exercício.
          PricePoint? nearest;
          var smallestDistance = 1 << 30;
          int inDays(DateTime x) =>
              DateTime.utc(x.year, x.month, x.day).millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay;
          final fiscalYearEnd = inDays(ex.fiscalPeriodEnd);
          for (final pt in points) {
            final d = (inDays(pt.date) - fiscalYearEnd).abs();
            if (d < smallestDistance) {
              smallestDistance = d;
              nearest = pt;
            }
          }
          if (nearest == null || smallestDistance > 20) continue;
          final yearMarketValue = nearest.close * shares;
          final debtToEquity = ex.debtToMarketEquity(yearMarketValue);
          if (debtToEquity == null) continue;
          byYear.add({'ano': ex.fiscalPeriodEnd.year, 'de': debtToEquity});
        }
      }
      final windowDebtToEquities = [
        for (final x in byYear) (x['de'] as num).toDouble()
      ];
      final windowDebtToEquity = _median(windowDebtToEquities);

      output.add({
        'ticker': ticker.value,
        'deJanela': windowDebtToEquity,
        'exerciciosNaJanela': byYear.length,
        'alavancagemPorAno': byYear,
        'setor': inputs.sectorKey,
        'aliquota': tau,
        'dividaBruta': last.totalDebt,
        'dividaLiquida': last.netDebt,
        'valorDeMercado': marketValue,
        // O valor de mercado que a fonte publica contra o que o preço de tela
        // e a contagem de ações produzem. Divergir aqui contamina a
        // alavancagem que desalavanca o beta.
        'vmPorPrecoEAcoes': last.sharesOutstanding == null
            ? null
            : inputs.marketPrice * last.sharesOutstanding!,
        'deBruta': grossDebtToEquity,
        'deLiquida': netDebtToEquity,
        'fatorBruta': grossFactor,
        'fatorLiquida': netFactor,
        // Quanto o beta desalavancado muda ao trocar a alavancagem da ida.
        'razaoDosFatores': grossFactor / netFactor,
        'betaAlavancado': betaL,
        'betaDesalavancado': betaU,
        'premio': inputs.capm.marketPremium,
        'caixaLiquido': last.netDebt < 0,
        'betaCru': raw?.beta,
        'erroPadrao': raw?.standardError,
        'peso': shrunk?.weight,
        // O desalavancado como era — do beta cru — e como passou a ser.
        'desalavancadoDoCru': raw == null
            ? null
            : BetaShrinkage.unlever(
                leveredBeta: raw.beta,
                debtToEquity: netDebtToEquity,
                taxRate: tau,
              ),
        'desalavancadoDoEncolhido': shrunk?.unlevered,
      });
    }
    stderr.writeln('');

    File('docs/validacao/beta_ida_volta.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output);
    stderr.writeln('\nescrito docs/validacao/beta_ida_volta.json '
        '(${output.length})');
  } finally {
    await ctx.dispose();
  }
}

void _printReport(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== A IDA E A VOLTA DO BETA — ${l.length} avaliados ===\n');

  final ratios = [
    for (final e in l) (e['razaoDosFatores'] as num).toDouble()
  ]..sort();
  double q(double f) => ratios[((ratios.length - 1) * f).round()];
  stdout.writeln('-- fator da ida ÷ fator da volta --');
  stdout.writeln('  p10=${q(0.10).toStringAsFixed(3)}  '
      'mediana=${_median(ratios)!.toStringAsFixed(3)}  '
      'p90=${q(0.90).toStringAsFixed(3)}');
  stdout.writeln('  acima de 1,10: ${ratios.where((x) => x > 1.10).length}  '
      'acima de 1,50: ${ratios.where((x) => x > 1.50).length}');
  stdout.writeln('  **o beta que volta é menor que o medido em '
      '${ratios.where((x) => x > 1.0001).length} de ${ratios.length}**');

  final withCash = l.where((e) => e['caixaLiquido'] == true).toList();
  stdout.writeln('\n-- empresas com caixa líquido --');
  stdout.writeln('  ${withCash.length} de ${l.length}');
  stdout.writeln('  nelas a dívida líquida é negativa e o fator da volta é o '
      'piso: a ida divide e a volta não multiplica de volta.');

  // O que a distância vale no custo do capital próprio.
  final deltas = <double>[];
  for (final e in l) {
    final bu = (e['betaDesalavancado'] as num?)?.toDouble();
    if (bu == null) continue;
    final premium = (e['premio'] as num).toDouble();
    final fb = (e['fatorBruta'] as num).toDouble();
    final netFactor = (e['fatorLiquida'] as num).toDouble();
    // Beta que a volta produz hoje contra o que produziria se a ida usasse a
    // mesma alavancagem — na alavancagem do ano zero, que é a de mercado.
    final today = bu * netFactor;
    final coherent = bu * (fb / netFactor) * netFactor;
    deltas.add((coherent - today) * premium);
  }
  if (deltas.isNotEmpty) {
    deltas.sort();
    double dq(double f) => deltas[((deltas.length - 1) * f).round()];
    stdout.writeln('\n-- o que isso vale no custo do capital próprio --');
    stdout.writeln('  p10=${_pp(dq(0.10))}  mediana=${_pp(_median(deltas)!)}  '
        'p90=${_pp(dq(0.90))}');
    stdout.writeln('  acima de 1 p.p.: ${deltas.where((x) => x > 0.01).length}'
        '  acima de 3 p.p.: ${deltas.where((x) => x > 0.03).length}');
  }

  final weights = [
    for (final e in l)
      if (e['peso'] != null) (e['peso'] as num).toDouble()
  ]..sort();
  if (weights.isNotEmpty) {
    stdout.writeln('\n-- peso do próprio ativo no encolhimento --');
    stdout.writeln('  p10=${weights[(weights.length * 0.1).floor()].toStringAsFixed(3)}  '
        'mediana=${_median(weights)!.toStringAsFixed(3)}  '
        'p90=${weights[(weights.length * 0.9).floor()].toStringAsFixed(3)}');
    stdout.writeln('  abaixo de 0,90: ${weights.where((x) => x < 0.90).length} '
        'de ${weights.length}');
    final diff = <double>[];
    for (final e in l) {
      final a = (e['desalavancadoDoCru'] as num?)?.toDouble();
      final b = (e['desalavancadoDoEncolhido'] as num?)?.toDouble();
      // Magnitude, e não igualdade: o divisor é um beta desalavancado, e um
      // resíduo de ponto flutuante ali produziria razão sem sentido.
      if (a == null || b == null || a.abs() < 1e-9) continue;
      diff.add((b / a - 1).abs());
    }
    if (diff.isNotEmpty) {
      diff.sort();
      stdout.writeln('  |desalavancado do encolhido ÷ do cru − 1|: '
          'mediana=${_pc(_median(diff)!)}  '
          'p90=${_pc(diff[(diff.length * 0.9).floor()])}');
    }
  }

  // --- A janela contra a foto -------------------------------------------
  final withWindow = [
    for (final e in l)
      if (e['deJanela'] != null && (e['exerciciosNaJanela'] as int) >= 3) e
  ];
  if (withWindow.isNotEmpty) {
    stdout.writeln('\n-- alavancagem: a foto de hoje contra a janela do beta --');
    stdout.writeln('  ativos com ao menos três exercícios na janela: '
        '${withWindow.length} de ${l.length}');
    final ratios2 = <double>[];
    for (final e in withWindow) {
      final today = (e['deLiquida'] as num).toDouble();
      final windowDebtToEquity = (e['deJanela'] as num).toDouble();
      final tau = (e['aliquota'] as num).toDouble();
      final todayFactor = BetaShrinkage.leverageFactor(debtToEquity: today, taxRate: tau);
      final windowFactor = BetaShrinkage.leverageFactor(debtToEquity: windowDebtToEquity, taxRate: tau);
      if (todayFactor == null || windowFactor == null || todayFactor <= 0) continue;
      ratios2.add(windowFactor / todayFactor);
    }
    ratios2.sort();
    if (ratios2.isNotEmpty) {
      stdout.writeln('  fator da janela ÷ fator de hoje: '
          'p10=${ratios2[(ratios2.length * 0.1).floor()].toStringAsFixed(3)}  '
          'mediana=${_median(ratios2)!.toStringAsFixed(3)}  '
          'p90=${ratios2[(ratios2.length * 0.9).floor()].toStringAsFixed(3)}');
      stdout.writeln('  distante mais de 10%: '
          '${ratios2.where((x) => (x - 1).abs() > 0.10).length}  '
          'mais de 25%: ${ratios2.where((x) => (x - 1).abs() > 0.25).length}');
      stdout.writeln('  a janela é MAIS alavancada em '
          '${ratios2.where((x) => x > 1).length} de ${ratios2.length}');
    }
    final ord2 = [...withWindow]..sort((a, b) =>
        ((b['deJanela'] as num) - (b['deLiquida'] as num))
            .abs()
            .compareTo(((a['deJanela'] as num) - (a['deLiquida'] as num)).abs()));
    stdout.writeln('  ${"ativo".padRight(8)}${"hoje".padLeft(9)}'
        '${"janela".padLeft(10)}${"anos".padLeft(6)}');
    for (final e in ord2.take(8)) {
      stdout.writeln('  ${(e['ticker'] as String).padRight(8)}'
          '${_pc((e['deLiquida'] as num).toDouble()).padLeft(9)}'
          '${_pc((e['deJanela'] as num).toDouble()).padLeft(10)}'
          '${(e['exerciciosNaJanela'] as int).toString().padLeft(6)}');
    }
  }

  final deviations = <({String ticker, double ratio})>[];
  for (final e in l) {
    final marketValue = (e['valorDeMercado'] as num).toDouble();
    final alt = (e['vmPorPrecoEAcoes'] as num?)?.toDouble();
    if (alt == null || alt <= 0 || marketValue <= 0) continue;
    deviations.add((ticker: e['ticker'] as String, ratio: alt / marketValue));
  }
  if (deviations.isNotEmpty) {
    final rs = [for (final d in deviations) d.ratio]..sort();
    stdout.writeln('\n-- o valor de mercado publicado confere? --');
    stdout.writeln('  preço × ações ÷ marketCap: '
        'p10=${rs[(rs.length * 0.1).floor()].toStringAsFixed(3)}  '
        'mediana=${_median(rs)!.toStringAsFixed(3)}  '
        'p90=${rs[(rs.length * 0.9).floor()].toStringAsFixed(3)}');
    stdout.writeln('  fora de [0,9; 1,1]: '
        '${rs.where((x) => x < 0.9 || x > 1.1).length} de ${rs.length}  '
        'fora de [0,5; 2,0]: '
        '${rs.where((x) => x < 0.5 || x > 2.0).length}');
    final worst2 = [...deviations]
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
    for (final d in worst2.take(6)) {
      stdout.writeln('    ${d.ticker.padRight(8)} '
          '${d.ratio.toStringAsFixed(1)}×');
    }
  }

  final worst = [...l]..sort((a, b) => (b['razaoDosFatores'] as num)
      .compareTo(a['razaoDosFatores'] as num));
  stdout.writeln('\n-- onde a distância é maior --');
  stdout.writeln('  ${"ativo".padRight(8)}${"D/E bruta".padLeft(11)}'
      '${"D/E líq".padLeft(10)}${"ida÷volta".padLeft(11)}');
  for (final e in worst.take(10)) {
    stdout.writeln('  ${(e['ticker'] as String).padRight(8)}'
        '${_pc((e['deBruta'] as num).toDouble()).padLeft(11)}'
        '${_pc((e['deLiquida'] as num).toDouble()).padLeft(10)}'
        '${(e['razaoDosFatores'] as num).toStringAsFixed(3).padLeft(11)}');
  }
}
