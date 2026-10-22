// A leitura da réplica fora da amostra (item C7, decisões 129 e 133).
//
// **Antes da data fixada, só a situação**: quantas coortes estão seladas e
// quantas já têm o retorno do horizonte — nenhuma estatística. **Na data**, o
// critério da decisão 96 sobre as previsões seladas do motor pré-registrado,
// pela mesma função que mede o R3, com os retornos de um backtest `--c7` feito
// com a base de então — e, ao lado, a mesma conta sobre a série de cada motor
// posterior, que é referência e não a leitura.
//
// Uso:
//   dart run tool/c7_leitura.dart                        # situação
//   dart run tool/c7_leitura.dart --ler 12 \
//       [--fim-dos-dados AAAA-MM-DD] [--hoje AAAA-MM-DD]  # a partir de 30/09/2029
import 'dart:convert';
import 'dart:io';

import 'c7/protocolo.dart';

Future<void> main(List<String> args) async {
  String? value(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final today = DateTime.parse(
      value('--hoje') ?? DateTime.now().toIso8601String().substring(0, 10));
  final dataEnd = DateTime.parse(value('--fim-dos-dados') ?? '2026-09-04');
  final folder = Directory(sealsDir);
  final read = value('--ler');

  if (read == null) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(
        situation(folder: folder, today: today, dataEnd: dataEnd)));
    return;
  }
  final source = File('data/c7/coortes.json');
  if (!source.existsSync()) {
    stderr.writeln('Falta ${source.path}, com os retornos: rode o backtest em '
        'modo --c7 com --fim-dos-dados da base de hoje.');
    exit(2);
  }
  try {
    final months = int.parse(read);
    final reading = await readFromFile(months, folder, today, source);
    final output = File('${folder.path}/leitura_${months}m.json');
    output.writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(reading)}\n');
    final fm = ((reading['leitura'] as Map)['famaMacBeth']
        as Map)['potencialDadoBm'] as Map?;
    stdout.writeln('== C7, $months meses ==');
    stdout.writeln('  potencial dado o B/M: ${fm?['media']}  t corrigido '
        '${fm?['tSobreposicao']} / ${fm?['criticoSobreposicao']}  '
        'Newey-West ${fm?['tNeweyWest']}  passa: ${fm?['passaR3'] ?? false}');
    stdout.writeln('  previsões refeitas que divergem do selo: '
        '${reading['previsoesRefeitasQueDivergem']}');
    // A leitura é a do pré-registrado; a de cada motor posterior vem ao lado,
    // sem decidir nada (decisão 129).
    for (final e in (reading['motoresDaData'] as Map).entries) {
      final m = (((e.value as Map)['famaMacBeth'] as Map)['potencialDadoBm'])
          as Map?;
      stdout.writeln('  motor da data ${(e.key as String).substring(0, 8)}: '
          '${m?['media']}  t corrigido ${m?['tSobreposicao']}  '
          '(referência, não a leitura)');
    }
    stdout.writeln('  escrito ${output.path}');
  } on ProtocolViolated catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}

Future<Map<String, dynamic>> readFromFile(
        int months, Directory folder, DateTime today, File source) =>
    read(
      months: months,
      folder: folder,
      today: today,
      rows: (jsonDecode(source.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>(),
    );
