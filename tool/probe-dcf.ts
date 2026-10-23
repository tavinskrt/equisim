// Sondas isoladas sobre o DCF: medem hipóteses de defeito sem tocar em dados
// de produção. Cada bloco imprime a grandeza que decide a hipótese.
import { DcfAssumptions, DcfCalculator, DiscreteScenarios } from '../src/core';
import { outln } from './lib/files';

const pct = (v: number): string => `${(v * 100).toFixed(2)}%`;

export function main(_args: string[]): void {
  // Premissas típicas de um ativo do universo: WACC corrente de 17,4%,
  // terminal de 13,0%, crescimento de 10% decaindo para 6,86%, ROIC de 25%.
  const base = new DcfAssumptions({
    projectionYears: 10,
    growthRate: 0.1,
    perpetualGrowth: 0.0686,
    discountRate: 0.174,
    terminalDiscountRate: 0.13,
    returnOnCapital: 0.25,
  });

  const o = DcfCalculator.firm({ baseProfit: 1000.0, assumptions: base, netDebt: 0.0, sharesOutstanding: 1.0 }).unwrap();

  outln('=== A) peso do valor terminal ===');
  outln(
    `EV = ${o.enterpriseValue.toFixed(2)}  VT descontado = ${o.discountedTerminalValue.toFixed(2)}  ` +
      `participação = ${pct(o.terminalShare)}`,
  );

  outln('\n=== B) as bandas discretas movem o terminal? ===');
  const bands = DiscreteScenarios.around(base);
  for (const [band, a] of bands.scenarios) {
    const v = DcfCalculator.firm({ baseProfit: 1000.0, assumptions: a, netDebt: 0.0, sharesOutstanding: 1.0 }).unwrap();
    outln(
      `${band.name.padEnd(5)} r1=${pct(a.discountRate)} r_inf=${pct(a.terminalDiscountRate)} g=${pct(a.growthRate)} ` +
        `-> valor ${v.fairValuePerShare.toFixed(2)} (${((v.fairValuePerShare / o.fairValuePerShare - 1) * 100).toFixed(1)}% vs base)`,
    );
  }

  outln('\n   contrafactual: deslocando também a taxa terminal');
  for (const d of [0.02, 0.0, -0.02]) {
    const a = base.copyWith({
      discountRate: base.discountRate + d,
      terminalDiscountRate: base.terminalDiscountRate + d,
      growthRate: base.growthRate - d * 1.5,
    });
    const v = DcfCalculator.firm({ baseProfit: 1000.0, assumptions: a, netDebt: 0.0, sharesOutstanding: 1.0 }).unwrap();
    outln(
      `   delta=${pct(d)} -> valor ${v.fairValuePerShare.toFixed(2)} ` +
        `(${((v.fairValuePerShare / o.fairValuePerShare - 1) * 100).toFixed(1)}%)`,
    );
  }

  outln('\n=== C) o rastro de auditoria reproduz o fluxo que a conta usa? ===');
  // O rastro escreve fluxo_t = F_0 (1+g)^t e desconto (1+r)^t, com g e r
  // constantes. A conta usa g_t e r_t decaindo, e ainda multiplica por (1-b_t).
  let factor = 1.0;
  for (let t = 1; t <= 10; t++) factor *= 1 + base.discountRateAt(t);
  const traceFlow10 = 1000.0 * repeatedProduct(1 + base.growthRate, 10);
  const traceFactor10 = repeatedProduct(1 + base.discountRate, 10);
  const flow10 = o.projectedFlows[9]!;
  outln(`ano 10 — fluxo que a conta usa: ${flow10.toFixed(2)}`);
  outln(`ano 10 — fluxo que o rastro escreve: ${traceFlow10.toFixed(2)} (razão ${(traceFlow10 / flow10).toFixed(2)}x)`);
  outln(`ano 10 — fator de desconto acumulado usado: ${factor.toFixed(4)}`);
  outln(`ano 10 — fator que o rastro escreve: ${traceFactor10.toFixed(4)} (razão ${(traceFactor10 / factor).toFixed(2)}x)`);

  outln('\n=== D) retenção quando a base NÃO é normalizada ===');
  // Base = NOPAT corrente (ROIC de 7,8%), mas returnOnCapital = ROIC do ciclo
  // (19,5%). A retenção sai de 19,5% em vez de 7,8%.
  const azza = new DcfAssumptions({
    projectionYears: 10,
    growthRate: 0.05,
    perpetualGrowth: 0.0686,
    discountRate: 0.1717,
    terminalDiscountRate: 0.133,
    returnOnCapital: 0.1955,
  });
  const withCycle = DcfCalculator.firm({ baseProfit: 751.2, assumptions: azza, netDebt: 0, sharesOutstanding: 1 }).unwrap();
  const withCurrent = DcfCalculator.firm({
    baseProfit: 751.2,
    assumptions: azza.copyWith({ returnOnCapital: 0.0782 }),
    netDebt: 0,
    sharesOutstanding: 1,
  }).unwrap();
  outln(`retorno do ciclo (19,55%) -> EV ${withCycle.enterpriseValue.toFixed(0)}`);
  outln(
    `retorno corrente (7,82%) -> EV ${withCurrent.enterpriseValue.toFixed(0)} ` +
      `(${((withCurrent.enterpriseValue / withCycle.enterpriseValue - 1) * 100).toFixed(1)}%)`,
  );

  outln('\n=== E) sensibilidade do valor ao horizonte, tudo o mais igual ===');
  for (const n of [5, 10]) {
    const v = DcfCalculator.firm({
      baseProfit: 1000.0,
      assumptions: base.copyWith({ projectionYears: n }),
      netDebt: 0,
      sharesOutstanding: 1,
    }).unwrap();
    outln(`N=${n} -> valor ${v.fairValuePerShare.toFixed(2)} terminal ${pct(v.terminalShare)}`);
  }
}

/** Potência por multiplicação repetida, como o rastro a escreve. */
function repeatedProduct(b: number, e: number): number {
  let r = 1.0;
  for (let i = 0; i < e; i++) r *= b;
  return r;
}
