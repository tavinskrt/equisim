import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

Map<String, dynamic> _linha({
  String classe = 'PN',
  String rotulo = 'DIVIDENDO',
  String com = '20/12/2007',
  String valor = '0,32',
  String lote = '1',
  String preco = '11,60',
}) =>
    {
      'typeStock': classe,
      'dateApproval': '20/12/2007',
      'valueCash': valor,
      'ratio': lote,
      'corporateAction': rotulo,
      'lastDatePriorEx': com,
      'closingPricePriorExDate': preco,
      'quotedPerShares': lote,
    };

void main() {
  group('Proventos da B3 — item A4', () {
    test('lê valor, classe, rótulo e as duas datas', () {
      // ABCB4, 20/12/2007: JCP de R$ 0,32 sobre fechamento de R$ 11,60 — os
      // 2,758621% que a própria B3 publica em `corporateActionPrice`.
      final p = B3CashDividends.parse([_linha(rotulo: 'JRS CAP PROPRIO')]).single;
      expect(p.shareClass, 'PN');
      expect(p.kind, CashDividendKind.jurosSobreCapital);
      expect(p.lastDateWithRights, _d(2007, 12, 20));
      expect(p.exDate, _d(2007, 12, 21));
      expect(p.amount, closeTo(0.32, 1e-12));
      expect(p.amount / p.closeWithRights!, closeTo(0.02758621, 1e-8));
    });

    test('a data ex pula fim de semana e feriado', () {
      final sexta = B3CashDividends.parse([_linha(com: '12/09/2025')]).single;
      expect(sexta.exDate, _d(2025, 9, 15));
      final vespera = B3CashDividends.parse([_linha(com: '30/12/2014')]).single;
      expect(vespera.exDate, _d(2015, 1, 2),
          reason: '31/12 não tem pregão e 1º/01 é feriado');
    });

    test('lote de mil vira valor por ação', () {
      final p = B3CashDividends.parse(
          [_linha(valor: '320,00', lote: '1000', preco: '11.600,00')]).single;
      expect(p.amount, closeTo(0.32, 1e-12));
      expect(p.closeWithRights, closeTo(11.6, 1e-12));
    });

    test('preço zerado não é preço', () {
      final p = B3CashDividends.parse([_linha(preco: '0,00')]).single;
      expect(p.closeWithRights, isNull);
    });

    test('recusa o que inventaria provento', () {
      expect(
          B3CashDividends.parse([
            _linha(valor: '0,00'),
            _linha(rotulo: 'BONIFICACAO'),
            _linha(com: ''),
            _linha(classe: ''),
            'isto não é linha',
          ]),
          isEmpty);
    });

    test('só o juro sobre capital próprio perde o imposto retido', () {
      final jcp = B3CashDividends.parse([_linha(rotulo: 'JRS CAP PROPRIO')]).single;
      final div = B3CashDividends.parse([_linha()]).single;
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
    final proventos = [
      CashDividend(
        shareClass: 'PN',
        kind: CashDividendKind.dividendo,
        lastDateWithRights: _d(2024, 3, 1),
        exDate: _d(2024, 3, 4),
        amount: 1.0,
      ),
      CashDividend(
        shareClass: 'PN',
        kind: CashDividendKind.jurosSobreCapital,
        lastDateWithRights: _d(2024, 9, 2),
        exDate: _d(2024, 9, 3),
        amount: 2.0,
      ),
    ];

    test('reinveste no fechamento da data ex, provento a provento', () {
      final r = TotalReturn.factor(
        dividends: proventos,
        de: _d(2024, 1, 1),
        ate: _d(2024, 12, 31),
        closeOnExDate: (d) => d.month == 3 ? 20.0 : 40.0,
      );
      expect(r.factor, closeTo((1 + 1 / 20) * (1 + 2 * 0.85 / 40), 1e-12));
      expect(r.applied, 2);
    });

    test('a janela é (de, ate]: data ex no primeiro dia não entra', () {
      final r = TotalReturn.factor(
        dividends: proventos,
        de: _d(2024, 3, 4),
        ate: _d(2024, 9, 3),
        closeOnExDate: (_) => 40.0,
        net: false,
      );
      expect(r.applied, 1);
      expect(r.factor, closeTo(1 + 2 / 40, 1e-12));
    });

    test('provento sem pregão nem preço com direito fica de fora e é contado',
        () {
      final r = TotalReturn.factor(
        dividends: proventos,
        de: _d(2024, 1, 1),
        ate: _d(2024, 12, 31),
        closeOnExDate: (d) => d.month == 3 ? null : 40.0,
      );
      expect(r.applied, 1);
      expect(r.withoutPrice, 1);
    });

    test('sem pregão, o preço com direito da B3 menos o provento', () {
      final comPreco = [
        CashDividend(
          shareClass: 'ON',
          kind: CashDividendKind.dividendo,
          lastDateWithRights: _d(2019, 3, 1),
          exDate: _d(2019, 3, 5),
          amount: 1.0,
          closeWithRights: 21.0,
        ),
      ];
      final r = TotalReturn.factor(
        dividends: comPreco,
        de: _d(2019, 1, 1),
        ate: _d(2019, 12, 31),
        closeOnExDate: (_) => null,
      );
      expect(r.factor, closeTo(1 + 1 / 20, 1e-12));
      expect(r.approximated, 1);
      expect(r.withoutPrice, 0);
    });
  });

  group('Índice de retorno total — o beta da decisão 89', () {
    CashDividend div(DateTime ex, double valor, double com,
            {CashDividendKind kind = CashDividendKind.dividendo}) =>
        CashDividend(
          shareClass: 'ON',
          kind: kind,
          lastDateWithRights: ex.subtract(const Duration(days: 1)),
          exDate: ex,
          amount: valor,
          closeWithRights: com,
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
      final bruto = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 4)],
        closes: [20.0, 19.0],
        dividends: [div(_d(2024, 3, 4), 1.0, 20.0)],
      );
      final ajustado = TotalReturnIndex.build(
        dates: [_d(2024, 3, 1), _d(2024, 3, 4)],
        closes: [10.0, 9.5],
        dividends: [div(_d(2024, 3, 4), 1.0, 20.0)],
      );
      expect(ajustado.index.last, closeTo(bruto.index.last, 1e-12));
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
            kind: CashDividendKind.dividendo,
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
      final on = B3CashDividends.parse([_linha(classe: 'ON')]);
      final pn = B3CashDividends.parse(
          [_linha(classe: 'PN', rotulo: 'JRS CAP PROPRIO', preco: '0,00')]);
      final lido = CashDividendsCodec.decode(CashDividendsCodec.encode(
          {'ABCB': [...on, ...pn]}, geradoEm: _d(2026, 9, 14)));
      final doPn = CashDividendsCodec.forTicker(lido, 'ABCB4');
      expect(doPn.single.kind, CashDividendKind.jurosSobreCapital);
      expect(doPn.single.closeWithRights, isNull);
      expect(CashDividendsCodec.forTicker(lido, 'ABCB3').single.amount,
          closeTo(0.32, 1e-12));
      expect(CashDividendsCodec.forTicker(lido, 'PETR4'), isEmpty);
    });

    test('versão desconhecida não é lida', () {
      expect(CashDividendsCodec.decode({'versao': 99, 'emissores': {}}), isEmpty);
    });
  });
}
