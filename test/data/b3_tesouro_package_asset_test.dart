import 'dart:convert';
import 'dart:io';

import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Os pacotes versionados da B3 e do Tesouro são o que o build leva.
///
/// No aplicativo, ausência vira recuo — a ponte segue a regra da fonte, a
/// curva recua para os dois pontos. Aqui, reprova a suíte: build que sai sem
/// eles por descuido é defeito, e o lugar de pegá-lo é antes do build.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('Registro de emissores da B3 — decisão 83', () {
    final arquivo = File(b3RegistryAsset);

    test('existe e está declarado', () {
      expect(arquivo.existsSync(), isTrue,
          reason: 'gerar com `dart run tool/b3_empacotar.dart` e versionar');
      expect(pubspec, contains('- assets/b3/'));
    });

    test('é legível e cobre o universo', () {
      final emissores = B3RegistryCodec.decodePackage(
          jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
      expect(emissores, isNotEmpty,
          reason: 'versão do codec mudou e o pacote não foi regerado');
      final universo = (jsonDecode(
        File('docs/validacao/universo.json').readAsStringSync(),
      ) as List)
          .map((e) => ((e as Map<String, dynamic>)['ticker'] as String).substring(0, 4))
          .toSet();
      final cobertos = universo.where((r) => emissores[r]?.totalShares != null);
      // 297 de 297 emissores em 14/09/2026.
      expect(cobertos.length / universo.length, greaterThanOrEqualTo(0.95));
    });
  });

  group('Cotações do Tesouro — decisão 84', () {
    final arquivo = File(tesouroQuotesAsset);

    test('existe e está declarado', () {
      expect(arquivo.existsSync(), isTrue,
          reason: 'gerar com `dart run tool/curva_empacotar.dart` e versionar');
      expect(pubspec, contains('- assets/tesouro/'));
    });

    test('é legível e monta uma curva na própria data', () {
      final json = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
      final cotacoes = TreasuryQuotesCodec.decode(json);
      expect(cotacoes, isNotEmpty);
      final gerado = DateTime.parse('${json['geradoEm']}T00:00:00Z');
      expect(TreasuryCurve.at(cotacoes, gerado), isNotNull,
          reason: 'o pacote precisa sustentar uma curva, ao menos no dia dele');
    });
  });
}
