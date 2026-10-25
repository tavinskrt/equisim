// O degrau da vantagem competitiva, medido antes de ser trocado.
//
// **Por que este utilitário existe.** A [decisão 35](../docs/decisoes/035-dcf-reverso-e-regressao-condicional.md)
// tirou do decaimento contínuo de `RONIC` o argumento que ele tinha: o terminal
// **não** é a causa do viés de nível, e trocá-lo não conserta o nível. A mesma
// decisão diz que quem propuser a troca depois dela precisa de outro argumento.
//
// **O outro argumento é este, e ele é medível:** a exceção de vantagem
// competitiva é um **degrau**. Quem passa nas cinco condições recebe
// `r_∞ + 0,30·(ROIC_ciclo − r_∞)`; quem falha em uma recebe `r_∞`. Duas
// empresas com rentabilidade praticamente igual, uma de cada lado do corte,
// saem com preços justos que diferem em dezenas de por cento — e a diferença
// não vem da economia delas, vem de onde o limiar caiu.
//
// É defeito da mesma família do que a [decisão 34](../docs/decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
// corrigiu na fronteira das vias: preço justo descontínuo numa grandeza
// contínua.
//
// **O que se mede aqui:**
//
//   1. O tamanho do degrau — quanto o preço justo salta entre `λ = 0` e
//      `λ = 0,30`, por ativo, e quanto disso está concentrado perto do corte.
//   2. A resposta do preço justo a `λ` ao longo de toda a faixa, para saber se
//      o degrau é a única descontinuidade.
//   3. Que `λ` a **persistência medida** do próprio ativo sugeriria, contra o
//      0,30 fixo. Se o `λ` estimado ficasse sempre perto de 0,30, a troca seria
//      cosmética e não vale as semanas.
//
// A persistência é estimada por AR(1) sobre o excedente `ROIC_t − r_∞`. Com
// oito a dezesseis pontos o estimador é enviesado para baixo — o viés de
// Kendall é da ordem de `−(1+3φ)/n` —, então o número **não** é usado como
// verdade: ele entra como ordem de grandeza, e o relatório diz isso.
//
// Uso:
//   npm run tool -- terminal-fade
//   npm run tool -- terminal-fade --limit 30
import {
  CapitalSeries,
  compareNum,
  DateTime,
  GrowthGuards,
  Inference,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  tryParseInt,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  ValuationModel,
  ValuationParameters,
  type YearExcess,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/**
 * Fração do excedente preservada na perpetuidade, na grade da varredura.
 *
 * `0` é o terminal neutro de hoje; `0,30` é o que a exceção concede a quem
 * passa. O resto da grade existe para mostrar a forma da resposta.
 */
const grid = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0];

function fairValue(inputs: ValuationInputs, terminal: number | null): number | null {
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker: inputs.ticker,
      asOf: inputs.asOf,
      fundamentals: inputs.fundamentals,
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
      terminalReturnOverride: terminal,
    }),
  );
  return r.isOk ? r.unwrap().fairValue.reais : null;
}

/**
 * Persistência do excedente por AR(1), sem intercepto forçado.
 *
 * Devolve `null` com menos de quatro variações — abaixo disso a inclinação
 * não é identificável e um número saindo dali seria ruído com casas decimais.
 */
function persistence(excess: readonly number[]): { phi: number; r2: number; n: number } | null {
  if (excess.length < 5) return null;
  const x = excess.slice(0, excess.length - 1);
  const y = excess.slice(1);
  const f = Inference.ols(x, y);
  if (f === null || !Number.isFinite(f.slope)) return null;
  return { phi: f.slope, r2: f.r2, n: x.length };
}

interface Row {
  ticker: string;
  setor: string | null;
  via: string;
  preco: number;
  justoProducao: number;
  potencial: number;
  rInfinito: number;
  roicCiclo: number;
  excedente: number;
  pesoTerminal: number;
  moatConcedido: boolean;
  lambdaAplicado: number;
  phiCru: number | null;
  phiAplicado: number | null;
  bloqueios: string[];
  folgaPorExcedente: number;
  curva: Record<string, number | null>;
  saltoDoDegrau: number | null;
  persistenciaPhi: number | null;
  persistenciaR2: number | null;
  persistenciaN: number | null;
  lambdaPorPersistencia: number | null;
  fracaoAnosComExcedente: number;
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
    errln(`universo: ${universe.length} ativos`);

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
      const baseResult = ValuationCascade.evaluate(inputs);
      if (baseResult.isErr) continue;
      const base = baseResult.unwrap();
      const rInf = base.diagnostics!.terminalDiscountRate;

      const lane = base.model === ValuationModel.dcfFcff ? ValuationLane.firm : ValuationLane.shareholder;
      const pub = new PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      const series = CapitalSeries.build(pub, lane);
      const cycle = series.cycleReturn({ window: ValuationParameters.cycleWindow });
      if (cycle === null || !Number.isFinite(cycle)) continue;

      const e0 = cycle - rInf;

      // Excedente por exercício, com o ano — a regressão de persistência só
      // pareia anos adjacentes, e sem o ano não teria como saber.
      const excesses: YearExcess[] = series.returns
        .filter((r) => Number.isFinite(r.value))
        .map((r) => ({ year: r.year, excess: r.value - rInf }));

      // O veredito completo, com as condições que barram e os dois valores de
      // persistência lado a lado.
      const verdict = GrowthGuards.residualMoat({
        cycleReturn: cycle,
        terminalDiscountRate: rInf,
        externalCapitalRatio: GrowthGuards.externalCapitalRatio(series),
        periods: series.length,
        excessReturns: excesses,
        projectionYears: inputs.projectionYears,
      });

      const curve: Record<string, number | null> = {};
      for (const lambda of grid) curve[lambda.toFixed(1)] = fairValue(inputs, e0 > 0 ? rInf + lambda * e0 : null);

      const noExcess = curve['0.0'] ?? null;
      const withDefault = curve['0.3'] ?? null;
      const jump = noExcess !== null && withDefault !== null && noExcess > 0 ? withDefault / noExcess - 1 : null;

      const p = persistence(excesses.map((e) => e.excess));
      const positiveYears = excesses.filter((x) => x.excess > 0).length / (excesses.length === 0 ? 1 : excesses.length);

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        via: lane.name,
        preco: inputs.marketPrice,
        justoProducao: base.fairValue.reais,
        potencial: base.upside,
        rInfinito: rInf,
        roicCiclo: cycle,
        excedente: e0,
        pesoTerminal: base.diagnostics!.terminalShare,
        moatConcedido: base.diagnostics!.moatApplied,
        lambdaAplicado: base.diagnostics!.terminalRetainedSpread,
        phiCru: verdict.rawPersistence,
        phiAplicado: verdict.persistence,
        bloqueios: verdict.blocks.map((b) => b.key),
        // A única fronteira de nível que restou: o excedente ser positivo.
        folgaPorExcedente: e0,
        curva: curve,
        saltoDoDegrau: jump,
        persistenciaPhi: p?.phi ?? null,
        persistenciaR2: p?.r2 ?? null,
        persistenciaN: p?.n ?? null,
        lambdaPorPersistencia: p === null ? null : power(p.phi, inputs.projectionYears),
        fracaoAnosComExcedente: positiveYears,
      });
    }
    errln('');

    writeText('docs/validacao/fade_terminal.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/fade_terminal.json (${output.length} ativos)`);
  } finally {
    await ctx.dispose();
  }
}

/**
 * `phi^n`, com `phi` negativo tratado como ausência de persistência.
 *
 * Excedente que troca de sinal de ano para ano não é vantagem que decai — é
 * oscilação, e elevar um número negativo a dez devolveria persistência
 * positiva por artefato de paridade.
 */
function power(phi: number, n: number): number {
  if (phi <= 0) return 0;
  let r = 1.0;
  for (let i = 0; i < n; i++) r *= phi;
  return r;
}

function printReport(rows: readonly Row[]): void {
  const med = (v: readonly number[]): number | null => {
    if (v.length === 0) return null;
    const s = [...v].sort(compareNum);
    const m = Math.floor(s.length / 2);
    return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
  };
  const pc = (x: number | null): string => (x === null ? '—' : `${(x * 100).toFixed(1)}%`);
  const at = (s: readonly number[], i: number): number => s[Math.floor(i)]!;

  const withExcess = rows.filter((e) => e.excedente > 0);
  const granted = rows.filter((e) => e.moatConcedido);

  outln(`\n=== O DEGRAU DA VANTAGEM COMPETITIVA — ${rows.length} avaliados ===\n`);
  outln(`com excedente positivo (ROIC do ciclo > r_infinito): ${withExcess.length}`);
  outln(`exceção concedida hoje:                              ${granted.length}`);

  // --- 1. O tamanho do degrau ---
  const jumps = withExcess.filter((e) => e.saltoDoDegrau !== null).map((e) => e.saltoDoDegrau!);
  outln('\n-- tamanho do degrau (justo em λ=0,30 contra λ=0) --');
  if (jumps.length > 0) {
    const s = [...jumps].sort(compareNum);
    outln(
      `  n=${s.length}  p25=${pc(at(s, s.length / 4))}  mediana=${pc(med(s))}  p75=${pc(at(s, (3 * s.length) / 4))}  ` +
        `máx=${pc(s[s.length - 1]!)}`,
    );
    outln(`  acima de 10%: ${s.filter((x) => x > 0.1).length}   acima de 25%: ${s.filter((x) => x > 0.25).length}`);
  }

  // --- 2. Quem está perto do corte ---
  //
  // A folga é a distância ao corte que menos falta. Perto de zero, dois ativos
  // economicamente iguais caem em lados diferentes.
  outln('\n-- ativos na vizinhança do corte (folga em ±3 p.p.) --');
  const neighbors = withExcess.filter((e) => Math.abs(margin(e)) <= 0.03).sort((a, b) => compareNum(margin(a), margin(b)));
  outln(`  ${neighbors.length} ativos`);
  for (const e of neighbors) {
    outln(
      `    ${e.ticker.padEnd(7)} folga=${(margin(e) * 100).toFixed(2).padStart(6)} p.p.  ` +
        `concedido=${e.moatConcedido ? 'sim' : 'não'}  salto=${pc(e.saltoDoDegrau).padStart(7)}  ROIC=${pc(e.roicCiclo)}`,
    );
  }

  // --- 3. O lambda que a produção passou a aplicar ---
  const applied = rows.filter((e) => e.lambdaAplicado > 0).map((e) => e.lambdaAplicado);
  outln('\n-- lambda EM PRODUÇÃO (decisão 36) --');
  outln(`  ativos com preservação > 0: ${applied.length} de ${rows.length}   (o degrau concedia a 8)`);
  if (applied.length > 0) {
    const s = [...applied].sort(compareNum);
    outln(
      `  λ: mediana=${med(s)!.toFixed(4)}  p75=${at(s, (3 * s.length) / 4).toFixed(4)}  ` +
        `p90=${at(s, (9 * s.length) / 10).toFixed(4)}  máx=${s[s.length - 1]!.toFixed(4)}   contra 0,3000 fixo`,
    );
    outln(`  acima de 0,30: ${s.filter((x) => x > 0.3).length}`);
  }

  // --- 4. Que lambda a persistência crua sugeriria ---
  const phis = withExcess.filter((e) => e.persistenciaPhi !== null).map((e) => e.persistenciaPhi!);
  const lambdas = withExcess.filter((e) => e.lambdaPorPersistencia !== null).map((e) => e.lambdaPorPersistencia!);
  outln('\n-- persistência medida do excedente (AR(1)) --');
  if (phis.length > 0) {
    const s = [...phis].sort(compareNum);
    outln(
      `  φ:  n=${s.length}  p25=${at(s, s.length / 4).toFixed(2)}  mediana=${med(s)!.toFixed(2)}  ` +
        `p75=${at(s, (3 * s.length) / 4).toFixed(2)}`,
    );
    outln(`  φ ≤ 0 (excedente oscila em vez de decair): ${s.filter((x) => x <= 0).length} de ${s.length}`);
  }
  if (lambdas.length > 0) {
    const s = [...lambdas].sort(compareNum);
    outln(`  λ = φ^10:  mediana=${med(s)!.toFixed(3)}  p90=${at(s, (9 * s.length) / 10).toFixed(3)}  contra 0,300 fixo`);
    outln(`  acima de 0,30: ${s.filter((x) => x > 0.3).length} de ${s.length}`);
  }
  const fractions = withExcess.map((e) => e.fracaoAnosComExcedente);
  if (fractions.length > 0) outln(`  fração de anos com excedente positivo: mediana=${med(fractions)!.toFixed(2)}`);
}

/** Distância à única fronteira de nível que restou: o excedente ser positivo. */
const margin = (e: Row): number => e.folgaPorExcedente;
