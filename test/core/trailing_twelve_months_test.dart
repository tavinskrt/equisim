import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('TEST3');

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

FundamentalsSnapshot _s(
  DateTime end, {
  double? revenue,
  double? profit,
  double? ebit,
  double? ebitda,
  double? cash,
  DateTime? received,
}) =>
    FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: end,
      totalRevenue: revenue,
      netIncome: profit,
      ebit: ebit,
      ebitda: ebitda,
      cash: cash,
      receiptDate: received,
    );

CvmPeriodDocument _dfp(int year, {double revenue = 30, double profit = 3}) =>
    CvmPeriodDocument(
      kind: CvmDocumentKind.dfp,
      periodStart: _d(year, 1, 1),
      periodEnd: _d(year, 12, 31),
      current: _s(_d(year, 12, 31),
          revenue: revenue, profit: profit, received: _d(year + 1, 3, 1)),
    );

CvmPeriodDocument _itrJune(
  int year, {
  double revenue = 16,
  double profit = 2,
  double previousRevenue = 14,
  double previousProfit = 1,
  double? cash = 5,
}) =>
    CvmPeriodDocument(
      kind: CvmDocumentKind.itr,
      periodStart: _d(year, 1, 1),
      periodEnd: _d(year, 6, 30),
      current: _s(_d(year, 6, 30),
          revenue: revenue, profit: profit, cash: cash,
          received: _d(year, 8, 10)),
      prior: _s(_d(year - 1, 6, 30), revenue: previousRevenue, profit: previousProfit),
      priorStart: _d(year - 1, 1, 1),
    );

void main() {
  group('Doze meses', () {
    test('anual + acumulado − anterior', () {
      // FY22 = 30; 1S23 = 16; 1S22 = 14 -> jul/22 a jun/23 = 32.
      final t = TrailingTwelveMonths.build(annual: _dfp(2022), itr: _itrJune(2023))!;
      expect(t.totalRevenue, 32);
      expect(t.netIncome, 4);
      expect(t.fiscalPeriodEnd, _d(2023, 6, 30));
    });

    test('identidade: um acumulado de doze meses devolve o próprio exercício',
        () {
      // Se o "trimestral" cobre o exercicio inteiro, a soma tem de reproduzir
      // a DFP dele. E a prova de que a aritmetica soma os periodos certos.
      final fy22 = _dfp(2022, revenue: 30, profit: 3);
      final asItr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 12, 31),
        current: _s(_d(2023, 12, 31), revenue: 37, profit: 5),
        prior: _s(_d(2022, 12, 31), revenue: 30, profit: 3),
        priorStart: _d(2022, 1, 1),
      );
      final t = TrailingTwelveMonths.build(annual: fy22, itr: asItr)!;
      expect(t.totalRevenue, 37);
      expect(t.netIncome, 5);
    });

    test('estoque vem da data do trimestre, e a publicidade também', () {
      final t = TrailingTwelveMonths.build(annual: _dfp(2022), itr: _itrJune(2023))!;
      expect(t.cash, 5);
      expect(t.receiptDate, _d(2023, 8, 10));
    });

    test('exercício social de abril a março soma do mesmo jeito', () {
      // SMTO3, JALL3 e RAIZ4 encerram em marco. FY abr/22–mar/23; o ITR de
      // jun/23 acumula abr–jun/23 e compara com abr–jun/22.
      final fy = CvmPeriodDocument(
        kind: CvmDocumentKind.dfp,
        periodStart: _d(2022, 4, 1),
        periodEnd: _d(2023, 3, 31),
        current: _s(_d(2023, 3, 31), revenue: 100),
      );
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 4, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), revenue: 28),
        prior: _s(_d(2022, 6, 30), revenue: 25),
        priorStart: _d(2022, 4, 1),
      );
      expect(TrailingTwelveMonths.build(annual: fy, itr: itr)!.totalRevenue, 103);
    });

    test('EBITDA sai de EBIT e D&A somados, não do EBITDA de um período só', () {
      final fy = CvmPeriodDocument(
        kind: CvmDocumentKind.dfp,
        periodStart: _d(2022, 1, 1),
        periodEnd: _d(2022, 12, 31),
        current: _s(_d(2022, 12, 31), ebit: 10, ebitda: 14),
      );
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), ebit: 6, ebitda: 8),
        prior: _s(_d(2022, 6, 30), ebit: 5, ebitda: 7),
        priorStart: _d(2022, 1, 1),
      );
      final t = TrailingTwelveMonths.build(annual: fy, itr: itr)!;
      expect(t.ebit, 11);
      expect(t.ebitda, 11 + (4 + 2 - 2));
    });
  });

  group('Recusas — somar períodos que não fecham produz outro intervalo', () {
    test('acumulado que não começa depois do exercício anual', () {
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 2, 15),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), revenue: 16),
        prior: _s(_d(2022, 6, 30), revenue: 14),
        priorStart: _d(2022, 1, 1),
      );
      expect(TrailingTwelveMonths.build(annual: _dfp(2022), itr: itr), isNull);
    });

    test('DFP de outro ano', () {
      expect(TrailingTwelveMonths.build(annual: _dfp(2021), itr: _itrJune(2023)),
          isNull);
    });

    test('sem o comparativo do ano anterior', () {
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), revenue: 16),
      );
      expect(TrailingTwelveMonths.build(annual: _dfp(2022), itr: itr), isNull);
    });

    test('tipos trocados', () {
      expect(TrailingTwelveMonths.build(annual: _itrJune(2023), itr: _dfp(2022)),
          isNull);
    });

    test('campo ausente em uma parcela fica ausente, e não vira zero', () {
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), revenue: 16, profit: 2),
        prior: _s(_d(2022, 6, 30), revenue: 14), // sem lucro
        priorStart: _d(2022, 1, 1),
      );
      final t = TrailingTwelveMonths.build(annual: _dfp(2022), itr: itr)!;
      expect(t.totalRevenue, 32);
      expect(t.netIncome, isNull);
    });
  });

  group('Série ancorada', () {
    bool all(FundamentalsSnapshot _) => true;

    final documents = [
      for (var a = 2018; a <= 2022; a++) _dfp(a),
      for (var a = 2019; a <= 2023; a++) _itrJune(a),
    ];

    test('ancorada em ITR, todos os pontos terminam na mesma data, a um ano', () {
      final s = TrailingTwelveMonths.anchoredSeries(documents,
          published: all);
      expect(s.length, 5);
      for (final p in s) {
        expect(p.fiscalPeriodEnd.month, 6);
        expect(p.fiscalPeriodEnd.day, 30);
      }
      for (var i = 1; i < s.length; i++) {
        expect(s[i].fiscalPeriodEnd.year - s[i - 1].fiscalPeriodEnd.year, 1,
            reason: 'é o espaçamento anual que as guardas do motor presumem');
      }
    });

    test('ancorada em DFP, devolve as DFPs', () {
      // Sem ITR publicado depois da ultima DFP, a serie e a de sempre.
      final onlyDfp = [for (var a = 2018; a <= 2022; a++) _dfp(a)];
      final s = TrailingTwelveMonths.anchoredSeries(onlyDfp, published: all);
      expect(s.map((p) => p.fiscalPeriodEnd.month).toSet(), {12});
      expect(s.length, 5);
    });

    test('a âncora troca quando o ITR é recebido, e só então', () {
      bool until(DateTime day, FundamentalsSnapshot snap) =>
          snap.receiptDate == null || !snap.receiptDate!.isAfter(day);

      // Em 01/05/2023 o mais recente publicado e a DFP 2022, recebida em
      // marco: a serie e a das DFPs.
      final before = TrailingTwelveMonths.anchoredSeries(documents,
          published: (s) => until(_d(2023, 5, 1), s));
      expect(before.last.fiscalPeriodEnd, _d(2022, 12, 31));

      // O ITR de jun/23 e recebido em 10/08/2023. Em 15/08 a ancora e ele, e a
      // serie inteira passa a terminar em junho.
      final after = TrailingTwelveMonths.anchoredSeries(documents,
          published: (s) => until(_d(2023, 8, 15), s));
      expect(after.last.fiscalPeriodEnd, _d(2023, 6, 30));
      expect(after.map((p) => p.fiscalPeriodEnd.month).toSet(), {6});
    });

    test('série com buraco recua INTEIRA para a âncora de DFP — decisão 73', () {
      // Em 14/09/2026 a CVM nao publica o ITR de 2025. A primeira versao
      // montou jun/24 seguido de jun/26, e as guardas anuais leram dois anos
      // como um: QUAL3 de -22% a +908%.
      final withoutItr2021 = [
        for (final d in documents)
          if (!(d.kind == CvmDocumentKind.itr && d.periodEnd.year == 2021)) d,
      ];
      final s = TrailingTwelveMonths.anchoredSeries(withoutItr2021,
          published: all);
      expect(s.map((p) => p.fiscalPeriodEnd.month).toSet(), {12},
          reason: 'nem buraco, nem mistura de âncoras');
      for (var i = 1; i < s.length; i++) {
        expect(s[i].fiscalPeriodEnd.year - s[i - 1].fiscalPeriodEnd.year, 1);
      }
      expect(TrailingTwelveMonths.isAnchoredOnQuarter(s, withoutItr2021), isFalse);
    });

    test('sem a DFP anterior à âncora, também recua', () {
      final withoutDfp2022 = [
        for (final d in documents)
          if (!(d.kind == CvmDocumentKind.dfp && d.periodEnd.year == 2022)) d,
      ];
      final s = TrailingTwelveMonths.anchoredSeries(withoutDfp2022,
          published: all);
      expect(s.map((p) => p.fiscalPeriodEnd.month).toSet(), {12});
    });

    test('série contígua é reconhecida como ancorada em trimestre', () {
      final s = TrailingTwelveMonths.anchoredSeries(documents,
          published: all);
      expect(TrailingTwelveMonths.isAnchoredOnQuarter(s, documents), isTrue);
    });
  });
}
