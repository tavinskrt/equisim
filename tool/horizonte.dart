// Item B6 — a varredura do horizonte de projeção.
//
// **A pergunta.** O horizonte explícito é fixo em dez anos para todo ativo,
// independentemente de ciclo, setor ou maturidade, e nunca foi medido se dez é
// melhor que sete ou quinze.
//
// **O que esta ferramenta mede.** Sobre a entrada congelada do gabarito, o
// universo inteiro reavaliado em cada horizonte de 5 a 20 anos:
//
//   1. quantos ativos o motor avalia em cada horizonte;
//   2. quanto o preço justo se move contra o horizonte de dez;
//   3. quanto do valor vem do terminal em cada horizonte;
//   4. **a correlação de postos do potencial contra o horizonte de dez** — que
//      é o que decide se o horizonte pode mudar a medição de habilidade.
//
// O item pede a varredura "sobre o universo e sobre a habilidade". A perna da
// habilidade exige reexecutar as coortes, o que depende da base bruta (item
// C5); a correlação de postos é o que se pode afirmar sem ela, e ela responde a
// pergunta pelo lado forte: uma ordenação que não se move não pode mudar um
// `t`.
//
//   dart run tool/gabarito_cascata.dart   # congela a entrada
//   dart run tool/horizonte.dart          # grava horizonte.json
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _horizons = [5, 6, 7, 8, 9, 10, 12, 15, 20];
const _reference = 10;
const _output = 'docs/validacao/horizonte.json';

/// Percentil pelo método do índice truncado, o mesmo do resto das medições.
double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _median(List<double> v) => _q(v, 0.5);

class _Reading {
  final Map<String, int> fairValueCents = {};
  final Map<String, double> upside = {};
  final Map<String, double> terminalWeight = {};
  final Map<String, String> refusal = {};
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final readings = <int, _Reading>{};

    for (final years in _horizons) {
      final reading = _Reading();
      final evaluated = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universe) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  $years anos: $i/${c.universe.length}   \r');
        }
        final prep = await c.prepare(t, years: years);
        if (prep.isErr) continue;
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (years == _reference) evaluated[t] = r.valueOrNull;
        if (r.isErr) {
          reading.refusal[t.value] = r.failureOrNull!.message;
          continue;
        }
        final v = r.unwrap();
        reading.fairValueCents[t.value] = v.fairValue.cents;
        reading.upside[t.value] = v.upside;
        final weight = v.diagnostics?.terminalShare;
        if (weight != null) reading.terminalWeight[t.value] = weight;
      }
      readings[years] = reading;

      // **A conferência é do horizonte de referência, e só dele.** Os outros
      // são, por construção, outra montagem: conferi-los contra o gabarito
      // acusaria divergência que é o próprio objeto da medição.
      if (years == _reference) {
        final div = await c.checkAgainstAnswerKey(evaluated);
        if (div == null) {
          stderr.writeln('AVISO: gabarito ausente; a montagem não foi '
              'conferida.');
        } else if (div.isNotEmpty) {
          stderr.writeln('ERRO: a montagem de $years anos diverge do gabarito '
              'em ${div.length} ativo(s): ${div.take(8).join(", ")}');
          exitCode = 1;
          return;
        } else {
          stdout.writeln('montagem de $_reference anos conferida contra o '
              'gabarito: zero divergências.');
        }
      }
    }
    stderr.write('                                        \r');

    final base = readings[_reference]!;
    final rows = <Map<String, dynamic>>[];

    stdout.writeln('');
    stdout.writeln('-- a varredura do horizonte, sobre a entrada congelada --');
    stdout.writeln('  anos  avaliados  entram  saem   preço justo vs 10        '
        'peso do terminal   postos vs 10');

    for (final years in _horizons) {
      final l = readings[years]!;
      final common = l.fairValueCents.keys
          .where(base.fairValueCents.containsKey)
          .toList()
        ..sort();

      final changeList = <double>[
        for (final k in common)
          if (base.fairValueCents[k]! != 0)
            l.fairValueCents[k]! / base.fairValueCents[k]! - 1,
      ];
      final included = l.fairValueCents.keys
          .where((k) => !base.fairValueCents.containsKey(k))
          .toList()
        ..sort();
      final leaving = base.fairValueCents.keys
          .where((k) => !l.fairValueCents.containsKey(k))
          .toList()
        ..sort();

      final rho = common.length < 3
          ? null
          : Regression.spearman(
              [for (final k in common) base.upside[k]!],
              [for (final k in common) l.upside[k]!],
            );

      final weights = <double>[
        for (final k in l.terminalWeight.keys) l.terminalWeight[k]!,
      ];

      stdout.writeln('  ${years.toString().padLeft(4)}  '
          '${l.fairValueCents.length.toString().padLeft(9)}  '
          '${included.length.toString().padLeft(6)}  '
          '${leaving.length.toString().padLeft(4)}   '
          'p25 ${_pct(_q(changeList, 0.25))}  med ${_pct(_median(changeList))}  '
          'p75 ${_pct(_q(changeList, 0.75))}   '
          '${(_median(weights) * 100).toStringAsFixed(1).padLeft(6)}%   '
          '${rho == null ? "   —  " : rho.toStringAsFixed(4)}');

      rows.add({
        'anos': years,
        'avaliados': l.fairValueCents.length,
        'comuns': common.length,
        'entram': included,
        'saem': leaving,
        'precoJusto': {
          'p10': _q(changeList, 0.10),
          'p25': _q(changeList, 0.25),
          'mediana': _median(changeList),
          'p75': _q(changeList, 0.75),
          'p90': _q(changeList, 0.90),
          'sobem': changeList.where((v) => v > 0).length,
        },
        'pesoTerminalMediano': _median(weights),
        'spearmanPotencialContra10': rho,
        'formasDeRecusa': l.refusal.values.toSet().length,
      });
    }

    // O par mais distante da varredura: se nem ele move a ordenação, nenhum
    // move.
    final extremes = <String>[
      for (final k in readings[_horizons.first]!.upside.keys)
        if (readings[_horizons.last]!.upside.containsKey(k)) k,
    ]..sort();
    final extremeRho = extremes.length < 3
        ? null
        : Regression.spearman(
            [
              for (final k in extremes)
                readings[_horizons.first]!.upside[k]!
            ],
            [
              for (final k in extremes)
                readings[_horizons.last]!.upside[k]!
            ],
          );
    stdout.writeln('');
    stdout.writeln('  ${_horizons.first} contra ${_horizons.last} anos, '
        'nos ${extremes.length} que os dois avaliam: '
        'postos ${extremeRho?.toStringAsFixed(4) ?? "—"}');

    final json = <String, dynamic>{
      'referencia': _reference,
      'horizontes': rows,
      'spearmanExtremos': extremeRho,
      'ativosNosExtremos': extremes.length,
    };
    File(_output).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json));
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(1).padLeft(6)}%';
