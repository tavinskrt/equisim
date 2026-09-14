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
late final DateTime _hoje;

/// Repositório que monta a série pelo `CvmSeries` do núcleo — a mesma
/// montagem que o aplicativo usa (A1.9), e não uma cópia dela.
class _DaCvm implements FundamentalsRepository {
  final FundamentalsRepository mercado;
  final Map<String, List<CvmPeriodDocument>> docs;
  final bool ancorada;
  final Map<FieldSource, int> procedencia = {};

  /// Tickers cuja série terminou ancorada em trimestre. Conjunto, e não
  /// contador: `history` é chamado mais de uma vez por ativo.
  final Set<String> ancoradasEmTrimestre = {};

  _DaCvm(this.mercado, this.docs, {required this.ancorada});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await mercado.history(t);
    if (base.isErr) return base;
    final meus = docs[t.value];
    if (meus == null || meus.isEmpty) return base;
    final r = CvmSeries.build(
      documentos: meus,
      mercado: base.unwrap(),
      asOf: _hoje,
      publicado: PointInTimeView(_hoje).isPublished,
      ancorada: ancorada,
    );
    if (r.anchoredOnQuarter) ancoradasEmTrimestre.add(t.value);
    r.provenance.forEach((k, v) => procedencia[k] = (procedencia[k] ?? 0) + v);
    return Ok(r.series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => mercado.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => mercado.universe();
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

void _comparar(
  String titulo,
  List<Map<String, Object?>> linhas,
  String de,
  String para,
) {
  final ambos = [
    for (final l in linhas)
      if (l[de] != null && l[para] != null) l,
  ];
  final ganhos = [
    for (final l in linhas)
      if (l[de] == null && l[para] != null) l['ticker'],
  ];
  final perdidos = [
    for (final l in linhas)
      if (l[de] != null && l[para] == null) l['ticker'],
  ];
  final dif = [
    for (final l in ambos) ((l[para]! as double) - (l[de]! as double)).abs(),
  ];
  stdout.writeln('\n== $titulo ==');
  stdout.writeln('  avaliados: ${linhas.where((l) => l[de] != null).length} '
      '→ ${linhas.where((l) => l[para] != null).length}');
  stdout.writeln('  ganhos  (${ganhos.length}): ${ganhos.take(14).join(" ")}');
  stdout.writeln('  perdidos (${perdidos.length}): ${perdidos.take(14).join(" ")}');
  stdout.writeln('  mediana do |Δ potencial|: ${_pc(_mediana(dif))}');
  stdout.writeln('  |Δ| > 1 p.p.: ${dif.where((d) => d > 0.01).length}   '
      '|Δ| > 10 p.p.: ${dif.where((d) => d > 0.10).length}');
  ambos.sort((a, b) => (((b[para]! as double) - (b[de]! as double)).abs())
      .compareTo(((a[para]! as double) - (a[de]! as double)).abs()));
  stdout.writeln('  os que mais se moveram:');
  for (final l in ambos.take(12)) {
    final a = l[de]! as double, d = l[para]! as double;
    stdout.writeln('    ${(l['ticker']! as String).padRight(8)} '
        '${_pc(a).padLeft(9)} → ${_pc(d).padLeft(9)}  '
        '(${_pc(d - a)})  ${l['fimAncora'] ?? ''}');
  }
}

Future<void> main(List<String> args) async {
  _hoje = args.isEmpty
      ? DateTime(2026, 9, 4)
      : DateTime.parse(args.first);
  stdout.writeln('== avaliação em ${_hoje.toIso8601String().substring(0, 10)} ==');
  final docs = carregarDocumentos('data/cvm_exercicios.json');
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final anual = _DaCvm(ctx.fundamentals, docs, ancorada: false);
    final ancorada = _DaCvm(ctx.fundamentals, docs, ancorada: true);

    Future<ValuationResult?> avaliar(Ticker t, FundamentalsRepository f) async {
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: f,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _hoje,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
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
      final m = await avaliar(t, ctx.fundamentals);
      final a = await avaliar(t, anual);
      final h = await ancorada.history(t);
      final z = await avaliar(t, ancorada);
      // O fim do último ponto **publicado** na data: a série montada traz
      // todos os exercícios, e o recorte é da cascata.
      final publicados = h.isOk
          ? h.unwrap().where(PointInTimeView(_hoje).isPublished).toList()
          : const <FundamentalsSnapshot>[];
      linhas.add({
        'ticker': t.value,
        'mercado': m?.upside,
        'anual': a?.upside,
        'ancorada': z?.upside,
        'fimAncora': publicados.isEmpty
            ? null
            : publicados.last.fiscalPeriodEnd.toIso8601String().substring(0, 10),
      });
    }
    stderr.writeln('');

    stdout.writeln('  documentos da CVM por ticker: ${docs.length}');
    stdout.writeln('  avaliações com série ancorada em trimestre: '
        '${ancorada.ancoradasEmTrimestre.length}');

    _comparar('A1.7 refeito — mercado → CVM anual', linhas, 'mercado', 'anual');
    _comparar('A1.8 — CVM anual → CVM ancorada', linhas, 'anual', 'ancorada');

    stdout.writeln('\n  procedência na montagem ancorada: ${ancorada.procedencia}');
    // Com data explícita, o arquivo leva a data: sem isso, a medição de
    // outra data sobrescrevia a da data padrão.
    final saida = args.isEmpty
        ? 'docs/validacao/cvm_ligacao.json'
        : 'docs/validacao/cvm_ligacao_${args.first}.json';
    File(saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(linhas),
    );
    stdout.writeln('  gravado $saida');
  } finally {
    await ctx.dispose();
  }
}
