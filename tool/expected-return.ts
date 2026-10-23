// O retorno esperado da carteira e a âncora que faltava.
//
// **O defeito.** `ExpectedReturn.crossSection` estimava
// `E[R_i] = CDI + z_i·prêmio`, com `z` sendo o potencial padronizado
// robustamente. O ativo **mediano** da seção recebia exatamente o CDI — de
// modo que uma carteira de ações centrada na seção esperava a renda fixa, e o
// prêmio de risco aparecia só como dispersão, nunca como nível.
//
// **A correção.** A âncora passa a ser o custo de capital próprio do ativo:
// `E[R_i] = Ke_i + z_i·prêmio`. O mediano recebe `Rf + β_i·prêmio`, que é o
// retorno esperado incondicional dele.
//
// Uso:
//   npm run tool -- expected-return
import {
  compareNum,
  DateTime,
  ExpectedReturn,
  floor,
  intDiv,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  type Ticker,
  ValuationCascade,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = intDiv(s.length, 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number): string => `${(v * 100).toFixed(2)}%`;

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

    const valuations = new Map<Ticker, ValuationResult>();
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
      if (prep.isErr) continue;
      const r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isOk) valuations.set(ticker, r.unwrap());
    }
    process.stderr.write('\n');

    const upsides = new Map<Ticker, number>();
    const kes = new Map<Ticker, number>();
    for (const [t, v] of valuations) {
      upsides.set(t, v.upside);
      if (v.diagnostics !== null) kes.set(t, v.diagnostics.costOfEquity);
    }

    const withCdi = ExpectedReturn.crossSection({ upsides, spotRiskFree: anchors.currentRiskFreeRate });
    const withKe = ExpectedReturn.crossSection({ upsides, spotRiskFree: anchors.currentRiskFreeRate, costOfEquity: kes });

    const output = [...upsides.keys()].map((t) => ({
      ticker: t.value,
      potencial: upsides.get(t)!,
      custoDoCapitalProprio: kes.get(t) ?? null,
      esperadoNoCdi: withCdi.get(t)!.expected,
      esperadoNoKe: withKe.get(t)!.expected,
      z: withKe.get(t)!.z,
      ancoradoNoKe: withKe.get(t)!.anchoredOnCostOfEquity,
      pisado: withKe.get(t)!.floored,
    }));
    writeText('docs/validacao/retorno_esperado.json', jsonPretty(output));

    outln(`\n=== RETORNO ESPERADO TRANSVERSAL — ${upsides.size} ativos ===\n`);
    outln(`  CDI corrente: ${pc(anchors.currentRiskFreeRate)}`);
    const kesL = [...kes.values()];
    outln(`  custo do capital próprio: mediana=${pc(median(kesL)!)}  n=${kesL.length}`);

    for (const [label, field] of [
      ['âncora no CDI (antes)', 'esperadoNoCdi'],
      ['âncora no Ke (agora)', 'esperadoNoKe'],
    ] as const) {
      const v = output.map((e) => e[field]).sort(compareNum);
      outln(
        `  ${label.padEnd(24)} p10=${pc(v[floor(v.length * 0.1)]!)}  mediana=${pc(median(v)!)}  ` +
          `p90=${pc(v[floor(v.length * 0.9)]!)}`,
      );
    }

    const floored = output.filter((e) => e.pisado).length;
    outln(`  pisados em zero: ${floored}`);
    const withoutKe = output.filter((e) => !e.ancoradoNoKe).length;
    outln(`  sem Ke, ancorados no CDI: ${withoutKe}`);

    // O que isso faz com uma carteira igualmente ponderada do universo.
    const cdiMean = output.map((e) => e.esperadoNoCdi).reduce((a, b) => a + b) / output.length;
    const keMean = output.map((e) => e.esperadoNoKe).reduce((a, b) => a + b) / output.length;
    outln('\n-- carteira igualmente ponderada do universo --');
    outln(`  antes: ${pc(cdiMean)}   agora: ${pc(keMean)}   diferença: ${pc(keMean - cdiMean)}`);
    outln(
      `  o CDI é ${pc(anchors.currentRiskFreeRate)}: antes a carteira de ações esperava ` +
        `${cdiMean < anchors.currentRiskFreeRate ? 'MENOS' : 'mais'} que a renda fixa`,
    );

    errln('\nescrito docs/validacao/retorno_esperado.json');
  } finally {
    await ctx.dispose();
  }
}
