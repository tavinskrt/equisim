// A identidade entre as duas rotas para o capital próprio.
//
// `DcfCalculator.equityFromFirm` não é uma segunda opinião sobre o valor: é a
// mesma avaliação por um caminho que não passa pela subtração `EV − D`. O que
// prova isso é a identidade, e é o que estes testes verificam:
//
// ```
// FCFE_{N+1} = FCFF_{N+1} − D·[Kd(1−τ) − g] = E·(Ke − g)
// ```
//
// Ela exige que o `WACC` tenha sido montado com os pesos `E/V` e `D/V` **do
// próprio modelo**. Aqui isso é construído de propósito; em produção o peso do
// equity vem do valor de mercado, e o resíduo daí é medido em
// `docs/validacao/`.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Identidade FCFF/WACC ≡ FCFE/Ke sob alavancagem constante', () {
    /// Monta o par consistente: dado `E`, `D`, `Ke` e `Kd`, devolve o `WACC`
    /// que a estrutura de capital implica. É a única forma de a identidade
    /// poder valer — com peso de mercado ela não vale, e é esse o achado.
    double waccDe({
      required double equity,
      required double debt,
      required double ke,
      required double kd,
      required double tax,
    }) {
      final v = equity + debt;
      return ke * (equity / v) + kd * (1 - tax) * (debt / v);
    }

    test('as duas rotas coincidem quando a alavancagem é de fato constante',
        () {
      // **Sem crescimento**, e é o ponto: com `g = 0` a dívida não cresce, o
      // valor não cresce, e `D/V` é constante em todo ano da projeção. É a
      // única configuração em que a identidade pode valer — ver o teste
      // seguinte, que mede o que acontece quando ela não vale.
      const kd = 0.11, tax = 0.30, ke = 0.155;
      const g = 0.0;
      const base = 1000.0;
      const divida = 3000.0;
      const papeis = 100.0;

      // Ponto fixo: parte de um `E` arbitrário, calcula o WACC que ele implica,
      // avalia, e repete até o `E` do modelo ser o `E` do peso. É a
      // circularidade do WACC resolvida por iteração — três dezenas de passos
      // bastam para o resíduo cair abaixo de um centavo.
      var equity = 5000.0;
      late DcfOutcome firma;
      for (var i = 0; i < 60; i++) {
        final wacc = waccDe(
          equity: equity,
          debt: divida,
          ke: ke,
          kd: kd,
          tax: tax,
        );
        final r = DcfCalculator.firm(
          baseProfit: base,
          assumptions: DcfAssumptions(
            projectionYears: 10,
            growthRate: g,
            perpetualGrowth: g,
            discountRate: wacc,
            terminalDiscountRate: wacc,
            returnOnCapital: 0.0,
            cashTiming: CashTiming.fimDeAno,
          ),
          netDebt: divida,
          sharesOutstanding: papeis,
        );
        expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
        firma = r.unwrap();
        equity = firma.equityValue;
      }

      final wacc = waccDe(
        equity: equity,
        debt: divida,
        ke: ke,
        kd: kd,
        tax: tax,
      );
      final acionista = DcfCalculator.equityFromFirm(
        baseProfit: base,
        assumptions: DcfAssumptions(
          projectionYears: 10,
          growthRate: g,
          perpetualGrowth: g,
          discountRate: wacc,
          terminalDiscountRate: wacc,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.fimDeAno,
        ),
        netDebt: divida,
        sharesOutstanding: papeis,
        costOfDebt: kd,
        taxRate: tax,
        equityDiscountRate: ke,
        terminalEquityDiscountRate: ke,
      );
      expect(acionista.isOk, isTrue, reason: acionista.failureOrNull?.message);

      final porFirma = firma.fairValuePerShare;
      final porAcionista = acionista.unwrap().fairValuePerShare;
      // Uma parte em dez mil: o que sobra é o ponto fixo não ter convergido a
      // zero absoluto, não discordância de método.
      expect(
        (porAcionista / porFirma - 1).abs(),
        lessThan(1e-4),
        reason: 'firma R\$ $porFirma contra acionista R\$ $porAcionista',
      );
    });

    test('sem dívida as duas rotas são a mesma conta', () {
      const ke = 0.15;
      const a = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.04,
        perpetualGrowth: 0.04,
        discountRate: ke,
        terminalDiscountRate: ke,
        returnOnCapital: 0.0,
      );
      final firma = DcfCalculator.firm(
        baseProfit: 500,
        assumptions: a,
        netDebt: 0,
        sharesOutstanding: 50,
      ).unwrap();
      final acionista = DcfCalculator.equityFromFirm(
        baseProfit: 500,
        assumptions: a,
        netDebt: 0,
        sharesOutstanding: 50,
        costOfDebt: 0.11,
        taxRate: 0.30,
        equityDiscountRate: ke,
        terminalEquityDiscountRate: ke,
      ).unwrap();
      expect(
        acionista.fairValuePerShare,
        closeTo(firma.fairValuePerShare, 1e-9),
      );
    });

    test('a alavancagem instável quebra a identidade, e o quanto é medido',
        () {
      // **O achado de A2.** Com `g > 0` a dívida cresce a `g`, mas o valor da
      // firma **não** cresce a `g` — a estrutura terminal faz `V` crescer a
      // outra taxa. Resultado: `D/V` muda ao longo da projeção, e o `WACC`
      // montado com os pesos do ano zero deixa de descrever os anos seguintes.
      //
      // Medido neste caso: no ano 10 o `E/V` do modelo é 0,62 contra os 0,71
      // com que o `WACC` foi construído, e as duas rotas divergem 4,2%.
      //
      // O conserto exige uma de duas coisas, e as duas são decisão nova:
      // amarrar a dívida ao **valor** em vez da base de capital, ou realavancar
      // o `Ke` ano a ano — que é onde o beta desalavancado da decisão 40 passa
      // a ser indispensável.
      const kd = 0.11, tax = 0.30, ke = 0.155, g = 0.05;
      const divida = 3000.0;

      double waccDe(double equity) {
        final v = equity + divida;
        return ke * (equity / v) + kd * (1 - tax) * (divida / v);
      }

      var equity = 5000.0;
      late DcfOutcome firma;
      var wacc = 0.0;
      for (var i = 0; i < 80; i++) {
        wacc = waccDe(equity);
        firma = DcfCalculator.firm(
          baseProfit: 1000,
          assumptions: DcfAssumptions(
            projectionYears: 10,
            growthRate: g,
            perpetualGrowth: g,
            discountRate: wacc,
            terminalDiscountRate: wacc,
            returnOnCapital: 0.0,
            cashTiming: CashTiming.fimDeAno,
          ),
          netDebt: divida,
          sharesOutstanding: 100,
        ).unwrap();
        equity = firma.equityValue;
      }

      final acionista = DcfCalculator.equityFromFirm(
        baseProfit: 1000,
        assumptions: DcfAssumptions(
          projectionYears: 10,
          growthRate: g,
          perpetualGrowth: g,
          discountRate: wacc,
          terminalDiscountRate: wacc,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.fimDeAno,
        ),
        netDebt: divida,
        sharesOutstanding: 100,
        costOfDebt: kd,
        taxRate: tax,
        equityDiscountRate: ke,
        terminalEquityDiscountRate: ke,
      ).unwrap();

      final divergencia =
          acionista.fairValuePerShare / firma.fairValuePerShare - 1;
      // Trava a ordem de grandeza, não o número: o que importa é que a
      // divergência existe e é material, e que ela some no teste anterior.
      expect(divergencia.abs(), greaterThan(0.01),
          reason: 'sem alavancagem constante a identidade não fecha');
      expect(divergencia.abs(), lessThan(0.10),
          reason: 'e o desvio é de poucos por cento, não de método');
    });

    test('recusa quando o Ke de equilíbrio não supera o crescimento', () {
      final r = DcfCalculator.equityFromFirm(
        baseProfit: 100,
        assumptions: const DcfAssumptions(
          projectionYears: 10,
          growthRate: 0.06,
          perpetualGrowth: 0.119,
          discountRate: 0.14,
          terminalDiscountRate: 0.12,
          returnOnCapital: 0.0,
          cashTiming: CashTiming.fimDeAno,
        ),
        netDebt: 100,
        sharesOutstanding: 10,
        costOfDebt: 0.11,
        taxRate: 0.30,
        equityDiscountRate: 0.14,
        terminalEquityDiscountRate: 0.12,
      );
      expect(r.isErr, isTrue);
    });
  });

  group('o juro e o rendimento do caixa seguem a curva (item B24)', () {
    const a = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.03,
      perpetualGrowth: 0.03,
      discountRate: 0.12,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.0,
      cashTiming: CashTiming.fimDeAno,
    );
    Result<DcfOutcome> rodar({
      List<double>? kd,
      List<double>? caixa,
      double? kdInf,
      double? caixaInf,
    }) =>
        DcfCalculator.equityFromFirm(
          baseProfit: 1000,
          assumptions: a,
          netDebt: 2000,
          sharesOutstanding: 100,
          costOfDebt: 0.12,
          taxRate: 0.34,
          equityDiscountRate: 0.15,
          terminalEquityDiscountRate: 0.15,
          cash: 500,
          cashYield: 0.10,
          costOfDebtPath: kd,
          cashYieldPath: caixa,
          terminalCostOfDebt: kdInf,
          terminalCashYield: caixaInf,
        );

    test('caminho constante é a taxa única', () {
      final unica = rodar().unwrap().equityValue;
      final caminho = rodar(
        kd: List.filled(5, 0.12),
        caixa: List.filled(5, 0.10),
        kdInf: 0.12,
        caixaInf: 0.10,
      ).unwrap().equityValue;
      expect(caminho, closeTo(unica, 1e-6));
    });

    test('juro mais alto no caminho baixa o capital próprio', () {
      final unica = rodar().unwrap().equityValue;
      final alto = rodar(
        kd: [0.15, 0.14, 0.13, 0.12, 0.12],
        caixa: List.filled(5, 0.10),
        kdInf: 0.12,
        caixaInf: 0.10,
      ).unwrap().equityValue;
      expect(alto, lessThan(unica));
    });

    test('o terminal usa a taxa de equilíbrio, e não a do ano 1', () {
      final unica = rodar().unwrap().equityValue;
      final terminalBaixo = rodar(kdInf: 0.09).unwrap().equityValue;
      expect(terminalBaixo, greaterThan(unica));
    });

    test('caminho de tamanho errado é recusado', () {
      expect(rodar(kd: [0.12, 0.12]).isErr, isTrue);
    });
  });
}
