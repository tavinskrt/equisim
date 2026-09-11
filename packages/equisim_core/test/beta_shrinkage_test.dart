// Encolhimento do beta por precisão, e a desalavancagem de Hamada.
//
// O que estes testes travam é o comportamento nos **dois extremos**: um beta
// preciso decide sozinho, e um beta sem informação não decide nada. É o que
// separa este desenho da proposta que a medição de 10/09/2026 descartou —
// substituir a regressão pela mediana setorial moveria o `Ke` do ativo mediano
// em 2,13 p.p. sem ganho medido.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  const prior = BetaPrior(
    unleveredBySector: {'energia': 0.30, 'tecnologia': 1.10},
    unleveredUniverse: 0.46,
    dispersion: 0.53,
  );

  group('Hamada', () {
    test('desalavancar e realavancar fecha o ciclo', () {
      const de = 0.80, t = 0.25;
      final f = BetaShrinkage.leverageFactor(debtToEquity: de, taxRate: t)!;
      final u = BetaShrinkage.unlever(
        leveredBeta: 1.20,
        debtToEquity: de,
        taxRate: t,
      )!;
      expect(f, closeTo(1 + 0.75 * 0.80, 1e-12));
      expect(u * f, closeTo(1.20, 1e-12));
    });

    test('sem dívida o beta desalavancado é o próprio', () {
      expect(
        BetaShrinkage.unlever(leveredBeta: 0.90, debtToEquity: 0, taxRate: 0.3),
        closeTo(0.90, 1e-12),
      );
    });

    test('D/E é confinado no teto', () {
      // A AZUL3 tem D/E de 94,5, e Hamada supõe dívida sem risco: acima de
      // alguma alavancagem o capital próprio é opção sobre os ativos, e a
      // relação linear deixa de descrever. Sem teto, realavancar um prior por
      // 94,5 inventaria um beta de dezenas.
      final noTeto = BetaShrinkage.leverageFactor(
        debtToEquity: BetaShrinkage.maxDebtToEquity,
        taxRate: 0.25,
      );
      final muitoAcima =
          BetaShrinkage.leverageFactor(debtToEquity: 94.5, taxRate: 0.25);
      expect(muitoAcima, noTeto);
    });

    test('entrada não finita devolve nulo', () {
      expect(
        BetaShrinkage.unlever(
          leveredBeta: double.nan,
          debtToEquity: 0.5,
          taxRate: 0.3,
        ),
        isNull,
      );
    });
  });

  group('A régua da alavancagem é uma só', () {
    // O beta é desalavancado numa ponta e realavancado na outra. Se as duas
    // usarem dívidas diferentes, a ida e a volta não se cancelam: medido em
    // 11/09/2026, com a bruta na ida e a líquida na volta, o beta que voltava
    // era menor que o medido em **100 dos 127** avaliados.
    FundamentalsSnapshot comCaixa(double caixa, double divida) =>
        FundamentalsSnapshot(
          ticker: Ticker.parse('TEST3'),
          fiscalPeriodEnd: DateTime(2025, 12, 31),
          cash: caixa,
          shortTermDebt: divida * 0.2,
          longTermDebt: divida * 0.8,
          netIncome: 500,
          ebit: 800,
        );

    test('é a dívida líquida sobre o valor de mercado', () {
      final s = comCaixa(400, 1000);
      expect(s.debtToMarketEquity(2000), closeTo(600 / 2000, 1e-12));
      // E não a bruta, que daria metade a mais.
      expect(s.debtToMarketEquity(2000), isNot(closeTo(1000 / 2000, 1e-9)));
    });

    test('caixa maior que a dívida devolve alavancagem negativa', () {
      // Negativa e não nula: quem consome é que confina, e confinar aqui
      // esconderia o caixa de quem quisesse vê-lo.
      expect(comCaixa(1500, 1000).debtToMarketEquity(2000), lessThan(0));
    });

    test('sem valor de mercado utilizável, não há alavancagem', () {
      final s = comCaixa(400, 1000);
      expect(s.debtToMarketEquity(null), isNull);
      expect(s.debtToMarketEquity(0), isNull);
      expect(s.debtToMarketEquity(-100), isNull);
      expect(s.debtToMarketEquity(double.nan), isNull);
    });

    test('a ida e a volta se cancelam sob a mesma régua', () {
      final s = comCaixa(400, 1000);
      final de = s.debtToMarketEquity(2000)!;
      const tau = 0.30;
      final betaU = BetaShrinkage.unlever(
        leveredBeta: 1.40,
        debtToEquity: de,
        taxRate: tau,
      )!;
      final fator =
          BetaShrinkage.leverageFactor(debtToEquity: de, taxRate: tau)!;
      expect(betaU * fator, closeTo(1.40, 1e-12));
    });
  });

  group('A alavancagem é medida na janela do beta', () {
    // O beta é covariância de cinco anos e carrega a estrutura de capital
    // daqueles cinco. Medido em 11/09/2026 sobre 124 ativos: o fator da janela
    // difere do de hoje em mais de 10% em 50 deles e em mais de 25% em 24 — a
    // CPLE3 aparece com 386,1% de dívida sobre valor de mercado hoje contra
    // 49,8% de mediana na janela.
    FundamentalsSnapshot ex(int ano, double divida, double acoes) =>
        FundamentalsSnapshot(
          ticker: Ticker.parse('TEST3'),
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          shortTermDebt: divida * 0.3,
          longTermDebt: divida * 0.7,
          cash: 0,
          sharesOutstandingAsOf: acoes,
          // A contagem **corrente**, propositalmente diferente: usá-la mediria
          // a empresa de hoje nos exercícios de então.
          sharesOutstanding: acoes * 10,
          netIncome: 100,
        );

    PricePoint pregao(int ano, int mes, int dia, double preco) =>
        PricePoint(date: DateTime(ano, mes, dia), close: preco);

    final janela = DateRange(DateTime(2021, 1, 1), DateTime(2026, 1, 1));

    test('mediana sobre a janela, com a contagem de ações do exercício', () {
      // Preço 10 e 1.000 ações dão valor de mercado 10.000 em cada exercício;
      // a dívida varia, e a mediana é a do meio.
      final snaps = [
        ex(2022, 2000, 1000),
        ex(2023, 4000, 1000),
        ex(2024, 6000, 1000),
      ];
      final precos = [
        pregao(2022, 12, 29, 10),
        pregao(2023, 12, 28, 10),
        pregao(2024, 12, 30, 10),
      ];
      final de = MarketLeverage.overWindow(
        snapshots: snaps,
        prices: precos,
        window: janela,
      );
      expect(de, closeTo(0.40, 1e-12));
      // Com a contagem corrente — dez vezes maior — daria um décimo disso.
      expect(de, isNot(closeTo(0.04, 1e-9)));
    });

    test('exercício sem pregão próximo fica de fora', () {
      final snaps = [
        ex(2022, 2000, 1000),
        ex(2023, 4000, 1000),
        ex(2024, 6000, 1000),
      ];
      // O pregão de 2023 está a mais de vinte dias do fechamento.
      final precos = [
        pregao(2022, 12, 29, 10),
        pregao(2023, 11, 20, 10),
        pregao(2024, 12, 30, 10),
      ];
      expect(
        MarketLeverage.overWindow(
          snapshots: snaps,
          prices: precos,
          window: janela,
        ),
        isNull,
        reason: 'sobram dois exercícios, e o mínimo é três',
      );
    });

    test('menos de três exercícios na janela devolve nulo', () {
      expect(
        MarketLeverage.overWindow(
          snapshots: [ex(2023, 2000, 1000), ex(2024, 4000, 1000)],
          prices: [pregao(2023, 12, 28, 10), pregao(2024, 12, 30, 10)],
          window: janela,
        ),
        isNull,
      );
    });

    test('exercício fora da janela não entra', () {
      final snaps = [
        ex(2015, 100000, 1000), // muito antigo, e muito alavancado
        ex(2022, 2000, 1000),
        ex(2023, 4000, 1000),
        ex(2024, 6000, 1000),
      ];
      final precos = [
        pregao(2015, 12, 30, 10),
        pregao(2022, 12, 29, 10),
        pregao(2023, 12, 28, 10),
        pregao(2024, 12, 30, 10),
      ];
      expect(
        MarketLeverage.overWindow(
          snapshots: snaps,
          prices: precos,
          window: janela,
        ),
        closeTo(0.40, 1e-12),
        reason: 'o exercício de 2015 deslocaria a mediana se entrasse',
      );
    });

    test('a contagem de dias não depende de horário de verão', () {
      // `difference().inDays` entre datas locais dá 23 ou 25 horas numa
      // transição, e o truncamento erra por um dia — exatamente na margem em
      // que a escolha do pregão mais próximo é decidida.
      final snaps = [
        ex(2022, 2000, 1000),
        ex(2023, 4000, 1000),
        ex(2024, 6000, 1000),
      ];
      // Pregões a exatamente vinte dias do fechamento, dos dois lados.
      final precos = [
        pregao(2023, 1, 18, 10), // 20 dias depois de 2022-12-31
        pregao(2023, 12, 11, 10), // 20 dias antes de 2023-12-31
        pregao(2025, 1, 20, 10), // 20 dias depois de 2024-12-31
      ];
      expect(
        MarketLeverage.overWindow(
          snapshots: snaps,
          prices: precos,
          window: janela,
        ),
        closeTo(0.40, 1e-12),
        reason: 'os três entram, e a mediana é a do exercício do meio',
      );
    });

    test('sem pregão algum devolve nulo', () {
      expect(
        MarketLeverage.overWindow(
          snapshots: [ex(2022, 1, 1000), ex(2023, 1, 1000), ex(2024, 1, 1000)],
          prices: const [],
          window: janela,
        ),
        isNull,
      );
    });
  });

  group('Encolhimento por precisão', () {
    ShrunkBeta encolher({
      required double beta,
      required double? se,
      String? setor = 'energia',
      double de = 0.0,
    }) =>
        BetaShrinkage.shrink(
          leveredBeta: beta,
          standardError: se,
          prior: prior,
          sectorKey: setor,
          debtToEquity: de,
          taxRate: 0.25,
        );

    test('beta preciso decide sozinho', () {
      // Erro-padrão de 0,07 é a mediana medida no universo, com cinco anos de
      // pregão diário. O peso resultante é 0,98.
      final r = encolher(beta: 1.20, se: 0.07);
      expect(r.weight, greaterThan(0.97));
      expect(r.beta, closeTo(1.20, 0.02));
    });

    test('beta sem informação não decide nada — o caso AZUL3', () {
      // β = 109.108 com ρ = 0,11 sobre 142 pregões dá erro-padrão de 83.228.
      final r = encolher(beta: 109108.81, se: 83227.99);
      expect(r.weight, lessThan(1e-9));
      // A tolerância é 1e-4 e não 1e-9 de propósito: o peso não é zero cravado,
      // é 4e-11, e multiplicado por um beta de 109 mil deixa um resíduo de
      // 4,4e-6. É a conta fazendo exatamente o que deve — o traço do estimador
      // sem informação some, mas não por truncamento.
      expect(r.beta, closeTo(prior.unleveredBySector['energia']!, 1e-4),
          reason: 'sem dívida, o prior alavancado é o próprio desalavancado');
    });

    test('erro-padrão ausente entrega o prior inteiro', () {
      final r = encolher(beta: 2.0, se: null);
      expect(r.weight, 0.0);
      expect(r.beta, closeTo(0.30, 1e-12));
    });

    test('o peso é monótono na precisão', () {
      double peso(double se) => encolher(beta: 1.0, se: se).weight;
      var anterior = 1.1;
      for (final se in [0.05, 0.1, 0.2, 0.4, 0.8, 1.6]) {
        final w = peso(se);
        expect(w, lessThan(anterior));
        anterior = w;
      }
    });

    test('setor desconhecido cai no prior do universo', () {
      final r = encolher(beta: 3.0, se: null, setor: 'inexistente');
      expect(r.beta, closeTo(prior.unleveredUniverse, 1e-12));
      final semSetor = encolher(beta: 3.0, se: null, setor: null);
      expect(semSetor.beta, closeTo(prior.unleveredUniverse, 1e-12));
    });

    test('o prior é realavancado para a estrutura do próprio ativo', () {
      // Duas empresas do mesmo setor com alavancagens diferentes não podem
      // receber o mesmo beta: o risco do negócio é o mesmo, o do acionista não.
      final semDivida = encolher(beta: 1.0, se: null, de: 0.0);
      final comDivida = encolher(beta: 1.0, se: null, de: 1.0);
      expect(comDivida.beta, greaterThan(semDivida.beta));
      expect(comDivida.beta, closeTo(0.30 * (1 + 0.75), 1e-12));
    });

    test('o desalavancado sai do beta ENCOLHIDO, e a volta é a identidade', () {
      // É ele que liga `Ke` a `WACC`, e é por isso que sai junto em vez de
      // ficar dentro da conta.
      //
      // **Sai do encolhido e não do cru** (decisão 54): o ponto fixo
      // realavanca `unlevered` e nunca toca em `beta`, de modo que derivá-lo
      // do cru descartava o encolhimento inteiro para quem usa o caminho
      // resolvido — a maioria do universo. A decisão 40 troca precisão por
      // viés, e a troca não estava chegando ao preço.
      final r = encolher(beta: 1.75, se: 0.07, de: 1.0);
      final fator = BetaShrinkage.leverageFactor(
        debtToEquity: 1.0,
        taxRate: 0.25,
      )!;
      expect(r.unlevered, closeTo(r.beta / fator, 1e-12));
      expect(r.beta, isNot(closeTo(1.75, 1e-6)),
          reason: 'sem encolhimento este teste não distingue as duas fontes');

      // Encolher em espaço alavancado e desalavancar o resultado é idêntico a
      // encolher em espaço desalavancado.
      final betaU = 1.75 / fator;
      final priorU = 0.30; // o prior setorial de energia no fixture
      expect(r.unlevered,
          closeTo(r.weight * betaU + (1 - r.weight) * priorU, 1e-12));
    });

    test('a identidade vale também quando o prior leva tudo', () {
      // Sem erro-padrão o encolhimento entrega o prior inteiro, e o
      // desalavancado tem de acompanhar.
      final r = encolher(beta: 1.75, se: null, de: 1.0);
      final fator = BetaShrinkage.leverageFactor(
        debtToEquity: 1.0,
        taxRate: 0.25,
      )!;
      expect(r.weight, 0.0);
      expect(r.unlevered, closeTo(r.beta / fator, 1e-12));
    });
  });

  group('ResolveBetaPrior.fromObservations', () {
    BetaObservation obs(double beta, String? setor, {double de = 0.0}) =>
        BetaObservation(
          leveredBeta: beta,
          sectorKey: setor,
          debtToEquity: de,
          taxRate: 0.25,
        );

    test('mediana setorial exige pares suficientes', () {
      final p = ResolveBetaPrior.fromObservations([
        obs(0.8, 'energia'), obs(0.9, 'energia'), obs(1.0, 'energia'),
        obs(2.0, 'raro'), obs(2.2, 'raro'),
      ]);
      expect(p, isNotNull);
      expect(p!.unleveredBySector.containsKey('energia'), isTrue);
      expect(p.unleveredBySector.containsKey('raro'), isFalse,
          reason: 'dois pares não sustentam mediana de setor');
      expect(p.unleveredFor('energia'), closeTo(0.9, 1e-12));
      expect(p.unleveredFor('raro'), p.unleveredUniverse);
    });

    test('a dispersão sai dos betas alavancados', () {
      final p = ResolveBetaPrior.fromObservations([
        for (final b in [0.5, 0.7, 0.9, 1.1, 1.3]) obs(b, 'energia'),
      ])!;
      expect(p.dispersion, greaterThan(0));
      // MAD escalado de {0,5..1,3} com passo 0,2: mediana 0,9, desvios
      // {0,4; 0,2; 0; 0,2; 0,4}, MAD 0,2, escalado por 1,4826.
      expect(p.dispersion, closeTo(0.2 * 1.4826, 1e-3));
    });

    test('sem observação utilizável devolve nulo', () {
      expect(ResolveBetaPrior.fromObservations(const []), isNull);
      expect(
        ResolveBetaPrior.fromObservations([obs(double.nan, 'energia')]),
        isNull,
      );
    });

    test('setor vazio conta como ausência de setor', () {
      final p = ResolveBetaPrior.fromObservations([
        obs(0.8, ''), obs(0.9, '  '), obs(1.0, null), obs(1.1, null),
      ])!;
      expect(p.unleveredBySector, isEmpty);
      expect(p.unleveredFor(''), p.unleveredUniverse);
    });
  });
}
