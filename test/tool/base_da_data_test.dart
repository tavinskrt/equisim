// A ponte por papel na data da coorte (item C3).
//
// O que se confere aqui é o que a montagem antiga errava por construção: o
// preço na base de ações de hoje contra a contagem na base do exercício, e a
// razão de unidade que saía 1 para qualquer unit. As referências são grandezas
// de fora da função testada — o financeiro do COTAHIST, a composição declarada
// da unit, a razão de unidade medida pelo próprio motor.
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/b3/proventos.dart';
import '../../tool/coortes/base_da_data.dart';

DateTime _d(int a, int m, int d) => DateTime.utc(a, m, d);

/// Pregões diários de [from] em diante, com fechamento e financeiro dados.
List<TradingDay> _tradingDays(DateTime from, List<double> closes,
    {double tradedValue = 1e6}) => [
      for (var i = 0; i < closes.length; i++)
        TradingDay(from.add(Duration(days: i)), closes[i], 100, tradedValue),
    ];

void main() {
  group('especieDo', () {
    test('lê a espécie pelo número do ticker', () {
      expect(kindOf('SAPR3'), ShareKind.common);
      expect(kindOf('SAPR4'), ShareKind.preferred);
      expect(kindOf('USIM6'), ShareKind.preferred);
      expect(kindOf('SAPR11'), ShareKind.unit);
      expect(kindOf('AZUL53'), isNull);
      expect(kindOf('AZUL97'), isNull);
    });
  });

  group('codigosDaCompanhia', () {
    test('a unit leva às espécies da mesma raiz, que a FCA nem sempre declara', () {
      final c = companyCodes({'ALUP11'});
      expect(c, containsAll(['ALUP11', 'ALUP3', 'ALUP4', 'ALUP5', 'ALUP6']));
      expect(companyCodes({'BHIA3', 'VVAR3'}), containsAll(['VVAR4', 'BHIA11']));
    });
  });

  group('encadear', () {
    test('junta o código anterior da mesma espécie, e o de hoje vence no dia comum',
        () {
      final cotahist = {
        'VVAR3': _tradingDays(_d(2020, 1, 1), [10, 11, 12]),
        'BHIA3': _tradingDays(_d(2020, 1, 3), [120, 130]),
        'VVAR4': _tradingDays(_d(2020, 1, 1), [99, 99, 99]),
      };
      final s = chain('BHIA3', {'BHIA3', 'VVAR3', 'VVAR4'}, cotahist);
      expect([for (final p in s) p.close], [10, 11, 120, 130]);
    });
  });

  group('fatorDeBase', () {
    test('mede o evento posterior pelo preço bruto contra o da fonte', () {
      // Grupamento de 10 para 1 depois da coorte: a fonte, na base de hoje,
      // publica o fechamento de 2020 multiplicado por dez.
      final rawSessions = _tradingDays(_d(2020, 9, 28), [8.5, 8.6, 8.4]);
      final source = PriceSeries(ticker: Ticker.parse('MGLU3'), points: [
        for (final p in rawSessions) PricePoint(date: p.date, close: p.close * 10),
      ]);
      final f = baseFactorOf(source: source, rawSessions: rawSessions, date: _d(2020, 9, 30));
      expect(f!.factor, closeTo(0.1, 1e-12));
      expect(f.tradingDay.close, 8.4);
    });

    test('sem pregão a até dez dias não há preço da data', () {
      final rawSessions = _tradingDays(_d(2020, 8, 1), [5, 5]);
      final source = PriceSeries(ticker: Ticker.parse('ABCD3'), points: [
        PricePoint(date: _d(2020, 8, 1), close: 5),
        PricePoint(date: _d(2020, 9, 30), close: 5),
      ]);
      expect(baseFactorOf(source: source, rawSessions: rawSessions, date: _d(2020, 9, 30)),
          isNull);
    });

    test('sem fechamento da fonte no dia do pregão, recusa em vez de misturar dias',
        () {
      final rawSessions = _tradingDays(_d(2020, 9, 30), [5]);
      final source = PriceSeries(ticker: Ticker.parse('ABCD3'), points: [
        PricePoint(date: _d(2020, 9, 29), close: 50),
      ]);
      expect(baseFactorOf(source: source, rawSessions: rawSessions, date: _d(2020, 9, 30)),
          isNull);
    });
  });

  group('serieNaBaseDaData', () {
    test('a Porta 0 volta a medir o financeiro do COTAHIST', () {
      // A fonte ajusta o fechamento e não o volume: com o grupamento de 10 para
      // 1 depois, `fechamento × volume` da fonte sai dez vezes o negociado.
      final rawSessions = [
        for (var i = 0; i < 30; i++)
          TradingDay(_d(2020, 9, 1).add(Duration(days: i)), 8.0 + i % 3, 100,
              1e6 + 1e4 * i),
      ];
      final source = PriceSeries(ticker: Ticker.parse('MGLU3'), points: [
        for (final p in rawSessions)
          PricePoint(
              date: p.date, close: p.close * 10, volume: p.tradedValue! / p.close),
      ]);
      final wrongValue = EligibilityGate.medianTradedValue(source)!;
      final base = seriesOnDateBasis(source, rawSessions, 0.1);
      final right = EligibilityGate.medianTradedValue(base)!;
      final tradedValues = [for (final p in rawSessions) p.tradedValue!]..sort();
      final median = (tradedValues[14] + tradedValues[15]) / 2;
      expect(wrongValue, closeTo(10 * median, 1e-3));
      expect(right, closeTo(median, 1e-3));
      expect(base.points.last.close, closeTo(rawSessions.last.close, 1e-12));
    });

    test('dia sem COTAHIST mantém o volume da fonte', () {
      final source = PriceSeries(ticker: Ticker.parse('ABCD3'), points: [
        PricePoint(date: _d(2020, 9, 1), close: 20, volume: 7),
      ]);
      final s = seriesOnDateBasis(source, const [], 0.5);
      expect(s.points.single.close, 10);
      expect(s.points.single.volume, 7);
    });
  });

  group('ValorDeMercado.naData', () {
    test('soma as espécies, cada uma pelo preço do papel mais negociado dela', () {
      final securities = {
        'ABCD3': _tradingDays(_d(2020, 9, 25), [10, 10], tradedValue: 5e5),
        'ABCD5': _tradingDays(_d(2020, 9, 25), [11, 11], tradedValue: 1e5),
        'ABCD6': _tradingDays(_d(2020, 9, 25), [12, 12], tradedValue: 9e5),
      };
      final v = MarketValue.atDate(
          shares: 100, commonFraction: 0.4, securities: securities, date: _d(2020, 9, 30));
      expect(v!.value, closeTo(100 * (0.4 * 10 + 0.6 * 12), 1e-9));
      expect(v.origin, 'especies');
    });

    test('espécie sem pregão vai pelo preço da outra', () {
      final v = MarketValue.atDate(
        shares: 100,
        commonFraction: 0.5,
        securities: {'ABCD4': _tradingDays(_d(2020, 9, 29), [6])},
        date: _d(2020, 9, 30),
      );
      expect(v!.value, closeTo(600, 1e-9));
      expect(v.origin, 'umaEspecie');
    });

    test('pregão velho não dá preço, e sem papel nenhum não há valor', () {
      expect(
        MarketValue.atDate(
          shares: 100,
          commonFraction: 1,
          securities: {'ABCD3': _tradingDays(_d(2020, 8, 1), [6])},
          date: _d(2020, 9, 30),
        ),
        isNull,
      );
    });

    test('a unit volta a medir as ações dela — a montagem antiga dava 1', () {
      // SAPR11 é 1 ON + 4 PN. Com as duas espécies ao mesmo preço, a unit vale
      // cinco ações, e o motor tem de medir cinco.
      const shares = 1.5e9;
      const sharePrice = 5.0;
      const unitPrice = 5 * sharePrice;
      final securities = {
        'SAPR3': _tradingDays(_d(2020, 9, 29), [sharePrice]),
        'SAPR4': _tradingDays(_d(2020, 9, 29), [sharePrice]),
      };
      final v = MarketValue.atDate(
          shares: shares, commonFraction: 0.2, securities: securities, date: _d(2020, 9, 30));
      final composition = UnitCompositionCodec.parse('1 ON e 4 PN')!;
      expect(
        ValuationCascade.quotedUnitRatio(
            sharesOutstanding: shares, marketCap: v!.value, marketPrice: unitPrice),
        composition.toDouble(),
      );
      // A reescala antiga: valor de mercado = contagem × preço do próprio papel.
      expect(
        ValuationCascade.quotedUnitRatio(
            sharesOutstanding: shares,
            marketCap: shares * unitPrice,
            marketPrice: unitPrice),
        1.0,
      );
    });
  });

  group('ClassesDoCapital', () {
    Map<String, String> row(String ref, int version, String approval,
            double on, double pn,
            {String kind = 'Capital Integralizado'}) =>
        {
          'Tipo_Capital': kind,
          'Data_Referencia': ref,
          'Versao': '$version',
          'Data_Autorizacao_Aprovacao': approval,
          'Quantidade_Acoes_Ordinarias': '$on',
          'Quantidade_Acoes_Preferenciais': '$pn',
        };

    test('cada aprovação vale pela primeira declaração, na maior versão dela', () {
      final c = CapitalClasses.fromFre([
        row('2018-01-01', 1, '2017-04-30', 40, 60),
        row('2018-01-01', 2, '2017-04-30', 50, 50),
        // O formulário seguinte repete a aprovação antiga com outra divisão.
        row('2019-01-01', 1, '2017-04-30', 10, 90),
        row('2019-01-01', 1, '2019-03-15', 100, 0),
      ]);
      expect(c.at(_d(2016, 1, 1)), 0.5);
      expect(c.at(_d(2018, 6, 30)), 0.5);
      expect(c.at(_d(2019, 6, 30)), 1.0);
      expect(CapitalClasses.fromJson(c.toJson()).at(_d(2019, 6, 30)), 1.0);
    });

    test('sem capital integralizado, lê o emitido; sem nada, não divide', () {
      final c = CapitalClasses.fromFre(
          [row('2020-01-01', 1, '2019-01-01', 3, 1, kind: 'Capital Emitido')]);
      expect(c.at(_d(2020, 1, 1)), 0.75);
      expect(CapitalClasses.fromFre(const []).at(_d(2020, 1, 1)), isNull);
    });
  });

  // A leitura do texto passou ao núcleo em 20/09/2026 (item B16): ela deixou
  // de ser conferência de ferramenta e virou o que o motor usa, e por isso é
  // testada também em `unit_composition_test.dart`. Este caso fica porque é o
  // que confere a lista inteira contra a FCA de 2024.
  group('UnitCompositionCodec.parse', () {
    test('lê as composições declaradas na FCA de 2024', () {
      const cases = {
        '1 ação ordinária e 4 ações preferenciais': 5,
        '1 ON + 4 PN': 5,
        '1 ON / 2 PN': 3,
        '1 ON E 2 PN': 3,
        '1 ON+ 2PN': 3,
        '2 ações preferenciais e 1 ação ordinária': 3,
        '1 ON e 2 PN': 3,
        '1 PN + 3 Recibos de Subscrição': 1,
        '1 ON e 4 PN': 5,
        '1 KLBN3 + 4 KLBN4': 5,
        '1 ON + 1 PN': 2,
      };
      for (final e in cases.entries) {
        expect(UnitCompositionCodec.parse(e.key), e.value, reason: e.key);
      }
      expect(UnitCompositionCodec.parse('não se aplica'), isNull);
    });
  });
}
