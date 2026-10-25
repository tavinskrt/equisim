// D8 — a perpetuidade aplicada a contrato que acaba.
//
// **A pergunta.** O valor terminal do motor é perpétuo para todo ativo. Uma
// concessão — rodovia, transmissão, saneamento, aeroporto — tem prazo, e no
// fim dele o ativo reverte ao poder concedente. Descontar fluxo perpétuo de um
// contrato que acaba em doze anos não é aproximação, é outra empresa.
//
// **O que a fonte não dá.** Prazo de concessão. Não há campo, e não haveria
// como haver: uma concessionária tem dezenas de contratos com vencimentos
// diferentes.
//
// **O que ela dá.** A base de ativos e a amortização anual. Numa concessão o
// ativo é registrado como intangível e amortizado **ao longo do prazo do
// contrato** — de modo que `(imobilizado + intangível) ÷ D&A` é a vida
// remanescente média da base, e numa concessionária ela É o prazo médio
// remanescente. Em empresa comum a mesma razão mede vida útil de máquina, que
// é outra coisa; por isso a medida sozinha não classifica nada, e a
// classificação vem do setor.
//
// Uso:
//   npm run tool -- concession
import {
  clamp,
  compareNum,
  DateTime,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  ValuationCascade,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number): string => `${(v * 100).toFixed(1)}%`;

/**
 * Fração do valor terminal perpétuo que sobra ao truncá-lo em [years].
 *
 * ```
 * VT_finito / VT_perpétuo = 1 − ((1 + g) / (1 + r))^anos
 * ```
 *
 * É a soma de uma progressão geométrica: a perpetuidade é a série infinita, e
 * truncá-la remove a cauda, que vale `((1+g)/(1+r))^anos` do total.
 */
export function remainingFraction(args: { years: number; g: number; r: number }): number {
  const { years, g, r } = args;
  if (!Number.isFinite(years) || years <= 0) return 0.0;
  if (r <= g) return 1.0;
  const tail = Math.pow((1 + g) / (1 + r), years);
  const v = 1 - tail;
  return Number.isFinite(v) ? clamp(v, 0.0, 1.0) : 1.0;
}

interface Row {
  ticker: string;
  setor: string | null;
  subsetor: string | null;
  via: string;
  justo: number;
  preco: number;
  pesoTerminal: number;
  crescimentoPerpetuo: number;
  descontoTerminal: number;
  vidaRemanescente: number | null;
  exerciciosComVida: number;
  intangivel: number | null;
  imobilizado: number | null;
  moat: boolean;
  lambda: number;
  retornoTerminal: number | null;
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
      const v = r.unwrap();
      const d = v.diagnostics!;

      const pub = new PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      if (pub.length === 0) continue;

      // Vida remanescente da base, medida na mediana dos exercícios: um ano
      // isolado com baixa/reavaliação distorce a razão.
      const lives: number[] = [];
      for (const s of pub) {
        const base = (s.propertyPlantEquipment ?? 0) + (s.intangibleAssets ?? 0);
        const dAndA = s.depreciationAndAmortization;
        if (dAndA === null || dAndA <= 0 || base <= 0) continue;
        const years = base / dAndA;
        if (Number.isFinite(years) && years > 0 && years < 200) lives.push(years);
      }
      const last = pub[pub.length - 1]!;

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        subsetor: inputs.industry,
        via: v.model.name,
        justo: v.fairValue.reais,
        preco: inputs.marketPrice,
        pesoTerminal: d.terminalShare,
        crescimentoPerpetuo: d.growthRate,
        descontoTerminal: d.terminalDiscountRate,
        vidaRemanescente: median(lives),
        exerciciosComVida: lives.length,
        intangivel: last.intangibleAssets,
        imobilizado: last.propertyPlantEquipment,
        // O que o terminal promete: excedente de retorno preservado na
        // perpetuidade. Num contrato com prazo, ele é a promessa mais forte
        // que o motor faz — e a que o contrato mais claramente nega.
        moat: d.moatApplied,
        lambda: d.terminalRetainedSpread,
        retornoTerminal: d.terminalReturnOnCapital,
      });
    }
    errln('');

    writeText('docs/validacao/concessao.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/concessao.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

/**
 * Subsetores que operam sob contrato de prazo determinado no Brasil.
 *
 * **É classificação, não parâmetro.** Nenhum número sai daqui; o que sai é a
 * pergunta "este negócio tem data para acabar?", e ela se responde pelo
 * rótulo da fonte.
 */
const concessionTerms = [
  'energia eletrica',
  'agua e saneamento',
  'exploracao de rodovias',
  'transporte ferroviario',
  'aeroportu',
  'concessao',
  'servicos de transporte',
];

function isConcession(e: Row): boolean {
  const sub = normalize(e.subsetor ?? '');
  const sector = normalize(e.setor ?? '');
  if (sector === 'saneamento' || sector === 'infraestrutura') return true;
  return concessionTerms.some((t) => sub.includes(t));
}

function normalize(v: string): string {
  const accented = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const plain = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  let b = '';
  for (const ch of v.toLowerCase()) {
    const i = accented.indexOf(ch);
    b += i >= 0 ? plain[i]!.toLowerCase() : ch;
  }
  return b;
}

function printReport(l: readonly Row[]): void {
  outln(`\n=== D8 — A PERPETUIDADE SOBRE CONTRATO COM PRAZO — ${l.length} ===\n`);

  // --- 1. O indicador que parecia servir, e não serve ---------------------
  const concessions = l.filter(isConcession);
  const remainder = l.filter((e) => !isConcession(e));
  const lives = (xs: readonly Row[]): number[] => xs.filter((e) => e.vidaRemanescente !== null).map((e) => e.vidaRemanescente!);
  const vc = lives(concessions).sort(compareNum);
  const vr = lives(remainder).sort(compareNum);
  const at = (xs: readonly number[], p: number): number => xs[Math.floor(xs.length * p)]!;
  outln('-- (imobilizado + intangível) ÷ D&A identifica concessão? --');
  if (vc.length > 0 && vr.length > 0) {
    outln(
      `  concessionárias: mediana=${median(vc)!.toFixed(1)} anos  p10=${at(vc, 0.1).toFixed(1)}  ` +
        `p90=${at(vc, 0.9).toFixed(1)}  (n=${vc.length})`,
    );
    outln(
      `  as demais:       mediana=${median(vr)!.toFixed(1)} anos  p10=${at(vr, 0.1).toFixed(1)}  ` +
        `p90=${at(vr, 0.9).toFixed(1)}  (n=${vr.length})`,
    );
    // Sobreposição: fração das concessionárias dentro do intervalo central das
    // demais. Alta sobreposição = o indicador não distingue.
    const q1 = at(vr, 0.25);
    const q3 = at(vr, 0.75);
    const within = vc.filter((x) => x >= q1 && x <= q3).length;
    outln(`  concessionárias dentro do miolo das demais (${q1.toFixed(1)}–${q3.toFixed(1)} anos): ${within} de ${vc.length}`);
  }

  // --- 2. A exposição, que existe independentemente do indicador ----------
  outln('\n-- exposição: quem opera sob prazo --');
  outln(`  ativos em setor de concessão: ${concessions.length} de ${l.length}`);
  const weights = concessions.map((e) => e.pesoTerminal);
  if (weights.length > 0) {
    outln(`  peso do terminal neles: mediana=${pc(median(weights)!)}  acima de 50%: ${weights.filter((x) => x > 0.5).length}`);
  }
  const withMoat = concessions.filter((e) => e.moat);
  outln(`  **com excedente de retorno preservado na perpetuidade: ${withMoat.length}**`);
  for (const e of withMoat) {
    outln(`    ${e.ticker.padEnd(7)} λ=${e.lambda.toFixed(4)}  terminal=${pc(e.pesoTerminal)}  ${e.subsetor}`);
  }

  // --- 3. O tamanho do que não se pode corrigir sem o prazo ---------------
  outln('\n-- se o contrato acabasse em N anos, quanto do preço justo sobraria --');
  for (const years of [10.0, 20.0, 30.0]) {
    const effects: number[] = [];
    for (const e of concessions) {
      const remaining = remainingFraction({ years, g: e.crescimentoPerpetuo, r: e.descontoTerminal });
      effects.push(1 + e.pesoTerminal * (remaining - 1));
    }
    if (effects.length === 0) continue;
    outln(`  ${years.toFixed(0).padStart(2)} anos → preço justo × ${median(effects)!.toFixed(2)} na mediana  (n=${effects.length})`);
  }
}
