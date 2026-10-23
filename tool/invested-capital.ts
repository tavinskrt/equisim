// As duas rotas do capital investido, que nunca se conferem.
//
// `FundamentalsSnapshot.investedCapital` apura pelo **financiamento**:
// `PL + dívida bruta − caixa`. `investedCapitalOperating` apura pelo lado
// **operacional**: `imobilizado + intangível + capital de giro`. A
// documentação da primeira diz que a concordância com a segunda "serve de
// teste de qualidade" — e **nada no motor faz esse teste**. A rota operacional
// só aparece num despejo de auditoria.
//
// O capital investido é o denominador do ROIC, que é o freio de reinvestimento
// `b = g/ROIC` e o veredito de fosso. Errá-lo move o preço.
//
// Uso:
//   npm run tool -- invested-capital
import { compareNum, DateTime, PointInTimeView, round, sortedNums } from '../src/core';
import { jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

function p(v: readonly number[], q: number): number | null {
  if (v.length === 0) return null;
  const s = sortedNums(v);
  return s[round((s.length - 1) * q)]!;
}

interface Row {
  ticker: string;
  exercicio: number;
  financiamento: number;
  operacional: number;
  razao: number;
  distancia: number;
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
      for (const s of new PointInTimeView(today).published(hist.unwrap())) {
        const fin = s.investedCapital;
        const operating = s.investedCapitalOperating;
        if (fin === null || operating === null || fin <= 0 || operating <= 0) continue;
        rows.push({
          ticker: ticker.value,
          exercicio: s.fiscalPeriodEnd.year,
          financiamento: fin,
          operacional: operating,
          razao: fin / operating,
          distancia: fin >= operating ? fin / operating : operating / fin,
        });
      }
    }
    process.stderr.write('\n');

    const d = rows.map((l) => l.distancia);
    outln(`== ${rows.length} exercícios com as duas rotas apuradas (${new Set(rows.map((l) => l.ticker)).size} ativos) ==\n`);
    outln('  distância multiplicativa entre as rotas');
    for (const q of [0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 1.0]) {
      outln(`    p${(q * 100).toFixed(0).padStart(3)}: ${p(d, q)!.toFixed(3)}x`);
    }
    for (const lim of [1.05, 1.1, 1.25, 1.5, 2.0, 5.0]) {
      const n = d.filter((x) => x > lim).length;
      outln(`  acima de ${lim.toFixed(2)}x: ${n} (${((100 * n) / d.length).toFixed(1)}%)`);
    }

    rows.sort((a, b) => compareNum(b.distancia, a.distancia));
    outln('\n  os 15 mais distantes');
    outln('  ticker   exerc   financiamento   operacional   distância');
    const inBillions = (v: number) => (v / 1e9).toFixed(3);
    for (const l of rows.slice(0, 15)) {
      outln(
        `  ${l.ticker.padEnd(8)} ${l.exercicio}   ${inBillions(l.financiamento).padStart(13)}   ` +
          `${inBillions(l.operacional).padStart(11)}   ${l.distancia.toFixed(2).padStart(9)}x`,
      );
    }

    // Viés: a rota do financiamento é sistematicamente maior ou menor?
    const logs = rows.map((l) => Math.log(l.razao));
    const mean = logs.reduce((a, b) => a + b) / logs.length;
    outln(`\n  viés (média do log da razão fin/oper): ${Math.exp(mean).toFixed(4)}x`);

    writeText('docs/validacao/capital_investido.json', jsonPretty(rows));
    outln('  gravado em docs/validacao/capital_investido.json');
  } finally {
    await ctx.dispose();
  }
}
