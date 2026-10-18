// Sem o par VPA × contagem, a base de patrimônio é o PL da demonstração
// (item B47).
//
// A fonte de mercado devolve, para Fleury, Copasa e Armac, o VPA vazio e a
// contagem do exercício zerada; a mescla da decisão 81 não tinha por onde
// dividir, e a elegibilidade recusava como insolvente quem tinha bilhões de
// patrimônio publicado.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

FundamentalsSnapshot _year({
  required int y,
  double? bookValuePerShare,
  double? count,
  double? pl,
}) =>
    FundamentalsSnapshot(
      ticker: Ticker.parse('BASE3'),
      fiscalPeriodEnd: DateTime(y, 12, 31),
      bookValuePerShare: bookValuePerShare,
      sharesOutstandingAsOf: count,
      totalStockholderEquity: pl,
    );

void main() {
  test('com o par, vale o produto, como antes', () {
    expect(_year(y: 2025, bookValuePerShare: 4, count: 100, pl: 999).equityBookValue, 400);
  });

  test('sem o par, vale o PL da demonstração', () {
    expect(
        _year(y: 2025, count: 0, pl: 5096268000).equityBookValue, 5096268000);
    expect(_year(y: 2025, bookValuePerShare: 4, pl: 800).equityBookValue, 800);
  });

  test('VPA negativo continua sendo insolvência, mesmo com PL publicado', () {
    expect(_year(y: 2025, bookValuePerShare: -1, count: 100, pl: 500).equityBookValue,
        isNull);
  });

  test('sem nada, continua sem base', () {
    expect(_year(y: 2025, count: 0).equityBookValue, isNull);
    expect(_year(y: 2025, pl: -300).equityBookValue, isNull);
  });
}
