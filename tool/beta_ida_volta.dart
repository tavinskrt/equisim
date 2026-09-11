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

final _hoje = DateTime(2026, 9, 4);

double? _mediana(List<double> v) {
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
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final prior = await ResolveBetaPrior.call(
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    );

    final saida = <Map<String, dynamic>>[];
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
        asOf: _hoje,
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
      final ultimo = pub.last;
      final vm = ultimo.marketCap;
      if (vm == null || vm <= 0) continue;

      final tau = CapitalSeries.structuralTaxRate(
            pub,
            statutoryRate: ValuationParameters.statutoryTaxRate,
          ) ??
          ValuationParameters.statutoryTaxRate;

      final deBruta = ultimo.totalDebt / vm;
      final deLiquida = ultimo.netDebt / vm;
      final fatorBruta =
          BetaShrinkage.leverageFactor(debtToEquity: deBruta, taxRate: tau);
      final fatorLiquida =
          BetaShrinkage.leverageFactor(debtToEquity: deLiquida, taxRate: tau);
      if (fatorBruta == null || fatorLiquida == null) continue;

      // O `Ke` do primeiro ano é afim no beta, de modo que a distância entre
      // os dois betas vira distância no custo do capital próprio pelo prêmio.
      final betaU = inputs.unleveredBeta;
      final betaL = inputs.capm.beta;

      // O peso do encolhimento, refeito aqui com os mesmos insumos: é ele que
      // diz quanto da decisão 40 chega ao preço. O beta cru vem de refazer a
      // regressão — `PrepareValuationInputs` devolve só o encolhido.
      ShrunkBeta? encolhido;
      BetaEstimate? bruto;
      // A mesma janela em que o beta é estimado.
      final janela = DateRange(
        DateTime(_hoje.year - PrepareValuationInputs.betaWindowYears,
            _hoje.month, _hoje.day),
        _hoje,
      );
      final serieRes = await ctx.prices.daily(ticker, janela);
      final mercadoRes = await ctx.benchmark.ibovespa(janela);
      if (serieRes.isOk && mercadoRes.isOk && prior != null) {
        final serie = serieRes.unwrap();
        final mercado = mercadoRes.unwrap();
        final pontos =
            serie.points.where((p) => janela.contains(p.date)).toList();
        if (pontos.length >= 2 && mercado.points.length >= 30) {
          final par = BetaCalculator.alignReturns(
            assetDates: [for (final p in pontos) p.date],
            assetIndex: [for (final p in pontos) p.close],
            marketDates: mercado.dates,
            marketIndex: mercado.points.map((p) => p.close).toList(),
          );
          final est = BetaCalculator.estimate(returns: par);
          if (est.isOk) {
            bruto = est.unwrap();
            encolhido = BetaShrinkage.shrink(
              leveredBeta: bruto.beta,
              standardError: bruto.standardError,
              prior: prior,
              sectorKey: inputs.sectorKey,
              debtToEquity: deLiquida,
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
      final porAno = <Map<String, dynamic>>[];
      if (serieRes.isOk) {
        final pontos = serieRes.unwrap().points;
        for (final ex in pub) {
          if (!janela.contains(ex.fiscalPeriodEnd)) continue;
          final acoes = ex.sharesOutstandingAsOf;
          if (acoes == null || acoes <= 0) continue;
          // Preço do fechamento mais próximo do fim do exercício.
          PricePoint? maisProximo;
          var menorDistancia = 1 << 30;
          int emDias(DateTime x) =>
              DateTime.utc(x.year, x.month, x.day).millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay;
          final fimDoExercicio = emDias(ex.fiscalPeriodEnd);
          for (final pt in pontos) {
            final d = (emDias(pt.date) - fimDoExercicio).abs();
            if (d < menorDistancia) {
              menorDistancia = d;
              maisProximo = pt;
            }
          }
          if (maisProximo == null || menorDistancia > 20) continue;
          final vmAno = maisProximo.close * acoes;
          final de = ex.debtToMarketEquity(vmAno);
          if (de == null) continue;
          porAno.add({'ano': ex.fiscalPeriodEnd.year, 'de': de});
        }
      }
      final desDaJanela = [
        for (final x in porAno) (x['de'] as num).toDouble()
      ];
      final deJanela = _mediana(desDaJanela);

      saida.add({
        'ticker': ticker.value,
        'deJanela': deJanela,
        'exerciciosNaJanela': porAno.length,
        'alavancagemPorAno': porAno,
        'setor': inputs.sectorKey,
        'aliquota': tau,
        'dividaBruta': ultimo.totalDebt,
        'dividaLiquida': ultimo.netDebt,
        'valorDeMercado': vm,
        // O valor de mercado que a fonte publica contra o que o preço de tela
        // e a contagem de ações produzem. Divergir aqui contamina a
        // alavancagem que desalavanca o beta.
        'vmPorPrecoEAcoes': ultimo.sharesOutstanding == null
            ? null
            : inputs.marketPrice * ultimo.sharesOutstanding!,
        'deBruta': deBruta,
        'deLiquida': deLiquida,
        'fatorBruta': fatorBruta,
        'fatorLiquida': fatorLiquida,
        // Quanto o beta desalavancado muda ao trocar a alavancagem da ida.
        'razaoDosFatores': fatorBruta / fatorLiquida,
        'betaAlavancado': betaL,
        'betaDesalavancado': betaU,
        'premio': inputs.capm.marketPremium,
        'caixaLiquido': ultimo.netDebt < 0,
        'betaCru': bruto?.beta,
        'erroPadrao': bruto?.standardError,
        'peso': encolhido?.weight,
        // O desalavancado como era — do beta cru — e como passou a ser.
        'desalavancadoDoCru': bruto == null
            ? null
            : BetaShrinkage.unlever(
                leveredBeta: bruto.beta,
                debtToEquity: deLiquida,
                taxRate: tau,
              ),
        'desalavancadoDoEncolhido': encolhido?.unlevered,
      });
    }
    stderr.writeln('');

    File('docs/validacao/beta_ida_volta.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida);
    stderr.writeln('\nescrito docs/validacao/beta_ida_volta.json '
        '(${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== A IDA E A VOLTA DO BETA — ${l.length} avaliados ===\n');

  final razoes = [
    for (final e in l) (e['razaoDosFatores'] as num).toDouble()
  ]..sort();
  double q(double f) => razoes[((razoes.length - 1) * f).round()];
  stdout.writeln('-- fator da ida ÷ fator da volta --');
  stdout.writeln('  p10=${q(0.10).toStringAsFixed(3)}  '
      'mediana=${_mediana(razoes)!.toStringAsFixed(3)}  '
      'p90=${q(0.90).toStringAsFixed(3)}');
  stdout.writeln('  acima de 1,10: ${razoes.where((x) => x > 1.10).length}  '
      'acima de 1,50: ${razoes.where((x) => x > 1.50).length}');
  stdout.writeln('  **o beta que volta é menor que o medido em '
      '${razoes.where((x) => x > 1.0001).length} de ${razoes.length}**');

  final comCaixa = l.where((e) => e['caixaLiquido'] == true).toList();
  stdout.writeln('\n-- empresas com caixa líquido --');
  stdout.writeln('  ${comCaixa.length} de ${l.length}');
  stdout.writeln('  nelas a dívida líquida é negativa e o fator da volta é o '
      'piso: a ida divide e a volta não multiplica de volta.');

  // O que a distância vale no custo do capital próprio.
  final deltas = <double>[];
  for (final e in l) {
    final bu = (e['betaDesalavancado'] as num?)?.toDouble();
    if (bu == null) continue;
    final premio = (e['premio'] as num).toDouble();
    final fb = (e['fatorBruta'] as num).toDouble();
    final fl = (e['fatorLiquida'] as num).toDouble();
    // Beta que a volta produz hoje contra o que produziria se a ida usasse a
    // mesma alavancagem — na alavancagem do ano zero, que é a de mercado.
    final hoje = bu * fl;
    final coerente = bu * (fb / fl) * fl;
    deltas.add((coerente - hoje) * premio);
  }
  if (deltas.isNotEmpty) {
    deltas.sort();
    double dq(double f) => deltas[((deltas.length - 1) * f).round()];
    stdout.writeln('\n-- o que isso vale no custo do capital próprio --');
    stdout.writeln('  p10=${_pp(dq(0.10))}  mediana=${_pp(_mediana(deltas)!)}  '
        'p90=${_pp(dq(0.90))}');
    stdout.writeln('  acima de 1 p.p.: ${deltas.where((x) => x > 0.01).length}'
        '  acima de 3 p.p.: ${deltas.where((x) => x > 0.03).length}');
  }

  final pesos = [
    for (final e in l)
      if (e['peso'] != null) (e['peso'] as num).toDouble()
  ]..sort();
  if (pesos.isNotEmpty) {
    stdout.writeln('\n-- peso do próprio ativo no encolhimento --');
    stdout.writeln('  p10=${pesos[(pesos.length * 0.1).floor()].toStringAsFixed(3)}  '
        'mediana=${_mediana(pesos)!.toStringAsFixed(3)}  '
        'p90=${pesos[(pesos.length * 0.9).floor()].toStringAsFixed(3)}');
    stdout.writeln('  abaixo de 0,90: ${pesos.where((x) => x < 0.90).length} '
        'de ${pesos.length}');
    final dif = <double>[];
    for (final e in l) {
      final a = (e['desalavancadoDoCru'] as num?)?.toDouble();
      final b = (e['desalavancadoDoEncolhido'] as num?)?.toDouble();
      // Magnitude, e não igualdade: o divisor é um beta desalavancado, e um
      // resíduo de ponto flutuante ali produziria razão sem sentido.
      if (a == null || b == null || a.abs() < 1e-9) continue;
      dif.add((b / a - 1).abs());
    }
    if (dif.isNotEmpty) {
      dif.sort();
      stdout.writeln('  |desalavancado do encolhido ÷ do cru − 1|: '
          'mediana=${_pc(_mediana(dif)!)}  '
          'p90=${_pc(dif[(dif.length * 0.9).floor()])}');
    }
  }

  // --- A janela contra a foto -------------------------------------------
  final comJanela = [
    for (final e in l)
      if (e['deJanela'] != null && (e['exerciciosNaJanela'] as int) >= 3) e
  ];
  if (comJanela.isNotEmpty) {
    stdout.writeln('\n-- alavancagem: a foto de hoje contra a janela do beta --');
    stdout.writeln('  ativos com ao menos três exercícios na janela: '
        '${comJanela.length} de ${l.length}');
    final razoes2 = <double>[];
    for (final e in comJanela) {
      final hoje = (e['deLiquida'] as num).toDouble();
      final jan = (e['deJanela'] as num).toDouble();
      final tau = (e['aliquota'] as num).toDouble();
      final fh = BetaShrinkage.leverageFactor(debtToEquity: hoje, taxRate: tau);
      final fj = BetaShrinkage.leverageFactor(debtToEquity: jan, taxRate: tau);
      if (fh == null || fj == null || fh <= 0) continue;
      razoes2.add(fj / fh);
    }
    razoes2.sort();
    if (razoes2.isNotEmpty) {
      stdout.writeln('  fator da janela ÷ fator de hoje: '
          'p10=${razoes2[(razoes2.length * 0.1).floor()].toStringAsFixed(3)}  '
          'mediana=${_mediana(razoes2)!.toStringAsFixed(3)}  '
          'p90=${razoes2[(razoes2.length * 0.9).floor()].toStringAsFixed(3)}');
      stdout.writeln('  distante mais de 10%: '
          '${razoes2.where((x) => (x - 1).abs() > 0.10).length}  '
          'mais de 25%: ${razoes2.where((x) => (x - 1).abs() > 0.25).length}');
      stdout.writeln('  a janela é MAIS alavancada em '
          '${razoes2.where((x) => x > 1).length} de ${razoes2.length}');
    }
    final ord2 = [...comJanela]..sort((a, b) =>
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

  final desvios = <({String ticker, double razao})>[];
  for (final e in l) {
    final vm = (e['valorDeMercado'] as num).toDouble();
    final alt = (e['vmPorPrecoEAcoes'] as num?)?.toDouble();
    if (alt == null || alt <= 0 || vm <= 0) continue;
    desvios.add((ticker: e['ticker'] as String, razao: alt / vm));
  }
  if (desvios.isNotEmpty) {
    final rs = [for (final d in desvios) d.razao]..sort();
    stdout.writeln('\n-- o valor de mercado publicado confere? --');
    stdout.writeln('  preço × ações ÷ marketCap: '
        'p10=${rs[(rs.length * 0.1).floor()].toStringAsFixed(3)}  '
        'mediana=${_mediana(rs)!.toStringAsFixed(3)}  '
        'p90=${rs[(rs.length * 0.9).floor()].toStringAsFixed(3)}');
    stdout.writeln('  fora de [0,9; 1,1]: '
        '${rs.where((x) => x < 0.9 || x > 1.1).length} de ${rs.length}  '
        'fora de [0,5; 2,0]: '
        '${rs.where((x) => x < 0.5 || x > 2.0).length}');
    final piores2 = [...desvios]
      ..sort((a, b) => b.razao.compareTo(a.razao));
    for (final d in piores2.take(6)) {
      stdout.writeln('    ${d.ticker.padRight(8)} '
          '${d.razao.toStringAsFixed(1)}×');
    }
  }

  final piores = [...l]..sort((a, b) => (b['razaoDosFatores'] as num)
      .compareTo(a['razaoDosFatores'] as num));
  stdout.writeln('\n-- onde a distância é maior --');
  stdout.writeln('  ${"ativo".padRight(8)}${"D/E bruta".padLeft(11)}'
      '${"D/E líq".padLeft(10)}${"ida÷volta".padLeft(11)}');
  for (final e in piores.take(10)) {
    stdout.writeln('  ${(e['ticker'] as String).padRight(8)}'
        '${_pc((e['deBruta'] as num).toDouble()).padLeft(11)}'
        '${_pc((e['deLiquida'] as num).toDouble()).padLeft(10)}'
        '${(e['razaoDosFatores'] as num).toStringAsFixed(3).padLeft(11)}');
  }
}
