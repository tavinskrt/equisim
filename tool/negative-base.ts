// O exercício-base no prejuízo, e o que o motor faz com ele.
//
// **O caso.** `npm run tool -- refusals` mostra sete ativos saindo por "os
// dados não sustentam nenhuma das duas vias": USIM3, USIM5, PCAR3, CSAN3,
// LWSA3, AZEV4 e HBSA3. Em quase todos a causa é a mesma — o último exercício
// publicado veio no prejuízo, o fluxo-base sai não positivo, e a cascata
// recusa.
//
// **Por que isso é defeito e não prudência.** O motor já normaliza o
// exercício-base contra a mediana do ciclo quando ele destoa: é a Guarda 1, e
// ela existe justamente porque um exercício não descreve a empresa. Só que o
// fator é `ciclo ÷ atual`, e ele exige `atual > 0` — de modo que a correção
// funciona para o pico e desliga no vale. Numa siderúrgica, o vale é metade do
// ciclo.
//
// **O que isto mede.** Quantos são, qual o retorno do ciclo deles, e o que a
// normalização daria se soubesse operar no vale.
//
// Uso:
//   npm run tool -- negative-base
import {
  CapitalSeries,
  compareStr,
  CyclicalSectors,
  DateTime,
  GrowthGuards,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  ValuationCascade,
  ValuationLane,
  ValuationParameters,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);

interface Row {
  ticker: string;
  via: string;
  setor: string | null;
  subsetor: string | null;
  ciclico: boolean;
  retornoAtual: number;
  retornoCiclo: number | null;
  quedaOperacional: number | null;
  exercicios: number;
  fracaoPositiva: number | null;
  capitalAtual: number | null;
  anosNegativos: number;
  avaliado: boolean;
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

      const disclosed = new PointInTimeView(inputs.asOf).published(inputs.fundamentals).filter((s) => s.hasIncomeStatement);
      if (disclosed.length === 0) continue;

      const taxRate = CapitalSeries.structuralTaxRate(disclosed, { statutoryRate: ValuationParameters.statutoryTaxRate });

      for (const lane of ValuationLane.values) {
        const series = CapitalSeries.build(disclosed, lane, { firmTaxRate: lane === ValuationLane.firm ? taxRate : null });
        if (series.isTooShort) continue;
        const current = series.latestReturn;
        if (current === null || current > 0) continue;

        const cycle = series.cycleReturn({ window: ValuationParameters.cycleWindow });
        const decline = GrowthGuards.recentOperationalDecline(disclosed);
        const cyclical = CyclicalSectors.hasCyclePrecedence({ sectorKey: inputs.sectorKey, industry: inputs.industry });
        const r = ValuationCascade.evaluate(inputs);
        const returns = series.returns;

        output.push({
          ticker: ticker.value,
          via: lane.name,
          setor: inputs.sectorKey,
          subsetor: inputs.industry,
          ciclico: cyclical,
          retornoAtual: current,
          retornoCiclo: cycle,
          quedaOperacional: decline,
          exercicios: disclosed.length,
          // Quantos dos últimos oito exercícios vieram no prejuízo: um vale é
          // um; quatro seguidos é outra empresa.
          fracaoPositiva: series.positiveShare({ window: ValuationParameters.cycleWindow }),
          capitalAtual: series.latestBase,
          anosNegativos: returns.slice(returns.length > 8 ? returns.length - 8 : 0).filter((x) => x.value <= 0).length,
          avaliado: r.isOk,
          recusa: r.isErr ? r.failureOrNull!.message : null,
        });
      }
    }
    process.stderr.write('\n');

    writeText('docs/validacao/base_negativa.json', jsonPretty(output));
    printReport(output);
    errln(`\nescrito docs/validacao/base_negativa.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  outln('\n=== EXERCÍCIO-BASE NO PREJUÍZO ===\n');
  const tickers = new Set(l.map((e) => e.ticker));
  outln(`  ativos com retorno corrente não positivo: ${tickers.size}`);
  const refusedCount = new Set(l.filter((e) => !e.avaliado).map((e) => e.ticker));
  outln(`  destes, recusados pelo motor: ${refusedCount.size}`);

  const withPositiveCycle = l.filter((e) => e.retornoCiclo !== null && e.retornoCiclo > 0);
  outln(`  linhas com ciclo positivo medível: ${withPositiveCycle.length} de ${l.length}`);

  outln(
    `\n  ${'ativo'.padEnd(8)}${'via'.padEnd(13)}${'atual'.padStart(8)}${'ciclo'.padStart(9)}${'queda'.padStart(9)}` +
      `${'neg/8'.padStart(7)}  cíclico  situação`,
  );
  const ord = [...l].sort((a, b) => compareStr(a.ticker, b.ticker));
  for (const e of ord) {
    outln(
      `  ${e.ticker.padEnd(8)}${e.via.padEnd(13)}${pc(e.retornoAtual).padStart(8)}${pc(e.retornoCiclo).padStart(9)}` +
        `${pc(e.quedaOperacional).padStart(9)}${String(e.anosNegativos).padStart(7)}` +
        `  ${(e.ciclico ? 'sim' : 'não').padEnd(7)}  ${e.avaliado ? 'avaliado' : 'RECUSADO'}`,
    );
  }
}
