// A2 — a curva de juros observada ligada ao motor, e o que ela move.
//
// Avalia o universo duas vezes na mesma data, com os mesmos fundamentos da
// fonte de mercado — para isolar o efeito da curva do efeito da CVM:
//
//   dois pontos  CDI corrente decaindo até a média decenal do CDI (antes)
//   curva        forwards de um ano da curva prefixada do Tesouro (A2)
//
// Uso:
//   python tool/tesouro_baixar.py
//   npm run tool -- curve-link [AAAA-MM-DD]
import { existsSync, writeFileSync } from 'node:fs';

import {
  compareNum,
  DateTime,
  intDiv,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  type Ticker,
  TreasuryCsv,
  TreasuryCurve,
  type TreasuryQuote,
  ValuationCascade,
  type ValuationResult,
  type YieldCurve,
} from '../src/core';
import { errln, fail, jsonPretty, outln, readLatin1, splitLines } from './lib/files';
import { ValidationContext } from './validation/context';

/**
 * Lê o CSV do Tesouro Direto pelo leitor do núcleo (`TreasuryCsv`), o mesmo
 * que o aplicativo e o empacotador usam.
 */
export function readTreasury(path: string): TreasuryQuote[] {
  if (!existsSync(path)) fail(`${path} não existe. Rode: python tool/tesouro_baixar.py`);
  return TreasuryCsv.parse(splitLines(readLatin1(path)));
}

function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = intDiv(s.length, 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function spearman(a: readonly number[], b: readonly number[]): number {
  const ranks = (v: readonly number[]) => {
    const idx = Array.from({ length: v.length }, (_, i) => i).sort((x, y) => compareNum(v[x]!, v[y]!));
    const r = new Array<number>(v.length).fill(0);
    for (let k = 0; k < idx.length; k++) r[idx[k]!] = k + 1.0;
    return r;
  };

  const ranksA = ranks(a);
  const ranksB = ranks(b);
  const meanA = ranksA.reduce((x, y) => x + y) / ranksA.length;
  const meanB = ranksB.reduce((x, y) => x + y) / ranksB.length;
  let n = 0;
  let sumSqA = 0;
  let sumSqB = 0;
  for (let i = 0; i < ranksA.length; i++) {
    n += (ranksA[i]! - meanA) * (ranksB[i]! - meanB);
    sumSqA += (ranksA[i]! - meanA) * (ranksA[i]! - meanA);
    sumSqB += (ranksB[i]! - meanB) * (ranksB[i]! - meanB);
  }
  // Sem variância numa das duas não há correlação a medir.
  if (!(sumSqA > 0 && sumSqB > 0)) return 0;
  return n / Math.sqrt(sumSqA * sumSqB);
}

const pc = (v: number | null | undefined) => (v === null || v === undefined ? '—' : `${(v * 100).toFixed(1)}%`);

export async function main(args: string[]): Promise<void> {
  const today = args.length === 0 ? DateTime.local(2026, 9, 4) : DateTime.parse(args[0]!);
  const quotes = readTreasury('data/tesouro/precotaxatesourodireto.csv');
  const curve = TreasuryCurve.at(quotes, today);
  if (curve === null) fail(`sem curva do Tesouro na semana de ${today}`);

  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    outln(`== A2 — avaliação em ${today.toIso8601String().slice(0, 10)} ==\n`);
    outln(
      `  curva de ${curve.referenceDate.toIso8601String().slice(0, 10)}, ${curve.vertices.length} vértices até ` +
        `${curve.vertices[curve.vertices.length - 1]!.years.toFixed(1)} anos`,
    );
    const fw = curve.annualForwards(10);
    outln(`  forwards anuais: ${fw.map(pc).join(' ')}`);
    outln(`  perpetuidade pela curva: ${pc(curve.terminalRate(10))}`);
    outln(`  motor de dois pontos: ${pc(anchors.currentRiskFreeRate)} → ${pc(anchors.riskFreeCagr)}\n`);

    const universe = (await ctx.fundamentals.universe()).unwrap();
    const evaluate = async (t: Ticker, c?: YieldCurve): Promise<ValuationResult | null> => {
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
        riskFreeCurve: c ?? null,
        projectionYears: 10,
      });
      if (prep.isErr) return null;
      const r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    };

    const rows: Record<string, unknown>[] = [];
    let i = 0;
    for (const t of universe) {
      if (++i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);
      const a = await evaluate(t);
      const b = await evaluate(t, curve);
      if (a === null && b === null) continue;
      rows.push({
        ticker: t.value,
        doisPontos: a?.upside ?? null,
        curva: b?.upside ?? null,
        pesoTerminal: b?.diagnostics?.terminalShare ?? null,
      });
    }
    errln('');

    const both = rows.filter((l) => l['doisPontos'] !== null && l['curva'] !== null);
    const before = both.map((l) => l['doisPontos'] as number);
    const after = both.map((l) => l['curva'] as number);
    outln(`  avaliados: ${rows.filter((l) => l['doisPontos'] !== null).length} → ${rows.filter((l) => l['curva'] !== null).length}`);
    outln(`  perdidos: ${rows.filter((l) => l['doisPontos'] !== null && l['curva'] === null).map((l) => l['ticker']).join(' ')}`);
    outln(`  ganhos: ${rows.filter((l) => l['doisPontos'] === null && l['curva'] !== null).map((l) => l['ticker']).join(' ')}`);
    outln(`  potencial mediano: ${pc(median(before))} → ${pc(median(after))}`);
    outln(
      `  fração com potencial positivo: ${pc(before.length === 0 ? null : before.filter((x) => x > 0).length / before.length)} → ` +
        `${pc(after.length === 0 ? null : after.filter((x) => x > 0).length / after.length)}`,
    );
    outln(`  mediana do Δ: ${pc(median(both.map((_, k) => after[k]! - before[k]!)))}`);
    outln(`  Spearman entre as duas ordenações: ${spearman(before, after).toFixed(4)}`);

    writeFileSync(`docs/validacao/curva_ligacao_${today.toIso8601String().slice(0, 10)}.json`, jsonPretty(rows));
  } finally {
    await ctx.dispose();
  }
}
