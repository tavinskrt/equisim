// B19 — a rentabilidade reverte à média? Em quanto tempo, e para onde?
//
// **A pergunta que o B12 deixou.** O terminal neutro mantém, para sempre, o
// retorno que o capital instalado alcança na projeção — e medido, esse retorno
// é de 0,71 vez o custo de capital na mediana
// ([terminal_excedente.md](../docs/validacao/terminal_excedente.md)). A
// [decisão 107](../docs/decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md)
// manteve o número por não haver medição de reversão à média; trocá-lo por
// `capital_N` move +14,1% do preço justo na mediana. Esta é a medição.
//
// **Duas perguntas, e só as duas juntas decidem.**
//
//   1. **Velocidade.** O quanto da vantagem — ou da desvantagem — de um ano
//      sobrevive ao seguinte? Persistência `φ` por AR(1) sobre o spread do
//      `ROIC` contra a mediana transversal do ano, no painel inteiro e ativo a
//      ativo, com a meia-vida que ela implica.
//   2. **Destino.** Reverter **para onde**? Converger o terminal ao custo de
//      capital supõe que a rentabilidade do mercado chega lá. Se a mediana do
//      `ROIC` do universo vive abaixo do custo de capital, convergir o terminal
//      a `r` não é reversão à média — é inventar uma rentabilidade que a seção
//      transversal nunca teve.
//
// **O `ROIC` é o do motor**, de `CapitalSeries.returns`: `lucro_t ÷ base_{t−1}`,
// na convenção da via da firma, sobre a mesma série limpa que a cascata usa.
//
// Uso:
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- roic-reversion
import {
  CapitalSeries,
  compareNum,
  PointInTimeView,
  round,
  type Ticker,
  ValuationCascade,
  ValuationLane,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';
import { Regression } from './validation/regression';

const output = 'docs/validacao/reversao_roic.json';

/**
 * Mínimo de exercícios para um ativo entrar no AR(1) próprio.
 *
 * Oito pares: abaixo disso o estimador de `φ` é dominado pelo viés de
 * pequena amostra, que é da ordem de `−(1 + 3φ)/n`.
 */
const minPeers = 8;

/** Horizontes em que o spread é seguido, em anos. */
const horizons = [1, 3, 5, 10];

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

/**
 * Meia-vida implícita numa persistência anual: `ln(0,5) ÷ ln(φ)`.
 *
 * `null` fora de `(0, 1)`: com `φ` não positivo não há decaimento a medir, e
 * com `φ ≥ 1` não há reversão.
 */
function halfLife(phi: number): number | null {
  if (!(phi > 0 && phi < 1)) return null;
  const ln2 = 0.6931471805599453;
  return ln2 / -ln(phi);
}

/**
 * Logaritmo por iteração de Newton sobre `exp`, como a medição original fazia
 * — trocar pelo `Math.log` mudaria o último dígito da meia-vida gravada.
 */
function ln(x: number): number {
  let y = 0.0;
  for (let i = 0; i < 80; i++) {
    const e = exp(y);
    y += (2 * (x - e)) / (x + e);
  }
  return y;
}

function exp(x: number): number {
  let term = 1.0;
  let sum = 1.0;
  for (let i = 1; i < 60; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

interface Survival {
  pares: number;
  spreadInicialAlto: number;
  spreadFinalAlto: number;
  sobraAlto: number;
  spreadInicialBaixo: number;
  spreadFinalBaixo: number;
  sobraBaixo: number;
}

interface Result {
  medidoEm: string;
  conferidoContraOGabarito: number | null;
  ativosComSerie: number;
  painel: { pares: number; phi: number | null; t: number | null; r2: number | null; meiaVidaAnos: number | null };
  porAtivo: { ativos: number; paresMedianos: number | null; phiP25: number | null; phiMediano: number | null; phiP75: number | null };
  sobrevivenciaDoSpread: Record<string, Survival>;
  nivelDoMercado: {
    medianaRoicPorAno: { ano: number; medianaRoic: number; ativos: number }[];
    medianaRoicDoPeriodo: number | null;
    medianaCustoDeCapital: number | null;
    ativosComCusto: number;
  };
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    // --- O painel de ROIC, do mesmo jeito que a cascata o lê ---------------
    const seriesOf = new Map<string, Map<number, number>>();
    const costOf = new Map<string, number>();
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
      const cost = r.valueOrNull?.diagnostics?.terminalDiscountRate ?? null;
      if (cost !== null) costOf.set(t.value, cost);

      const published = new PointInTimeView(frozenToday).published(inputs.fundamentals);
      const series = CapitalSeries.build(published, ValuationLane.firm);
      const returns = series.returns;
      if (returns.length < 3) continue;
      seriesOf.set(t.value, new Map(returns.map((x) => [x.year, x.value])));
    }
    errln('');

    const divergent = await c.checkAgainstAnswerKey(evaluated);

    // --- A mediana transversal de cada ano ---------------------------------
    const years = [...new Set([...seriesOf.values()].flatMap((s) => [...s.keys()]))].sort(compareNum);
    const yearMedian = new Map<number, number>();
    const yearCount = new Map<number, number>();
    for (const year of years) {
      const xs = [...seriesOf.values()].filter((s) => s.has(year)).map((s) => s.get(year)!);
      yearCount.set(year, xs.length);
      // Anos de ponta têm poucos papéis, e uma mediana de cinco ativos não é
      // a do mercado: eles entram no painel mas não definem referência.
      if (xs.length >= 20) yearMedian.set(year, median(xs)!);
    }

    // --- O spread contra a mediana do ano ----------------------------------
    const spread = new Map<string, Map<number, number>>();
    for (const [key, values] of seriesOf) {
      const m = new Map<number, number>();
      for (const [year, value] of values) {
        const med = yearMedian.get(year);
        if (med === undefined) continue;
        m.set(year, value - med);
      }
      if (m.size >= 3) spread.set(key, m);
    }

    // --- 1. AR(1) no painel inteiro ----------------------------------------
    const x0: number[] = [];
    const x1: number[] = [];
    for (const s of spread.values()) {
      for (const [year, value] of s) {
        const next = s.get(year + 1);
        if (next === undefined) continue;
        x0.push(value);
        x1.push(next);
      }
    }
    const panel = Regression.ols([x0], x1);

    // --- 2. AR(1) ativo a ativo --------------------------------------------
    const phis: number[] = [];
    const pairsPerAsset: number[] = [];
    for (const s of spread.values()) {
      const a: number[] = [];
      const b: number[] = [];
      for (const [year, value] of s) {
        const next = s.get(year + 1);
        if (next === undefined) continue;
        a.push(value);
        b.push(next);
      }
      if (a.length < minPeers) continue;
      const ols = Regression.ols([a], b);
      if (ols === null) continue;
      phis.push(ols.coefficients[1]!);
      pairsPerAsset.push(a.length);
    }

    // --- 3. O que sobra do spread depois de h anos, sem supor AR(1) --------
    //
    // A leitura direta: dos que estavam no quinto superior, quanto do spread
    // deles restava h anos depois? Não supõe forma funcional nenhuma.
    const survival = new Map<number, Survival>();
    for (const h of horizons) {
      const pairs: { from: number; to: number }[] = [];
      for (const s of spread.values()) {
        for (const [year, value] of s) {
          const after = s.get(year + h);
          if (after === undefined) continue;
          pairs.push({ from: value, to: after });
        }
      }
      if (pairs.length < 30) continue;
      const sortedRows = pairs.map((p) => p.from).sort(compareNum);
      const highCut = quantile(sortedRows, 0.8)!;
      const lowCut = quantile(sortedRows, 0.2)!;
      const highs = pairs.filter((p) => p.from >= highCut);
      const lows = pairs.filter((p) => p.from <= lowCut);
      const ratio = (xs: readonly { from: number; to: number }[]): number | null => {
        const from = median(xs.map((x) => x.from));
        const to = median(xs.map((x) => x.to));
        if (from === null || to === null || Math.abs(from) < 1e-9) return null;
        return to / from;
      };

      survival.set(h, {
        pares: pairs.length,
        spreadInicialAlto: median(highs.map((x) => x.from))!,
        spreadFinalAlto: median(highs.map((x) => x.to))!,
        sobraAlto: ratio(highs) ?? Number.NaN,
        spreadInicialBaixo: median(lows.map((x) => x.from))!,
        spreadFinalBaixo: median(lows.map((x) => x.to))!,
        sobraBaixo: ratio(lows) ?? Number.NaN,
      });
    }

    // --- 4. O destino: o nível do mercado contra o custo de capital --------
    const costs = [...costOf.values()];
    const level = years
      .filter((year) => yearMedian.has(year))
      .map((year) => ({ ano: year, medianaRoic: yearMedian.get(year)!, ativos: yearCount.get(year)! }));

    const result: Result = {
      medidoEm: frozenToday.toIso8601String().substring(0, 10),
      conferidoContraOGabarito: divergent?.length ?? null,
      ativosComSerie: seriesOf.size,
      painel: {
        pares: x0.length,
        phi: panel?.coefficients[1] ?? null,
        t: panel?.tStats[1] ?? null,
        r2: panel?.r2 ?? null,
        meiaVidaAnos: panel === null ? null : halfLife(panel.coefficients[1]!),
      },
      porAtivo: {
        ativos: phis.length,
        paresMedianos: median(pairsPerAsset),
        phiP25: quantile(phis, 0.25),
        phiMediano: median(phis),
        phiP75: quantile(phis, 0.75),
      },
      // Chave em texto, como o registro sempre gravou.
      sobrevivenciaDoSpread: Object.fromEntries([...survival].map(([h, v]) => [String(h), v])),
      nivelDoMercado: {
        medianaRoicPorAno: level,
        medianaRoicDoPeriodo: median([...yearMedian.values()]),
        medianaCustoDeCapital: median(costs),
        ativosComCusto: costs.length,
      },
    };

    writeText(output, jsonPretty(result, ' '));
    printReport(result, divergent);
    errln(`\nescrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}

function printReport(r: Result, divergent: readonly string[] | null): void {
  if (divergent === null) {
    outln('\n!! sem gabarito para conferir');
  } else if (divergent.length > 0) {
    outln(`\n!! a montagem DIVERGE do gabarito em ${divergent.length} ativo(s) — os números abaixo não valem`);
  } else {
    outln('\nmontagem idêntica à do gabarito.');
  }

  outln('\n=== B19 — A REVERSÃO DA RENTABILIDADE À MÉDIA ===');
  outln(`ativos com série de ROIC: ${r.ativosComSerie}`);

  const p = r.painel;
  outln('\n-- 1. velocidade: AR(1) do spread contra a mediana do ano --');
  outln(`  painel:  φ = ${n(p.phi)}  t = ${n(p.t, 1)}  R² = ${n(p.r2)}  pares = ${p.pares}  meia-vida = ${n(p.meiaVidaAnos, 1)} anos`);
  const a = r.porAtivo;
  outln(
    `  por ativo (${a.ativos} com ≥ ${minPeers} pares, mediana de ${n(a.paresMedianos, 0)}): ` +
      `φ p25 ${n(a.phiP25)}  mediana ${n(a.phiMediano)}  p75 ${n(a.phiP75)}`,
  );
  const panelPhi = p.phi;
  const pairs = p.pares;
  if (panelPhi !== null && pairs > 0) {
    // Viés de Kendall do AR(1): `−(1 + 3φ)/n`. No painel ele é desprezível; no
    // estimador por ativo, com dez pares, é da ordem de −0,3.
    outln(`  viés de Kendall: painel ${n(-(1 + 3 * panelPhi) / pairs, 4)}  por ativo com 10 pares ${n(-(1 + 3 * panelPhi) / 10, 3)}`);
  }

  outln('\n-- 2. o que sobra do spread, sem supor forma funcional --');
  for (const h of horizons) {
    const mm = r.sobrevivenciaDoSpread[String(h)];
    if (mm === undefined) continue;
    outln(
      `  ${h} ano(s): quinto superior ${pc(mm.spreadInicialAlto)} → ${pc(mm.spreadFinalAlto)} (sobra ${n(mm.sobraAlto, 2)})   ` +
        `quinto inferior ${pc(mm.spreadInicialBaixo)} → ${pc(mm.spreadFinalBaixo)} (sobra ${n(mm.sobraBaixo, 2)})   n = ${mm.pares}`,
    );
  }

  const nv = r.nivelDoMercado;
  outln('\n-- 3. destino: reverter para onde? --');
  outln(`  ROIC mediano do universo, mediana dos anos: ${pc(nv.medianaRoicDoPeriodo)}`);
  outln(`  custo de capital de equilíbrio mediano: ${pc(nv.medianaCustoDeCapital)} (${nv.ativosComCusto} avaliados)`);
  outln('  por ano:');
  for (const x of nv.medianaRoicPorAno) outln(`    ${x.ano}  ${pc(x.medianaRoic)}   (${x.ativos} ativos)`);
}
