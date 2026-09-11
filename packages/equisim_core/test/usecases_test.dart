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
      // **O piso é o da banda de sanidade, e não zero** (decisão 56). O piso
      // em zero afirmava que toda empresa em declínio volta a crescer zero em
      // dez anos, e tornava inalcançável o limite que o projeto já declarara
      // em `floorRate` — com a razão escrita lá.
      expect(
          GrowthEstimator.perpetual(explicitGrowth: -0.05, economyGrowth: teto),
          GrowthEstimator.floorRate);
      expect(
          GrowthEstimator.perpetual(explicitGrowth: -0.02, economyGrowth: teto),
          -0.02);
      // Abaixo da banda, o piso segura: encolher para sempre tem limite.
      expect(
          GrowthEstimator.perpetual(explicitGrowth: -0.40, economyGrowth: teto),
          GrowthEstimator.floorRate);
      // E o teto continua onde estava, mesmo com economia encolhendo.
      expect(
          GrowthEstimator.perpetual(explicitGrowth: 0.10, economyGrowth: -0.01),
          closeTo(-0.01, 1e-12));
      // Economia encolhendo mais que o piso: o teto vence, e não estoura.
      // `clamp` lança quando o piso passa o teto.
      expect(
          GrowthEstimator.perpetual(explicitGrowth: 0.10, economyGrowth: -0.20),
          closeTo(-0.20, 1e-12));
      expect(
          GrowthEstimator.perpetual(explicitGrowth: -0.30, economyGrowth: -0.20),
          closeTo(-0.20, 1e-12));
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
      //
      // **Não remova esta migração sem refazer a medição da decisão 64.** A
      // lente `metodo` propôs recusar estes ativos em vez de migrá-los; sobre
      // 8 coortes *point-in-time*, a Porta 3 saiu com o MAIOR poder de
      // ordenação dos três roteamentos (IC12 +0,4197, IC36 +0,3815), e
      // recusá-la baixaria o IC do universo inteiro.
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

    test('a unit é reconhecida mesmo com o preço andado desde o valor de '
        'mercado', () {
      // SAPR11 em 04/09/2026: 503,7 mi de ações, R$ 3,608 bi de valor de
      // mercado e unit a R$ 34,95 — razão medida de **4,8799**, a 0,1201 do
      // inteiro. A banda absoluta de 0,12 recusava por **0,0001**, e a unit
      // de cinco ações caía para a convenção de ação comum. Decisão 61.
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 503733800,
          marketCap: 3607751300,
          marketPrice: 34.95,
        ),
        5.0,
      );
    });

    test('a mesma discordância relativa decide igual em qualquer unit', () {
      // O desvio mede quanto o preço andou desde o valor de mercado
      // publicado, e isso não depende de quantas ações formam a unit. Com
      // banda absoluta, 3% valiam 0,06 em u = 2 e 0,15 em u = 5 — aceito ali,
      // recusado aqui, pela mesma discordância.
      for (final u in [2, 3, 5, 10]) {
        expect(
          ValuationCascade.quotedUnitRatio(
            sharesOutstanding: u * 1.03e9,
            marketCap: 1e9,
            marketPrice: 1.0,
          ),
          u.toDouble(),
          reason: '3% de discordância cabe em qualquer unit',
        );
      }
    });

    test('e a tolerância relativa aperta a unit de duas ações', () {
      // 5,5% em u = 2 são 0,11 absolutos — dentro da banda antiga, fora da
      // nova. A troca não é permissiva em toda parte: de u = 3 para cima
      // afrouxa, em u = 2 aperta, e em u = 1 não decide nada.
      expect(
        ValuationCascade.quotedUnitRatio(
          sharesOutstanding: 2.11e9,
          marketCap: 1e9,
          marketPrice: 1.0,
        ),
        1.0,
      );
    });

    test('em ação comum a tolerância não decide nada', () {
      // Aceitar devolve 1,0 e recusar devolve 1,0. É por isso que apertar a
      // banda em u = 1 não tem consequência.
      for (final bruto in [0.79, 0.95, 1.0, 1.05, 1.21]) {
        expect(
          ValuationCascade.quotedUnitRatio(
            sharesOutstanding: bruto * 1e9,
            marketCap: 1e9,
            marketPrice: 1.0,
          ),
          1.0,
        );
      }
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

    test('o prêmio de crédito vem da alavancagem, não da despesa financeira', () {
      // A cobertura de juros foi o primeiro substituto da razão observada e
      // herdava o defeito dela: a despesa contaminada por arrendamento e
      // variação cambial está no denominador. Medido, ela punia justamente as
      // sólidas — ABEV3 e WEGE3, de caixa líquido, pagavam 2,4 p.p.; a SAPR11,
      // com 0,60x de alavancagem, pagava o teto de 10 p.p.
      const caixaLiquido = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.473,
        taxRate: 0.34,
        equityValue: 203,
        debtValue: 4.6,
        interestCoverage: 3.68,
        netDebtToEbitda: -0.30,
      );
      expect(caixaLiquido.effectiveCostOfDebt, closeTo(rf + 0.010, 1e-12));
      expect(caixaLiquido.costOfDebtWasClamped, isTrue);

      const moderada = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.279,
        taxRate: 0.34,
        equityValue: 3.6,
        debtValue: 3.2,
        interestCoverage: 1.26,
        netDebtToEbitda: 1.17,
      );
      expect(moderada.effectiveCostOfDebt, closeTo(rf + 0.018, 1e-12),
          reason: 'alavancagem de 1,17x não é crédito de pré-falência');

      const alavancada = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.20,
        taxRate: 0.34,
        equityValue: 20,
        debtValue: 80,
        interestCoverage: 2.0,
        netDebtToEbitda: 6.0,
      );
      expect(alavancada.effectiveCostOfDebt,
          closeTo(rf + CostOfCapital.maxCreditSpread, 1e-12));

      expect(caixaLiquido.effectiveCostOfDebt,
          lessThan(moderada.effectiveCostOfDebt));
      expect(moderada.effectiveCostOfDebt,
          lessThan(alavancada.effectiveCostOfDebt),
          reason: 'a ordenação de risco de crédito precisa ser monótona na '
              'alavancagem');
    });

    test('sem EBITDA positivo, o prêmio é o do pior caso', () {
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.90,
        taxRate: 0.34,
        equityValue: 100,
        debtValue: 50,
        interestCoverage: 3.0,
      );
      expect(coc.effectiveCostOfDebt, rf + CostOfCapital.maxCreditSpread);
      expect(coc.costOfDebtWasClamped, isTrue);
    });


    test('observado próximo do estimado não é declarado como substituição', () {
      // Cobertura de 3,7x pede Rf + 2,4 p.p. = 14,9%. O observado de 14,5%
      // está a 0,4 p.p. disso — dentro do passo da própria tabela de prêmios,
      // e portanto não é divergência a declarar.
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.149,
        taxRate: 0.34,
        equityValue: 100,
        debtValue: 40,
        netDebtToEbitda: 2.4,
        interestCoverage: 9.0,
      );
      expect(coc.effectiveCostOfDebt, closeTo(rf + 0.024, 1e-12));
      expect(coc.costOfDebtWasClamped, isFalse);
      expect(coc.waccWasFloored, isFalse);
    });

    test('o escudo fiscal é limitado pela capacidade de usá-lo', () {
      // Com EBIT abaixo da despesa financeira, a dedução excedente não abate
      // imposto no exercício: o escudo vale 34% × cobertura, não 34%.
      const semFolga = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.18,
        taxRate: 0.34,
        equityValue: 10,
        debtValue: 90,
        interestCoverage: 0.5,
        netDebtToEbitda: 2.0,
      );
      expect(semFolga.effectiveTaxShield, closeTo(0.34 * 0.5, 1e-12));

      const comFolga = CostOfCapital(
        capm: capmRf,
        costOfDebt: 0.18,
        taxRate: 0.34,
        equityValue: 10,
        debtValue: 90,
        interestCoverage: 4.0,
        netDebtToEbitda: 2.0,
      );
      expect(comFolga.effectiveTaxShield, 0.34);
      expect(semFolga.rawWacc, greaterThan(comFolga.rawWacc),
          reason: 'menos escudo é mais custo de capital');
    });

    test('WACC nunca desce abaixo da taxa livre de risco', () {
      // Empresa muito alavancada, com custo de dívida no piso da tabela: o
      // benefício fiscal empurraria o desconto para baixo do soberano, e a
      // perpetuidade explodiria.
      const coc = CostOfCapital(
        capm: capmRf,
        costOfDebt: rf,
        taxRate: 0.34,
        equityValue: 10,
        debtValue: 90,
        interestCoverage: 20.0,
        netDebtToEbitda: -1.0,
      );
      expect(coc.effectiveCostOfDebt, closeTo(rf + 0.010, 1e-12));
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
      // Os dois ativos têm o mesmo potencial, então a seção transversal colapsa
      // num ponto: não há escala robusta a estimar, o escore é zero e cada um
      // recebe a âncora — o CDI corrente de 14,15%. É a leitura neutra, e é o
      // que se quer: com dois pontos iguais não há ordenação a premiar.
      expect(
        alignment.expectedReturn,
        closeTo(MarketAnchors.fallback2026.currentRiskFreeRate, 1e-9),
      );
      expect(alignment.meetsGoal, isTrue);
      expect(alignment.gap, greaterThan(0));
      expect(alignment.valuationCoverage, closeTo(1.0, 1e-9));
    });

    test('o esperado ordena pelo desconto relativo, ancorado no CDI', () {
      final goal = FinancialGoal.unvalidated(
        initialContribution: Money.fromReais(10000),
        monthlyContribution: Money.fromReais(1000),
        months: 120,
        targetWealth: Money.fromReais(200000),
      );

      // Seção larga o bastante para ter escala: potenciais de −50% a +100%,
      // mediana em 0%. A carteira fica acima da mediana e recebe prêmio.
      const secao = [-0.5, -0.25, 0.0, 0.25, 1.0];

      GoalAlignment run(double fair) => EvaluateGoalAlignment.call(
            portfolio: portfolio,
            goal: goal,
            valuations: {
              Ticker.parse('PETR4'): valuationWith('PETR4', fair, 40),
              Ticker.parse('VALE3'): valuationWith('VALE3', fair, 40),
            },
            anchors: MarketAnchors.fallback2026,
            crossSection: secao,
          ).unwrap();

      const cdi = 0.1415;
      // Preço justo igual ao de mercado: potencial nulo, que é a mediana da
      // seção. Recebe exatamente a âncora.
      expect(run(40).expectedReturn, closeTo(cdi, 1e-9));
      // Descontada em relação aos pares: acima do CDI.
      expect(run(60).expectedReturn, greaterThan(cdi));
      // Esticada: abaixo do CDI, e ainda assim **não negativa** — que é o
      // ponto do estimador. Pelo caminho antigo, um preço justo de R$ 4,00
      // contra R$ 40,00 dava (0,10)^(1/3) − 1 = −53,6% ao ano, e nenhuma meta
      // era alcançável por construção.
      final esticada = run(4).expectedReturn;
      expect(esticada, lessThan(cdi));
      expect(esticada, greaterThan(0));
    });

    test('a lacuna é a distância até o exigido, e nada mais', () {
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
      // A lacuna é negativa quando o esperado não alcança o exigido, e é o
      // único número desta leitura. `yieldToCloseGap` saiu pela decisão 62:
      // somar um yield ao esperado contaria o provento duas vezes desde que
      // a âncora virou o `Ke`, que é retorno total pelo CAPM.
      expect(alignment.gap, lessThan(0));
      expect(alignment.gap / 100,
          closeTo(alignment.expectedReturn - alignment.required.annual, 1e-12));
    });

    test('meta atingida não tem lacuna', () {
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
      expect(alignment.gap, greaterThanOrEqualTo(0));
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
      expect(alignment.verdict.level, FeasibilityLevel.unrealistic);
    });
  });
}
