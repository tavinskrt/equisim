import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('WEGE3');
DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

CvmPeriodDocument _itr() => CvmPeriodDocument(
      kind: CvmDocumentKind.itr,
      periodStart: _d(2023, 1, 1),
      periodEnd: _d(2023, 6, 30),
      current: FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: _d(2023, 6, 30),
        receiptDate: _d(2023, 7, 26),
        totalRevenue: 15867479000,
        netIncome: 2733728000,
        cash: 4918937000,
        treasuryFraction: 0.0012,
      ),
      prior: FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: _d(2022, 6, 30),
        totalRevenue: 14013893000,
        netIncome: 1879602000,
      ),
      priorStart: _d(2022, 1, 1),
    );

void main() {
  test('ida e volta preserva cada campo, período e publicidade', () {
    final original = _itr();
    // Pelo JSON de verdade, e não só pelo mapa: é o que o aplicativo lê.
    final json = jsonEncode(CvmDocumentCodec.encode(original));
    final volta = CvmDocumentCodec.decode(
        _t, jsonDecode(json) as Map<String, dynamic>)!;
    expect(volta.kind, CvmDocumentKind.itr);
    expect(volta.periodStart, original.periodStart);
    expect(volta.periodEnd, original.periodEnd);
    expect(volta.priorStart, original.priorStart);
    expect(volta.current.receiptDate, original.current.receiptDate);
    expect(volta.current.totalRevenue, original.current.totalRevenue);
    expect(volta.current.netIncome, original.current.netIncome);
    expect(volta.current.cash, original.current.cash);
    expect(volta.current.treasuryFraction, original.current.treasuryFraction);
    expect(volta.prior!.netIncome, original.prior!.netIncome);
    expect(volta.current.ebit, isNull, reason: 'nulo continua nulo');
  });

  test('a soma de doze meses dá o mesmo resultado antes e depois do codec', () {
    final dfp = CvmPeriodDocument(
      kind: CvmDocumentKind.dfp,
      periodStart: _d(2022, 1, 1),
      periodEnd: _d(2022, 12, 31),
      current: FundamentalsSnapshot(
          ticker: _t, fiscalPeriodEnd: _d(2022, 12, 31), totalRevenue: 29904000000),
    );
    CvmPeriodDocument ida(CvmPeriodDocument d) => CvmDocumentCodec.decode(_t,
        jsonDecode(jsonEncode(CvmDocumentCodec.encode(d))) as Map<String, dynamic>)!;
    final direto = TrailingTwelveMonths.build(anual: dfp, itr: _itr())!;
    final pelo = TrailingTwelveMonths.build(anual: ida(dfp), itr: ida(_itr()))!;
    expect(pelo.totalRevenue, direto.totalRevenue);
  });

  test('omite nulo e grava inteiro sem casas', () {
    final m = CvmDocumentCodec.encode(_itr());
    final c = m['c']! as Map<String, Object>;
    expect(c.containsKey('ebit'), isFalse);
    expect(c['rev'], isA<int>());
    expect(c['tf'], isA<double>());
  });

  test('pacote de versão desconhecida não é lido pela metade', () {
    final pacote = CvmDocumentCodec.encodePackage(
        {'WEGE3': [_itr()]}, geradoEm: _d(2026, 9, 14));
    final ok = CvmDocumentCodec.decodePackage(
        jsonDecode(jsonEncode(pacote)) as Map<String, dynamic>);
    expect(ok['WEGE3'], hasLength(1));

    final futuro = {...pacote, 'versao': CvmDocumentCodec.versao + 1};
    expect(CvmDocumentCodec.decodePackage(
        jsonDecode(jsonEncode(futuro)) as Map<String, dynamic>), isEmpty);
  });

  test('documento sem período ou de tipo desconhecido é descartado', () {
    expect(CvmDocumentCodec.decode(_t, {'k': 'D', 'c': <String, dynamic>{}}), isNull);
    expect(CvmDocumentCodec.decode(_t, {
      'k': 'X', 's': '2023-01-01', 'e': '2023-12-31', 'c': <String, dynamic>{},
    }), isNull);
  });
}
