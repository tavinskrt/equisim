// D7 — o efeito da ponte completa, isolado do dado novo.
//
// **O confundidor.** A [decisão 49](../docs/decisoes/049-a-ponte-devolve-o-que-nao-e-do-controlador.md)
// acrescentou dois campos ao cache, e a migração invalidou a chave de
// fundamentos — de modo que a rodada seguinte trouxe **todos** os campos
// frescos da fonte, não só os dois. Comparar contra o relatório anterior
// mediria a correção somada ao que a fonte mudou desde então.
//
// A separação é feita aqui: o mesmo ativo, na mesma série recém-buscada, é
// avaliado duas vezes — uma com os dois termos e outra com eles zerados, que é
// exatamente o comportamento de antes da decisão 49.
//
// Uso:
//   npm run tool -- bridge
import {
  compareNum,
  DateTime,
  FundamentalsSnapshot,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  ValuationCascade,
  ValuationInputs,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/**
 * A mesma série, sem os dois termos da ponte.
 *
 * Reproduz o motor de antes da decisão 49 **sobre o dado de agora**, que é o
 * que torna a comparação uma medida da correção e não da atualização.
 */
const withoutTerms = (series: readonly FundamentalsSnapshot[]): FundamentalsSnapshot[] =>
  series.map(
    (s) =>
      new FundamentalsSnapshot({
        ticker: s.ticker,
        fiscalPeriodEnd: s.fiscalPeriodEnd,
        totalRevenue: s.totalRevenue,
        ebit: s.ebit,
        ebitda: s.ebitda,
        netIncome: s.netIncome,
        incomeBeforeTax: s.incomeBeforeTax,
        incomeTaxExpense: s.incomeTaxExpense,
        interestExpense: s.interestExpense,
        earningsPerShare: s.earningsPerShare,
        cash: s.cash,
        shortTermInvestments: s.shortTermInvestments,
        shortTermDebt: s.shortTermDebt,
        longTermDebt: s.longTermDebt,
        totalStockholderEquity: s.totalStockholderEquity,
        bookValuePerShare: s.bookValuePerShare,
        operatingCashFlow: s.operatingCashFlow,
        investmentCashFlow: s.investmentCashFlow,
        freeCashFlow: s.freeCashFlow,
        nopat: s.nopat,
        propertyPlantEquipment: s.propertyPlantEquipment,
        intangibleAssets: s.intangibleAssets,
        totalCurrentAssets: s.totalCurrentAssets,
        currentLiabilities: s.currentLiabilities,
        realizedShareCapital: s.realizedShareCapital,
        profitReserves: s.profitReserves,
        sharesOutstanding: s.sharesOutstanding,
        sharesOutstandingAsOf: s.sharesOutstandingAsOf,
        marketCap: s.marketCap,
        enterpriseToEbitda: s.enterpriseToEbitda,
        // Os dois que a decisão 49 introduziu ficam de fora.
      }),
  );

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number): string => `${(v * 100).toFixed(1)}%`;

interface Row {
  ticker: string;
  setor: string | null;
  via: string | null;
  justoCom: number | null;
  justoSem: number | null;
  minoritarios: number | null;
  equivalencia: number | null;
  ebit: number | null;
  valorDeMercado: number | null;
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
      const inputs = prep.unwrap();

      const withTerms = ValuationCascade.evaluate(inputs);
      const withoutTermsResult = ValuationCascade.evaluate(
        new ValuationInputs({
          ticker: inputs.ticker,
          asOf: inputs.asOf,
          fundamentals: withoutTerms(inputs.fundamentals),
          marketPrice: inputs.marketPrice,
          capm: inputs.capm,
          marginOfSafety: inputs.marginOfSafety,
          projectionYears: inputs.projectionYears,
          perpetualGrowthCap: inputs.perpetualGrowthCap,
          sectorKey: inputs.sectorKey,
          industry: inputs.industry,
          inflation: inputs.inflation,
          declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
          prices: inputs.prices,
          isDistressed: inputs.isDistressed,
          unleveredBeta: inputs.unleveredBeta,
        }),
      );

      const published = new PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      const last = published.length === 0 ? null : published[published.length - 1]!;
      const marketValue = inputs.marketPrice * (last?.sharesOutstanding ?? Number.NaN);

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        via: withTerms.isOk ? withTerms.unwrap().model.name : null,
        justoCom: withTerms.isOk ? withTerms.unwrap().fairValue.reais : null,
        justoSem: withoutTermsResult.isOk ? withoutTermsResult.unwrap().fairValue.reais : null,
        minoritarios: last?.minorityInterest ?? null,
        equivalencia: last?.equityIncomeResult ?? null,
        ebit: last?.ebit ?? null,
        valorDeMercado: Number.isFinite(marketValue) ? marketValue : null,
      });
    }
    errln('');

    writeText('docs/validacao/ponte.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/ponte.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  outln(`\n=== D7 — A PONTE COMPLETA — ${l.length} ativos ===\n`);

  const withMinority = l.filter((e) => e.minoritarios !== null && Math.abs(e.minoritarios) > 0).length;
  const withEquityMethod = l.filter((e) => e.equivalencia !== null && e.equivalencia > 0).length;
  outln('-- quantos têm cada termo --');
  outln(`  com participação de não controladores: ${withMinority}`);
  outln(`  com equivalência patrimonial positiva: ${withEquityMethod}`);

  const weight = l
    .filter((e) => e.equivalencia !== null && e.ebit !== null && e.ebit > 0 && e.equivalencia > 0)
    .map((e) => e.equivalencia! / e.ebit!);
  if (weight.length > 0) {
    weight.sort(compareNum);
    outln(`  equivalência ÷ EBIT: mediana=${pc(median(weight)!)}  máx=${pc(weight[weight.length - 1]!)}  (n=${weight.length})`);
    outln(`  acima de 20% do EBIT: ${weight.filter((x) => x > 0.2).length}`);
  }

  const changes: { ticker: string; delta: number }[] = [];
  let evaluatedWith = 0;
  let evaluatedWithout = 0;
  for (const e of l) {
    const withInput = e.justoCom;
    const without = e.justoSem;
    if (withInput !== null && withInput > 0) evaluatedWith++;
    if (without !== null && without > 0) evaluatedWithout++;
    if (withInput === null || without === null || without <= 0 || withInput <= 0) continue;
    const d = withInput / without - 1;
    if (Math.abs(d) > 0.005) changes.push({ ticker: e.ticker, delta: d });
  }
  changes.sort((a, b) => compareNum(a.delta, b.delta));

  outln('\n-- o efeito da correção, na mesma série --');
  outln(`  avaliados com os termos: ${evaluatedWith}   sem eles: ${evaluatedWithout}`);
  outln(`  preços justos alterados além de 0,5%: ${changes.length}`);
  if (changes.length > 0) {
    const ds = changes.map((v) => v.delta);
    outln(`  variação mediana dos alterados: ${pc(median(ds)!)}`);
    outln(`  caem: ${ds.filter((d) => d < 0).length}   sobem: ${ds.filter((d) => d > 0).length}`);
    outln('  as maiores quedas:');
    for (const v of changes.slice(0, 6)) outln(`    ${v.ticker.padEnd(7)} ${pc(v.delta).padStart(9)}`);
    outln('  as maiores altas:');
    for (const v of [...changes].reverse().slice(0, 6)) outln(`    ${v.ticker.padEnd(7)} ${pc(v.delta).padStart(9)}`);
  }

  // O tamanho dos minoritários contra o valor de mercado, que é a régua da
  // materialidade: 24,1% na CSNA3 quando a sonda mediu.
  const ratios = l
    .filter((e) => e.minoritarios !== null && e.valorDeMercado !== null && e.valorDeMercado > 0 && e.minoritarios > 0)
    .map((e) => [e.ticker, e.minoritarios! / e.valorDeMercado!] as const)
    .sort((a, b) => compareNum(b[1], a[1]));
  if (ratios.length > 0) {
    outln('\n-- não controladores ÷ valor de mercado --');
    outln(`  mediana=${pc(median(ratios.map((r) => r[1]))!)}   acima de 10%: ${ratios.filter((r) => r[1] > 0.1).length}`);
    for (const r of ratios.slice(0, 8)) outln(`    ${r[0].padEnd(7)} ${pc(r[1]).padStart(7)}`);
  }
}
