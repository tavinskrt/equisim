// O grupamento que a regra do maior sempre ignora.
//
// `quotedShares` compara duas candidatas a divisor — a implícita no valor de
// mercado e a conciliada pelas demonstrações — e, na divergência, **adota a
// maior**, porque divisor pequeno demais infla o preço justo e produz sinal
// falso de barato.
//
// A regra tem um viés estrutural que ninguém escolheu: `reconciledShares` só
// pode confirmar a contagem **do exercício** — o árbitro `N = lucro ÷ LPA` usa
// dois campos das mesmas demonstrações. Um **grupamento** posterior reduz a
// contagem corrente sem tocar a do exercício, de modo que a candidata contábil
// fica maior **sempre**, e sempre vence. Um desdobramento faz o contrário e a
// regra o absorve bem. O viés é assimétrico, e só contra grupamento.
//
// Uso:
//   npm run tool -- reverse-split
import { compareNum, DateRange, DateTime, Duration, PointInTimeView, ValuationCascade } from '../src/core';
import { jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

interface Row {
  ticker: string;
  u: number;
  fonte: string;
  divisor: number;
  mercado: number | null;
  balanco: number | null;
  diverge: boolean;
  corrente: number | null;
  doExercicio: number | null;
  grupamentoAparente: boolean;
  razaoDivisor: number | null;
}

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const universe = (await ctx.fundamentals.universe()).unwrap();
    const rows: Row[] = [];

    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);

      const hist = await ctx.fundamentals.history(ticker);
      if (hist.isErr) continue;
      const pub = new PointInTimeView(today).published(hist.unwrap());
      if (pub.length === 0) continue;
      const latest = pub[pub.length - 1]!;

      const series = await ctx.prices.daily(ticker, new DateRange(today.subtract(new Duration({ days: 30 })), today));
      if (series.isErr || series.unwrap().points.length === 0) continue;
      const points = series.unwrap().points;
      const price = points[points.length - 1]!.close;

      const u = ValuationCascade.quotedUnitRatio({
        sharesOutstanding: latest.sharesOutstanding,
        marketCap: latest.marketCap,
        marketPrice: price,
      });
      const q = ValuationCascade.quotedShares({ latest, marketPrice: price, sharesPerQuote: u, published: pub });
      if (q === null) continue;

      const current = latest.sharesOutstanding;
      const fiscalYearValue = latest.sharesOutstandingAsOf;
      const wasGrouped = current !== null && fiscalYearValue !== null && current > 0 && fiscalYearValue > current * 1.5;

      rows.push({
        ticker: ticker.value,
        u,
        fonte: q.source.name,
        divisor: q.count,
        mercado: q.fromMarketCap,
        balanco: q.fromStatements,
        diverge: q.diverge,
        corrente: current,
        doExercicio: fiscalYearValue,
        grupamentoAparente: wasGrouped,
        razaoDivisor: q.fromMarketCap !== null && q.fromMarketCap > 0 ? q.count / q.fromMarketCap : null,
      });
    }
    process.stderr.write('\n');

    const diverging = rows.filter((l) => l.diverge);
    const bookWins = diverging.filter((l) => l.fonte === 'reconciled');
    const grouped = rows.filter((l) => l.grupamentoAparente);
    const bookGrouped = grouped.filter((l) => l.fonte === 'reconciled');

    outln(`== ${rows.length} ativos com divisor apurado ==\n`);
    outln(`  divergem além da banda:            ${diverging.length}`);
    outln(`  ...e a contábil vence:             ${bookWins.length}`);
    outln(`  grupamento aparente (exerc > 1,5x corrente): ${grouped.length}`);
    outln(`  ...e a contábil vence:             ${bookGrouped.length}`);

    const factor = (l: Row) => l.doExercicio! / l.corrente!;
    grouped.sort((a, b) => compareNum(factor(b), factor(a)));
    outln('\n  ticker    exerc/corrente   fonte        divisor/mercado');
    for (const l of grouped) {
      const rd = l.razaoDivisor;
      outln(
        `  ${l.ticker.padEnd(8)} ${factor(l).toFixed(2).padStart(14)}x  ${l.fonte.padEnd(12)} ` +
          (rd === null ? '-' : `${rd.toFixed(2)}x`),
      );
    }

    writeText('docs/validacao/grupamento.json', jsonPretty(rows));
    outln('\n  gravado em docs/validacao/grupamento.json');
  } finally {
    await ctx.dispose();
  }
}
