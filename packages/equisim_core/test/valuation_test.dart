import 'dart:math' as math;
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('CostOfCapital', () {
    test('CAPM: Ke = Rf + β(Rm − Rf)', () {
      const capm = CapmInputs(
        riskFreeRate: 0.094,
        beta: 1.2,
        marketPremium: 0.055,
      );
      expect(capm.costOfEquity, closeTo(0.094 + 1.2 * 0.055, 1e-12));
    });

    test('empresa sem dívida: WACC degenera para Ke', () {
      const capm = CapmInputs(
        riskFreeRate: 0.09,
        beta: 1.0,
        marketPremium: 0.055,
      );
      final unlevered = CostOfCapital.unlevered(capm);
      expect(unlevered.wacc, closeTo(capm.costOfEquity, 1e-12));
    });

    test('WACC fica abaixo do Ke quando há dívida com benefício fiscal', () {
      const capm = CapmInputs(
        riskFreeRate: 0.09,
        beta: 1.0,
        marketPremium: 0.055,
      );
      const levered = CostOfCapital(
        capm: capm,
        costOfDebt: 0.11,
        taxRate: 0.34,
        equityValue: 600,
        debtValue: 400,
        interestCoverage: 9.0,
        netDebtToEbitda: -0.3,
      );
      // O custo da dívida aplicado é o sintético: Rf + 1,0 p.p. na faixa de
      // caixa líquido. Daí 0,6 × 0,145 + 0,4 × 0,10 × 0,66
      // = 0,087 + 0,0264 = 0,1134.
      expect(levered.effectiveCostOfDebt, closeTo(0.10, 1e-12));
      expect(levered.wacc, closeTo(0.1134, 1e-9));
      expect(levered.wacc, lessThan(levered.costOfEquity));
    });
  });

  group('DCF pela via da firma', () {
    // Sem decaimento e sem freio, para que o valor confira com conta manual.
    const flat = DcfAssumptions(
      projectionYears: 3,
      growthRate: 0.05,
      perpetualGrowth: 0.05,
      discountRate: 0.10,
      returnOnCapital: 0.0,
    );

    test('valor por papel confere com o cálculo manual', () {
      final r = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: 0,
        sharesOutstanding: 10,
      );
      expect(r.isOk, isTrue);
      final o = r.unwrap();

      // Fluxos: 105, 110,25, 115,7625.
      expect(o.projectedFlows[0], closeTo(105.0, 1e-9));
      expect(o.projectedFlows[2], closeTo(115.7625, 1e-6));

      // Terminal neutro: VT = fluxo_{N+1}/r = 115,7625 × 1,05 / 0,10.
      expect(o.terminalValue, closeTo(115.7625 * 1.05 / 0.10, 1e-6));

      var vp = 0.0;
      for (var t = 1; t <= 3; t++) {
        vp += 100 * math.pow(1.05, t) / math.pow(1.10, t);
      }
      vp += o.terminalValue / math.pow(1.10, 3);
      expect(o.fairValuePerShare, closeTo(vp / 10, 1e-6));
    });

    test('o terminal neutro não depende do crescimento perpétuo', () {
      // É a consequência algébrica de ROIC_∞ = WACC, e o que blinda o resultado
      // da premissa que carregava até 80% do valor.
      double terminal(double gInf) => DcfCalculator
          .firm(
            baseProfit: 100,
            assumptions: flat.copyWith(perpetualGrowth: gInf),
            netDebt: 0,
            sharesOutstanding: 10,
          )
          .unwrap()
          .terminalValue;

      // A identidade que sustenta a afirmação: VT = lucro_{N+1}/r, sem nenhuma
      // divisão por (r − g) para amplificar a premissa. Com g_∞ a 0,02 ou a
      // 0,06 o denominador é o mesmo — 0,10 —, e só o numerador muda.
      for (final gInf in [0.02, 0.06, 0.09]) {
        final o = DcfCalculator.firm(
          baseProfit: 100,
          assumptions: flat.copyWith(perpetualGrowth: gInf),
          netDebt: 0,
          sharesOutstanding: 10,
        ).unwrap();
        final lucroFinal = o.projectedFlows.last; // retenção nula: fluxo = lucro
        expect(o.terminalValue, closeTo(lucroFinal * (1 + gInf) / 0.10, 1e-6),
            reason: 'o denominador é o desconto, não o spread');
      }
      // E o valor terminal continua finito quando g_∞ se aproxima de r, que é
      // onde a perpetuidade de Gordon explodiria.
      final quaseNoDesconto = terminal(0.0999);
      expect(quaseNoDesconto.isFinite, isTrue);
    });

    test('o freio de reinvestimento reduz o fluxo distribuído', () {
      final semFreio = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();
      final comFreio = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat.copyWith(returnOnCapital: 0.125),
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();

      // g₁ = 5% e retorno de 12,5% → b₁ = 40%.
      expect(comFreio.projectedFlows[0], closeTo(105.0 * 0.60, 1e-9));
      expect(comFreio.fairValuePerShare, lessThan(semFreio.fairValuePerShare),
          reason: 'crescer exige reinvestir; descontar o lucro inteiro e '
              'fazê-lo crescer conta o mesmo dinheiro duas vezes');
    });

    test('o crescimento decai linearmente até a perpetuidade', () {
      const a = DcfAssumptions(
        projectionYears: 5,
        growthRate: 0.20,
        perpetualGrowth: 0.04,
        discountRate: 0.12,
      );
      expect(a.growthAt(1), closeTo(0.20, 1e-12));
      expect(a.growthAt(5), closeTo(0.04, 1e-12));
      expect(a.growthAt(3), closeTo(0.12, 1e-12),
          reason: 'no meio do horizonte, o ponto médio entre as duas taxas');
    });

    test('dívida líquida reduz o valor do equity', () {
      final semDivida = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();
      final comDivida = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: 500,
        sharesOutstanding: 10,
      ).unwrap();
      expect(comDivida.equityValue,
          closeTo(semDivida.equityValue - 500, 1e-6));
      expect(comDivida.equityShare, lessThan(semDivida.equityShare));
    });

    test('a participação do equity expõe a ponte fina', () {
      final o = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();
      // Dívida a 95% do valor da firma deixa 5% de equity — abaixo do mínimo
      // de 20%, é o caso RENT3, em que o preço por papel vira resíduo.
      final fino = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: o.enterpriseValue * 0.95,
        sharesOutstanding: 10,
      ).unwrap();
      expect(fino.equityShare, closeTo(0.05, 1e-6));
      expect(fino.equityShare, lessThan(ValuationParameters.minEquityShare));
    });

    test('lucro operacional negativo não é avaliável pela via da firma', () {
      final r = DcfCalculator.firm(
        baseProfit: -50,
        assumptions: flat,
        netDebt: 0,
        sharesOutstanding: 10,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull, isA<InsufficientData>());
    });

    test('exige quantidade de papéis válida', () {
      final r = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: flat,
        netDebt: 0,
        sharesOutstanding: 0,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull, isA<InsufficientData>());
    });
  });

  group('DCF pela via do acionista', () {
    const a = DcfAssumptions(
      projectionYears: 3,
      growthRate: 0.06,
      perpetualGrowth: 0.06,
      discountRate: 0.12,
      returnOnCapital: 0.12,
    );

    test('desconta apenas a parcela distribuível do lucro', () {
      final o = DcfCalculator.shareholder(baseProfit: 10, assumptions: a)
          .unwrap();
      // g = 6% e ROE de 12% → b = 50%, e o payout é o complemento.
      expect(o.projectedFlows[0], closeTo(10 * 1.06 * 0.50, 1e-9),
          reason: 'LPA × (1 − b) é literalmente o dividendo');
    });

    test('sem retenção, o terminal é LPA ÷ Ke', () {
      const semCrescimento = DcfAssumptions(
        projectionYears: 1,
        growthRate: 0.0,
        perpetualGrowth: 0.0,
        discountRate: 0.10,
      );
      final o =
          DcfCalculator.shareholder(baseProfit: 10, assumptions: semCrescimento)
              .unwrap();
      expect(o.terminalValue, closeTo(100.0, 1e-9));
    });

    test('não há ponte de dívida: o fluxo já é do acionista', () {
      final o =
          DcfCalculator.shareholder(baseProfit: 10, assumptions: a).unwrap();
      expect(o.equityValue, closeTo(o.enterpriseValue, 1e-12));
      expect(o.equityShare, 1.0);
    });

    test('lucro base não positivo não é avaliável', () {
      final r = DcfCalculator.shareholder(baseProfit: 0, assumptions: a);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull, isA<InsufficientData>());
    });

    test('retentionFor devolve a retenção que gerou o crescimento', () {
      // O laço da decisão 25: alimentada com g = retorno × b, devolve b.
      const roe = 0.15, b = 0.40;
      final g = roe * b;
      expect(DcfCalculator.retentionFor(growth: g, returnOnCapital: roe),
          closeTo(b, 1e-12));
    });

    test('crescimento que exigiria reter todo o lucro não é financiável', () {
      expect(DcfCalculator.retentionFor(growth: 0.30, returnOnCapital: 0.20),
          isNull);
    });
  });

  group('ScenarioEngine', () {
    const center = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.05,
      perpetualGrowth: 0.02,
      discountRate: 0.10,
    );

    Result<double> valuate(DcfAssumptions a) => DcfCalculator.firm(
          baseProfit: 100,
          assumptions: a,
          netDebt: 0,
          sharesOutstanding: 10,
        ).map((o) => o.fairValuePerShare);

    test('modo discreto produz as três faixas nomeadas', () {
      final result = ScenarioEngine.run(
        source: DiscreteScenarios.around(center),
        valuate: valuate,
      );
      expect(result.isOk, isTrue);
      final outcome = result.unwrap();
      expect(outcome.mode, ScenarioMode.discrete);
      expect(outcome.discrete!.length, 3);
      // Pessimista < Base < Otimista.
      expect(outcome.discrete![ScenarioBand.bear]!,
          lessThan(outcome.discrete![ScenarioBand.base]!));
      expect(outcome.discrete![ScenarioBand.base]!,
          lessThan(outcome.discrete![ScenarioBand.bull]!));
    });

    test('modo Monte Carlo produz distribuição com percentis ordenados', () {
      final result = ScenarioEngine.run(
        source: StochasticScenarios.around(center),
        valuate: valuate,
        samples: 2000,
      );
      expect(result.isOk, isTrue);
      final distribution = result.unwrap().distribution!;
      expect(distribution.sortedValues.length, greaterThan(1500));
      expect(distribution.p5, lessThan(distribution.median));
      expect(distribution.median, lessThan(distribution.p95));
    });

    test('mesma semente produz exatamente o mesmo resultado', () {
      final first = ScenarioEngine.run(
        source: StochasticScenarios.around(center),
        valuate: valuate,
        samples: 500,
        seed: 7,
      ).unwrap();
      final second = ScenarioEngine.run(
        source: StochasticScenarios.around(center),
        valuate: valuate,
        samples: 500,
        seed: 7,
      ).unwrap();
      expect(first.distribution!.median, second.distribution!.median);
      expect(first.distribution!.p95, second.distribution!.p95);
    });

    test('os dois modos partem do mesmo cenário central', () {
      final discrete = ScenarioEngine.run(
        source: DiscreteScenarios.around(center),
        valuate: valuate,
      ).unwrap();
      final stochastic = ScenarioEngine.run(
        source: StochasticScenarios.around(center),
        valuate: valuate,
        samples: 200,
      ).unwrap();
      expect(discrete.baseValue, closeTo(stochastic.baseValue, 1e-12));
    });

    test('probabilidade de o valor justo superar o preço de mercado', () {
      final distribution = ScenarioEngine.run(
        source: StochasticScenarios.around(center),
        valuate: valuate,
        samples: 1000,
      ).unwrap().distribution!;
      final probability = distribution.probabilityAbove(0.0);
      expect(probability, closeTo(1.0, 1e-9));
    });
  });
}
