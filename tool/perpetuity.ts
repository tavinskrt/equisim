// B15 — o beta e a estrutura de capital com que a perpetuidade é descontada.
//
// **O apontamento, e o que dele sobrou.** A lente `metodo` disse em 15/09/2026
// que a taxa de equilíbrio troca só a taxa livre de risco: mesmo beta, e — na
// via da firma — o WACC com o peso e a dívida **de hoje**. Metade disso caiu
// com a [decisão 105](../docs/decisoes/105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md):
// o aplicativo passou a resolver o caminho de taxas, e a alavancagem de
// equilíbrio virou a que a própria projeção alcança no ano N. **O beta não**:
// ele é o de hoje, estimado na janela de cinco anos, e vai à perpetuidade sem
// convergir.
//
// **O que este programa mede, sobre a entrada congelada do gabarito:**
//
//   1. a alavancagem de equilíbrio que o modelo produz, contra a de hoje e
//      contra a mediana do setor da B3 — o modelo chega a um estado
//      estacionário, ou só continua a tendência da projeção?
//   2. o efeito de convergir o beta de equilíbrio em direção a 1 (Blume, com
//      `w = 0,67`) sobre a taxa e sobre o preço justo;
//   3. o efeito de impor a alavancagem mediana do setor na perpetuidade.
//
// As duas alternativas entram por **imposição de diagnóstico**, como as demais:
// elas não são do aplicativo, e medir o efeito é o que permite ao registro
// escolher.
//
// Uso:
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- perpetuity
import {
  compareNum,
  compareStr,
  round,
  str,
  type Ticker,
  ValuationCascade,
  ValuationInputs,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';

const output = 'docs/validacao/perpetuidade.json';

/** O peso clássico de Blume: dois terços do beta do ativo, um terço do mercado. */
const blume = 0.67;

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/** Quantil pelo índice arredondado `round(p·(n−1))`. */
function quantile(v: readonly number[], p: number): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  return s[round(p * (s.length - 1))]!;
}

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);
const n = (v: number | null, c = 3): string => (v === null ? '—' : v.toFixed(c));

/** Os mesmos insumos com as imposições de equilíbrio do B15. */
const impose = (b: ValuationInputs, args: { betaWeight?: number; leverage?: number }): ValuationInputs =>
  new ValuationInputs({
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: b.capm,
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
    riskFreeCurve: b.riskFreeCurve,
    officialShares: b.officialShares,
    prices: b.prices,
    isDistressed: b.isDistressed,
    unleveredBeta: b.unleveredBeta,
    concessionEnd: b.concessionEnd,
    dividendsInBeta: b.dividendsInBeta,
    creditReferenceRiskFree: b.creditReferenceRiskFree,
    declaredSharesPerUnit: b.declaredSharesPerUnit,
    terminalBetaWeightOverride: args.betaWeight ?? null,
    terminalLeverageOverride: args.leverage ?? null,
  });

interface Row {
  ticker: string;
  setor: string | null;
  modelo: string;
  beta: number;
  justo: number;
  descontoTerminal: number | null;
  keTerminal: number | null;
  pesoEquityHoje: number | null;
  pesoEquityTerminal: number | null;
  deHoje: number | null;
  deTerminal: number | null;
  deMedianaDoSetor: number | null;
  justoComBlume: number | null;
  descontoTerminalComBlume: number | null;
  justoComSetor: number | null;
  descontoTerminalComSetor: number | null;
}

type NumericKey = { [K in keyof Row]: Row[K] extends number | null ? K : never }[keyof Row];

/**
 * `D/E` do que o motor avalia. Participação fora de `(0; 1,5]` não tem
 * alavancagem que se leia.
 */
function debtToEquityOf(r: ValuationResult): number | null {
  const s = r.diagnostics?.equityShare ?? null;
  if (s === null || s <= 0 || s > 1.5) return null;
  return (1 - s) / s;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    // --- Passo 1: a montagem de produção, e a alavancagem de cada ativo ----
    const base = new Map<string, ValuationResult>();
    const inputsOf = new Map<string, ValuationInputs>();
    const sectorOf = new Map<string, string>();
    const evaluated = new Map<Ticker, ValuationResult | null>();
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const inputs = prep.unwrap();
      const r = ValuationCascade.evaluate(inputs);
      evaluated.set(t, r.valueOrNull);
      if (r.isErr) continue;
      base.set(t.value, r.unwrap());
      inputsOf.set(t.value, inputs);
      const s = inputs.sectorKey;
      if (s !== null && s !== '') sectorOf.set(t.value, s);
    }
    errln('');

    const divergent = await c.checkAgainstAnswerKey(evaluated);

    // --- A mediana de alavancagem de cada setor, hoje ----------------------
    //
    // `D/E` do que o motor avalia, por setor da B3. É a alternativa que o item
    // propõe para o estado estacionário, e ela sai do dado que o projeto tem.
    const bySector = new Map<string, number[]>();
    for (const [key, value] of base) {
      const s = sectorOf.get(key);
      const debtToEquity = debtToEquityOf(value);
      if (s === undefined || debtToEquity === null) continue;
      if (!bySector.has(s)) bySector.set(s, []);
      bySector.get(s)!.push(debtToEquity);
    }
    const sectorMedian = new Map<string, number>();
    for (const [key, value] of bySector) {
      if (value.length >= 3) sectorMedian.set(key, median(value)!);
    }

    // --- Passo 2: as duas alternativas -------------------------------------
    const fairValue = (x: ValuationInputs): number | null => {
      const r = ValuationCascade.evaluate(x);
      return r.isOk ? r.unwrap().fairValue.reais : null;
    };
    const terminalRate = (x: ValuationInputs): number | null => {
      const r = ValuationCascade.evaluate(x);
      return r.isOk ? (r.unwrap().diagnostics?.terminalDiscountRate ?? null) : null;
    };

    const rows: Row[] = [];
    for (const [key, value] of base) {
      const inputs = inputsOf.get(key)!;
      const d = value.diagnostics;
      const target = sectorMedian.get(sectorOf.get(key) ?? '') ?? null;

      const withBlume = impose(inputs, { betaWeight: blume });
      const withSector = target === null ? null : impose(inputs, { leverage: target });
      const terminalShare = d?.terminalEquityShare ?? null;

      rows.push({
        ticker: key,
        setor: sectorOf.get(key) ?? null,
        modelo: value.model.name,
        beta: inputs.capm.beta,
        justo: value.fairValue.reais,
        descontoTerminal: d?.terminalDiscountRate ?? null,
        keTerminal: d?.terminalCostOfEquity ?? null,
        pesoEquityHoje: d?.equityShare ?? null,
        pesoEquityTerminal: terminalShare,
        deHoje: debtToEquityOf(value),
        // A mesma guarda de `debtToEquityOf`: participação não positiva não
        // tem `D/E`, e dividir por ela devolveria `Infinity`.
        deTerminal: terminalShare === null || terminalShare <= 0 ? null : (1 - terminalShare) / terminalShare,
        deMedianaDoSetor: target,
        justoComBlume: fairValue(withBlume),
        descontoTerminalComBlume: terminalRate(withBlume),
        justoComSetor: withSector === null ? null : fairValue(withSector),
        descontoTerminalComSetor: withSector === null ? null : terminalRate(withSector),
      });
    }

    writeText(
      output,
      jsonPretty(
        {
          medidoEm: frozenToday.toIso8601String().substring(0, 10),
          conferidoContraOGabarito: divergent?.length ?? null,
          pesoDeBlume: blume,
          medianaDeAlavancagemPorSetor: Object.fromEntries(sectorMedian),
          ativos: rows,
        },
        ' ',
      ),
    );
    printReport(rows, sectorMedian, divergent);
    errln(`\nescrito ${output} (${rows.length})`);
  } finally {
    await c.ctx.dispose();
  }
}

function printReport(l: readonly Row[], sectorMedian: ReadonlyMap<string, number>, divergent: readonly string[] | null): void {
  if (divergent === null) {
    outln('\n!! sem gabarito para conferir');
  } else if (divergent.length > 0) {
    outln(`\n!! a montagem DIVERGE do gabarito em ${divergent.length} ativo(s) — os números abaixo não valem`);
  } else {
    outln('\nmontagem idêntica à do gabarito.');
  }

  const col = (k: NumericKey): number[] =>
    l.map((e) => e[k]).filter((v): v is number => v !== null && Number.isFinite(v));

  const resolved = l.filter((e) => e.deTerminal !== null);
  outln('\n=== B15 — A PERPETUIDADE ===');
  outln(`avaliados: ${l.length}   com taxas resolvidas: ${resolved.length}`);

  outln('\n-- a alavancagem D/E --');
  for (const [name, k] of [
    ['hoje', 'deHoje'],
    ['no ano N (o do modelo)', 'deTerminal'],
    ['mediana do setor, hoje', 'deMedianaDoSetor'],
  ] as const) {
    const v = col(k);
    outln(
      `  ${name.padEnd(24)} p25 ${n(quantile(v, 0.25), 2)}  mediana ${n(median(v), 2)}  p75 ${n(quantile(v, 0.75), 2)}  (n=${v.length})`,
    );
  }
  const pairs = resolved.filter((e) => e.deHoje !== null).map((e) => e.deTerminal! - e.deHoje!);
  outln(`  o ano N contra hoje: mediana ${n(median(pairs), 2)}, sobe em ${pairs.filter((x) => x > 0).length} de ${pairs.length}`);

  outln('\n-- mediana de D/E por setor da B3 --');
  for (const [key, value] of [...sectorMedian].sort((a, b) => compareStr(a[0], b[0]))) {
    outln(`  ${key.padEnd(32)} ${n(value, 2)}`);
  }

  outln(`\n-- o efeito de convergir o beta (Blume, w = ${str(blume)}) --`);
  effect(l, 'justoComBlume', 'descontoTerminalComBlume');

  outln('\n-- o efeito de impor a alavancagem mediana do setor --');
  effect(l, 'justoComSetor', 'descontoTerminalComSetor');
}

function effect(
  l: readonly Row[],
  fairKey: 'justoComBlume' | 'justoComSetor',
  rateKey: 'descontoTerminalComBlume' | 'descontoTerminalComSetor',
): void {
  const ratios: number[] = [];
  const rateDelta: number[] = [];
  let some = 0;
  for (const e of l) {
    const a = e.justo;
    const b = e[fairKey];
    const rateA = e.descontoTerminal;
    const rateB = e[rateKey];
    if (b === null) {
      some++;
      continue;
    }
    if (Math.abs(a) > 1e-9) ratios.push(b / a - 1);
    if (rateA !== null && rateB !== null) rateDelta.push(rateB - rateA);
  }
  outln(`  taxa de equilíbrio: mediana ${pc(median(rateDelta))}  p10 ${pc(quantile(rateDelta, 0.1))}  p90 ${pc(quantile(rateDelta, 0.9))}`);
  outln(
    `  preço justo:        mediana ${pc(median(ratios))}  p10 ${pc(quantile(ratios, 0.1))}  p90 ${pc(quantile(ratios, 0.9))}  ` +
      `(sobe em ${ratios.filter((x) => x > 0).length} de ${ratios.length})`,
  );
  if (some > 0) outln(`  deixam de ser avaliados: ${some}`);
}
