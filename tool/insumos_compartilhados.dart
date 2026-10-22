// A1 — quanto da discordância entre as vias vem de medir a mesma coisa duas
// vezes?
//
// **A pergunta.** [`vias.md`](../docs/validacao/vias.md) mediu que as duas vias
// discordam além de 1,5× em 55 de 92 ativos. A
// [decisão 38](../docs/decisoes/038-transicao-continua-entre-as-vias.md) removeu
// o degrau que essa discordância produzia, e **não** a discordância. Antes de
// decidir se conciliá-las exige reconstruir a Porta 2, é preciso saber de onde
// ela vem.
//
// **A hipótese testável.** Uma empresa tem **um** crescimento e **uma** posição
// no ciclo. As duas vias os medem separadamente — sobre capital investido de um
// lado e patrimônio do outro — e chegam a números diferentes: mais de 3 p.p. de
// diferença no crescimento em 43 de 92, e fator de normalização fora de
// [0,8; 1,25] em 34. Se a discordância entre os preços justos colapsar ao impor
// os mesmos dois insumos, ela é do **medidor**, e o conserto é amarrá-los. Se
// não colapsar, ela é estrutural, e amarrar não resolve.
//
// **O que NÃO se compartilha, e é deliberado.** O retorno sobre o capital
// difere legitimamente entre as vias — ROE excede ROIC quando há alavancagem —,
// e a taxa de desconto também: WACC e Ke descontam fluxos diferentes. Impor
// esses seria apagar a economia do problema em vez de medi-la.
//
// **O empréstimo roda nos dois sentidos.** Compartilhar os insumos da firma e
// compartilhar os do acionista são experimentos diferentes, e concluir a partir
// de um só confundiria "a discordância colapsa" com "a via da firma tem razão".
//
// Uso:
//   dart run tool/insumos_compartilhados.dart
//   dart run tool/insumos_compartilhados.dart --limit 30
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

/// Avalia forçando a via, e opcionalmente o crescimento e o fator de base.
({double fairValue, double growth, double factor})? _evaluate(
  ValuationInputs base,
  ValuationLane lane, {
  double? growth,
  double? factor,
}) {
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
    laneOverride: lane,
    growthOverride: growth,
    baseFactorOverride: factor,
  ));
  if (r.isErr) return null;
  final v = r.unwrap();
  if (v.fairValue.reais <= 0) return null;
  return (
    fairValue: v.fairValue.reais,
    growth: v.diagnostics!.growthRate,
    factor: v.diagnostics!.baseFactor,
  );
}

/// Razão entre as duas vias sob um conjunto de insumos, ou `null`.
double? _ratio(
  ValuationInputs inputs, {
  double? growth,
  double? factor,
}) {
  final f = _evaluate(inputs, ValuationLane.firm,
      growth: growth, factor: factor);
  final a = _evaluate(inputs, ValuationLane.shareholder,
      growth: growth, factor: factor);
  if (f == null || a == null || a.fairValue <= 0) return null;
  return f.fairValue / a.fairValue;
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Resumo da dispersão de um conjunto de razões.
///
/// A medida central é a **mediana de `|ln razão|`**: razão é grandeza
/// multiplicativa, e 0,5× e 2,0× são a mesma discordância em direções opostas.
/// Média de razões trataria as duas de forma diferente.
({double medianAbsLog, int outside15, int outside20, int n}) _dispersion(
  List<double> ratios,
) {
  final logs = [
    for (final r in ratios)
      if (r > 0 && r.isFinite) math.log(r).abs(),
  ];
  return (
    medianAbsLog: _median(logs) ?? double.nan,
    outside15: ratios.where((r) => r > 1.5 || r < 1 / 1.5).length,
    outside20: ratios.where((r) => r > 2 || r < 0.5).length,
    n: ratios.length,
  );
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
      );
      if (prep.isErr) continue;
      final inputs = prep.unwrap();

      final firm = _evaluate(inputs, ValuationLane.firm);
      final shareholder = _evaluate(inputs, ValuationLane.shareholder);
      if (firm == null || shareholder == null) continue;

      final r0 = firm.fairValue / shareholder.fairValue;

      output.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'preco': inputs.marketPrice,
        'justoFirma': firm.fairValue,
        'justoAcionista': shareholder.fairValue,
        'crescimentoFirma': firm.growth,
        'crescimentoAcionista': shareholder.growth,
        'fatorFirma': firm.factor,
        'fatorAcionista': shareholder.factor,
        'razaoAtual': r0,
        // Empréstimo no sentido firma → acionista.
        'razaoCrescimentoDaFirma':
            _ratio(inputs, growth: firm.growth),
        'razaoFatorDaFirma': _ratio(inputs, factor: firm.factor),
        'razaoAmbosDaFirma':
            _ratio(inputs, growth: firm.growth, factor: firm.factor),
        // E no sentido inverso, para separar "colapsa" de "a firma tem razão".
        'razaoAmbosDoAcionista': _ratio(
          inputs,
          growth: shareholder.growth,
          factor: shareholder.factor,
        ),
      });
    }
    stderr.writeln('');

    File('docs/validacao/insumos_compartilhados.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output);
    stderr.writeln('\nescrito docs/validacao/insumos_compartilhados.json '
        '(${output.length})');
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

  stdout.writeln('\n=== A1 — INSUMOS COMPARTILHADOS — ${l.length} ativos ===\n');

  // Quanto os dois insumos divergem entre as vias, para dimensionar o teste.
  final dg = [
    for (final e in l)
      ((e['crescimentoFirma'] as num) - (e['crescimentoAcionista'] as num))
          .toDouble(),
  ];
  final df = [
    for (final e in l)
      // Guarda por magnitude: o fator é `double`, e um denominador de 1e-16
      // passaria por um teste de zero cravado e devolveria razão absurda.
      if ((e['fatorAcionista'] as num).abs() > 1e-9)
        ((e['fatorFirma'] as num) / (e['fatorAcionista'] as num)).toDouble(),
  ];
  stdout.writeln('-- o quanto os insumos divergem --');
  stdout.writeln('  crescimento (firma − acionista): '
      'mediana=${((_median(dg) ?? 0) * 100).toStringAsFixed(2)} p.p.   '
      '|dif| > 3 p.p. em ${dg.where((x) => x.abs() > 0.03).length} de ${dg.length}');
  stdout.writeln('  fator (firma ÷ acionista): '
      'mediana=${(_median(df) ?? 0).toStringAsFixed(2)}x   '
      'fora de [0,8; 1,25] em '
      '${df.where((x) => x < 0.8 || x > 1.25).length} de ${df.length}');

  void row(String label, String key) {
    final d = _dispersion(col(key));
    if (d.n == 0) {
      stdout.writeln('  ${label.padRight(34)} —');
      return;
    }
    stdout.writeln('  ${label.padRight(34)} '
        'mediana|ln r|=${d.medianAbsLog.toStringAsFixed(3)}  '
        'fora de 1,5x: ${d.outside15.toString().padLeft(3)}/${d.n}  '
        'fora de 2x: ${d.outside20.toString().padLeft(3)}/${d.n}');
  }

  stdout.writeln('\n-- dispersão da razão entre as vias --');
  row('como está hoje', 'razaoAtual');
  row('só o crescimento da firma', 'razaoCrescimentoDaFirma');
  row('só o fator da firma', 'razaoFatorDaFirma');
  row('ambos, da firma', 'razaoAmbosDaFirma');
  row('ambos, do acionista', 'razaoAmbosDoAcionista');

  // O veredito quantitativo: quanto da dispersão colapsa.
  final base = _dispersion(col('razaoAtual'));
  for (final e in const [
    ('ambos, da firma', 'razaoAmbosDaFirma'),
    ('ambos, do acionista', 'razaoAmbosDoAcionista'),
  ]) {
    final d = _dispersion(col(e.$2));
    if (d.n == 0 || !base.medianAbsLog.isFinite) continue;
    final collapse = 1 - d.medianAbsLog / base.medianAbsLog;
    stdout.writeln('\n  colapso com "${e.$1}": '
        '${(collapse * 100).toStringAsFixed(1)}% da dispersão mediana');
  }
}
