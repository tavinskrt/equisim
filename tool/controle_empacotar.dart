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

const _saida = 'assets/cvm/controle.json';

/// A data de referência dos pacotes versionados.
final _referencia = DateTime(2026, 9, 14);

void main(List<String> args) {
  final data = args.contains('--agora') ? DateTime.now() : _referencia;
  final arquivos = Directory('data/cvm')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'fca_cia_aberta_geral_\d{4}\.csv$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (arquivos.isEmpty) {
    stderr.writeln('sem FCA em data/cvm. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --docs FCA');
    exitCode = 2;
    return;
  }

  final porCnpj = <String, List<ShareholderControlFiling>>{};
  for (final f in arquivos) {
    final linhas = latin1.decode(f.readAsBytesSync()).split('\n');
    final cabecalho = linhas.first.trim().split(';');
    final iCnpj = cabecalho.indexOf('CNPJ_Companhia');
    final iRef = cabecalho.indexOf('Data_Referencia');
    final iEspecie = cabecalho.indexOf('Especie_Controle_Acionario');
    final iData = cabecalho.indexOf('Data_Especie_Controle_Acionario');
    if ([iCnpj, iRef, iEspecie, iData].contains(-1)) {
      stderr.writeln('${f.path}: colunas do FCA não encontradas');
      exitCode = 1;
      return;
    }
    for (final linha in linhas.skip(1)) {
      final c = linha.trim().split(';');
      if (c.length <= iData) continue;
      final ref = DateTime.tryParse(c[iRef]);
      if (ref == null || c[iEspecie].trim().isEmpty) continue;
      porCnpj.putIfAbsent(c[iCnpj], () => []).add((
        reference: ref,
        species: c[iEspecie],
        speciesDate: DateTime.tryParse(c[iData]),
      ));
    }
  }

  final ponte = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
              .readAsStringSync()) as Map<String, dynamic>)['ponte']
          as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  final pacote = <String, List<ShareholderControlPeriod>>{};
  final semFca = <String>[];
  var mudancas = 0;
  for (final e in ponte.entries) {
    final raiz = e.key.length >= 4 ? e.key.substring(0, 4) : e.key;
    if (pacote.containsKey(raiz)) continue;
    final historico =
        ShareholderControlHistory.fromFilings(porCnpj[e.value] ?? const []);
    if (historico.isEmpty) {
      semFca.add(raiz);
      continue;
    }
    pacote[raiz] = historico;
    mudancas += historico.length - 1;
  }

  File(_saida).writeAsStringSync(
      jsonEncode(ShareholderControlHistory.encode(pacote, geradoEm: data)));
  final hoje = {
    for (final c in ShareholderControl.values)
      c: pacote.values
          .where((p) => ShareholderControlHistory.at(p, data) == c)
          .length,
  };
  stdout.writeln('  emissores: ${pacote.length} '
      '(${semFca.length} sem FCA: ${semFca.join(' ')})');
  stdout.writeln('  em ${data.toIso8601String().substring(0, 10)}: '
      'estatal ${hoje[ShareholderControl.state]}, '
      'privado ${hoje[ShareholderControl.private]}, '
      'estrangeiro ${hoje[ShareholderControl.foreign]}');
  stdout.writeln('  mudanças de espécie no histórico: $mudancas');
  for (final e in pacote.entries) {
    if (e.value.length < 2) continue;
    stdout.writeln('    ${e.key}: ${[
      for (final p in e.value)
        '${p.control.name} desde ${p.since.toIso8601String().substring(0, 10)}'
    ].join(' → ')}');
  }
  stdout.writeln('  gravado $_saida');
}
