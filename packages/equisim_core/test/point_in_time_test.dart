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
      final normal = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        incomeBeforeTax: 1000,
        incomeTaxExpense: 340,
      );
      expect(normal.effectiveTaxRate, closeTo(0.34, 1e-12));

      final atipico = FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        incomeBeforeTax: 100,
        incomeTaxExpense: 900,
      );
      expect(atipico.effectiveTaxRate, 0.5);
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

  group('TaxPolicy', () {
    test('JCP retém 15% e dividendo é isento', () {
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 1.0,
        kind: DividendKind.jcp,
      );
      expect(TaxPolicy.brasil.netAmount(jcp), closeTo(0.85, 1e-12));
      expect(TaxPolicy.brasil.withheldAmount(jcp), closeTo(0.15, 1e-12));

      final dividendo = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 1.0,
        kind: DividendKind.dividendo,
      );
      expect(TaxPolicy.brasil.netAmount(dividendo), closeTo(1.0, 1e-12));
    });

    test('vigência permite trocar o regime sem alterar código', () {
      final futuro = TaxPolicy(
        name: 'Hipótese de reforma',
        rules: [
          TaxRule(
            kind: DividendKind.dividendo,
            rate: 0.15,
            effectiveFrom: DateTime(2027, 1, 1),
          ),
          const TaxRule(kind: DividendKind.dividendo, rate: 0.0),
        ],
      );

      DividendEvent eventOn(DateTime date) => DividendEvent(
            ticker: Ticker.parse('ITUB4'),
            exDate: date,
            paymentDate: date,
            amountPerShare: 1.0,
            kind: DividendKind.dividendo,
          );

      expect(futuro.netAmount(eventOn(DateTime(2026, 6, 1))),
          closeTo(1.0, 1e-12));
      expect(futuro.netAmount(eventOn(DateTime(2027, 6, 1))),
          closeTo(0.85, 1e-12));
    });

    test('rótulo desconhecido é tratado de forma conservadora', () {
      expect(DividendKind.fromLabel('ALGO NOVO'), DividendKind.desconhecido);
      expect(DividendKind.fromLabel('jcp'), DividendKind.jcp);
      expect(DividendKind.fromLabel(null), DividendKind.desconhecido);
    });

    test('base bruta é a premissa vigente do trabalho', () {
      expect(TaxPolicy.brasil.basis, DividendBasis.gross);
    });

    test('em base bruta, R\$ 1,00 de JCP rende R\$ 0,85', () {
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 1.0,
        kind: DividendKind.jcp,
      );
      expect(TaxPolicy.brasil.netAmount(jcp), closeTo(0.85, 1e-12));
      expect(TaxPolicy.brasil.withheldAmount(jcp), closeTo(0.15, 1e-12));
      expect(TaxPolicy.brasil.grossAmount(jcp), closeTo(1.0, 1e-12));
    });

    test('em base líquida, R\$ 0,85 de JCP é o que entra no caixa', () {
      // Mesmo evento visto sob a outra premissa: o informado já é o recebido,
      // e o bruto é deduzido por reversão.
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 0.85,
        kind: DividendKind.jcp,
      );
      const policy = TaxPolicy.brasilBaseLiquida;
      expect(policy.netAmount(jcp), closeTo(0.85, 1e-12));
      expect(policy.withheldAmount(jcp), closeTo(0.15, 1e-12));
      expect(policy.grossAmount(jcp), closeTo(1.0, 1e-12));
    });

    test('trocar a base é a única alteração necessária para reverter', () {
      // Se a conferência documental indicar base líquida, aplicar 15% sobre um
      // valor que já era líquido subestimaria o provento em 15%.
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 1.0,
        kind: DividendKind.jcp,
      );
      final comoBruto = TaxPolicy.brasil.netAmount(jcp);
      final comoLiquido = TaxPolicy.brasilBaseLiquida.netAmount(jcp);
      expect(comoLiquido - comoBruto, closeTo(0.15, 1e-12));
      expect(comoBruto / comoLiquido, closeTo(0.85, 1e-12));
    });

    test('base não altera provento isento', () {
      final dividendo = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 1.0,
        kind: DividendKind.dividendo,
      );
      expect(TaxPolicy.brasil.netAmount(dividendo),
          TaxPolicy.brasilBaseLiquida.netAmount(dividendo));
      expect(TaxPolicy.brasilBaseLiquida.withheldAmount(dividendo), 0.0);
    });

    test('política zero não retém nada', () {
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: DateTime(2025, 1, 1),
        paymentDate: DateTime(2025, 2, 1),
        amountPerShare: 1.0,
        kind: DividendKind.jcp,
      );
      expect(TaxPolicy.zero.netAmount(jcp), closeTo(1.0, 1e-12));
    });
  });
}
