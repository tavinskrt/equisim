// A taxa de cada ano segue a curva também sem o custo de capital resolvido
// (item B37), e o rastro descreve a conta que foi feita (item B35).
//
// Sem o ponto fixo — o banco, que não realavanca, e o recuo de quem não tem
// beta desalavancado — o desconto interpolava em linha reta do CDI de hoje até
// o forward depois do ano N, e o aviso dizia que a taxa seguia a curva. O
// rastro da via da firma montava o fator com o `WACC` e mostrava ao lado o
// valor presente do fluxo do acionista, descontado ao `Ke`.
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _hoje = DateTime(2026, 9, 14);

/// Curva com inclinação: 14% no primeiro ano, 12% no longo.
final _curva = YieldCurve.of(_hoje, const [
  CurveVertex(1, 0.14),
  CurveVertex(3, 0.13),
  CurveVertex(10, 0.12),
])!;

/// O banco do teste da Porta 1: lucro de 12% sobre o patrimônio, sem dívida.
List<FundamentalsSnapshot> _banco(Ticker t) {
  final pontos = <FundamentalsSnapshot>[];
  var pl = 1000.0;
  for (var ano = 2012; ano <= 2025; ano++) {
    final lucro = (ano.isEven ? 0.11 : 0.13) * pl;
    pl += lucro;
    pontos.add(FundamentalsSnapshot(
      ticker: t,
      fiscalPeriodEnd: DateTime(ano, 12, 31),
      bookValuePerShare: pl / 1000,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      netIncome: lucro,
      nopat: lucro,
      ebit: lucro * 1.4,
      longTermDebt: 0,
      marketCap: 20000,
    ));
  }
  return pontos;
}

/// Companhia não financeira da via da firma, sem beta desalavancado — o
/// custo de capital não é resolvido.
FundamentalsSnapshot _exercicio(Ticker t, int ano, double escala) =>
    FundamentalsSnapshot(
      ticker: t,
      fiscalPeriodEnd: DateTime(ano, 12, 31),
      totalRevenue: 10000 * escala,
      ebit: 1400 * escala,
      ebitda: 1900 * escala,
      netIncome: 700 * escala,
      incomeBeforeTax: 1000 * escala,
      incomeTaxExpense: -300 * escala,
      interestExpense: 120,
      earningsPerShare: 0.7 * escala,
      cash: 500,
      shortTermInvestments: 200,
      shortTermDebt: 400,
      longTermDebt: 1600,
      totalStockholderEquity: 6000 * escala,
      bookValuePerShare: 6.0 * escala,
      operatingCashFlow: 1500 * escala,
      freeCashFlow: 900 * escala,
      nopat: 924 * escala,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 10000,
    );

const _capm = CapmInputs(riskFreeRate: 0.15, beta: 1.0, marketPremium: 0.055);

({ValuationResult r, AuditEvent ev}) _avaliar(ValuationInputs i) {
  final eventos = <AuditEvent>[];
  AuditRecorder.attach(eventos.add);
  try {
    final r = ValuationCascade.evaluate(i);
    expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
    return (r: r.unwrap(), ev: eventos.single);
  } finally {
    AuditRecorder.detach();
  }
}

CalculationTrace _passo(AuditEvent ev, String prefixo) =>
    ev.calculations.singleWhere((c) => c.formulaName.startsWith(prefixo));

void main() {
  final fw = _curva.annualForwards(10);

  group('Sem resolução, a taxa de cada ano é a da curva (B37)', () {
    ValuationInputs banco({YieldCurve? curva}) => ValuationInputs(
          ticker: Ticker.parse('BANC3'),
          asOf: _hoje,
          fundamentals: _banco(Ticker.parse('BANC3')),
          marketPrice: 20.0,
          capm: _capm,
          sectorKey: 'financeiro',
          industry: 'Intermediários Financeiros / Bancos',
          riskFreeCurve: curva,
          declaredTerminalRiskFreeRate: 0.10,
        );

    test('o banco desconta o ano 1 ao forward do ano 1, e não ao CDI', () {
      final r = _avaliar(banco(curva: _curva)).r;
      expect(r.model, ValuationModel.dcfEarnings);
      expect(r.discountRate, closeTo(fw.first + 0.055, 1e-12));
      expect(r.discountRate, isNot(closeTo(_capm.costOfEquity, 1e-6)));
    });

    test('o rastro do banco mostra o K_e de cada ano sobre o forward', () {
      final ev = _avaliar(banco(curva: _curva)).ev;
      final d = _passo(ev, 'Projeção e desconto do período explícito');
      expect(d.mappedVariables['K_e,1 (% a.a.)'],
          closeTo((fw.first + 0.055) * 100, 0.006));
      expect(d.mappedVariables['K_e,N (% a.a.)'],
          closeTo((fw.last + 0.055) * 100, 0.006));
      final termo = _passo(ev, 'Estrutura a termo');
      expect(termo.intermediateSteps.first, contains('forward'));
    });

    test('sem curva, vale a interpolação da corrente à estrutural', () {
      final r = _avaliar(banco()).r;
      expect(r.discountRate, closeTo(_capm.costOfEquity, 1e-12));
    });

    test('a via da firma sem beta desalavancado desconta ao K_e da curva', () {
      final t = Ticker.parse('FIRM3');
      final ev = _avaliar(ValuationInputs(
        ticker: t,
        asOf: _hoje,
        fundamentals: [
          for (var i = 15; i >= 0; i--)
            _exercicio(t, 2025 - i, math.pow(1.05, 15 - i).toDouble()),
        ],
        marketPrice: 10.0,
        capm: _capm,
        riskFreeCurve: _curva,
        declaredTerminalRiskFreeRate: 0.10,
      )).ev;
      final d = _passo(ev, 'Fluxo do acionista e desconto ao K_e');
      expect(d.mappedVariables['K_e,1 (% a.a.)'],
          closeTo((fw.first + 0.055) * 100, 0.006));
      expect(d.mappedVariables['K_e,N (% a.a.)'],
          closeTo((fw.last + 0.055) * 100, 0.006));
      final ponte = _passo(ev, 'Capital próprio pelo fluxo do acionista');
      expect(ponte.mappedVariables['desconto'], contains('forward'));
    });
  });

  group('O rastro da via da firma fecha com a conta (B35)', () {
    final t = Ticker.parse('FIRM3');
    final insumos = ValuationInputs(
      ticker: t,
      asOf: _hoje,
      fundamentals: [
        for (var i = 15; i >= 0; i--)
          _exercicio(t, 2025 - i, math.pow(1.05, 15 - i).toDouble()),
      ],
      marketPrice: 10.0,
      capm: _capm,
      riskFreeCurve: _curva,
      declaredTerminalRiskFreeRate: 0.10,
      unleveredBeta: 0.8,
    );

    test('explícito e terminal do rastro são os que a ponte soma', () {
      final a = _avaliar(insumos);
      final explicito = _passo(a.ev, 'Fluxo do acionista e desconto ao K_e');
      final terminal = _passo(a.ev, 'Valor terminal (');
      final ponte = _passo(a.ev, 'Capital próprio pelo fluxo do acionista');
      expect(terminal.formulaName, contains('convertido para o acionista'));
      expect(ponte.mappedVariables['VP do fluxo explícito do acionista (R\$)'],
          closeTo(explicito.finalValue!, 0.006));
      expect(ponte.mappedVariables['VP do terminal do acionista (R\$)'],
          closeTo(terminal.finalValue!, 0.006));
      expect(ponte.finalValue, closeTo(a.r.fairValue.reais, 0.006));
      // A projeção da firma vem antes, e não desconta nada.
      expect(a.ev.calculations.any(
          (c) => c.formulaName == 'Projeção do fluxo da firma (NOPAT)'), isTrue);
    });

    test('o desfecho expõe as taxas que descontaram cada fluxo', () {
      const premissas = DcfAssumptions(
        projectionYears: 5,
        growthRate: 0.08,
        perpetualGrowth: 0.04,
        discountRate: 0.14,
        terminalDiscountRate: 0.12,
        returnOnCapital: 0.20,
      );
      final ke = [0.18, 0.175, 0.17, 0.165, 0.16];
      final o = DcfCalculator.equityFromFirm(
        baseProfit: 1000,
        assumptions: premissas,
        netDebt: 2000,
        sharesOutstanding: 100,
        costOfDebt: 0.16,
        taxRate: 0.34,
        equityDiscountRate: ke.first,
        terminalEquityDiscountRate: 0.155,
        equityDiscountRatePath: ke,
        cash: 500,
        cashYield: 0.14,
      ).unwrap();
      expect(o.discountRates, ke);
      expect(o.terminalDiscountRateUsed, 0.155);
      var fator = 1.0;
      for (var i = 0; i < 5; i++) {
        fator *= 1 + ke[i];
        // O fluxo do acionista é o da firma menos o serviço da dívida.
        expect(o.projectedFlows[i],
            closeTo(o.firmFlows![i] - o.debtService![i], 1e-9));
        // «fluxo × levantamento ÷ fator» dá o valor presente escrito ao lado.
        expect(o.discountedFlows[i],
            closeTo(o.projectedFlows[i] * math.sqrt(1 + ke[i]) / fator, 1e-9));
      }
      expect(o.terminalEquityFlow,
          closeTo(o.terminalFirmFlow! - o.terminalDebtService!, 1e-9));
      expect(o.terminalValue,
          closeTo(o.terminalEquityFlow! / (0.155 - 0.04), 1e-6));
      expect(o.discountedTerminalValue,
          closeTo(o.terminalValue * math.sqrt(1.155) / fator, 1e-6));
    });
  });
}
