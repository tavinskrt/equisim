// D2b — o destino da via do acionista sobre LPA.
//
// **A pergunta.** A [decisão 45](../docs/decisoes/045-estrutura-de-capital-recusada.md)
// tirou da via do acionista o papel de segundo estimador: nos 90 ativos em que
// as duas vias são calculáveis, nenhum resultado mescla e nenhum migra. Ela
// continua, porém, sendo **a única via** para instituição financeira (Porta 1),
// para quem não sustenta lucro operacional (Porta 3) e para quem tem a
// estrutura de capital recusada. Nesses ela decide sozinha.
//
// **A inconsistência a medir.** Desde a decisão 41 a via da firma resolve o
// custo do capital próprio ano a ano contra a alavancagem que a própria
// avaliação produz. A via do acionista não: ela desconta ao `Ke` do CAPM com o
// beta alavancado de hoje, e supõe essa alavancagem perene. **O motor tem dois
// custos de capital próprio para o mesmo ativo**, e nunca os comparou.
//
// Uso:
//   dart run tool/via_acionista.dart
//   dart run tool/via_acionista.dart --limit 30
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

/// Avalia o ativo forçando uma via, sem roteamento e sem migração.
ValuationResult? _porVia(ValuationInputs base, ValuationLane via) {
  final r = ValuationCascade.evaluate(ValuationInputs(
    ticker: base.ticker,
    asOf: base.asOf,
    fundamentals: base.fundamentals,
    marketPrice: base.marketPrice,
    capm: base.capm,
    marginOfSafety: base.marginOfSafety,
    projectionYears: base.projectionYears,
    perpetualGrowthCap: base.perpetualGrowthCap,
    sectorKey: base.sectorKey,
    industry: base.industry,
    inflation: base.inflation,
    declaredTerminalRiskFreeRate: base.declaredTerminalRiskFreeRate,
    prices: base.prices,
    isDistressed: base.isDistressed,
    unleveredBeta: base.unleveredBeta,
    laneOverride: via,
  ));
  return r.isOk ? r.unwrap() : null;
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1)}%';
String _pp(double v) => '${(v * 100).toStringAsFixed(2)} p.p.';

Future<void> main(List<String> args) async {
  final limiteIdx = args.indexOf('--limit');
  final limite = limiteIdx >= 0 ? int.tryParse(args[limiteIdx + 1]) ?? 0 : 0;

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (limite > 0 && universe.length > limite) {
      universe = universe.sublist(0, limite);
    }

    final prior = await ResolveBetaPrior.call(
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    );

    final saida = <Map<String, dynamic>>[];
    var i = 0;
    var recusados = 0;
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

      final producao = ValuationCascade.evaluate(inputs);
      if (producao.isErr) {
        recusados++;
        continue;
      }
      final p = producao.unwrap();

      // Qual porta mandou o ativo para a via do acionista.
      final financeira =
          p.warnings.any((w) => w.startsWith('Instituição financeira:'));
      final fluxoFraco = p.warnings
          .any((w) => w.startsWith('O lucro operacional não se sustenta'));
      final estruturaRecusada =
          p.warnings.any((w) => w.contains('não sustenta a via da firma'));

      // O `Ke` que cada via usa, para o mesmo ativo.
      final firma = _porVia(inputs, ValuationLane.firm);
      final acionista = _porVia(inputs, ValuationLane.shareholder);

      saida.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'preco': inputs.marketPrice,
        'viaProducao': p.model.name,
        'justoProducao': p.fairValue.reais,
        'potencial': p.upside,
        'porta1Financeira': financeira,
        'porta3FluxoFraco': fluxoFraco,
        'estruturaRecusada': estruturaRecusada,
        'temBetaU': inputs.unleveredBeta != null,
        // Desde a decisão 46 a via do acionista resolve o próprio `Ke` contra
        // a alavancagem — menos em instituição financeira, onde a captação é
        // insumo do negócio e a realavancagem não teria sentido. Onde não
        // resolve, o `Ke` abaixo é o do CAPM sobre o beta alavancado de hoje,
        // suposto perene.
        'keAcionistaResolvido': acionista?.warnings
                .any((w) => w.contains('resolvido ano a ano')) ??
            false,
        'keAcionistaAno1': acionista?.discountRate,
        'keAcionistaTerminal': acionista?.diagnostics?.terminalDiscountRate,
        // `Ke` resolvido contra a alavancagem, quando a via da firma o produz.
        'keResolvidoTerminal': firma?.diagnostics?.terminalCostOfEquity,
        'waccResolvidoTerminal': firma?.diagnostics?.terminalDiscountRate,
        'justoFirma': firma?.fairValue.reais,
        'justoAcionista': acionista?.fairValue.reais,
      });
    }
    stderr.writeln('');

    File('docs/validacao/via_acionista.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida, recusados);
    stderr.writeln(
        '\nescrito docs/validacao/via_acionista.json (${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l, int recusados) {
  stdout.writeln('\n=== D2b — A VIA DO ACIONISTA — ${l.length} avaliados '
      '($recusados recusados) ===\n');

  final porAcionista =
      l.where((e) => e['viaProducao'] == 'dcfEarnings').toList();
  final p1 = porAcionista.where((e) => e['porta1Financeira'] == true).length;
  final p3 = porAcionista.where((e) => e['porta3FluxoFraco'] == true).length;
  final rec = porAcionista.where((e) => e['estruturaRecusada'] == true).length;

  stdout.writeln('-- quem a via do acionista avalia em produção --');
  stdout.writeln(
      '  pela via do acionista: ${porAcionista.length} de ${l.length}');
  stdout.writeln('    Porta 1 (instituição financeira): $p1');
  stdout.writeln('    Porta 3 (lucro operacional não sustentado): $p3');
  stdout.writeln('    estrutura de capital recusada: $rec');
  stdout.writeln(
      '    sem porta declarada: ${porAcionista.length - p1 - p3 - rec}');

  // A inconsistência: dois `Ke` para o mesmo ativo.
  final comOsDois = [
    for (final e in l)
      if (e['keAcionistaTerminal'] != null && e['keResolvidoTerminal'] != null)
        e
  ];
  final resolvidosAcionista =
      l.where((e) => e['keAcionistaResolvido'] == true).length;
  stdout.writeln('\n-- a via do acionista resolve o próprio Ke? --');
  stdout.writeln('  resolvem: $resolvidosAcionista de ${l.length}');
  stdout.writeln('    entre os que ela avalia em produção: '
      '${porAcionista.where((e) => e['keAcionistaResolvido'] == true).length} '
      'de ${porAcionista.length}');
  stdout.writeln('    instituição financeira (exceção declarada): $p1');

  stdout.writeln('\n-- dois custos de capital próprio para o mesmo ativo --');
  stdout.writeln('  ativos com os dois medidos: ${comOsDois.length}');
  if (comOsDois.isNotEmpty) {
    final delta = [
      for (final e in comOsDois)
        (e['keResolvidoTerminal'] as num).toDouble() -
            (e['keAcionistaTerminal'] as num).toDouble()
    ];
    final ordenado = [...delta]..sort();
    double q(double f) => ordenado[((ordenado.length - 1) * f).round()];
    stdout.writeln('  Ke resolvido − Ke do CAPM (equilíbrio):');
    stdout.writeln('    p10=${_pp(q(0.10))}  mediana=${_pp(_mediana(delta)!)}  '
        'p90=${_pp(q(0.90))}');
    stdout.writeln('    |dif| > 1 p.p. em '
        '${delta.where((d) => d.abs() > 0.01).length} de ${delta.length}   '
        '> 3 p.p. em ${delta.where((d) => d.abs() > 0.03).length}');
    stdout.writeln('    o resolvido é MAIOR em '
        '${delta.where((d) => d > 0).length} de ${delta.length}');
  }

  // Nos que a via do acionista decide sozinha, o Ke resolvido existe?
  final decideSozinha =
      porAcionista.where((e) => e['porta1Financeira'] != true).toList();
  final comResolvido =
      decideSozinha.where((e) => e['keResolvidoTerminal'] != null).length;
  stdout.writeln(
      '\n-- onde a via do acionista decide sozinha, fora da Porta 1 --');
  stdout.writeln('  ativos: ${decideSozinha.length}');
  stdout.writeln('  com Ke resolvido disponível (a via da firma o produz): '
      '$comResolvido');
  if (decideSozinha.isNotEmpty) {
    final d = [
      for (final e in decideSozinha)
        if (e['keResolvidoTerminal'] != null &&
            e['keAcionistaTerminal'] != null)
          (e['keResolvidoTerminal'] as num).toDouble() -
              (e['keAcionistaTerminal'] as num).toDouble()
    ];
    if (d.isNotEmpty) {
      stdout.writeln('  Ke resolvido − Ke do CAPM: mediana='
          '${_pp(_mediana(d)!)}   |dif| > 1 p.p. em '
          '${d.where((x) => x.abs() > 0.01).length} de ${d.length}');
    }
    stdout.writeln('  os que decide sozinha:');
    final ord = [...decideSozinha]..sort((a, b) => ((b['potencial'] as num?) ?? 0)
        .compareTo((a['potencial'] as num?) ?? 0));
    for (final e in ord.take(15)) {
      final ke = e['keAcionistaTerminal'] as num?;
      final kr = e['keResolvidoTerminal'] as num?;
      stdout.writeln('    ${(e['ticker'] as String).padRight(7)} '
          'potencial=${_pc(((e['potencial'] as num?) ?? 0).toDouble()).padLeft(8)}  '
          'Ke=${ke == null ? "  —  " : _pc(ke.toDouble()).padLeft(6)}  '
          'Ke*=${kr == null ? "  —  " : _pc(kr.toDouble()).padLeft(6)}  '
          '${e['porta3FluxoFraco'] == true ? "porta3" : ""}'
          '${e['estruturaRecusada'] == true ? "recusada" : ""}');
    }
  }
}
