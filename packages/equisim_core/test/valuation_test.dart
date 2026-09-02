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
      );
      // 0,6 × 0,145 + 0,4 × 0,11 × 0,66 = 0,087 + 0,02904 = 0,11604
      expect(levered.wacc, closeTo(0.11604, 1e-9));
      expect(levered.wacc, lessThan(levered.costOfEquity));
    });
  });

  group('DCF por FCFF', () {
    const assumptions = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.05,
      perpetualGrowth: 0.02,
      discountRate: 0.10,
    );

    test('valor por ação confere com o cálculo manual', () {
      final result = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: assumptions,
        netDebt: 0,
        sharesOutstanding: 10,
      );
      expect(result.isOk, isTrue);
      final outcome = result.unwrap();

      // Fluxos: 105 · 110,25 · 115,7625 · 121,550625 · 127,62815625
      expect(outcome.projectedFlows.length, 5);
      expect(outcome.projectedFlows.first, closeTo(105.0, 1e-9));
      expect(outcome.projectedFlows.last, closeTo(127.62815625, 1e-9));

      // Σ dos fluxos descontados a 10% ≈ 435,8121
      final sumDiscounted =
          outcome.discountedFlows.reduce((a, b) => a + b);
      expect(sumDiscounted, closeTo(435.812086, 1e-5));

      // VT de Gordon = 127,62815625 × 1,02 / 0,08 = 1627,258992
      expect(outcome.terminalValue, closeTo(1627.2589922, 1e-5));
      expect(outcome.enterpriseValue, closeTo(1446.211893, 1e-4));
      expect(outcome.fairValuePerShare, closeTo(144.6211893, 1e-5));
    });

    test('dívida líquida reduz o valor do equity', () {
      final semDivida = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: assumptions,
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();
      final comDivida = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: assumptions,
        netDebt: 446.211893,
        sharesOutstanding: 10,
      ).unwrap();
      expect(comDivida.enterpriseValue,
          closeTo(semDivida.enterpriseValue, 1e-9));
      expect(comDivida.fairValuePerShare, closeTo(100.0, 1e-4));
    });

    test('reporta a parcela explicada pelo valor terminal', () {
      final outcome = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: assumptions,
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();
      // ~70% do valor vem da perpetuidade — informação que o usuário precisa ver.
      expect(outcome.terminalShare, closeTo(0.6986, 1e-3));
    });

    test('protege contra a explosão de Gordon quando r se aproxima de g', () {
      final result = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: const DcfAssumptions(
          growthRate: 0.05,
          perpetualGrowth: 0.099,
          discountRate: 0.10,
        ),
        netDebt: 0,
        sharesOutstanding: 10,
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ComputationFailure>());
    });

    test('fluxo de caixa negativo não é avaliável por FCFF', () {
      final result = DcfCalculator.fcff(
        baseFreeCashFlow: -50,
        assumptions: assumptions,
        netDebt: 0,
        sharesOutstanding: 10,
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('exige quantidade de ações válida', () {
      final result = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: assumptions,
        netDebt: 0,
        sharesOutstanding: 0,
      );
      expect(result.isErr, isTrue);
    });
  });

  group('Valor terminal por múltiplo de saída', () {
    test('aplica EV/EBITDA sobre o EBITDA terminal', () {
      final result = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: const DcfAssumptions(
          projectionYears: 5,
          growthRate: 0.05,
          perpetualGrowth: 0.02,
          discountRate: 0.10,
          terminalMethod: TerminalValueMethod.exitMultiple,
          exitMultiple: 6.0,
        ),
        netDebt: 0,
        sharesOutstanding: 10,
        terminalEbitda: 200,
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().terminalValue, closeTo(1200.0, 1e-9));
    });

    test('falha explicitamente sem EBITDA terminal', () {
      final result = DcfCalculator.fcff(
        baseFreeCashFlow: 100,
        assumptions: const DcfAssumptions(
          growthRate: 0.05,
          perpetualGrowth: 0.02,
          discountRate: 0.10,
          terminalMethod: TerminalValueMethod.exitMultiple,
          exitMultiple: 6.0,
        ),
        netDebt: 0,
        sharesOutstanding: 10,
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
    });
  });

  group('DCF por LPA — retenção para financiar o crescimento', () {
    const base = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.05,
      perpetualGrowth: 0.03,
      discountRate: 0.10,
    );

    test('sem ROE, o crescimento é zerado e o valor vira LPA ÷ Ke', () {
      // *Earnings power value*: sem saber quanto do lucro precisa ficar na
      // empresa, crescer seria contar o mesmo dinheiro duas vezes. O modelo
      // colapsa no lucro estacionário, e a identidade é exata — a soma do
      // período explícito com o terminal descontado reconstitui LPA/r.
      final result = DcfCalculator.earningsPerShare(
        baseEps: 10,
        assumptions: base,
      );
      expect(result.unwrap().fairValuePerShare, closeTo(100.0, 1e-9));
    });

    test('com ROE, desconta só a parcela distribuível do lucro', () {
      // ROE de 20% e crescimento de 5% implicam reter 25% (b = g/ROE); na
      // perpetuidade, 3%/20% = 15%. O fluxo descontado é o lucro menos isso.
      final result = DcfCalculator.earningsPerShare(
        baseEps: 10,
        assumptions: base,
        returnOnEquity: 0.20,
      );
      final outcome = result.unwrap();
      // Primeiro fluxo: 10 × 1,05 × (1 − 0,25) = 7,875.
      expect(outcome.projectedFlows.first, closeTo(7.875, 1e-12));
    });

    test('a retenção derruba o preço justo diante da dupla contagem', () {
      // O modelo antigo distribuía o lucro inteiro E o fazia crescer. É o
      // defeito que a lente `metodo` apontou, e a diferença não é marginal.
      final comRetencao = DcfCalculator.earningsPerShare(
        baseEps: 10,
        assumptions: base,
        returnOnEquity: 0.20,
      ).unwrap().fairValuePerShare;

      // ROE altíssimo ⇒ retenção próxima de zero ⇒ o valor tende ao do modelo
      // que distribuía tudo. É a forma de reproduzir o comportamento antigo
      // sem manter o código antigo por perto.
      final semRetencao = DcfCalculator.earningsPerShare(
        baseEps: 10,
        assumptions: base,
        returnOnEquity: 1e6,
      ).unwrap().fairValuePerShare;

      expect(comRetencao, lessThan(semRetencao));
      expect(semRetencao / comRetencao, greaterThan(1.15));
    });

    test('crescimento que exigiria reter todo o lucro não é financiável', () {
      // g = 12% com ROE de 8% pediria b = 1,5: mais lucro do que existe. A
      // premissa está errada, não apertada — o modelo cai para estacionário.
      expect(
        DcfCalculator.retentionFor(growth: 0.12, returnOnEquity: 0.08),
        isNull,
      );
      expect(
        DcfCalculator.retentionFor(growth: 0.05, returnOnEquity: 0.20),
        closeTo(0.25, 1e-12),
      );
      // Crescimento nulo não retém nada, e ROE ausente não sustenta a relação.
      expect(DcfCalculator.retentionFor(growth: 0.0, returnOnEquity: 0.2), 0.0);
      expect(DcfCalculator.retentionFor(growth: 0.05, returnOnEquity: null),
          isNull);
      expect(
        DcfCalculator.retentionFor(growth: 0.05, returnOnEquity: -0.1),
        isNull,
      );
    });
  });

  group('ScenarioEngine', () {
    const center = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.05,
      perpetualGrowth: 0.02,
      discountRate: 0.10,
    );

    Result<double> valuate(DcfAssumptions a) => DcfCalculator.fcff(
          baseFreeCashFlow: 100,
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
