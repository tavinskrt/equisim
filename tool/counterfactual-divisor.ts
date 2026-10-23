// O divisor da ponte: quanto custa a regra do maior, e o que o backtest vê.
//
// Duas perguntas, e a segunda foi descoberta ao tentar responder a primeira.
//
// **1.** `quotedShares` adota, na divergência, a **maior** das duas candidatas
// a divisor. Um grupamento societário reduz a contagem corrente sem tocar a do
// exercício, de modo que a candidata contábil fica maior sempre — e vence
// sempre. Quanto isso move o potencial dos afetados, e onde eles caem na
// ordenação que o usuário lê?
//
// **2.** A validação fora da amostra **não enxerga nada disso**.
// `tool/backtest-valuation.ts` reconstrói o valor de mercado de cada exercício
// como `contagem do exercício × preço da coorte` — o que é correto para não
// injetar a capitalização de hoje numa avaliação de 2018, mas faz as duas
// candidatas a divisor colapsarem na mesma, e a razão de unidade valer 1
// sempre. Esta ferramenta confere isso em vez de supor.
//
// Uso:
//   npm run tool -- counterfactual-divisor
import {
  compareNum,
  DateTime,
  FundamentalsSnapshot,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  ValuationCascade,
} from '../src/core';
import { jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/** Réplica da reescala do backtest, para conferir o que ela faz ao divisor. */
function asInBacktest(s: FundamentalsSnapshot, price: number): FundamentalsSnapshot {
  return new FundamentalsSnapshot({
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
    nopat: s.nopat,
    cash: s.cash,
    shortTermInvestments: s.shortTermInvestments,
    shortTermDebt: s.shortTermDebt,
    longTermDebt: s.longTermDebt,
    totalStockholderEquity: s.totalStockholderEquity,
    bookValuePerShare: s.bookValuePerShare,
    propertyPlantEquipment: s.propertyPlantEquipment,
    intangibleAssets: s.intangibleAssets,
    totalCurrentAssets: s.totalCurrentAssets,
    currentLiabilities: s.currentLiabilities,
    realizedShareCapital: s.realizedShareCapital,
    profitReserves: s.profitReserves,
    operatingCashFlow: s.operatingCashFlow,
    investmentCashFlow: s.investmentCashFlow,
    freeCashFlow: s.freeCashFlow,
    sharesOutstanding: s.sharesOutstandingAsOf,
    sharesOutstandingAsOf: s.sharesOutstandingAsOf,
    marketCap: s.sharesOutstandingAsOf !== null && s.sharesOutstandingAsOf > 0 && price > 0 ? s.sharesOutstandingAsOf * price : null,
    enterpriseToEbitda: null,
  });
}

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);

interface Row {
  ticker: string;
  preco: number;
  fonte: string;
  diverge: boolean;
  divisorAdotado: number;
  divisorDeMercado: number | null;
  razao: number | null;
  justoAdotado: number;
  justoPeloMercado: number | null;
  potencialAdotado: number;
  potencialPeloMercado: number | null;
}

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );
    const universe = (await ctx.fundamentals.universe()).unwrap();

    const rows: Row[] = [];
    let collapsed = 0;
    let checked = 0;

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
      });
      if (prep.isErr) continue;
      const inputs = prep.unwrap();
      const pub = new PointInTimeView(today).published(inputs.fundamentals);
      if (pub.length === 0) continue;
      const latest = pub[pub.length - 1]!;
      const price = inputs.marketPrice;

      // -- Pergunta 2: a reescala do backtest colapsa as candidatas? --------
      const rescaled = asInBacktest(latest, price);
      const uBack = ValuationCascade.quotedUnitRatio({
        sharesOutstanding: rescaled.sharesOutstanding,
        marketCap: rescaled.marketCap,
        marketPrice: price,
      });
      const qBack = ValuationCascade.quotedShares({
        latest: rescaled,
        marketPrice: price,
        sharesPerQuote: uBack,
        published: pub.map((s) => asInBacktest(s, price)),
      });
      if (qBack !== null) {
        checked++;
        // Tolerância, e não `=== 1.0`: este contador é o número que a
        // ferramenta existe para produzir, e uma razão que voltasse
        // 1,0000000000000002 o omitiria em silêncio.
        if (!qBack.diverge && Math.abs(uBack - 1.0) < 1e-9) collapsed++;
      }

      // -- Pergunta 1: o custo da regra do maior, hoje ----------------------
      const u = ValuationCascade.quotedUnitRatio({
        sharesOutstanding: latest.sharesOutstanding,
        marketCap: latest.marketCap,
        marketPrice: price,
      });
      const q = ValuationCascade.quotedShares({ latest, marketPrice: price, sharesPerQuote: u, published: pub });
      if (q === null) continue;

      const r = ValuationCascade.evaluate(inputs);
      if (r.isErr) continue;
      const res = r.unwrap();

      // O potencial é `E ÷ (P × N) − 1`. Trocar o divisor por N' reescala o
      // preço justo por N/N', e o potencial acompanha por identidade.
      const adopted = q.count;
      const market = q.fromMarketCap;
      const fairValue = res.fairValue.reais;
      const fairByMarket = market !== null && market > 0 ? (fairValue * adopted) / market : null;

      rows.push({
        ticker: ticker.value,
        preco: price,
        fonte: q.source.name,
        diverge: q.diverge,
        divisorAdotado: adopted,
        divisorDeMercado: market,
        razao: market !== null && market > 0 ? adopted / market : null,
        justoAdotado: fairValue,
        justoPeloMercado: fairByMarket,
        potencialAdotado: res.upside,
        potencialPeloMercado: fairByMarket === null ? null : fairByMarket / price - 1,
      });
    }
    process.stderr.write('\n');

    outln('== 2. O que a validação fora da amostra enxerga ==');
    outln('');
    outln(`  Sob a reescala do backtest, em ${checked} ativos:`);
    outln(`    candidatas colapsadas (u = 1 e sem divergência): ${collapsed} de ${checked}`);
    outln('  Ou seja: a razão de unidade e a regra do maior não são');
    outln('  exercitadas por coorte nenhuma. O potencial medido fora');
    outln('  da amostra não é o potencial que a tela mostra, para os');
    outln('  ativos em que essas duas peças decidem algo.');

    const affected = rows.filter((l) => l.fonte === 'reconciled' && l.diverge).sort((a, b) => compareNum(b.razao!, a.razao!));

    outln('');
    outln('');
    outln('== 1. O custo da regra do maior, hoje ==');
    outln('');
    outln(`  ${rows.length} avaliados; ${affected.length} com a contábil vencendo a divergência.`);
    outln('');
    outln('  ticker    divisor/merc   justo adotado   justo p/ merc    pot. adotado   pot. p/ merc');
    for (const l of affected) {
      outln(
        `  ${l.ticker.padEnd(8)} ${l.razao!.toFixed(2).padStart(11)}x   ${l.justoAdotado.toFixed(2).padStart(13)}   ` +
          `${l.justoPeloMercado === null ? '            —' : l.justoPeloMercado.toFixed(2).padStart(13)}` +
          `   ${pc(l.potencialAdotado).padStart(13)}   ${pc(l.potencialPeloMercado).padStart(13)}`,
      );
    }

    // Onde os afetados caem na ordenação que o usuário lê.
    const withUpside = [...rows].sort((a, b) => compareNum(b.potencialAdotado, a.potencialAdotado));
    outln('');
    outln(`  posição dos afetados na ordenação por potencial (${withUpside.length} avaliados):`);
    withUpside.forEach((l, k) => {
      if (l.fonte !== 'reconciled' || !l.diverge) return;
      outln(
        `    ${String(k + 1).padStart(3)}º  ${l.ticker.padEnd(8)} ${pc(l.potencialAdotado)}  →  pelo divisor de ` +
          `mercado seria ${pc(l.potencialPeloMercado)}`,
      );
    });

    writeText('docs/validacao/divisor_contrafactual.json', jsonPretty(rows));
    outln('');
    outln('  gravado em docs/validacao/divisor_contrafactual.json');
  } finally {
    await ctx.dispose();
  }
}
