// Item B5 — mede a divergência entre o fluxo descontado e os múltiplos de
// pares, no universo.
//
// **O que a segunda leitura serve para descobrir.** O item pedia «um teste de
// sanidade sobre o nível que hoje só a §2.8 discute em prosa». Esta ferramenta
// faz o teste: para cada avaliado, quanto o DCF diz, quanto os pares dizem, e
// quanto os dois discordam.
//
// **A pergunta que ela decide** é se o desacordo de nível do motor contra o
// mercado (§0: potencial mediano de −38%) aparece também contra os pares. Se o
// DCF ficar abaixo dos múltiplos na mesma proporção em que fica abaixo do
// preço, o desacordo é do modelo; se ficar perto dos múltiplos, ele é do
// mercado.
//
//   dart run tool/gabarito_cascata.dart       # congela a entrada
//   dart run tool/multiplos_empacotar.dart    # grava o pacote
//   dart run tool/multiplos.dart              # grava multiplos.json
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _package = 'assets/mercado/multiplos_setoriais.json';
const _output = 'docs/validacao/multiplos.json';

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _median(List<double> v) => _q(v, 0.5);

Future<void> main(List<String> args) async {
  final file = File(_package);
  if (!file.existsSync()) {
    stderr.writeln('pacote ausente: rode tool/multiplos_empacotar.dart antes.');
    exitCode = 2;
    return;
  }
  final medians = PeerMultipleCodec.decode(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>);

  final c = await Frozen.build();
  try {
    final evaluated = <Ticker, ValuationResult?>{};
    final rows = <Map<String, Object?>>[];
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final b = prep.unwrap();
      // A mesma montagem do gabarito, **mais** o pacote de pares: é a única
      // diferença, e é o que se quer medir.
      final r = ValuationCascade.evaluate(_withPeers(b, medians[t.value]));
      if (r.isErr) continue;
      final v = r.unwrap();
      evaluated[t] = v;
      final tri = v.triangulation;
      rows.add({
        'ticker': t.value,
        'setor': b.sectorKey,
        'dcf': v.fairValue.reais,
        'preco': v.marketPrice.reais,
        'potencial': v.upside,
        'multiplos': tri?.consolidated,
        'divergencia': tri?.divergence,
        'aplicadas': tri?.applied ?? 0,
        'leituras': {
          for (final reading in tri?.readings ?? const <MultipleReading>[])
            reading.kind.key: reading.applied
                ? {
                    'justo': reading.fairValuePerShare,
                    'mediana': reading.peer!.median,
                    'pares': reading.peer!.peers,
                    'grupo': reading.peer!.group,
                  }
                : {'recusa': reading.refusal?.key},
        },
      });
    }
    stderr.write('                              \r');

    // **A conferência é do preço justo, e não da triangulação.** A segunda
    // leitura não entra no preço: se o gabarito divergir, foi ela que vazou
    // para o cálculo, e a medição não vale.
    final div = await c.checkAgainstAnswerKey(evaluated);
    if (div == null) {
      stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.isNotEmpty) {
      stderr.writeln('ERRO: a triangulação mudou o preço justo em '
          '${div.length} ativo(s): ${div.take(8).join(", ")}. Ela é segunda '
          'leitura, e não pode entrar no cálculo.');
      exitCode = 1;
      return;
    } else {
      stdout.writeln('preço justo idêntico ao do gabarito em todos os '
          'avaliados: a segunda leitura não entra no cálculo.');
    }

    final withTriangulation =
        rows.where((l) => l['multiplos'] != null).toList();
    final divergences = <double>[
      for (final l in withTriangulation)
        if (l['divergencia'] != null) l['divergencia'] as double,
    ];
    final aboveLimit = divergences
        .where((d) => d.abs() > PeerValuation.divergenceLimit)
        .length;

    // O potencial pelos múltiplos, para comparar com o do DCF: os pares dizem
    // que a ação está cara ou barata?
    final dcfUpside = <double>[];
    final multiplesUpside = <double>[];
    for (final l in withTriangulation) {
      final price = l['preco'] as double;
      if (price <= 0) continue;
      dcfUpside.add(l['potencial'] as double);
      multiplesUpside.add((l['multiplos'] as double) / price - 1);
    }

    stdout.writeln('');
    stdout.writeln('-- a segunda leitura, sobre a entrada congelada --');
    stdout.writeln('  avaliados                        ${rows.length}');
    stdout.writeln('  com alguma leitura de pares      '
        '${withTriangulation.length}');
    stdout.writeln('  divergência além de '
        '${(PeerValuation.divergenceLimit * 100).toStringAsFixed(0)}%          '
        '$aboveLimit de ${divergences.length}');
    stdout.writeln('');
    stdout.writeln('  divergência (múltiplos ÷ DCF − 1):');
    stdout.writeln('    p10 ${_pct(_q(divergences, 0.10))}   '
        'p25 ${_pct(_q(divergences, 0.25))}   '
        'mediana ${_pct(_median(divergences))}   '
        'p75 ${_pct(_q(divergences, 0.75))}   '
        'p90 ${_pct(_q(divergences, 0.90))}');
    stdout.writeln('');
    stdout.writeln('  potencial mediano:');
    stdout.writeln('    pelo fluxo descontado   '
        '${_pct(_median(dcfUpside))}');
    stdout.writeln('    pelos múltiplos         '
        '${_pct(_median(multiplesUpside))}');
    final rho = Regression.spearman(dcfUpside, multiplesUpside);
    stdout.writeln('    postos entre os dois    '
        '${rho?.toStringAsFixed(4) ?? "—"}');

    // Quantas leituras se aplicaram, e por que as outras não.
    final byApplied = <int, int>{};
    final refusals = <String, int>{};
    for (final l in rows) {
      byApplied.update(l['aplicadas'] as int, (v) => v + 1,
          ifAbsent: () => 1);
      final readings = l['leituras'] as Map<String, Object?>;
      for (final e in readings.entries) {
        final m = e.value as Map<String, Object?>;
        final r = m['recusa'];
        if (r != null) {
          refusals.update('${e.key}: $r', (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    stdout.writeln('');
    stdout.writeln('  leituras aplicadas por ativo:');
    final keys = byApplied.keys.toList()..sort();
    for (final k in keys) {
      stdout.writeln('    $k de 3   ${byApplied[k]}');
    }
    stdout.writeln('');
    stdout.writeln('  por que as outras não entraram:');
    final sorted = refusals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      stdout.writeln('    ${e.key.padRight(48)} ${e.value}');
    }

    File(_output).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'avaliados': rows.length,
      'comTriangulacao': withTriangulation.length,
      'limiteDeDivergencia': PeerValuation.divergenceLimit,
      'acimaDoLimite': aboveLimit,
      'divergencia': {
        'p10': _q(divergences, 0.10),
        'p25': _q(divergences, 0.25),
        'mediana': _median(divergences),
        'p75': _q(divergences, 0.75),
        'p90': _q(divergences, 0.90),
      },
      'potencialMedianoDcf': _median(dcfUpside),
      'potencialMedianoMultiplos': _median(multiplesUpside),
      'spearmanPotencial': rho,
      'leiturasAplicadasPorAtivo': {
        for (final k in keys) '$k': byApplied[k],
      },
      'recusas': refusals,
      'ativos': rows,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

/// Os mesmos insumos, mais o pacote de pares. É a única diferença contra a
/// montagem do gabarito.
ValuationInputs _withPeers(ValuationInputs b, PeerMultipleSet? pairs) =>
    b.withPeerMultiples(pairs);

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(1).padLeft(6)}%';
