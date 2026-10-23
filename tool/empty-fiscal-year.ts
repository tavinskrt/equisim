// O exercício que a fonte publica sem demonstração de resultado.
//
// **O caso que abriu a pergunta.** A TIMS3 é recusada por "os dados não
// sustentam nenhuma das duas vias". O exercício que o motor usou como base tem
// `ebit = 0`, `nopat = 0`, `lpa = 0` e `receita = 0` — com patrimônio líquido
// de R$ 24 bilhões no mesmo balanço. Ela teve EBIT de R$ 4,7 bi em 2023.
//
// Uma empresa com R$ 24 bi de patrimônio não tem receita zero. O exercício
// existe na fonte e a demonstração de resultado dele **não foi publicada** — e
// o motor lê o vazio como o número zero.
//
// **O que isto mede.** Quantos exercícios são assim, onde eles caem na série, e
// o que acontece com o ativo por causa disso.
//
// Uso:
//   npm run tool -- empty-fiscal-year
import {
  DateTime,
  type FundamentalsSnapshot,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  str,
  ValuationCascade,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/**
 * `true` quando o exercício não traz resultado algum.
 *
 * Os quatro juntos: receita, resultado operacional, lucro líquido e lucro por
 * ação. Zerar **um** deles é possível — holding sem receita, empresa no
 * zero a zero. Zerar os quatro, não.
 */
function withoutResult(s: FundamentalsSnapshot): boolean {
  const isEmptyValue = (v: number | null) => v === null || v === 0;
  return isEmptyValue(s.totalRevenue) && isEmptyValue(s.ebit) && isEmptyValue(s.netIncome) && isEmptyValue(s.earningsPerShare);
}

/**
 * `true` quando o balanço do mesmo exercício tem conteúdo.
 *
 * É o que separa "a empresa não existia" de "a demonstração de resultado não
 * veio": o exercício está lá, com patrimônio e ativo, e só o resultado falta.
 */
function withBalanceSheet(s: FundamentalsSnapshot): boolean {
  const pl = s.totalStockholderEquity;
  const fixedAssets = s.propertyPlantEquipment;
  const asset = s.totalCurrentAssets;
  return (pl !== null && pl !== 0) || (fixedAssets !== null && fixedAssets !== 0) || (asset !== null && asset !== 0);
}

interface Row {
  ticker: string;
  exercicios: number;
  vazios: number;
  anosVazios: number[];
  ultimoVazio: boolean;
  comBalanco: number;
  justo: number | null;
  recusa: string | null;
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

    const output: Row[] = [];
    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);
      const series = await ctx.fundamentals.history(ticker);
      if (series.isErr) continue;
      const pub = new PointInTimeView(today).published(series.unwrap());
      if (pub.length === 0) continue;

      const empty = pub.filter(withoutResult);
      if (empty.length === 0) continue;

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
      let refusal: string | null = null;
      let fairValue: number | null = null;
      if (prep.isErr) {
        refusal = `insumo: ${prep.failureOrNull?.message}`;
      } else {
        const r = ValuationCascade.evaluate(prep.unwrap());
        if (r.isErr) {
          refusal = r.failureOrNull!.message;
        } else {
          fairValue = r.unwrap().fairValue.reais;
        }
      }

      output.push({
        ticker: ticker.value,
        exercicios: pub.length,
        vazios: empty.length,
        anosVazios: empty.map((s) => s.fiscalPeriodEnd.year),
        ultimoVazio: withoutResult(pub[pub.length - 1]!),
        comBalanco: empty.filter(withBalanceSheet).length,
        justo: fairValue,
        recusa: refusal,
      });
    }
    process.stderr.write('\n');

    writeText('docs/validacao/exercicio_vazio.json', jsonPretty(output));
    printReport(output, universe.length);
    errln(`\nescrito docs/validacao/exercicio_vazio.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[], universe: number): void {
  const line = (e: Row) =>
    `  ${e.ticker.padEnd(7)} vazios=${e.vazios}/${e.exercicios}  anos=[${e.anosVazios.join(', ')}]  ` +
    (e.recusa !== null ? 'RECUSADO' : `justo=${e.justo === null ? 'null' : str(e.justo)}`);
  outln('\n=== EXERCÍCIO SEM DEMONSTRAÇÃO DE RESULTADO ===\n');
  outln(`  ativos com ao menos um: ${l.length} de ${universe}`);
  const withBalance = l.filter((e) => e.comBalanco > 0).length;
  outln(`  destes, com balanço preenchido no mesmo exercício: ${withBalance}`);
  const inLast = l.filter((e) => e.ultimoVazio);
  outln(`  **com o exercício-base vazio: ${inLast.length}**`);
  const refusedCount = l.filter((e) => e.recusa !== null).length;
  outln(`  recusados pelo motor: ${refusedCount}`);

  const totalEmpty = l.reduce((a, e) => a + e.vazios, 0);
  const totalFiscalYears = l.reduce((a, e) => a + e.exercicios, 0);
  outln(`  exercícios vazios: ${totalEmpty} de ${totalFiscalYears} publicados nesses ativos`);

  if (inLast.length > 0) {
    outln('\n-- os que têm o exercício-base vazio --');
    for (const e of inLast) outln(line(e));
  }

  const inMiddle = l.filter((e) => !e.ultimoVazio);
  if (inMiddle.length > 0) {
    outln('\n-- vazio no meio da série (envenena crescimento e retorno, não a base) --');
    for (const e of inMiddle.slice(0, 20)) outln(line(e));
    if (inMiddle.length > 20) outln(`  … e mais ${inMiddle.length - 20}`);
  }
}
