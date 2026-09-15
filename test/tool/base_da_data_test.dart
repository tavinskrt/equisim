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
import '../../tool/cvm/codigos_fca.dart';

DateTime _d(int a, int m, int d) => DateTime.utc(a, m, d);

/// Pregões diários de [de] em diante, com fechamento e financeiro dados.
List<Pregao> _pregoes(DateTime de, List<double> fechamentos,
    {double financeiro = 1e6}) => [
      for (var i = 0; i < fechamentos.length; i++)
        Pregao(de.add(Duration(days: i)), fechamentos[i], 100, financeiro),
    ];

void main() {
  group('especieDo', () {
    test('lê a espécie pelo número do ticker', () {
      expect(especieDo('SAPR3'), Especie.ordinaria);
      expect(especieDo('SAPR4'), Especie.preferencial);
      expect(especieDo('USIM6'), Especie.preferencial);
      expect(especieDo('SAPR11'), Especie.unit);
      expect(especieDo('AZUL53'), isNull);
      expect(especieDo('AZUL97'), isNull);
    });
  });

  group('codigosDaCompanhia', () {
    test('a unit leva às espécies da mesma raiz, que a FCA nem sempre declara', () {
      final c = codigosDaCompanhia({'ALUP11'});
      expect(c, containsAll(['ALUP11', 'ALUP3', 'ALUP4', 'ALUP5', 'ALUP6']));
      expect(codigosDaCompanhia({'BHIA3', 'VVAR3'}), containsAll(['VVAR4', 'BHIA11']));
    });
  });

  group('encadear', () {
    test('junta o código anterior da mesma espécie, e o de hoje vence no dia comum',
        () {
      final cotahist = {
        'VVAR3': _pregoes(_d(2020, 1, 1), [10, 11, 12]),
        'BHIA3': _pregoes(_d(2020, 1, 3), [120, 130]),
        'VVAR4': _pregoes(_d(2020, 1, 1), [99, 99, 99]),
      };
      final s = encadear('BHIA3', {'BHIA3', 'VVAR3', 'VVAR4'}, cotahist);
      expect([for (final p in s) p.close], [10, 11, 120, 130]);
    });
  });

  group('fatorDeBase', () {
    test('mede o evento posterior pelo preço bruto contra o da fonte', () {
      // Grupamento de 10 para 1 depois da coorte: a fonte, na base de hoje,
      // publica o fechamento de 2020 multiplicado por dez.
      final brutos = _pregoes(_d(2020, 9, 28), [8.5, 8.6, 8.4]);
      final fonte = PriceSeries(ticker: Ticker.parse('MGLU3'), points: [
        for (final p in brutos) PricePoint(date: p.date, close: p.close * 10),
      ]);
      final f = fatorDeBase(fonte: fonte, brutos: brutos, data: _d(2020, 9, 30));
      expect(f!.fator, closeTo(0.1, 1e-12));
      expect(f.pregao.close, 8.4);
    });

    test('sem pregão a até dez dias não há preço da data', () {
      final brutos = _pregoes(_d(2020, 8, 1), [5, 5]);
      final fonte = PriceSeries(ticker: Ticker.parse('ABCD3'), points: [
        PricePoint(date: _d(2020, 8, 1), close: 5),
        PricePoint(date: _d(2020, 9, 30), close: 5),
      ]);
      expect(fatorDeBase(fonte: fonte, brutos: brutos, data: _d(2020, 9, 30)),
          isNull);
    });

    test('sem fechamento da fonte no dia do pregão, recusa em vez de misturar dias',
        () {
      final brutos = _pregoes(_d(2020, 9, 30), [5]);
      final fonte = PriceSeries(ticker: Ticker.parse('ABCD3'), points: [
        PricePoint(date: _d(2020, 9, 29), close: 50),
      ]);
      expect(fatorDeBase(fonte: fonte, brutos: brutos, data: _d(2020, 9, 30)),
          isNull);
    });
  });

  group('serieNaBaseDaData', () {
    test('a Porta 0 volta a medir o financeiro do COTAHIST', () {
      // A fonte ajusta o fechamento e não o volume: com o grupamento de 10 para
      // 1 depois, `fechamento × volume` da fonte sai dez vezes o negociado.
      final brutos = [
        for (var i = 0; i < 30; i++)
          Pregao(_d(2020, 9, 1).add(Duration(days: i)), 8.0 + i % 3, 100,
              1e6 + 1e4 * i),
      ];
      final fonte = PriceSeries(ticker: Ticker.parse('MGLU3'), points: [
        for (final p in brutos)
          PricePoint(
              date: p.date, close: p.close * 10, volume: p.financeiro! / p.close),
      ]);
      final errada = EligibilityGate.medianTradedValue(fonte)!;
      final base = serieNaBaseDaData(fonte, brutos, 0.1);
      final certa = EligibilityGate.medianTradedValue(base)!;
      final financeiros = [for (final p in brutos) p.financeiro!]..sort();
      final mediana = (financeiros[14] + financeiros[15]) / 2;
      expect(errada, closeTo(10 * mediana, 1e-3));
      expect(certa, closeTo(mediana, 1e-3));
      expect(base.points.last.close, closeTo(brutos.last.close, 1e-12));
    });

    test('dia sem COTAHIST mantém o volume da fonte', () {
      final fonte = PriceSeries(ticker: Ticker.parse('ABCD3'), points: [
        PricePoint(date: _d(2020, 9, 1), close: 20, volume: 7),
      ]);
      final s = serieNaBaseDaData(fonte, const [], 0.5);
      expect(s.points.single.close, 10);
      expect(s.points.single.volume, 7);
    });
  });

  group('ValorDeMercado.naData', () {
    test('soma as espécies, cada uma pelo preço do papel mais negociado dela', () {
      final papeis = {
        'ABCD3': _pregoes(_d(2020, 9, 25), [10, 10], financeiro: 5e5),
        'ABCD5': _pregoes(_d(2020, 9, 25), [11, 11], financeiro: 1e5),
        'ABCD6': _pregoes(_d(2020, 9, 25), [12, 12], financeiro: 9e5),
      };
      final v = ValorDeMercado.naData(
          acoes: 100, fracaoOrdinarias: 0.4, papeis: papeis, data: _d(2020, 9, 30));
      expect(v!.valor, closeTo(100 * (0.4 * 10 + 0.6 * 12), 1e-9));
      expect(v.origem, 'especies');
    });

    test('espécie sem pregão vai pelo preço da outra', () {
      final v = ValorDeMercado.naData(
        acoes: 100,
        fracaoOrdinarias: 0.5,
        papeis: {'ABCD4': _pregoes(_d(2020, 9, 29), [6])},
        data: _d(2020, 9, 30),
      );
      expect(v!.valor, closeTo(600, 1e-9));
      expect(v.origem, 'umaEspecie');
    });

    test('pregão velho não dá preço, e sem papel nenhum não há valor', () {
      expect(
        ValorDeMercado.naData(
          acoes: 100,
          fracaoOrdinarias: 1,
          papeis: {'ABCD3': _pregoes(_d(2020, 8, 1), [6])},
          data: _d(2020, 9, 30),
        ),
        isNull,
      );
    });

    test('a unit volta a medir as ações dela — a montagem antiga dava 1', () {
      // SAPR11 é 1 ON + 4 PN. Com as duas espécies ao mesmo preço, a unit vale
      // cinco ações, e o motor tem de medir cinco.
      const acoes = 1.5e9;
      const precoAcao = 5.0;
      const precoUnit = 5 * precoAcao;
      final papeis = {
        'SAPR3': _pregoes(_d(2020, 9, 29), [precoAcao]),
        'SAPR4': _pregoes(_d(2020, 9, 29), [precoAcao]),
      };
      final v = ValorDeMercado.naData(
          acoes: acoes, fracaoOrdinarias: 0.2, papeis: papeis, data: _d(2020, 9, 30));
      final composicao = CodigosFca.acoesNaComposicao('1 ON e 4 PN')!;
      expect(
        ValuationCascade.quotedUnitRatio(
            sharesOutstanding: acoes, marketCap: v!.valor, marketPrice: precoUnit),
        composicao.toDouble(),
      );
      // A reescala antiga: valor de mercado = contagem × preço do próprio papel.
      expect(
        ValuationCascade.quotedUnitRatio(
            sharesOutstanding: acoes,
            marketCap: acoes * precoUnit,
            marketPrice: precoUnit),
        1.0,
      );
    });
  });

  group('ClassesDoCapital', () {
    Map<String, String> linha(String ref, int versao, String aprovacao,
            double on, double pn,
            {String tipo = 'Capital Integralizado'}) =>
        {
          'Tipo_Capital': tipo,
          'Data_Referencia': ref,
          'Versao': '$versao',
          'Data_Autorizacao_Aprovacao': aprovacao,
          'Quantidade_Acoes_Ordinarias': '$on',
          'Quantidade_Acoes_Preferenciais': '$pn',
        };

    test('cada aprovação vale pela primeira declaração, na maior versão dela', () {
      final c = ClassesDoCapital.fromFre([
        linha('2018-01-01', 1, '2017-04-30', 40, 60),
        linha('2018-01-01', 2, '2017-04-30', 50, 50),
        // O formulário seguinte repete a aprovação antiga com outra divisão.
        linha('2019-01-01', 1, '2017-04-30', 10, 90),
        linha('2019-01-01', 1, '2019-03-15', 100, 0),
      ]);
      expect(c.at(_d(2016, 1, 1)), 0.5);
      expect(c.at(_d(2018, 6, 30)), 0.5);
      expect(c.at(_d(2019, 6, 30)), 1.0);
      expect(ClassesDoCapital.fromJson(c.toJson()).at(_d(2019, 6, 30)), 1.0);
    });

    test('sem capital integralizado, lê o emitido; sem nada, não divide', () {
      final c = ClassesDoCapital.fromFre(
          [linha('2020-01-01', 1, '2019-01-01', 3, 1, tipo: 'Capital Emitido')]);
      expect(c.at(_d(2020, 1, 1)), 0.75);
      expect(ClassesDoCapital.fromFre(const []).at(_d(2020, 1, 1)), isNull);
    });
  });

  group('CodigosFca.acoesNaComposicao', () {
    test('lê as composições declaradas na FCA de 2024', () {
      const casos = {
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
      for (final e in casos.entries) {
        expect(CodigosFca.acoesNaComposicao(e.key), e.value, reason: e.key);
      }
      expect(CodigosFca.acoesNaComposicao('não se aplica'), isNull);
    });
  });
}
