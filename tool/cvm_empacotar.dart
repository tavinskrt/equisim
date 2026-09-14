// A1.9 — empacota os documentos da CVM do universo para o aplicativo.
//
// Lê a base ingerida, fica só com os tickers do universo e só com os campos que
// o motor lê, e grava no formato compacto de `CvmDocumentCodec`. O aplicativo
// carrega o pacote como asset e o mescla por `CvmFundamentalsRepository`.
//
// Uso:
//   dart run tool/cvm_ingerir.dart data/cvm
//   dart run tool/cvm_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'cvm/documentos.dart';

void main(List<String> args) {
  final universo = (jsonDecode(
          File('docs/validacao/universo.json').readAsStringSync()) as List)
      .map((e) => (e as Map<String, dynamic>)['ticker'] as String)
      .toSet();
  final docs = carregarDocumentos('data/cvm_exercicios.json', soTickers: universo);

  final pacote = CvmDocumentCodec.encodePackage(docs, geradoEm: DateTime.now());
  final saida = File('assets/cvm/documentos.json')..createSync(recursive: true);
  saida.writeAsStringSync(jsonEncode(pacote));

  final bytes = saida.lengthSync();
  final gz = gzip.encode(saida.readAsBytesSync()).length;
  final total = docs.values.fold<int>(0, (a, v) => a + v.length);
  stdout.writeln('== pacote da CVM para o aplicativo ==');
  stdout.writeln('  tickers: ${docs.length} de ${universo.length}');
  stdout.writeln('  documentos: $total');
  stdout.writeln('  tamanho: ${(bytes / 1e6).toStringAsFixed(2)} MB '
      '(${(gz / 1e6).toStringAsFixed(2)} MB comprimido)');
  stdout.writeln('  gravado ${saida.path}');
}
