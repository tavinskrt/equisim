import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('TEST3');

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

FundamentalsSnapshot _s(
  DateTime fim, {
  double? receita,
  double? lucro,
  double? ebit,
  double? ebitda,
  double? caixa,
  DateTime? recebido,
}) =>
    FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: fim,
      totalRevenue: receita,
      netIncome: lucro,
      ebit: ebit,
      ebitda: ebitda,
      cash: caixa,
      receiptDate: recebido,
    );

CvmPeriodDocument _dfp(int ano, {double receita = 30, double lucro = 3}) =>
    CvmPeriodDocument(
      kind: CvmDocumentKind.dfp,
      periodStart: _d(ano, 1, 1),
      periodEnd: _d(ano, 12, 31),
      current: _s(_d(ano, 12, 31),
          receita: receita, lucro: lucro, recebido: _d(ano + 1, 3, 1)),
    );

CvmPeriodDocument _itrJun(
  int ano, {
  double receita = 16,
  double lucro = 2,
  double receitaAnt = 14,
  double lucroAnt = 1,
  double? caixa = 5,
}) =>
    CvmPeriodDocument(
      kind: CvmDocumentKind.itr,
      periodStart: _d(ano, 1, 1),
      periodEnd: _d(ano, 6, 30),
      current: _s(_d(ano, 6, 30),
          receita: receita, lucro: lucro, caixa: caixa,
          recebido: _d(ano, 8, 10)),
      prior: _s(_d(ano - 1, 6, 30), receita: receitaAnt, lucro: lucroAnt),
      priorStart: _d(ano - 1, 1, 1),
    );

void main() {
  group('Doze meses', () {
    test('anual + acumulado − anterior', () {
      // FY22 = 30; 1S23 = 16; 1S22 = 14 -> jul/22 a jun/23 = 32.
      final t = TrailingTwelveMonths.build(anual: _dfp(2022), itr: _itrJun(2023))!;
      expect(t.totalRevenue, 32);
      expect(t.netIncome, 4);
      expect(t.fiscalPeriodEnd, _d(2023, 6, 30));
    });

    test('identidade: um acumulado de doze meses devolve o próprio exercício',
        () {
      // Se o "trimestral" cobre o exercicio inteiro, a soma tem de reproduzir
      // a DFP dele. E a prova de que a aritmetica soma os periodos certos.
      final fy22 = _dfp(2022, receita: 30, lucro: 3);
      final comoItr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 12, 31),
        current: _s(_d(2023, 12, 31), receita: 37, lucro: 5),
        prior: _s(_d(2022, 12, 31), receita: 30, lucro: 3),
        priorStart: _d(2022, 1, 1),
      );
      final t = TrailingTwelveMonths.build(anual: fy22, itr: comoItr)!;
      expect(t.totalRevenue, 37);
      expect(t.netIncome, 5);
    });

    test('estoque vem da data do trimestre, e a publicidade também', () {
      final t = TrailingTwelveMonths.build(anual: _dfp(2022), itr: _itrJun(2023))!;
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
        current: _s(_d(2023, 3, 31), receita: 100),
      );
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 4, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), receita: 28),
        prior: _s(_d(2022, 6, 30), receita: 25),
        priorStart: _d(2022, 4, 1),
      );
      expect(TrailingTwelveMonths.build(anual: fy, itr: itr)!.totalRevenue, 103);
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
      final t = TrailingTwelveMonths.build(anual: fy, itr: itr)!;
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
        current: _s(_d(2023, 6, 30), receita: 16),
        prior: _s(_d(2022, 6, 30), receita: 14),
        priorStart: _d(2022, 1, 1),
      );
      expect(TrailingTwelveMonths.build(anual: _dfp(2022), itr: itr), isNull);
    });

    test('DFP de outro ano', () {
      expect(TrailingTwelveMonths.build(anual: _dfp(2021), itr: _itrJun(2023)),
          isNull);
    });

    test('sem o comparativo do ano anterior', () {
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), receita: 16),
      );
      expect(TrailingTwelveMonths.build(anual: _dfp(2022), itr: itr), isNull);
    });

    test('tipos trocados', () {
      expect(TrailingTwelveMonths.build(anual: _itrJun(2023), itr: _dfp(2022)),
          isNull);
    });

    test('campo ausente em uma parcela fica ausente, e não vira zero', () {
      final itr = CvmPeriodDocument(
        kind: CvmDocumentKind.itr,
        periodStart: _d(2023, 1, 1),
        periodEnd: _d(2023, 6, 30),
        current: _s(_d(2023, 6, 30), receita: 16, lucro: 2),
        prior: _s(_d(2022, 6, 30), receita: 14), // sem lucro
        priorStart: _d(2022, 1, 1),
      );
      final t = TrailingTwelveMonths.build(anual: _dfp(2022), itr: itr)!;
      expect(t.totalRevenue, 32);
      expect(t.netIncome, isNull);
    });
  });

  group('Série ancorada', () {
    bool todos(FundamentalsSnapshot _) => true;

    final documentos = [
      for (var a = 2018; a <= 2022; a++) _dfp(a),
      for (var a = 2019; a <= 2023; a++) _itrJun(a),
    ];

    test('ancorada em ITR, todos os pontos terminam na mesma data, a um ano', () {
      final s = TrailingTwelveMonths.serieAncorada(documentos,
          asOf: _d(2023, 9, 1), publicado: todos);
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
      final soDfp = [for (var a = 2018; a <= 2022; a++) _dfp(a)];
      final s = TrailingTwelveMonths.serieAncorada(soDfp,
          asOf: _d(2023, 4, 1), publicado: todos);
      expect(s.map((p) => p.fiscalPeriodEnd.month).toSet(), {12});
      expect(s.length, 5);
    });

    test('a âncora troca quando o ITR é recebido, e só então', () {
      bool ate(DateTime dia, FundamentalsSnapshot snap) =>
          snap.receiptDate == null || !snap.receiptDate!.isAfter(dia);

      // Em 01/05/2023 o mais recente publicado e a DFP 2022, recebida em
      // marco: a serie e a das DFPs.
      final antes = TrailingTwelveMonths.serieAncorada(documentos,
          asOf: _d(2023, 5, 1), publicado: (s) => ate(_d(2023, 5, 1), s));
      expect(antes.last.fiscalPeriodEnd, _d(2022, 12, 31));

      // O ITR de jun/23 e recebido em 10/08/2023. Em 15/08 a ancora e ele, e a
      // serie inteira passa a terminar em junho.
      final depois = TrailingTwelveMonths.serieAncorada(documentos,
          asOf: _d(2023, 8, 15), publicado: (s) => ate(_d(2023, 8, 15), s));
      expect(depois.last.fiscalPeriodEnd, _d(2023, 6, 30));
      expect(depois.map((p) => p.fiscalPeriodEnd.month).toSet(), {6});
    });

    test('série com buraco recua INTEIRA para a âncora de DFP — decisão 73', () {
      // Em 14/09/2026 a CVM nao publica o ITR de 2025. A primeira versao
      // montou jun/24 seguido de jun/26, e as guardas anuais leram dois anos
      // como um: QUAL3 de -22% a +908%.
      final semItr2021 = [
        for (final d in documentos)
          if (!(d.kind == CvmDocumentKind.itr && d.periodEnd.year == 2021)) d,
      ];
      final s = TrailingTwelveMonths.serieAncorada(semItr2021,
          asOf: _d(2023, 9, 1), publicado: todos);
      expect(s.map((p) => p.fiscalPeriodEnd.month).toSet(), {12},
          reason: 'nem buraco, nem mistura de âncoras');
      for (var i = 1; i < s.length; i++) {
        expect(s[i].fiscalPeriodEnd.year - s[i - 1].fiscalPeriodEnd.year, 1);
      }
      expect(TrailingTwelveMonths.isAnchoredOnQuarter(s, semItr2021), isFalse);
    });

    test('sem a DFP anterior à âncora, também recua', () {
      final semDfp2022 = [
        for (final d in documentos)
          if (!(d.kind == CvmDocumentKind.dfp && d.periodEnd.year == 2022)) d,
      ];
      final s = TrailingTwelveMonths.serieAncorada(semDfp2022,
          asOf: _d(2023, 9, 1), publicado: todos);
      expect(s.map((p) => p.fiscalPeriodEnd.month).toSet(), {12});
    });

    test('série contígua é reconhecida como ancorada em trimestre', () {
      final s = TrailingTwelveMonths.serieAncorada(documentos,
          asOf: _d(2023, 9, 1), publicado: todos);
      expect(TrailingTwelveMonths.isAnchoredOnQuarter(s, documentos), isTrue);
    });
  });
}
