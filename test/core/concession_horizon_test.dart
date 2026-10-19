import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Concessionária de energia com fluxo da firma sustentado.
List<FundamentalsSnapshot> _history(Ticker ticker) => [
      for (var year = 2016; year <= 2025; year++)
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(year, 12, 31),
          netIncome: 1000.0 * (year - 2015),
          ebit: 1400.0 * (year - 2015),
          ebitda: 1800.0 * (year - 2015),
          incomeBeforeTax: 1300.0 * (year - 2015),
          incomeTaxExpense: 300.0 * (year - 2015),
          interestExpense: 120.0,
          operatingCashFlow: 1600.0 * (year - 2015),
          freeCashFlow: 1200.0 * (year - 2015),
          shortTermDebt: 400.0,
          longTermDebt: 1600.0,
          cash: 300.0,
          nopat: 1000.0 * (year - 2015),
          sharesOutstanding: 1000.0,
          sharesOutstandingAsOf: 1000.0,
          marketCap: 20000.0,
          bookValuePerShare: 8.0 * (year - 2015),
          enterpriseToEbitda: 6.0,
        ),
    ];

ValuationInputs _inputs(
  Ticker ticker, {
  DateTime? end,
  String? sector = 'utilidade-publica',
  String? subsector = 'Energia Elétrica / Energia Elétrica',
}) =>
    ValuationInputs(
      ticker: ticker,
      asOf: DateTime(2026, 9, 14),
      fundamentals: _history(ticker),
      marketPrice: 20.0,
      capm: const CapmInputs(
        riskFreeRate: 0.105,
        beta: 1.2,
        marketPremium: 0.055,
      ),
      projectionYears: 10,
      sectorKey: sector,
      industry: subsector,
      concessionEnd: end,
    );

void main() {
  final ticker = Ticker.parse('TAEE11');

  group('O terminal do contrato — decisão 88', () {
    DcfAssumptions assumptions({required double returnRate, int? contract}) =>
        DcfAssumptions(
          growthRate: 0.045,
          perpetualGrowth: 0.045,
          discountRate: 0.12,
          returnOnCapital: returnRate,
          cashTiming: CashTiming.endOfYear,
          contractYearsAfterHorizon: contract,
        );
    double firm(double returnRate, int? contract) => DcfCalculator.firm(
          baseProfit: 1000,
          assumptions: assumptions(returnRate: returnRate, contract: contract),
          netDebt: 0,
          sharesOutstanding: 1,
        ).unwrap().fairValuePerShare;

    // A identidade verdadeira: com o capital rendendo exatamente o custo dele,
    // não há excedente a cortar, e o prazo não muda nada.
    for (final m in [0, 15, 40]) {
      test('capital que rende o custo dele: contrato de $m anos além = perpétuo',
          () {
        final perpetual = firm(0.12, null);
        expect(firm(0.12, m), closeTo(perpetual, perpetual * 1e-9));
      });
    }

    test('capital que rende mais que o custo: o contrato corta o excedente', () {
      // O que a lente `metodo` apontou: `lucro_{N+1}/r` perpetua o excedente do
      // capital existente, e o contrato que acaba não o paga para sempre.
      final perpetual = firm(0.24, null);
      final atEnd = firm(0.24, 0);
      final far = firm(0.24, 15);
      final veryFar = firm(0.24, 400);
      expect(atEnd, lessThan(far));
      expect(far, lessThan(perpetual));
      expect(veryFar, closeTo(perpetual, perpetual * 1e-6),
          reason: 'contrato sem fim à vista é a perpetuidade');
    });

    test('capital que rende menos que o custo: o contrato devolve mais', () {
      expect(firm(0.08, 0), greaterThan(firm(0.08, null)));
    });

    test('sem retorno utilizável, não há capital, e o terminal fica perpétuo',
        () {
      expect(firm(0.0, 0), closeTo(firm(0.0, null), 1e-9));
    });

    test('na rota derivada, o contrato longo tende à perpetuidade do acionista, '
        'e fica entre ela e o capital devolvido', () {
      double terminal(int? contract) => DcfCalculator.equityFromFirm(
            baseProfit: 1000,
            assumptions: assumptions(returnRate: 0.24, contract: contract),
            netDebt: 2000,
            sharesOutstanding: 1,
            costOfDebt: 0.10,
            taxRate: 0.34,
            equityDiscountRate: 0.15,
            terminalEquityDiscountRate: 0.15,
          ).unwrap().terminalValue;
      final perpetual = terminal(null);
      final returned = terminal(0);
      expect(terminal(400), closeTo(perpetual, perpetual.abs() * 1e-6));
      final smaller = returned < perpetual ? returned : perpetual;
      final isGreater = returned < perpetual ? perpetual : returned;
      var previous = returned;
      for (final m in [5, 15, 30, 60]) {
        final v = terminal(m);
        expect(v, inInclusiveRange(smaller, isGreater), reason: '$m anos');
        // Monótono no prazo, na direção do perpétuo.
        expect((v - previous) * (perpetual - returned), greaterThanOrEqualTo(0));
        previous = v;
      }
    });

    test('na rota derivada, no contrato que acaba no horizonte, o terminal do '
        'acionista é o da firma menos a dívida', () {
      final a = assumptions(returnRate: 0.24, contract: 0);
      final firmR = DcfCalculator.firm(
              baseProfit: 1000, assumptions: a, netDebt: 2000, sharesOutstanding: 1)
          .unwrap();
      final derivedOutcome = DcfCalculator.equityFromFirm(
        baseProfit: 1000,
        assumptions: a,
        netDebt: 2000,
        sharesOutstanding: 1,
        costOfDebt: 0.10,
        taxRate: 0.34,
        equityDiscountRate: 0.15,
        terminalEquityDiscountRate: 0.15,
      ).unwrap();
      final debtAtN = 2000 * math.pow(1.045, 10);
      expect(derivedOutcome.terminalValue,
          closeTo(firmR.terminalValue - debtAtN, 1e-6));
    });
  });

  group('O contrato encurta a projeção só quando acaba dentro dela', () {
    test('anos até o fim, arredondados, e nunca abaixo de um', () {
      expect(
          ValuationCascade.contractYears(
              _inputs(ticker, end: DateTime(2030, 9, 14))),
          4);
      expect(
          ValuationCascade.contractYears(
              _inputs(ticker, end: DateTime(2026, 10, 1))),
          1);
      expect(ValuationCascade.contractYears(_inputs(ticker)), isNull);
      expect(
          ValuationCascade.contractYears(
              _inputs(ticker, end: DateTime(2016, 2, 29))),
          isNull,
          reason: 'contrato vencido no formulário não impõe horizonte');
      expect(
          ValuationCascade.contractYears(_inputs(ticker,
              end: DateTime(2030, 9, 14),
              sector: 'bens-industriais',
              subsector: 'Máquinas e Equipamentos')),
          isNull,
          reason: 'só concessão tem contrato');
    });

    test('dentro da projeção, o preço muda e o aviso diz até quando', () {
      final full = ValuationCascade.evaluate(_inputs(ticker)).unwrap();
      final short = ValuationCascade.evaluate(
              _inputs(ticker, end: DateTime(2030, 9, 14)))
          .unwrap();
      expect((short.fairValue.cents - full.fairValue.cents).abs(),
          greaterThan(0));
      expect(short.warnings.join(' '), contains('14/09/2030'));
      expect(short.warnings.join(' '), contains('vai até lá, 4 anos'));
    });

    test('depois da projeção, o preço fica entre o do contrato curto e o perpétuo',
        () {
      final full = ValuationCascade.evaluate(_inputs(ticker)).unwrap();
      final short = ValuationCascade.evaluate(
              _inputs(ticker, end: DateTime(2036, 9, 14)))
          .unwrap();
      final longTerm = ValuationCascade.evaluate(
              _inputs(ticker, end: DateTime(2047, 8, 11)))
          .unwrap();
      // **Entre os dois, na direção que o excedente do acionista dá** (decisão
      // 102). O capital próprio sai do fluxo do acionista derivado, ao `Ke`, e
      // o terminal do contrato é a perpetuidade truncada com o capital devolvido
      // no fim: o contrato longo fica entre o que acaba no horizonte e o
      // perpétuo. Se fica acima ou abaixo do perpétuo é o excedente do
      // acionista sobre o capital contábil que decide — e neste fixture, ao `Ke`
      // do CAPM, o capital devolvido vale mais que a perpetuidade, embora a
      // firma renda acima do WACC: sem taxas resolvidas, WACC e `Ke` não
      // conversam, e a ordem da firma não é a do acionista.
      final smaller = short.fairValue.cents < full.fairValue.cents
          ? short.fairValue.cents
          : full.fairValue.cents;
      final isGreater = short.fairValue.cents < full.fairValue.cents
          ? full.fairValue.cents
          : short.fairValue.cents;
      expect(longTerm.fairValue.cents, inInclusiveRange(smaller, isGreater));
      expect(short.fairValue.cents, isNot(full.fairValue.cents));
      expect(longTerm.warnings.join(' '), contains('anos depois da projeção'));
    });

    test('fora de concessão, o fim declarado não faz nada', () {
      ValuationResult evaluate(DateTime? end) => ValuationCascade.evaluate(
              _inputs(ticker,
                  end: end,
                  sector: 'bens-industriais',
                  subsector: 'Máquinas e Equipamentos / Motores'))
          .unwrap();
      expect(evaluate(DateTime(2028, 1, 1)).fairValue.cents,
          evaluate(null).fairValue.cents);
    });

    test('sem prazo lido, o aviso diz o que se supõe e o que acontece se não',
        () {
      final r = ValuationCascade.evaluate(_inputs(ticker)).unwrap();
      final warning = r.warnings.join(' ');
      expect(warning, contains('o prazo não foi lido'));
      expect(warning, contains('excedente de retorno sobre o capital existente'));
      expect(warning, isNot(contains('0,80')),
          reason: 'a truncagem sem indenização não é a conta certa');
    });
  });

  group('O rastro do terminal da concessão', () {
    // Lente `metodo`, 21/09/2026. Com prazo, o terminal é
    // `capital_N + EVA·anuidade(M)` (decisão 88), e o rastro imprimia a
    // perpetuidade de Gordon — a mesma forma de defeito que a ponte `EV − D`
    // tinha antes da decisão 102: rastro que descreve outra conta é pior que
    // nenhum.
    List<CalculationTrace> traceOf(DateTime? end) {
      final captured = <CalculationTrace>[];
      AuditRecorder.attach((e) => captured.addAll(e.calculations));
      try {
        ValuationCascade.evaluate(_inputs(Ticker.parse('TEST3'), end: end));
      } finally {
        AuditRecorder.detach();
      }
      return captured;
    }

    test('com prazo, o rastro traz o capital devolvido e a anuidade', () {
      final step = traceOf(DateTime(2040, 6, 30))
          .firstWhere((c) => c.formulaName.contains('Valor terminal'));
      expect(step.formulaName, contains('contrato com prazo'));
      expect(step.latexRepresentation, contains('K_N'));
      expect(step.mappedVariables['M (anos de contrato além de N)'], isNotNull);
      expect(step.intermediateSteps.first, contains('o capital volta'));
      expect(step.latexRepresentation, isNot(contains(r'\frac{L_{N+1}}{r_\infty}')),
          reason: 'a perpetuidade não é a conta que foi feita aqui');
    });

    test('sem prazo, continua sendo a perpetuidade de retorno neutro', () {
      final step = traceOf(null)
          .firstWhere((c) => c.formulaName.contains('Valor terminal'));
      expect(step.formulaName, contains('retorno neutro'));
      expect(step.mappedVariables['M (anos de contrato além de N)'], isNull);
    });
  });
}
