// A unit e a classe que a compõe têm de concordar.
//
// Uma unit é uma cesta de ações da mesma empresa. O potencial apurado para ela
// e o apurado para a classe que a compõe descrevem o mesmo negócio, e só podem
// divergir pelo ágio entre ON e PN dentro da cesta — nunca por uma ordem de
// grandeza. **É o teste que nenhuma peça isolada faz**: a razão de unidade só
// se verifica confrontando dois tickers.
//
// Uso:
//   npm run tool -- unit-vs-class
import {
  compareStr,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  type Ticker,
  ValuationCascade,
} from '../src/core';
import { outln } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );
    const universe = (await ctx.fundamentals.universe()).unwrap();

    // Agrupa por raiz de quatro letras.
    const byRoot = new Map<string, Ticker[]>();
    for (const t of universe) {
      const root = t.value.length >= 4 ? t.value.slice(0, 4) : t.value;
      let list = byRoot.get(root);
      if (list === undefined) byRoot.set(root, (list = []));
      list.push(t);
    }
    const withUnit = new Map<string, Ticker[]>();
    for (const [root, list] of byRoot) {
      if (list.some((t) => t.value.endsWith('11')) && list.length > 1) withUnit.set(root, list);
    }

    const cache = new Map<Ticker, number | null>();
    const upside = async (t: Ticker): Promise<number | null> => {
      if (cache.has(t)) return cache.get(t)!;
      const prep = await PrepareValuationInputs.call({
        ticker: t,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      });
      let v: number | null = null;
      if (prep.isOk) {
        const r = ValuationCascade.evaluate(prep.unwrap());
        if (r.isOk) v = r.unwrap().upside;
      }
      cache.set(t, v);
      return v;
    };

    outln(`== ${withUnit.size} raízes com unit e ao menos outra classe ==\n`);
    let largestGap = 0.0;
    let worst: string | null = null;
    for (const root of [...withUnit.keys()].sort(compareStr)) {
      const tickers = withUnit.get(root)!.sort((a, b) => a.compareTo(b));
      const unit = tickers.find((t) => t.value.endsWith('11'))!;
      const unitUpside = await upside(unit);
      let row = `  ${root}: `;
      for (const t of tickers) {
        const p = await upside(t);
        row += `${t.value}=${p === null ? '—' : `${(p * 100).toFixed(1)}%`}  `;
      }
      if (unitUpside !== null) {
        for (const t of tickers) {
          if (t === unit) continue;
          const p = await upside(t);
          if (p === null) continue;
          const gap = Math.abs(p - unitUpside);
          if (gap > largestGap) {
            largestGap = gap;
            worst = `${root} (${t.value} contra ${unit.value})`;
          }
        }
      }
      outln(row.trimEnd());
    }
    outln(`\n  maior distância unit↔classe: ${(largestGap * 100).toFixed(1)} p.p. em ${worst ?? '—'}`);
  } finally {
    await ctx.dispose();
  }
}
