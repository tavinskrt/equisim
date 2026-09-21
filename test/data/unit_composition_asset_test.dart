import 'dart:convert';
import 'dart:io';

import 'package:equisim/data/repositories/unit_composition_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A composição declarada das units versionada com o build (item B16).
///
/// **Sem ela a razão volta a ser inferida do valor de mercado**, que só acerta
/// quando ordinária e preferencial valem o mesmo. No aplicativo isso vira
/// ressalva; aqui reprova a suíte, porque um build sem o pacote avalia nove
/// papéis por uma convenção de fonte que ninguém declarou.
void main() {
  final arquivo = File(unitCompositionAsset);

  test('o pacote existe e está declarado como asset', () {
    expect(arquivo.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/unit_empacotar.dart` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/cvm/'));
  });

  test('as nove units do universo saem com a composição da FCA', () {
    final lido = UnitCompositionCodec.decodePackage(
        jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
    // Conferido contra o quadro de valores mobiliários da FCA de 2026. A
    // BPAC11 só aparece porque a chave é o CNPJ: o código de negociação dela
    // no formulário é `000000`.
    const esperado = {
      'ALUP11': 3,
      'BPAC11': 3,
      'BRBI11': 3,
      'ENGI11': 5,
      'IGTI11': 3,
      'KLBN11': 5,
      'SANB11': 2,
      'SAPR11': 5,
      'TAEE11': 3,
    };
    for (final e in esperado.entries) {
      final c = UnitCompositionCodec.at(
          lido[e.key] ?? const [], DateTime(2026, 9, 14));
      expect(c?.shares, e.value, reason: e.key);
      expect(c?.declared, isNotEmpty, reason: '${e.key} sem o texto declarado');
    }
  });

  test('a série é por ano, e a ENGI11 de 2018 já sai com cinco', () {
    final lido = UnitCompositionCodec.decodePackage(
        jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
    // Em 2018 a companhia declarou "1 ENG3 e 4 ENGI4": código de três letras,
    // que o leitor antigo não somava.
    expect(
        UnitCompositionCodec.at(lido['ENGI11']!, DateTime(2018, 12, 31))
            ?.shares,
        5);
    expect(lido['ENGI11']!.length, greaterThan(1),
        reason: 'um formulário por ano, e não só o último');
  });

  group('O repositório', () {
    test('devolve a composição vigente na data', () async {
      final r = UnitCompositionRepository(
        carregarPacote: () async => arquivo.readAsStringSync(),
      );
      expect(
          await r.sharesPerUnitFor(Ticker.parse('SAPR11'),
              asOf: DateTime(2026, 9, 14)),
          5);
      expect(
          await r.sharesPerUnitFor(Ticker.parse('BRBI11'),
              asOf: DateTime(2019, 1, 1)),
          isNull,
          reason: 'a BRBI11 só declara de 2022 em diante');
    });

    test('papel que não é unit não tem composição', () async {
      final r = UnitCompositionRepository(
        carregarPacote: () async => arquivo.readAsStringSync(),
      );
      expect(
          await r.sharesPerUnitFor(Ticker.parse('PETR4'),
              asOf: DateTime(2026, 9, 14)),
          isNull);
    });

    test('sem data, vale o relógio injetado — e ele é injetado', () async {
      // O provider não lê o relógio no ponto de uso: ele o entrega ao
      // repositório, que é o que torna a composição vigente testável.
      final r = UnitCompositionRepository(
        carregarPacote: () async => arquivo.readAsStringSync(),
        hoje: () => DateTime(2019, 1, 1),
      );
      expect(await r.sharesPerUnitFor(Ticker.parse('BRBI11')), isNull,
          reason: 'em 2019 a BRBI11 ainda não declarava');
      expect(await r.sharesPerUnitFor(Ticker.parse('SAPR11')), 5);
    });

    test('sem pacote, é transparente', () async {
      final r = UnitCompositionRepository(
        carregarPacote: () async => throw Exception('sem asset'),
      );
      expect(
          await r.sharesPerUnitFor(Ticker.parse('SAPR11'),
              asOf: DateTime(2026, 9, 14)),
          isNull);
    });
  });
}
