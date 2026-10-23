// A discordância entre as duas vias, medida ativo a ativo.
//
// **A pergunta.** A pós-condição da ponte de equity escolhe entre a via da
// firma e a do acionista por um limiar — 20% de participação do capital
// próprio. A [decisão 37](../docs/decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md)
// mostrou que a escolha decide muito: nove ativos trocaram de via ao receber a
// alíquota certa, e caíram de 58,9% a 92,1%. Na VBBR3 as duas vias diferem por
// 12,7×.
//
// A [decisão 34](../docs/decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
// registrou isso e não o resolveu: "Isto não concilia as duas vias, que seguem
// discordando por medirem crescimento e base em séries de capital diferentes".
// Conciliar exige primeiro saber o tamanho e a forma da discordância.
//
// **Em teoria elas não deveriam discordar.** `FCFF/WACC` e `FCFE/Ke` são a
// mesma avaliação vista de dois lados, e coincidem quando os insumos são
// consistentes entre si. A distância entre elas é, portanto, uma medida direta
// de **inconsistência interna do motor** — e não uma diferença de método.
//
// Uso:
//   npm run tool -- lanes
//   npm run tool -- lanes --limit 30
import {
  compareNum,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  tryParseInt,
  ValuationCascade,
  ValuationCaveat,
  ValuationInputs,
  ValuationLane,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

interface LaneReading {
  fairValue: number;
  growth: number;
  returnRate: number;
  discount: number;
  terminalDiscount: number;
  baseFactor: number;
  stake: number;
  terminalWeight: number;
  resolvedFlag: boolean;
}

/** Avalia o ativo forçando uma via, sem roteamento e sem migração. */
function byLane(base: ValuationInputs, lane: ValuationLane): LaneReading | null {
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
      // Sem isto a via da firma aqui seria a **anterior** às decisões 41 a 44:
      // interpolação de dois pontos e ponte `EV − D`. A comparação mediria
      // o motor velho contra a via do acionista.
      unleveredBeta: base.unleveredBeta,
      laneOverride: lane,
    }),
  );
  if (r.isErr) return null;
  const v = r.unwrap();
  const d = v.diagnostics!;
  if (v.fairValue.reais <= 0) return null;
  return {
    fairValue: v.fairValue.reais,
    growth: d.growthRate,
    returnRate: d.returnOnCapital,
    discount: v.discountRate,
    terminalDiscount: d.terminalDiscountRate,
    baseFactor: d.baseFactor,
    stake: d.equityShare,
    terminalWeight: d.terminalShare,
    // O aviso da decisão 42 é quem declara qual dos dois caminhos valeu.
    resolvedFlag: v.warnings.some((a) => a.includes('resolvido ano a ano')),
  };
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

interface Row {
  ticker: string;
  setor: string | null;
  preco: number;
  viaProducao: string;
  justoProducao: number;
  justoFirma: number;
  justoAcionista: number;
  razaoFirmaAcionista: number;
  participacaoFirma: number;
  crescimentoFirma: number;
  crescimentoAcionista: number;
  retornoFirma: number;
  retornoAcionista: number;
  fatorBaseFirma: number;
  fatorBaseAcionista: number;
  descontoFirma: number;
  descontoAcionista: number;
  pesoTerminalFirma: number;
  pesoTerminalAcionista: number;
  erroFirma: number;
  erroAcionista: number;
  temBetaU: boolean;
  firmaResolvida: boolean;
  mesclado: boolean;
  migrou: boolean;
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

    // O prior do beta é o que dá à via da firma o caminho de taxas resolvido
    // das decisões 41 a 44. Sem ele, esta medição compararia a via do
    // acionista contra a firma **antiga**.
    const prior = await ResolveBetaPrior.call({
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: today,
    });
    errln(prior === null ? 'sem prior de beta: a via da firma fica na interpolação' : `prior de beta: ${prior.unleveredBySector.size} setores`);

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

      const production = ValuationCascade.evaluate(inputs);
      if (production.isErr) continue;
      const p = production.unwrap();

      const firm = byLane(inputs, ValuationLane.firm);
      const shareholder = byLane(inputs, ValuationLane.shareholder);
      if (firm === null || shareholder === null) continue;

      const ratio = firm.fairValue / shareholder.fairValue;

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        preco: inputs.marketPrice,
        viaProducao: p.model.name,
        justoProducao: p.fairValue.reais,
        justoFirma: firm.fairValue,
        justoAcionista: shareholder.fairValue,
        razaoFirmaAcionista: ratio,
        participacaoFirma: firm.stake,
        // As três fontes de divergência que a decisão 34 nomeou.
        crescimentoFirma: firm.growth,
        crescimentoAcionista: shareholder.growth,
        retornoFirma: firm.returnRate,
        retornoAcionista: shareholder.returnRate,
        fatorBaseFirma: firm.baseFactor,
        fatorBaseAcionista: shareholder.baseFactor,
        descontoFirma: firm.discount,
        descontoAcionista: shareholder.discount,
        pesoTerminalFirma: firm.terminalWeight,
        pesoTerminalAcionista: shareholder.terminalWeight,
        // Qual das duas o preço de mercado prefere.
        erroFirma: Math.abs(firm.fairValue / inputs.marketPrice - 1),
        erroAcionista: Math.abs(shareholder.fairValue / inputs.marketPrice - 1),
        // **A pergunta que D2 faz depois da decisão 43.** A discordância só é
        // defeito onde ela decide: onde o motor tem as duas vias disponíveis e
        // escolhe uma.
        temBetaU: inputs.unleveredBeta !== null,
        firmaResolvida: firm.resolvedFlag,
        mesclado: p.diagnostics!.caveats.includes(ValuationCaveat.mergedLanes),
        migrou: p.diagnostics!.caveats.includes(ValuationCaveat.migratedLane),
      });
    }
    errln('');

    writeText('docs/validacao/vias.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/vias.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  if (l.length === 0) {
    outln('nenhum ativo com as duas vias avaliáveis');
    return;
  }
  const col = (k: 'razaoFirmaAcionista' | 'erroFirma' | 'erroAcionista'): number[] =>
    l.map((e) => e[k]).filter((v) => Number.isFinite(v));
  const pc = (x: number | null): string => (x === null ? '—' : `${(x * 100).toFixed(1)}%`);

  outln(`\n=== DISCORDÂNCIA ENTRE AS VIAS — ${l.length} ativos com as duas avaliáveis ===\n`);

  const r = col('razaoFirmaAcionista').sort(compareNum);
  const at = (i: number): string => r[Math.floor(i)]!.toFixed(2);
  outln('-- razão justo(firma) ÷ justo(acionista) --');
  outln(
    `  p10=${at(r.length / 10)}x  p25=${at(r.length / 4)}x  mediana=${median(r)!.toFixed(2)}x  ` +
      `p75=${at((3 * r.length) / 4)}x  p90=${at((9 * r.length) / 10)}x`,
  );
  const outside2 = r.filter((x) => x > 2 || x < 0.5).length;
  const outside15 = r.filter((x) => x > 1.5 || x < 1 / 1.5).length;
  outln(`  discordam além de 1,5x: ${outside15} de ${r.length}   além de 2x: ${outside2}`);

  // --- De onde vem a divergência ---
  outln('\n-- as três fontes que a decisão 34 nomeou --');
  const dg = l.map((e) => e.crescimentoFirma - e.crescimentoAcionista);
  const df = l.map((e) => e.fatorBaseFirma / e.fatorBaseAcionista);
  const dd = l.map((e) => e.descontoFirma - e.descontoAcionista);
  outln(`  crescimento: firma − acionista, mediana=${pc(median(dg))}   |dif| > 3 p.p. em ${dg.filter((x) => Math.abs(x) > 0.03).length}`);
  outln(
    `  fator de base: firma ÷ acionista, mediana=${median(df)!.toFixed(2)}x   fora de [0,8; 1,25] em ` +
      `${df.filter((x) => x < 0.8 || x > 1.25).length}`,
  );
  outln(`  desconto: WACC − Ke, mediana=${pc(median(dd))}   |dif| > 2 p.p. em ${dd.filter((x) => Math.abs(x) > 0.02).length}`);

  // --- Qual via o preço prefere ---
  let firmWins = 0;
  let shareholderWins = 0;
  for (const e of l) {
    if (e.erroFirma < e.erroAcionista) firmWins++;
    else shareholderWins++;
  }
  outln('\n-- qual via fica mais perto do preço de mercado --');
  outln(`  firma: ${firmWins}    acionista: ${shareholderWins}`);
  outln(`  erro |justo/preço − 1| mediano: firma=${pc(median(col('erroFirma')))}  acionista=${pc(median(col('erroAcionista')))}`);

  // --- A discordância ainda decide? ---
  //
  // Ela só é defeito onde decide: onde o motor tem as duas vias disponíveis e
  // escolhe uma. Com a rota derivada da decisão 43 a via da firma não migra
  // mais, e o roteamento por Porta 1 e Porta 3 não é escolha entre
  // alternativas — é a única opção disponível para aquele ativo.
  const withBeta = l.filter((e) => e.firmaResolvida).length;
  const merged = l.filter((e) => e.mesclado).length;
  const migrated = l.filter((e) => e.migrou).length;
  outln('\n-- a discordância ainda DECIDE alguma coisa? --');
  outln(`  com caminho resolvido (rota derivada): ${withBeta} de ${l.length}`);
  outln(`  ainda mesclados (dois estimadores):    ${merged}`);
  outln(`  ainda migrados:                        ${migrated}`);

  // --- A faixa exposta ao limiar ---
  const exposed = l
    .filter((e) => e.participacaoFirma < 0.35 && e.participacaoFirma > 0.05)
    .sort((a, b) => compareNum(a.participacaoFirma, b.participacaoFirma));
  outln('\n-- ativos na faixa exposta (participação entre 5% e 35%) --');
  outln(`  ${exposed.length} ativos`);
  for (const e of exposed.slice(0, 20)) {
    outln(
      `    ${e.ticker.padEnd(7)} s=${pc(e.participacaoFirma).padStart(6)}  ` +
        `firma=${e.justoFirma.toFixed(2).padStart(8)}  acionista=${e.justoAcionista.toFixed(2).padStart(8)}` +
        `  razão=${e.razaoFirmaAcionista.toFixed(2)}x  produção=${e.viaProducao}`,
    );
  }
}
