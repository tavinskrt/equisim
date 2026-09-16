import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// O deslocamento do nível da taxa livre de risco — o instrumento da varredura
/// do item B10.
void main() {
  final hoje = DateTime(2026, 9, 14);
  final curvaPlana = YieldCurve.of(hoje, const [
    CurveVertex(1, 0.10),
    CurveVertex(5, 0.10),
    CurveVertex(10, 0.10),
  ])!;

  ValuationInputs insumos({YieldCurve? curva, double? terminal}) =>
      ValuationInputs(
        ticker: Ticker.parse('PETR4'),
        asOf: hoje,
        fundamentals: const [],
        marketPrice: 30,
        capm: const CapmInputs(riskFreeRate: 0.12, beta: 1.1, marketPremium: 0.055),
        riskFreeCurve: curva,
        declaredTerminalRiskFreeRate: terminal,
      );

  test('desloca a corrente, a de equilíbrio declarada e a curva inteira', () {
    final d = insumos(curva: curvaPlana, terminal: 0.09).withRiskFreeShift(0.02);
    expect(d.capm.riskFreeRate, closeTo(0.14, 1e-12));
    expect(d.declaredTerminalRiskFreeRate, closeTo(0.11, 1e-12));
    // Curva plana deslocada continua plana: todo forward sobe o deslocamento.
    for (final f in d.riskFreeCurve!.annualForwards(10)) {
      expect(f, closeTo(0.12, 1e-12));
    }
    // Com curva, a perpetuidade é o forward dela, e ele também se desloca.
    expect(d.terminalRiskFreeRate, closeTo(0.12, 1e-12));
    // O resto não muda.
    expect(d.capm.beta, 1.1);
    expect(d.marketPrice, 30);
  });

  test('sem curva, a perpetuidade é a declarada deslocada', () {
    final d = insumos(terminal: 0.09).withRiskFreeShift(-0.03);
    expect(d.riskFreeCurve, isNull);
    expect(d.terminalRiskFreeRate, closeTo(0.06, 1e-12));
    expect(d.capm.riskFreeRate, closeTo(0.09, 1e-12));
  });

  test('taxa que ficaria negativa para no piso de 0,1%', () {
    final d = insumos(curva: curvaPlana, terminal: 0.09).withRiskFreeShift(-0.20);
    expect(d.capm.riskFreeRate, closeTo(0.001, 1e-12));
    expect(d.declaredTerminalRiskFreeRate, closeTo(0.001, 1e-12));
    expect(d.riskFreeCurve!.vertices.every((v) => (v.rate - 0.001).abs() < 1e-12),
        isTrue);
  });
}
