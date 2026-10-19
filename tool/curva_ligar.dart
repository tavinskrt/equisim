// A2 — a curva de juros observada ligada ao motor, e o que ela move.
//
// Avalia o universo duas vezes na mesma data, com os mesmos fundamentos da
// fonte de mercado — para isolar o efeito da curva do efeito da CVM:
//
//   dois pontos  CDI corrente decaindo até a média decenal do CDI (antes)
//   curva        forwards de um ano da curva prefixada do Tesouro (A2)
//
// Uso:
//   python tool/tesouro_baixar.py
//   dart run tool/curva_ligar.dart [AAAA-MM-DD]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

/// Lê o CSV do Tesouro Direto pelo leitor do núcleo (`TreasuryCsv`), o mesmo
/// que o aplicativo e o empacotador usam.
List<TreasuryQuote> readTreasury(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('$path não existe. Rode: python tool/tesouro_baixar.py');
    exit(2);
  }
  return TreasuryCsv.parse(
      const LineSplitter().convert(latin1.decode(f.readAsBytesSync())));
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _spearman(List<double> a, List<double> b) {
  List<double> ranks(List<double> v) {
    final idx = List.generate(v.length, (i) => i)..sort((x, y) => v[x].compareTo(v[y]));
    final r = List<double>.filled(v.length, 0);
    for (var k = 0; k < idx.length; k++) {
      r[idx[k]] = k + 1.0;
    }
    return r;
  }

  final ranksA = ranks(a), ranksB = ranks(b);
  final meanA = ranksA.reduce((x, y) => x + y) / ranksA.length;
  final meanB = ranksB.reduce((x, y) => x + y) / ranksB.length;
  var n = 0.0, sumSqA = 0.0, sumSqB = 0.0;
  for (var i = 0; i < ranksA.length; i++) {
    n += (ranksA[i] - meanA) * (ranksB[i] - meanB);
    sumSqA += (ranksA[i] - meanA) * (ranksA[i] - meanA);
    sumSqB += (ranksB[i] - meanB) * (ranksB[i] - meanB);
  }
  // Sem variância numa das duas não há correlação a medir.
  if (!(sumSqA > 0 && sumSqB > 0)) return 0;
  return n / math.sqrt(sumSqA * sumSqB);
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

Future<void> main(List<String> args) async {
  final today = args.isEmpty ? DateTime(2026, 9, 4) : DateTime.parse(args.first);
  final quotes = readTreasury('data/tesouro/precotaxatesourodireto.csv');
  final curve = TreasuryCurve.at(quotes, today);
  if (curve == null) {
    stderr.writeln('sem curva do Tesouro na semana de $today');
    exit(2);
  }

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stdout.writeln('== A2 — avaliação em ${today.toIso8601String().substring(0, 10)} ==\n');
    stdout.writeln('  curva de ${curve.referenceDate.toIso8601String().substring(0, 10)}, '
        '${curve.vertices.length} vértices até '
        '${curve.vertices.last.years.toStringAsFixed(1)} anos');
    final fw = curve.annualForwards(10);
    stdout.writeln('  forwards anuais: ${[for (final f in fw) _pc(f)].join(" ")}');
    stdout.writeln('  perpetuidade pela curva: ${_pc(curve.terminalRate(10))}');
    stdout.writeln('  motor de dois pontos: ${_pc(anchors.currentRiskFreeRate)} '
        '→ ${_pc(anchors.riskFreeCagr)}\n');

    final universe = (await ctx.fundamentals.universe()).unwrap();
    Future<ValuationResult?> evaluate(Ticker t, {YieldCurve? c}) async {
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: c,
        projectionYears: 10,
      );
      if (prep.isErr) return null;
      final r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    }

    final rows = <Map<String, Object?>>[];
    var i = 0;
    for (final t in universe) {
      if (++i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final a = await evaluate(t);
      final b = await evaluate(t, c: curve);
      if (a == null && b == null) continue;
      rows.add({
        'ticker': t.value,
        'doisPontos': a?.upside,
        'curva': b?.upside,
        'pesoTerminal': b?.diagnostics?.terminalShare,
      });
    }
    stderr.writeln('');

    final both = [
      for (final l in rows)
        if (l['doisPontos'] != null && l['curva'] != null) l,
    ];
    final before = [for (final l in both) l['doisPontos']! as double];
    final after = [for (final l in both) l['curva']! as double];
    stdout.writeln('  avaliados: ${rows.where((l) => l['doisPontos'] != null).length}'
        ' → ${rows.where((l) => l['curva'] != null).length}');
    stdout.writeln('  perdidos: ${[for (final l in rows) if (l['doisPontos'] != null && l['curva'] == null) l['ticker']].join(" ")}');
    stdout.writeln('  ganhos: ${[for (final l in rows) if (l['doisPontos'] == null && l['curva'] != null) l['ticker']].join(" ")}');
    stdout.writeln('  potencial mediano: ${_pc(_median(before))} → ${_pc(_median(after))}');
    stdout.writeln('  fração com potencial positivo: '
        '${_pc(before.isEmpty ? null : before.where((x) => x > 0).length / before.length)} → '
        '${_pc(after.isEmpty ? null : after.where((x) => x > 0).length / after.length)}');
    stdout.writeln('  mediana do Δ: ${_pc(_median([for (var k = 0; k < both.length; k++) after[k] - before[k]]))}');
    stdout.writeln('  Spearman entre as duas ordenações: '
        '${_spearman(before, after).toStringAsFixed(4)}');

    File('docs/validacao/curva_ligacao_${today.toIso8601String().substring(0, 10)}.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
  } finally {
    await ctx.dispose();
  }
}
