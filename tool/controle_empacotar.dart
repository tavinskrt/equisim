// B46 — empacota a espécie do controle acionário de cada emissor.
//
// Lê o Formulário Cadastral da CVM de todos os anos
// (`data/cvm/fca_cia_aberta_geral_<ano>.csv`), monta o histórico de cada
// companhia por `ShareholderControlHistory.fromFilings` — com a data da
// privatização tirada da coluna `Data_Especie_Controle_Acionario` quando ela é
// plausível — e grava o pacote pela raiz do código de negociação, a mesma chave
// do registro da B3. O aplicativo o lê para declarar o controle estatal na
// avaliação; as medições do item B46 o leem para separar estatais e privadas
// em cada data.
//
// **A data do pacote é declarada, e não lida do relógio**, como nos outros
// pacotes versionados. `--agora` usa o dia, para quando o conjunto for
// atualizado.
//
// Uso:
//   python tool/cvm_baixar.py --docs FCA
//   dart run tool/controle_empacotar.dart

import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

const _output = 'assets/cvm/controle.json';

/// A data de referência dos pacotes versionados.
final _reference = DateTime(2026, 9, 14);

void main(List<String> args) {
  final date = args.contains('--agora') ? DateTime.now() : _reference;
  final files = Directory('data/cvm')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'fca_cia_aberta_geral_\d{4}\.csv$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('sem FCA em data/cvm. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --docs FCA');
    exitCode = 2;
    return;
  }

  final byCnpj = <String, List<ShareholderControlFiling>>{};
  for (final f in files) {
    final rows = latin1.decode(f.readAsBytesSync()).split('\n');
    final header = rows.first.trim().split(';');
    final cnpjIndex = header.indexOf('CNPJ_Companhia');
    final iRef = header.indexOf('Data_Referencia');
    final kindIndex = header.indexOf('Especie_Controle_Acionario');
    final iDate = header.indexOf('Data_Especie_Controle_Acionario');
    if ([cnpjIndex, iRef, kindIndex, iDate].contains(-1)) {
      stderr.writeln('${f.path}: colunas do FCA não encontradas');
      exitCode = 1;
      return;
    }
    for (final row in rows.skip(1)) {
      final c = row.trim().split(';');
      if (c.length <= iDate) continue;
      final ref = DateTime.tryParse(c[iRef]);
      if (ref == null || c[kindIndex].trim().isEmpty) continue;
      byCnpj.putIfAbsent(c[cnpjIndex], () => []).add((
        reference: ref,
        species: c[kindIndex],
        speciesDate: DateTime.tryParse(c[iDate]),
      ));
    }
  }

  final bridge = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
              .readAsStringSync()) as Map<String, dynamic>)['ponte']
          as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  final package = <String, List<ShareholderControlPeriod>>{};
  final withoutFca = <String>[];
  var changes = 0;
  for (final e in bridge.entries) {
    final root = e.key.length >= 4 ? e.key.substring(0, 4) : e.key;
    if (package.containsKey(root)) continue;
    final history =
        ShareholderControlHistory.fromFilings(byCnpj[e.value] ?? const []);
    if (history.isEmpty) {
      withoutFca.add(root);
      continue;
    }
    package[root] = history;
    changes += history.length - 1;
  }

  File(_output).writeAsStringSync(
      jsonEncode(ShareholderControlHistory.encode(package, generatedAt: date)));
  final today = {
    for (final c in ShareholderControl.values)
      c: package.values
          .where((p) => ShareholderControlHistory.at(p, date) == c)
          .length,
  };
  stdout.writeln('  emissores: ${package.length} '
      '(${withoutFca.length} sem FCA: ${withoutFca.join(' ')})');
  stdout.writeln('  em ${date.toIso8601String().substring(0, 10)}: '
      'estatal ${today[ShareholderControl.state]}, '
      'privado ${today[ShareholderControl.private]}, '
      'estrangeiro ${today[ShareholderControl.foreign]}');
  stdout.writeln('  mudanças de espécie no histórico: $changes');
  for (final e in package.entries) {
    if (e.value.length < 2) continue;
    stdout.writeln('    ${e.key}: ${[
      for (final p in e.value)
        '${p.control.name} desde ${p.since.toIso8601String().substring(0, 10)}'
    ].join(' → ')}');
  }
  stdout.writeln('  gravado $_output');
}
