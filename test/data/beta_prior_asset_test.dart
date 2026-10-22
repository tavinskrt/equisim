import 'dart:convert';
import 'dart:io';

import 'package:equisim/data/repositories/beta_prior_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// O prior transversal do beta versionado é o que o build leva (item B11).
///
/// **Sem ele o motor é outro**: beta cru, WACC estático, e nenhum dos caminhos
/// que as decisões 40 a 46 descrevem. No aplicativo isso vira ressalva — a
/// avaliação segue e diz que seguiu sem o prior. Aqui **reprova a suíte**: um
/// build que sai sem o prior por descuido não é estado aceitável.
void main() {
  final file = File(betaPriorAsset);

  test('o pacote existe e está declarado como asset', () {
    expect(file.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/beta_prior_empacotar.dart` e '
            'versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/mercado/'));
  });

  test('o pacote é legível pelo codec deste build', () {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['versao'], BetaPriorCodec.version,
        reason: 'o codec mudou de versão e o pacote não foi regerado');
    final parsed = BetaPriorCodec.decode(json);
    expect(parsed, isNotNull);
    // Beta desalavancado do universo brasileiro: 0,64 em 14/09/2026. A faixa é
    // larga de propósito — o que ela barra é pacote corrompido ou gerado com
    // outra régua de alavancagem, não uma variação de mercado.
    expect(parsed!.prior.unleveredUniverse, inInclusiveRange(0.2, 1.5));
    expect(parsed.prior.dispersion, greaterThan(0));
    expect(parsed.prior.unleveredBySector, isNotEmpty);
    expect(parsed.observations, greaterThan(100));
  });

  test('cada mediana setorial usa a chave da B3, e não a da fonte de preços',
      () {
    final parsed = BetaPriorCodec.decode(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)!;
    // As chaves são as do setor econômico da B3 (decisão 87). Uma chave fora
    // dessa lista diz que o prior foi resolvido sobre outra camada de dados, e
    // aí ele agrupa outros pares.
    const fromB3 = {
      'bens-industriais',
      'comunicacoes',
      'consumo-ciclico',
      'consumo-nao-ciclico',
      'financeiro',
      'materiais-basicos',
      'petroleo-gas-e-biocombustiveis',
      'saude',
      'tecnologia-da-informacao',
      'utilidade-publica',
      'outros',
    };
    for (final k in parsed.prior.unleveredBySector.keys) {
      expect(fromB3, contains(k));
    }
  });

  group('O repositório', () {
    test('sem pacote, devolve nulo e diz que o motor é o do beta cru',
        () async {
      final r = BetaPriorRepository(
        loadPackage: () async => throw Exception('sem asset'),
      );
      final reading = await r.reading();
      expect(reading.prior, isNull);
      expect(reading.note, contains('beta'));
    });

    test('pacote velho demais não é usado, e a ressalva diz de quando é',
        () async {
      final package = jsonEncode(BetaPriorCodec.encode(
        const BetaPrior(
          unleveredBySector: {},
          unleveredUniverse: 0.64,
          dispersion: 0.5,
        ),
        generatedAt: DateTime(2020, 1, 1),
        observations: 300,
      ));
      final r = BetaPriorRepository(
        loadPackage: () async => package,
        today: () => DateTime(2026, 9, 14),
      );
      final reading = await r.reading();
      expect(reading.prior, isNull);
      expect(reading.note, contains('2020-01-01'));
    });

    test('pacote dentro da validade passa sem ressalva', () async {
      final package = jsonEncode(BetaPriorCodec.encode(
        const BetaPrior(
          unleveredBySector: {'saude': 0.78},
          unleveredUniverse: 0.64,
          dispersion: 0.5,
        ),
        generatedAt: DateTime(2026, 6, 30),
        observations: 300,
      ));
      final r = BetaPriorRepository(
        loadPackage: () async => package,
        today: () => DateTime(2026, 9, 14),
      );
      final reading = await r.reading();
      expect(reading.note, isNull);
      expect(reading.prior!.unleveredFor('saude'), closeTo(0.78, 1e-9));
      expect(reading.prior!.unleveredFor('nao-existe'), closeTo(0.64, 1e-9));
    });

    test('versão desconhecida é recusada, e não lida pela metade', () async {
      final r = BetaPriorRepository(
        loadPackage: () async => jsonEncode({
          'versao': BetaPriorCodec.version + 1,
          'universo': 0.64,
          'dispersao': 0.5,
          'geradoEm': '2026-09-14',
        }),
      );
      expect((await r.reading()).prior, isNull);
    });
  });
}
