import 'dart:convert';
import 'dart:io';

import 'package:equisim/data/repositories/market_premium_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A série do prêmio implícito versionada é o que o build leva (decisão 142).
///
/// **Sem ela o prêmio é outro**: os 5,5% parametrizados, quatro pontos acima da
/// média de dez anos que o preço da bolsa embute. No aplicativo isso vira
/// ressalva; aqui **reprova a suíte**: um build que sai sem a série por
/// descuido não é estado aceitável.
void main() {
  final file = File(marketPremiumAsset);

  /// Trimestres de 2011 a meados de 2026, com `r − Rf` igual a [premio].
  String package(double premium, {DateTime? generated}) =>
      jsonEncode(ImpliedPremiumCodec.encode(ImpliedPremiumPackage(
        generatedAt: generated ?? DateTime.utc(2026, 9, 14),
        quarters: [
          for (var year = 2011; year <= 2026; year++)
            for (final month in const [3, 6, 9, 12])
              if (!(year == 2026 && month > 6))
                ImpliedPremiumQuarter(
                  date: DateTime.utc(year, month + 1, 0),
                  impliedReturn: 0.12 + premium,
                  riskFree: 0.12,
                ),
        ],
      )));

  test('o pacote existe e está declarado como asset', () {
    expect(file.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/premio_implicito.dart --so-serie` e '
            'versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/mercado/'));
  });

  test('o pacote é legível pelo codec deste build, e a média é plausível', () {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['versao'], ImpliedPremiumCodec.version,
        reason: 'o codec mudou de versão e o pacote não foi regerado');
    final parsed = ImpliedPremiumCodec.decode(json);
    expect(parsed, isNotNull);
    final mean = parsed!.normalizedAt(parsed.generatedAt);
    // A média de dez anos ficou entre 1% e 1,6% em todas as datas do backtest
    // (premio_implicito.md). A faixa é larga de propósito: o que ela barra é
    // pacote corrompido, com o prêmio em pontos em vez de fração, ou com o
    // sinal trocado.
    expect(mean, isNotNull);
    expect(mean, inInclusiveRange(-0.02, 0.06));
    expect(parsed.window(parsed.generatedAt).length, ImpliedPremiumPackage.windowYears * 4,
        reason: 'a série tem de cobrir os dez anos até a data do pacote');
  });

  group('O repositório', () {
    test('sem pacote, devolve os 5,5% parametrizados e diz isso', () async {
      final r = MarketPremiumRepository(
        loadPackage: () async => throw Exception('sem asset'),
      );
      final reading = await r.reading();
      expect(reading.premium, CapmInputs.defaultMarketPremium);
      expect(reading.source, MarketPremiumSource.parameterized);
      expect(reading.note, contains('5,5%'));
    });

    test('pacote recente: a média de dez anos, sem ressalva', () async {
      final r = MarketPremiumRepository(
        loadPackage: () async => package(0.0124),
        today: () => DateTime(2026, 10, 1),
      );
      final reading = await r.reading();
      expect(reading.premium, closeTo(0.0124, 1e-12));
      expect(reading.source, MarketPremiumSource.impliedNormalized);
      expect(reading.note, isNull);
    });

    test('pacote velho continua valendo, e a ressalva diz de quando é',
        () async {
      final r = MarketPremiumRepository(
        loadPackage: () async => package(0.0124),
        today: () => DateTime(2027, 9, 14),
      );
      final reading = await r.reading();
      // A média é a da data do pacote, e não a de uma janela que perdeu
      // trimestres sem ganhar nenhum.
      expect(reading.premium, closeTo(0.0124, 1e-12));
      expect(reading.source, MarketPremiumSource.impliedNormalized);
      expect(reading.note, contains('2026-09-14'));
    });

    test('pacote ilegível cai nos 5,5%', () async {
      final r = MarketPremiumRepository(
        loadPackage: () async => '{"versao": 99}',
      );
      final reading = await r.reading();
      expect(reading.source, MarketPremiumSource.parameterized);
    });
  });
}
