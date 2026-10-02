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
  final arquivo = File(marketPremiumAsset);

  /// Trimestres de 2011 a meados de 2026, com `r − Rf` igual a [premio].
  String pacote(double premio, {DateTime? gerado}) =>
      jsonEncode(ImpliedPremiumCodec.encode(ImpliedPremiumPackage(
        geradoEm: gerado ?? DateTime.utc(2026, 9, 14),
        quarters: [
          for (var ano = 2011; ano <= 2026; ano++)
            for (final mes in const [3, 6, 9, 12])
              if (!(ano == 2026 && mes > 6))
                ImpliedPremiumQuarter(
                  date: DateTime.utc(ano, mes + 1, 0),
                  impliedReturn: 0.12 + premio,
                  riskFree: 0.12,
                ),
        ],
      )));

  test('o pacote existe e está declarado como asset', () {
    expect(arquivo.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/premio_implicito.dart --so-serie` e '
            'versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/mercado/'));
  });

  test('o pacote é legível pelo codec deste build, e a média é plausível', () {
    final json = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    expect(json['versao'], ImpliedPremiumCodec.versao,
        reason: 'o codec mudou de versão e o pacote não foi regerado');
    final lido = ImpliedPremiumCodec.decode(json);
    expect(lido, isNotNull);
    final media = lido!.normalizedAt(lido.geradoEm);
    // A média de dez anos ficou entre 1% e 1,6% em todas as datas do backtest
    // (premio_implicito.md). A faixa é larga de propósito: o que ela barra é
    // pacote corrompido, com o prêmio em pontos em vez de fração, ou com o
    // sinal trocado.
    expect(media, isNotNull);
    expect(media, inInclusiveRange(-0.02, 0.06));
    expect(lido.window(lido.geradoEm).length, ImpliedPremiumPackage.windowYears * 4,
        reason: 'a série tem de cobrir os dez anos até a data do pacote');
  });

  group('O repositório', () {
    test('sem pacote, devolve os 5,5% parametrizados e diz isso', () async {
      final r = MarketPremiumRepository(
        carregarPacote: () async => throw Exception('sem asset'),
      );
      final leitura = await r.reading();
      expect(leitura.premium, CapmInputs.defaultMarketPremium);
      expect(leitura.source, MarketPremiumSource.parameterized);
      expect(leitura.note, contains('5,5%'));
    });

    test('pacote recente: a média de dez anos, sem ressalva', () async {
      final r = MarketPremiumRepository(
        carregarPacote: () async => pacote(0.0124),
        hoje: () => DateTime(2026, 10, 1),
      );
      final leitura = await r.reading();
      expect(leitura.premium, closeTo(0.0124, 1e-12));
      expect(leitura.source, MarketPremiumSource.impliedNormalized);
      expect(leitura.note, isNull);
    });

    test('pacote velho continua valendo, e a ressalva diz de quando é',
        () async {
      final r = MarketPremiumRepository(
        carregarPacote: () async => pacote(0.0124),
        hoje: () => DateTime(2027, 9, 14),
      );
      final leitura = await r.reading();
      // A média é a da data do pacote, e não a de uma janela que perdeu
      // trimestres sem ganhar nenhum.
      expect(leitura.premium, closeTo(0.0124, 1e-12));
      expect(leitura.source, MarketPremiumSource.impliedNormalized);
      expect(leitura.note, contains('2026-09-14'));
    });

    test('pacote ilegível cai nos 5,5%', () async {
      final r = MarketPremiumRepository(
        carregarPacote: () async => '{"versao": 99}',
      );
      final leitura = await r.reading();
      expect(leitura.source, MarketPremiumSource.parameterized);
    });
  });
}
