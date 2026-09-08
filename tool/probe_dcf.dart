// Sondas isoladas sobre o DCF: medem hipóteses de defeito sem tocar em dados
// de produção. Cada bloco imprime a grandeza que decide a hipótese.
import 'package:equisim_core/equisim_core.dart';

String pct(double v) => '${(v * 100).toStringAsFixed(2)}%';

void main() {
  // Premissas típicas de um ativo do universo: WACC corrente de 17,4%,
  // terminal de 13,0%, crescimento de 10% decaindo para 6,86%, ROIC de 25%.
  const base = DcfAssumptions(
    projectionYears: 10,
    growthRate: 0.10,
    perpetualGrowth: 0.0686,
    discountRate: 0.174,
    terminalDiscountRate: 0.130,
    returnOnCapital: 0.25,
  );

  final o = DcfCalculator.firm(
    baseProfit: 1000.0,
    assumptions: base,
    netDebt: 0.0,
    sharesOutstanding: 1.0,
  ).unwrap();

  print('=== A) peso do valor terminal ===');
  print('EV = ${o.enterpriseValue.toStringAsFixed(2)}  '
      'VT descontado = ${o.discountedTerminalValue.toStringAsFixed(2)}  '
      'participação = ${pct(o.terminalShare)}');

  print('\n=== B) as bandas discretas movem o terminal? ===');
  final bandas = DiscreteScenarios.around(base);
  for (final e in bandas.scenarios.entries) {
    final a = e.value;
    final v = DcfCalculator.firm(
      baseProfit: 1000.0,
      assumptions: a,
      netDebt: 0.0,
      sharesOutstanding: 1.0,
    ).unwrap();
    print('${e.key.name.padRight(5)} r1=${pct(a.discountRate)} '
        'r_inf=${pct(a.terminalDiscountRate)} g=${pct(a.growthRate)} '
        '-> valor ${v.fairValuePerShare.toStringAsFixed(2)} '
        '(${((v.fairValuePerShare / o.fairValuePerShare - 1) * 100).toStringAsFixed(1)}% vs base)');
  }

  print('\n   contrafactual: deslocando também a taxa terminal');
  for (final d in [0.02, 0.0, -0.02]) {
    final a = base.copyWith(
      discountRate: base.discountRate + d,
      terminalDiscountRate: base.terminalDiscountRate + d,
      growthRate: base.growthRate - d * 1.5,
    );
    final v = DcfCalculator.firm(
      baseProfit: 1000.0,
      assumptions: a,
      netDebt: 0.0,
      sharesOutstanding: 1.0,
    ).unwrap();
    print('   delta=${pct(d)} -> valor ${v.fairValuePerShare.toStringAsFixed(2)} '
        '(${((v.fairValuePerShare / o.fairValuePerShare - 1) * 100).toStringAsFixed(1)}%)');
  }

  print('\n=== C) o rastro de auditoria reproduz o fluxo que a conta usa? ===');
  // O rastro escreve fluxo_t = F_0 (1+g)^t e desconto (1+r)^t, com g e r
  // constantes. A conta usa g_t e r_t decaindo, e ainda multiplica por (1-b_t).
  var fator = 1.0;
  for (var t = 1; t <= 10; t++) {
    fator *= 1 + base.discountRateAt(t);
  }
  final rastroFluxo10 = 1000.0 * _pow(1 + base.growthRate, 10);
  final rastroFator10 = _pow(1 + base.discountRate, 10);
  print('ano 10 — fluxo que a conta usa: ${o.projectedFlows[9].toStringAsFixed(2)}');
  print('ano 10 — fluxo que o rastro escreve: ${rastroFluxo10.toStringAsFixed(2)} '
      '(razão ${(rastroFluxo10 / o.projectedFlows[9]).toStringAsFixed(2)}x)');
  print('ano 10 — fator de desconto acumulado usado: ${fator.toStringAsFixed(4)}');
  print('ano 10 — fator que o rastro escreve: ${rastroFator10.toStringAsFixed(4)} '
      '(razão ${(rastroFator10 / fator).toStringAsFixed(2)}x)');

  print('\n=== D) retenção quando a base NÃO é normalizada ===');
  // Base = NOPAT corrente (ROIC de 7,8%), mas returnOnCapital = ROIC do ciclo
  // (19,5%). A retenção sai de 19,5% em vez de 7,8%.
  const azza = DcfAssumptions(
    projectionYears: 10,
    growthRate: 0.05,
    perpetualGrowth: 0.0686,
    discountRate: 0.1717,
    terminalDiscountRate: 0.1330,
    returnOnCapital: 0.1955,
  );
  final comCiclo = DcfCalculator.firm(
    baseProfit: 751.2,
    assumptions: azza,
    netDebt: 0,
    sharesOutstanding: 1,
  ).unwrap();
  final comAtual = DcfCalculator.firm(
    baseProfit: 751.2,
    assumptions: azza.copyWith(returnOnCapital: 0.0782),
    netDebt: 0,
    sharesOutstanding: 1,
  ).unwrap();
  print('retorno do ciclo (19,55%) -> EV ${comCiclo.enterpriseValue.toStringAsFixed(0)}');
  print('retorno corrente (7,82%) -> EV ${comAtual.enterpriseValue.toStringAsFixed(0)} '
      '(${((comAtual.enterpriseValue / comCiclo.enterpriseValue - 1) * 100).toStringAsFixed(1)}%)');

  print('\n=== E) sensibilidade do valor ao horizonte, tudo o mais igual ===');
  for (final n in [5, 10]) {
    final v = DcfCalculator.firm(
      baseProfit: 1000.0,
      assumptions: base.copyWith(projectionYears: n),
      netDebt: 0,
      sharesOutstanding: 1,
    ).unwrap();
    print('N=$n -> valor ${v.fairValuePerShare.toStringAsFixed(2)} '
        'terminal ${pct(v.terminalShare)}');
  }
}

double _pow(double b, int e) {
  var r = 1.0;
  for (var i = 0; i < e; i++) {
    r *= b;
  }
  return r;
}
