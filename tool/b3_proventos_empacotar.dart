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

const _saida = 'assets/b3/proventos.json';
final _desde = DateTime.utc(2015, 1, 1);

void main() {
  final todos = lerProventos();
  final pacote = <String, List<CashDividend>>{};
  var entram = 0, semPreco = 0, antigos = 0;
  for (final e in todos.entries) {
    final lista = <CashDividend>[];
    for (final p in e.value) {
      if (p.exDate.isBefore(_desde)) {
        antigos++;
        continue;
      }
      if (p.closeWithRights == null) {
        semPreco++;
        continue;
      }
      lista.add(p);
    }
    if (lista.isNotEmpty) {
      pacote[e.key] = lista;
      entram += lista.length;
    }
  }
  final consulta = Directory('data/b3/complemento')
      .listSync()
      .whereType<File>()
      .map((f) => (jsonDecode(f.readAsStringSync())
          as Map<String, dynamic>)['consultadoEm'] as String)
      .fold<String>('9999-12-31', (a, b) => b.compareTo(a) < 0 ? b : a);
  File(_saida)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(CashDividendsCodec.encode(pacote,
        geradoEm: DateTime.parse('${consulta}T00:00:00Z'))));
  stdout.writeln('  emissores: ${pacote.length}  proventos: $entram');
  stdout.writeln('  fora: $antigos antes de 2015, $semPreco sem preço com direito');
  stdout.writeln('  consulta mais antiga: $consulta');
  stdout.writeln('  tamanho: ${(File(_saida).lengthSync() / 1024).toStringAsFixed(0)} KB');
  stdout.writeln('  gravado $_saida');
}
