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

final _hoje = DateTime(2026, 9, 4);

/// Avalia forçando a via, e opcionalmente o crescimento e o fator de base.
({double justo, double crescimento, double fator})? _avaliar(
  ValuationInputs base,
  ValuationLane via, {
  double? crescimento,
  double? fator,
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
    laneOverride: via,
    growthOverride: crescimento,
    baseFactorOverride: fator,
  ));
  if (r.isErr) return null;
  final v = r.unwrap();
  if (v.fairValue.reais <= 0) return null;
  return (
    justo: v.fairValue.reais,
    crescimento: v.diagnostics!.growthRate,
    fator: v.diagnostics!.baseFactor,
  );
}

/// Razão entre as duas vias sob um conjunto de insumos, ou `null`.
double? _razao(
  ValuationInputs inputs, {
  double? crescimento,
  double? fator,
}) {
  final f = _avaliar(inputs, ValuationLane.firm,
      crescimento: crescimento, fator: fator);
  final a = _avaliar(inputs, ValuationLane.shareholder,
      crescimento: crescimento, fator: fator);
  if (f == null || a == null || a.justo <= 0) return null;
  return f.justo / a.justo;
}

double? _mediana(List<double> v) {
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
({double medianaAbsLog, int fora15, int fora20, int n}) _dispersao(
  List<double> razoes,
) {
  final logs = [
    for (final r in razoes)
      if (r > 0 && r.isFinite) math.log(r).abs(),
  ];
  return (
    medianaAbsLog: _mediana(logs) ?? double.nan,
    fora15: razoes.where((r) => r > 1.5 || r < 1 / 1.5).length,
    fora20: razoes.where((r) => r > 2 || r < 0.5).length,
    n: razoes.length,
  );
}

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
      );
      if (prep.isErr) continue;
      final inputs = prep.unwrap();

      final firma = _avaliar(inputs, ValuationLane.firm);
      final acionista = _avaliar(inputs, ValuationLane.shareholder);
      if (firma == null || acionista == null) continue;

      final r0 = firma.justo / acionista.justo;

      saida.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'preco': inputs.marketPrice,
        'justoFirma': firma.justo,
        'justoAcionista': acionista.justo,
        'crescimentoFirma': firma.crescimento,
        'crescimentoAcionista': acionista.crescimento,
        'fatorFirma': firma.fator,
        'fatorAcionista': acionista.fator,
        'razaoAtual': r0,
        // Empréstimo no sentido firma → acionista.
        'razaoCrescimentoDaFirma':
            _razao(inputs, crescimento: firma.crescimento),
        'razaoFatorDaFirma': _razao(inputs, fator: firma.fator),
        'razaoAmbosDaFirma':
            _razao(inputs, crescimento: firma.crescimento, fator: firma.fator),
        // E no sentido inverso, para separar "colapsa" de "a firma tem razão".
        'razaoAmbosDoAcionista': _razao(
          inputs,
          crescimento: acionista.crescimento,
          fator: acionista.fator,
        ),
      });
    }
    stderr.writeln('');

    File('docs/validacao/insumos_compartilhados.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida);
    stderr.writeln('\nescrito docs/validacao/insumos_compartilhados.json '
        '(${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l) {
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
      'mediana=${((_mediana(dg) ?? 0) * 100).toStringAsFixed(2)} p.p.   '
      '|dif| > 3 p.p. em ${dg.where((x) => x.abs() > 0.03).length} de ${dg.length}');
  stdout.writeln('  fator (firma ÷ acionista): '
      'mediana=${(_mediana(df) ?? 0).toStringAsFixed(2)}x   '
      'fora de [0,8; 1,25] em '
      '${df.where((x) => x < 0.8 || x > 1.25).length} de ${df.length}');

  void linha(String rotulo, String chave) {
    final d = _dispersao(col(chave));
    if (d.n == 0) {
      stdout.writeln('  ${rotulo.padRight(34)} —');
      return;
    }
    stdout.writeln('  ${rotulo.padRight(34)} '
        'mediana|ln r|=${d.medianaAbsLog.toStringAsFixed(3)}  '
        'fora de 1,5x: ${d.fora15.toString().padLeft(3)}/${d.n}  '
        'fora de 2x: ${d.fora20.toString().padLeft(3)}/${d.n}');
  }

  stdout.writeln('\n-- dispersão da razão entre as vias --');
  linha('como está hoje', 'razaoAtual');
  linha('só o crescimento da firma', 'razaoCrescimentoDaFirma');
  linha('só o fator da firma', 'razaoFatorDaFirma');
  linha('ambos, da firma', 'razaoAmbosDaFirma');
  linha('ambos, do acionista', 'razaoAmbosDoAcionista');

  // O veredito quantitativo: quanto da dispersão colapsa.
  final base = _dispersao(col('razaoAtual'));
  for (final e in const [
    ('ambos, da firma', 'razaoAmbosDaFirma'),
    ('ambos, do acionista', 'razaoAmbosDoAcionista'),
  ]) {
    final d = _dispersao(col(e.$2));
    if (d.n == 0 || !base.medianaAbsLog.isFinite) continue;
    final colapso = 1 - d.medianaAbsLog / base.medianaAbsLog;
    stdout.writeln('\n  colapso com "${e.$1}": '
        '${(colapso * 100).toStringAsFixed(1)}% da dispersão mediana');
  }
}
