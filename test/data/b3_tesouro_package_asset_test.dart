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
    final file = File(b3RegistryAsset);

    test('existe e está declarado', () {
      expect(file.existsSync(), isTrue,
          reason: 'gerar com `dart run tool/b3_empacotar.dart` e versionar');
      expect(pubspec, contains('- assets/b3/'));
    });

    test('é legível e cobre o universo', () {
      final issuers = B3RegistryCodec.decodePackage(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      expect(issuers, isNotEmpty,
          reason: 'versão do codec mudou e o pacote não foi regerado');
      final universe = (jsonDecode(
        File('docs/validacao/universo.json').readAsStringSync(),
      ) as List)
          .map((e) => ((e as Map<String, dynamic>)['ticker'] as String).substring(0, 4))
          .toSet();
      final covered = universe.where((r) => issuers[r]?.totalShares != null);
      // 297 de 297 emissores em 14/09/2026.
      expect(covered.length / universe.length, greaterThanOrEqualTo(0.95));
    });

    test('classifica o setor de todo emissor do universo — item A5', () {
      final issuers = B3RegistryCodec.decodePackage(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      final universe = (jsonDecode(
        File('docs/validacao/universo.json').readAsStringSync(),
      ) as List)
          .map((e) => ((e as Map<String, dynamic>)['ticker'] as String).substring(0, 4))
          .toSet();
      final withoutSector = [
        for (final r in universe)
          if (issuers[r] != null && issuers[r]!.classification == null) r,
      ];
      expect(withoutSector, isEmpty,
          reason: 'rodar `python tool/b3_complemento_baixar.py` antes de empacotar');
      for (final bank in ['BRSR', 'PINE', 'SANB']) {
        final c = issuers[bank]!.classification!;
        expect(
            FinancialSectors.isFinancial(
                sectorKey: c.sectorKey, industry: c.industry),
            isTrue,
            reason: '$bank escapava da Porta 1 sem setor');
      }
    });
  });

  group('Proventos da B3 — decisão 89', () {
    final file = File(cashDividendsAsset);

    test('existe, é legível e traz o preço com direito', () {
      expect(file.existsSync(), isTrue,
          reason: 'gerar com `dart run tool/b3_proventos_empacotar.dart`');
      final dividends = CashDividendsCodec.decode(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      expect(dividends.length, greaterThan(200));
      expect(
          dividends.values.every((l) => l.every((p) => p.closeWithRights != null)),
          isTrue,
          reason: 'provento sem preço com direito não entra no índice');
    });
  });

  group('Prazo das outorgas — decisão 88', () {
    final file = File(concessionTermsAsset);

    test('existe e é legível', () {
      expect(file.existsSync(), isTrue,
          reason: 'gerar com `dart run tool/fre_outorgas.dart`');
      expect(pubspec, contains('- assets/cvm/'));
      final terms = ConcessionTermsCodec.decode(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      expect(terms, isNotEmpty);
      expect(terms['TAEE11'], isNotNull,
          reason: 'transmissora com 39 outorgas legíveis no FRE de 2022');
    });
  });

  group('Cotações do Tesouro — decisão 84', () {
    final file = File(treasuryQuotesAsset);

    test('existe e está declarado', () {
      expect(file.existsSync(), isTrue,
          reason: 'gerar com `dart run tool/curva_empacotar.dart` e versionar');
      expect(pubspec, contains('- assets/tesouro/'));
    });

    test('é legível e monta uma curva na própria data', () {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final quotes = TreasuryQuotesCodec.decode(json);
      expect(quotes, isNotEmpty);
      final generated = DateTime.parse('${json['geradoEm']}T00:00:00Z');
      expect(TreasuryCurve.at(quotes, generated), isNotNull,
          reason: 'o pacote precisa sustentar uma curva, ao menos no dia dele');
    });
  });
}
