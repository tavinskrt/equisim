// O beta e a negociação não síncrona.
//
// **O defeito apontado.** O beta sai de regressão de retorno **diário** contra
// o Ibovespa. Ativo que não negocia todo dia responde ao mercado com atraso: o
// retorno dele hoje carrega parte da informação de ontem, e a covariância
// contemporânea perde essa parte. O viés é conhecido e tem direção — **para
// baixo** —, e a correção clássica é a de Dimson: somar as inclinações contra
// o mercado defasado, contemporâneo e adiantado.
//
// **A outra metade do apontamento está bloqueada por dado.** Retorno sobre
// cotação "suja" — não ajustada por provento — só se corrige com a série de
// retorno total da fonte, e a [limitação 1.2](../docs/validacao/limitacoes.md)
// mediu que ela é inutilizável: desvio mediano de 9,1% contra o fluxo de
// proventos publicado, máximo de 38,5%.
//
// **O que isto mede.** Três estimadores no mesmo ativo, na mesma janela:
// diário contemporâneo (o de produção), semanal, e Dimson com uma defasagem e
// uma antecipação.
//
// Uso:
//   npm run tool -- beta-synchrony
import { existsSync, readFileSync } from 'node:fs';

import { BetaCalculator, compareNum, DateRange, DateTime, intDiv, PrepareValuationInputs } from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';
import { Regression } from './validation/regression';

const today = DateTime.local(2026, 9, 4);

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number): string => `${(v * 100).toFixed(1)}%`;

const millisecondsPerDay = 86_400_000;

/**
 * Reduz a série ao **último pregão de cada semana**.
 *
 * Semana pela data ISO — segunda a domingo —, de modo que feriado no meio não
 * desloca a contagem. O que interessa é ter um ponto por semana com o mesmo
 * corte nos dois lados da regressão.
 */
function weekly(dates: readonly DateTime[], closes: readonly number[]): { date: DateTime; close: number }[] {
  const byWeek = new Map<number, { date: DateTime; close: number }>();
  for (let i = 0; i < dates.length; i++) {
    const d = dates[i]!;
    // Chave da semana: dias desde a época, divididos por sete, alinhados à
    // segunda-feira. Em UTC, para não depender de horário de verão.
    const days = intDiv(DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch, millisecondsPerDay);
    const week = intDiv(days + 3, 7); // 1970-01-01 foi quinta
    const current = byWeek.get(week);
    if (current === undefined || d.isAfter(current.date)) byWeek.set(week, { date: d, close: closes[i]! });
  }
  return [...byWeek.keys()].sort(compareNum).map((k) => byWeek.get(k)!);
}

/** Raiz quadrada por Newton, como a medição original fazia. */
function root(x: number): number {
  if (x <= 0) return 0;
  let r = x;
  for (let i = 0; i < 60; i++) r = 0.5 * (r + x / r);
  return r;
}

interface Row {
  ticker: string;
  pregoes: number;
  pregoesPorAno: number;
  betaDiario: number;
  seDiario: number | null;
  betaSemanal: number | null;
  seSemanal: number | null;
  obsSemanal: number;
  betaDimson: number | null;
  seDimson: number | null;
}

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const universe = (await ctx.fundamentals.universe()).unwrap();
    const window = new DateRange(DateTime.local(today.year - PrepareValuationInputs.betaWindowYears, today.month, today.day), today);
    const indexResult = await ctx.benchmark.ibovespa(window);
    if (indexResult.isErr) {
      errln(`sem índice: ${indexResult.failureOrNull?.message ?? null}`);
      return;
    }
    const index = indexResult.unwrap();
    const indexCloses = index.points.map((p) => p.close);

    // **Só os que o motor avalia.** O universo cru tem ativo que negocia vinte
    // pregões por ano, e neles o beta diário não é estimador ruim — é ruído.
    // A Porta 0 já os barra, e medir o viés fora dela mede outra coisa.
    const evaluable = new Set<string>();
    const report = 'docs/validacao/fluxo_explicito.json';
    if (existsSync(report)) {
      for (const e of JSON.parse(readFileSync(report, 'utf8')) as { ticker: string }[]) evaluable.add(e.ticker);
    }
    errln(`avaliáveis: ${evaluable.size}`);

    const output: Row[] = [];
    let i = 0;
    for (const ticker of universe) {
      if (evaluable.size > 0 && !evaluable.has(ticker.value)) continue;
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);
      const seriesResult = await ctx.prices.daily(ticker, window);
      if (seriesResult.isErr) continue;
      const points = seriesResult.unwrap().points.filter((p) => window.contains(p.date));
      if (points.length < 60) continue;

      // --- Diário contemporâneo: o estimador de produção -------------------
      const pair = BetaCalculator.alignReturns({
        assetDates: points.map((p) => p.date),
        assetIndex: points.map((p) => p.close),
        marketDates: index.dates,
        marketIndex: indexCloses,
      });
      const daily = BetaCalculator.estimate({ returns: pair });
      if (daily.isErr) continue;

      // --- Semanal ---------------------------------------------------------
      const assetWeekly = weekly(
        points.map((p) => p.date),
        points.map((p) => p.close),
      );
      const marketWeekly = weekly(index.dates, indexCloses);
      const weeklyPair = BetaCalculator.alignReturns({
        assetDates: assetWeekly.map((p) => p.date),
        assetIndex: assetWeekly.map((p) => p.close),
        marketDates: marketWeekly.map((p) => p.date),
        marketIndex: marketWeekly.map((p) => p.close),
      });
      const weeklyBeta = BetaCalculator.estimate({ returns: weeklyPair });

      // --- Dimson: defasado, contemporâneo e adiantado ---------------------
      //
      // `β = β₋₁ + β₀ + β₊₁`, das inclinações de uma regressão múltipla. É a
      // correção clássica para negociação não síncrona.
      let dimson: number | null = null;
      let dimsonSe: number | null = null;
      const ra = pair.asset;
      const rm = pair.market;
      if (ra.length >= 40) {
        const n = ra.length;
        const y: number[] = [];
        const x0: number[] = [];
        const xMinus: number[] = [];
        const xPlus: number[] = [];
        for (let t = 1; t < n - 1; t++) {
          y.push(ra[t]!);
          x0.push(rm[t]!);
          xMinus.push(rm[t - 1]!);
          xPlus.push(rm[t + 1]!);
        }
        const ols = Regression.ols([xMinus, x0, xPlus], y);
        if (ols !== null) {
          dimson = ols.coefficients[1]! + ols.coefficients[2]! + ols.coefficients[3]!;
          // Erro-padrão da soma, ignorando a covariância entre coeficientes:
          // é cota inferior, e serve para ordem de grandeza.
          let sum = 0.0;
          for (let k = 1; k <= 3; k++) sum += ols.stdErrors[k]! * ols.stdErrors[k]!;
          dimsonSe = root(sum);
        }
      }

      const d = daily.unwrap();
      output.push({
        ticker: ticker.value,
        pregoes: points.length,
        pregoesPorAno: points.length / PrepareValuationInputs.betaWindowYears,
        betaDiario: d.beta,
        seDiario: d.standardError,
        betaSemanal: weeklyBeta.isOk ? weeklyBeta.unwrap().beta : null,
        seSemanal: weeklyBeta.isOk ? weeklyBeta.unwrap().standardError : null,
        obsSemanal: weeklyPair.asset.length,
        betaDimson: dimson,
        seDimson: dimsonSe,
      });
    }
    errln('');

    writeText('docs/validacao/beta_sincronia.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/beta_sincronia.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  outln(`\n=== BETA E NEGOCIAÇÃO NÃO SÍNCRONA — ${l.length} ===\n`);

  const col = (k: 'seDiario' | 'seSemanal' | 'seDimson'): number[] =>
    l.map((e) => e[k]).filter((v): v is number => v !== null && Number.isFinite(v));

  for (const [label, key] of [
    ['semanal ÷ diário', 'betaSemanal'],
    ['Dimson ÷ diário', 'betaDimson'],
  ] as const) {
    const ratios: number[] = [];
    for (const e of l) {
      const a = e.betaDiario;
      const b = e[key];
      if (b === null || Math.abs(a) < 1e-9) continue;
      ratios.push(b / a);
    }
    if (ratios.length === 0) continue;
    ratios.sort(compareNum);
    outln(`-- ${label} --`);
    outln(
      `  p10=${ratios[Math.floor(ratios.length * 0.1)]!.toFixed(3)}  mediana=${median(ratios)!.toFixed(3)}  ` +
        `p90=${ratios[Math.floor(ratios.length * 0.9)]!.toFixed(3)}`,
    );
    outln(`  maior que o diário em ${ratios.filter((x) => x > 1).length} de ${ratios.length}  (acima de 1,10: ${ratios.filter((x) => x > 1.1).length})`);
  }

  const seDaily = col('seDiario');
  const seWeekly = col('seSemanal');
  const seDimson = col('seDimson');
  outln('\n-- erro-padrão de cada estimador --');
  if (seDaily.length > 0) outln(`  diário:  mediana=${median(seDaily)!.toFixed(4)}`);
  if (seWeekly.length > 0) outln(`  semanal: mediana=${median(seWeekly)!.toFixed(4)}`);
  if (seDimson.length > 0) outln(`  Dimson:  mediana=${median(seDimson)!.toFixed(4)}`);

  // A hipótese: o viés é dos que negociam menos.
  const byLiquidity = [...l].sort((a, b) => compareNum(a.pregoesPorAno, b.pregoesPorAno));
  outln('\n-- o viés é dos que negociam menos? --');
  const half = Math.floor(byLiquidity.length / 2);
  for (const [label, group] of [
    ['menos pregões', byLiquidity.slice(0, half)],
    ['mais pregões', byLiquidity.slice(half)],
  ] as const) {
    const ratios: number[] = [];
    for (const e of group) {
      const a = e.betaDiario;
      const b = e.betaDimson;
      if (b === null || Math.abs(a) < 1e-9) continue;
      ratios.push(b / a);
    }
    if (ratios.length === 0) continue;
    const tradingDays = group.map((e) => e.pregoesPorAno);
    outln(`  ${label.padEnd(16)} pregões/ano mediano=${median(tradingDays)!.toFixed(0)}  Dimson÷diário mediano=${median(ratios)!.toFixed(3)}`);
  }

  const ord = [...l].sort((a, b) => compareNum((b.betaDimson ?? 0) / b.betaDiario, (a.betaDimson ?? 0) / a.betaDiario));
  outln('\n-- onde Dimson mais eleva o beta --');
  outln(`  ${'ativo'.padEnd(8)}${'diário'.padStart(9)}${'semanal'.padStart(9)}${'Dimson'.padStart(9)}${'pregões'.padStart(9)}`);
  for (const e of ord.slice(0, 8)) {
    const f = (v: number | null): string => (v === null ? '—' : v.toFixed(3));
    outln(
      `  ${e.ticker.padEnd(8)}${f(e.betaDiario).padStart(9)}${f(e.betaSemanal).padStart(9)}` +
        `${f(e.betaDimson).padStart(9)}${e.pregoesPorAno.toFixed(0).padStart(9)}`,
    );
  }
  outln(
    `\n  (a metade "cotação suja" do apontamento está bloqueada pela limitação 1.2: ${pc(0.091)} de desvio mediano na série de retorno total da fonte)`,
  );
}
