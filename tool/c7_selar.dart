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
//   dart run tool/c7_preregistrado.dart [--fim-dos-dados AAAA-MM-DD]
//
// Com o motor igual ao pré-registrado, este programa sela a série
// pré-registrada; com motor novo, sela a série «motor da data», e a
// pré-registrada sai do commit dela pelo terceiro passo (decisão 138).
//
// **Selar logo depois da coorte** é o que dá valor ao selo: o commit do
// arquivo selado é a prova de que a previsão existia antes do desfecho.
import 'dart:convert';
import 'dart:io';

import 'c7/protocolo.dart';

Future<void> main(List<String> args) async {
  String? value(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final source = File('data/c7/coortes.json');
  if (!source.existsSync()) {
    stderr.writeln('Falta ${source.path}. Rode antes: dart run '
        'tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas '
        '--trimestral --c7');
    exit(2);
  }
  final rows = (jsonDecode(source.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final engine = await currentEngine();
  // A data do selo é injetável, como na leitura: o relógio só entra quando
  // `--hoje` não vem. O que prova quando o selo foi feito é o commit dele.
  final today =
      value('--hoje') ?? DateTime.now().toIso8601String().substring(0, 10);
  try {
    final r = await seal(
      rows: rows,
      engine: engine,
      folder: Directory(sealsDir),
      today: today,
    );
    stdout.writeln('== Selagem do C7 — série ${r.series} ==');
    stdout.writeln('  motor: ${engine.fingerprint}'
        '${engine.clean ? '' : '  (núcleo com mudança não commitada sobre '
            '${engine.commit?.substring(0, 7)})'}');
    stdout.writeln('  seladas agora: ${r.sealedCohorts.isEmpty ? 'nenhuma' : r.sealedCohorts.join(', ')}');
    stdout.writeln('  já seladas, conferidas: '
        '${r.alreadySealed.isEmpty ? 'nenhuma' : r.alreadySealed.join(', ')}');
    for (final e in r.divergent.entries) {
      stdout.writeln('  ! ${e.key}: ${e.value} previsões refeitas divergem do '
          'selo — o selo não muda, e a divergência precisa de explicação');
    }
    if (r.series != 'preRegistrado') {
      stdout.writeln('  ! o motor mudou desde o pré-registrado: a série dele '
          'para estas coortes sai do commit registrado no índice — rode '
          '`dart run tool/c7_preregistrado.dart` (decisão 138)');
    }
  } on ProtocolViolated catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}
