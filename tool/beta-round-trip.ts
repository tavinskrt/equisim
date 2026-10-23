// A ida e a volta do beta não se cancelam.
//
// **O defeito.** O beta é desalavancado contra a dívida **bruta** sobre o valor
// de mercado, e realavancado contra a dívida **líquida** sobre o capital
// próprio que o modelo produz:
//
// ```
// β_U   = β_L / (1 + (1 − τ)·D_bruta/E_mercado)     ← prepare-valuation-inputs
// β_L,t = β_U · (1 + (1 − τ)·D_líquida/E_modelo)    ← levered-rates
// ```
//
// As duas contas usam alavancagens diferentes, de modo que o `β_L` que volta
// não é o que saiu. Numa empresa com caixa alto a diferença é o caixa inteiro:
// a ida divide por um fator grande e a volta multiplica por um pequeno.
//
// **O que isto mede.** O tamanho da distância entre as duas alavancagens e o
// que ela faz com o beta e com o custo do capital próprio.
//
// Uso:
//   npm run tool -- beta-round-trip
import {
  BetaCalculator,
  type BetaEstimate,
  BetaShrinkage,
  CapitalSeries,
  compareNum,
  DateRange,
  DateTime,
  intDiv,
  MarketAnchors,
  PointInTimeView,
  type PricePoint,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  round,
  type ShrunkBeta,
  ValuationCascade,
  ValuationParameters,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);
const millisecondsPerDay = 86_400_000;

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);
const pp = (v: number): string => `${(v * 100).toFixed(2)} p.p.`;

interface Row {
  ticker: string;
  deJanela: number | null;
  exerciciosNaJanela: number;
  alavancagemPorAno: { ano: number; de: number }[];
  setor: string | null;
  aliquota: number;
  dividaBruta: number;
  dividaLiquida: number;
  valorDeMercado: number;
  vmPorPrecoEAcoes: number | null;
  deBruta: number;
  deLiquida: number;
  fatorBruta: number;
  fatorLiquida: number;
  razaoDosFatores: number;
  betaAlavancado: number;
  betaDesalavancado: number | null;
  premio: number;
  caixaLiquido: boolean;
  betaCru: number | null;
  erroPadrao: number | null;
  peso: number | null;
  desalavancadoDoCru: number | null;
  desalavancadoDoEncolhido: number | null;
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
      const r = ValuationCascade.evaluate(inputs);
      if (r.isErr) continue;

      const pub = new PointInTimeView(inputs.asOf).published(inputs.fundamentals).filter((s) => s.hasIncomeStatement);
      if (pub.length === 0) continue;
      const last = pub[pub.length - 1]!;
      const marketValue = last.marketCap;
      if (marketValue === null || marketValue <= 0) continue;

      const tau = CapitalSeries.structuralTaxRate(pub, { statutoryRate: ValuationParameters.statutoryTaxRate }) ?? ValuationParameters.statutoryTaxRate;

      const grossDebtToEquity = last.totalDebt / marketValue;
      const netDebtToEquity = last.netDebt / marketValue;
      const grossFactor = BetaShrinkage.leverageFactor({ debtToEquity: grossDebtToEquity, taxRate: tau });
      const netFactor = BetaShrinkage.leverageFactor({ debtToEquity: netDebtToEquity, taxRate: tau });
      if (grossFactor === null || netFactor === null) continue;

      // O `Ke` do primeiro ano é afim no beta, de modo que a distância entre
      // os dois betas vira distância no custo do capital próprio pelo prêmio.
      const betaU = inputs.unleveredBeta;
      const betaL = inputs.capm.beta;

      // O peso do encolhimento, refeito aqui com os mesmos insumos: é ele que
      // diz quanto da decisão 40 chega ao preço. O beta cru vem de refazer a
      // regressão — `PrepareValuationInputs` devolve só o encolhido.
      let shrunk: ShrunkBeta | null = null;
      let raw: BetaEstimate | null = null;
      // A mesma janela em que o beta é estimado.
      const window = new DateRange(DateTime.local(today.year - PrepareValuationInputs.betaWindowYears, today.month, today.day), today);
      const seriesResult = await ctx.prices.daily(ticker, window);
      const marketResult = await ctx.benchmark.ibovespa(window);
      if (seriesResult.isOk && marketResult.isOk && prior !== null) {
        const series = seriesResult.unwrap();
        const market = marketResult.unwrap();
        const points = series.points.filter((p) => window.contains(p.date));
        if (points.length >= 2 && market.points.length >= 30) {
          const pair = BetaCalculator.alignReturns({
            assetDates: points.map((p) => p.date),
            assetIndex: points.map((p) => p.close),
            marketDates: market.dates,
            marketIndex: market.points.map((p) => p.close),
          });
          const est = BetaCalculator.estimate({ returns: pair });
          if (est.isOk) {
            raw = est.unwrap();
            shrunk = BetaShrinkage.shrink({
              leveredBeta: raw.beta,
              standardError: raw.standardError,
              prior,
              sectorKey: inputs.sectorKey,
              debtToEquity: netDebtToEquity,
              taxRate: tau,
            });
          }
        }
      }

      // --- A alavancagem ao longo da janela do beta ---------------------
      //
      // O beta é covariância de cinco anos; a alavancagem que o desalavanca é
      // a foto de hoje. Se a empresa desalavancou no período, a foto é menor
      // que a média e o `β_U` sai grande demais.
      const byYear: { ano: number; de: number }[] = [];
      if (seriesResult.isOk) {
        const points = seriesResult.unwrap().points;
        const inDays = (x: DateTime): number => intDiv(DateTime.utc(x.year, x.month, x.day).millisecondsSinceEpoch, millisecondsPerDay);
        for (const ex of pub) {
          if (!window.contains(ex.fiscalPeriodEnd)) continue;
          const shares = ex.sharesOutstandingAsOf;
          if (shares === null || shares <= 0) continue;
          // Preço do fechamento mais próximo do fim do exercício.
          let nearest: PricePoint | null = null;
          let smallestDistance = 1 << 30;
          const fiscalYearEnd = inDays(ex.fiscalPeriodEnd);
          for (const pt of points) {
            const d = Math.abs(inDays(pt.date) - fiscalYearEnd);
            if (d < smallestDistance) {
              smallestDistance = d;
              nearest = pt;
            }
          }
          if (nearest === null || smallestDistance > 20) continue;
          const yearMarketValue = nearest.close * shares;
          const debtToEquity = ex.debtToMarketEquity(yearMarketValue);
          if (debtToEquity === null) continue;
          byYear.push({ ano: ex.fiscalPeriodEnd.year, de: debtToEquity });
        }
      }
      const windowDebtToEquity = median(byYear.map((x) => x.de));

      output.push({
        ticker: ticker.value,
        deJanela: windowDebtToEquity,
        exerciciosNaJanela: byYear.length,
        alavancagemPorAno: byYear,
        setor: inputs.sectorKey,
        aliquota: tau,
        dividaBruta: last.totalDebt,
        dividaLiquida: last.netDebt,
        valorDeMercado: marketValue,
        // O valor de mercado que a fonte publica contra o que o preço de tela
        // e a contagem de ações produzem. Divergir aqui contamina a
        // alavancagem que desalavanca o beta.
        vmPorPrecoEAcoes: last.sharesOutstanding === null ? null : inputs.marketPrice * last.sharesOutstanding,
        deBruta: grossDebtToEquity,
        deLiquida: netDebtToEquity,
        fatorBruta: grossFactor,
        fatorLiquida: netFactor,
        // Quanto o beta desalavancado muda ao trocar a alavancagem da ida.
        razaoDosFatores: grossFactor / netFactor,
        betaAlavancado: betaL,
        betaDesalavancado: betaU,
        premio: inputs.capm.marketPremium,
        caixaLiquido: last.netDebt < 0,
        betaCru: raw?.beta ?? null,
        erroPadrao: raw?.standardError ?? null,
        peso: shrunk?.weight ?? null,
        // O desalavancado como era — do beta cru — e como passou a ser.
        desalavancadoDoCru: raw === null ? null : BetaShrinkage.unlever({ leveredBeta: raw.beta, debtToEquity: netDebtToEquity, taxRate: tau }),
        desalavancadoDoEncolhido: shrunk?.unlevered ?? null,
      });
    }
    errln('');

    writeText('docs/validacao/beta_ida_volta.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/beta_ida_volta.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  outln(`\n=== A IDA E A VOLTA DO BETA — ${l.length} avaliados ===\n`);

  const at = (s: readonly number[], p: number): number => s[Math.floor(s.length * p)]!;

  const ratios = l.map((e) => e.razaoDosFatores).sort(compareNum);
  const q = (f: number): number => ratios[round((ratios.length - 1) * f)]!;
  outln('-- fator da ida ÷ fator da volta --');
  outln(`  p10=${q(0.1).toFixed(3)}  mediana=${median(ratios)!.toFixed(3)}  p90=${q(0.9).toFixed(3)}`);
  outln(`  acima de 1,10: ${ratios.filter((x) => x > 1.1).length}  acima de 1,50: ${ratios.filter((x) => x > 1.5).length}`);
  outln(`  **o beta que volta é menor que o medido em ${ratios.filter((x) => x > 1.0001).length} de ${ratios.length}**`);

  const withCash = l.filter((e) => e.caixaLiquido);
  outln('\n-- empresas com caixa líquido --');
  outln(`  ${withCash.length} de ${l.length}`);
  outln('  nelas a dívida líquida é negativa e o fator da volta é o piso: a ida divide e a volta não multiplica de volta.');

  // O que a distância vale no custo do capital próprio.
  const deltas: number[] = [];
  for (const e of l) {
    const bu = e.betaDesalavancado;
    if (bu === null) continue;
    const premium = e.premio;
    const fb = e.fatorBruta;
    const netFactor = e.fatorLiquida;
    // Beta que a volta produz hoje contra o que produziria se a ida usasse a
    // mesma alavancagem — na alavancagem do ano zero, que é a de mercado.
    const now = bu * netFactor;
    const coherent = bu * (fb / netFactor) * netFactor;
    deltas.push((coherent - now) * premium);
  }
  if (deltas.length > 0) {
    deltas.sort(compareNum);
    const dq = (f: number): number => deltas[round((deltas.length - 1) * f)]!;
    outln('\n-- o que isso vale no custo do capital próprio --');
    outln(`  p10=${pp(dq(0.1))}  mediana=${pp(median(deltas)!)}  p90=${pp(dq(0.9))}`);
    outln(`  acima de 1 p.p.: ${deltas.filter((x) => x > 0.01).length}  acima de 3 p.p.: ${deltas.filter((x) => x > 0.03).length}`);
  }

  const weights = l
    .filter((e) => e.peso !== null)
    .map((e) => e.peso!)
    .sort(compareNum);
  if (weights.length > 0) {
    outln('\n-- peso do próprio ativo no encolhimento --');
    outln(`  p10=${at(weights, 0.1).toFixed(3)}  mediana=${median(weights)!.toFixed(3)}  p90=${at(weights, 0.9).toFixed(3)}`);
    outln(`  abaixo de 0,90: ${weights.filter((x) => x < 0.9).length} de ${weights.length}`);
    const diff: number[] = [];
    for (const e of l) {
      const a = e.desalavancadoDoCru;
      const b = e.desalavancadoDoEncolhido;
      // Magnitude, e não igualdade: o divisor é um beta desalavancado, e um
      // resíduo de ponto flutuante ali produziria razão sem sentido.
      if (a === null || b === null || Math.abs(a) < 1e-9) continue;
      diff.push(Math.abs(b / a - 1));
    }
    if (diff.length > 0) {
      diff.sort(compareNum);
      outln(`  |desalavancado do encolhido ÷ do cru − 1|: mediana=${pc(median(diff)!)}  p90=${pc(at(diff, 0.9))}`);
    }
  }

  // --- A janela contra a foto -------------------------------------------
  const withWindow = l.filter((e) => e.deJanela !== null && e.exerciciosNaJanela >= 3);
  if (withWindow.length > 0) {
    outln('\n-- alavancagem: a foto de hoje contra a janela do beta --');
    outln(`  ativos com ao menos três exercícios na janela: ${withWindow.length} de ${l.length}`);
    const ratios2: number[] = [];
    for (const e of withWindow) {
      const todayFactor = BetaShrinkage.leverageFactor({ debtToEquity: e.deLiquida, taxRate: e.aliquota });
      const windowFactor = BetaShrinkage.leverageFactor({ debtToEquity: e.deJanela!, taxRate: e.aliquota });
      if (todayFactor === null || windowFactor === null || todayFactor <= 0) continue;
      ratios2.push(windowFactor / todayFactor);
    }
    ratios2.sort(compareNum);
    if (ratios2.length > 0) {
      outln(`  fator da janela ÷ fator de hoje: p10=${at(ratios2, 0.1).toFixed(3)}  mediana=${median(ratios2)!.toFixed(3)}  p90=${at(ratios2, 0.9).toFixed(3)}`);
      outln(`  distante mais de 10%: ${ratios2.filter((x) => Math.abs(x - 1) > 0.1).length}  mais de 25%: ${ratios2.filter((x) => Math.abs(x - 1) > 0.25).length}`);
      outln(`  a janela é MAIS alavancada em ${ratios2.filter((x) => x > 1).length} de ${ratios2.length}`);
    }
    const gap = (e: Row): number => Math.abs(e.deJanela! - e.deLiquida);
    const ord2 = [...withWindow].sort((a, b) => compareNum(gap(b), gap(a)));
    outln(`  ${'ativo'.padEnd(8)}${'hoje'.padStart(9)}${'janela'.padStart(10)}${'anos'.padStart(6)}`);
    for (const e of ord2.slice(0, 8)) {
      outln(`  ${e.ticker.padEnd(8)}${pc(e.deLiquida).padStart(9)}${pc(e.deJanela).padStart(10)}${String(e.exerciciosNaJanela).padStart(6)}`);
    }
  }

  const deviations: { ticker: string; ratio: number }[] = [];
  for (const e of l) {
    const marketValue = e.valorDeMercado;
    const alt = e.vmPorPrecoEAcoes;
    if (alt === null || alt <= 0 || marketValue <= 0) continue;
    deviations.push({ ticker: e.ticker, ratio: alt / marketValue });
  }
  if (deviations.length > 0) {
    const rs = deviations.map((d) => d.ratio).sort(compareNum);
    outln('\n-- o valor de mercado publicado confere? --');
    outln(`  preço × ações ÷ marketCap: p10=${at(rs, 0.1).toFixed(3)}  mediana=${median(rs)!.toFixed(3)}  p90=${at(rs, 0.9).toFixed(3)}`);
    outln(`  fora de [0,9; 1,1]: ${rs.filter((x) => x < 0.9 || x > 1.1).length} de ${rs.length}  fora de [0,5; 2,0]: ${rs.filter((x) => x < 0.5 || x > 2.0).length}`);
    const worst2 = [...deviations].sort((a, b) => compareNum(b.ratio, a.ratio));
    for (const d of worst2.slice(0, 6)) outln(`    ${d.ticker.padEnd(8)} ${d.ratio.toFixed(1)}×`);
  }

  const worst = [...l].sort((a, b) => compareNum(b.razaoDosFatores, a.razaoDosFatores));
  outln('\n-- onde a distância é maior --');
  outln(`  ${'ativo'.padEnd(8)}${'D/E bruta'.padStart(11)}${'D/E líq'.padStart(10)}${'ida÷volta'.padStart(11)}`);
  for (const e of worst.slice(0, 10)) {
    outln(`  ${e.ticker.padEnd(8)}${pc(e.deBruta).padStart(11)}${pc(e.deLiquida).padStart(10)}${e.razaoDosFatores.toFixed(3).padStart(11)}`);
  }
}
