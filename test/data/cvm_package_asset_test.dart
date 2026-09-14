import 'dart:convert';
import 'dart:io';

import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// O pacote da CVM versionado é o que o build leva (decisão 80).
///
/// No aplicativo, pacote ausente ou ilegível vira ressalva — a avaliação segue.
/// Aqui, **reprova a suíte**: um build que sai sem a CVM por descuido não é
/// estado aceitável, é defeito, e o lugar de pegá-lo é antes do build.
void main() {
  final arquivo = File(cvmPackageAsset);

  test('o pacote existe e está declarado como asset', () {
    expect(arquivo.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/cvm_empacotar.dart` e versionar');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/cvm/'));
  });

  test('o pacote é legível pelo codec deste build', () {
    final json = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    expect(json['versao'], CvmDocumentCodec.versao,
        reason: 'o codec mudou de versão e o pacote não foi regerado');
    expect(DateTime.tryParse('${json['geradoEm']}'), isNotNull);

    final documentos = CvmDocumentCodec.decodePackage(json);
    final universo = (jsonDecode(
      File('docs/validacao/universo.json').readAsStringSync(),
    ) as List)
        .map((e) => (e as Map<String, dynamic>)['ticker'] as String)
        .toSet();
    final cobertos = universo.where((t) => documentos[t]?.isNotEmpty ?? false);
    // 371 de 375 em 14/09/2026: os quatro sem ponte ticker↔CNPJ (A1.1).
    expect(cobertos.length / universo.length, greaterThanOrEqualTo(0.95),
        reason: 'pacote truncado ou gerado sobre outro universo');
  });

  test('todo documento do pacote tem período e demonstração', () {
    final json = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    final brutos = json['tickers'] as Map<String, dynamic>;
    final documentos = CvmDocumentCodec.decodePackage(json);
    for (final e in brutos.entries) {
      expect(documentos[e.key]?.length, (e.value as List).length,
          reason: '${e.key}: documento que o codec não consegue ler');
    }
  });
}
