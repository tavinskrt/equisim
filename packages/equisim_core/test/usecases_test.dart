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
      totalStockholderEquity: 1500 * scale,
      bookValuePerShare: 15 * scale,
      operatingCashFlow: 320 * scale,
      freeCashFlow: 250 * scale,
      // NOPAT publicado e patrimônio crescendo com o lucro retido: é o que a
      // decisão 25 exige para reconstituir base de capital e retorno.
      nopat: 200 * scale,
      sharesOutstanding: 100,
      sharesOutstandingAsOf: 100,
      marketCap: 3000,
      enterpriseToEbitda: 6.0,
    );

/// Série de exercícios crescendo à taxa informada.
///
/// Dez exercícios por padrão: a Porta 0 exige ao menos oito publicados, que é o
/// mínimo em que a janela de ciclo existe e os testes das guardas têm graus de
/// liberdade (decisão 25).
List<FundamentalsSnapshot> growingHistory({
  required double rate,
  int years = 10,
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
      expect(estimate.periodsUsed, 10);
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
      // O teto passa a ser informado, não constante: 6,52% é a composição do
      // crescimento real medido do IBC-Br com o IPCA observado (decisão 25).
      const teto = 0.0652;
      expect(
          GrowthEstimator.perpetual(explicitGrowth: 0.15, economyGrowth: teto),
          teto);
      expect(
          GrowthEstimator.perpetual(explicitGrowth: 0.01, economyGrowth: teto),
          0.01);
      expect(
          GrowthEstimator.perpetual(explicitGrowth: -0.05, economyGrowth: teto),
          0.0);
    });
  });

  group('ValuationCascade — escolha do modelo', () {
    ValuationInputs inputsWith(
      List<FundamentalsSnapshot> fundamentals, {
      double price = 30.0,
    }) =>
        ValuationInputs(
          ticker: ticker,
          asOf: asOf,
          fundamentals: fundamentals,
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

    test('sem lucro operacional recorrente, a Porta 3 manda para a via do '
        'acionista', () {
      // Antes da decisão 25 a via caía pelo sinal do fluxo de caixa de um
      // exercício. Agora quem decide é o lucro operacional recorrente, que é o
      // fluxo de manutenção sob a aproximação de capex de manutenção igual à
      // depreciação — o que não penaliza quem está em ciclo de investimento.
      final history = growingHistory(rate: 0.08)
          .map((s) => FundamentalsSnapshot(
                ticker: s.ticker,
                fiscalPeriodEnd: s.fiscalPeriodEnd,
                earningsPerShare: s.earningsPerShare,
                netIncome: s.netIncome,
                bookValuePerShare: s.bookValuePerShare,
                sharesOutstanding: s.sharesOutstanding,
                sharesOutstandingAsOf: s.sharesOutstandingAsOf,
              ))
          .toList();

      final result = ValuationCascade.evaluate(inputsWith(history));
      expect(result.isOk, isTrue);
      final valuation = result.unwrap();
      expect(valuation.model, ValuationModel.dcfEarnings);
      expect(valuation.discountRate, closeTo(capm.costOfEquity, 1e-12),
          reason: 'fluxo do acionista se desconta ao Ke, não ao WACC');
      expect(
        valuation.warnings.any((w) => w.contains('lucro operacional')),
        isTrue,
        reason: 'a escolha de via precisa ficar visível',
      );
    });

    test('sem base de capital reconstituível, recusa em vez de inventar piso',
        () {
      // Até a decisão 25 este ativo caía para múltiplos e devolvia o valor
      // patrimonial rotulado como piso contábil. O degrau saiu: ele reconstruía
      // o valor da firma a partir do múltiplo que o mercado já atribui ao
      // próprio ativo, devolvendo o preço de mercado por construção — e um
      // potencial de valorização nulo por aritmética, não por análise.
      final history = [
        for (var y = 2020; y <= 2025; y++)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(y, 12, 31),
            bookValuePerShare: 15,
          ),
      ];

      final result = ValuationCascade.evaluate(inputsWith(history));
      expect(result.isErr, isTrue,
          reason: 'sem contagem de ações do exercício não há patrimônio nem '
              'capital investido, e nenhuma das duas vias se sustenta');
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('múltiplo próprio não é mais degrau de cascata', () {
      // O EV/EBITDA da própria empresa reconstrói o próprio preço. Com dado
      // suficiente só para ele, a resposta correta é recusar.
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
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
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
        marketPrice: 30,
        capm: capm,
      ));
      // 100 ações a R$ 30 valem R$ 3.000 de mercado; em units de 5, são 20
      // units a R$ 150.
      final porUnit = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: asOf,
        fundamentals: growingHistory(rate: 0.05),
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

  group('MarketAnchors — unidades', () {
    test('crescimento perpétuo composto real com inflação', () {
      const anchors = MarketAnchors(
        riskFreeCagr: 0.094,
        marketCagr: 0.1126,
        inflationCagr: 0.05,
        observedYears: 10,
      );
      // (1 + 1,45%) × (1 + 5%) − 1. A parcela real deixou de ser a constante
      // de 3% e passou a ser medida do IBC-Br (decisão 25).
      expect(anchors.nominalEconomyGrowth, closeTo(0.0652, 1e-4));
      expect(
        anchors.nominalEconomyGrowth,
        greaterThan(anchors.realEconomyGrowth),
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
      final goal = FinancialGoal.unvalidated(
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
        anchors: MarketAnchors.fallback2026,
      );

      expect(result.isOk, isTrue);
      final alignment = result.unwrap();
      // 50% de potencial, convergindo em 36 meses e sem parcela de provento:
      // (1,50)^(1/3) − 1 = 14,47% ao ano. Com os 12 meses anteriores a
      // anualização era a identidade e o potencial bruto virava retorno anual
      // — o defeito D1 que a decisão 25 corrigiu.
      expect(alignment.expectedReturn, closeTo(0.1447, 1e-4));
      expect(alignment.meetsGoal, isTrue);
      expect(alignment.gap, greaterThan(0));
      expect(alignment.valuationCoverage, closeTo(1.0, 1e-9));
    });

    test('a lacuna vira o yield que a fecharia, sem premissa de provento', () {
      // O esperado é retorno de PREÇO desde a decisão 023. Uma carteira que
      // paga bem aparece em déficit permanente, e o número que desfaz essa
      // leitura é a própria lacuna invertida — não uma estimativa de yield.
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(400000),
      );

      final alignment = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: {
          Ticker.parse('PETR4'): valuationWith('PETR4', 44, 40),
          Ticker.parse('VALE3'): valuationWith('VALE3', 44, 40),
        },
        anchors: MarketAnchors.fallback2026,
      ).unwrap();

      expect(alignment.meetsGoal, isFalse);
      final yieldToClose = alignment.yieldToCloseGap;
      expect(yieldToClose, isNotNull);
      // Identidade exata: o yield que fecha é a lacuna com o sinal trocado.
      expect(yieldToClose!, closeTo(-alignment.gap / 100, 1e-12));
      expect(yieldToClose, greaterThan(0));
    });

    test('meta atingida não tem lacuna a fechar', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(200000),
      );

      final alignment = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: {
          Ticker.parse('PETR4'): valuationWith('PETR4', 60, 40),
          Ticker.parse('VALE3'): valuationWith('VALE3', 60, 40),
        },
        anchors: MarketAnchors.fallback2026,
      ).unwrap();

      expect(alignment.meetsGoal, isTrue);
      expect(alignment.yieldToCloseGap, isNull);
    });

    test('sinaliza cobertura fraca de avaliação', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(200000),
      );

      final alignment = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: {Ticker.parse('PETR4'): valuationWith('PETR4', 50, 40)},
        anchors: MarketAnchors.fallback2026,
      ).unwrap();

      expect(alignment.valuationCoverage, closeTo(0.5, 1e-9));
      expect(alignment.coverageIsWeak, isTrue);
    });

    test('meta impossível propaga a falha do solver', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1),
        monthlyContribution: Money.zero,
        months: 12,
        targetWealth: Money.fromReais(1000000000),
      );
      final result = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: const {},
        anchors: MarketAnchors.fallback2026,
      );
      expect(result.isErr, isTrue);
    });

    test('veredito de viabilidade acompanha o alinhamento', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(1000),
        monthlyContribution: Money.fromReais(100),
        months: 24,
        targetWealth: Money.fromReais(100000),
      );
      final alignment = EvaluateGoalAlignment.call(
        portfolio: portfolio,
        goal: goal,
        valuations: const {},
        anchors: MarketAnchors.fallback2026,
      ).unwrap();
      expect(alignment.verdict.blocks, isTrue);
    });
  });
}
