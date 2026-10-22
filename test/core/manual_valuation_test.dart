// O cálculo do usuário refaz a conta do motor com os números de quem discorda
// dele (decisão 147).
//
// A promessa que estes testes travam: **sem nenhuma troca, o resultado é o
// preço justo do motor** — em cada rota da cascata —, e cada troca muda só a
// premissa trocada.
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');
final _today = DateTime(2026, 9, 9);

/// Companhia operacional: o resultado operacional sustenta a via da firma.
FundamentalsSnapshot _firmYear(int y, double e) => FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * e,
      ebit: 1800 * e,
      ebitda: 2400 * e,
      netIncome: 900 * e,
      incomeBeforeTax: 1300 * e,
      incomeTaxExpense: -400 * e,
      interestExpense: 400,
      earningsPerShare: 0.9 * e,
      cash: 200,
      shortTermDebt: 1000,
      longTermDebt: 3000,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 6.0 * e,
      operatingCashFlow: 2000 * e,
      nopat: 1188 * e,
      minorityInterest: 150,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    );

/// Companhia cujo resultado operacional é negativo e o lucro líquido positivo:
/// a Porta 3 a manda para a via do acionista.
FundamentalsSnapshot _shareholderYear(int y, double e) => FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * e,
      ebit: -200 * e,
      ebitda: 300 * e,
      netIncome: 900 * e,
      incomeBeforeTax: 1200 * e,
      incomeTaxExpense: -300 * e,
      interestExpense: 50,
      earningsPerShare: 0.9 * e,
      cash: 2000 * e,
      shortTermDebt: 500,
      longTermDebt: 500,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 6.0 * e,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    );

List<FundamentalsSnapshot> _series(
  FundamentalsSnapshot Function(int, double) year,
) {
  final out = <FundamentalsSnapshot>[];
  var e = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(year(2025 - i, e));
    // Crescimento que oscila em torno de 5%: série sem dispersão não deixa o
    // erro-padrão ser medido.
    e *= i.isEven ? 1.04 : 1.06;
  }
  return out;
}

ValuationInputs _inputs({
  bool firm = true,
  double? unlevered,
  YieldCurve? curve,
  List<ShareIssue> issuances = const [],
}) =>
    ValuationInputs(
      ticker: _ticker,
      asOf: _today,
      fundamentals: _series(firm ? _firmYear : _shareholderYear),
      marketPrice: 12.0,
      capm: const CapmInputs(
        riskFreeRate: 0.14,
        beta: 1.0,
        marketPremium: 0.055,
      ),
      declaredTerminalRiskFreeRate: 0.10,
      unleveredBeta: unlevered,
      riskFreeCurve: curve,
      shareIssues: issuances,
    );

ValuationResult _evaluate(ValuationInputs i) {
  final r = ValuationCascade.evaluate(i);
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

final _curve = YieldCurve.of(_today, const [
  CurveVertex(1, 0.14),
  CurveVertex(3, 0.13),
  CurveVertex(10, 0.12),
]);

/// As rotas da cascata que a conta congelada precisa reproduzir.
final _routes = <String, ValuationInputs Function()>{
  'firma, taxas resolvidas': () => _inputs(unlevered: 0.8),
  'firma, interpolação de dois pontos': _inputs,
  'firma, sobre a curva sem resolução': () => _inputs(curve: _curve),
  'firma, com emissão depois do balanço': () => _inputs(
        issuances: [
          ShareIssue(
            date: DateTime(2026, 4, 15),
            amount: Money.fromReais(1200),
            shares: 100,
          ),
        ],
      ),
  'acionista, Ke resolvido': () => _inputs(firm: false, unlevered: 0.9),
  'acionista, interpolação': () => _inputs(firm: false),
  'acionista, sobre a curva': () => _inputs(firm: false, curve: _curve),
};

/// Uma conta congelada sintética da via do acionista, para os testes que
/// precisam de fórmula fechada.
ManualValuation _synthetic({
  double rate = 0.13,
  double g = 0.06,
  double gInf = 0.04,
  double returnRate = 0.20,
  double? advantage,
}) {
  final a = DcfAssumptions(
    growthRate: g,
    perpetualGrowth: gInf,
    discountRate: rate,
    terminalDiscountRate: rate,
    returnOnCapital: returnRate,
    terminalReturnOnCapital: advantage,
  );
  final o = DcfCalculator.shareholder(baseProfit: 1.0, assumptions: a).unwrap();
  return ManualValuation(
    lane: ValuationLane.shareholder,
    shares: 100,
    marketPrice: 10,
    engineFairValue: o.fairValuePerShare,
    engineBase: 1.0,
    engineAssumptions: a,
    engineRates: o.discountRates!,
    engineTerminalRate: o.terminalDiscountRateUsed!,
  );
}

void main() {
  group('sem nenhuma troca, o preço é o do motor', () {
    for (final MapEntry(key: name, value: build) in _routes.entries) {
      test(name, () {
        final r = _evaluate(build());
        final m = r.manual;
        expect(m, isNotNull, reason: 'a cascata congela a conta da via');
        final o = m!.evaluate(m.enginePremises);
        expect(o.isOk, isTrue, reason: o.failureOrNull?.message);
        final yours = o.unwrap().fairValuePerShare;
        // Igualdade exata, e não tolerância: sem troca, a conta é a mesma.
        expect(yours, m.engineFairValue);
        expect(Money.fromReais(yours), r.fairValue);
        expect(
          m.lane == ValuationLane.firm,
          r.model == ValuationModel.dcfFcff,
        );
      });
    }

    test('o patrimônio fecha: explícito + perpetuidade − minoritários + '
        'emissão = preço × papéis', () {
      for (final build in _routes.values) {
        final m = _evaluate(build()).manual!;
        final o = m.evaluate(m.enginePremises).unwrap();
        expect(
          o.explicitPresentValue +
              o.terminalPresentValue -
              o.minorityInterest +
              o.postStatementCapital,
          closeTo(o.fairValuePerShare * m.shares, 1e-6),
        );
        expect(o.equityValue, closeTo(o.fairValuePerShare * m.shares, 1e-6));
        // Cada ano: fluxo ÷ fator = valor presente.
        for (final y in o.years) {
          expect(y.flow / y.discountFactor, closeTo(y.presentValue, 1e-9));
        }
      }
    });

    test('na via da firma, a emissão posterior entra pelo valor de emissão',
        () {
      final m = _evaluate(_routes['firma, com emissão depois do balanço']!())
          .manual!;
      expect(m.postStatementCapital, 1200);
      expect(m.evaluate(m.enginePremises).unwrap().postStatementCapital, 1200);
    });
  });

  group('cada troca muda só a premissa trocada', () {
    for (final MapEntry(key: name, value: build) in _routes.entries) {
      test('taxa mais alta, preço mais baixo — $name', () {
        final m = _evaluate(build()).manual!;
        final p = m.enginePremises;
        final base = m.evaluate(p).unwrap().fairValuePerShare;
        final high = m
            .evaluate(p.copyWith(discountRate: p.discountRate + 0.01))
            .unwrap()
            .fairValuePerShare;
        final low = m
            .evaluate(p.copyWith(discountRate: p.discountRate - 0.01))
            .unwrap()
            .fairValuePerShare;
        expect(high, lessThan(base));
        expect(low, greaterThan(base));
      });
    }

    test('o caminho do motor desloca todos os anos e a perpetuidade juntos', () {
      final m = _evaluate(_inputs(curve: _curve, firm: false)).manual!;
      final p = m.enginePremises.copyWith(
        discountRate: m.enginePremises.discountRate + 0.02,
      );
      final o = m.evaluate(p).unwrap();
      for (var i = 0; i < o.years.length; i++) {
        expect(o.years[i].rate, closeTo(m.engineRates[i] + 0.02, 1e-12));
      }
      expect(o.terminalRate, closeTo(m.engineTerminalRate + 0.02, 1e-12));
    });

    test('a taxa constante vale do primeiro ano à perpetuidade', () {
      final m = _evaluate(_inputs(curve: _curve)).manual!;
      final p = m.enginePremises.copyWith(
        ratePath: ManualRatePath.constant,
        discountRate: 0.15,
      );
      final o = m.evaluate(p).unwrap();
      for (final y in o.years) {
        expect(y.rate, closeTo(0.15, 1e-15));
      }
      expect(o.terminalRate, closeTo(0.15, 1e-15));
    });

    test('na via da firma, a taxa desconta e o custo médio do capital fica', () {
      // A taxa do usuário entra no `Ke` que desconta o fluxo do acionista; o
      // `WACC`, alvo do retorno e da perpetuidade da firma, é o do motor.
      final m = _evaluate(_inputs(unlevered: 0.8)).manual!;
      final p = m.enginePremises;
      final before = m.evaluate(p).unwrap();
      final after =
          m.evaluate(p.copyWith(discountRate: p.discountRate + 0.01)).unwrap();
      expect(after.capitalCostRates, before.capitalCostRates);
      expect(after.terminalCapitalCost, before.terminalCapitalCost);
      for (var i = 0; i < before.years.length; i++) {
        // O fluxo do ano não muda: só o desconto.
        expect(after.years[i].flow, closeTo(before.years[i].flow, 1e-9));
        expect(after.years[i].rate, closeTo(before.years[i].rate + 0.01, 1e-12));
      }
    });

    test('na via do acionista, o preço é proporcional ao lucro de partida', () {
      final m = _evaluate(_inputs(firm: false)).manual!;
      final p = m.enginePremises;
      final one = m.evaluate(p).unwrap().fairValuePerShare;
      final two = m
          .evaluate(p.copyWith(baseProfit: p.baseProfit * 2))
          .unwrap()
          .fairValuePerShare;
      expect(two, closeTo(2 * one, 1e-9));
    });

    test('o lucro de partida é o do ano, em reais, nas duas vias', () {
      final firm = _evaluate(_inputs()).manual!;
      final shareholder = _evaluate(_inputs(firm: false)).manual!;
      expect(firm.enginePremises.baseProfit, firm.engineBase);
      expect(
        shareholder.enginePremises.baseProfit,
        closeTo(shareholder.engineBase * shareholder.shares, 1e-9),
      );
      // O último exercício publicado, sem a normalização: lucro líquido de
      // 900 × e na via do acionista.
      expect(shareholder.publishedBase, isNotNull);
      expect(shareholder.publishedBase! > 0, isTrue);
    });

    test('o crescimento constante vale nos dez anos', () {
      final m = _synthetic();
      final p = m.enginePremises.copyWith(
        growth: 0.08,
        growthPath: ManualGrowthPath.constant,
      );
      final o = m.evaluate(p).unwrap();
      expect(o.years.every((y) => (y.growth - 0.08).abs() < 1e-12), isTrue);
    });
  });

  group('as formas da perpetuidade', () {
    test('a parcela fixa é Gordon com a mesma parcela, em fórmula fechada', () {
      const r = 0.13, g = 0.07, gInf = 0.04, b = 0.35;
      final m = _synthetic(rate: r);
      final p = m.enginePremises.copyWith(
        reinvestment: ManualReinvestment.fixedFraction,
        retention: b,
        growth: g,
        growthPath: ManualGrowthPath.constant,
        perpetualGrowth: gInf,
      );
      final o = m.evaluate(p).unwrap();
      expect(o.terminalKind, ManualTerminal.fixedFraction);
      // A conta à mão: lucro por papel de 1, dez anos a 7%, metade do ano.
      var vp = 0.0;
      var profit = 1.0;
      for (var t = 1; t <= 10; t++) {
        profit *= 1 + g;
        vp += profit * (1 - b) * math.sqrt(1 + r) / math.pow(1 + r, t);
      }
      final vt = profit * (1 + gInf) * (1 - b) / (r - gInf);
      vp += vt * math.sqrt(1 + r) / math.pow(1 + r, 10);
      expect(o.fairValuePerShare, closeTo(vp, 1e-9));
      expect(o.years.every((y) => y.retention == b), isTrue);
    });

    test('a parcela fixa solta o crescimento do retorno', () {
      // Retorno de 5% não financia crescer 30%: pelo retorno o motor confina,
      // com a parcela fixa não.
      final m = _synthetic(returnRate: 0.05);
      final withGrowth = m.evaluate(m.enginePremises.copyWith(growth: 0.30)).unwrap();
      expect(
        withGrowth.notices.any((n) => n.kind == ManualNoticeKind.confinedGrowth),
        isTrue,
      );
      expect(withGrowth.years.first.growth, lessThan(0.30));
      final fixed = m
          .evaluate(m.enginePremises.copyWith(
            growth: 0.30,
            reinvestment: ManualReinvestment.fixedFraction,
            retention: 0.4,
          ))
          .unwrap();
      expect(fixed.years.first.growth, 0.30);
      expect(
        fixed.notices.any((n) => n.kind == ManualNoticeKind.confinedGrowth),
        isFalse,
      );
    });

    test('devolver a vantagem competitiva ao estado estacionário', () {
      final m = _synthetic(advantage: 0.22);
      expect(m.enginePremises.terminalReturn, 0.22);
      final o =
          m.evaluate(m.enginePremises.copyWith(terminalReturn: null)).unwrap();
      expect(o.terminalKind, ManualTerminal.neutral);
      // Neutro: lucro do ano 11 ÷ taxa.
      final profit10 = o.years.last.profit / m.shares;
      expect(
        o.terminalValue / m.shares,
        closeTo(profit10 * (1 + 0.04) / 0.13, 1e-9),
      );
    });

    test('o capital novo acima da taxa dá valor ao crescimento perpétuo', () {
      final m = _synthetic();
      double price(double gInf, double? ronic) => m
          .evaluate(m.enginePremises
              .copyWith(perpetualGrowth: gInf, terminalReturn: ronic))
          .unwrap()
          .fairValuePerShare;
      // Com retorno de 25% sobre o capital novo, crescer mais vale mais.
      expect(price(0.06, 0.25), greaterThan(price(0.04, 0.25)));
      final neutral = m
          .evaluate(m.enginePremises.copyWith(perpetualGrowth: 0.06))
          .unwrap();
      expect(
        neutral.notices.any((n) => n.kind == ManualNoticeKind.neutralPerpetuity),
        isTrue,
      );
    });
  });

  group('as recusas nomeiam o campo', () {
    final m = _synthetic();
    final p = m.enginePremises;

    String? field(ManualPremises x) {
      final f = m.evaluate(x).failureOrNull;
      return f is InvalidInput ? f.field : null;
    }

    test('lucro de partida não positivo', () {
      expect(field(p.copyWith(baseProfit: 0)), ManualField.baseProfit.name);
    });

    test('parcela reinvestida de 100% ou mais', () {
      expect(
        field(p.copyWith(
          reinvestment: ManualReinvestment.fixedFraction,
          retention: 1.0,
        )),
        ManualField.retention.name,
      );
    });

    test('taxa não positiva', () {
      expect(field(p.copyWith(discountRate: -0.01)),
          ManualField.discountRate.name);
    });

    test('perpetuidade de Gordon sem margem sobre o crescimento', () {
      final f = m
          .evaluate(p.copyWith(
            reinvestment: ManualReinvestment.fixedFraction,
            retention: 0.3,
            perpetualGrowth: 0.13,
          ))
          .failureOrNull;
      expect(f, isA<InvalidInput>());
      final i = f as InvalidInput;
      expect(i.field, ManualField.perpetualGrowth.name);
      expect(i.limit, DcfCalculator.minimumSpread);
      expect(i.actual, closeTo(0.0, 1e-12));
    });

    test('retorno do capital novo não positivo', () {
      expect(field(p.copyWith(terminalReturn: 0.0)),
          ManualField.terminalReturn.name);
    });
  });

  group('onde você discorda do motor', () {
    test('os degraus somam a diferença inteira', () {
      final m = _evaluate(_inputs(unlevered: 0.8)).manual!;
      final p = m.enginePremises.copyWith(
        baseProfit: m.enginePremises.baseProfit * 1.2,
        growth: m.enginePremises.growth + 0.02,
        discountRate: m.enginePremises.discountRate - 0.01,
      );
      final steps = m.attribution(p);
      expect(steps.map((d) => d.groups.single), [
        ManualGroup.profit,
        ManualGroup.growth,
        ManualGroup.rate,
      ]);
      final sum = steps.fold(0.0, (s, d) => s + d.delta!);
      final yours = m.evaluate(p).unwrap().fairValuePerShare;
      expect(sum, closeTo(yours - m.engineFairValue, 1e-9));
    });

    test('sem troca, nenhum degrau', () {
      final m = _synthetic();
      expect(m.attribution(m.enginePremises), isEmpty);
    });

    test('o grupo que sozinho não fecha a conta se soma ao seguinte', () {
      // Taxa de 4,2% com o crescimento perpétuo de 4% do motor fica sem a
      // margem de 0,5 p.p.; com o perpétuo de 2% do usuário, fecha.
      final m = _synthetic();
      final p = m.enginePremises.copyWith(
        reinvestment: ManualReinvestment.fixedFraction,
        retention: 0.3,
        discountRate: 0.042,
        perpetualGrowth: 0.02,
      );
      final steps = m.attribution(p);
      expect(steps.last.groups, [ManualGroup.rate, ManualGroup.perpetuity]);
      expect(steps.last.to, isNotNull);
    });
  });

  group('o que o preço de hoje supõe', () {
    test('a taxa que iguala o preço justo ao de mercado', () {
      final m = _evaluate(_inputs(unlevered: 0.8)).manual!;
      final s = m.solve(ManualField.discountRate, m.enginePremises);
      expect(s.value, isNotNull);
      final price = m
          .evaluate(m.enginePremises.copyWith(discountRate: s.value))
          .unwrap()
          .fairValuePerShare;
      expect(price, closeTo(m.marketPrice, 1e-6));
    });

    test('o lucro de partida que o preço supõe, nas duas vias', () {
      for (final firm in [true, false]) {
        final m = _evaluate(_inputs(firm: firm)).manual!;
        final s = m.solve(ManualField.baseProfit, m.enginePremises);
        expect(s.value, isNotNull);
        final price = m
            .evaluate(m.enginePremises.copyWith(baseProfit: s.value))
            .unwrap()
            .fairValuePerShare;
        expect(price, closeTo(m.marketPrice, 1e-6));
      }
    });

    test('sem solução, devolve o mais perto que o campo chega', () {
      final m = _synthetic();
      // Nenhum retorno do capital novo leva o preço a mil reais.
      final s = m.solve(
        ManualField.terminalReturn,
        m.enginePremises,
        target: 1000,
      );
      expect(s.value, isNull);
      expect(s.closestValue, isNotNull);
      expect(s.closestPrice, lessThan(1000));
    });

    test('a resposta é determinística', () {
      final m = _evaluate(_inputs()).manual!;
      final a = m.solve(ManualField.growth, m.enginePremises);
      final b = m.solve(ManualField.growth, m.enginePremises);
      expect(a.value, b.value);
      expect(a.closestValue, b.closestValue);
    });
  });

  group('as premissas novas não mudam a produção', () {
    test('sem caminho de crescimento, o planejado é o decaimento linear', () {
      const a = DcfAssumptions(
        growthRate: 0.10,
        perpetualGrowth: 0.04,
        discountRate: 0.13,
      );
      for (var t = 1; t <= 10; t++) {
        expect(a.plannedGrowthAt(t),
            closeTo(0.10 - 0.06 * (t - 1) / 9, 1e-15));
        expect(a.growthAt(t), a.plannedGrowthAt(t));
      }
    });

    test('caminho de crescimento com tamanho errado é recusado', () {
      final a = const DcfAssumptions(
        growthRate: 0.05,
        perpetualGrowth: 0.04,
        discountRate: 0.13,
      ).copyWith(growthPath: [0.05, 0.05]);
      expect(
        DcfCalculator.shareholder(baseProfit: 1, assumptions: a).isErr,
        isTrue,
      );
    });

    test('a cópia com o retorno terminal nulo mantém todo o resto', () {
      final a = const DcfAssumptions(
        growthRate: 0.05,
        perpetualGrowth: 0.04,
        discountRate: 0.13,
        terminalDiscountRate: 0.11,
        returnOnCapital: 0.2,
        terminalReturnOnCapital: 0.18,
        contractYearsAfterHorizon: 7,
        inflation: 0.04,
      ).copyWith(fixedRetention: 0.3, growthPath: List.filled(10, 0.05));
      final b = a.withTerminalReturnOnCapital(null);
      expect(b.terminalReturnOnCapital, isNull);
      expect(b.terminalDiscountRate, a.terminalDiscountRate);
      expect(b.contractYearsAfterHorizon, a.contractYearsAfterHorizon);
      expect(b.inflation, a.inflation);
      expect(b.fixedRetention, a.fixedRetention);
      expect(b.growthPath, a.growthPath);
      expect(b.returnOnCapital, a.returnOnCapital);
    });
  });
}
