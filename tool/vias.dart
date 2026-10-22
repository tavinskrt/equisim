// A discordância entre as duas vias, medida ativo a ativo.
//
// **A pergunta.** A pós-condição da ponte de equity escolhe entre a via da
// firma e a do acionista por um limiar — 20% de participação do capital
// próprio. A [decisão 37](../docs/decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md)
// mostrou que a escolha decide muito: nove ativos trocaram de via ao receber a
// alíquota certa, e caíram de 58,9% a 92,1%. Na VBBR3 as duas vias diferem por
// 12,7×.
//
// A [decisão 34](../docs/decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
// registrou isso e não o resolveu: "Isto não concilia as duas vias, que seguem
// discordando por medirem crescimento e base em séries de capital diferentes".
// Conciliar exige primeiro saber o tamanho e a forma da discordância.
//
// **Em teoria elas não deveriam discordar.** `FCFF/WACC` e `FCFE/Ke` são a
// mesma avaliação vista de dois lados, e coincidem quando os insumos são
// consistentes entre si. A distância entre elas é, portanto, uma medida direta
// de **inconsistência interna do motor** — e não uma diferença de método.
//
// Uso:
//   dart run tool/vias.dart
//   dart run tool/vias.dart --limit 30
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

/// Avalia o ativo forçando uma via, sem roteamento e sem migração.
({
  double fairValue,
  double growth,
  double returnRate,
  double discount,
  double terminalDiscount,
  double baseFactor,
  double stake,
  double terminalWeight,
  bool resolvedFlag,
})? _byLane(ValuationInputs base, ValuationLane lane) {
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
    // Sem isto a via da firma aqui seria a **anterior** às decisões 41 a 44:
    // interpolação de dois pontos e ponte `EV − D`. A comparação mediria
    // o motor velho contra a via do acionista.
    unleveredBeta: base.unleveredBeta,
    laneOverride: lane,
  ));
  if (r.isErr) return null;
  final v = r.unwrap();
  final d = v.diagnostics!;
  if (v.fairValue.reais <= 0) return null;
  return (
    fairValue: v.fairValue.reais,
    growth: d.growthRate,
    returnRate: d.returnOnCapital,
    discount: v.discountRate,
    terminalDiscount: d.terminalDiscountRate,
    baseFactor: d.baseFactor,
    stake: d.equityShare,
    terminalWeight: d.terminalShare,
    // O aviso da decisão 42 é quem declara qual dos dois caminhos valeu.
    resolvedFlag: v.warnings.any((a) => a.contains('resolvido ano a ano')),
  );
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

Future<void> main(List<String> args) async {
  final limitIndex = args.indexOf('--limit');
  final limit = limitIndex >= 0 ? int.tryParse(args[limitIndex + 1]) ?? 0 : 0;

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (limit > 0 && universe.length > limit) {
      universe = universe.sublist(0, limit);
    }

    // O prior do beta é o que dá à via da firma o caminho de taxas resolvido
    // das decisões 41 a 44. Sem ele, esta medição compararia a via do
    // acionista contra a firma **antiga**.
    final prior = await ResolveBetaPrior.call(
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: _today,
    );
    stderr.writeln(prior == null
        ? 'sem prior de beta: a via da firma fica na interpolação'
        : 'prior de beta: ${prior.unleveredBySector.length} setores');

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

      final production = ValuationCascade.evaluate(inputs);
      if (production.isErr) continue;
      final p = production.unwrap();

      final firm = _byLane(inputs, ValuationLane.firm);
      final shareholder = _byLane(inputs, ValuationLane.shareholder);
      if (firm == null || shareholder == null) continue;

      final ratio = firm.fairValue / shareholder.fairValue;

      output.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'preco': inputs.marketPrice,
        'viaProducao': p.model.name,
        'justoProducao': p.fairValue.reais,
        'justoFirma': firm.fairValue,
        'justoAcionista': shareholder.fairValue,
        'razaoFirmaAcionista': ratio,
        'participacaoFirma': firm.stake,
        // As três fontes de divergência que a decisão 34 nomeou.
        'crescimentoFirma': firm.growth,
        'crescimentoAcionista': shareholder.growth,
        'retornoFirma': firm.returnRate,
        'retornoAcionista': shareholder.returnRate,
        'fatorBaseFirma': firm.baseFactor,
        'fatorBaseAcionista': shareholder.baseFactor,
        'descontoFirma': firm.discount,
        'descontoAcionista': shareholder.discount,
        'pesoTerminalFirma': firm.terminalWeight,
        'pesoTerminalAcionista': shareholder.terminalWeight,
        // Qual das duas o preço de mercado prefere.
        'erroFirma': (firm.fairValue / inputs.marketPrice - 1).abs(),
        'erroAcionista': (shareholder.fairValue / inputs.marketPrice - 1).abs(),
        // **A pergunta que D2 faz depois da decisão 43.** A discordância só é
        // defeito onde ela decide: onde o motor tem as duas vias disponíveis e
        // escolhe uma.
        'temBetaU': inputs.unleveredBeta != null,
        'firmaResolvida': firm.resolvedFlag,
        'mesclado': p.diagnostics!.caveats
            .contains(ValuationCaveat.mergedLanes),
        'migrou': p.diagnostics!.caveats.contains(ValuationCaveat.migratedLane),
      });
    }
    stderr.writeln('');

    File('docs/validacao/vias.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output);
    stderr.writeln('\nescrito docs/validacao/vias.json (${output.length})');
  } finally {
    await ctx.dispose();
  }
}

void _printReport(List<Map<String, dynamic>> l) {
  if (l.isEmpty) {
    stdout.writeln('nenhum ativo com as duas vias avaliáveis');
    return;
  }
  List<double> col(String k) => [
        for (final e in l)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble(),
      ];
  String pc(double? x) => x == null ? '—' : '${(x * 100).toStringAsFixed(1)}%';

  stdout.writeln('\n=== DISCORDÂNCIA ENTRE AS VIAS — ${l.length} ativos '
      'com as duas avaliáveis ===\n');

  final r = col('razaoFirmaAcionista')..sort();
  stdout.writeln('-- razão justo(firma) ÷ justo(acionista) --');
  stdout.writeln('  p10=${r[r.length ~/ 10].toStringAsFixed(2)}x  '
      'p25=${r[r.length ~/ 4].toStringAsFixed(2)}x  '
      'mediana=${_median(r)!.toStringAsFixed(2)}x  '
      'p75=${r[3 * r.length ~/ 4].toStringAsFixed(2)}x  '
      'p90=${r[9 * r.length ~/ 10].toStringAsFixed(2)}x');
  final outside2 = r.where((x) => x > 2 || x < 0.5).length;
  final outside15 = r.where((x) => x > 1.5 || x < 1 / 1.5).length;
  stdout.writeln('  discordam além de 1,5x: $outside15 de ${r.length}   '
      'além de 2x: $outside2');

  // --- De onde vem a divergência ---
  stdout.writeln('\n-- as três fontes que a decisão 34 nomeou --');
  final dg = [
    for (final e in l)
      ((e['crescimentoFirma'] as num) - (e['crescimentoAcionista'] as num))
          .toDouble(),
  ];
  final df = [
    for (final e in l)
      ((e['fatorBaseFirma'] as num) / (e['fatorBaseAcionista'] as num))
          .toDouble(),
  ];
  final dd = [
    for (final e in l)
      ((e['descontoFirma'] as num) - (e['descontoAcionista'] as num))
          .toDouble(),
  ];
  stdout.writeln('  crescimento: firma − acionista, mediana=${pc(_median(dg))}'
      '   |dif| > 3 p.p. em ${dg.where((x) => x.abs() > 0.03).length}');
  stdout.writeln('  fator de base: firma ÷ acionista, '
      'mediana=${_median(df)!.toStringAsFixed(2)}x'
      '   fora de [0,8; 1,25] em '
      '${df.where((x) => x < 0.8 || x > 1.25).length}');
  stdout.writeln('  desconto: WACC − Ke, mediana=${pc(_median(dd))}'
      '   |dif| > 2 p.p. em ${dd.where((x) => x.abs() > 0.02).length}');

  // --- Qual via o preço prefere ---
  var firmWins = 0, shareholderWins = 0;
  for (final e in l) {
    if ((e['erroFirma'] as num) < (e['erroAcionista'] as num)) {
      firmWins++;
    } else {
      shareholderWins++;
    }
  }
  stdout.writeln('\n-- qual via fica mais perto do preço de mercado --');
  stdout.writeln('  firma: $firmWins    acionista: $shareholderWins');
  stdout.writeln('  erro |justo/preço − 1| mediano: '
      'firma=${pc(_median(col('erroFirma')))}  '
      'acionista=${pc(_median(col('erroAcionista')))}');

  // --- A discordância ainda decide? ---
  //
  // Ela só é defeito onde decide: onde o motor tem as duas vias disponíveis e
  // escolhe uma. Com a rota derivada da decisão 43 a via da firma não migra
  // mais, e o roteamento por Porta 1 e Porta 3 não é escolha entre
  // alternativas — é a única opção disponível para aquele ativo.
  final withBeta = l.where((e) => e['firmaResolvida'] == true).length;
  final merged = l.where((e) => e['mesclado'] == true).length;
  final migrated = l.where((e) => e['migrou'] == true).length;
  stdout.writeln('\n-- a discordância ainda DECIDE alguma coisa? --');
  stdout.writeln('  com caminho resolvido (rota derivada): $withBeta de '
      '${l.length}');
  stdout.writeln('  ainda mesclados (dois estimadores):    $merged');
  stdout.writeln('  ainda migrados:                        $migrated');

  // --- A faixa exposta ao limiar ---
  final exposed = [
    for (final e in l)
      if ((e['participacaoFirma'] as num) < 0.35 &&
          (e['participacaoFirma'] as num) > 0.05)
        e,
  ]..sort((a, b) => (a['participacaoFirma'] as num)
      .compareTo(b['participacaoFirma'] as num));
  stdout.writeln('\n-- ativos na faixa exposta (participação entre 5% e 35%) --');
  stdout.writeln('  ${exposed.length} ativos');
  for (final e in exposed.take(20)) {
    stdout.writeln('    ${(e['ticker'] as String).padRight(7)} '
        's=${pc((e['participacaoFirma'] as num).toDouble()).padLeft(6)}  '
        'firma=${(e['justoFirma'] as num).toStringAsFixed(2).padLeft(8)}  '
        'acionista=${(e['justoAcionista'] as num).toStringAsFixed(2).padLeft(8)}'
        '  razão=${(e['razaoFirmaAcionista'] as num).toStringAsFixed(2)}x'
        '  produção=${e['viaProducao']}');
  }
}
