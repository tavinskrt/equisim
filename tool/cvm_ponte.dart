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

List<Map<String, String>> _lerCsv(File f) {
  final linhas = const LineSplitter().convert(latin1.decode(f.readAsBytesSync()));
  if (linhas.isEmpty) return const [];
  List<String> campos(String l) {
    final out = <String>[];
    final atual = StringBuffer();
    var aspas = false;
    for (var i = 0; i < l.length; i++) {
      final ch = l[i];
      if (ch == '"') {
        aspas = !aspas;
      } else if (ch == ';' && !aspas) {
        out.add(atual.toString());
        atual.clear();
      } else {
        atual.write(ch);
      }
    }
    out.add(atual.toString());
    return out;
  }

  final cab = campos(linhas.first);
  final out = <Map<String, String>>[];
  for (var i = 1; i < linhas.length; i++) {
    if (linhas[i].trim().isEmpty) continue;
    final c = campos(linhas[i]);
    if (c.length != cab.length) continue;
    out.add({for (var j = 0; j < cab.length; j++) cab[j]: c[j]});
  }
  return out;
}

Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? '.' : args.first;

  // --- Regra 1: Codigo_Negociacao com formato de ticker, em todos os FCA ---
  final porCodigo = <String, Set<String>>{};
  var linhasFca = 0, emBranco = 0, descartadas = 0;
  for (final f in Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('fca_cia_aberta_valor_mobiliario_'))) {
    for (final r in _lerCsv(f)) {
      linhasFca++;
      final cod = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
      if (cod.isEmpty) {
        emBranco++;
        continue;
      }
      if (!CvmBridge.pareceTicker(cod)) {
        descartadas++;
        continue;
      }
      porCodigo
          .putIfAbsent(cod, () => {})
          .add(r['CNPJ_Companhia'] ?? '');
    }
  }
  final ambiguos = {
    for (final e in porCodigo.entries)
      if (e.value.length > 1) e.key: e.value,
  };
  final codigoUnico = {
    for (final e in porCodigo.entries)
      if (e.value.length == 1) e.key: e.value.first,
  };

  // --- Regra 3: nome exato contra o DENOM_CIA ---
  final porNome = <String, String>{};
  for (final n in ['dfp_cia_aberta_2024.csv', 'itr_cia_aberta_2024.csv']) {
    final f = File('$dir/$n');
    if (!f.existsSync()) continue;
    for (final r in _lerCsv(f)) {
      final nome = r['DENOM_CIA'];
      final cnpj = r['CNPJ_CIA'];
      if (nome == null || cnpj == null) continue;
      porNome.putIfAbsent(CvmBridge.normalizarNome(nome), () => cnpj);
    }
  }

  // --- Universo ---
  final uni = (jsonDecode(
    File('docs/validacao/universo.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();
  final tickers = [for (final u in uni) u['ticker'] as String];
  final nomes = {
    for (final u in uni)
      if (u['nome'] != null) u['ticker'] as String: u['nome'] as String,
  };

  final ponte = CvmBridge.resolverUniverso(
    tickers,
    porCodigo: codigoUnico,
    porNome: porNome,
    nomes: nomes,
  );
  final faltando = [for (final t in tickers) if (!ponte.containsKey(t)) t];

  stdout.writeln('== Ponte ticker -> CNPJ, pelas regras do núcleo ==\n');
  stdout.writeln('  linhas de FCA lidas        : $linhasFca');
  stdout.writeln('    em branco                : $emBranco '
      '(${(100 * emBranco / linhasFca).toStringAsFixed(1)}%)');
  stdout.writeln('    descartadas pelo formato : $descartadas');
  stdout.writeln('    códigos com CNPJ único   : ${codigoUnico.length}');
  stdout.writeln('    AMBÍGUOS                 : ${ambiguos.length} '
      '${ambiguos.keys.take(6).join(", ")}');
  stdout.writeln('');
  stdout.writeln('  universo: ${tickers.length}');
  stdout.writeln('  resolvidos: ${ponte.length} '
      '(${(100 * ponte.length / tickers.length).toStringAsFixed(1)}%)');
  stdout.writeln('  companhias distintas: ${ponte.values.toSet().length}');
  stdout.writeln('  sem ponte: ${faltando.length}  ${faltando.join(" ")}');
  final inesperados =
      faltando.where((t) => !CvmBridge.semPonte.contains(t)).toList();
  stdout.writeln('  fora do que o núcleo declara em semPonte: '
      '${inesperados.isEmpty ? "nenhum" : inesperados.join(" ")}');

  // A regra geral: uma companhia alcançada por duas raízes tem uma ponte
  // errada, e nenhuma medição interna diz qual.
  final conflitos = CvmBridge.conflitosDeRaiz(ponte);
  stdout.writeln('');
  stdout.writeln('  companhias alcançadas por mais de uma raiz: '
      '${conflitos.length}');
  for (final e in conflitos.entries) {
    final tickers = [for (final t in ponte.entries) if (t.value == e.key) t.key]
      ..sort();
    stdout.writeln('    ${e.key}  raízes ${e.value.join("/")}  '
        '-> ${tickers.join(" ")}');
  }

  File('docs/validacao/ponte_cvm.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'medidoEm': '2026-09-11',
      'universo': tickers.length,
      'resolvidos': ponte.length,
      'companhias': ponte.values.toSet().length,
      'semPonte': faltando,
      'ponte': ponte,
    }),
  );
  stdout.writeln('\n  gravado docs/validacao/ponte_cvm.json');
}
