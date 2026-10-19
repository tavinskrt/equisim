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
    final roundTrip = CvmDocumentCodec.decode(
        _t, jsonDecode(json) as Map<String, dynamic>)!;
    expect(roundTrip.kind, CvmDocumentKind.itr);
    expect(roundTrip.periodStart, original.periodStart);
    expect(roundTrip.periodEnd, original.periodEnd);
    expect(roundTrip.priorStart, original.priorStart);
    expect(roundTrip.current.receiptDate, original.current.receiptDate);
    expect(roundTrip.current.totalRevenue, original.current.totalRevenue);
    expect(roundTrip.current.netIncome, original.current.netIncome);
    expect(roundTrip.current.cash, original.current.cash);
    expect(roundTrip.current.treasuryFraction, original.current.treasuryFraction);
    expect(roundTrip.prior!.netIncome, original.prior!.netIncome);
    expect(roundTrip.current.ebit, isNull, reason: 'nulo continua nulo');
  });

  test('a soma de doze meses dá o mesmo resultado antes e depois do codec', () {
    final dfp = CvmPeriodDocument(
      kind: CvmDocumentKind.dfp,
      periodStart: _d(2022, 1, 1),
      periodEnd: _d(2022, 12, 31),
      current: FundamentalsSnapshot(
          ticker: _t, fiscalPeriodEnd: _d(2022, 12, 31), totalRevenue: 29904000000),
    );
    CvmPeriodDocument roundTrip(CvmPeriodDocument d) => CvmDocumentCodec.decode(_t,
        jsonDecode(jsonEncode(CvmDocumentCodec.encode(d))) as Map<String, dynamic>)!;
    final direct = TrailingTwelveMonths.build(annual: dfp, itr: _itr())!;
    final withGrowth = TrailingTwelveMonths.build(annual: roundTrip(dfp), itr: roundTrip(_itr()))!;
    expect(withGrowth.totalRevenue, direct.totalRevenue);
  });

  test('omite nulo e grava inteiro sem casas', () {
    final m = CvmDocumentCodec.encode(_itr());
    final c = m['c']! as Map<String, Object>;
    expect(c.containsKey('ebit'), isFalse);
    expect(c['rev'], isA<int>());
    expect(c['tf'], isA<double>());
  });

  test('pacote de versão desconhecida não é lido pela metade', () {
    final package = CvmDocumentCodec.encodePackage(
        {'WEGE3': [_itr()]}, generatedAt: _d(2026, 9, 14));
    final ok = CvmDocumentCodec.decodePackage(
        jsonDecode(jsonEncode(package)) as Map<String, dynamic>);
    expect(ok['WEGE3'], hasLength(1));

    final future = {...package, 'versao': CvmDocumentCodec.version + 1};
    expect(CvmDocumentCodec.decodePackage(
        jsonDecode(jsonEncode(future)) as Map<String, dynamic>), isEmpty);
  });

  test('documento sem período ou de tipo desconhecido é descartado', () {
    expect(CvmDocumentCodec.decode(_t, {'k': 'D', 'c': <String, dynamic>{}}), isNull);
    expect(CvmDocumentCodec.decode(_t, {
      'k': 'X', 's': '2023-01-01', 'e': '2023-12-31', 'c': <String, dynamic>{},
    }), isNull);
  });
}
