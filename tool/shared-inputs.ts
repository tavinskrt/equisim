// A1 — quanto da discordância entre as vias vem de medir a mesma coisa duas
// vezes?
//
// **A pergunta.** [`vias.md`](../docs/validacao/vias.md) mediu que as duas vias
// discordam além de 1,5× em 55 de 92 ativos. A
// [decisão 38](../docs/decisoes/038-transicao-continua-entre-as-vias.md) removeu
// o degrau que essa discordância produzia, e **não** a discordância. Antes de
// decidir se conciliá-las exige reconstruir a Porta 2, é preciso saber de onde
// ela vem.
//
// **A hipótese testável.** Uma empresa tem **um** crescimento e **uma** posição
// no ciclo. As duas vias os medem separadamente — sobre capital investido de um
// lado e patrimônio do outro — e chegam a números diferentes: mais de 3 p.p. de
// diferença no crescimento em 43 de 92, e fator de normalização fora de
// [0,8; 1,25] em 34. Se a discordância entre os preços justos colapsar ao impor
// os mesmos dois insumos, ela é do **medidor**, e o conserto é amarrá-los. Se
// não colapsar, ela é estrutural, e amarrar não resolve.
//
// **O que NÃO se compartilha, e é deliberado.** O retorno sobre o capital
// difere legitimamente entre as vias — ROE excede ROIC quando há alavancagem —,
// e a taxa de desconto também: WACC e Ke descontam fluxos diferentes. Impor
// esses seria apagar a economia do problema em vez de medi-la.
//
// **O empréstimo roda nos dois sentidos.** Compartilhar os insumos da firma e
// compartilhar os do acionista são experimentos diferentes, e concluir a partir
// de um só confundiria "a discordância colapsa" com "a via da firma tem razão".
//
// Uso:
//   npm run tool -- shared-inputs
//   npm run tool -- shared-inputs --limit 30
import {
  compareNum,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  tryParseInt,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/** Avalia forçando a via, e opcionalmente o crescimento e o fator de base. */
function evaluate(
  base: ValuationInputs,
  lane: ValuationLane,
  overrides: { growth?: number | null; factor?: number | null } = {},
): { fairValue: number; growth: number; factor: number } | null {
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
      laneOverride: lane,
      growthOverride: overrides.growth ?? null,
      baseFactorOverride: overrides.factor ?? null,
    }),
  );
  if (r.isErr) return null;
  const v = r.unwrap();
  if (v.fairValue.reais <= 0) return null;
  return { fairValue: v.fairValue.reais, growth: v.diagnostics!.growthRate, factor: v.diagnostics!.baseFactor };
}

/** Razão entre as duas vias sob um conjunto de insumos, ou `null`. */
function ratio(inputs: ValuationInputs, overrides: { growth?: number; factor?: number }): number | null {
  const f = evaluate(inputs, ValuationLane.firm, overrides);
  const a = evaluate(inputs, ValuationLane.shareholder, overrides);
  if (f === null || a === null || a.fairValue <= 0) return null;
  return f.fairValue / a.fairValue;
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/**
 * Resumo da dispersão de um conjunto de razões.
 *
 * A medida central é a **mediana de `|ln razão|`**: razão é grandeza
 * multiplicativa, e 0,5× e 2,0× são a mesma discordância em direções opostas.
 * Média de razões trataria as duas de forma diferente.
 */
function dispersion(ratios: readonly number[]): { medianAbsLog: number; outside15: number; outside20: number; n: number } {
  const logs = ratios.filter((r) => r > 0 && Number.isFinite(r)).map((r) => Math.abs(Math.log(r)));
  return {
    medianAbsLog: median(logs) ?? Number.NaN,
    outside15: ratios.filter((r) => r > 1.5 || r < 1 / 1.5).length,
    outside20: ratios.filter((r) => r > 2 || r < 0.5).length,
    n: ratios.length,
  };
}

interface Row {
  ticker: string;
  setor: string | null;
  preco: number;
  justoFirma: number;
  justoAcionista: number;
  crescimentoFirma: number;
  crescimentoAcionista: number;
  fatorFirma: number;
  fatorAcionista: number;
  razaoAtual: number;
  razaoCrescimentoDaFirma: number | null;
  razaoFatorDaFirma: number | null;
  razaoAmbosDaFirma: number | null;
  razaoAmbosDoAcionista: number | null;
}

type RatioKey = 'razaoAtual' | 'razaoCrescimentoDaFirma' | 'razaoFatorDaFirma' | 'razaoAmbosDaFirma' | 'razaoAmbosDoAcionista';

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
      });
      if (prep.isErr) continue;
      const inputs = prep.unwrap();

      const firm = evaluate(inputs, ValuationLane.firm);
      const shareholder = evaluate(inputs, ValuationLane.shareholder);
      if (firm === null || shareholder === null) continue;

      const r0 = firm.fairValue / shareholder.fairValue;

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        preco: inputs.marketPrice,
        justoFirma: firm.fairValue,
        justoAcionista: shareholder.fairValue,
        crescimentoFirma: firm.growth,
        crescimentoAcionista: shareholder.growth,
        fatorFirma: firm.factor,
        fatorAcionista: shareholder.factor,
        razaoAtual: r0,
        // Empréstimo no sentido firma → acionista.
        razaoCrescimentoDaFirma: ratio(inputs, { growth: firm.growth }),
        razaoFatorDaFirma: ratio(inputs, { factor: firm.factor }),
        razaoAmbosDaFirma: ratio(inputs, { growth: firm.growth, factor: firm.factor }),
        // E no sentido inverso, para separar "colapsa" de "a firma tem razão".
        razaoAmbosDoAcionista: ratio(inputs, { growth: shareholder.growth, factor: shareholder.factor }),
      });
    }
    errln('');

    writeText('docs/validacao/insumos_compartilhados.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/insumos_compartilhados.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  if (l.length === 0) {
    outln('nenhum ativo com as duas vias avaliáveis');
    return;
  }

  const col = (k: RatioKey): number[] =>
    l
      .map((e) => e[k])
      .filter((v): v is number => v !== null && Number.isFinite(v));

  outln(`\n=== A1 — INSUMOS COMPARTILHADOS — ${l.length} ativos ===\n`);

  // Quanto os dois insumos divergem entre as vias, para dimensionar o teste.
  const dg = l.map((e) => e.crescimentoFirma - e.crescimentoAcionista);
  const df = l
    // Guarda por magnitude: o fator é `double`, e um denominador de 1e-16
    // passaria por um teste de zero cravado e devolveria razão absurda.
    .filter((e) => Math.abs(e.fatorAcionista) > 1e-9)
    .map((e) => e.fatorFirma / e.fatorAcionista);
  outln('-- o quanto os insumos divergem --');
  outln(
    `  crescimento (firma − acionista): mediana=${((median(dg) ?? 0) * 100).toFixed(2)} p.p.   ` +
      `|dif| > 3 p.p. em ${dg.filter((x) => Math.abs(x) > 0.03).length} de ${dg.length}`,
  );
  outln(
    `  fator (firma ÷ acionista): mediana=${(median(df) ?? 0).toFixed(2)}x   fora de [0,8; 1,25] em ` +
      `${df.filter((x) => x < 0.8 || x > 1.25).length} de ${df.length}`,
  );

  const row = (label: string, key: RatioKey): void => {
    const d = dispersion(col(key));
    if (d.n === 0) {
      outln(`  ${label.padEnd(34)} —`);
      return;
    }
    outln(
      `  ${label.padEnd(34)} mediana|ln r|=${d.medianAbsLog.toFixed(3)}  ` +
        `fora de 1,5x: ${String(d.outside15).padStart(3)}/${d.n}  fora de 2x: ${String(d.outside20).padStart(3)}/${d.n}`,
    );
  };

  outln('\n-- dispersão da razão entre as vias --');
  row('como está hoje', 'razaoAtual');
  row('só o crescimento da firma', 'razaoCrescimentoDaFirma');
  row('só o fator da firma', 'razaoFatorDaFirma');
  row('ambos, da firma', 'razaoAmbosDaFirma');
  row('ambos, do acionista', 'razaoAmbosDoAcionista');

  // O veredito quantitativo: quanto da dispersão colapsa.
  const base = dispersion(col('razaoAtual'));
  for (const [label, key] of [
    ['ambos, da firma', 'razaoAmbosDaFirma'],
    ['ambos, do acionista', 'razaoAmbosDoAcionista'],
  ] as const) {
    const d = dispersion(col(key));
    if (d.n === 0 || !Number.isFinite(base.medianAbsLog)) continue;
    const collapse = 1 - d.medianAbsLog / base.medianAbsLog;
    outln(`\n  colapso com "${label}": ${(collapse * 100).toFixed(1)}% da dispersão mediana`);
  }
}
