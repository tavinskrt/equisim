// A Selic prevista no lugar da taxa livre de risco — o pedido do orientador,
// medido sobre a entrada congelada do gabarito.
//
// **A pergunta.** O orientador pediu, em 27/09/2026, que a projeção deixasse de
// usar "a mediana da Selic do passado" e usasse "a mediana da Selic prevista
// para os próximos cinco anos". A média do passado — a decenal do CDI — foi a
// taxa estrutural do motor até a decisão 84, e hoje só vale quando a curva do
// Tesouro falta. Desde 14/09/2026 a taxa de cada ano é o forward da curva dos
// prefixados, que é o que o mercado de títulos cobra por prazo.
//
// **O que esta ferramenta mede**, na mesma execução e com a montagem de
// referência conferida contra o gabarito:
//
//   curva        o motor de hoje: forwards da curva prefixada do Tesouro
//   orientador   dois pontos: o CDI corrente convergindo à mediana das
//                expectativas anuais do Focus (ano corrente e quatro seguintes)
//                no ano 10, e a perpetuidade nela
//   trajetoria   a trajetória do Focus: a taxa de cada ano é a Selic média que
//                o Focus espera para ele, e depois do último ano a última
//                expectativa segue até a perpetuidade
//   passado      dois pontos até a média decenal do CDI — o motor de antes da
//                decisão 84, e o recuo de hoje quando a curva falta
//
// O Focus vem do Banco Central (Olinda, `ExpectativasMercadoAnuais`,
// indicador `Selic`, base de cálculo 0), na última data até a da entrada
// congelada, e fica gravado no JSON de saída.
//
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- selic-focus      # grava selic_focus.json
import {
  compareNum,
  compareStr,
  CurveVertex,
  DateTime,
  type Ticker,
  ValuationCascade,
  type ValuationResult,
  YieldCurve,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';
import { Regression } from './validation/regression';

const output = 'docs/validacao/selic_focus.json';

/** As variantes, na ordem em que são impressas; a primeira é a referência. */
const variants = ['curva', 'orientador', 'trajetoria', 'passado'] as const;
type Variant = (typeof variants)[number];

interface Focus {
  date: string;
  byYear: Map<number, number>;
}

/**
 * As expectativas anuais da Selic (fim de ano, em fração) na última data do
 * Focus até [until].
 */
async function fetchFocus(until: DateTime): Promise<Focus> {
  const day = until.toIso8601String().substring(0, 10);
  const url =
    'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/' +
    'ExpectativasMercadoAnuais?$top=20' +
    "&$filter=Indicador%20eq%20'Selic'%20and%20baseCalculo%20eq%200" +
    `%20and%20Data%20le%20'${day}'` +
    '&$orderby=Data%20desc&$format=json' +
    '&$select=Data,DataReferencia,Mediana';
  const response = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (response.status !== 200) throw new Error(`Focus respondeu ${response.status}, uri = ${url}`);
  const rows = ((await response.json()) as { value: { Data: string; DataReferencia: string; Mediana: number }[] }).value;
  if (rows.length === 0) throw new Error(`Focus sem expectativa até ${day}`);
  const date = rows[0]!.Data;
  const byYear = new Map<number, number>();
  for (const l of rows) {
    if (l.Data === date) byYear.set(Number.parseInt(l.DataReferencia, 10), l.Mediana / 100);
  }
  return { date, byYear };
}

/**
 * A curva de uma trajetória de taxas anuais: vértices à vista nos anos
 * inteiros, compostos dos forwards; depois do último, a curva segue no último
 * forward, que é a extrapolação da `YieldCurve`.
 */
export function forwardsCurve(ref: DateTime, forwards: readonly number[]): YieldCurve {
  let factor = 1.0;
  const vertices: CurveVertex[] = [];
  for (let k = 1; k <= forwards.length; k++) {
    factor *= 1 + forwards[k - 1]!;
    vertices.push(new CurveVertex(k, Math.pow(factor, 1 / k) - 1.0));
  }
  return YieldCurve.of(ref, vertices)!;
}

/**
 * A Selic média esperada em cada um dos [n] anos seguintes a [today].
 *
 * A trajetória liga, por segmentos de reta, a taxa corrente em [today] à
 * expectativa de cada fim de ano, e segue plana na última. A taxa do ano é a
 * média composta da trajetória nele — `exp(média de ln(1 + S))` —, que é o que
 * o CDI acumularia.
 */
export function focusForwards(today: DateTime, current: number, byYear: ReadonlyMap<number, number>, n: number): number[] {
  // Em UTC: diferença entre datas locais perde um dia na troca de horário.
  const todayUtc = DateTime.utc(today.year, today.month, today.day);
  const years = (year: number, month: number, day: number): number => DateTime.utc(year, month, day).difference(todayUtc).inDays / 365.25;
  const points: [number, number][] = [[0.0, current]];
  for (const a of [...byYear.keys()].sort(compareNum)) {
    if (years(a, 12, 31) > 0) points.push([years(a, 12, 31), byYear.get(a)!]);
  }
  const last = points[points.length - 1]!;
  const rate = (t: number): number => {
    if (t >= last[0]) return last[1];
    for (let i = 1; i < points.length; i++) {
      if (t <= points[i]![0]) {
        const [t0, s0] = points[i - 1]!;
        const [t1, s1] = points[i]!;
        return s0 + ((s1 - s0) * (t - t0)) / (t1 - t0);
      }
    }
    return last[1];
  };

  const stepCount = 360;
  const out: number[] = [];
  for (let k = 1; k <= n; k++) {
    let sum = 0.0;
    for (let j = 0; j < stepCount; j++) sum += Math.log(1 + rate(k - 1 + (j + 0.5) / stepCount));
    out.push(Math.exp(sum / stepCount) - 1);
  }
  return out;
}

/** A mediana, ou `null` para lista vazia — `NaN` não é número que se grave. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const o = [...v].sort(compareNum);
  const m = Math.floor(o.length / 2);
  return o.length % 2 === 1 ? o[m]! : (o[m - 1]! + o[m]!) / 2;
}

const pct = (v: number | null): string => (v === null || !Number.isFinite(v) ? '   —  ' : `${(v * 100).toFixed(2).padStart(6)}%`);

interface RatePath {
  ano1: number;
  ano5: number | null;
  ano10: number;
  perpetuidade: number;
  mediaDosDezAnos: number;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  let focus: Focus;
  try {
    focus = await fetchFocus(frozenToday);
  } catch (e) {
    errln(`sem o Focus do Banco Central: ${e instanceof Error ? e.message : String(e)}`);
    await c.ctx.dispose();
    process.exitCode = 2;
    return;
  }
  const focusYears = [...focus.byYear.keys()].sort(compareNum);
  const expectations = focusYears.map((a) => focus.byYear.get(a)!);
  // `fetchFocus` recusa resposta sem expectativa: a lista não é vazia.
  const focusMedian = median(expectations)!;
  const current = c.anchors.currentRiskFreeRate;
  const forwards = focusForwards(frozenToday, current, focus.byYear, 10);
  const trajectory = forwardsCurve(frozenToday, forwards);

  const rates: Record<Variant, { curve: YieldCurve | null; structural: number | null } | null> = {
    curva: null,
    orientador: { curve: null, structural: focusMedian },
    // Com curva, a perpetuidade é o forward terminal dela (a última
    // expectativa); a estrutural só vale sem curva, e é dita aqui por clareza.
    trajetoria: { curve: trajectory, structural: forwards[forwards.length - 1]! },
    passado: { curve: null, structural: c.anchors.riskFreeCagr },
  };

  outln(`-- as taxas, em ${frozenToday.toIso8601String().substring(0, 10)} --`);
  outln(`  Focus de ${focus.date}: ${focusYears.map((a) => `${a} ${pct(focus.byYear.get(a)!)}`).join('  ')}`);
  outln(`  mediana das expectativas anuais   ${pct(focusMedian)}`);
  outln(`  CDI corrente                      ${pct(current)}`);
  outln(`  média decenal do CDI              ${pct(c.anchors.riskFreeCagr)}`);

  const paths = new Map<Variant, RatePath>();
  const fairValues = new Map<Variant, Map<string, number>>();
  const upsideByTicker = new Map<Variant, Map<string, number>>();
  try {
    for (const v of variants) {
      fairValues.set(v, new Map());
      upsideByTicker.set(v, new Map());
      const reference = new Map<Ticker, ValuationResult | null>();
      let i = 0;
      for (const t of c.universe) {
        i++;
        if (i % 50 === 0) process.stderr.write(`  ${v}: ${i}/${c.universe.length}   \r`);
        const prep = await c.prepare(t, { rate: rates[v] });
        if (prep.isErr) continue;
        const inputs = prep.unwrap();
        if (!paths.has(v)) {
          const curve = inputs.riskFreeCurve;
          const n = inputs.projectionYears;
          const rf = inputs.capm.riskFreeRate;
          const fw =
            curve !== null
              ? curve.annualForwards(n)
              : Array.from({ length: n }, (_, idx) => (n <= 1 ? rf : rf + ((inputs.terminalRiskFreeRate - rf) * idx) / (n - 1)));
          paths.set(v, {
            ano1: fw[0]!,
            ano5: fw.length >= 5 ? fw[4]! : null,
            ano10: fw[fw.length - 1]!,
            perpetuidade: inputs.terminalRiskFreeRate,
            // Média composta, e não aritmética: taxa se compõe (regra R3).
            mediaDosDezAnos: Math.pow(fw.map((r) => 1 + r).reduce((a, b) => a * b), 1 / fw.length) - 1.0,
          });
        }
        const r = ValuationCascade.evaluate(inputs);
        if (v === 'curva') reference.set(t, r.valueOrNull);
        if (r.isErr) continue;
        fairValues.get(v)!.set(t.value, r.unwrap().fairValue.cents);
        upsideByTicker.get(v)!.set(t.value, r.unwrap().upside);
      }
      if (v === 'curva') {
        const div = await c.checkAgainstAnswerKey(reference);
        if (div === null) {
          errln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (div.length > 0) {
          errln(`ERRO: a montagem de referência diverge do gabarito em ${div.length}: ${div.slice(0, 8).join(', ')}`);
          process.exitCode = 1;
          return;
        } else {
          outln('  montagem da curva conferida contra o gabarito: zero divergências');
        }
      }
    }
  } finally {
    await c.ctx.dispose();
  }
  process.stderr.write('                                        \r');

  const base = upsideByTicker.get('curva')!;
  const baseFairValue = fairValues.get('curva')!;
  const rows: Record<string, unknown>[] = [];
  outln('');
  outln('-- o que cada fonte de taxa faz, sobre a entrada congelada --');
  outln('  fonte        ano 1   ano 10  perpet.  avaliados  potencial mediano  acima de zero  justo vs curva  postos');
  for (const v of variants) {
    const fv = fairValues.get(v)!;
    const up = upsideByTicker.get(v)!;
    const upsideValues = [...up.values()];
    const common = [...fv.keys()].filter((k) => baseFairValue.has(k)).sort(compareStr);
    const changeList = common.filter((k) => baseFairValue.get(k)! !== 0).map((k) => fv.get(k)! / baseFairValue.get(k)! - 1);
    const rho =
      common.length < 3
        ? null
        : Regression.spearman(
            common.map((k) => base.get(k)!),
            common.map((k) => up.get(k)!),
          );
    const gains = [...fv.keys()].filter((k) => !baseFairValue.has(k)).sort(compareStr);
    const lost = [...baseFairValue.keys()].filter((k) => !fv.has(k)).sort(compareStr);
    const selectedPath = paths.get(v)!;
    const above = upsideValues.filter((p) => p > 0).length;
    outln(
      `  ${v.padEnd(11)} ${pct(selectedPath.ano1)} ${pct(selectedPath.ano10)} ${pct(selectedPath.perpetuidade)}  ` +
        `${String(upsideValues.length).padStart(9)}   ${pct(median(upsideValues)).padStart(14)}  ` +
        `${String(above).padStart(6)} de ${upsideValues.length}   ${pct(median(changeList)).padStart(13)}   ` +
        (rho === null ? '  —  ' : rho.toFixed(4)),
    );
    if (gains.length > 0 || lost.length > 0) outln(`               ganha ${gains.join(', ')}; perde ${lost.join(', ')}`);
    rows.push({
      fonte: v,
      taxas: selectedPath,
      avaliados: upsideValues.length,
      potencialMediano: median(upsideValues),
      acimaDeZero: above,
      justoMedianoContraCurva: median(changeList),
      spearmanContraCurva: rho,
      ganha: gains,
      perde: lost,
    });
  }

  const allTickers = [
    ...new Set([...baseFairValue.keys(), ...fairValues.get('orientador')!.keys(), ...fairValues.get('trajetoria')!.keys()]),
  ].sort(compareStr);
  const byAsset: Record<string, Record<string, { justoCentavos: number; potencial: number }>> = {};
  for (const k of allTickers) {
    const entry: Record<string, { justoCentavos: number; potencial: number }> = {};
    for (const v of variants) {
      if (fairValues.get(v)!.has(k)) entry[v] = { justoCentavos: fairValues.get(v)!.get(k)!, potencial: upsideByTicker.get(v)!.get(k)! };
    }
    byAsset[k] = entry;
  }

  writeText(
    output,
    `${jsonPretty(
      {
        dataDaEntrada: frozenToday.toIso8601String().substring(0, 10),
        focus: {
          data: focus.date,
          expectativas: Object.fromEntries(focusYears.map((a) => [String(a), focus.byYear.get(a)!])),
          mediana: focusMedian,
          forwardsDaTrajetoria: forwards,
        },
        cdiCorrente: current,
        mediaDecenalDoCdi: c.anchors.riskFreeCagr,
        fontes: rows,
        porAtivo: byAsset,
      },
      ' ',
    )}\n`,
  );
  outln('');
  outln(`escrito ${output}`);
}
