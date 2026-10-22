// B16 — empacota a composição declarada das units para o aplicativo.
//
// A razão de unidade era inferida do valor de mercado, e só acerta quando
// ordinária e preferencial valem o mesmo (item B16,
// `docs/validacao/ponte_por_papel.md` §3). A composição que a companhia declara
// no quadro de valores mobiliários da FCA é fonte primária e datada; este
// programa a lê, ano a ano, e grava o pacote que o aplicativo carrega como
// asset.
//
// **O código de negociação da FCA não serve de chave**, e a medição do A1 já
// dizia por quê: a coluna é texto livre, vem em branco em 44% das linhas e
// traz zeros no BTG — a BPAC11 declara a composição sob `000000`. A chave é o
// **CNPJ**, pela ponte do registro da B3 (decisão 82).
//
// **A data do pacote é declarada, e não lida do relógio.** Rodar o programa
// hoje e amanhã sobre a mesma FCA tem de produzir o mesmo arquivo: a
// composição não muda, e um `geradoEm` do relógio geraria diff espúrio no
// repositório. O padrão é a data de referência dos pacotes versionados, e
// `--agora` usa o dia, para quando o conjunto for atualizado — o mesmo arranjo
// de `beta_prior_empacotar.dart`.
//
// Uso:
//   python tool/cvm_baixar.py --docs FCA
//   dart run tool/unit_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'cvm/codigos_fca.dart';

const _output = 'assets/cvm/units.json';

/// A data de referência dos pacotes versionados.
final _reference = DateTime(2026, 9, 14);

void main(List<String> args) {
  final date = args.contains('--agora') ? DateTime.now() : _reference;
  final universe = (jsonDecode(
          File('docs/validacao/universo.json').readAsStringSync()) as List)
      .map((e) => (e as Map<String, dynamic>)['ticker'] as String)
      .toList();
  final bridge = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
          as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));

  final fca = FcaCodes.read();
  if (fca.unitsByCnpj.isEmpty) {
    stderr.writeln('sem FCA em data/cvm. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --docs FCA');
    exitCode = 2;
    return;
  }

  // Unit é a classe 11 da B3. A regra é do formato do código, e não de uma
  // lista: um papel novo não pode depender de alguém lembrar de cadastrá-lo.
  final units = [for (final t in universe) if (t.endsWith('11')) t];
  final package = <String, List<UnitComposition>>{};
  final without = <String>[];
  for (final t in units) {
    final cnpj = bridge[t];
    final declared = cnpj == null ? null : fca.unitsByCnpj[cnpj];
    if (declared == null || declared.isEmpty) {
      without.add(t);
      continue;
    }
    package[t] = declared;
  }

  File(_output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(UnitCompositionCodec.encodePackage(
      package,
      generatedAt: date,
    )));

  stdout.writeln('== composição declarada das units ==');
  for (final t in package.keys.toList()..sort()) {
    final c = package[t]!..sort((a, b) => a.year.compareTo(b.year));
    final years = '${c.first.year}–${c.last.year}';
    final shares = {for (final x in c) x.shares}.toList()..sort();
    stdout.writeln('  $t  $years  ${shares.join('/')} ações  '
        '"${c.last.declared}"');
  }
  stdout.writeln('  ${package.length} de ${units.length} units do universo');
  if (without.isNotEmpty) {
    // Sem declaração o motor recua para a razão medida — e passa a dizer que
    // ela foi inferida, que é o que o item B16 pede.
    stdout.writeln('  sem composição declarada: ${without.join(', ')}');
  }
  stdout.writeln('  gravado $_output');
}
