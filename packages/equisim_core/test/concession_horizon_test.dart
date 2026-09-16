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
  DateTime? fim,
  String? setor = 'utilidade-publica',
  String? subsetor = 'Energia Elétrica / Energia Elétrica',
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
      sectorKey: setor,
      industry: subsetor,
      concessionEnd: fim,
    );

void main() {
  final ticker = Ticker.parse('TAEE11');

  group('O terminal do contrato — decisão 88', () {
    DcfAssumptions premissas({required double retorno, int? contrato}) =>
        DcfAssumptions(
          growthRate: 0.045,
          perpetualGrowth: 0.045,
          discountRate: 0.12,
          returnOnCapital: retorno,
          cashTiming: CashTiming.fimDeAno,
          contractYearsAfterHorizon: contrato,
        );
    double firma(double retorno, int? contrato) => DcfCalculator.firm(
          baseProfit: 1000,
          assumptions: premissas(retorno: retorno, contrato: contrato),
          netDebt: 0,
          sharesOutstanding: 1,
        ).unwrap().fairValuePerShare;

    // A identidade verdadeira: com o capital rendendo exatamente o custo dele,
    // não há excedente a cortar, e o prazo não muda nada.
    for (final m in [0, 15, 40]) {
      test('capital que rende o custo dele: contrato de $m anos além = perpétuo',
          () {
        final perpetuo = firma(0.12, null);
        expect(firma(0.12, m), closeTo(perpetuo, perpetuo * 1e-9));
      });
    }

    test('capital que rende mais que o custo: o contrato corta o excedente', () {
      // O que a lente `metodo` apontou: `lucro_{N+1}/r` perpetua o excedente do
      // capital existente, e o contrato que acaba não o paga para sempre.
      final perpetuo = firma(0.24, null);
      final noFim = firma(0.24, 0);
      final longe = firma(0.24, 15);
      final muitoLonge = firma(0.24, 400);
      expect(noFim, lessThan(longe));
      expect(longe, lessThan(perpetuo));
      expect(muitoLonge, closeTo(perpetuo, perpetuo * 1e-6),
          reason: 'contrato sem fim à vista é a perpetuidade');
    });

    test('capital que rende menos que o custo: o contrato devolve mais', () {
      expect(firma(0.08, 0), greaterThan(firma(0.08, null)));
    });

    test('sem retorno utilizável, não há capital, e o terminal fica perpétuo',
        () {
      expect(firma(0.0, 0), closeTo(firma(0.0, null), 1e-9));
    });

    test('na rota derivada, o contrato longo tende à perpetuidade do acionista, '
        'e fica entre ela e o capital devolvido', () {
      double terminal(int? contrato) => DcfCalculator.equityFromFirm(
            baseProfit: 1000,
            assumptions: premissas(retorno: 0.24, contrato: contrato),
            netDebt: 2000,
            sharesOutstanding: 1,
            costOfDebt: 0.10,
            taxRate: 0.34,
            equityDiscountRate: 0.15,
            terminalEquityDiscountRate: 0.15,
          ).unwrap().terminalValue;
      final perpetuo = terminal(null);
      final devolvido = terminal(0);
      expect(terminal(400), closeTo(perpetuo, perpetuo.abs() * 1e-6));
      final menor = devolvido < perpetuo ? devolvido : perpetuo;
      final maior = devolvido < perpetuo ? perpetuo : devolvido;
      var anterior = devolvido;
      for (final m in [5, 15, 30, 60]) {
        final v = terminal(m);
        expect(v, inInclusiveRange(menor, maior), reason: '$m anos');
        // Monótono no prazo, na direção do perpétuo.
        expect((v - anterior) * (perpetuo - devolvido), greaterThanOrEqualTo(0));
        anterior = v;
      }
    });

    test('na rota derivada, no contrato que acaba no horizonte, o terminal do '
        'acionista é o da firma menos a dívida', () {
      final a = premissas(retorno: 0.24, contrato: 0);
      final firmaR = DcfCalculator.firm(
              baseProfit: 1000, assumptions: a, netDebt: 2000, sharesOutstanding: 1)
          .unwrap();
      final derivada = DcfCalculator.equityFromFirm(
        baseProfit: 1000,
        assumptions: a,
        netDebt: 2000,
        sharesOutstanding: 1,
        costOfDebt: 0.10,
        taxRate: 0.34,
        equityDiscountRate: 0.15,
        terminalEquityDiscountRate: 0.15,
      ).unwrap();
      final dividaEmN = 2000 * math.pow(1.045, 10);
      expect(derivada.terminalValue,
          closeTo(firmaR.terminalValue - dividaEmN, 1e-6));
    });
  });

  group('O contrato encurta a projeção só quando acaba dentro dela', () {
    test('anos até o fim, arredondados, e nunca abaixo de um', () {
      expect(
          ValuationCascade.contractYears(
              _inputs(ticker, fim: DateTime(2030, 9, 14))),
          4);
      expect(
          ValuationCascade.contractYears(
              _inputs(ticker, fim: DateTime(2026, 10, 1))),
          1);
      expect(ValuationCascade.contractYears(_inputs(ticker)), isNull);
      expect(
          ValuationCascade.contractYears(
              _inputs(ticker, fim: DateTime(2016, 2, 29))),
          isNull,
          reason: 'contrato vencido no formulário não impõe horizonte');
      expect(
          ValuationCascade.contractYears(_inputs(ticker,
              fim: DateTime(2030, 9, 14),
              setor: 'bens-industriais',
              subsetor: 'Máquinas e Equipamentos')),
          isNull,
          reason: 'só concessão tem contrato');
    });

    test('dentro da projeção, o preço muda e o aviso diz até quando', () {
      final cheio = ValuationCascade.evaluate(_inputs(ticker)).unwrap();
      final curto = ValuationCascade.evaluate(
              _inputs(ticker, fim: DateTime(2030, 9, 14)))
          .unwrap();
      expect((curto.fairValue.cents - cheio.fairValue.cents).abs(),
          greaterThan(0));
      expect(curto.warnings.join(' '), contains('14/09/2030'));
      expect(curto.warnings.join(' '), contains('vai até lá, 4 anos'));
    });

    test('depois da projeção, o preço fica entre o do contrato curto e o perpétuo',
        () {
      final cheio = ValuationCascade.evaluate(_inputs(ticker)).unwrap();
      final curto = ValuationCascade.evaluate(
              _inputs(ticker, fim: DateTime(2036, 9, 14)))
          .unwrap();
      final longo = ValuationCascade.evaluate(
              _inputs(ticker, fim: DateTime(2047, 8, 11)))
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
      final menor = curto.fairValue.cents < cheio.fairValue.cents
          ? curto.fairValue.cents
          : cheio.fairValue.cents;
      final maior = curto.fairValue.cents < cheio.fairValue.cents
          ? cheio.fairValue.cents
          : curto.fairValue.cents;
      expect(longo.fairValue.cents, inInclusiveRange(menor, maior));
      expect(curto.fairValue.cents, isNot(cheio.fairValue.cents));
      expect(longo.warnings.join(' '), contains('anos depois da projeção'));
    });

    test('fora de concessão, o fim declarado não faz nada', () {
      ValuationResult avaliar(DateTime? fim) => ValuationCascade.evaluate(
              _inputs(ticker,
                  fim: fim,
                  setor: 'bens-industriais',
                  subsetor: 'Máquinas e Equipamentos / Motores'))
          .unwrap();
      expect(avaliar(DateTime(2028, 1, 1)).fairValue.cents,
          avaliar(null).fairValue.cents);
    });

    test('sem prazo lido, o aviso diz o que se supõe e o que acontece se não',
        () {
      final r = ValuationCascade.evaluate(_inputs(ticker)).unwrap();
      final aviso = r.warnings.join(' ');
      expect(aviso, contains('o prazo não foi lido'));
      expect(aviso, contains('excedente de retorno sobre o capital existente'));
      expect(aviso, isNot(contains('0,80')),
          reason: 'a truncagem sem indenização não é a conta certa');
    });
  });
}
