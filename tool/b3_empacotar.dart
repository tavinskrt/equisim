// A3.3 — empacota o registro de emissores da B3 para o aplicativo.
//
// Lê as respostas baixadas por `tool/b3_companhias_baixar.py`, passa cada uma
// pelo leitor do núcleo (`B3Registry`) e grava no formato de `B3RegistryCodec`.
// O aplicativo carrega o pacote e usa a contagem oficial como árbitro do
// divisor por papel (decisão 83).
//
// Uso:
//   python tool/b3_companhias_baixar.py
//   dart run tool/b3_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

const _saida = 'assets/b3/emissores.json';

void main() {
  final dir = Directory('data/b3/companhias');
  if (!dir.existsSync()) {
    stderr.writeln('sem data/b3/companhias — rode tool/b3_companhias_baixar.py');
    exit(2);
  }
  final emissores = <B3Issuer>[];
  var eventos = 0, semContagem = 0;
  DateTime? maisAntiga;
  final arquivos = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in arquivos) {
    final bruto = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final consultado = DateTime.parse(bruto['consultadoEm'] as String);
    for (final c in (bruto['resposta'] as List).cast<Map<String, dynamic>>()) {
      final e = B3Registry.issuer(c, consultedOn: consultado);
      if (e == null) continue;
      emissores.add(e);
      eventos += e.events.length;
      if (e.totalShares == null) semContagem++;
      if (maisAntiga == null || consultado.isBefore(maisAntiga)) {
        maisAntiga = consultado;
      }
    }
  }
  final pacote = B3RegistryCodec.encodePackage(emissores,
      geradoEm: maisAntiga ?? DateTime.utc(2000));
  File(_saida)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(pacote));
  stdout.writeln('  emissores: ${emissores.length}  sem contagem: $semContagem');
  stdout.writeln('  eventos de ações compostos: $eventos');
  stdout.writeln('  consulta mais antiga: ${maisAntiga?.toIso8601String().substring(0, 10)}');
  stdout.writeln('  tamanho: ${(File(_saida).lengthSync() / 1024).toStringAsFixed(0)} KB');
  stdout.writeln('  gravado $_saida');
}
