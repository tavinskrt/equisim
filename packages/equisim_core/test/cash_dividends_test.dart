import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

Map<String, dynamic> _row({
  String shareClass = 'PN',
  String label = 'DIVIDENDO',
  String withInput = '20/12/2007',
  String value = '0,32',
  String lot = '1',
  String price = '11,60',
}) =>
    {
      'typeStock': shareClass,
      'dateApproval': '20/12/2007',
      'valueCash': value,
      'ratio': lot,
      'corporateAction': label,
      'lastDatePriorEx': withInput,
      'closingPricePriorExDate': price,
      'quotedPerShares': lot,
    };

void main() {
  group('Proventos da B3 — item A4', () {
    test('lê valor, classe, rótulo e as duas datas', () {
      // ABCB4, 20/12/2007: JCP de R$ 0,32 sobre fechamento de R$ 11,60 — os
      // 2,758621% que a própria B3 publica em `corporateActionPrice`.
      final p = B3CashDividends.parse([_row(label: 'JRS CAP PROPRIO')]).single;
      expect(p.shareClass, 'PN');
      expect(p.kind, CashDividendKind.interestOnEquity);
      expect(p.lastDateWithRights, _d(2007, 12, 20));
      expect(p.exDate, _d(2007, 12, 21));
      expect(p.amount, closeTo(0.32, 1e-12));
      expect(p.amount / p.closeWithRights!, closeTo(0.02758621, 1e-8));
    });

    test('a data ex pula fim de semana e feriado', () {
      final friday = B3CashDividends.parse([_row(withInput: '12/09/2025')]).single;
      expect(friday.exDate, _d(2025, 9, 15));
      final dayBefore = B3CashDividends.parse([_row(withInput: '30/12/2014')]).single;
      expect(dayBefore.exDate, _d(2015, 1, 2),
          reason: '31/12 não tem pregão e 1º/01 é feriado');
    });

    test('lote de mil vira valor por ação', () {
      final p = B3CashDividends.parse(
          [_row(value: '320,00', lot: '1000', price: '11.600,00')]).single;
      expect(p.amount, closeTo(0.32, 1e-12));
      expect(p.closeWithRights, closeTo(11.6, 1e-12));
    });

    test('preço zerado não é preço', () {
      final p = B3CashDividends.parse([_row(price: '0,00')]).single;
      expect(p.closeWithRights, isNull);
    });

    test('recusa o que inventaria provento', () {
      expect(
          B3CashDividends.parse([
            _row(value: '0,00'),
            _row(label: 'BONIFICACAO'),
            _row(withInput: ''),
            _row(shareClass: ''),
            'isto não é linha',
          ]),
          isEmpty);
    });

    test('só o juro sobre capital próprio perde o imposto retido', () {
      final jcp = B3CashDividends.parse([_row(label: 'JRS CAP PROPRIO')]).single;
      final div = B3CashDividends.parse([_row()]).single;
      expect(jcp.netAmount, closeTo(0.32 * 0.85, 1e-12));
      expect(div.netAmount, closeTo(0.32, 1e-12));
    });

    test('classe pelo sufixo do ticker', () {
      expect(B3CashDividends.shareClassOf('PETR3'), 'ON');
      expect(B3CashDividends.shareClassOf('PETR4'), 'PN');
      expect(B3CashDividends.shareClassOf('USIM5'), 'PNA');
      expect(B3CashDividends.shareClassOf('TAEE11'), 'UNT');
      expect(B3CashDividends.shareClassOf('XPTO9'), isNull);
    });
  });

  group('Retorno total', () {
    final dividends = [
      CashDividend(
        shareClass: 'PN',
        kind: CashDividendKind.dividend,
        lastDateWithRights: _d(2024, 3, 1),
        exDate: _d(2024, 3, 4),
        amount: 1.0,
      ),
      CashDividend(
        shareClass: 'PN',
        kind: CashDividendKind.interestOnEquity,
        lastDateWithRights: _d(2024, 9, 2),
        exDate: _d(2024, 9, 3),
        amount: 2.0,
      ),
    ];

    test('reinveste no fechamento da data ex, provento a provento', () {
      final r = TotalReturn.factor(
        dividends: dividends,
        from: _d(2024, 1, 1),
        until: _d(2024, 12, 31),
        closeOnExDate: (d) => d.month == 3 ? 20.0 : 40.0,
      );
      expect(r.factor, closeTo((1 + 1 / 20) * (1 + 2 * 0.85 / 40), 1e-12));
      expect(r.applied, 2);
    });

    test('a janela é (de, ate]: data ex no primeiro dia não entra', () {
      final r = TotalReturn.factor(
        dividends: dividends,
        from: _d(2024, 3, 4),
        until: _d(2024, 9, 3),
        closeOnExDate: (_) => 40.0,
        net: false,
      );
      expect(r.applied, 1);
      expect(r.factor, closeTo(1 + 2 / 40, 1e-12));
    });

    test('provento sem pregão nem preço com direito fica de fora e é contado',
        () {
      final r = TotalReturn.factor(
        dividends: dividends,
        from: _d(2024, 1, 1),
        until: _d(2024, 12, 31),
        closeOnExDate: (d) => d.month == 3 ? null : 40.0,
      );
      expect(r.applied, 1);
      expect(r.withoutPrice, 1);
    });

    test('sem pregão, o preço com direito da B3 menos o provento', () {
      final withPrice = [
        CashDividend(
          shareClass: 'ON',
          kind: CashDividendKind.dividend,
          lastDateWithRights: _d(2019, 3, 1),
          exDate: _d(2019, 3, 5),
          amount: 1.0,
          closeWithRights: 21.0,
        ),
      ];
      final r = TotalReturn.factor(
        dividends: withPrice,
        from: _d(2019, 1, 1),
        until: _d(2019, 12, 31),
        closeOnExDate: (_) => null,
      );
      expect(r.factor, closeTo(1 + 1 / 20, 1e-12));
      expect(r.approximated, 1);
      expect(r.withoutPrice, 0);
    });
  });

  group('proventos da mesma data ex', () {
    // Dividendo e juro sobre capital próprio no mesmo dia: o fator é o do
    // total, sem o termo cruzado de um rendendo sobre o outro.
    CashDividend dividend(double value, CashDividendKind kind) => CashDividend(
          shareClass: 'PN',
          kind: kind,
          lastDateWithRights: _d(2024, 6, 3),
          exDate: _d(2024, 6, 4),
          amount: value,
          closeWithRights: 24.0,
        );
    final day = [
      dividend(2.0, CashDividendKind.dividend),
      dividend(2.0, CashDividendKind.interestOnEquity),
    ];

    test('com o pregão ex, 1 + (D₁ + D₂)/P_ex', () {
      final r = TotalReturn.factor(
        dividends: day,
        from: _d(2024, 1, 1),
        until: _d(2024, 12, 31),
        closeOnExDate: (_) => 20.0,
        net: false,
      );
      expect(r.factor, closeTo(1 + 4 / 20, 1e-12),
          reason: 'o produto separado daria 1,21, com 0,01 de termo cruzado');
      expect(r.applied, 2);
    });

    test('sem o pregão, o preço ex sai do com direito menos os dois', () {
      final r = TotalReturn.factor(
        dividends: day,
        from: _d(2024, 1, 1),
        until: _d(2024, 12, 31),
        closeOnExDate: (_) => null,
        net: false,
      );
      // P_ex = 24 − 2 − 2 = 20.
      expect(r.factor, closeTo(1 + 4 / 20, 1e-12));
      expect(r.approximated, 2);
    });

    test('o imposto do juro sai do que se recebe, não da queda do preço', () {
      final r = TotalReturn.factor(
        dividends: day,
        from: _d(2024, 1, 1),
        until: _d(2024, 12, 31),
        closeOnExDate: (_) => 20.0,
      );
      expect(r.factor, closeTo(1 + (2 + 2 * 0.85) / 20, 1e-12));
    });
  });

  group('Índice de retorno total — o beta da decisão 89', () {
    CashDividend div(DateTime ex, double value, double withInput,
            {CashDividendKind kind = CashDividendKind.dividend}) =>
        CashDividend(
          shareClass: 'ON',
          kind: kind,
          lastDateWithRights: ex.subtract(const Duration(days: 1)),
          exDate: ex,
          amount: value,
          closeWithRights: withInput,
        );

    test('na data ex, o retorno é o do preço mais o rendimento com direito', () {
      final r = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 4), _d(2024, 3, 5)],
        closes: [20.0, 19.0, 19.38],
        dividends: [div(_d(2024, 3, 4), 1.0, 20.0)],
      );
      expect(r.index[1], closeTo(19 / 20 + 1 / 20, 1e-12),
          reason: 'queda do dia ex coberta pelo provento: retorno total zero');
      expect(r.index[2], closeTo(r.index[1] * 19.38 / 19, 1e-12));
      expect(r.applied, 1);
    });

    test('a série ajustada por desdobramento dá o mesmo índice', () {
      // Desdobramento de 1 para 2 depois do período: a fonte divide o passado
      // por dois, e o rendimento, que é bruto sobre bruto, não muda.
      final raw = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 4)],
        closes: [20.0, 19.0],
        dividends: [div(_d(2024, 3, 4), 1.0, 20.0)],
      );
      final adjusted = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 4)],
        closes: [10.0, 9.5],
        dividends: [div(_d(2024, 3, 4), 1.0, 20.0)],
      );
      expect(adjusted.index.last, closeTo(raw.index.last, 1e-12));
    });

    test('data ex sem pregão cai no pregão seguinte; antes da série, fora', () {
      final r = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 5)],
        closes: [20.0, 19.0],
        dividends: [
          div(_d(2024, 2, 1), 5.0, 25.0),
          div(_d(2024, 3, 4), 1.0, 20.0),
        ],
      );
      expect(r.applied, 1);
      expect(r.index.last, closeTo(19 / 20 + 0.05, 1e-12));
    });

    test('sem preço com direito, o provento não entra e é contado', () {
      final r = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 4)],
        closes: [20.0, 19.0],
        dividends: [
          CashDividend(
            shareClass: 'ON',
            kind: CashDividendKind.dividend,
            lastDateWithRights: _d(2024, 3, 1),
            exDate: _d(2024, 3, 4),
            amount: 1.0,
          ),
        ],
      );
      expect(r.withoutPrice, 1);
      expect(r.index.last, closeTo(0.95, 1e-12));
    });
  });

  group('Pacote de proventos', () {
    test('ida e volta, e a classe separa os papéis do emissor', () {
      final on = B3CashDividends.parse([_row(shareClass: 'ON')]);
      final pn = B3CashDividends.parse(
          [_row(shareClass: 'PN', label: 'JRS CAP PROPRIO', price: '0,00')]);
      final parsed = CashDividendsCodec.decode(CashDividendsCodec.encode(
          {'ABCB': [...on, ...pn]}, generatedAt: _d(2026, 9, 14)));
      final ofPn = CashDividendsCodec.forTicker(parsed, 'ABCB4');
      expect(ofPn.single.kind, CashDividendKind.interestOnEquity);
      expect(ofPn.single.closeWithRights, isNull);
      expect(CashDividendsCodec.forTicker(parsed, 'ABCB3').single.amount,
          closeTo(0.32, 1e-12));
      expect(CashDividendsCodec.forTicker(parsed, 'PETR4'), isEmpty);
    });

    test('versão desconhecida não é lida', () {
      expect(CashDividendsCodec.decode({'versao': 99, 'emissores': {}}), isEmpty);
    });
  });
}
