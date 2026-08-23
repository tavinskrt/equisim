import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final ticker = Ticker.parse('PETR4');
final asOf = DateTime(2026, 8, 19);

const capm = CapmInputs(
  riskFreeRate: 0.094,
  beta: 1.0,
  marketPremium: CapmInputs.defaultMarketPremium,
);

/// Exercício com todos os campos necessários ao FCFF.
FundamentalsSnapshot complete(int year, {double scale = 1.0}) =>
    FundamentalsSnapshot(
      ticker: ticker,
      fiscalPeriodEnd: DateTime(year, 12, 31),
      totalRevenue: 1000 * scale,
      ebit: 300 * scale,
      ebitda: 400 * scale,
      netIncome: 200 * scale,
      incomeBeforeTax: 300 * scale,
      incomeTaxExpense: 100 * scale,
      interestExpense: 55,
      earningsPerShare: 2.0 * scale,
      cash: 100,
      shortTermInvestments: 50,
      shortTermDebt: 100,
      longTermDebt: 400,
      totalStockholderEquity: 1500,
      bookValuePerShare: 15,
      operatingCashFlow: 320 * scale,
      freeCashFlow: 250 * scale,
      sharesOutstanding: 100,
      marketCap: 3000,
      enterpriseToEbitda: 6.0,
    );

/// Série de exercícios crescendo à taxa informada.
List<FundamentalsSnapshot> growingHistory({
  required double rate,
  int years = 6,
  int endYear = 2025,
}) {
  final out = <FundamentalsSnapshot>[];
  var scale = 1.0;
  for (var i = years - 1; i >= 0; i--) {
    out.add(complete(endYear - i, scale: scale));
    scale *= 1 + rate;
  }
  return out;
}

void main() {
  group('GrowthEstimator', () {
    test('recupera exatamente a taxa de uma série geométrica', () {
      final history = growingHistory(rate: 0.10);
      final estimate = GrowthEstimator.fromHistory(
        history,
        (s) => s.freeCashFlow,
        metricName: 'FCF',
      );
      expect(estimate.rate, closeTo(0.10, 1e-9));
      expect(estimate.periodsUsed, 6);
      expect(estimate.clamped, isFalse);
    });

    test('limita crescimento implausível e registra o valor bruto', () {
      final estimate = GrowthEstimator.fromHistory(
        growingHistory(rate: 0.50),
        (s) => s.freeCashFlow,
      );
      expect(estimate.rate, GrowthEstimator.ceilingRate);
      expect(estimate.clamped, isTrue);
      expect(estimate.basis, contains('limitado'));
    });

    test('impõe piso a séries em queda acentuada', () {
      final estimate = GrowthEstimator.fromHistory(
        growingHistory(rate: -0.30),
        (s) => s.freeCashFlow,
      );
      expect(estimate.rate, GrowthEstimator.floorRate);
      expect(estimate.clamped, isTrue);
    });

    test('cai para taxa conservadora com histórico curto demais', () {
      final estimate = GrowthEstimator.fromHistory(
        [complete(2024), complete(2025)],
        (s) => s.freeCashFlow,
      );
      expect(estimate.rate, GrowthEstimator.fallbackRate);
      expect(estimate.periodsUsed, 0);
    });

    test('ignora exercícios com valor não positivo', () {
      final history = [
        complete(2020),
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(2021, 12, 31),
          freeCashFlow: -500, // prejuízo não informa crescimento
        ),
        complete(2022, scale: 1.21),
        complete(2023, scale: 1.331),
      ];
      final estimate =
          GrowthEstimator.fromHistory(history, (s) => s.freeCashFlow);
      expect(estimate.periodsUsed, 3);
      expect(estimate.rate, greaterThan(0));
    });

    test('perpetuidade nunca supera o crescimento da economia', () {
      expect(GrowthEstimator.perpetual(explicitGrowth: 0.15), 0.03);
      expect(GrowthEstimator.perpetual(explicitGrowth: 0.01), 0.01);
      expect(GrowthEstimator.perpetual(explicitGrowth: -0.05), 0.0);
    });
  });

  group('ValuationCascade — escolha do modelo', () {
    ValuationInputs inputsWith(
      List<FundamentalsSnapshot> fundamentals, {
      List<DividendEvent> dividends = const [],
      double price = 30.0,
    }) =>
        ValuationInputs(
          ticker: ticker,
          asOf: asOf,
          fundamentals: fundamentals,
          dividends: dividends,
          marketPrice: price,
          capm: capm,
        );

    test('usa FCFF quando há fluxo, dívida e ações', () {
      final result =
          ValuationCascade.evaluate(inputsWith(growingHistory(rate: 0.08)));
      expect(result.isOk, isTrue);
      expect(result.unwrap().model, ValuationModel.dcfFcff);
    });

    test('FCFF desconta ao WACC, abaixo do custo do capital próprio', () {
      final result =
          ValuationCascade.evaluate(inputsWith(growingHistory(rate: 0.08)));
      final valuation = result.unwrap();
      expect(valuation.discountRate, lessThan(capm.costOfEquity),
          reason: 'com dívida e benefício fiscal, o WACC fica abaixo do Ke');
    });

    test('cai para LPA quando falta fluxo de caixa', () {
      final history = growingHistory(rate: 0.08)
          .map((s) => FundamentalsSnapshot(
                ticker: s.ticker,
                fiscalPeriodEnd: s.fiscalPeriodEnd,
                earningsPerShare: s.earningsPerShare,
                sharesOutstanding: s.sharesOutstanding,
              ))
          .toList();

      final result = ValuationCascade.evaluate(inputsWith(history));
      expect(result.isOk, isTrue);
      final valuation = result.unwrap();
      expect(valuation.model, ValuationModel.dcfEarnings);
      expect(valuation.discountRate, closeTo(capm.costOfEquity, 1e-12),
          reason: 'fluxo do acionista se desconta ao Ke, não ao WACC');
      expect(
        valuation.warnings.any((w) => w.contains('lucro por ação')),
        isTrue,
        reason: 'a queda de modelo precisa ficar visível',
      );
    });

    test('cai para Gordon quando só há dividendos', () {
      final history = [
        for (var y = 2020; y <= 2025; y++)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(y, 12, 31),
            bookValuePerShare: 15,
          ),
      ];
      final dividends = [
        DividendEvent(
          ticker: ticker,
          exDate: DateTime(2026, 3, 1),
          paymentDate: DateTime(2026, 3, 15),
          amountPerShare: 2.0,
          kind: DividendKind.dividendo,
        ),
      ];

      final result =
          ValuationCascade.evaluate(inputsWith(history, dividends: dividends));
      expect(result.isOk, isTrue);
      expect(result.unwrap().model, ValuationModel.gordonGrowth);
      expect(
        result.unwrap().warnings.any((w) => w.contains('Gordon')),
        isTrue,
      );
    });

    test('cai para múltiplos como último recurso', () {
      final history = [
        for (var y = 2020; y <= 2025; y++)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(y, 12, 31),
            ebitda: 400,
            enterpriseToEbitda: 6.0,
            sharesOutstanding: 100,
            shortTermDebt: 100,
            longTermDebt: 400,
            cash: 100,
          ),
      ];
      final result = ValuationCascade.evaluate(inputsWith(history));
      expect(result.isOk, isTrue);
      final valuation = result.unwrap();
      expect(valuation.model, ValuationModel.multiples);
      // EV = 400 × 6 = 2.400; dívida líquida = 500 − 100 = 400; equity = 2.000.
      expect(valuation.fairValue.reais, closeTo(20.0, 0.01));
      expect(
        valuation.warnings.any((w) => w.contains('referência grosseira')),
        isTrue,
      );
    });

    test('falha explicitamente quando nada é aplicável', () {
      final history = [
        for (var y = 2020; y <= 2025; y++)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(y, 12, 31),
          ),
      ];
      final result = ValuationCascade.evaluate(inputsWith(history));
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('rejeita preço de mercado inválido', () {
      final result = ValuationCascade.evaluate(
        inputsWith(growingHistory(rate: 0.05), price: 0),
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InvalidInput>());
    });
  });

  group('ValuationCascade — barreira temporal', () {
    test('exercício ainda não divulgado não é usado', () {
      // Exercício encerrado 30 dias antes da análise: dentro da defasagem
      // de 90 dias, portanto ainda não público.
      final result = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 1, 30),
        fundamentals: [complete(2025)],
        dividends: const [],
        marketPrice: 30,
        capm: capm,
      ));
      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.message, contains('divulgado'));
    });

    test('avisa quando o exercício disponível está defasado', () {
      final result = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: asOf,
        fundamentals: growingHistory(rate: 0.05, endYear: 2021),
        dividends: const [],
        marketPrice: 30,
        capm: capm,
      ));
      expect(result.isOk, isTrue);
      expect(
        result.unwrap().warnings.any((w) => w.contains('desatualizada')),
        isTrue,
      );
    });
  });

  group('ValuationCascade — cenários', () {
    test('modo discreto é o padrão e traz as três faixas', () {
      final result = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: asOf,
        fundamentals: growingHistory(rate: 0.08),
        dividends: const [],
        marketPrice: 30,
        capm: capm,
      ));
      final valuation = result.unwrap();
      expect(valuation.mode, ScenarioMode.discrete);
      expect(valuation.discreteScenarios!.length, 3);
    });

    test('Monte Carlo é ativado trocando a fonte de premissas', () {
      final result = ValuationCascade.evaluate(
        ValuationInputs(
          ticker: ticker,
          asOf: asOf,
          fundamentals: growingHistory(rate: 0.08),
          dividends: const [],
          marketPrice: 30,
          capm: capm,
        ),
        scenarioBuilder: StochasticScenarios.around,
        monteCarloSamples: 1000,
      );
      final valuation = result.unwrap();
      expect(valuation.mode, ScenarioMode.monteCarlo);
      expect(valuation.distribution, isNotNull);
      expect(valuation.distribution!.p5, lessThan(valuation.distribution!.p95));
    });

    test('trocar de modo não altera o cenário base', () {
      final inputs = ValuationInputs(
        ticker: ticker,
        asOf: asOf,
        fundamentals: growingHistory(rate: 0.08),
        dividends: const [],
        marketPrice: 30,
        capm: capm,
      );
      final discrete = ValuationCascade.evaluate(inputs).unwrap();
      final stochastic = ValuationCascade.evaluate(
        inputs,
        scenarioBuilder: StochasticScenarios.around,
        monteCarloSamples: 500,
      ).unwrap();
      expect(discrete.fairValue, stochastic.fairValue);
    });
  });

  group('Unidade de negociação', () {
    test('ação comum devolve razão 1', () {
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 12888733000,
          marketCap: 571228600000,
          marketPrice: 44.32,
        ),
        1.0,
      );
    });

    test('unit de cinco ações é reconhecida pelos números da fonte', () {
      // SAPR11 em 21/08/2026: 1,511 bi de ações, valor de mercado de
      // R$ 10,08 bi e unit a R$ 33,35.
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 1511205500,
          marketCap: 10079740685,
          marketPrice: 33.35,
        ),
        5.0,
      );
    });

    test('unit de três ações também', () {
      // BPAC11 nas mesmas condições.
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 11670063000,
          marketCap: 202203291580,
          marketPrice: 51.97,
        ),
        3.0,
      );
    });

    test('razão longe de um inteiro é recusada em favor de 1', () {
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 1000,
          marketCap: 1000,
          marketPrice: 2.4,
        ),
        1.0,
        reason: 'nenhuma unit da B3 tem 2,4 ações; melhor não aplicar fator',
      );
    });

    test('sem valor de mercado publicado, não se inventa fator', () {
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 1000,
          marketCap: null,
          marketPrice: 10,
        ),
        1.0,
      );
    });

    test('o preço justo sai por unit, não por ação', () {
      // Mesma empresa, mesmos demonstrativos: só muda a forma de negociar.
      final porAcao = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: asOf,
        fundamentals: growingHistory(rate: 0.05),
        dividends: const [],
        marketPrice: 30,
        capm: capm,
      ));
      // 100 ações a R$ 30 valem R$ 3.000 de mercado; em units de 5, são 20
      // units a R$ 150.
      final porUnit = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: asOf,
        fundamentals: growingHistory(rate: 0.05),
        dividends: const [],
        marketPrice: 150,
        capm: capm,
      ));

      expect(porAcao.isOk, isTrue);
      expect(porUnit.isOk, isTrue);
      expect(
        porUnit.unwrap().fairValue.reais,
        closeTo(porAcao.unwrap().fairValue.reais * 5, 0.05),
        reason: 'o valor da firma é o mesmo; muda o número de papéis',
      );
      // E o que importa para a decisão — a distância até o preço justo — fica
      // igual nos dois casos.
      expect(
        porUnit.unwrap().upside,
        closeTo(porAcao.unwrap().upside, 0.01),
      );
    });
  });

  group('BaseFlowNormalizer', () {
    test('série comportada passa intacta', () {
      final base = BaseFlowNormalizer.normalize([10, 11, 12, 13, 14]);
      expect(base.value, 14);
      expect(base.winsorized, isFalse);
      expect(base.median, 12);
    });

    test('exercício atípico é aparado para a borda da banda', () {
      // SAPR11 em 21/08/2026: fluxo livre de R$ 4,44 bi contra mediana de
      // R$ 0,47 bi em cinco exercícios.
      final base =
          BaseFlowNormalizer.normalize([0.380, 0.242, 0.468, 0.866, 4.445]);
      expect(base.winsorized, isTrue);
      expect(base.median, closeTo(0.468, 1e-9));
      expect(base.value, closeTo(0.468 * 1.5, 1e-9),
          reason: 'apara para a borda, não substitui pela mediana');
      expect(base.observed, closeTo(4.445, 1e-9));
      expect(base.deviationFactor, closeTo(9.5, 0.1));
    });

    test('exercício muito abaixo da mediana também é aparado', () {
      final base = BaseFlowNormalizer.normalize([100, 90, 95, 88, 10]);
      expect(base.winsorized, isTrue);
      expect(base.value, closeTo(90 * 0.5, 1e-9));
    });

    test('preserva a direção da tendência dentro da banda', () {
      // Queda consistente, sem exercício isolado: não há o que corrigir.
      final base = BaseFlowNormalizer.normalize([20, 18, 16, 14, 12]);
      expect(base.winsorized, isFalse);
      expect(base.value, 12);
    });

    test('mediana não positiva não autoriza aparar nada', () {
      final base = BaseFlowNormalizer.normalize([-5, -3, -4, 1, 8]);
      expect(base.winsorized, isFalse);
      expect(base.value, 8, reason: 'sem mediana positiva não há banda válida');
      expect(base.median, lessThanOrEqualTo(0));
    });

    test('amostra curta demais não sustenta mediana', () {
      final base = BaseFlowNormalizer.normalize([3, 40]);
      expect(base.winsorized, isFalse);
      expect(base.value, 40);
      expect(base.median, isNull);
    });

    test('usa apenas os exercícios mais recentes da janela', () {
      final base = BaseFlowNormalizer.normalize(
        [1000, 1000, 1000, 10, 11, 12, 13, 14],
      );
      expect(base.periodsUsed, BaseFlowNormalizer.defaultWindow);
      expect(base.median, 12, reason: 'os exercicios antigos de 1.000 ficam de fora');
    });
  });

  group('MarketAnchors — unidades', () {
    test('crescimento perpétuo composto real com inflação', () {
      const anchors = MarketAnchors(
        riskFreeCagr: 0.094,
        marketCagr: 0.1126,
        inflationCagr: 0.05,
        observedYears: 10,
      );
      // (1 + 3%) × (1 + 5%) − 1
      expect(anchors.nominalEconomyGrowth, closeTo(0.0815, 1e-6));
      expect(
        anchors.nominalEconomyGrowth,
        greaterThan(GrowthEstimator.realEconomyGrowth),
        reason: 'o teto nominal precisa superar o real, ou a unidade se mistura',
      );
    });

    test('sem taxa corrente informada, cai para a média histórica', () {
      const anchors = MarketAnchors(
        riskFreeCagr: 0.094,
        marketCagr: 0.1126,
        observedYears: 10,
      );
      expect(anchors.currentRiskFreeRate, 0.094);
    });

    test('taxa de desconto e limiar da meta são números distintos', () {
      const anchors = MarketAnchors(
        riskFreeCagr: 0.094,
        currentRiskFreeRate: 0.1415,
        marketCagr: 0.1126,
        observedYears: 10,
      );
      expect(anchors.riskFreeCagr, isNot(anchors.currentRiskFreeRate));
      expect(anchors.currentRiskFreeRate, 0.1415);
    });
  });


  group('CostOfCapital — banda de sanidade', () {
    const rf = 0.125;
    const capmRf = CapmInputs(
      riskFreeRate: rf,
      beta: 1.0,
      marketPremium: CapmInputs.defaultMarketPremium,
    );

    test('custo da dívida abaixo do soberano sobe para ele', () {
      // PETR4 em 21/08/2026: despesa financeira sobre dívida bruta deu
      // 0,9% a.a., o que não é custo de dívida em lugar nenhum.
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.009,
        taxRate: 0.266,
        equityValue: 391,
        debtValue: 384,
      );
      expect(coc.effectiveCostOfDebt, rf);
      expect(coc.costOfDebtWasClamped, isTrue);
    });

    test('custo da dívida acima do teto de crédito desce para ele', () {
      // WEGE3 na mesma medição: 47,3% a.a.
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.473,
        taxRate: 0.168,
        equityValue: 203,
        debtValue: 4.6,
      );
      expect(coc.effectiveCostOfDebt, rf + CostOfCapital.maxCreditSpread);
      expect(coc.costOfDebtWasClamped, isTrue);
    });

    test('custo da dívida plausível passa intacto', () {
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.16,
        taxRate: 0.34,
        equityValue: 100,
        debtValue: 40,
      );
      expect(coc.effectiveCostOfDebt, 0.16);
      expect(coc.costOfDebtWasClamped, isFalse);
      expect(coc.waccWasFloored, isFalse);
    });

    test('WACC nunca desce abaixo da taxa livre de risco', () {
      // Empresa muito alavancada: o benefício fiscal empurraria o desconto
      // para baixo do soberano, e a perpetuidade explodiria.
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: rf,
        taxRate: 0.34,
        equityValue: 10,
        debtValue: 90,
      );
      expect(coc.rawWacc, lessThan(rf));
      expect(coc.wacc, rf);
      expect(coc.waccWasFloored, isTrue);
    });
  });


  group('SwapAssetBetweenPortfolios', () {
    Asset assetOf(String symbol, String sector) => Asset(
          ticker: Ticker.parse(symbol),
          name: symbol,
          sector: Sector.fromKey(sector, label: sector),
        );

    Portfolio principalWith(List<Asset> assets) => Portfolio.equalWeighted(
          id: 'principal',
          name: 'Principal',
          kind: PortfolioKind.principal,
          assets: assets,
        ).unwrap();

    Portfolio reservaWith(List<Asset> assets) => Portfolio.equalWeighted(
          id: 'reserva',
          name: 'Reserva',
          kind: PortfolioKind.reserva,
          assets: assets,
        ).unwrap();

    test('promove ativo da reserva e reequipondera as duas carteiras', () {
      final result = SwapAssetBetweenPortfolios.call(
        principal: principalWith([
          assetOf('PETR4', 'energia'),
          assetOf('VALE3', 'materiais'),
        ]),
        reserva: reservaWith([assetOf('ITUB4', 'financeiro')]),
        ticker: Ticker.parse('ITUB4'),
        toPrincipal: true,
      );

      expect(result.isOk, isTrue);
      final outcome = result.unwrap();
      expect(outcome.principal.length, 3);
      expect(outcome.reserva.length, 0);
      expect(Weights.sumsToOne(outcome.principal.weights), isTrue);
      for (final w in outcome.principal.weights) {
        expect(w.value, closeTo(1 / 3, 1e-9));
      }
    });

    test('rebaixa ativo do principal para a reserva', () {
      final result = SwapAssetBetweenPortfolios.call(
        principal: principalWith([
          assetOf('PETR4', 'energia'),
          assetOf('VALE3', 'materiais'),
        ]),
        reserva: reservaWith([assetOf('ITUB4', 'financeiro')]),
        ticker: Ticker.parse('PETR4'),
        toPrincipal: false,
      );
      final outcome = result.unwrap();
      expect(outcome.principal.length, 1);
      expect(outcome.reserva.length, 2);
    });

    test('recalcula a concentração setorial na mesma operação', () {
      final result = SwapAssetBetweenPortfolios.call(
        principal: principalWith([assetOf('ITUB4', 'financeiro')]),
        reserva: reservaWith([assetOf('BBAS3', 'financeiro')]),
        ticker: Ticker.parse('BBAS3'),
        toPrincipal: true,
      );
      final outcome = result.unwrap();
      expect(outcome.concentration.hasAlert, isTrue);
      expect(outcome.concentration.concentrated.first.sector.key, 'financeiro');
    });

    test('rejeita ativo ausente na origem', () {
      final result = SwapAssetBetweenPortfolios.call(
        principal: principalWith([assetOf('PETR4', 'energia')]),
        reserva: reservaWith([assetOf('ITUB4', 'financeiro')]),
        ticker: Ticker.parse('VALE3'),
        toPrincipal: true,
      );
      expect(result.isErr, isTrue);
    });

    test('respeita o teto de 15 ativos no destino', () {
      final cheia = principalWith([
        for (var i = 0; i < 15; i++) assetOf('AAAA$i', 'financeiro'),
      ]);
      final result = SwapAssetBetweenPortfolios.call(
        principal: cheia,
        reserva: reservaWith([assetOf('ITUB4', 'financeiro')]),
        ticker: Ticker.parse('ITUB4'),
        toPrincipal: true,
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.message, contains('15'));
    });
  });

  group('EvaluateGoalAlignment', () {
    final portfolio = Portfolio.equalWeighted(
      id: 'p',
      name: 'Principal',
      kind: PortfolioKind.principal,
      assets: [
        Asset(ticker: Ticker.parse('PETR4'), name: 'PETR4'),
        Asset(ticker: Ticker.parse('VALE3'), name: 'VALE3'),
      ],
    ).unwrap();

    ValuationResult valuationWith(String symbol, double fair, double price) =>
        ValuationResult(
          ticker: Ticker.parse(symbol),
          asOf: asOf,
          model: ValuationModel.dcfFcff,
          fairValue: Money.fromReais(fair),
          marketPrice: Money.fromReais(price),
          discountRate: 0.12,
        );

    test('carteira que supera a exigência é aprovada', () {
      final goal = FinancialGoal(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(200000),
      );

      final result = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: {
          Ticker.parse('PETR4'): valuationWith('PETR4', 60, 40),
          Ticker.parse('VALE3'): valuationWith('VALE3', 60, 40),
        },
        netDividendYields: {
          Ticker.parse('PETR4'): 0.05,
          Ticker.parse('VALE3'): 0.05,
        },
        anchors: MarketAnchors.fallback2026,
      );

      expect(result.isOk, isTrue);
      final alignment = result.unwrap();
      // 50% de upside em 12 meses + 5% de DY = 55% esperado ao ano.
      expect(alignment.expectedReturn, closeTo(0.55, 1e-6));
      expect(alignment.meetsGoal, isTrue);
      expect(alignment.gap, greaterThan(0));
      expect(alignment.valuationCoverage, closeTo(1.0, 1e-9));
    });

    test('sinaliza cobertura fraca de avaliação', () {
      final goal = FinancialGoal(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(200000),
      );

      final alignment = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: {Ticker.parse('PETR4'): valuationWith('PETR4', 50, 40)},
        netDividendYields: const {},
        anchors: MarketAnchors.fallback2026,
      ).unwrap();

      expect(alignment.valuationCoverage, closeTo(0.5, 1e-9));
      expect(alignment.coverageIsWeak, isTrue);
    });

    test('meta impossível propaga a falha do solver', () {
      final goal = FinancialGoal(
        initialContribution: Money.fromReais(1),
        monthlyContribution: Money.zero,
        months: 12,
        targetWealth: Money.fromReais(1000000000),
      );
      final result = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: const {},
        netDividendYields: const {},
        anchors: MarketAnchors.fallback2026,
      );
      expect(result.isErr, isTrue);
    });

    test('veredito de viabilidade acompanha o alinhamento', () {
      final goal = FinancialGoal(
        initialContribution: Money.fromReais(1000),
        monthlyContribution: Money.fromReais(100),
        months: 24,
        targetWealth: Money.fromReais(100000),
      );
      final alignment = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: const {},
        netDividendYields: const {},
        anchors: MarketAnchors.fallback2026,
      ).unwrap();
      expect(alignment.verdict.blocks, isTrue);
    });
  });
}
