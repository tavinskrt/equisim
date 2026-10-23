// A4 — os proventos da B3 conferidos, e o retorno total nas coortes.
//
// Quatro perguntas, sobre os 297 emissores do universo:
//
//   1. unidade e data  o fechamento com direito que a B3 publica bate com o
//                      COTAHIST no mesmo dia?
//   2. data ex         o preço cai na data ex, e cai na ordem do provento?
//   3. adjustedClose   o ajuste da fonte de preços corresponde aos proventos da
//                      B3? É a medição da §1.2 das limitações — desvio de 9,1%
//                      em 2026-08 contra o fluxo da própria fonte —, agora com
//                      fonte independente.
//   4. coortes         quanto o retorno total difere do de preço nas coortes de
//                      `backtest_valuation.json`, e o que muda na habilidade.
//
// Grava `docs/validacao/proventos.json` e, para a regressão condicional, uma
// cópia das coortes com `ret12tot` e `ret36tot` em
// `docs/validacao/backtest_valuation_total.json`.
//
// Uso:
//   python tool/b3_complemento_baixar.py
//   npm run tool -- dividends-check
import { existsSync } from 'node:fs';

import { compareNum, compareStr, DateRange, DateTime, intDiv, round, Ticker, TotalReturn } from '../src/core';
import { dividendsOf, readDividends, readRawCotahist, tradingDayFrom, tradingDayUntil } from './b3/dividends';
import { errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = intDiv(s.length, 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function quantile(v: readonly number[], q: number): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  return s[round((s.length - 1) * q)]!;
}

const pc = (v: number | null, decimals = 1): string => (v === null ? '—' : `${(v * 100).toFixed(decimals)}%`);

interface Adjustment {
  ticker: string;
  proventos: number;
  semPreco: number;
  observado: number;
  implicitoB3: number;
  desvio: number;
}

export async function main(_args: string[]): Promise<void> {
  const dividends = readDividends();
  const universe = new Set(readJson<{ ticker: string }[]>('docs/validacao/universo.json').map((e) => e.ticker));
  const raw = readRawCotahist(universe);
  errln(`proventos de ${dividends.size} emissores; COTAHIST de ${raw.size} tickers`);

  // ---- 1 e 2: unidade, data-com e queda na data ex ----------------------
  let withPrice = 0;
  let priceMatches = 0;
  let withExSession = 0;
  const drops: number[] = [];
  const priceDeviations: number[] = [];
  for (const t of universe) {
    const series = raw.get(t);
    if (series === undefined) continue;
    for (const p of dividendsOf(dividends, t)) {
      if (p.exDate.year < 2010) continue;
      const withInput = tradingDayUntil(series, p.lastDateWithRights, 0);
      const ex = tradingDayFrom(series, p.exDate, 5);
      if (p.closeWithRights !== null && withInput !== null) {
        withPrice++;
        const d = Math.abs(p.closeWithRights / withInput.close - 1);
        priceDeviations.push(d);
        if (d <= 0.01) priceMatches++;
      }
      if (withInput !== null && ex !== null) {
        withExSession++;
        // Só provento que pesa: abaixo de 0,5% do preço, o ruído do dia manda.
        if (p.amount / withInput.close >= 0.005) drops.push((withInput.close - ex.close) / p.amount);
      }
    }
  }

  // ---- 3: adjustedClose da fonte contra os proventos da B3 ---------------
  const end = DateTime.local(2026, 9, 14);
  const start = DateTime.local(2016, 9, 14);
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  const adjustments: Adjustment[] = [];
  try {
    for (const t of [...universe].sort(compareStr)) {
      const list = dividendsOf(dividends, t);
      const series = raw.get(t);
      if (list.length === 0 || series === undefined) continue;
      const r = await ctx.prices.daily(Ticker.parse(t), new DateRange(start, end));
      if (r.isErr) continue;
      const points = r.unwrap().points.filter((p) => p.adjustedClose !== null && p.adjustedClose > 0 && p.close > 0);
      if (points.length < 500) continue;
      const a = points[0]!;
      const b = points[points.length - 1]!;
      // Convenção de ajuste para trás: cada provento multiplica os preços
      // anteriores por `1 − D/P_com`. A razão ajustado ÷ bruto entre as pontas
      // é o produto desses fatores.
      const observed = a.adjustedClose! / a.close / (b.adjustedClose! / b.close);
      let implied = 1.0;
      let used = 0;
      let withoutPrice = 0;
      for (const p of list) {
        if (!p.exDate.isAfter(a.date) || p.exDate.isAfter(b.date)) continue;
        const withInput = tradingDayUntil(series, p.lastDateWithRights, 5);
        const price = p.closeWithRights ?? withInput?.close ?? null;
        if (price === null || price <= p.amount) {
          withoutPrice++;
          continue;
        }
        implied *= 1 - p.amount / price;
        used++;
      }
      if (used === 0) continue;
      adjustments.push({
        ticker: t,
        proventos: used,
        semPreco: withoutPrice,
        observado: observed,
        implicitoB3: implied,
        desvio: Math.abs(observed / implied - 1),
      });
    }
  } finally {
    await ctx.dispose();
  }
  const deviations = adjustments.map((x) => x.desvio);

  // ---- 4: retorno total nas coortes -------------------------------------
  const cohortsFile = 'docs/validacao/backtest_valuation.json';
  const cohorts = existsSync(cohortsFile) ? readJson<Record<string, unknown>[]>(cohortsFile) : [];
  const byCohort = new Map<number, number[]>();
  let withoutPriceCohorts = 0;
  let approximatedCohorts = 0;
  for (const l of cohorts) {
    const t = l['ticker'] as string;
    const year = l['coorte'] as number;
    const base = DateTime.utc(year, 9, 30);
    const series = raw.get(t);
    const list = dividendsOf(dividends, t);
    for (const [months, field] of [
      [12, 'ret12'],
      [36, 'ret36'],
    ] as const) {
      const price = typeof l[field] === 'number' ? (l[field] as number) : null;
      if (price === null) continue;
      if (series === undefined) {
        l[`${field}tot`] = null;
        continue;
      }
      const r = TotalReturn.factor({
        dividends: list,
        from: base,
        until: DateTime.utc(year + intDiv(months, 12), 9, 30),
        closeOnExDate: (d) => tradingDayFrom(series, d, 5)?.close ?? null,
      });
      withoutPriceCohorts += r.withoutPrice;
      approximatedCohorts += r.approximated;
      const total = (1 + price) * r.factor - 1;
      l[`${field}tot`] = total;
      if (months === 36) {
        let list36 = byCohort.get(year);
        if (list36 === undefined) byCohort.set(year, (list36 = []));
        list36.push(total - price);
      }
    }
  }
  if (cohorts.length > 0) writeText('docs/validacao/backtest_valuation_total.json', jsonPretty(cohorts));

  const result = {
    medidoEm: '2026-09-14',
    dataCom: { comPrecoDaB3: withPrice, batemA1pct: priceMatches, desvioMediano: median(priceDeviations) },
    dataEx: {
      comPregaoNasDuasDatas: withExSession,
      quedaSobreProventoMediana: median(drops),
      quedaSobreProventoP25: quantile(drops, 0.25),
      quedaSobreProventoP75: quantile(drops, 0.75),
      n: drops.length,
    },
    adjustedClose: {
      ativos: adjustments.length,
      desvioMediano: median(deviations),
      desvioP90: quantile(deviations, 0.9),
      acimaDe5pct: deviations.filter((d) => d > 0.05).length,
      porAtivo: adjustments,
    },
    coortes: {
      linhas: cohorts.length,
      proventosSemPreco: withoutPriceCohorts,
      proventosPeloPrecoComDireito: approximatedCohorts,
      totalMenosPreco36m: Object.fromEntries([...byCohort].map(([k, v]) => [String(k), median(v)])),
    },
  };
  writeText('docs/validacao/proventos.json', jsonPretty(result));

  outln('== 1. Fechamento com direito: B3 contra COTAHIST ==');
  outln(
    `  ${priceMatches} de ${withPrice} a 1% (${pc(withPrice === 0 ? null : priceMatches / withPrice)}); ` +
      `desvio mediano ${pc(median(priceDeviations), 2)}`,
  );
  outln('\n== 2. Queda na data ex ÷ provento ==');
  const fixed3 = (v: number | null) => (v === null ? 'null' : v.toFixed(3));
  outln(
    `  mediana ${fixed3(median(drops))}  p25 ${fixed3(quantile(drops, 0.25))}  p75 ${fixed3(quantile(drops, 0.75))}  ` +
      `(n = ${drops.length})`,
  );
  outln('\n== 3. adjustedClose da fonte contra os proventos da B3, 2016-09 a 2026-09 ==');
  outln(
    `  ativos: ${adjustments.length}  desvio mediano ${pc(median(deviations))}  p90 ${pc(quantile(deviations, 0.9))}  ` +
      `acima de 5%: ${deviations.filter((d) => d > 0.05).length}`,
  );
  adjustments.sort((a, b) => compareNum(b.desvio, a.desvio));
  for (const x of adjustments.slice(0, 10)) {
    outln(`    ${x.ticker.padEnd(7)} desvio ${pc(x.desvio)}  ${x.proventos} proventos`);
  }
  outln('\n== 4. Coortes: retorno total − de preço, 36 meses, mediana por coorte ==');
  for (const [year, v] of byCohort) outln(`  ${year}: ${pc(median(v))}  (n = ${v.length})`);
  outln(
    `  proventos pelo preço com direito da B3, sem pregão no COTAHIST: ${approximatedCohorts}; ` +
      `sem preço nenhum: ${withoutPriceCohorts}`,
  );
  outln('\n  gravado docs/validacao/proventos.json e docs/validacao/backtest_valuation_total.json');
}
