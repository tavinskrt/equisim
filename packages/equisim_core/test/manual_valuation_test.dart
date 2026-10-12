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
final _hoje = DateTime(2026, 9, 9);

/// Companhia operacional: o resultado operacional sustenta a via da firma.
FundamentalsSnapshot _anoDaFirma(int y, double e) => FundamentalsSnapshot(
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
FundamentalsSnapshot _anoDoAcionista(int y, double e) => FundamentalsSnapshot(
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

List<FundamentalsSnapshot> _serie(
  FundamentalsSnapshot Function(int, double) ano,
) {
  final out = <FundamentalsSnapshot>[];
  var e = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(ano(2025 - i, e));
    // Crescimento que oscila em torno de 5%: série sem dispersão não deixa o
    // erro-padrão ser medido.
    e *= i.isEven ? 1.04 : 1.06;
  }
  return out;
}

ValuationInputs _insumos({
  bool firma = true,
  double? desalavancado,
  YieldCurve? curva,
  List<ShareIssue> emissoes = const [],
}) =>
    ValuationInputs(
      ticker: _ticker,
      asOf: _hoje,
      fundamentals: _serie(firma ? _anoDaFirma : _anoDoAcionista),
      marketPrice: 12.0,
      capm: const CapmInputs(
        riskFreeRate: 0.14,
        beta: 1.0,
        marketPremium: 0.055,
      ),
      declaredTerminalRiskFreeRate: 0.10,
      unleveredBeta: desalavancado,
      riskFreeCurve: curva,
      shareIssues: emissoes,
    );

ValuationResult _avaliar(ValuationInputs i) {
  final r = ValuationCascade.evaluate(i);
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

final _curva = YieldCurve.of(_hoje, const [
  CurveVertex(1, 0.14),
  CurveVertex(3, 0.13),
  CurveVertex(10, 0.12),
]);

/// As rotas da cascata que a conta congelada precisa reproduzir.
final _rotas = <String, ValuationInputs Function()>{
  'firma, taxas resolvidas': () => _insumos(desalavancado: 0.8),
  'firma, interpolação de dois pontos': () => _insumos(),
  'firma, sobre a curva sem resolução': () => _insumos(curva: _curva),
  'firma, com emissão depois do balanço': () => _insumos(
        emissoes: [
          ShareIssue(
            date: DateTime(2026, 4, 15),
            amount: Money.fromReais(1200),
            shares: 100,
          ),
        ],
      ),
  'acionista, Ke resolvido': () => _insumos(firma: false, desalavancado: 0.9),
  'acionista, interpolação': () => _insumos(firma: false),
  'acionista, sobre a curva': () => _insumos(firma: false, curva: _curva),
};

/// Uma conta congelada sintética da via do acionista, para os testes que
/// precisam de fórmula fechada.
ManualValuation _sintetica({
  double taxa = 0.13,
  double g = 0.06,
  double gInf = 0.04,
  double retorno = 0.20,
  double? vantagem,
}) {
  final a = DcfAssumptions(
    growthRate: g,
    perpetualGrowth: gInf,
    discountRate: taxa,
    terminalDiscountRate: taxa,
    returnOnCapital: retorno,
    terminalReturnOnCapital: vantagem,
  );
  final o = DcfCalculator.shareholder(baseProfit: 1.0, assumptions: a).unwrap();
  return ManualValuation(
    lane: ValuationLane.shareholder,
    shares: 100,
    marketPrice: 10,
    motorFairValue: o.fairValuePerShare,
    motorBase: 1.0,
    motorAssumptions: a,
    motorRates: o.discountRates!,
    motorTerminalRate: o.terminalDiscountRateUsed!,
  );
}

void main() {
  group('sem nenhuma troca, o preço é o do motor', () {
    for (final MapEntry(key: nome, value: montar) in _rotas.entries) {
      test(nome, () {
        final r = _avaliar(montar());
        final m = r.manual;
        expect(m, isNotNull, reason: 'a cascata congela a conta da via');
        final o = m!.evaluate(m.motorPremises);
        expect(o.isOk, isTrue, reason: o.failureOrNull?.message);
        final seu = o.unwrap().fairValuePerShare;
        // Igualdade exata, e não tolerância: sem troca, a conta é a mesma.
        expect(seu, m.motorFairValue);
        expect(Money.fromReais(seu), r.fairValue);
        expect(
          m.lane == ValuationLane.firm,
          r.model == ValuationModel.dcfFcff,
        );
      });
    }

    test('o patrimônio fecha: explícito + perpetuidade − minoritários + '
        'emissão = preço × papéis', () {
      for (final montar in _rotas.values) {
        final m = _avaliar(montar()).manual!;
        final o = m.evaluate(m.motorPremises).unwrap();
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
      final m = _avaliar(_rotas['firma, com emissão depois do balanço']!())
          .manual!;
      expect(m.postStatementCapital, 1200);
      expect(m.evaluate(m.motorPremises).unwrap().postStatementCapital, 1200);
    });
  });

  group('cada troca muda só a premissa trocada', () {
    for (final MapEntry(key: nome, value: montar) in _rotas.entries) {
      test('taxa mais alta, preço mais baixo — $nome', () {
        final m = _avaliar(montar()).manual!;
        final p = m.motorPremises;
        final base = m.evaluate(p).unwrap().fairValuePerShare;
        final alta = m
            .evaluate(p.copyWith(discountRate: p.discountRate + 0.01))
            .unwrap()
            .fairValuePerShare;
        final baixa = m
            .evaluate(p.copyWith(discountRate: p.discountRate - 0.01))
            .unwrap()
            .fairValuePerShare;
        expect(alta, lessThan(base));
        expect(baixa, greaterThan(base));
      });
    }

    test('o caminho do motor desloca todos os anos e a perpetuidade juntos', () {
      final m = _avaliar(_insumos(curva: _curva, firma: false)).manual!;
      final p = m.motorPremises.copyWith(
        discountRate: m.motorPremises.discountRate + 0.02,
      );
      final o = m.evaluate(p).unwrap();
      for (var i = 0; i < o.years.length; i++) {
        expect(o.years[i].rate, closeTo(m.motorRates[i] + 0.02, 1e-12));
      }
      expect(o.terminalRate, closeTo(m.motorTerminalRate + 0.02, 1e-12));
    });

    test('a taxa constante vale do primeiro ano à perpetuidade', () {
      final m = _avaliar(_insumos(curva: _curva)).manual!;
      final p = m.motorPremises.copyWith(
        ratePath: ManualRatePath.constante,
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
      final m = _avaliar(_insumos(desalavancado: 0.8)).manual!;
      final p = m.motorPremises;
      final antes = m.evaluate(p).unwrap();
      final depois =
          m.evaluate(p.copyWith(discountRate: p.discountRate + 0.01)).unwrap();
      expect(depois.capitalCostRates, antes.capitalCostRates);
      expect(depois.terminalCapitalCost, antes.terminalCapitalCost);
      for (var i = 0; i < antes.years.length; i++) {
        // O fluxo do ano não muda: só o desconto.
        expect(depois.years[i].flow, closeTo(antes.years[i].flow, 1e-9));
        expect(depois.years[i].rate, closeTo(antes.years[i].rate + 0.01, 1e-12));
      }
    });

    test('na via do acionista, o preço é proporcional ao lucro de partida', () {
      final m = _avaliar(_insumos(firma: false)).manual!;
      final p = m.motorPremises;
      final um = m.evaluate(p).unwrap().fairValuePerShare;
      final dois = m
          .evaluate(p.copyWith(baseProfit: p.baseProfit * 2))
          .unwrap()
          .fairValuePerShare;
      expect(dois, closeTo(2 * um, 1e-9));
    });

    test('o lucro de partida é o do ano, em reais, nas duas vias', () {
      final firma = _avaliar(_insumos()).manual!;
      final acionista = _avaliar(_insumos(firma: false)).manual!;
      expect(firma.motorPremises.baseProfit, firma.motorBase);
      expect(
        acionista.motorPremises.baseProfit,
        closeTo(acionista.motorBase * acionista.shares, 1e-9),
      );
      // O último exercício publicado, sem a normalização: lucro líquido de
      // 900 × e na via do acionista.
      expect(acionista.publishedBase, isNotNull);
      expect(acionista.publishedBase! > 0, isTrue);
    });

    test('o crescimento constante vale nos dez anos', () {
      final m = _sintetica();
      final p = m.motorPremises.copyWith(
        growth: 0.08,
        growthPath: ManualGrowthPath.constante,
      );
      final o = m.evaluate(p).unwrap();
      expect(o.years.every((y) => (y.growth - 0.08).abs() < 1e-12), isTrue);
    });
  });

  group('as formas da perpetuidade', () {
    test('a parcela fixa é Gordon com a mesma parcela, em fórmula fechada', () {
      const r = 0.13, g = 0.07, gInf = 0.04, b = 0.35;
      final m = _sintetica(taxa: r);
      final p = m.motorPremises.copyWith(
        reinvestment: ManualReinvestment.parcelaFixa,
        retention: b,
        growth: g,
        growthPath: ManualGrowthPath.constante,
        perpetualGrowth: gInf,
      );
      final o = m.evaluate(p).unwrap();
      expect(o.terminalKind, ManualTerminal.parcelaFixa);
      // A conta à mão: lucro por papel de 1, dez anos a 7%, metade do ano.
      var vp = 0.0;
      var lucro = 1.0;
      for (var t = 1; t <= 10; t++) {
        lucro *= 1 + g;
        vp += lucro * (1 - b) * math.sqrt(1 + r) / math.pow(1 + r, t);
      }
      final vt = lucro * (1 + gInf) * (1 - b) / (r - gInf);
      vp += vt * math.sqrt(1 + r) / math.pow(1 + r, 10);
      expect(o.fairValuePerShare, closeTo(vp, 1e-9));
      expect(o.years.every((y) => y.retention == b), isTrue);
    });

    test('a parcela fixa solta o crescimento do retorno', () {
      // Retorno de 5% não financia crescer 30%: pelo retorno o motor confina,
      // com a parcela fixa não.
      final m = _sintetica(retorno: 0.05);
      final pelo = m.evaluate(m.motorPremises.copyWith(growth: 0.30)).unwrap();
      expect(
        pelo.notices.any((n) => n.kind == ManualNoticeKind.crescimentoConfinado),
        isTrue,
      );
      expect(pelo.years.first.growth, lessThan(0.30));
      final fixa = m
          .evaluate(m.motorPremises.copyWith(
            growth: 0.30,
            reinvestment: ManualReinvestment.parcelaFixa,
            retention: 0.4,
          ))
          .unwrap();
      expect(fixa.years.first.growth, 0.30);
      expect(
        fixa.notices.any((n) => n.kind == ManualNoticeKind.crescimentoConfinado),
        isFalse,
      );
    });

    test('devolver a vantagem competitiva ao estado estacionário', () {
      final m = _sintetica(vantagem: 0.22);
      expect(m.motorPremises.terminalReturn, 0.22);
      final o =
          m.evaluate(m.motorPremises.copyWith(terminalReturn: null)).unwrap();
      expect(o.terminalKind, ManualTerminal.neutro);
      // Neutro: lucro do ano 11 ÷ taxa.
      final lucro10 = o.years.last.profit / m.shares;
      expect(
        o.terminalValue / m.shares,
        closeTo(lucro10 * (1 + 0.04) / 0.13, 1e-9),
      );
    });

    test('o capital novo acima da taxa dá valor ao crescimento perpétuo', () {
      final m = _sintetica();
      double preco(double gInf, double? ronic) => m
          .evaluate(m.motorPremises
              .copyWith(perpetualGrowth: gInf, terminalReturn: ronic))
          .unwrap()
          .fairValuePerShare;
      // Com retorno de 25% sobre o capital novo, crescer mais vale mais.
      expect(preco(0.06, 0.25), greaterThan(preco(0.04, 0.25)));
      final neutro = m
          .evaluate(m.motorPremises.copyWith(perpetualGrowth: 0.06))
          .unwrap();
      expect(
        neutro.notices.any((n) => n.kind == ManualNoticeKind.perpetuidadeNeutra),
        isTrue,
      );
    });
  });

  group('as recusas nomeiam o campo', () {
    final m = _sintetica();
    final p = m.motorPremises;

    String? campo(ManualPremises x) {
      final f = m.evaluate(x).failureOrNull;
      return f is InvalidInput ? f.field : null;
    }

    test('lucro de partida não positivo', () {
      expect(campo(p.copyWith(baseProfit: 0)), ManualField.baseProfit.name);
    });

    test('parcela reinvestida de 100% ou mais', () {
      expect(
        campo(p.copyWith(
          reinvestment: ManualReinvestment.parcelaFixa,
          retention: 1.0,
        )),
        ManualField.retention.name,
      );
    });

    test('taxa não positiva', () {
      expect(campo(p.copyWith(discountRate: -0.01)),
          ManualField.discountRate.name);
    });

    test('perpetuidade de Gordon sem margem sobre o crescimento', () {
      final f = m
          .evaluate(p.copyWith(
            reinvestment: ManualReinvestment.parcelaFixa,
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
      expect(campo(p.copyWith(terminalReturn: 0.0)),
          ManualField.terminalReturn.name);
    });
  });

  group('onde você discorda do motor', () {
    test('os degraus somam a diferença inteira', () {
      final m = _avaliar(_insumos(desalavancado: 0.8)).manual!;
      final p = m.motorPremises.copyWith(
        baseProfit: m.motorPremises.baseProfit * 1.2,
        growth: m.motorPremises.growth + 0.02,
        discountRate: m.motorPremises.discountRate - 0.01,
      );
      final degraus = m.attribution(p);
      expect(degraus.map((d) => d.groups.single), [
        ManualGroup.lucro,
        ManualGroup.crescimento,
        ManualGroup.taxa,
      ]);
      final soma = degraus.fold(0.0, (s, d) => s + d.delta!);
      final seu = m.evaluate(p).unwrap().fairValuePerShare;
      expect(soma, closeTo(seu - m.motorFairValue, 1e-9));
    });

    test('sem troca, nenhum degrau', () {
      final m = _sintetica();
      expect(m.attribution(m.motorPremises), isEmpty);
    });

    test('o grupo que sozinho não fecha a conta se soma ao seguinte', () {
      // Taxa de 4,2% com o crescimento perpétuo de 4% do motor fica sem a
      // margem de 0,5 p.p.; com o perpétuo de 2% do usuário, fecha.
      final m = _sintetica();
      final p = m.motorPremises.copyWith(
        reinvestment: ManualReinvestment.parcelaFixa,
        retention: 0.3,
        discountRate: 0.042,
        perpetualGrowth: 0.02,
      );
      final degraus = m.attribution(p);
      expect(degraus.last.groups, [ManualGroup.taxa, ManualGroup.perpetuidade]);
      expect(degraus.last.to, isNotNull);
    });
  });

  group('o que o preço de hoje supõe', () {
    test('a taxa que iguala o preço justo ao de mercado', () {
      final m = _avaliar(_insumos(desalavancado: 0.8)).manual!;
      final s = m.solve(ManualField.discountRate, m.motorPremises);
      expect(s.value, isNotNull);
      final preco = m
          .evaluate(m.motorPremises.copyWith(discountRate: s.value))
          .unwrap()
          .fairValuePerShare;
      expect(preco, closeTo(m.marketPrice, 1e-6));
    });

    test('o lucro de partida que o preço supõe, nas duas vias', () {
      for (final firma in [true, false]) {
        final m = _avaliar(_insumos(firma: firma)).manual!;
        final s = m.solve(ManualField.baseProfit, m.motorPremises);
        expect(s.value, isNotNull);
        final preco = m
            .evaluate(m.motorPremises.copyWith(baseProfit: s.value))
            .unwrap()
            .fairValuePerShare;
        expect(preco, closeTo(m.marketPrice, 1e-6));
      }
    });

    test('sem solução, devolve o mais perto que o campo chega', () {
      final m = _sintetica();
      // Nenhum retorno do capital novo leva o preço a mil reais.
      final s = m.solve(
        ManualField.terminalReturn,
        m.motorPremises,
        target: 1000,
      );
      expect(s.value, isNull);
      expect(s.closestValue, isNotNull);
      expect(s.closestPrice, lessThan(1000));
    });

    test('a resposta é determinística', () {
      final m = _avaliar(_insumos()).manual!;
      final a = m.solve(ManualField.growth, m.motorPremises);
      final b = m.solve(ManualField.growth, m.motorPremises);
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
