// D2b — o destino da via do acionista sobre LPA.
//
// **A pergunta.** A [decisão 45](../docs/decisoes/045-estrutura-de-capital-recusada.md)
// tirou da via do acionista o papel de segundo estimador: nos 90 ativos em que
// as duas vias são calculáveis, nenhum resultado mescla e nenhum migra. Ela
// continua, porém, sendo **a única via** para instituição financeira (Porta 1),
// para quem não sustenta lucro operacional (Porta 3) e para quem tem a
// estrutura de capital recusada. Nesses ela decide sozinha.
//
// **A inconsistência a medir.** Desde a decisão 41 a via da firma resolve o
// custo do capital próprio ano a ano contra a alavancagem que a própria
// avaliação produz. A via do acionista não: ela desconta ao `Ke` do CAPM com o
// beta alavancado de hoje, e supõe essa alavancagem perene. **O motor tem dois
// custos de capital próprio para o mesmo ativo**, e nunca os comparou.
//
// Uso:
//   npm run tool -- equity-route
//   npm run tool -- equity-route --limit 30
import {
  compareNum,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  round,
  tryParseInt,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/** Avalia o ativo forçando uma via, sem roteamento e sem migração. */
function byLane(base: ValuationInputs, lane: ValuationLane): ValuationResult | null {
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker: base.ticker,
      asOf: base.asOf,
      fundamentals: base.fundamentals,
      marketPrice: base.marketPrice,
      capm: base.capm,
      marginOfSafety: base.marginOfSafety,
      projectionYears: base.projectionYears,
      perpetualGrowthCap: base.perpetualGrowthCap,
      sectorKey: base.sectorKey,
      industry: base.industry,
      inflation: base.inflation,
      declaredTerminalRiskFreeRate: base.declaredTerminalRiskFreeRate,
      prices: base.prices,
      isDistressed: base.isDistressed,
      unleveredBeta: base.unleveredBeta,
      laneOverride: lane,
    }),
  );
  return r.isOk ? r.unwrap() : null;
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number): string => `${(v * 100).toFixed(1)}%`;
const pp = (v: number): string => `${(v * 100).toFixed(2)} p.p.`;

interface Row {
  ticker: string;
  setor: string | null;
  preco: number;
  viaProducao: string;
  justoProducao: number;
  potencial: number;
  porta1Financeira: boolean;
  porta3FluxoFraco: boolean;
  estruturaRecusada: boolean;
  temBetaU: boolean;
  keAcionistaResolvido: boolean;
  keAcionistaAno1: number | null;
  keAcionistaTerminal: number | null;
  keResolvidoTerminal: number | null;
  waccResolvidoTerminal: number | null;
  justoFirma: number | null;
  justoAcionista: number | null;
}

export async function main(args: string[]): Promise<void> {
  const limitIndex = args.indexOf('--limit');
  const limit = limitIndex >= 0 ? (tryParseInt(args[limitIndex + 1] ?? '') ?? 0) : 0;

  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    let universe = (await ctx.fundamentals.universe()).unwrap();
    if (limit > 0 && universe.length > limit) universe = universe.slice(0, limit);

    const prior = await ResolveBetaPrior.call({
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: today,
    });

    const output: Row[] = [];
    let i = 0;
    let refusedCount = 0;
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

      const production = ValuationCascade.evaluate(inputs);
      if (production.isErr) {
        refusedCount++;
        continue;
      }
      const p = production.unwrap();

      // Qual porta mandou o ativo para a via do acionista.
      const financial = p.warnings.some((w) => w.startsWith('Instituição financeira:'));
      const weakFlow = p.warnings.some((w) => w.startsWith('O lucro operacional não se sustenta'));
      const refusedStructure = p.warnings.some((w) => w.includes('não sustenta a via da firma'));

      // O `Ke` que cada via usa, para o mesmo ativo.
      const firm = byLane(inputs, ValuationLane.firm);
      const shareholder = byLane(inputs, ValuationLane.shareholder);

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        preco: inputs.marketPrice,
        viaProducao: p.model.name,
        justoProducao: p.fairValue.reais,
        potencial: p.upside,
        porta1Financeira: financial,
        porta3FluxoFraco: weakFlow,
        estruturaRecusada: refusedStructure,
        temBetaU: inputs.unleveredBeta !== null,
        // Desde a decisão 46 a via do acionista resolve o próprio `Ke` contra
        // a alavancagem — menos em instituição financeira, onde a captação é
        // insumo do negócio e a realavancagem não teria sentido. Onde não
        // resolve, o `Ke` abaixo é o do CAPM sobre o beta alavancado de hoje,
        // suposto perene.
        keAcionistaResolvido: shareholder?.warnings.some((w) => w.includes('resolvido ano a ano')) ?? false,
        keAcionistaAno1: shareholder?.discountRate ?? null,
        keAcionistaTerminal: shareholder?.diagnostics?.terminalDiscountRate ?? null,
        // `Ke` resolvido contra a alavancagem, quando a via da firma o produz.
        keResolvidoTerminal: firm?.diagnostics?.terminalCostOfEquity ?? null,
        waccResolvidoTerminal: firm?.diagnostics?.terminalDiscountRate ?? null,
        justoFirma: firm?.fairValue.reais ?? null,
        justoAcionista: shareholder?.fairValue.reais ?? null,
      });
    }
    errln('');

    writeText('docs/validacao/via_acionista.json', jsonPretty(output, ' '));
    printReport(output, refusedCount);
    errln(`\nescrito docs/validacao/via_acionista.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[], refusedCount: number): void {
  outln(`\n=== D2b — A VIA DO ACIONISTA — ${l.length} avaliados (${refusedCount} recusados) ===\n`);

  const byShareholder = l.filter((e) => e.viaProducao === 'dcfEarnings');
  const p1 = byShareholder.filter((e) => e.porta1Financeira).length;
  const p3 = byShareholder.filter((e) => e.porta3FluxoFraco).length;
  const rec = byShareholder.filter((e) => e.estruturaRecusada).length;

  outln('-- quem a via do acionista avalia em produção --');
  outln(`  pela via do acionista: ${byShareholder.length} de ${l.length}`);
  outln(`    Porta 1 (instituição financeira): ${p1}`);
  outln(`    Porta 3 (lucro operacional não sustentado): ${p3}`);
  outln(`    estrutura de capital recusada: ${rec}`);
  outln(`    sem porta declarada: ${byShareholder.length - p1 - p3 - rec}`);

  // A inconsistência: dois `Ke` para o mesmo ativo.
  const withBoth = l.filter((e) => e.keAcionistaTerminal !== null && e.keResolvidoTerminal !== null);
  const resolvedShareholder = l.filter((e) => e.keAcionistaResolvido).length;
  outln('\n-- a via do acionista resolve o próprio Ke? --');
  outln(`  resolvem: ${resolvedShareholder} de ${l.length}`);
  outln(`    entre os que ela avalia em produção: ${byShareholder.filter((e) => e.keAcionistaResolvido).length} de ${byShareholder.length}`);
  outln(`    instituição financeira (exceção declarada): ${p1}`);

  outln('\n-- dois custos de capital próprio para o mesmo ativo --');
  outln(`  ativos com os dois medidos: ${withBoth.length}`);
  if (withBoth.length > 0) {
    const delta = withBoth.map((e) => e.keResolvidoTerminal! - e.keAcionistaTerminal!);
    const sortedEntries = [...delta].sort(compareNum);
    const q = (f: number): number => sortedEntries[round((sortedEntries.length - 1) * f)]!;
    outln('  Ke resolvido − Ke do CAPM (equilíbrio):');
    outln(`    p10=${pp(q(0.1))}  mediana=${pp(median(delta)!)}  p90=${pp(q(0.9))}`);
    outln(
      `    |dif| > 1 p.p. em ${delta.filter((d) => Math.abs(d) > 0.01).length} de ${delta.length}   ` +
        `> 3 p.p. em ${delta.filter((d) => Math.abs(d) > 0.03).length}`,
    );
    outln(`    o resolvido é MAIOR em ${delta.filter((d) => d > 0).length} de ${delta.length}`);
  }

  // Nos que a via do acionista decide sozinha, o Ke resolvido existe?
  const decidesAlone = byShareholder.filter((e) => !e.porta1Financeira);
  const withResolved = decidesAlone.filter((e) => e.keResolvidoTerminal !== null).length;
  outln('\n-- onde a via do acionista decide sozinha, fora da Porta 1 --');
  outln(`  ativos: ${decidesAlone.length}`);
  outln(`  com Ke resolvido disponível (a via da firma o produz): ${withResolved}`);
  if (decidesAlone.length > 0) {
    const d = decidesAlone
      .filter((e) => e.keResolvidoTerminal !== null && e.keAcionistaTerminal !== null)
      .map((e) => e.keResolvidoTerminal! - e.keAcionistaTerminal!);
    if (d.length > 0) {
      outln(
        `  Ke resolvido − Ke do CAPM: mediana=${pp(median(d)!)}   |dif| > 1 p.p. em ` +
          `${d.filter((x) => Math.abs(x) > 0.01).length} de ${d.length}`,
      );
    }
    outln('  os que decide sozinha:');
    const ord = [...decidesAlone].sort((a, b) => compareNum(b.potencial, a.potencial));
    for (const e of ord.slice(0, 15)) {
      const ke = e.keAcionistaTerminal;
      const resolvedKe = e.keResolvidoTerminal;
      outln(
        `    ${e.ticker.padEnd(7)} potencial=${pc(e.potencial).padStart(8)}  ` +
          `Ke=${ke === null ? '  —  ' : pc(ke).padStart(6)}  ` +
          `Ke*=${resolvedKe === null ? '  —  ' : pc(resolvedKe).padStart(6)}  ` +
          `${e.porta3FluxoFraco ? 'porta3' : ''}${e.estruturaRecusada ? 'recusada' : ''}`,
      );
    }
  }
}
