import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Testes das portas e guardas introduzidas pela decisão 25.
///
/// Cada caso reproduz a **forma** de um ativo real da calibragem, com os
/// números que motivaram a regra. É o que impede que um limiar volte a ser
/// ajustado sem que o motivo original seja reencontrado.
void main() {
  final ticker = Ticker.parse('TEST3');

  FundamentalsSnapshot exercicio(
    int ano, {
    double? vpa,
    double? acoes,
    double? lucro,
    double? nopat,
    double dividaCurta = 0,
    double dividaLonga = 0,
    double caixa = 0,
  }) =>
      FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(ano, 12, 31),
        bookValuePerShare: vpa,
        sharesOutstandingAsOf: acoes,
        sharesOutstanding: acoes,
        netIncome: lucro,
        nopat: nopat,
        shortTermDebt: dividaCurta,
        longTermDebt: dividaLonga,
        cash: caixa,
      );

  group('Inference — primitivas conferidas contra tabela', () {
    test('quantil da t de Student bate com a tabela publicada', () {
      expect(Inference.studentT(0.975, 14), closeTo(2.1448, 5e-4));
      expect(Inference.studentT(0.975, 6), closeTo(2.4469, 5e-4));
      expect(Inference.studentT(0.95, 10), closeTo(1.8125, 5e-4));
      expect(Inference.studentT(0.995, 30), closeTo(2.7500, 5e-4));
    });

    test('R² crítico depende de n, e é isso que condena o limiar fixo', () {
      // Com n = 8 o corte correto é 0,50; com n = 16, 0,25. Um limiar único é
      // simultaneamente laxo numa ponta e estrito na outra.
      expect(Inference.criticalR2(8, 0.05), closeTo(0.499, 1e-3));
      expect(Inference.criticalR2(16, 0.05), closeTo(0.247, 1e-3));
      expect(Inference.criticalR2(8, 0.05),
          greaterThan(Inference.criticalR2(16, 0.05)));
    });

    test('MAD escalado resiste a contaminação que derruba o desvio-padrão', () {
      // Mediana 3, MAD 1 → 1,4826. O ponto em 100 não move a escala robusta.
      expect(Inference.scaledMad([1, 2, 3, 4, 100]), closeTo(1.4826, 1e-4));
    });
  });

  group('Base de capital', () {
    test('patrimônio usa a contagem de ações do exercício, não a corrente', () {
      // Forma do BBAS3: bonificação dobra as ações em 2024. Com a contagem
      // corrente aplicada a todos os anos, a série cairia pela metade num
      // degrau que é troca de denominador, não de lucro.
      final antes = exercicio(2023, vpa: 56.9, acoes: 2865417000, lucro: 33.1e9);
      final depois = exercicio(2024, vpa: 32.1, acoes: 5730834000, lucro: 29.2e9);
      expect(antes.equityBookValue! / 1e9, closeTo(163.1, 0.5));
      expect(depois.equityBookValue! / 1e9, closeTo(184.0, 0.5));
      expect(depois.equityBookValue, greaterThan(antes.equityBookValue!),
          reason: 'o patrimônio cresceu; foi o valor por ação que se dividiu');
    });

    test('capital investido soma dívida e subtrai caixa', () {
      final e = exercicio(2025,
          vpa: 10,
          acoes: 1000,
          nopat: 900,
          dividaCurta: 2000,
          dividaLonga: 3000,
          caixa: 1500);
      expect(e.investedCapital, closeTo(10 * 1000 + 5000 - 1500, 1e-9));
    });

    test('limpeza é por vizinhança: crescimento real de ordens de magnitude '
        'sobrevive', () {
      // Forma da PRIO3, que multiplicou a base por trinta em oito anos — 1,53x
      // ao ano. Um corte contra a mediana global apagaria os exercícios
      // recentes, os únicos que descrevem a empresa de hoje.
      var vpa = 1.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2018; ano <= 2025; ano++) {
        pontos.add(exercicio(ano, vpa: vpa, acoes: 1000, lucro: vpa * 100));
        vpa *= 1.526;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      expect(serie.length, 8, reason: 'nenhum exercício legítimo foi cortado');
    });

    test('limpeza remove falha pontual da fonte', () {
      // Forma da ABEV3 em 2012: bookValue de 0,062 contra 2,81 no ano seguinte.
      final serie = CapitalSeries.build([
        exercicio(2020, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2021, vpa: 0.05, acoes: 1000, lucro: 100),
        exercicio(2022, vpa: 11, acoes: 1000, lucro: 100),
        exercicio(2023, vpa: 12, acoes: 1000, lucro: 100),
      ], ValuationLane.shareholder);
      expect(serie.length, 3);
      expect(serie.points.any((p) => p.year == 2021), isFalse);
    });
  });

  group('Conciliação da contagem de ações', () {
    // Os números são os do MILS3 no exercício de 2025, medidos no cache de
    // produção em 07/09/2026. A contagem corrente vinha 4.868x menor que a do
    // exercício, e a ponte de equity devolvia R$ 37.708,72 contra R$ 15,79 de
    // mercado na validação fora da amostra.
    FundamentalsSnapshot mils({double? lpa}) => FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(2025, 12, 31),
          netIncome: 301263000,
          earningsPerShare: lpa,
          sharesOutstanding: 48172,
          sharesOutstandingAsOf: 234178210,
          bookValuePerShare: 6.7376337,
        );

    test('o lucro por ação publicado arbitra a favor da contagem do exercício',
        () {
      // N implícito = 301.263.000 / 1,2865 = 234,2 mi, que é a do exercício.
      final f = mils(lpa: 1.2865);
      expect(f.reconciledShares, 234178210);
    });

    test('sem árbitro, prevalece a contagem que reconstrói o patrimônio', () {
      expect(mils().reconciledShares, 234178210);
    });

    test('o árbitro pode confirmar a contagem corrente, e então ela vence', () {
      // Mesmo par de candidatas, mas agora o LPA aponta para a corrente:
      // 301.263.000 / 6254,0 = 48.172.
      final f = mils(lpa: 6254.0);
      expect(f.reconciledShares, 48172);
    });

    test('divergência das duas contagens é sinalizada', () {
      expect(mils().sharesDisagree, isTrue);
    });

    test('contagens concordantes não geram sinal nem escolha', () {
      final f = FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        sharesOutstanding: 100000000,
        sharesOutstandingAsOf: 98000000,
      );
      expect(f.sharesDisagree, isFalse);
      expect(f.reconciledShares, 98000000);
    });

    test('uma contagem só é usada como está', () {
      final f = FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        sharesOutstanding: 48172,
      );
      expect(f.reconciledShares, 48172);
      expect(f.sharesDisagree, isFalse);
    });

    test('LPA nulo ou zerado não é árbitro', () {
      expect(mils(lpa: 0).reconciledShares, 234178210);
    });
  });

  group('Guarda 2 — capital externo', () {
    test('expansão por lucro retido é orgânica', () {
      // Patrimônio cresce exatamente pelo lucro: nada veio de fora.
      var pl = 1000.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2016; ano <= 2025; ano++) {
        pontos.add(exercicio(ano, vpa: pl / 1000, acoes: 1000, lucro: 100));
        pl += 100;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final phi = GrowthGuards.externalCapitalRatio(serie);
      expect(phi, isNotNull);
      expect(phi!, lessThan(0.05));
    });

    test('salto de patrimônio acima do lucro acusa capital externo', () {
      // Forma da RENT3 na incorporação: o patrimônio salta muito além do que a
      // empresa lucrou no ano.
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2016; ano <= 2025; ano++) {
        if (ano == 2022) pl += 8000;
        pontos.add(exercicio(ano, vpa: pl / 1000, acoes: 1000, lucro: 100));
        pl += 100;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final phi = GrowthGuards.externalCapitalRatio(serie);
      expect(phi, isNotNull);
      expect(phi!, greaterThan(ValuationParameters.maxExternalCapital));
    });
  });

  group('Saída 2 — identificação do crescimento', () {
    List<FundamentalsSnapshot> comCrescimento(double g, {double ruido = 0}) {
      var pl = 1000.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2014; ano <= 2025; ano++) {
        final desvio = ruido == 0 ? 1.0 : (ano.isEven ? 1 + ruido : 1 - ruido);
        pontos.add(exercicio(ano,
            vpa: pl * desvio / 1000, acoes: 1000, lucro: pl * 0.15));
        pl *= 1 + g;
      }
      return pontos;
    }

    test('série limpa devolve o crescimento pela mediana das variações', () {
      final serie =
          CapitalSeries.build(comCrescimento(0.08), ValuationLane.shareholder);
      final d = GrowthGuards.dispersion(serie);
      expect(d, isNotNull);
      expect(d!.isIdentified, isTrue);
      expect(d.medianGrowth, closeTo(0.08, 1e-6));
    });

    test('estimador impreciso é barrado antes do teste de discordância', () {
      // Forma da PRIO3: os dois estimadores concordam (D pequeno) porque ambos
      // são ruins. Sem o piso de precisão, o ativo mais imprecisamente medido
      // da amostra receberia o maior crescimento.
      final serie = CapitalSeries.build(
          comCrescimento(0.25, ruido: 0.45), ValuationLane.shareholder);
      final d = GrowthGuards.dispersion(serie);
      expect(d, isNotNull);
      expect(d!.stdError, greaterThan(ValuationParameters.maxGrowthStdError));
      expect(d.isIdentified, isFalse);
      expect(d.failure, contains('impreciso'));
    });

    test('financiabilidade discrimina por retorno, não por setor', () {
      // Retorno alto torna a inflação barata de financiar; retorno baixo, não.
      // É a forma de BBSE3 contra VIVT3.
      expect(
        GrowthGuards.anchorIsFundable(
            inflation: 0.05, cycleReturn: 0.675, observedRetention: 0.113),
        isTrue,
        reason: 'com retorno de 67,5%, crescer à inflação custa 7,4% de '
            'retenção contra 11,3% observados',
      );
      expect(
        GrowthGuards.anchorIsFundable(
            inflation: 0.05, cycleReturn: 0.078, observedRetention: 0.06),
        isFalse,
        reason: 'com retorno de 7,8%, exigiria reter 64% contra 6% observados',
      );
    });
  });

  group('Porta 0 — elegibilidade', () {
    test('histórico curto reprova', () {
      final v = EligibilityGate.assess(snapshots: [
        for (var ano = 2021; ano <= 2025; ano++)
          exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
      ]);
      expect(v.isEligible, isFalse);
      expect(v.reasons, contains(IneligibilityReason.shortHistory));
    });

    test('patrimônio negativo em dois exercícios consecutivos reprova', () {
      final v = EligibilityGate.assess(snapshots: [
        for (var ano = 2016; ano <= 2023; ano++)
          exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2024, vpa: -1, acoes: 1000, lucro: -50),
        exercicio(2025, vpa: -2, acoes: 1000, lucro: -50),
      ]);
      expect(v.isEligible, isFalse);
      expect(v.reasons, contains(IneligibilityReason.insolvent));
    });

    test('um exercício isolado de patrimônio negativo não reprova', () {
      final v = EligibilityGate.assess(snapshots: [
        for (var ano = 2016; ano <= 2023; ano++)
          exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2024, vpa: -1, acoes: 1000, lucro: -50),
        exercicio(2025, vpa: 9, acoes: 1000, lucro: 80),
      ]);
      expect(v.reasons, isNot(contains(IneligibilityReason.insolvent)));
    });

    test('recuperação judicial reprova, e vem de fora', () {
      final v = EligibilityGate.assess(
        snapshots: [
          for (var ano = 2016; ano <= 2025; ano++)
            exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        ],
        isDistressed: true,
      );
      expect(v.isEligible, isFalse);
      expect(v.reasons, contains(IneligibilityReason.distressed));
    });

    test('série sem volume omite o teste de liquidez em vez de reprovar', () {
      final v = EligibilityGate.assess(
        snapshots: [
          for (var ano = 2016; ano <= 2025; ano++)
            exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        ],
        prices: PriceSeries(
          ticker: ticker,
          points: [
            for (var i = 0; i < 100; i++)
              PricePoint(date: DateTime(2026, 1, 1).add(Duration(days: i)),
                  close: 10),
          ],
        ),
      );
      expect(v.averageDailyTradedValue, isNull);
      expect(v.reasons, isNot(contains(IneligibilityReason.illiquid)));
    });

    test('volume financeiro abaixo do corte reprova', () {
      final v = EligibilityGate.assess(
        snapshots: [
          for (var ano = 2016; ano <= 2025; ano++)
            exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        ],
        prices: PriceSeries(
          ticker: ticker,
          points: [
            for (var i = 0; i < 100; i++)
              PricePoint(
                  date: DateTime(2026, 1, 1).add(Duration(days: i)),
                  close: 10,
                  volume: 1000),
          ],
        ),
      );
      expect(v.averageDailyTradedValue, closeTo(10000, 1e-6));
      expect(v.reasons, contains(IneligibilityReason.illiquid));
    });
  });

  group('Estrutura a termo do desconto', () {
    const a = DcfAssumptions(
      projectionYears: 10,
      growthRate: 0.10,
      perpetualGrowth: 0.05,
      discountRate: 0.16,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.20,
    );

    test('a taxa parte da corrente e chega à de equilíbrio', () {
      expect(a.discountRateAt(1), closeTo(0.16, 1e-12));
      expect(a.discountRateAt(10), closeTo(0.12, 1e-12));
    });

    test('o decaimento é linear no passo da janela', () {
      // No ano 6 percorreram-se 5/9 da janela.
      expect(a.discountRateAt(6), closeTo(0.16 - 0.04 * 5 / 9, 1e-12));
    });

    test('o retorno converge para o custo de capital do próprio ano', () {
      expect(a.returnOnCapitalAt(1), closeTo(0.20, 1e-12));
      expect(a.returnOnCapitalAt(10), closeTo(a.discountRateAt(10), 1e-12));
    });

    test('o último ano explícito encontra a retenção do estado estacionário',
        () {
      // b_N = g_inf / r_inf é exatamente a retenção que o terminal supõe:
      // a projeção deixa de saltar para a perpetuidade.
      expect(a.retentionAt(10), closeTo(0.05 / 0.12, 1e-12));
    });

    test('o fator de desconto acumula as taxas, não eleva uma só a t', () {
      final r = DcfCalculator.shareholder(
        baseProfit: 100,
        assumptions: const DcfAssumptions(
          projectionYears: 2,
          growthRate: 0.0,
          perpetualGrowth: 0.0,
          discountRate: 0.20,
          terminalDiscountRate: 0.10,
        ),
      );
      final o = r.unwrap();
      // Ano 1 a 20%, ano 2 a 10%: fatores 1,20 e 1,20 x 1,10 = 1,32.
      expect(o.discountedFlows[0], closeTo(100 / 1.20, 1e-9));
      expect(o.discountedFlows[1], closeTo(100 / 1.32, 1e-9));
    });

    test('sem taxa terminal declarada, o desconto é plano', () {
      const plana = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.10,
        perpetualGrowth: 0.05,
        discountRate: 0.16,
      );
      expect(plana.terminalDiscountRate, 0.16);
      expect(plana.discountRateAt(7), closeTo(0.16, 1e-12));
    });
  });

  group('Vantagem competitiva residual', () {
    double? moat({
      double? retorno = 0.30,
      double desconto = 0.12,
      double? phi = 0.10,
      int exercicios = 14,
    }) =>
        GrowthGuards.residualMoatReturn(
          cycleReturn: retorno,
          terminalDiscountRate: desconto,
          externalCapitalRatio: phi,
          periods: exercicios,
        );

    test('as três condições cumpridas preservam 30% do excedente', () {
      // 0,12 + 0,30 x (0,30 - 0,12) = 0,174
      expect(moat(), closeTo(0.174, 1e-12));
    });

    test('crescimento inorgânico reprova', () {
      expect(moat(phi: 0.40), isNull);
    });

    test('Phi não medido reprova — ausência não é aprovação', () {
      expect(moat(phi: null), isNull);
    });

    test('retorno abaixo de duas vezes o custo de capital reprova', () {
      expect(moat(retorno: 0.23), isNull);
      expect(moat(retorno: 0.24), isNotNull);
    });

    test('histórico curto reprova', () {
      expect(moat(exercicios: 11), isNull);
      expect(moat(exercicios: 12), isNotNull);
    });

    test('sem retorno do ciclo não há vantagem a preservar', () {
      expect(moat(retorno: null), isNull);
    });

    test('o terminal com moat supera o do estado estacionário', () {
      const base = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.08,
        perpetualGrowth: 0.05,
        discountRate: 0.14,
        terminalDiscountRate: 0.12,
        returnOnCapital: 0.30,
      );
      final neutro =
          DcfCalculator.terminalValue(finalProfit: 100, assumptions: base)
              .unwrap();
      final comMoat = DcfCalculator.terminalValue(
        finalProfit: 100,
        assumptions: base.copyWith(terminalReturnOnCapital: 0.174),
      ).unwrap();
      // Neutro: 105 / 0,12 = 875.
      expect(neutro, closeTo(875.0, 1e-9));
      // Moat: 105 x (1 - 0,05/0,174) / (0,12 - 0,05) = 1039,3...
      expect(comMoat, closeTo(105 * (1 - 0.05 / 0.174) / 0.07, 1e-9));
      expect(comMoat, greaterThan(neutro));
    });

    test('o terminal com moat exige folga entre desconto e crescimento', () {
      const apertado = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.08,
        perpetualGrowth: 0.119,
        discountRate: 0.14,
        terminalDiscountRate: 0.12,
        returnOnCapital: 0.30,
        terminalReturnOnCapital: 0.174,
      );
      final r =
          DcfCalculator.terminalValue(finalProfit: 100, assumptions: apertado);
      expect(r.isErr, isTrue);
    });
  });

  group('Constantes que carregam decisão', () {
    test('horizonte de convergência é de 36 meses', () {
      // Com 12 a anualização vira a identidade e o upside bruto passa a ser
      // lido como retorno anual — o defeito D1 da decisão 25.
      expect(ExpectedReturn.defaultHorizonMonths, 36);
      final r = ExpectedReturn.annualizedFromUpside(1.0);
      expect(r, closeTo(0.2599, 1e-4),
          reason: '(1 + 1,00)^(1/3) − 1, e não os 100% da identidade');
    });

    test('teto nominal compõe crescimento real medido com inflação', () {
      const a = MarketAnchors(
        riskFreeCagr: 0.10,
        marketCagr: 0.12,
        inflationCagr: 0.05,
        realEconomyGrowth: 0.0145,
        observedYears: 10,
      );
      expect(a.nominalEconomyGrowth, closeTo(0.0652, 1e-4));
    });

    test('projeção explícita é de dez anos', () {
      const a = DcfAssumptions(
        growthRate: 0.10,
        perpetualGrowth: 0.04,
        discountRate: 0.12,
      );
      expect(a.projectionYears, 10);
    });
  });
}
