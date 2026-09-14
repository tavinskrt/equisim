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
List<TreasuryQuote> lerTesouro(String caminho) {
  final f = File(caminho);
  if (!f.existsSync()) {
    stderr.writeln('$caminho não existe. Rode: python tool/tesouro_baixar.py');
    exit(2);
  }
  return TreasuryCsv.parse(
      const LineSplitter().convert(latin1.decode(f.readAsBytesSync())));
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _spearman(List<double> a, List<double> b) {
  List<double> postos(List<double> v) {
    final idx = List.generate(v.length, (i) => i)..sort((x, y) => v[x].compareTo(v[y]));
    final r = List<double>.filled(v.length, 0);
    for (var k = 0; k < idx.length; k++) {
      r[idx[k]] = k + 1.0;
    }
    return r;
  }

  final ra = postos(a), rb = postos(b);
  final ma = ra.reduce((x, y) => x + y) / ra.length;
  final mb = rb.reduce((x, y) => x + y) / rb.length;
  var n = 0.0, da = 0.0, db = 0.0;
  for (var i = 0; i < ra.length; i++) {
    n += (ra[i] - ma) * (rb[i] - mb);
    da += (ra[i] - ma) * (ra[i] - ma);
    db += (rb[i] - mb) * (rb[i] - mb);
  }
  // Sem variância numa das duas não há correlação a medir.
  if (!(da > 0 && db > 0)) return 0;
  return n / math.sqrt(da * db);
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

Future<void> main(List<String> args) async {
  final hoje = args.isEmpty ? DateTime(2026, 9, 4) : DateTime.parse(args.first);
  final quotes = lerTesouro('data/tesouro/precotaxatesourodireto.csv');
  final curva = TreasuryCurve.at(quotes, hoje);
  if (curva == null) {
    stderr.writeln('sem curva do Tesouro na semana de $hoje');
    exit(2);
  }

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stdout.writeln('== A2 — avaliação em ${hoje.toIso8601String().substring(0, 10)} ==\n');
    stdout.writeln('  curva de ${curva.referenceDate.toIso8601String().substring(0, 10)}, '
        '${curva.vertices.length} vértices até '
        '${curva.vertices.last.years.toStringAsFixed(1)} anos');
    final fw = curva.annualForwards(10);
    stdout.writeln('  forwards anuais: ${[for (final f in fw) _pc(f)].join(" ")}');
    stdout.writeln('  perpetuidade pela curva: ${_pc(curva.terminalRate(10))}');
    stdout.writeln('  motor de dois pontos: ${_pc(anchors.currentRiskFreeRate)} '
        '→ ${_pc(anchors.riskFreeCagr)}\n');

    final universe = (await ctx.fundamentals.universe()).unwrap();
    Future<ValuationResult?> avaliar(Ticker t, {YieldCurve? c}) async {
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: hoje,
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

    final linhas = <Map<String, Object?>>[];
    var i = 0;
    for (final t in universe) {
      if (++i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final a = await avaliar(t);
      final b = await avaliar(t, c: curva);
      if (a == null && b == null) continue;
      linhas.add({
        'ticker': t.value,
        'doisPontos': a?.upside,
        'curva': b?.upside,
        'pesoTerminal': b?.diagnostics?.terminalShare,
      });
    }
    stderr.writeln('');

    final ambos = [
      for (final l in linhas)
        if (l['doisPontos'] != null && l['curva'] != null) l,
    ];
    final antes = [for (final l in ambos) l['doisPontos']! as double];
    final depois = [for (final l in ambos) l['curva']! as double];
    stdout.writeln('  avaliados: ${linhas.where((l) => l['doisPontos'] != null).length}'
        ' → ${linhas.where((l) => l['curva'] != null).length}');
    stdout.writeln('  perdidos: ${[for (final l in linhas) if (l['doisPontos'] != null && l['curva'] == null) l['ticker']].join(" ")}');
    stdout.writeln('  ganhos: ${[for (final l in linhas) if (l['doisPontos'] == null && l['curva'] != null) l['ticker']].join(" ")}');
    stdout.writeln('  potencial mediano: ${_pc(_mediana(antes))} → ${_pc(_mediana(depois))}');
    stdout.writeln('  fração com potencial positivo: '
        '${_pc(antes.isEmpty ? null : antes.where((x) => x > 0).length / antes.length)} → '
        '${_pc(depois.isEmpty ? null : depois.where((x) => x > 0).length / depois.length)}');
    stdout.writeln('  mediana do Δ: ${_pc(_mediana([for (var k = 0; k < ambos.length; k++) depois[k] - antes[k]]))}');
    stdout.writeln('  Spearman entre as duas ordenações: '
        '${_spearman(antes, depois).toStringAsFixed(4)}');

    File('docs/validacao/curva_ligacao_${hoje.toIso8601String().substring(0, 10)}.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(linhas));
  } finally {
    await ctx.dispose();
  }
}
