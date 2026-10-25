// O retorno por ativo mede o ativo, ou o cronograma de aportes?
//
// `BacktestOutcome` reporta três retornos para a **carteira** — TWR, XIRR e o
// CAGR derivado do TWR —, e um só para cada **ativo**:
//
//     totalReturn = (valor final + caixa − aportado) ÷ aportado
//
// que é razão de capital acumulado, sem dimensão de tempo. A lente `metodo`
// aponta que ele herda o calendário de aportes e não é comparável ao da
// carteira. A pergunta desta medição é se isso **desloca a ordenação** entre
// ativos, que é o que o usuário lê.
//
// Duas partes: um caso sintético que isola o mecanismo, e uma carteira real
// que mede o tamanho.
//
// Uso:
//   npm run tool -- return-by-asset
import {
  Asset,
  compareNum,
  ContributionPlan,
  DateRange,
  DateTime,
  Money,
  Portfolio,
  PortfolioBacktest,
  PortfolioKind,
  PricePoint,
  PriceSeries,
  Sector,
  Ticker,
  TransactionCosts,
} from '../src/core';
import { jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const start = DateTime.local(2019, 9, 30);
const end = DateTime.local(2026, 9, 4);

/**
 * Retorno de preço do ativo no período — a medida que **não** depende do
 * cronograma de aportes.
 */
function priceReturn(s: PriceSeries, from: DateTime, until: DateTime): number | null {
  let p0: number | null = null;
  let p1: number | null = null;
  for (const p of s.points) {
    if (p.date.isBefore(from)) continue;
    p0 ??= p.close;
    if (!p.date.isAfter(until)) p1 = p.close;
  }
  if (p0 === null || p1 === null || p0 <= 0) return null;
  return p1 / p0 - 1;
}

/**
 * Empate em posto: dois retornos indistinguíveis dentro da tolerância.
 *
 * A comparação é **relativa à magnitude**, e não `===`: dois retornos que
 * saem de somas diferentes de centavos podem diferir no último bit e
 * receberiam postos distintos, o que muda o Spearman sem que nada tenha
 * mudado no dado.
 */
function tie(a: number, b: number): boolean {
  const scale = Math.abs(a) > Math.abs(b) ? Math.abs(a) : Math.abs(b);
  return Math.abs(a - b) <= (scale > 1 ? scale : 1) * 1e-12;
}

function ranks(v: readonly number[]): number[] {
  const idx = v.map((_, i) => i).sort((x, y) => compareNum(v[x]!, v[y]!));
  const r = new Array<number>(v.length).fill(0);
  let i = 0;
  while (i < idx.length) {
    let j = i;
    while (j + 1 < idx.length && tie(v[idx[j + 1]!]!, v[idx[i]!]!)) j++;
    const middle = (i + j) / 2 + 1;
    for (let k = i; k <= j; k++) r[idx[k]!] = middle;
    i = j + 1;
  }
  return r;
}

function spearman(a: readonly number[], b: readonly number[]): number {
  if (a.length < 2) return 0.0;
  const ranksA = ranks(a);
  const ranksB = ranks(b);
  const meanA = ranksA.reduce((x, y) => x + y) / ranksA.length;
  const meanB = ranksB.reduce((x, y) => x + y) / ranksB.length;
  let num = 0.0;
  let sumSqA = 0.0;
  let sumSqB = 0.0;
  for (let i = 0; i < ranksA.length; i++) {
    num += (ranksA[i]! - meanA) * (ranksB[i]! - meanB);
    sumSqA += Math.pow(ranksA[i]! - meanA, 2);
    sumSqB += Math.pow(ranksB[i]! - meanB, 2);
  }
  return sumSqA <= 0 || sumSqB <= 0 ? 0.0 : num / Math.sqrt(sumSqA * sumSqB);
}

// ------------------------------------------------------- caso sintético --

function synthetic(): void {
  outln('== 1. O mecanismo, isolado ==');
  outln('');
  outln('Dois ativos que começam e terminam no MESMO preço — retorno');
  outln('de preço zero para ambos. Um cai e volta; o outro sobe e');
  outln('volta. Mesmo peso, mesmo aporte mensal, mesma janela.');
  outln('');

  const days = Array.from({ length: 84 }, (_, i) => DateTime.local(2019, 1 + i, 1));

  // Vale e pico, simétricos: ambos partem de 100 e voltam a 100.
  const vale = (i: number): number => 100 - 40 * Math.sin((Math.PI * i) / (days.length - 1));
  const peak = (i: number): number => 100 + 40 * Math.sin((Math.PI * i) / (days.length - 1));

  const series = (t: string, f: (i: number) => number): PriceSeries =>
    new PriceSeries({ ticker: Ticker.parse(t), points: days.map((d, i) => new PricePoint({ date: d, close: f(i) })) });

  const fell = Ticker.parse('VALE4');
  const rose = Ticker.parse('PICO4');
  const sector = new Sector({ key: 's', label: 'S' });
  const portfolio = Portfolio.equalWeighted({
    id: 'x',
    name: 'x',
    kind: PortfolioKind.principal,
    assets: [new Asset({ ticker: fell, name: 'Vale', sector }), new Asset({ ticker: rose, name: 'Pico', sector })],
  }).unwrap();

  const plan = (): ContributionPlan =>
    new ContributionPlan({ initial: Money.fromReais(1000), monthly: Money.fromReais(1000), contributionDay: 1 });

  const r = PortfolioBacktest.run({
    portfolio,
    prices: new Map([
      [fell, series('VALE4', vale)],
      [rose, series('PICO4', peak)],
    ]),
    plan: plan(),
    range: new DateRange(days[0]!, days[days.length - 1]!),
    // A demonstração é de TWR contra XIRR, e não de custo (item C4).
    costs: TransactionCosts.none,
  });
  if (r.isErr) {
    outln(`  falhou: ${r.failureOrNull?.message ?? null}`);
    return;
  }
  const o = r.unwrap();
  outln(`  período efetivo: ${o.effectivePeriod.toString()}`);
  for (const t of [fell, rose]) {
    const a = o.perAsset.get(t);
    if (a === undefined) continue;
    outln(
      `  ${t.value}: totalReturn = ${(a.totalReturn * 100).toFixed(1)}%   retorno de preço = 0,0%   ` +
        `aportado ${(a.invested.cents / 100).toFixed(0)}   final ${(a.finalValue.cents / 100).toFixed(0)}`,
    );
  }
  const va = o.perAsset.get(fell)?.totalReturn;
  const nv = o.perAsset.get(rose)?.totalReturn;
  if (va !== undefined && nv !== undefined) {
    outln('');
    outln(`  distância entre dois ativos de retorno de preço IGUAL (zero): ${((va - nv) * 100).toFixed(1)} p.p.`);
    outln('  O número não descreve o ativo: descreve o que o dinheiro');
    outln('  do aporte mensal fez dentro dele. As duas leituras são');
    outln('  verdadeiras, e respondem a perguntas diferentes.');
  }

  // E o canal que a lente teme — datas de listagem diferentes — é fechado
  // pelo próprio backtest: o período recua para o ativo mais novo.
  const newSecurity = Ticker.parse('NOVO3');
  const c2 = Portfolio.equalWeighted({
    id: 'y',
    name: 'y',
    kind: PortfolioKind.principal,
    assets: [new Asset({ ticker: fell, name: 'Vale', sector }), new Asset({ ticker: newSecurity, name: 'Novo', sector })],
  }).unwrap();
  const r2 = PortfolioBacktest.run({
    portfolio: c2,
    prices: new Map([
      [fell, series('VALE4', vale)],
      [
        newSecurity,
        new PriceSeries({
          ticker: newSecurity,
          points: days.slice(60).map((d, k) => new PricePoint({ date: d, close: vale(60 + k) })),
        }),
      ],
    ]),
    plan: plan(),
    range: new DateRange(days[0]!, days[days.length - 1]!),
  });
  outln('');
  if (r2.isOk) {
    const o2 = r2.unwrap();
    outln(`  com um ativo listado 60 meses depois, o período efetivo vira ${o2.effectivePeriod.toString()}`);
    for (const w of o2.warnings) outln(`    aviso: ${w}`);
    const a = o2.perAsset.get(fell)?.totalReturn;
    const b = o2.perAsset.get(newSecurity)?.totalReturn;
    if (a !== undefined && b !== undefined) {
      outln(`    VALE4 ${(a * 100).toFixed(1)}%  NOVO3 ${(b * 100).toFixed(1)}%  — medidos na mesma janela`);
    }
  }
}

// --------------------------------------------------------- carteira real --

interface Row {
  ticker: string;
  totalReturn: number;
  retornoDePreco: number;
  aportado: number;
  caixa: number;
  pregoes: number;
}

async function real(ctx: ValidationContext): Promise<void> {
  outln('');
  outln('');
  outln('== 2. O tamanho, numa carteira real ==');
  outln('');

  const universe = (await ctx.fundamentals.universe()).unwrap();
  const chosen: Ticker[] = [];
  const series = new Map<Ticker, PriceSeries>();
  for (const t of universe) {
    if (chosen.length >= Portfolio.maxAssets) break;
    const r = await ctx.prices.daily(t, new DateRange(start, end));
    if (r.isErr) continue;
    const s = r.unwrap();
    if (s.points.length < 1000) continue;
    chosen.push(t);
    series.set(t, s);
  }
  if (chosen.length < 5) {
    outln('  ativos insuficientes com histórico completo.');
    return;
  }

  const assets: Asset[] = [];
  for (const t of chosen) {
    const p = await ctx.fundamentals.profile(t);
    assets.push(p.isOk ? p.unwrap() : new Asset({ ticker: t, name: t.value, sector: new Sector({ key: 'x', label: 'X' }) }));
  }
  const portfolio = Portfolio.equalWeighted({ id: 'r', name: 'r', kind: PortfolioKind.principal, assets }).unwrap();

  const r = PortfolioBacktest.run({
    portfolio,
    prices: series,
    plan: new ContributionPlan({ initial: Money.fromReais(10000), monthly: Money.fromReais(1000), contributionDay: 5 }),
    range: new DateRange(start, end),
  });
  if (r.isErr) {
    outln(`  falhou: ${r.failureOrNull?.message ?? null}`);
    return;
  }
  const o = r.unwrap();

  const rows: Row[] = [];
  for (const t of chosen) {
    const a = o.perAsset.get(t);
    if (a === undefined) continue;
    const price = priceReturn(series.get(t)!, start, end);
    if (price === null) continue;
    rows.push({
      ticker: t.value,
      totalReturn: a.totalReturn,
      retornoDePreco: price,
      aportado: a.invested.cents / 100,
      caixa: a.cash.cents / 100,
      pregoes: series.get(t)!.points.length,
    });
  }
  rows.sort((a, b) => compareNum(b.totalReturn, a.totalReturn));

  const tr = rows.map((l) => l.totalReturn);
  const priceReturns = rows.map((l) => l.retornoDePreco);
  const priceOrder = rows.map((_, i) => i).sort((x, y) => compareNum(priceReturns[y]!, priceReturns[x]!));
  const priceRank = new Map<number, number>();
  priceOrder.forEach((row, i) => priceRank.set(row, i + 1));

  outln('  ticker    totalReturn   retorno de preço   posto tR   posto preço   pregões');
  let largestShift = 0;
  for (let i = 0; i < rows.length; i++) {
    const d = Math.abs(priceRank.get(i)! - (i + 1));
    if (d > largestShift) largestShift = d;
    outln(
      `  ${rows[i]!.ticker.padEnd(8)} ${(tr[i]! * 100).toFixed(1).padStart(11)}%   ` +
        `${(priceReturns[i]! * 100).toFixed(1).padStart(15)}%   ${String(i + 1).padStart(8)}   ` +
        `${String(priceRank.get(i)).padStart(11)}   ${String(rows[i]!.pregoes).padStart(7)}`,
    );
  }
  outln('');
  outln(`  Spearman entre as duas medidas: ${spearman(tr, priceReturns).toFixed(4)}`);
  outln(`  maior deslocamento de posto: ${largestShift} de ${rows.length}`);
  const xirr = o.metrics.moneyWeightedReturn;
  outln(
    `  TWR da carteira: ${(o.metrics.timeWeightedReturn * 100).toFixed(1)}%   ` +
      `XIRR: ${xirr === null ? '—' : `${(xirr * 100).toFixed(1)}%`}`,
  );

  writeText('docs/validacao/retorno_por_ativo.json', jsonPretty(rows, ' '));
  outln('');
  outln('  gravado em docs/validacao/retorno_por_ativo.json');
}

export async function main(_args: string[]): Promise<void> {
  synthetic();
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    await real(ctx);
  } finally {
    await ctx.dispose();
  }
}
