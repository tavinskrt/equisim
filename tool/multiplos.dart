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

const _pacote = 'assets/mercado/multiplos_setoriais.json';
const _saida = 'docs/validacao/multiplos.json';

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _mediana(List<double> v) => _q(v, 0.5);

Future<void> main(List<String> args) async {
  final arquivo = File(_pacote);
  if (!arquivo.existsSync()) {
    stderr.writeln('pacote ausente: rode tool/multiplos_empacotar.dart antes.');
    exitCode = 2;
    return;
  }
  final medianas = PeerMultipleCodec.decode(
      jsonDecode(arquivo.readAsStringSync()) as Map<String, Object?>);

  final c = await Congelado.montar();
  try {
    final avaliadas = <Ticker, ValuationResult?>{};
    final linhas = <Map<String, Object?>>[];
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final b = prep.unwrap();
      // A mesma montagem do gabarito, **mais** o pacote de pares: é a única
      // diferença, e é o que se quer medir.
      final r = ValuationCascade.evaluate(_comPares(b, medianas[t.value]));
      if (r.isErr) continue;
      final v = r.unwrap();
      avaliadas[t] = v;
      final tri = v.triangulation;
      linhas.add({
        'ticker': t.value,
        'setor': b.sectorKey,
        'dcf': v.fairValue.reais,
        'preco': v.marketPrice.reais,
        'potencial': v.upside,
        'multiplos': tri?.consolidated,
        'divergencia': tri?.divergence,
        'aplicadas': tri?.applied ?? 0,
        'leituras': {
          for (final leitura in tri?.readings ?? const <MultipleReading>[])
            leitura.kind.name: leitura.applied
                ? {
                    'justo': leitura.fairValuePerShare,
                    'mediana': leitura.peer!.median,
                    'pares': leitura.peer!.peers,
                    'grupo': leitura.peer!.group,
                  }
                : {'recusa': leitura.refusal?.name},
        },
      });
    }
    stderr.write('                              \r');

    // **A conferência é do preço justo, e não da triangulação.** A segunda
    // leitura não entra no preço: se o gabarito divergir, foi ela que vazou
    // para o cálculo, e a medição não vale.
    final div = await c.conferirContraGabarito(avaliadas);
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

    final comTriangulacao =
        linhas.where((l) => l['multiplos'] != null).toList();
    final divergencias = <double>[
      for (final l in comTriangulacao)
        if (l['divergencia'] != null) l['divergencia'] as double,
    ];
    final acimaDoLimite = divergencias
        .where((d) => d.abs() > PeerValuation.divergenceLimit)
        .length;

    // O potencial pelos múltiplos, para comparar com o do DCF: os pares dizem
    // que a ação está cara ou barata?
    final potencialDcf = <double>[];
    final potencialMultiplos = <double>[];
    for (final l in comTriangulacao) {
      final preco = l['preco'] as double;
      if (preco <= 0) continue;
      potencialDcf.add(l['potencial'] as double);
      potencialMultiplos.add((l['multiplos'] as double) / preco - 1);
    }

    stdout.writeln('');
    stdout.writeln('-- a segunda leitura, sobre a entrada congelada --');
    stdout.writeln('  avaliados                        ${linhas.length}');
    stdout.writeln('  com alguma leitura de pares      '
        '${comTriangulacao.length}');
    stdout.writeln('  divergência além de '
        '${(PeerValuation.divergenceLimit * 100).toStringAsFixed(0)}%          '
        '$acimaDoLimite de ${divergencias.length}');
    stdout.writeln('');
    stdout.writeln('  divergência (múltiplos ÷ DCF − 1):');
    stdout.writeln('    p10 ${_pct(_q(divergencias, 0.10))}   '
        'p25 ${_pct(_q(divergencias, 0.25))}   '
        'mediana ${_pct(_mediana(divergencias))}   '
        'p75 ${_pct(_q(divergencias, 0.75))}   '
        'p90 ${_pct(_q(divergencias, 0.90))}');
    stdout.writeln('');
    stdout.writeln('  potencial mediano:');
    stdout.writeln('    pelo fluxo descontado   '
        '${_pct(_mediana(potencialDcf))}');
    stdout.writeln('    pelos múltiplos         '
        '${_pct(_mediana(potencialMultiplos))}');
    final rho = Regression.spearman(potencialDcf, potencialMultiplos);
    stdout.writeln('    postos entre os dois    '
        '${rho?.toStringAsFixed(4) ?? "—"}');

    // Quantas leituras se aplicaram, e por que as outras não.
    final porAplicadas = <int, int>{};
    final recusas = <String, int>{};
    for (final l in linhas) {
      porAplicadas.update(l['aplicadas'] as int, (v) => v + 1,
          ifAbsent: () => 1);
      final leituras = l['leituras'] as Map<String, Object?>;
      for (final e in leituras.entries) {
        final m = e.value as Map<String, Object?>;
        final r = m['recusa'];
        if (r != null) {
          recusas.update('${e.key}: $r', (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    stdout.writeln('');
    stdout.writeln('  leituras aplicadas por ativo:');
    final chaves = porAplicadas.keys.toList()..sort();
    for (final k in chaves) {
      stdout.writeln('    $k de 3   ${porAplicadas[k]}');
    }
    stdout.writeln('');
    stdout.writeln('  por que as outras não entraram:');
    final ordenadas = recusas.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ordenadas) {
      stdout.writeln('    ${e.key.padRight(48)} ${e.value}');
    }

    File(_saida).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'avaliados': linhas.length,
      'comTriangulacao': comTriangulacao.length,
      'limiteDeDivergencia': PeerValuation.divergenceLimit,
      'acimaDoLimite': acimaDoLimite,
      'divergencia': {
        'p10': _q(divergencias, 0.10),
        'p25': _q(divergencias, 0.25),
        'mediana': _mediana(divergencias),
        'p75': _q(divergencias, 0.75),
        'p90': _q(divergencias, 0.90),
      },
      'potencialMedianoDcf': _mediana(potencialDcf),
      'potencialMedianoMultiplos': _mediana(potencialMultiplos),
      'spearmanPotencial': rho,
      'leiturasAplicadasPorAtivo': {
        for (final k in chaves) '$k': porAplicadas[k],
      },
      'recusas': recusas,
      'ativos': linhas,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

/// Os mesmos insumos, mais o pacote de pares. É a única diferença contra a
/// montagem do gabarito.
ValuationInputs _comPares(ValuationInputs b, PeerMultipleSet? pares) =>
    b.withPeerMultiples(pares);

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(1).padLeft(6)}%';
