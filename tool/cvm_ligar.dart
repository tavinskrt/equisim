// A1.7 e A1.8 — a ingestão da CVM ligada ao motor, em três montagens.
//
//   mercado   só a fonte de mercado — o motor de antes
//   anual     CVM mesclada, série de DFPs                     (A1.7)
//   ancorada  CVM mesclada, doze meses no trimestre mais novo (A1.8)
//
// **Por que refazer o A1.7.** A primeira medição tratava como anual todo
// exercício terminado em dezembro. Cinco companhias do universo têm exercício
// social fora do calendário — AGRO3, SMTO3, CAML3, JALL3, RAIZ4 —, e para elas o
// ITR de dezembro é um acumulado parcial que entrava como ano cheio. O SMTO3
// (−45,2 p.p.) e o AGRO3 (−5,6 p.p.) estavam na lista de movimentos daquela
// medição, e eram artefato. Aqui a série anual é **a DFP**, pelo tipo de
// documento, e não pelo mês.
//
// **Sem olhar para a frente na mescla.** Um ponto da CVM terminado em junho só
// pode ser completado com o exercício de mercado que terminou **antes** dele. O
// de dezembro do mesmo ano ainda não existia.
//
// Uso:
//   dart run tool/cvm_ingerir.dart data/cvm
//   dart run tool/cvm_ligar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'cvm/documentos.dart';
import 'validation/context.dart';

/// Data da avaliação. Primeiro argumento, `AAAA-MM-DD`; padrão 04/09/2026.
late final DateTime _today;

/// Repositório que monta a série pelo `CvmSeries` do núcleo — a mesma
/// montagem que o aplicativo usa (A1.9), e não uma cópia dela.
class _FromCvm implements FundamentalsRepository {
  final FundamentalsRepository market;
  final Map<String, List<CvmPeriodDocument>> docs;
  final bool anchored;
  final Map<FieldSource, int> provenance = {};

  /// Tickers cuja série terminou ancorada em trimestre. Conjunto, e não
  /// contador: `history` é chamado mais de uma vez por ativo.
  final Set<String> quarterAnchoredSet = {};

  _FromCvm(this.market, this.docs, {required this.anchored});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await market.history(t);
    if (base.isErr) return base;
    final ownDocs = docs[t.value];
    if (ownDocs == null || ownDocs.isEmpty) return base;
    final r = CvmSeries.build(
      documents: ownDocs,
      market: base.unwrap(),
      published: PointInTimeView(_today).isPublished,
      anchored: anchored,
    );
    if (r.anchoredOnQuarter) quarterAnchoredSet.add(t.value);
    r.provenance.forEach((k, v) => provenance[k] = (provenance[k] ?? 0) + v);
    return Ok(r.series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => market.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => market.universe();
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

void _compare(
  String title,
  List<Map<String, Object?>> rows,
  String fromKey,
  String toKey,
) {
  final both = [
    for (final l in rows)
      if (l[fromKey] != null && l[toKey] != null) l,
  ];
  final gains = [
    for (final l in rows)
      if (l[fromKey] == null && l[toKey] != null) l['ticker'],
  ];
  final lost = [
    for (final l in rows)
      if (l[fromKey] != null && l[toKey] == null) l['ticker'],
  ];
  final diff = [
    for (final l in both) ((l[toKey]! as double) - (l[fromKey]! as double)).abs(),
  ];
  stdout.writeln('\n== $title ==');
  stdout.writeln('  avaliados: ${rows.where((l) => l[fromKey] != null).length} '
      '→ ${rows.where((l) => l[toKey] != null).length}');
  stdout.writeln('  ganhos  (${gains.length}): ${gains.take(14).join(" ")}');
  stdout.writeln('  perdidos (${lost.length}): ${lost.take(14).join(" ")}');
  stdout.writeln('  mediana do |Δ potencial|: ${_pc(_median(diff))}');
  stdout.writeln('  |Δ| > 1 p.p.: ${diff.where((d) => d > 0.01).length}   '
      '|Δ| > 10 p.p.: ${diff.where((d) => d > 0.10).length}');
  both.sort((a, b) => (((b[toKey]! as double) - (b[fromKey]! as double)).abs())
      .compareTo(((a[toKey]! as double) - (a[fromKey]! as double)).abs()));
  stdout.writeln('  os que mais se moveram:');
  for (final l in both.take(12)) {
    final a = l[fromKey]! as double, d = l[toKey]! as double;
    stdout.writeln('    ${(l['ticker']! as String).padRight(8)} '
        '${_pc(a).padLeft(9)} → ${_pc(d).padLeft(9)}  '
        '(${_pc(d - a)})  ${l['fimAncora'] ?? ''}');
  }
}

Future<void> main(List<String> args) async {
  _today = args.isEmpty
      ? DateTime(2026, 9, 4)
      : DateTime.parse(args.first);
  stdout.writeln('== avaliação em ${_today.toIso8601String().substring(0, 10)} ==');
  final docs = loadDocuments('data/cvm_exercicios.json');
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final annual = _FromCvm(ctx.fundamentals, docs, anchored: false);
    final anchored = _FromCvm(ctx.fundamentals, docs, anchored: true);

    Future<ValuationResult?> evaluate(Ticker t, FundamentalsRepository f) async {
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: f,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
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
      final m = await evaluate(t, ctx.fundamentals);
      final a = await evaluate(t, annual);
      final h = await anchored.history(t);
      final z = await evaluate(t, anchored);
      // O fim do último ponto **publicado** na data: a série montada traz
      // todos os exercícios, e o recorte é da cascata.
      final published = h.isOk
          ? h.unwrap().where(PointInTimeView(_today).isPublished).toList()
          : const <FundamentalsSnapshot>[];
      rows.add({
        'ticker': t.value,
        'mercado': m?.upside,
        'anual': a?.upside,
        'ancorada': z?.upside,
        'fimAncora': published.isEmpty
            ? null
            : published.last.fiscalPeriodEnd.toIso8601String().substring(0, 10),
      });
    }
    stderr.writeln('');

    stdout.writeln('  documentos da CVM por ticker: ${docs.length}');
    stdout.writeln('  avaliações com série ancorada em trimestre: '
        '${anchored.quarterAnchoredSet.length}');

    _compare('A1.7 refeito — mercado → CVM anual', rows, 'mercado', 'anual');
    _compare('A1.8 — CVM anual → CVM ancorada', rows, 'anual', 'ancorada');

    stdout.writeln('\n  procedência na montagem ancorada: ${anchored.provenance}');
    // Com data explícita, o arquivo leva a data: sem isso, a medição de
    // outra data sobrescrevia a da data padrão.
    final output = args.isEmpty
        ? 'docs/validacao/cvm_ligacao.json'
        : 'docs/validacao/cvm_ligacao_${args.first}.json';
    File(output).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(rows),
    );
    stdout.writeln('  gravado $output');
  } finally {
    await ctx.dispose();
  }
}
