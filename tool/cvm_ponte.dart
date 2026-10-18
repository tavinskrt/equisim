// Constrói a ponte ticker -> CNPJ com as regras do núcleo, sobre o FCA real.
//
// A lógica mora em `CvmBridge`, no núcleo, e é testada lá. Isto aqui só a
// alimenta com os arquivos e mede a cobertura contra o universo.
//
// Uso:
//   dart run tool/cvm_ponte.dart <diretorio-com-os-csv-extraidos>
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

List<Map<String, String>> _readCsv(File f) {
  final rows = const LineSplitter().convert(latin1.decode(f.readAsBytesSync()));
  if (rows.isEmpty) return const [];
  List<String> fields(String l) {
    final out = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var i = 0; i < l.length; i++) {
      final ch = l[i];
      if (ch == '"') {
        quoted = !quoted;
      } else if (ch == ';' && !quoted) {
        out.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    out.add(current.toString());
    return out;
  }

  final headerRow = fields(rows.first);
  final out = <Map<String, String>>[];
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].trim().isEmpty) continue;
    final c = fields(rows[i]);
    if (c.length != headerRow.length) continue;
    out.add({for (var j = 0; j < headerRow.length; j++) headerRow[j]: c[j]});
  }
  return out;
}

Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? '.' : args.first;

  // --- Regra 1: Codigo_Negociacao com formato de ticker, em todos os FCA ---
  final byCode = <String, Set<String>>{};
  var fcaRows = 0, blank = 0, discarded = 0;
  for (final f in Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('fca_cia_aberta_valor_mobiliario_'))) {
    for (final r in _readCsv(f)) {
      fcaRows++;
      final code = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
      if (code.isEmpty) {
        blank++;
        continue;
      }
      if (!CvmBridge.looksLikeTicker(code)) {
        discarded++;
        continue;
      }
      byCode
          .putIfAbsent(code, () => {})
          .add(r['CNPJ_Companhia'] ?? '');
    }
  }
  final ambiguous = {
    for (final e in byCode.entries)
      if (e.value.length > 1) e.key: e.value,
  };
  final uniqueCode = {
    for (final e in byCode.entries)
      if (e.value.length == 1) e.key: e.value.first,
  };

  // --- Regra 3: nome exato contra o DENOM_CIA ---
  final byName = <String, String>{};
  for (final n in ['dfp_cia_aberta_2024.csv', 'itr_cia_aberta_2024.csv']) {
    final f = File('$dir/$n');
    if (!f.existsSync()) continue;
    for (final r in _readCsv(f)) {
      final name = r['DENOM_CIA'];
      final cnpj = r['CNPJ_CIA'];
      if (name == null || cnpj == null) continue;
      byName.putIfAbsent(CvmBridge.normalizeName(name), () => cnpj);
    }
  }

  // --- Regra 0: registro oficial da B3 (decisão 82) ---
  // Emissor → código CVM, de data/b3/companhias; código CVM → CNPJ, dos
  // metadados de DFP e ITR de todos os anos. Ausente o registro, a regra só
  // não responde.
  final cvmToCnpj = <String, String>{};
  for (final f in Directory(dir).listSync().whereType<File>().where((f) {
    final n = f.uri.pathSegments.last;
    return RegExp(r'^(dfp|itr)_cia_aberta_\d{4}\.csv$').hasMatch(n);
  })) {
    for (final r in _readCsv(f)) {
      final cd = int.tryParse(r['CD_CVM'] ?? '');
      final cnpj = r['CNPJ_CIA'];
      if (cd != null && cnpj != null) cvmToCnpj['$cd'] = cnpj;
    }
  }
  final byOfficialRegistry = <String, String>{};
  final registry = Directory('data/b3/companhias');
  if (registry.existsSync()) {
    for (final f in registry.listSync().whereType<File>()) {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final c in (raw['resposta'] as List).cast<Map<String, dynamic>>()) {
        final cd = int.tryParse('${c['codeCVM']}');
        final cnpj = cd == null ? null : cvmToCnpj['$cd'];
        final code = c['code'];
        if (code is String && cnpj != null) byOfficialRegistry[code] = cnpj;
      }
    }
  }

  // --- Universo ---
  final uni = (jsonDecode(
    File('docs/validacao/universo.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();
  final tickers = [for (final u in uni) u['ticker'] as String];
  final names = {
    for (final u in uni)
      if (u['nome'] != null) u['ticker'] as String: u['nome'] as String,
  };

  final withoutOfficial = CvmBridge.resolveUniverse(
    tickers,
    byCode: uniqueCode,
    byName: byName,
    names: names,
  );
  final bridge = CvmBridge.resolveUniverse(
    tickers,
    byCode: uniqueCode,
    byName: byName,
    names: names,
    byOfficialRegistry: byOfficialRegistry,
  );
  final missingTickers = [for (final t in tickers) if (!bridge.containsKey(t)) t];

  stdout.writeln('== Ponte ticker -> CNPJ, pelas regras do núcleo ==\n');
  stdout.writeln('  linhas de FCA lidas        : $fcaRows');
  stdout.writeln('    em branco                : $blank '
      '(${(100 * blank / fcaRows).toStringAsFixed(1)}%)');
  stdout.writeln('    descartadas pelo formato : $discarded');
  stdout.writeln('    códigos com CNPJ único   : ${uniqueCode.length}');
  stdout.writeln('    AMBÍGUOS                 : ${ambiguous.length} '
      '${ambiguous.keys.take(6).join(", ")}');
  stdout.writeln('');
  stdout.writeln('  universo: ${tickers.length}');
  stdout.writeln('  resolvidos: ${bridge.length} '
      '(${(100 * bridge.length / tickers.length).toStringAsFixed(1)}%)');
  stdout.writeln('  companhias distintas: ${bridge.values.toSet().length}');
  stdout.writeln('  sem ponte: ${missingTickers.length}  ${missingTickers.join(" ")}');
  stdout.writeln('  emissores no registro oficial da B3: '
      '${byOfficialRegistry.length}');
  final corrected = [
    for (final e in bridge.entries)
      if (withoutOfficial[e.key] != null && withoutOfficial[e.key] != e.value)
        '${e.key} ${withoutOfficial[e.key]} → ${e.value}',
  ];
  stdout.writeln('  corrigidos pelo registro oficial: ${corrected.length}');
  for (final c in corrected) {
    stdout.writeln('    $c');
  }
  final unexpected =
      missingTickers.where((t) => !CvmBridge.withoutBridge.contains(t)).toList();
  stdout.writeln('  fora do que o núcleo declara em semPonte: '
      '${unexpected.isEmpty ? "nenhum" : unexpected.join(" ")}');

  // A regra geral: uma companhia alcançada por duas raízes tem uma ponte
  // errada, e nenhuma medição interna diz qual.
  final conflicts = CvmBridge.rootConflicts(bridge);
  stdout.writeln('');
  stdout.writeln('  companhias alcançadas por mais de uma raiz: '
      '${conflicts.length}');
  for (final e in conflicts.entries) {
    final tickers = [for (final t in bridge.entries) if (t.value == e.key) t.key]
      ..sort();
    stdout.writeln('    ${e.key}  raízes ${e.value.join("/")}  '
        '-> ${tickers.join(" ")}');
  }

  File('docs/validacao/ponte_cvm.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'medidoEm': '2026-09-14',
      'universo': tickers.length,
      'resolvidos': bridge.length,
      'companhias': bridge.values.toSet().length,
      'semPonte': missingTickers,
      'ponte': bridge,
    }),
  );
  stdout.writeln('\n  gravado docs/validacao/ponte_cvm.json');
}
