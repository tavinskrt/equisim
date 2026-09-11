import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

FundamentalsSnapshot snapshotFor(int year) => FundamentalsSnapshot(
      ticker: Ticker.parse('PETR4'),
      fiscalPeriodEnd: DateTime(year, 12, 31),
      earningsPerShare: year - 2000.0,
    );

void main() {
  group('PointInTimeView', () {
    final history = [
      snapshotFor(2023),
      snapshotFor(2024),
      snapshotFor(2025),
    ];

    test('exercício recém-encerrado ainda não é público', () {
      // Em 15/01/2026 o balanço de 31/12/2025 não foi divulgado à CVM.
      final view = PointInTimeView(DateTime(2026, 1, 15));
      final latest = view.latestPublished(history);
      expect(latest, isNotNull);
      expect(latest!.fiscalPeriodEnd.year, 2024);
    });

    test('após a defasagem de 90 dias o exercício passa a ser visível', () {
      final view = PointInTimeView(DateTime(2026, 6, 30));
      expect(view.latestPublished(history)!.fiscalPeriodEnd.year, 2025);
    });

    test('defasagem é parâmetro declarado e altera o recorte', () {
      final semDefasagem = PointInTimeView(
        DateTime(2026, 1, 15),
        publicationLag: Duration.zero,
      );
      expect(semDefasagem.latestPublished(history)!.fiscalPeriodEnd.year, 2025);
    });

    test('devolve nada quando nenhum exercício era público', () {
      final view = PointInTimeView(DateTime(2020, 1, 1));
      expect(view.latestPublished(history), isNull);
    });

    test('recorte dos N mais recentes respeita a barreira', () {
      final view = PointInTimeView(DateTime(2026, 1, 15));
      final range = view.latestPublishedRange(history, 5);
      expect(range.length, 2);
      expect(range.last.fiscalPeriodEnd.year, 2024);
      expect(range.every(view.isPublished), isTrue);
    });
  });

  group('Fundamentos derivados', () {
    test('D&A sai de EBITDA menos EBIT', () {
      final snapshot = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        ebit: 100,
        ebitda: 140,
      );
      expect(snapshot.depreciationAndAmortization, closeTo(40, 1e-12));
    });

    test('alíquota efetiva é limitada para conter exercícios atípicos', () {
      // **A fonte grava a despesa com sinal negativo.** Conferido pela
      // identidade no cache: lucro líquido = lucro antes + incomeTaxExpense.
      // O teste seguia a convenção oposta, e passava porque `effectiveTaxRate`
      // tirava o módulo — os dois erros se cancelavam, e o cancelamento
      // escondia que crédito tributário virava imposto a pagar.
      final normal = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        incomeBeforeTax: 1000,
        incomeTaxExpense: -340,
      );
      expect(normal.effectiveTaxRate, closeTo(0.34, 1e-12));

      final atipico = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        incomeBeforeTax: 100,
        incomeTaxExpense: -900,
      );
      expect(atipico.effectiveTaxRate, 0.5);
    });

    test('crédito tributário produz alíquota nula, não imposto a pagar', () {
      // Campo positivo é crédito. Com o módulo, isto devolvia 0,20 e cobrava
      // imposto de quem recuperou imposto.
      final credito = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        incomeBeforeTax: 1000,
        incomeTaxExpense: 200,
      );
      expect(credito.effectiveTaxRate, 0.0);
    });

    test('prejuízo antes de impostos não produz alíquota', () {
      final prejuizo = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        incomeBeforeTax: -500,
        incomeTaxExpense: 10,
      );
      expect(prejuizo.effectiveTaxRate, isNull);
    });

    test('dívida líquida desconta caixa e aplicações', () {
      final snapshot = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        shortTermDebt: 200,
        longTermDebt: 800,
        cash: 300,
        shortTermInvestments: 100,
      );
      expect(snapshot.totalDebt, 1000);
      expect(snapshot.totalCash, 400);
      expect(snapshot.netDebt, 600);
    });

    test('custo da dívida implícito', () {
      final snapshot = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        shortTermDebt: 200,
        longTermDebt: 800,
        interestExpense: 110,
      );
      expect(snapshot.costOfDebt, closeTo(0.11, 1e-12));
    });

    test('campos ausentes devolvem nulo em vez de zero silencioso', () {
      final vazio = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
      );
      expect(vazio.depreciationAndAmortization, isNull);
      expect(vazio.effectiveTaxRate, isNull);
      expect(vazio.costOfDebt, isNull);
      expect(vazio.approximateCapex, isNull);
    });
  });
}
