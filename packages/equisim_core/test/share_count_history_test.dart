import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

Map<String, String> _cap(String tipo, String aprovacao, String total,
        {String referencia = '2022-12-31', String versao = '1', String id = ''}) =>
    {
      'ID_Documento': id,
      'Tipo_Capital': tipo,
      'Data_Autorizacao_Aprovacao': aprovacao,
      'Data_Referencia': referencia,
      'Versao': versao,
      'Quantidade_Total_Acoes': total,
    };

List<RawQuote> _serie(List<(DateTime, double, int)> v) =>
    [for (final x in v) RawQuote(x.$1, x.$2, x.$3)];

void main() {
  group('Contagem por data do FRE — item A3.4', () {
    test('cada aprovação vale até a seguinte', () {
      final h = ShareCountHistory.fromFre([
        _cap('Capital Integralizado', '2012-04-30', '100000000'),
        _cap('Capital Integralizado', '2018-06-15', '200000000'),
        _cap('Capital Autorizado', '2010-01-01', '999999999'),
      ]);
      expect(h.points, hasLength(2));
      expect(h.at(_d(2011, 1, 1)), isNull);
      expect(h.at(_d(2015, 9, 30))!.total, closeTo(1e8, 1e-6));
      expect(h.at(_d(2018, 6, 15))!.total, closeTo(2e8, 1e-6));
    });

    // O caso da CPFL Transmissão: grupamento de 40 para 1 em 2016, sem capital
    // novo. O formulário de 2017 repete a aprovação de 2010 com a contagem de
    // depois do grupamento.
    final formularios = [
      _cap('Capital Integralizado', '2010-04-30', '4000',
          referencia: '2011-01-01'),
      _cap('Capital Integralizado', '2010-04-30', '100',
          referencia: '2017-01-01', id: 'doc2017'),
    ];

    test('grupamento sem capital novo: a contagem da época vale até o evento',
        () {
      final h = ShareCountHistory.fromFre(formularios,
          events: [(date: _d(2016, 4, 29), totalAfter: 100)]);
      expect(h.at(_d(2012, 12, 31))!.total, closeTo(4000, 1e-9));
      expect(h.at(_d(2016, 5, 2))!.total, closeTo(100, 1e-9));
      expect(h.at(_d(2016, 5, 2))!.source, ShareCountSource.shareEvent);
    });

    test('evento não declarado entra no recebimento do formulário que o mostra',
        () {
      final h = ShareCountHistory.fromFre(formularios,
          receivedOn: {'doc2017': _d(2017, 5, 31)});
      expect(h.at(_d(2016, 12, 31))!.total, closeTo(4000, 1e-9));
      expect(h.at(_d(2017, 6, 1))!.total, closeTo(100, 1e-9));
      expect(h.at(_d(2017, 6, 1))!.source, ShareCountSource.filingCorrection);
    });

    test('formulário que a série explica não corrige nada', () {
      final h = ShareCountHistory.fromFre(formularios,
          events: [(date: _d(2016, 4, 29), totalAfter: 100)],
          receivedOn: {'doc2017': _d(2017, 5, 31)});
      expect(
          h.points.where((p) => p.source == ShareCountSource.filingCorrection),
          isEmpty);
    });

    test('na mesma referência, a maior versão', () {
      final h = ShareCountHistory.fromFre([
        _cap('Capital Integralizado', '2018-06-15', '205', versao: '1'),
        _cap('Capital Integralizado', '2018-06-15', '210', versao: '2'),
      ]);
      expect(h.points.single.total, closeTo(210, 1e-9));
    });

    test('sem integralizado, recua ao emitido; sem nenhum, série vazia', () {
      expect(
          ShareCountHistory.fromFre(
                  [_cap('Capital Emitido', '2024-05-01', '300')])
              .points
              .single
              .total,
          closeTo(300, 1e-9));
      expect(
          ShareCountHistory.fromFre(
                  [_cap('Capital Autorizado', '2024-05-01', '300')])
              .points,
          isEmpty);
    });
  });

  group('Data ex de evento declarado — item A3.4', () {
    test('desdobramento de 1 para 10: o preço se divide no pregão certo', () {
      final ev = CorporateEvents.locate(
        _serie([
          (_d(2019, 3, 1), 50.0, 100),
          (_d(2019, 3, 29), 51.0, 100),
          (_d(2019, 4, 1), 5.12, 101),
          (_d(2019, 4, 2), 5.10, 101),
        ]),
        factor: 10,
        approvedOn: _d(2019, 3, 15),
      )!;
      expect(ev.exDate, _d(2019, 4, 1));
      expect(ev.factor, closeTo(10, 1e-12));
    });

    test('salto antes da aprovação não é o evento', () {
      final ev = CorporateEvents.locate(
        _serie([
          (_d(2019, 3, 1), 50.0, 100),
          (_d(2019, 3, 4), 5.0, 101),
          (_d(2019, 3, 20), 5.0, 101),
        ]),
        factor: 10,
        approvedOn: _d(2019, 3, 15),
      );
      expect(ev, isNull);
    });

    test('bonificação pequena sai pela troca de DISMES', () {
      final ev = CorporateEvents.locate(
        _serie([
          (_d(2020, 5, 4), 20.0, 200),
          (_d(2020, 5, 5), 19.1, 200),
          (_d(2020, 5, 6), 18.3, 201),
        ]),
        factor: 1.05,
        approvedOn: _d(2020, 4, 30),
      )!;
      expect(ev.exDate, _d(2020, 5, 6));
    });

    test('grupamento de papel em crise: o dia despenca e o fator ainda casa',
        () {
      // Grupamento de 25 para 1 com o papel caindo 15% no mesmo pregão: a
      // razão sai 21,25, fora da folga de 6%, e a troca de DISMES localiza.
      final ev = CorporateEvents.locate(
        _serie([
          (_d(2016, 5, 2), 0.04, 300),
          (_d(2016, 5, 20), 0.04, 300),
          (_d(2016, 5, 23), 0.85, 301),
        ]),
        factor: 0.04,
        approvedOn: _d(2016, 4, 29),
      )!;
      expect(ev.exDate, _d(2016, 5, 23));
    });

    test('troca de DISMES com razão distante do fator não é o evento', () {
      final ev = CorporateEvents.locate(
        _serie([
          (_d(2016, 5, 2), 0.04, 300),
          (_d(2016, 5, 3), 0.038, 301),
        ]),
        factor: 0.04,
        approvedOn: _d(2016, 4, 29),
      );
      expect(ev, isNull, reason: 'dividendo, e não grupamento');
    });

    test('fora da janela, não localiza', () {
      final ev = CorporateEvents.locate(
        _serie([
          (_d(2021, 1, 4), 30.0, 10),
          (_d(2022, 3, 1), 30.0, 10),
          (_d(2022, 3, 2), 15.0, 11),
        ]),
        factor: 2,
        approvedOn: _d(2021, 1, 10),
      );
      expect(ev, isNull);
    });
  });
}
