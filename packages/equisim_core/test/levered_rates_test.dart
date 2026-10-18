// O ponto fixo do custo de capital, e a identidade que ele existe para fechar.
//
// A sonda de 10/09/2026 mediu que as duas rotas para o capital próprio
// divergem 4,2% quando há crescimento: a dívida cresce a `g`, o valor não, e o
// `WACC` montado com os pesos do ano zero deixa de descrever os anos seguintes.
//
// A rota (b) aceita que a alavancagem muda e reprecifica `Ke` a cada ano. O que
// prova que ela funciona é a identidade voltar a fechar **com crescimento** —
// é o que o primeiro teste verifica, e é o critério de aceite de D1.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  const spread = 0.02, tax = 0.30, premium = 0.055, betaU = 0.60;
  const rf = 0.09;
  // O `K_d` aplicado é `Rf + spread` — a classificação sintética, a mesma do
  // WACC estático (item B11). Com a taxa livre de risco constante nestes
  // testes, ele é o número único de antes.
  const kd = rf + spread;

  // **Sob a convenção de fim de ano, de propósito.** `FCFF/WACC ≡ FCFE/Ke` é
  // identidade algébrica exata quando os dois fluxos são descontados nos
  // mesmos instantes. O meio de ano desloca cada um por meio ano descontado à
  // **sua** taxa — `√(1+WACC)` de um lado, `√(1+Ke)` do outro —, e o vão que
  // sobra é o termo de spread, medido no próprio arquivo. O que estes testes
  // provam é a álgebra do ponto fixo, e ela se prova onde é exata.
  DcfAssumptions assumptions({
    required double g,
    double? rate,
    CashTiming timing = CashTiming.endOfYear,
  }) =>
      DcfAssumptions(
        projectionYears: 10,
        growthRate: g,
        perpetualGrowth: g,
        discountRate: rate ?? 0.13,
        terminalDiscountRate: rate ?? 0.13,
        returnOnCapital: 0.0,
        cashTiming: timing,
      );

  const base = 1000.0;
  Result<LeveredRates> resolver({
    required double g,
    required double debt,
    double base = base,
    CashTiming timing = CashTiming.endOfYear,
    double? cash,
  }) =>
      LeveredCostOfCapital.solve(
        baseProfit: base,
        assumptions: assumptions(g: g, timing: timing),
        netDebt: debt,
        unleveredBeta: betaU,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
        cash: cash,
      );

  group('Ponto fixo do custo de capital', () {
    test('converge, e o caminho de taxas acompanha a alavancagem', () {
      final r = resolver(g: 0.05, debt: 3000);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();

      expect(v.converged, isTrue,
          reason: 'não convergiu em ${v.iterations} iterações');
      expect(v.costOfEquity, hasLength(10));
      expect(v.wacc, hasLength(10));

      // A dívida cresce a `g` e o valor cresce a outra taxa: a participação do
      // capital próprio **muda**, e é isso que a rota (b) precisa enxergar.
      final s0 = v.equityShareAt(0)!;
      final sN = v.equityShareAt(10)!;
      expect((s0 - sN).abs(), greaterThan(0.01),
          reason: 'sem variação de alavancagem o teste não mede nada');

      // Alavancagem subindo é `Ke` subindo: é a relação de Hamada.
      if (sN < s0) {
        expect(v.costOfEquity.last, greaterThan(v.costOfEquity.first));
      } else {
        expect(v.costOfEquity.last, lessThan(v.costOfEquity.first));
      }
    });

    test('o valor que alimenta a alavancagem é o mesmo que sai no preço', () {
      // **A invariante que a convenção de caixa poderia quebrar em silêncio.**
      // O ponto fixo reconstrói o valor ano a ano por acumulação regressiva
      // para conhecer `D/E`; o preço sai do desconto direto. Se as duas contas
      // usarem convenções diferentes, `V` fica na de fim de ano e `D` não é
      // levantado — de modo que `D/E` sai inflado e o `Ke` com ele, sem que
      // nada acuse.
      for (final timing in CashTiming.values) {
        final r = resolver(g: 0.05, debt: 3000, timing: timing);
        expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
        final v = r.unwrap();

        final direct = DcfCalculator.firm(
          baseProfit: base,
          assumptions: assumptions(g: 0.05, timing: timing).copyWith(
            discountRatePath: v.wacc,
            terminalDiscountRate: v.terminalWacc,
          ),
          netDebt: 0,
          sharesOutstanding: 1,
        ).unwrap();

        expect(v.enterpriseValue.first / direct.enterpriseValue,
            closeTo(1.0, 1e-9),
            reason: 'sob ${timing.key} a acumulação regressiva não reproduz '
                'o valor descontado');
      }
    });

    test('AS DUAS ROTAS COINCIDEM COM CRESCIMENTO — o critério de D1', () {
      const g = 0.05;
      const debt = 3000.0;
      const securities = 100.0;
      final r = resolver(g: g, debt: debt).unwrap();

      final withPath = assumptions(g: g).copyWith(
        discountRatePath: v(r.wacc),
        terminalDiscountRate: r.terminalWacc,
      );

      final firm = DcfCalculator.firm(
        baseProfit: 1000,
        assumptions: withPath,
        netDebt: debt,
        sharesOutstanding: securities,
      );
      expect(firm.isOk, isTrue, reason: firm.failureOrNull?.message);

      final shareholder = DcfCalculator.equityFromFirm(
        baseProfit: 1000,
        assumptions: withPath,
        netDebt: debt,
        sharesOutstanding: securities,
        costOfDebt: kd,
        taxRate: tax,
        equityDiscountRate: r.costOfEquity.first,
        terminalEquityDiscountRate: r.terminalCostOfEquity,
        equityDiscountRatePath: v(r.costOfEquity),
      );
      expect(shareholder.isOk, isTrue, reason: shareholder.failureOrNull?.message);

      final a = firm.unwrap().fairValuePerShare;
      final b = shareholder.unwrap().fairValuePerShare;
      final divergence = (b / a - 1).abs();

      // Sob a interpolação de dois pontos esta divergência era de 4,2%.
      expect(divergence, lessThan(1e-6),
          reason: 'firma R\$ $a contra acionista R\$ $b '
              '(${(divergence * 100).toStringAsFixed(2)}%)');
    });

    test('a dívida cresce ao ritmo do lucro, e o prêmio de crédito não tem '
        'o que mudar', () {
      // O prêmio sintético sai de dívida ÷ EBITDA. Com a dívida crescendo a
      // `g_t` como o lucro projetado, a razão fica parada — e é essa a
      // premissa que torna correto um prêmio só para o caminho inteiro.
      final a = assumptions(g: 0.06);
      final r = resolver(g: 0.06, debt: 3000).unwrap();
      for (var t = 1; t < r.debt.length; t++) {
        expect(r.debt[t] / r.debt[t - 1] - 1, closeTo(a.growthAt(t), 1e-12));
      }
    });

    test('sem dívida o caminho é plano e igual ao CAPM sem alavancagem', () {
      final v = resolver(g: 0.04, debt: 0).unwrap();
      final expected = rf + betaU * premium;
      for (final k in v.costOfEquity) {
        expect(k, closeTo(expected, 1e-9));
      }
      for (final w in v.wacc) {
        expect(w, closeTo(expected, 1e-9),
            reason: 'sem dívida o WACC é o próprio Ke');
      }
      expect(v.terminalCostOfEquity, closeTo(expected, 1e-9));
    });

    test('capital próprio que desaparece vira recusa nomeada', () {
      // Dívida grande demais para o fluxo sustentar: em vez de devolver um
      // preço por papel que é resíduo de subtração, recusa.
      final r = resolver(g: 0.02, debt: 500000, base: 100);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, contains('capital próprio'));
      // **A recusa diz quando aconteceu**, e é disso que a cascata precisa
      // para separar "a estrutura não fecha" de "o ponto fixo passeou": a
      // primeira iteração usa a interpolação de dois pontos como chute, de
      // modo que falhar nela é a interpolação já estar inviável.
      expect(r.failureOrNull!.message, contains('iteração'));
      expect(r.failureOrNull!.message, contains('ano'));
    });

    test('caixa líquido não quebra o peso do capital', () {
      // `netDebt` negativo é empresa de caixa líquido, e `E + D` fica menor
      // que `E`. Sem guarda o peso divide por zero quando o caixa se aproxima
      // do próprio valor.
      final r = resolver(g: 0.03, debt: -2000);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();
      for (final w in v.wacc) {
        expect(w.isFinite, isTrue);
        expect(w, greaterThan(0));
      }
      // Sem dívida líquida positiva não há alavancagem: o fator de Hamada é
      // confinado no piso, e o `Ke` é o desalavancado puro.
      final expected = rf + betaU * premium;
      expect(v.costOfEquity.first, closeTo(expected, 1e-9));
    });

    test('caixa líquido extremo mantém as taxas finitas', () {
      // `E + D` é o valor da firma, e com lucro-base positivo ele não pode ser
      // não positivo — a guarda contra isso é rede de segurança, não caminho
      // alcançável daqui. O que se trava é que caixa de ordem de grandeza
      // maior que o próprio negócio não produz taxa infinita nem NaN.
      final r = resolver(g: 0.01, debt: -1e9, base: 100);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();
      for (final w in v.wacc) {
        expect(w.isFinite, isTrue);
        expect(w, greaterThan(0));
      }
      expect(v.terminalWacc.isFinite, isTrue);
      // Com caixa dominando, o peso do capital próprio passa de 1 — e **não é
      // confinado** (decisão 104): o peso da dívida fica negativo e o `WACC`
      // sobe acima do `Ke`, que é o mesmo tratamento do WACC estático.
      expect(v.equityShareAt(0)!, greaterThan(1.0));
      expect(v.wacc.first, greaterThan(v.costOfEquity.first),
          reason: 'com caixa líquido o ativo operacional sozinho é mais caro '
              'que a companhia inteira');
    });

    test('o custo da dívida é Rf do ano mais o prêmio, e decai com a curva', () {
      // Item B11. Antes entrava o custo **observado**, que não decai com a
      // curva: a perpetuidade herdava o juro de hoje. Agora o `K_d` de cada ano
      // é `Rf_t + spread`, como em `CostOfCapital.effectiveCostOfDebt`.
      const terminalRf = 0.06;
      final r = LeveredCostOfCapital.solve(
        baseProfit: base,
        assumptions: assumptions(g: 0.04),
        netDebt: 3000,
        unleveredBeta: betaU,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: terminalRf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
      );
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();

      // O `K_d` implícito sai da própria identidade do WACC do ano, com o peso
      // que o ponto fixo fixou: é o número que a conta usou, e não um número
      // remontado por outro caminho.
      double impliedKd(double wacc, double ke, double equityWeight) =>
          (wacc - ke * equityWeight) / ((1 - equityWeight) * (1 - tax));

      expect(
          impliedKd(v.wacc.first, v.costOfEquity.first, v.equityShareAt(0)!),
          closeTo(rf + spread, 1e-9));
      expect(
          impliedKd(v.terminalWacc, v.terminalCostOfEquity,
              v.equityShareAt(10)!),
          closeTo(terminalRf + spread, 1e-9),
          reason: 'o prêmio de crédito é da empresa; a taxa base é do ano');
    });

    test('exige beta desalavancado, e recusa sem ele', () {
      final r = LeveredCostOfCapital.solve(
        baseProfit: 1000,
        assumptions: assumptions(g: 0.04),
        netDebt: 1000,
        unleveredBeta: double.nan,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, contains('desalavancado'));
    });

    test('caminho de taxa livre de risco com tamanho errado é recusado', () {
      final r = LeveredCostOfCapital.solve(
        baseProfit: 1000,
        assumptions: assumptions(g: 0.04),
        netDebt: 1000,
        unleveredBeta: betaU,
        riskFreePath: List<double>.filled(3, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
      );
      expect(r.isErr, isTrue);
    });
  });

  group('Caminho explícito de desconto no DCF', () {
    test('caminho de tamanho errado é recusado', () {
      final r = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: const DcfAssumptions(
          projectionYears: 10,
          growthRate: 0.04,
          perpetualGrowth: 0.04,
          discountRate: 0.13,
          returnOnCapital: 0.0,
          discountRatePath: [0.13, 0.13, 0.13],
        ),
        netDebt: 0,
        sharesOutstanding: 1,
      );
      expect(r.isErr, isTrue);
    });

    test('caminho constante reproduz a taxa única', () {
      const a = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.04,
        perpetualGrowth: 0.04,
        discountRate: 0.13,
        returnOnCapital: 0.0,
      );
      final withoutPath =
          DcfCalculator.firm(baseProfit: 100, assumptions: a, netDebt: 0, sharesOutstanding: 1);
      final withPath = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: a.copyWith(discountRatePath: List<double>.filled(10, 0.13)),
        netDebt: 0,
        sharesOutstanding: 1,
      );
      expect(
        withPath.unwrap().fairValuePerShare,
        closeTo(withoutPath.unwrap().fairValuePerShare, 1e-12),
      );
    });
  });

  group('O ponto fixo não depende de onde começa', () {
    // Item B18, decisão 110. A recusa da decisão 45 saía da interpolação de
    // dois pontos — o recuo que a decisão 41 substituiu —, e não do ponto
    // fixo: os 14 ativos que saíram do aplicativo em 20/09/2026 foram
    // recusados todos na primeira iteração. Agora o ponto fixo é tentado de
    // duas partidas, e um ponto fixo é um ponto fixo.
    Result<LeveredRates> withGuess(double rate, {double debt = 3000}) =>
        LeveredCostOfCapital.solve(
          baseProfit: base,
          assumptions: DcfAssumptions(
            projectionYears: 10,
            growthRate: 0.05,
            perpetualGrowth: 0.05,
            discountRate: rate,
            terminalDiscountRate: rate,
            returnOnCapital: 0.0,
            cashTiming: CashTiming.endOfYear,
          ),
          netDebt: debt,
          unleveredBeta: betaU,
          riskFreePath: List<double>.filled(10, rf),
          terminalRiskFree: rf,
          marketPremium: premium,
          creditSpread: spread,
          taxRate: tax,
        );

    test('dois chutes bem diferentes chegam ao mesmo lugar', () {
      // O chute só semeia: dentro do laço o caminho é reescrito. Se a resposta
      // dependesse dele, ela seria do chute.
      final low = withGuess(0.10).unwrap();
      final high = withGuess(0.30).unwrap();
      expect(low.converged && high.converged, isTrue);
      expect((high.equity.first / low.equity.first - 1).abs(),
          lessThan(LeveredCostOfCapital.startIndependence),
          reason: 'o mesmo ponto fixo, por caminhos diferentes');
      expect(high.terminalWacc, closeTo(low.terminalWacc, 1e-6));
    });

    test('chute que mata o capital próprio não decide a recusa', () {
      // Com o chute alto o capital próprio some no ano zero da primeira
      // iteração; a partida desalavancada fecha, e é ela que vale.
      final warnings = <String>[];
      final r = LeveredCostOfCapital.solve(
        baseProfit: base,
        assumptions: const DcfAssumptions(
          projectionYears: 10,
          growthRate: 0.05,
          perpetualGrowth: 0.05,
          // Um chute absurdamente caro: a interpolação não sustenta a dívida.
          discountRate: 0.90,
          terminalDiscountRate: 0.90,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.endOfYear,
        ),
        netDebt: 6000,
        unleveredBeta: 0.30,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
        warnings: warnings,
      );
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      expect(warnings.any((a) => a.contains('não fecha a partir do caminho sem realavancagem')),
          isTrue,
          reason: 'quando as duas partidas discordam sobre existir solução, a '
              'avaliação precisa dizer de onde veio a que valeu');
    });

    test('quando nenhuma das duas fecha, a recusa diz que é do método', () {
      final r = LeveredCostOfCapital.solve(
        baseProfit: 1.0,
        assumptions: const DcfAssumptions(
          projectionYears: 10,
          growthRate: 0.05,
          perpetualGrowth: 0.05,
          discountRate: 0.13,
          terminalDiscountRate: 0.13,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.endOfYear,
        ),
        // Dívida de ordem de grandeza acima do que o fluxo sustenta.
        netDebt: 1e9,
        unleveredBeta: betaU,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, contains('nenhuma das duas partidas'));
      expect(r.failureOrNull!.message, contains('e não do chute'));
    });
  });

  group('Ponto fixo pelo lado do acionista', () {
    // A via do acionista avalia sozinha 33 dos 120 em produção, e em nenhum
    // deles a via da firma produz caminho de taxas para emprestar: ou o `Ke`
    // sai dos fluxos dela mesma, ou continua supondo a alavancagem de hoje
    // perene. Decisão 46.
    Result<LeveredRates> resolveShareholder({
      required double g,
      required double debtPerShare,
      double eps = 1.0,
      double rate = 0.13,
    }) =>
        LeveredCostOfCapital.solveEquity(
          baseProfit: eps,
          assumptions: assumptions(g: g, rate: rate),
          netDebtPerShare: debtPerShare,
          unleveredBeta: betaU,
          riskFreePath: List<double>.filled(10, rf),
          terminalRiskFree: rf,
          marketPremium: premium,
          taxRate: tax,
        );

    test('sem dívida, o caminho é plano e igual ao CAPM desalavancado', () {
      final r = resolveShareholder(g: 0.04, debtPerShare: 0);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();
      expect(v.converged, isTrue);
      final expected = rf + betaU * premium;
      for (final ke in v.costOfEquity) {
        expect(ke, closeTo(expected, 1e-12));
      }
      expect(v.terminalCostOfEquity, closeTo(expected, 1e-12));
      // Não há custo médio nesta via: `wacc` repete `Ke`, por contrato.
      expect(v.wacc, v.costOfEquity);
      expect(v.terminalWacc, v.terminalCostOfEquity);
    });

    test('mais dívida por papel eleva o Ke, e é monótono', () {
      double? keOf(double d) {
        final r = resolveShareholder(g: 0.04, debtPerShare: d);
        return r.isOk ? r.unwrap().costOfEquity.first : null;
      }

      double? previous;
      var evaluated = 0;
      for (var step = 0; step <= 8; step++) {
        final ke = keOf(step * 1.5);
        if (ke == null) continue;
        evaluated++;
        if (previous != null) {
          expect(ke, greaterThanOrEqualTo(previous - 1e-12),
              reason: 'alavancar mais não pode baratear o capital próprio');
        }
        previous = ke;
      }
      expect(evaluated, greaterThan(5));
      expect(previous, greaterThan(rf + betaU * premium),
          reason: 'no topo da varredura a realavancagem tem de ter mordido');
    });

    test('a escala não muda nada: D/E é razão', () {
      // Dobrar lucro e dívida por papel é a mesma empresa com metade das ações.
      final a = resolveShareholder(g: 0.04, eps: 1.0, debtPerShare: 4.0);
      final b = resolveShareholder(g: 0.04, eps: 3.0, debtPerShare: 12.0);
      expect(a.isOk && b.isOk, isTrue);
      for (var t = 0; t < 10; t++) {
        expect(b.unwrap().costOfEquity[t],
            closeTo(a.unwrap().costOfEquity[t], 1e-12));
      }
      expect(b.unwrap().terminalCostOfEquity,
          closeTo(a.unwrap().terminalCostOfEquity, 1e-12));
    });

    test('a alavancagem se move ao longo da projeção, e o Ke com ela', () {
      final r = resolveShareholder(g: 0.06, debtPerShare: 6.0);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();
      expect(v.converged, isTrue);
      final s0 = v.equityShareAt(0)!;
      final sN = v.equityShareAt(10)!;
      expect((s0 - sN).abs(), greaterThan(0.005),
          reason: 'sem variação de alavancagem o teste não mede nada');
      expect((v.costOfEquity.first - v.costOfEquity.last).abs(),
          greaterThan(1e-6),
          reason: 'a taxa tem de acompanhar a alavancagem que se move');
    });

    test('valor terminal divergente vira recusa datada', () {
      // **Só com vantagem residual declarada.** No terminal neutro o valor é
      // `lucro/r` e não depende do crescimento perpétuo — de propósito, pela
      // decisão 25 —, de modo que a divergência nem existe ali. Com `moat` a
      // perpetuidade volta à forma de Gordon, e aí a taxa de equilíbrio tem de
      // superar `g`.
      final r = LeveredCostOfCapital.solveEquity(
        baseProfit: 1.0,
        assumptions: assumptions(g: 0.14, rate: 0.10)
            .copyWith(terminalReturnOnCapital: 0.20),
        netDebtPerShare: 1.0,
        unleveredBeta: betaU,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        taxRate: tax,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, contains('iteração'));
      expect(r.failureOrNull!.message, contains('crescimento perpétuo'));
    });

    test('participação sem sentido é nula, e não NaN', () {
      // Pelo lado do acionista `enterpriseValue` é `E + D`, e com caixa
      // líquido maior que o próprio negócio ele fica não positivo: a razão
      // deixa de ter significado. O sentinela de ponto flutuante atravessava a
      // formatação e chegava ao aviso do usuário como `NaN%` — a auditoria
      // pegou, e o nulo obriga quem lê a decidir o que dizer.
      final r = resolveShareholder(g: 0.02, debtPerShare: -1e6);
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();
      expect(v.enterpriseValue.first, lessThanOrEqualTo(0),
          reason: 'o fixture precisa produzir E + D não positivo para medir o '
              'que promete');
      expect(v.equityShareAt(0), isNull);
      // Fora do intervalo também é nulo, e não NaN.
      expect(v.equityShareAt(-1), isNull);
      expect(v.equityShareAt(999), isNull);
    });

    test('a dívida não cresce: o crescimento já sai do lucro retido', () {
      // Item B11. Esta via desconta `lucro × (1 − b)`, isto é, o crescimento já
      // é financiado por retenção. Fazer a dívida crescer a `g` junto
      // financiaria o mesmo crescimento duas vezes, e o acionista pagaria o
      // `Ke` mais alto sem receber nada pela dívida nova.
      final r = LeveredCostOfCapital.solveEquity(
        baseProfit: 1.0,
        assumptions: assumptions(g: 0.08),
        netDebtPerShare: 3.0,
        unleveredBeta: betaU,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        taxRate: tax,
      );
      expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
      final v = r.unwrap();

      expect(v.debt, everyElement(closeTo(3.0, 1e-12)),
          reason: 'a dívida fica parada em termos nominais');
      final debtToEquity0 = v.debt.first / v.equity.first;
      final debtToEquityN = v.debt.last / v.equity.last;
      expect(debtToEquityN, lessThan(debtToEquity0),
          reason: 'o capital próprio cresce pelo lucro retido e a dívida não: '
              'a alavancagem cai');
      expect(v.costOfEquity.last, lessThan(v.costOfEquity.first),
          reason: 'desalavancagem de verdade barateia o capital próprio');
    });

    test('sem beta desalavancado, recusa', () {
      final r = LeveredCostOfCapital.solveEquity(
        baseProfit: 1.0,
        assumptions: assumptions(g: 0.04),
        netDebtPerShare: 2.0,
        unleveredBeta: double.nan,
        riskFreePath: List<double>.filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        taxRate: tax,
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, contains('desalavancado'));
    });
  });

  group('O caixa da via alavancada rende a taxa livre de risco', () {
    // Lente `metodo`, 21/09/2026. A via da firma projetava a dívida
    // **líquida** e remunerava a perna inteira ao custo de empréstimo. Quem
    // tem caixa via a metade que rende `R_f` ser creditada com prêmio de
    // crédito — e o WACC saía baixo demais. A separação não muda os pesos:
    // as duas metades crescem com o mesmo fator, e a diferença delas é a
    // mesma série líquida de antes.
    test('a mesma dívida líquida, com caixa conhecido, custa mais', () {
      final without = resolver(g: 0.05, debt: 3000);
      final withInput = resolver(g: 0.05, debt: 3000, cash: 2000);
      expect(without.isOk, isTrue, reason: without.failureOrNull?.message);
      expect(withInput.isOk, isTrue, reason: withInput.failureOrNull?.message);
      final a = without.unwrap();
      final b = withInput.unwrap();
      for (var t = 0; t < a.wacc.length; t++) {
        expect(b.wacc[t], greaterThan(a.wacc[t]),
            reason: 'ano ${t + 1}: o caixa deixa de render prêmio de crédito');
      }
      expect(b.terminalWacc, greaterThan(a.terminalWacc));
      expect(b.equity.first, lessThan(a.equity.first),
          reason: 'taxa maior, valor menor');
    });

    test('a dívida projetada é a mesma: o que muda é a taxa', () {
      final without = resolver(g: 0.05, debt: 3000).unwrap();
      final withInput = resolver(g: 0.05, debt: 3000, cash: 2000).unwrap();
      for (var t = 0; t < without.debt.length; t++) {
        expect(withInput.debt[t], closeTo(without.debt[t], 1e-9));
      }
    });

    test('o WACC do ano 1 fecha na forma de três pernas', () {
      final r = resolver(g: 0.05, debt: 3000, cash: 2000).unwrap();
      const cash = 2000.0;
      final v0 = r.equity.first + r.debt.first;
      final equityWeight = r.equity.first / v0;
      final wGross = (r.debt.first + cash) / v0;
      final wCash = cash / v0;
      final interest = (rf + spread) * (1 - tax);
      final income = rf * (1 - tax);
      expect(
        r.wacc.first,
        closeTo(
          r.costOfEquity.first * equityWeight + interest * wGross - income * wCash,
          1e-9,
        ),
      );
      // E a soma dos dois pesos da perna é a participação da líquida: a
      // separação redistribui a mesma perna entre duas taxas.
      expect(wGross - wCash, closeTo(1 - equityWeight, 1e-12));
    });

    test('caixa zero é a forma anterior, bit a bit', () {
      final without = resolver(g: 0.05, debt: 3000).unwrap();
      final withInput = resolver(g: 0.05, debt: 3000, cash: 0).unwrap();
      for (var t = 0; t < without.wacc.length; t++) {
        expect(withInput.wacc[t], closeTo(without.wacc[t], 1e-12));
      }
      expect(withInput.terminalWacc, closeTo(without.terminalWacc, 1e-12));
    });
  });
}

/// Cópia mutável para passar ao `copyWith`, que guarda a lista como está.
List<double> v(List<double> x) => List<double>.from(x);
