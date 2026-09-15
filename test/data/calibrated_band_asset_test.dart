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
  final arquivo = File(calibratedBandAsset);

  test('existe, está declarado e é legível', () {
    expect(arquivo.existsSync(), isTrue,
        reason: 'gerar com `python tool/cobertura_banda.py` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/validacao/'));
    final tabelas = CalibratedBandCodec.decode(
        jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
    for (final meses in const [12, 36]) {
      for (final nominal in const [0.5, 0.8, 0.9]) {
        expect(
            CalibratedBand.select(tabelas, months: meses, nominal: nominal),
            isNotNull,
            reason: 'faltou a faixa de $meses meses a ${nominal * 100}%');
      }
    }
  });

  // **A cobertura declarada é a medida** (decisão 97). Até 15/09/2026 este teste
  // exigia a cobertura a até 5 p.p. da nominal, e passava — sobre coortes com o
  // preço na base de ações de hoje. Na montagem corrigida a faixa não cobre, e
  // o critério do R2 continua sendo esse: ele mora na §7 do plano, desmarcado,
  // e o item C2c o persegue. O que o pacote não pode é declarar ao aplicativo
  // uma cobertura diferente da que a ferramenta mediu.
  test('a cobertura fora da amostra do pacote é a que cobertura_banda mediu', () {
    final tabelas = CalibratedBandCodec.decode(
        jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
    final medicao = jsonDecode(
        File('docs/validacao/cobertura_banda_trimestral.json')
            .readAsStringSync()) as Map<String, dynamic>;
    Map<String, dynamic> campo(Map<String, dynamic> m, String k) =>
        m[k] as Map<String, dynamic>;
    for (final t in tabelas) {
      expect(t.outOfSampleCoverage, isNotNull);
      final horizonte = campo(campo(medicao, 'horizontes'), '${t.months}');
      final cobertura =
          campo(campo(campo(horizonte, 'recalibrada'), 'justo'), 'cobertura');
      final medida = cobertura['${(t.nominal * 100).round()}%'] as num;
      expect(t.outOfSampleCoverage, closeTo(medida / 100, 1e-9),
          reason: '${t.months} meses a ${t.nominal}');
      // A faixa central mais larga contém a mais estreita.
      final estreita = CalibratedBand.select(tabelas,
          months: t.months, nominal: t.nominal - 0.1);
      if (estreita != null) {
        expect(t.lowerFactor, lessThanOrEqualTo(estreita.lowerFactor));
        expect(t.upperFactor, greaterThanOrEqualTo(estreita.upperFactor));
      }
    }
  });

  test('sem pacote utilizável o repositório devolve vazio, e não falha',
      () async {
    final quebrado =
        CalibratedBandRepository(carregarPacote: () async => 'não é json');
    expect(await quebrado.tables(), isEmpty);
    final ausente = CalibratedBandRepository(
        carregarPacote: () async => throw const FileSystemException('sem'));
    expect(await ausente.tables(), isEmpty);
  });
}
