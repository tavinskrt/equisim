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

const _horizontes = [5, 6, 7, 8, 9, 10, 12, 15, 20];
const _referencia = 10;
const _saida = 'docs/validacao/horizonte.json';

/// Percentil pelo método do índice truncado, o mesmo do resto das medições.
double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _mediana(List<double> v) => _q(v, 0.5);

class _Leitura {
  _Leitura(this.anos);
  final int anos;
  final Map<String, int> justoCentavos = {};
  final Map<String, double> potencial = {};
  final Map<String, double> pesoTerminal = {};
  final Map<String, String> recusa = {};
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final leituras = <int, _Leitura>{};

    for (final anos in _horizontes) {
      final leitura = _Leitura(anos);
      final avaliadas = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universo) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  $anos anos: $i/${c.universo.length}   \r');
        }
        final prep = await c.preparar(t, anos: anos);
        if (prep.isErr) continue;
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (anos == _referencia) avaliadas[t] = r.valueOrNull;
        if (r.isErr) {
          leitura.recusa[t.value] = r.failureOrNull!.message;
          continue;
        }
        final v = r.unwrap();
        leitura.justoCentavos[t.value] = v.fairValue.cents;
        leitura.potencial[t.value] = v.upside;
        final peso = v.diagnostics?.terminalShare;
        if (peso != null) leitura.pesoTerminal[t.value] = peso;
      }
      leituras[anos] = leitura;

      // **A conferência é do horizonte de referência, e só dele.** Os outros
      // são, por construção, outra montagem: conferi-los contra o gabarito
      // acusaria divergência que é o próprio objeto da medição.
      if (anos == _referencia) {
        final div = await c.conferirContraGabarito(avaliadas);
        if (div == null) {
          stderr.writeln('AVISO: gabarito ausente; a montagem não foi '
              'conferida.');
        } else if (div.isNotEmpty) {
          stderr.writeln('ERRO: a montagem de $anos anos diverge do gabarito '
              'em ${div.length} ativo(s): ${div.take(8).join(", ")}');
          exitCode = 1;
          return;
        } else {
          stdout.writeln('montagem de $_referencia anos conferida contra o '
              'gabarito: zero divergências.');
        }
      }
    }
    stderr.write('                                        \r');

    final base = leituras[_referencia]!;
    final linhas = <Map<String, dynamic>>[];

    stdout.writeln('');
    stdout.writeln('-- a varredura do horizonte, sobre a entrada congelada --');
    stdout.writeln('  anos  avaliados  entram  saem   preço justo vs 10        '
        'peso do terminal   postos vs 10');

    for (final anos in _horizontes) {
      final l = leituras[anos]!;
      final comuns = l.justoCentavos.keys
          .where(base.justoCentavos.containsKey)
          .toList()
        ..sort();

      final variacao = <double>[
        for (final k in comuns)
          if (base.justoCentavos[k]! != 0)
            l.justoCentavos[k]! / base.justoCentavos[k]! - 1,
      ];
      final entram = l.justoCentavos.keys
          .where((k) => !base.justoCentavos.containsKey(k))
          .toList()
        ..sort();
      final saem = base.justoCentavos.keys
          .where((k) => !l.justoCentavos.containsKey(k))
          .toList()
        ..sort();

      final rho = comuns.length < 3
          ? null
          : Regression.spearman(
              [for (final k in comuns) base.potencial[k]!],
              [for (final k in comuns) l.potencial[k]!],
            );

      final pesos = <double>[
        for (final k in l.pesoTerminal.keys) l.pesoTerminal[k]!,
      ];

      stdout.writeln('  ${anos.toString().padLeft(4)}  '
          '${l.justoCentavos.length.toString().padLeft(9)}  '
          '${entram.length.toString().padLeft(6)}  '
          '${saem.length.toString().padLeft(4)}   '
          'p25 ${_pct(_q(variacao, 0.25))}  med ${_pct(_mediana(variacao))}  '
          'p75 ${_pct(_q(variacao, 0.75))}   '
          '${(_mediana(pesos) * 100).toStringAsFixed(1).padLeft(6)}%   '
          '${rho == null ? "   —  " : rho.toStringAsFixed(4)}');

      linhas.add({
        'anos': anos,
        'avaliados': l.justoCentavos.length,
        'comuns': comuns.length,
        'entram': entram,
        'saem': saem,
        'precoJusto': {
          'p10': _q(variacao, 0.10),
          'p25': _q(variacao, 0.25),
          'mediana': _mediana(variacao),
          'p75': _q(variacao, 0.75),
          'p90': _q(variacao, 0.90),
          'sobem': variacao.where((v) => v > 0).length,
        },
        'pesoTerminalMediano': _mediana(pesos),
        'spearmanPotencialContra10': rho,
        'formasDeRecusa': l.recusa.values.toSet().length,
      });
    }

    // O par mais distante da varredura: se nem ele move a ordenação, nenhum
    // move.
    final extremos = <String>[
      for (final k in leituras[_horizontes.first]!.potencial.keys)
        if (leituras[_horizontes.last]!.potencial.containsKey(k)) k,
    ]..sort();
    final rhoExtremo = extremos.length < 3
        ? null
        : Regression.spearman(
            [
              for (final k in extremos)
                leituras[_horizontes.first]!.potencial[k]!
            ],
            [
              for (final k in extremos)
                leituras[_horizontes.last]!.potencial[k]!
            ],
          );
    stdout.writeln('');
    stdout.writeln('  ${_horizontes.first} contra ${_horizontes.last} anos, '
        'nos ${extremos.length} que os dois avaliam: '
        'postos ${rhoExtremo?.toStringAsFixed(4) ?? "—"}');

    final json = <String, dynamic>{
      'referencia': _referencia,
      'horizontes': linhas,
      'spearmanExtremos': rhoExtremo,
      'ativosNosExtremos': extremos.length,
    };
    File(_saida).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json));
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(1).padLeft(6)}%';
