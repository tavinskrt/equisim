// O controle acionário, do Formulário Cadastral da CVM (item B46).
//
// O histórico sai das linhas do FCA de todos os anos, com a data da mudança
// tirada da coluna que a companhia declara quando ela é plausível; e a
// avaliação de uma estatal ganha a ressalva sem mudar o preço justo.
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

ShareholderControlFiling _fca(int ano, String especie, [DateTime? data]) =>
    (reference: DateTime(ano), species: especie, speciesDate: data);

final _ticker = Ticker.parse('ESTA3');

FundamentalsSnapshot _ano(int y, double e) => FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * e,
      ebit: 1400 * e,
      ebitda: 1900 * e,
      netIncome: 700 * e,
      incomeBeforeTax: 1000 * e,
      incomeTaxExpense: -300 * e,
      interestExpense: 120,
      earningsPerShare: 0.7 * e / 3,
      cash: 500,
      shortTermDebt: 400,
      longTermDebt: 1600,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 2.0 * e,
      nopat: 924 * e,
      sharesOutstanding: 3000,
      sharesOutstandingAsOf: 3000,
      marketCap: 30000,
    );

ValuationResult _avaliar({required bool estatal}) {
  final r = ValuationCascade.evaluate(ValuationInputs(
    ticker: _ticker,
    asOf: DateTime(2026, 9, 9),
    fundamentals: [
      for (var i = 15; i >= 0; i--)
        _ano(2025 - i, math.pow(1.05, 15 - i).toDouble()),
    ],
    marketPrice: 10.0,
    capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.012),
    declaredTerminalRiskFreeRate: 0.094,
    stateControlled: estatal,
  ));
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

void main() {
  group('a espécie do FCA', () {
    test('holding é a mesma espécie, e texto vazio não diz nada', () {
      expect(ShareholderControl.fromFca('Estatal Holding'),
          ShareholderControl.state);
      expect(ShareholderControl.fromFca('Privado Holding'),
          ShareholderControl.private);
      expect(ShareholderControl.fromFca('Estrangeiro'),
          ShareholderControl.foreign);
      expect(ShareholderControl.fromFca(''), isNull);
    });
  });

  group('o histórico', () {
    test('a privatização vale do dia declarado pela espécie nova', () {
      // O caso da Eletrobras: os formulários de 2022 a 2024 declaram a data da
      // fundação, e os de 2025 e 2026, o dia da privatização.
      final h = ShareholderControlHistory.fromFilings([
        _fca(2020, 'Estatal Holding', DateTime(1962, 6, 11)),
        _fca(2021, 'Estatal Holding', DateTime(1971, 1, 28)),
        _fca(2022, 'Privado Holding', DateTime(1971, 1, 28)),
        _fca(2023, 'Privado Holding', DateTime(1971, 1, 28)),
        _fca(2025, 'Privado Holding', DateTime(2022, 6, 17)),
      ]);
      expect(h, hasLength(2));
      expect(h.last.since, DateTime.utc(2022, 6, 17));
      expect(ShareholderControlHistory.at(h, DateTime(2022, 3, 31)),
          ShareholderControl.state);
      expect(ShareholderControlHistory.at(h, DateTime(2022, 6, 30)),
          ShareholderControl.private);
    });

    test('sem data plausível, a mudança vale da referência do formulário novo',
        () {
      final h = ShareholderControlHistory.fromFilings([
        _fca(2021, 'Estatal'),
        _fca(2022, 'Privado'),
      ]);
      expect(h.last.since, DateTime.utc(2022));
    });

    test('antes do primeiro formulário não há espécie', () {
      final h = ShareholderControlHistory.fromFilings([_fca(2015, 'Estatal')]);
      expect(ShareholderControlHistory.at(h, DateTime(2014, 12, 31)), isNull);
      expect(ShareholderControlHistory.at(h, DateTime(2015)),
          ShareholderControl.state);
    });

    test('o pacote volta igual, e versão estranha é recusada', () {
      final h = {
        'AXIA': ShareholderControlHistory.fromFilings([
          _fca(2021, 'Estatal'),
          _fca(2022, 'Privado', DateTime(2022, 6, 17)),
        ]),
      };
      final json = ShareholderControlHistory.encode(h,
          geradoEm: DateTime(2026, 9, 14));
      final lido = ShareholderControlHistory.decode(json)!;
      expect(lido.geradoEm, DateTime.utc(2026, 9, 14));
      expect(lido.porEmissor['AXIA']!.map((p) => p.since),
          [DateTime.utc(2021), DateTime.utc(2022, 6, 17)]);
      expect(ShareholderControlHistory.decode({...json, 'versao': 99}), isNull);
    });
  });

  group('a avaliação', () {
    test('a estatal ganha a ressalva e o aviso, e o preço não muda', () {
      final privada = _avaliar(estatal: false);
      final estatal = _avaliar(estatal: true);
      expect(estatal.fairValue, privada.fairValue);
      expect(estatal.diagnostics!.caveats,
          contains(ValuationCaveat.controleEstatal));
      expect(privada.diagnostics!.caveats,
          isNot(contains(ValuationCaveat.controleEstatal)));
      expect(estatal.warnings.where((w) => w.contains('controle estatal')),
          hasLength(1));
      expect(privada.warnings.where((w) => w.contains('controle estatal')),
          isEmpty);
    });
  });
}
