// A4 — empacota os proventos da B3 para o aplicativo.
//
// O beta do aplicativo sai do retorno total do ativo (decisão 89), e o índice
// de retorno total precisa do provento **e** do preço com direito
// (`TotalReturnIndex`). Entra no pacote o provento com data ex a partir de
// 2015 — a janela do beta é de cinco anos, e a folga cobre a avaliação de
// qualquer data desde 2020 — e com preço com direito publicado pela B3: sem
// ele, o provento não entraria no índice e só ocuparia espaço.
//
// Uso:
//   python tool/b3_complemento_baixar.py
//   dart run tool/b3_proventos_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';

const _output = 'assets/b3/proventos.json';
final _since = DateTime.utc(2015, 1, 1);

void main() {
  final all = readDividends();
  final package = <String, List<CashDividend>>{};
  var included = 0, withoutPrice = 0, old = 0;
  for (final e in all.entries) {
    final list = <CashDividend>[];
    for (final p in e.value) {
      if (p.exDate.isBefore(_since)) {
        old++;
        continue;
      }
      if (p.closeWithRights == null) {
        withoutPrice++;
        continue;
      }
      list.add(p);
    }
    if (list.isNotEmpty) {
      package[e.key] = list;
      included += list.length;
    }
  }
  final queryDir = Directory('data/b3/complemento')
      .listSync()
      .whereType<File>()
      .map((f) => (jsonDecode(f.readAsStringSync())
          as Map<String, dynamic>)['consultadoEm'] as String)
      .fold<String>('9999-12-31', (a, b) => b.compareTo(a) < 0 ? b : a);
  File(_output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(CashDividendsCodec.encode(package,
        generatedAt: DateTime.parse('${queryDir}T00:00:00Z'))));
  stdout.writeln('  emissores: ${package.length}  proventos: $included');
  stdout.writeln('  fora: $old antes de 2015, $withoutPrice sem preço com direito');
  stdout.writeln('  consulta mais antiga: $queryDir');
  stdout.writeln('  tamanho: ${(File(_output).lengthSync() / 1024).toStringAsFixed(0)} KB');
  stdout.writeln('  gravado $_output');
}
