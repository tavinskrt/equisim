import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('TEST3');
DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

FundamentalsSnapshot _s(DateTime end, {double? profit, double? mc, DateTime? rec}) =>
    FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: end,
      netIncome: profit,
      marketCap: mc,
      receiptDate: rec,
    );

CvmPeriodDocument _dfp(int a) => CvmPeriodDocument(
      kind: CvmDocumentKind.dfp,
      periodStart: _d(a, 1, 1),
      periodEnd: _d(a, 12, 31),
      current: _s(_d(a, 12, 31), profit: 10, rec: _d(a + 1, 3, 1)),
    );

CvmPeriodDocument _itr(int a) => CvmPeriodDocument(
      kind: CvmDocumentKind.itr,
      periodStart: _d(a, 1, 1),
      periodEnd: _d(a, 6, 30),
      current: _s(_d(a, 6, 30), profit: 6, rec: _d(a, 8, 10)),
      prior: _s(_d(a - 1, 6, 30), profit: 5),
      priorStart: _d(a - 1, 1, 1),
    );

bool _all(FundamentalsSnapshot _) => true;

void main() {
  // Mercado cobre 2016-2022, sempre em dezembro, com valor de mercado.
  final market = [
    for (var a = 2016; a <= 2022; a++) _s(_d(a, 12, 31), profit: 9, mc: 1000.0 + a),
  ];

  test('anual: CVM onde existe, mercado onde só ele existe', () {
    final r = CvmSeries.build(
      documents: [for (var a = 2019; a <= 2022; a++) _dfp(a)],
      market: market,
      published: _all,
      anchored: false,
    );
    expect(r.anchoredOnQuarter, isFalse);
    expect(r.series.length, 7, reason: '2016–2018 do mercado, 2019–2022 da CVM');
    expect(r.series.last.netIncome, 10, reason: 'a CVM vence onde tem');
    expect(r.series.first.netIncome, 9);
  });

  test('DFP recebida depois da data não apaga o exercício de mercado', () {
    // USIM3: a DFP de 2023 foi reapresentada, e a versão ingerida tem
    // recebimento em 16/01/2025. Em 04/09/2024 ela não existia — mas ocupava
    // o ano na mescla, o exercício de mercado de 2023 era descartado, e a
    // cascata depois removia o ponto mesclado por ser do futuro. O ano sumia.
    final docs = [
      for (var a = 2019; a <= 2021; a++) _dfp(a),
      CvmPeriodDocument(
        kind: CvmDocumentKind.dfp,
        periodStart: _d(2022, 1, 1),
        periodEnd: _d(2022, 12, 31),
        current: _s(_d(2022, 12, 31), profit: 10, rec: _d(2024, 1, 16)),
      ),
    ];
    final asOf = _d(2023, 9, 1);
    final r = CvmSeries.build(
      documents: docs,
      market: market,
      published: PointInTimeView(asOf).isPublished,
      anchored: false,
    );
    final visible = r.series.where(PointInTimeView(asOf).isPublished).toList();
    expect(visible.last.fiscalPeriodEnd, _d(2022, 12, 31),
        reason: 'o exercício de 2022 estava publicado pelo mercado');
    expect(visible.last.netIncome, 9, reason: 'e é o do mercado');
  });

  test('ancorada: só junhos, e o mercado de dezembro não entra no meio', () {
    final docs = [
      for (var a = 2018; a <= 2022; a++) _dfp(a),
      for (var a = 2019; a <= 2023; a++) _itr(a),
    ];
    final r = CvmSeries.build(
      documents: docs,
      market: market,
      published: _all,
      anchored: true,
    );
    expect(r.anchoredOnQuarter, isTrue);
    expect(r.series.map((s) => s.fiscalPeriodEnd.month).toSet(), {6});
  });

  test('a mescla não olha para a frente: junho usa o dezembro ANTERIOR', () {
    final docs = [
      for (var a = 2018; a <= 2022; a++) _dfp(a),
      for (var a = 2019; a <= 2023; a++) _itr(a),
    ];
    final r = CvmSeries.build(
      documents: docs,
      market: market,
      published: _all,
      anchored: true,
    );
    // O ponto de jun/2022 tem de levar o valor de mercado de dez/2021.
    final jun22 = r.series.firstWhere((s) => s.fiscalPeriodEnd.year == 2022);
    expect(jun22.marketCap, 1000.0 + 2021);
  });

  test('e o dezembro anterior não empresta fluxo ao junho — decisão 78', () {
    final withInterest = [
      for (final s in market)
        FundamentalsSnapshot(
          ticker: s.ticker,
          fiscalPeriodEnd: s.fiscalPeriodEnd,
          netIncome: s.netIncome,
          marketCap: s.marketCap,
          interestExpense: -3,
        ),
    ];
    final docs = [
      for (var a = 2018; a <= 2022; a++) _dfp(a),
      for (var a = 2019; a <= 2023; a++) _itr(a),
    ];
    final anchored = CvmSeries.build(
      documents: docs,
      market: withInterest,
      published: _all,
      anchored: true,
    );
    expect(anchored.series.every((s) => s.interestExpense == null), isTrue,
        reason: 'juros de dezembro num ponto de junho');
    expect(anchored.series.every((s) => s.marketCap != null), isTrue);

    // Na anual, dezembro com dezembro: o mercado continua completando.
    final annual = CvmSeries.build(
      documents: docs,
      market: withInterest,
      published: _all,
      anchored: false,
    );
    expect(annual.series.every((s) => s.interestExpense == -3), isTrue);
  });

  test('ancorada que recua para DFP se comporta como a anual', () {
    // Sem ITR de 2021, a série ancorada recua. Recuada, ela tem de aceitar os
    // exercícios que só o mercado tem — senão encurta à toa.
    final docs = [
      for (var a = 2019; a <= 2022; a++) _dfp(a),
      for (final a in [2020, 2022, 2023]) _itr(a),
    ];
    final anchored = CvmSeries.build(
      documents: docs,
      market: market,
      published: _all,
      anchored: true,
    );
    final annual = CvmSeries.build(
      documents: docs,
      market: market,
      published: _all,
      anchored: false,
    );
    expect(anchored.anchoredOnQuarter, isFalse);
    expect(anchored.series.length, annual.series.length);
  });

  test('sem documento da CVM, a série de mercado passa intacta', () {
    final r = CvmSeries.build(
      documents: const [],
      market: market,
      published: _all,
      anchored: true,
    );
    expect(r.series.length, market.length);
    expect(r.provenance, isEmpty);
  });

  test('a procedência soma as duas fontes', () {
    final r = CvmSeries.build(
      documents: [for (var a = 2019; a <= 2022; a++) _dfp(a)],
      market: market,
      published: _all,
      anchored: false,
    );
    expect(r.provenance[FieldSource.cvm], greaterThan(0));
    expect(r.provenance[FieldSource.market], greaterThan(0));
  });

  group('versões do mesmo documento (item B8)', () {
    // A DFP de 2021 saiu com lucro 10 em 01/03/2022 e foi reapresentada com
    // lucro 4 em 15/06/2023. Quem avaliava em 2022 só tinha a original.
    CvmPeriodDocument version(double profit, DateTime rec) => CvmPeriodDocument(
          kind: CvmDocumentKind.dfp,
          periodStart: _d(2021, 1, 1),
          periodEnd: _d(2021, 12, 31),
          current: _s(_d(2021, 12, 31), profit: profit, rec: rec),
        );
    final original = version(10, _d(2022, 3, 1));
    final restated = version(4, _d(2023, 6, 15));
    final docs = [_dfp(2020), restated, original];

    FundamentalsSnapshot ofYear2021(DateTime asOf) => CvmSeries.build(
          documents: docs,
          market: market,
          published: PointInTimeView(asOf).isPublished,
          anchored: false,
        ).series.lastWhere((s) => s.fiscalPeriodEnd.year == 2021);

    test('antes da reapresentação, a coorte lê a original', () {
      expect(ofYear2021(_d(2022, 9, 30)).netIncome, 10);
    });

    test('depois dela, a reapresentada — em qualquer ordem da lista', () {
      expect(ofYear2021(_d(2023, 9, 30)).netIncome, 4);
    });

    test('um exercício entra uma vez só, com qualquer número de versões', () {
      final r = CvmSeries.build(
        documents: docs,
        market: market,
        published: _all,
        anchored: false,
      );
      expect(r.series.where((s) => s.fiscalPeriodEnd.year == 2021).length, 1);
    });

    test('vigentes: descarta a versão ainda não recebida e a superada', () {
      final in2022 = CvmSeries.inForceAt(
          docs, PointInTimeView(_d(2022, 9, 30)).isPublished);
      expect(in2022.map((d) => d.current.netIncome), [10, 10],
          reason: 'a DFP de 2020 e a original de 2021');
      final in2023 = CvmSeries.inForceAt(
          docs, PointInTimeView(_d(2023, 9, 30)).isPublished);
      expect(in2023.last, same(restated));
    });

    test('com uma versão por documento, vigentes é o filtro de publicados', () {
      final single = [for (var a = 2019; a <= 2022; a++) _dfp(a)];
      final p = PointInTimeView(_d(2022, 9, 30)).isPublished;
      expect(CvmSeries.inForceAt(single, p), [
        for (final d in single)
          if (p(d.current)) d,
      ]);
    });
  });
}
