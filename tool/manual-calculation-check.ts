// Conferência do cálculo do usuário sobre o universo inteiro (decisão 147).
//
// **A promessa.** O botão "Editar valuation" abre a conta do motor congelada, e
// o usuário a refaz com os números dele. Duas coisas precisam ser verdade em
// cada ativo avaliado, e não só nos casos que os testes do núcleo montam:
//
// 1. **Sem nenhuma troca, o preço é o do motor** — igualdade exata, e o mesmo
//    centavo que a tela mostra.
// 2. **A conta responde como a teoria manda**: taxa mais alta dá preço mais
//    baixo; a decomposição de "onde você discorda" soma a diferença inteira; e
//    a taxa que "o preço de hoje supõe", quando existe, devolve o preço de
//    mercado.
//
// Roda sobre a entrada congelada de 14/09/2026, na montagem do aplicativo — a
// mesma do gabarito.
//
// Uso:
//   npm run tool -- manual-calculation-check
//   npm run tool -- manual-calculation-check --exemplo WEGE3
//
// Sai com código 1 quando alguma propriedade falha, e lista os ativos. Com
// `--exemplo`, imprime também o caso de um ativo — o preço do motor, o efeito
// de trocar cada campo e o que o preço de hoje supõe —, que é de onde saem os
// números do guia de estudo (capítulo 4, seção 4.16).

import {
  ManualField,
  type ManualPremises,
  ManualRatePath,
  type ManualValuation,
  Money,
  str,
  type Ticker,
  toStringAsExponential,
  ValuationCascade,
  ValuationLane,
} from '../src/core';
import { flagValue, outln } from './lib/files';
import { Frozen } from './validation/frozen';

export async function main(args: string[]): Promise<void> {
  const example = flagValue(args, '--exemplo');
  const c = await Frozen.build();
  let evaluated = 0;
  let firm = 0;
  let shareholder = 0;
  let withSolution = 0;
  let withoutSolution = 0;
  let largestReverseDeviation = 0.0;
  const failures: string[] = [];

  for (const t of c.universe) {
    const prep = await c.prepare(t);
    if (prep.isErr) continue;
    const r = ValuationCascade.evaluate(prep.unwrap());
    if (r.isErr) continue;
    const res = r.unwrap();
    evaluated++;
    const m = res.manual;
    if (m === null) {
      failures.push(`${t.value}: avaliado sem a conta congelada`);
      continue;
    }
    if (m.lane === ValuationLane.firm) {
      firm++;
    } else {
      shareholder++;
    }
    const p = m.enginePremises;
    if (example === t.value) printExample(t, m);

    // 1. Sem troca, o preço do motor.
    const without = m.evaluate(p);
    if (without.isErr) {
      failures.push(`${t.value}: sem troca, a conta recusou — ${without.failureOrNull!.message}`);
      continue;
    }
    const yours = without.unwrap().fairValuePerShare;
    if (yours !== m.engineFairValue) {
      failures.push(`${t.value}: sem troca, ${str(yours)} contra ${str(m.engineFairValue)} do motor`);
    }
    if (!Money.fromReais(yours).equals(res.fairValue)) {
      failures.push(`${t.value}: sem troca, ${Money.fromReais(yours)} contra ${res.fairValue} na tela`);
    }

    // 2a. Taxa mais alta, preço mais baixo.
    const high = m.evaluate(p.copyWith({ discountRate: p.discountRate + 0.01 }));
    if (high.isOk && high.unwrap().fairValuePerShare >= yours) {
      failures.push(`${t.value}: +1 p.p. de taxa não baixou o preço`);
    }

    // 2b. A decomposição soma a diferença inteira.
    const swapped = p.copyWith({
      baseProfit: p.baseProfit * 1.1,
      growth: p.growth + 0.01,
      discountRate: p.discountRate - 0.005,
    });
    const swappedResult = m.evaluate(swapped);
    if (swappedResult.isOk) {
      const steps = m.attribution(swapped);
      const sum = steps.reduce((s, d) => s + (d.delta ?? Number.NaN), 0.0);
      const target = swappedResult.unwrap().fairValuePerShare - m.engineFairValue;
      if (!(Math.abs(sum - target) <= 1e-6 * (1 + Math.abs(target)))) {
        failures.push(`${t.value}: degraus somam ${str(sum)}, a diferença é ${str(target)}`);
      }
    }

    // 2c. A taxa que o preço de hoje supõe devolve o preço de mercado.
    const s = m.solve(ManualField.discountRate, p);
    const v = s.value;
    if (v === null) {
      withoutSolution++;
    } else {
      withSolution++;
      const price = m.evaluate(p.copyWith({ discountRate: v }));
      const d = price.isOk ? Math.abs(price.unwrap().fairValuePerShare - m.marketPrice) : Number.POSITIVE_INFINITY;
      if (d > largestReverseDeviation) largestReverseDeviation = d;
      if (d > 0.005) {
        failures.push(`${t.value}: a taxa de ${(v * 100).toFixed(2)}% dá preço a ${str(d)} do de mercado`);
      }
    }
  }

  outln(`ativos avaliados: ${evaluated} (${firm} pela via da firma, ${shareholder} pela do acionista)`);
  outln(
    `a taxa que o preço de hoje supõe: ${withSolution} com solução, ${withoutSolution} sem; maior desvio do preço de mercado: ` +
      `R$ ${toStringAsExponential(largestReverseDeviation, 2)}`,
  );
  if (failures.length === 0) {
    outln('CONTA DO USUÁRIO CONFERIDA: sem troca, o preço do motor em todos os ativos, ao centavo e bit a bit.');
    process.exit(0);
  }
  outln(`FALHAS (${failures.length}):`);
  for (const f of failures) outln(`  ${f}`);
  process.exit(1);
}

const pct = (v: number): string => `${(v * 100).toFixed(2)}%`;
const rs = (v: number): string => `R$ ${v.toFixed(2)}`;
const inMillions = (v: number): string => `R$ ${(v / 1e6).toFixed(1)} mi`;

/** O caso de um ativo, para o guia de estudo. */
function printExample(t: Ticker, m: ManualValuation): void {
  const p = m.enginePremises;
  const price = (x: ManualPremises): number => m.evaluate(x).valueOrNull?.fairValuePerShare ?? Number.NaN;
  const o = m.evaluate(p).unwrap();
  outln(`--- exemplo ${t.value} (${m.lane.name}) ---`);
  outln(`preço de mercado ${rs(m.marketPrice)}; motor ${rs(m.engineFairValue)}`);
  outln(
    `lucro de partida ${inMillions(p.baseProfit)}` +
      `${m.publishedBase === null ? '' : ` (último exercício ${inMillions(m.publishedBase)})`}; ` +
      `crescimento ${pct(p.growth)}; taxa ${pct(p.discountRate)} no ano 1 e ${pct(m.engineTerminalRate)} na perpetuidade; ` +
      `perpetuidade ${pct(p.perpetualGrowth)}; retorno ${pct(p.returnOnCapital)}; ` +
      `capital novo ${p.terminalReturn === null ? 'igual à taxa' : pct(p.terminalReturn)}`,
  );
  outln(
    `VP dos 10 anos ${inMillions(o.explicitPresentValue)}; VP da perpetuidade ${inMillions(o.terminalPresentValue)}; ` +
      `patrimônio ${inMillions(o.equityValue)}; ações ${(m.shares / 1e6).toFixed(1)} mi`,
  );
  outln(
    `taxa −1 p.p.: ${rs(price(p.copyWith({ discountRate: p.discountRate - 0.01 })))}; ` +
      `+1 p.p.: ${rs(price(p.copyWith({ discountRate: p.discountRate + 0.01 })))}`,
  );
  outln(`taxa constante de ${pct(p.discountRate)}: ${rs(price(p.copyWith({ ratePath: ManualRatePath.constant })))}`);
  outln(
    `crescimento +2 p.p.: ${rs(price(p.copyWith({ growth: p.growth + 0.02 })))}; lucro do último exercício: ` +
      `${m.publishedBase === null ? '—' : rs(price(p.copyWith({ baseProfit: m.publishedBase })))}`,
  );
  outln(`capital novo rendendo a taxa + 5 p.p.: ${rs(price(p.copyWith({ terminalReturn: m.engineTerminalRate + 0.05 })))}`);
  for (const f of [ManualField.discountRate, ManualField.growth, ManualField.baseProfit]) {
    const s = m.solve(f, p);
    const v = s.value;
    outln(`o preço de hoje supõe ${f.name} = ${v === null ? 'sem solução' : f === ManualField.baseProfit ? inMillions(v) : pct(v)}`);
  }
}
