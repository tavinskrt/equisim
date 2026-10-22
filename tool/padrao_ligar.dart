// Fase 1 — o que cada peça do eixo A move, somadas uma a uma, na mesma execução.
//
// Quatro montagens por ativo, na mesma data e com os mesmos dados — comparar
// execuções diferentes mistura o efeito do código com a deriva do dado de
// mercado, que já contaminou 26 ativos entre duas execuções com meia hora de
// intervalo (cvm_trimestral.md §3.5):
//
//   mercado    fonte de preços, dois pontos do CDI, divisor da fonte (antes)
//   +oficial   mais a contagem oficial da B3 no divisor        (A3.3, dec. 83)
//   +curva     mais a curva do Tesouro                         (A2.1, dec. 84)
//   padrão     mais a CVM anual — a configuração do aplicativo até A3
//   +setor     mais a classificação setorial oficial da B3     (A5, dec. 87)
//   +prazo     mais o prazo das outorgas do FRE                (A6, dec. 88)
//   +proventos mais o beta sobre retorno total, com a B3       (A4, dec. 89)
//
// `+proventos` é a configuração do aplicativo ao fim da Fase 1.
//
// A data é a da consulta ao registro da B3: registro consultado depois da
// avaliação não entra nela, pela regra de nunca olhar para a frente.
//
// Uso:
//   dart run tool/padrao_ligar.dart [AAAA-MM-DD]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'curva_ligar.dart' show readTreasury;
import 'cvm/documentos.dart';
import 'validation/context.dart';

class _FromCvm implements FundamentalsRepository {
  final FundamentalsRepository market;
  final Map<String, List<CvmPeriodDocument>> docs;
  final DateTime today;
  _FromCvm(this.market, this.docs, this.today);

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await market.history(t);
    if (base.isErr) return base;
    final ownDocs = docs[t.value];
    if (ownDocs == null || ownDocs.isEmpty) return base;
    return Ok(CvmSeries.build(
      documents: ownDocs,
      market: base.unwrap(),
      published: PointInTimeView(today).isPublished,
      anchored: false,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => market.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => market.universe();
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _spearman(List<double> a, List<double> b) {
  List<double> ranks(List<double> v) {
    final idx = List.generate(v.length, (i) => i)
      ..sort((x, y) => v[x].compareTo(v[y]));
    final r = List<double>.filled(v.length, 0);
    var k = 0;
    while (k < idx.length) {
      var j = k;
      // Empate a um trilionésimo: dois potenciais iguais podem diferir no
      // último dígito binário, e `double` não se compara por igualdade.
      while (j + 1 < idx.length && (v[idx[j + 1]] - v[idx[k]]).abs() < 1e-12) {
        j++;
      }
      for (var m = k; m <= j; m++) {
        r[idx[m]] = (k + j) / 2 + 1;
      }
      k = j + 1;
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
  final today = args.isEmpty ? DateTime(2026, 9, 14) : DateTime.parse(args.first);
  final registry = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final curve = TreasuryCurve.at(
      readTreasury('data/tesouro/precotaxatesourodireto.csv'), today);
  final docs = loadDocuments('data/cvm_exercicios.json');
  final terms = ConcessionTermsCodec.decode(
      jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
          as Map<String, dynamic>);
  final dividends = CashDividendsCodec.decode(
      jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
          as Map<String, dynamic>);

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final fromCvm = _FromCvm(ctx.fundamentals, docs, today);
    B3Issuer? issuer(Ticker t) =>
        registry[t.value.length >= 4 ? t.value.substring(0, 4) : ''];
    final withSector = OfficialSectorFundamentalsRepository(
      inner: fromCvm,
      classification: (t) async => issuer(t)?.classification,
    );

    Future<ValuationResult?> evaluate(Ticker t,
        {required bool official,
        required bool withCurve,
        required bool cvm,
        bool sector = false,
        bool term = false,
        bool withDividends = false}) async {
      final e = issuer(t);
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: sector ? withSector : (cvm ? fromCvm : ctx.fundamentals),
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: withCurve ? curve : null,
        officialShares: official && e?.totalShares != null
            ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
            : null,
        projectionYears: 10,
        concessionEnd: term ? terms[t.value]?.end : null,
        dividends: withDividends
            ? CashDividendsCodec.forTicker(dividends, t.value)
            : null,
      );
      if (prep.isErr) return null;
      final r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    }

    // A5 antes de avaliar: o que muda de porta pela classificação oficial.
    final changes = <String>[];
    for (final t in universe) {
      final source = await ctx.fundamentals.profile(t);
      final official = issuer(t)?.classification;
      if (official == null) continue;
      final sk = source.isOk ? source.unwrap().sector.key : null;
      final ind = source.isOk ? source.unwrap().industry : null;
      String gates(String? key, String? sub) => [
            if (FinancialSectors.isFinancial(sectorKey: key, industry: sub))
              'financeira',
            if (CyclicalSectors.hasCyclePrecedence(sectorKey: key, industry: sub))
              'cíclica',
            if (ConcessionSectors.hasFiniteTerm(sectorKey: key, industry: sub))
              'concessão',
          ].join('+');
      final before = gates(sk, ind);
      final after = gates(official.sectorKey, official.industry);
      if (before != after) {
        changes.add('    ${t.value.padRight(7)} ${before.isEmpty ? '—' : before} → '
            '${after.isEmpty ? '—' : after}   (${sk ?? 'sem setor'} | ${official.label})');
      }
    }

    final rows = <Map<String, Object?>>[];
    var i = 0;
    for (final t in universe) {
      if (++i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final m = await evaluate(t, official: false, withCurve: false, cvm: false);
      final o = await evaluate(t, official: true, withCurve: false, cvm: false);
      final c = await evaluate(t, official: true, withCurve: true, cvm: false);
      final p = await evaluate(t, official: true, withCurve: true, cvm: true);
      final st = await evaluate(t,
          official: true, withCurve: true, cvm: true, sector: true);
      final pz = await evaluate(t,
          official: true, withCurve: true, cvm: true, sector: true, term: true);
      final pv = await evaluate(t,
          official: true,
          withCurve: true,
          cvm: true,
          sector: true,
          term: true,
          withDividends: true);
      rows.add({
        'ticker': t.value,
        'mercado': m?.upside,
        'oficial': o?.upside,
        'curva': c?.upside,
        'padrao': p?.upside,
        'setor': st?.upside,
        'prazo': pz?.upside,
        'proventos': pv?.upside,
        'fimDoContrato': terms[t.value]?.end.toIso8601String().substring(0, 10),
        'fonteDoDivisor': o?.warnings
                .any((w) => w.contains('contagem oficial da B3')) ==
            true
            ? 'oficial-divergente'
            : null,
        'avisosPadrao': p?.warnings,
      });
    }
    stderr.writeln('');

    stdout.writeln('== Fase 1 somada, em ${today.toIso8601String().substring(0, 10)} ==');
    stdout.writeln('  curva: ${curve == null ? 'AUSENTE — a montagem +curva repete a anterior' : 'data-base ${curve.referenceDate.toIso8601String().substring(0, 10)}'}');
    void compare(String title, String fromKey, String toKey) {
      final both = [
        for (final l in rows)
          if (l[fromKey] != null && l[toKey] != null) l,
      ];
      final diff = [
        for (final l in both) ((l[toKey]! as double) - (l[fromKey]! as double)).abs(),
      ];
      final medianFrom = _median([for (final l in both) l[fromKey]! as double]);
      final medianTo = _median([for (final l in both) l[toKey]! as double]);
      stdout.writeln('\n== $title ==');
      stdout.writeln('  avaliados: ${rows.where((l) => l[fromKey] != null).length} → '
          '${rows.where((l) => l[toKey] != null).length}');
      stdout.writeln('  ganhos: ${[for (final l in rows) if (l[fromKey] == null && l[toKey] != null) l['ticker']].join(' ')}');
      stdout.writeln('  perdidos: ${[for (final l in rows) if (l[fromKey] != null && l[toKey] == null) l['ticker']].join(' ')}');
      stdout.writeln('  potencial mediano: ${_pc(medianFrom)} → ${_pc(medianTo)}');
      stdout.writeln('  mediana do |Δ|: ${_pc(_median(diff))}   |Δ| > 10 p.p.: '
          '${diff.where((d) => d > 0.10).length}');
      if (both.length > 2) {
        stdout.writeln('  correlação de postos: ${_spearman([
          for (final l in both) l[fromKey]! as double
        ], [
          for (final l in both) l[toKey]! as double
        ]).toStringAsFixed(4)}');
      }
      both.sort((a, b) => (((b[toKey]! as double) - (b[fromKey]! as double)).abs())
          .compareTo(((a[toKey]! as double) - (a[fromKey]! as double)).abs()));
      stdout.writeln('  os que mais se moveram:');
      for (final l in both.take(12)) {
        stdout.writeln('    ${(l['ticker']! as String).padRight(8)} '
            '${_pc(l[fromKey] as double?).padLeft(9)} → ${_pc(l[toKey] as double?).padLeft(9)}');
      }
    }

    compare('A3.3 — contagem oficial no divisor', 'mercado', 'oficial');
    compare('A2.1 — curva do Tesouro', 'oficial', 'curva');
    compare('A1.7 a A1.11 — CVM anual', 'curva', 'padrao');
    stdout.writeln('\n== A5 — portas que mudam pela classificação oficial '
        '(${changes.length}) ==');
    changes.forEach(stdout.writeln);
    compare('A5 — classificação setorial oficial', 'padrao', 'setor');
    compare('A6 — prazo das outorgas', 'setor', 'prazo');
    compare('A4 — beta sobre retorno total', 'prazo', 'proventos');
    compare('Fase 1 inteira — antes → padrão do aplicativo', 'mercado', 'proventos');

    final output = 'docs/validacao/padrao_ligacao_${today.toIso8601String().substring(0, 10)}.json';
    File(output).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
    stdout.writeln('\n  gravado $output');
  } finally {
    await ctx.dispose();
  }
}
