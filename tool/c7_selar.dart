// Sela as previsões das coortes novas (item C7, decisões 129 e 133).
//
// Lê `data/c7/coortes.json` — do backtest em modo `--c7` — e grava, em
// `docs/validacao/c7/`, um arquivo de previsões por coorte que ainda não tem
// selo do motor atual, com o hash do git dele no índice. **Nunca reescreve um
// selo**: uma coorte já selada é refeita e conferida, e a divergência é
// relatada. Ver `tool/c7/protocolo.dart`.
//
// Uso, a cada trimestre fechado:
//   dart run tool/backtest_valuation.dart --montagem aplicativo \
//       --com-deslistadas --trimestral --c7 [--fim-dos-dados AAAA-MM-DD]
//   dart run tool/c7_selar.dart [--hoje AAAA-MM-DD]
//
// **Selar logo depois da coorte** é o que dá valor ao selo: o commit do
// arquivo selado é a prova de que a previsão existia antes do desfecho.
import 'dart:convert';
import 'dart:io';

import 'c7/protocolo.dart';

Future<void> main(List<String> args) async {
  String? valor(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final fonte = File('data/c7/coortes.json');
  if (!fonte.existsSync()) {
    stderr.writeln('Falta ${fonte.path}. Rode antes: dart run '
        'tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas '
        '--trimestral --c7');
    exit(2);
  }
  final linhas = (jsonDecode(fonte.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final motor = await motorAtual();
  // A data do selo é injetável, como na leitura: o relógio só entra quando
  // `--hoje` não vem. O que prova quando o selo foi feito é o commit dele.
  final hoje =
      valor('--hoje') ?? DateTime.now().toIso8601String().substring(0, 10);
  try {
    final r = await selar(
      linhas: linhas,
      motor: motor,
      pasta: Directory(pastaDosSelos),
      hoje: hoje,
    );
    stdout.writeln('== Selagem do C7 — série ${r.serie} ==');
    stdout.writeln('  motor: ${motor.impressao}'
        '${motor.limpo ? '' : '  (núcleo com mudança não commitada sobre '
            '${motor.commit?.substring(0, 7)})'}');
    stdout.writeln('  seladas agora: ${r.seladas.isEmpty ? 'nenhuma' : r.seladas.join(', ')}');
    stdout.writeln('  já seladas, conferidas: '
        '${r.jaSeladas.isEmpty ? 'nenhuma' : r.jaSeladas.join(', ')}');
    for (final e in r.divergentes.entries) {
      stdout.writeln('  ! ${e.key}: ${e.value} previsões refeitas divergem do '
          'selo — o selo não muda, e a divergência precisa de explicação');
    }
    if (r.serie != 'preRegistrado') {
      stdout.writeln('  ! o motor mudou desde o pré-registrado: a série dele '
          'para estas coortes sai de um `git worktree` do commit registrado '
          'no índice (decisão 133)');
    }
  } on ProtocoloViolado catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}
