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

import 'curva_ligar.dart' show lerTesouro;
import 'cvm/documentos.dart';
import 'validation/context.dart';

class _DaCvm implements FundamentalsRepository {
  final FundamentalsRepository mercado;
  final Map<String, List<CvmPeriodDocument>> docs;
  final DateTime hoje;
  _DaCvm(this.mercado, this.docs, this.hoje);

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await mercado.history(t);
    if (base.isErr) return base;
    final meus = docs[t.value];
    if (meus == null || meus.isEmpty) return base;
    return Ok(CvmSeries.build(
      documentos: meus,
      mercado: base.unwrap(),
      asOf: hoje,
      publicado: PointInTimeView(hoje).isPublished,
      ancorada: false,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => mercado.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => mercado.universe();
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _spearman(List<double> a, List<double> b) {
  List<double> postos(List<double> v) {
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
  final hoje = args.isEmpty ? DateTime(2026, 9, 14) : DateTime.parse(args.first);
  final registro = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final curva = TreasuryCurve.at(
      lerTesouro('data/tesouro/precotaxatesourodireto.csv'), hoje);
  final docs = carregarDocumentos('data/cvm_exercicios.json');
  final prazos = ConcessionTermsCodec.decode(
      jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
          as Map<String, dynamic>);
  final proventos = CashDividendsCodec.decode(
      jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
          as Map<String, dynamic>);

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final daCvm = _DaCvm(ctx.fundamentals, docs, hoje);
    B3Issuer? emissor(Ticker t) =>
        registro[t.value.length >= 4 ? t.value.substring(0, 4) : ''];
    final comSetor = OfficialSectorFundamentalsRepository(
      inner: daCvm,
      classificacao: (t) async => emissor(t)?.classification,
    );

    Future<ValuationResult?> avaliar(Ticker t,
        {required bool oficial,
        required bool comCurva,
        required bool cvm,
        bool setor = false,
        bool prazo = false,
        bool comProventos = false}) async {
      final e = emissor(t);
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: setor ? comSetor : (cvm ? daCvm : ctx.fundamentals),
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: hoje,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: comCurva ? curva : null,
        officialShares: oficial && e?.totalShares != null
            ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
            : null,
        projectionYears: 10,
        concessionEnd: prazo ? prazos[t.value]?.end : null,
        dividends: comProventos
            ? CashDividendsCodec.forTicker(proventos, t.value)
            : null,
      );
      if (prep.isErr) return null;
      final r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    }

    // A5 antes de avaliar: o que muda de porta pela classificação oficial.
    final mudancas = <String>[];
    for (final t in universe) {
      final fonte = await ctx.fundamentals.profile(t);
      final oficial = emissor(t)?.classification;
      if (oficial == null) continue;
      final sk = fonte.isOk ? fonte.unwrap().sector.key : null;
      final ind = fonte.isOk ? fonte.unwrap().industry : null;
      String portas(String? chave, String? sub) => [
            if (FinancialSectors.isFinancial(sectorKey: chave, industry: sub))
              'financeira',
            if (CyclicalSectors.hasCyclePrecedence(sectorKey: chave, industry: sub))
              'cíclica',
            if (ConcessionSectors.hasFiniteTerm(sectorKey: chave, industry: sub))
              'concessão',
          ].join('+');
      final antes = portas(sk, ind);
      final depois = portas(oficial.sectorKey, oficial.industry);
      if (antes != depois) {
        mudancas.add('    ${t.value.padRight(7)} ${antes.isEmpty ? '—' : antes} → '
            '${depois.isEmpty ? '—' : depois}   (${sk ?? 'sem setor'} | ${oficial.label})');
      }
    }

    final linhas = <Map<String, Object?>>[];
    var i = 0;
    for (final t in universe) {
      if (++i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final m = await avaliar(t, oficial: false, comCurva: false, cvm: false);
      final o = await avaliar(t, oficial: true, comCurva: false, cvm: false);
      final c = await avaliar(t, oficial: true, comCurva: true, cvm: false);
      final p = await avaliar(t, oficial: true, comCurva: true, cvm: true);
      final st = await avaliar(t,
          oficial: true, comCurva: true, cvm: true, setor: true);
      final pz = await avaliar(t,
          oficial: true, comCurva: true, cvm: true, setor: true, prazo: true);
      final pv = await avaliar(t,
          oficial: true,
          comCurva: true,
          cvm: true,
          setor: true,
          prazo: true,
          comProventos: true);
      linhas.add({
        'ticker': t.value,
        'mercado': m?.upside,
        'oficial': o?.upside,
        'curva': c?.upside,
        'padrao': p?.upside,
        'setor': st?.upside,
        'prazo': pz?.upside,
        'proventos': pv?.upside,
        'fimDoContrato': prazos[t.value]?.end.toIso8601String().substring(0, 10),
        'fonteDoDivisor': o?.warnings
                .any((w) => w.contains('contagem oficial da B3')) ==
            true
            ? 'oficial-divergente'
            : null,
        'avisosPadrao': p?.warnings,
      });
    }
    stderr.writeln('');

    stdout.writeln('== Fase 1 somada, em ${hoje.toIso8601String().substring(0, 10)} ==');
    stdout.writeln('  curva: ${curva == null ? 'AUSENTE — a montagem +curva repete a anterior' : 'data-base ${curva.referenceDate.toIso8601String().substring(0, 10)}'}');
    void comparar(String titulo, String de, String para) {
      final ambos = [
        for (final l in linhas)
          if (l[de] != null && l[para] != null) l,
      ];
      final dif = [
        for (final l in ambos) ((l[para]! as double) - (l[de]! as double)).abs(),
      ];
      final medDe = _mediana([for (final l in ambos) l[de]! as double]);
      final medPara = _mediana([for (final l in ambos) l[para]! as double]);
      stdout.writeln('\n== $titulo ==');
      stdout.writeln('  avaliados: ${linhas.where((l) => l[de] != null).length} → '
          '${linhas.where((l) => l[para] != null).length}');
      stdout.writeln('  ganhos: ${[for (final l in linhas) if (l[de] == null && l[para] != null) l['ticker']].join(' ')}');
      stdout.writeln('  perdidos: ${[for (final l in linhas) if (l[de] != null && l[para] == null) l['ticker']].join(' ')}');
      stdout.writeln('  potencial mediano: ${_pc(medDe)} → ${_pc(medPara)}');
      stdout.writeln('  mediana do |Δ|: ${_pc(_mediana(dif))}   |Δ| > 10 p.p.: '
          '${dif.where((d) => d > 0.10).length}');
      if (ambos.length > 2) {
        stdout.writeln('  correlação de postos: ${_spearman([
          for (final l in ambos) l[de]! as double
        ], [
          for (final l in ambos) l[para]! as double
        ]).toStringAsFixed(4)}');
      }
      ambos.sort((a, b) => (((b[para]! as double) - (b[de]! as double)).abs())
          .compareTo(((a[para]! as double) - (a[de]! as double)).abs()));
      stdout.writeln('  os que mais se moveram:');
      for (final l in ambos.take(12)) {
        stdout.writeln('    ${(l['ticker']! as String).padRight(8)} '
            '${_pc(l[de] as double?).padLeft(9)} → ${_pc(l[para] as double?).padLeft(9)}');
      }
    }

    comparar('A3.3 — contagem oficial no divisor', 'mercado', 'oficial');
    comparar('A2.1 — curva do Tesouro', 'oficial', 'curva');
    comparar('A1.7 a A1.11 — CVM anual', 'curva', 'padrao');
    stdout.writeln('\n== A5 — portas que mudam pela classificação oficial '
        '(${mudancas.length}) ==');
    mudancas.forEach(stdout.writeln);
    comparar('A5 — classificação setorial oficial', 'padrao', 'setor');
    comparar('A6 — prazo das outorgas', 'setor', 'prazo');
    comparar('A4 — beta sobre retorno total', 'prazo', 'proventos');
    comparar('Fase 1 inteira — antes → padrão do aplicativo', 'mercado', 'proventos');

    final saida = 'docs/validacao/padrao_ligacao_${hoje.toIso8601String().substring(0, 10)}.json';
    File(saida).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(linhas));
    stdout.writeln('\n  gravado $saida');
  } finally {
    await ctx.dispose();
  }
}
