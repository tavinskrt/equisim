import 'dart:convert';
import 'dart:io';

import 'package:equisim/data/repositories/calibrated_band_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A faixa calibrada é o que o aplicativo declara como incerteza (item C2,
/// decisão 92). Pacote ausente, ilegível ou fora do critério reprova a suíte:
/// no aplicativo, a ausência só esconde o cartão, e o lugar de pegar o descuido
/// é antes do build.
void main() {
  final file = File(calibratedBandAsset);

  test('existe, está declarado e é legível', () {
    expect(file.existsSync(), isTrue,
        reason: 'gerar com `python tool/cobertura_banda.py` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/validacao/'));
    final tables = CalibratedBandCodec.decode(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    for (final months in const [12, 36]) {
      for (final nominal in const [0.5, 0.8, 0.9]) {
        expect(
            CalibratedBand.select(tables, months: months, nominal: nominal),
            isNotNull,
            reason: 'faltou a faixa de $months meses a ${nominal * 100}%');
      }
    }
  });

  // **A cobertura declarada é a medida.** O pacote não pode dizer ao aplicativo
  // uma cobertura diferente da que a ferramenta mediu, e a forma do pacote é a
  // que a regra da §9 de `cobertura_banda.md` escolheu — hoje a da volatilidade
  // (decisão 100). Até 15/09/2026 este teste exigia a cobertura a até 5 p.p. da
  // nominal; o critério do R2 mora na §7 do plano, e quem o persegue é o C2c.
  test('a cobertura fora da amostra do pacote é a que cobertura_banda mediu', () {
    final tables = CalibratedBandCodec.decode(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    final measurement = jsonDecode(
        File('docs/validacao/cobertura_banda_trimestral.json')
            .readAsStringSync()) as Map<String, dynamic>;
    Map<String, dynamic> field(Map<String, dynamic> m, String k) =>
        m[k] as Map<String, dynamic>;
    final form = field(measurement, 'regraDoPacote')['forma'] as String;
    for (final t in tables) {
      expect(t.outOfSampleCoverage, isNotNull);
      final horizon = field(field(measurement, 'horizontes'), '${t.months}');
      final measurements = t is VolatilityBandTable
          ? field(field(field(horizon, 'formaFixada'), 'formas'), form)
          : field(field(horizon, 'recalibrada'), 'justo');
      final measured =
          field(measurements, 'cobertura')['${(t.nominal * 100).round()}%'] as num;
      expect(t.outOfSampleCoverage, closeTo(measured / 100, 1e-9),
          reason: '${t.months} meses a ${t.nominal}');
      // A faixa central mais larga contém a mais estreita.
      final narrow = CalibratedBand.select(tables,
          months: t.months, nominal: t.nominal - 0.1);
      if (narrow == null) continue;
      switch ((t, narrow)) {
        case (FairValueBandTable(:final lowerFactor, :final upperFactor),
              FairValueBandTable narrow):
          expect(lowerFactor, lessThanOrEqualTo(narrow.lowerFactor));
          expect(upperFactor, greaterThanOrEqualTo(narrow.upperFactor));
        case (VolatilityBandTable(:final a, :final b, :final zLower, :final zUpper),
              VolatilityBandTable narrow):
          // O centro é o mesmo nas três frequências do horizonte; o que muda
          // são os quantis.
          expect(a, closeTo(narrow.a, 1e-12));
          expect(b, closeTo(narrow.b, 1e-12));
          expect(zLower, lessThanOrEqualTo(narrow.zLower));
          expect(zUpper, greaterThanOrEqualTo(narrow.zUpper));
        case _:
          fail('o pacote mistura formas em ${t.months} meses');
      }
    }
  });

  // A faixa da volatilidade precisa do preço e da volatilidade do papel; a do
  // justo, não. O aplicativo lê a que estiver no pacote, e o cartão de
  // avaliação passa os dois.
  test('a faixa do pacote se forma com o que a avaliação tem', () {
    final tables = CalibratedBandCodec.decode(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    for (final t in tables) {
      final band = CalibratedBand.of(
        Money.fromReais(42.80),
        t,
        marketPrice: Money.fromReais(33.15),
        volatility: 0.42,
      );
      expect(band, isNotNull, reason: '${t.months} meses a ${t.nominal}');
      expect(band!.low.cents, lessThan(band.high.cents));
    }
  });

  test('sem pacote utilizável o repositório devolve vazio, e não falha',
      () async {
    final broken =
        CalibratedBandRepository(loadPackage: () async => 'não é json');
    expect(await broken.tables(), isEmpty);
    final missing = CalibratedBandRepository(
        loadPackage: () async => throw const FileSystemException('sem'));
    expect(await missing.tables(), isEmpty);
  });
}
