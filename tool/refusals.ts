// Por que o motor recusa o que recusa.
//
// A cobertura não é critério — a decisão 45 diz isso —, mas a **composição**
// das recusas é diagnóstico: um motivo que domina a lista é ou uma guarda
// necessária ou um defeito escondido atrás dela.
//
// Uso:
//   npm run tool -- refusals
import {
  compareNum,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  ValuationCascade,
} from '../src/core';
import { outln } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/** Agrupa a mensagem de recusa numa família estável. */
function family(m: string): string {
  if (m.includes('Lucro operacional base não positivo')) return 'lucro operacional base não positivo';
  if (m.includes('Lucro base não positivo')) return 'lucro base não positivo';
  if (m.includes('não sustenta a via da firma')) return 'estrutura de capital recusada';
  if (m.includes('capital próprio responde por apenas')) return 'ponte frágil e via do acionista inaplicável';
  if (m.includes('Preço de mercado')) return 'sem preço de mercado';
  if (m.includes('não sustentam nenhuma das duas vias')) return 'nenhuma via aplicável';
  if (m.includes('exercício')) return 'exercícios insuficientes';
  return m.length > 60 ? `${m.slice(0, 60)}…` : m;
}

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );
    const universe = (await ctx.fundamentals.universe()).unwrap();
    const prior = await ResolveBetaPrior.call({
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: today,
    });

    const byFamily = new Map<string, string[]>();
    let evaluated = 0;
    let withoutInput = 0;
    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);
      const prep = await PrepareValuationInputs.call({
        ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
        betaPrior: prior,
      });
      if (prep.isErr) {
        withoutInput++;
        continue;
      }
      const r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isOk) {
        evaluated++;
        continue;
      }
      const f = family(r.failureOrNull!.message);
      let list = byFamily.get(f);
      if (list === undefined) byFamily.set(f, (list = []));
      list.push(ticker.value);
    }
    process.stderr.write('\n');

    outln(`\n=== POR QUE O MOTOR RECUSA — ${universe.length} do universo ===\n`);
    outln(`  avaliados:            ${evaluated}`);
    outln(`  sem insumo suficiente: ${withoutInput}`);
    let total = 0;
    for (const xs of byFamily.values()) total += xs.length;
    outln(`  recusados na cascata:  ${total}\n`);
    const keys = [...byFamily.keys()].sort((a, b) => compareNum(byFamily.get(b)!.length, byFamily.get(a)!.length));
    for (const k of keys) {
      const xs = byFamily.get(k)!;
      outln(`  ${String(xs.length).padStart(4)}  ${k}`);
      outln(`        ${xs.slice(0, 10).join(', ')}${xs.length > 10 ? ', …' : ''}`);
    }
  } finally {
    await ctx.dispose();
  }
}
