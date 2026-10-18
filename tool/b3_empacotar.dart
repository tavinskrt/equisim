// A3.3 — empacota o registro de emissores da B3 para o aplicativo.
//
// Lê as respostas baixadas por `tool/b3_companhias_baixar.py`, passa cada uma
// pelo leitor do núcleo (`B3Registry`) e grava no formato de `B3RegistryCodec`.
// O aplicativo carrega o pacote e usa a contagem oficial como árbitro do
// divisor por papel (decisão 83).
//
// A classificação setorial oficial (item A5) sai do detalhe baixado por
// `tool/b3_complemento_baixar.py`; sem ele, o emissor fica sem classificação e o
// aplicativo recua para a taxonomia da fonte de preços.
//
// Uso:
//   python tool/b3_companhias_baixar.py
//   python tool/b3_complemento_baixar.py
//   dart run tool/b3_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

const _output = 'assets/b3/emissores.json';

void main() {
  final dir = Directory('data/b3/companhias');
  if (!dir.existsSync()) {
    stderr.writeln('sem data/b3/companhias — rode tool/b3_companhias_baixar.py');
    exit(2);
  }
  final issuers = <B3Issuer>[];
  var events = 0, withoutCount = 0, withoutClassification = 0;
  DateTime? oldest;
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final consultedAt = DateTime.parse(raw['consultadoEm'] as String);
    // A classificação setorial vem do detalhe do mesmo emissor (item A5).
    final supplement = File(
        'data/b3/complemento/${f.uri.pathSegments.last}');
    final detail = supplement.existsSync()
        ? (jsonDecode(supplement.readAsStringSync())
            as Map<String, dynamic>)['detalhe'] as Map<String, dynamic>?
        : null;
    for (final c in (raw['resposta'] as List).cast<Map<String, dynamic>>()) {
      final e = B3Registry.issuer(c, consultedOn: consultedAt, detail: detail);
      if (e == null) continue;
      issuers.add(e);
      events += e.events.length;
      if (e.totalShares == null) withoutCount++;
      if (e.classification == null) withoutClassification++;
      if (oldest == null || consultedAt.isBefore(oldest)) {
        oldest = consultedAt;
      }
    }
  }
  final package = B3RegistryCodec.encodePackage(issuers,
      generatedAt: oldest ?? DateTime.utc(2000));
  File(_output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(package));
  stdout.writeln('  emissores: ${issuers.length}  sem contagem: $withoutCount  '
      'sem classificação: $withoutClassification');
  stdout.writeln('  eventos de ações compostos: $events');
  stdout.writeln('  consulta mais antiga: ${oldest?.toIso8601String().substring(0, 10)}');
  stdout.writeln('  tamanho: ${(File(_output).lengthSync() / 1024).toStringAsFixed(0)} KB');
  stdout.writeln('  gravado $_output');
}
