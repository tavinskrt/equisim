// A razão de unidade e a tolerância que aperta onde deveria afrouxar.
//
// `ValuationCascade.quotedUnitRatio` mede `ações × preço ÷ valor de mercado` e
// arredonda, recusando o resultado quando ele fica a mais de **0,12 absoluto**
// de um inteiro. A tolerância é absoluta, e a razão não é: para a ação comum
// ela vale 12% de folga; para uma unit de dez ações, 1,2%. O aperto cresce
// exatamente onde o fator errado custa mais.
//
// Uso:
//   npm run tool -- unit
import { compareNum, DateRange, DateTime, Duration, PointInTimeView, roundToDouble, ValuationCascade } from '../src/core';
import { jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

interface Row {
  ticker: string;
  bruto: number;
  inteiro: number;
  desvioAbsoluto: number;
  desvioRelativo: number | null;
  aceitoHoje: boolean;
  adotadoHoje: number;
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

      const n = latest.sharesOutstanding;
      const marketValue = latest.marketCap;
      if (n === null || n <= 0 || marketValue === null || marketValue <= 0 || price <= 0) continue;

      const raw = (n * price) / marketValue;
      if (!Number.isFinite(raw)) continue;
      const whole = roundToDouble(raw);
      const deviation = Math.abs(raw - whole);

      rows.push({
        ticker: ticker.value,
        bruto: raw,
        inteiro: whole,
        desvioAbsoluto: deviation,
        desvioRelativo: whole > 0 ? deviation / whole : null,
        aceitoHoje: whole >= 1 && whole <= ValuationCascade.maxSharesPerUnit && deviation <= 0.12,
        adotadoHoje: ValuationCascade.quotedUnitRatio({ sharesOutstanding: n, marketCap: marketValue, marketPrice: price }),
      });
    }
    process.stderr.write('\n');

    rows.sort((a, b) => compareNum(b.bruto, a.bruto));

    outln(`== ${rows.length} ativos com razão mensurável ==\n`);
    outln('  ticker    bruto   inteiro   desvio abs   desvio rel  adotado');
    for (const l of rows) {
      if (l.bruto < 1.5 && l.desvioAbsoluto < 0.12) continue;
      const rel = l.desvioRelativo;
      outln(
        `  ${l.ticker.padEnd(8)} ${l.bruto.toFixed(4).padStart(8)} ${l.inteiro.toFixed(0).padStart(7)} ` +
          `${l.desvioAbsoluto.toFixed(4).padStart(11)} ${rel === null ? '     -' : `${(rel * 100).toFixed(2)}%`.padStart(11)} ` +
          `${l.adotadoHoje.toFixed(0).padStart(6)}`,
      );
    }

    // Quantos seriam recusados hoje mas aceitos por tolerância relativa?
    for (const tol of [0.02, 0.03, 0.05, 0.08]) {
      const flips = rows.filter(
        (l) =>
          l.inteiro > 1 &&
          l.inteiro <= ValuationCascade.maxSharesPerUnit &&
          !l.aceitoHoje &&
          l.desvioRelativo !== null &&
          l.desvioRelativo <= tol,
      );
      outln(
        `\n  tolerância relativa de ${(tol * 100).toFixed(0)}%: ${flips.length} unit(s) que hoje caem para 1 ` +
          flips.map((l) => l.ticker).join(', '),
      );
    }

    writeText('docs/validacao/unidade.json', jsonPretty(rows));
    outln('\n  gravado em docs/validacao/unidade.json');
  } finally {
    await ctx.dispose();
  }
}
