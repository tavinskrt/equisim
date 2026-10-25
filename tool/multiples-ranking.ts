// Item B22 — o múltiplo de pares como ordenação, medido ao lado das três da
// decisão 103.
//
// **Por que ele entrou.** O item B5 mediu que o potencial do DCF e o dos
// múltiplos têm correlação de postos de **0,470**, com o mesmo sinal em 63 de
// 93: o múltiplo relativo é **sinal distinto**, e não cópia. Se ele ordena
// melhor é pergunta de coorte, e é esta ferramenta.
//
// **A mediana é da coorte, e não do pacote.** O pacote versionado
// (`public/assets/mercado/multiplos_setoriais.json`) é de 14/09/2026: usá-lo
// numa observação de 2018 seria conhecimento futuro pela porta da frente. Aqui
// a mediana setorial sai da **própria seção transversal da coorte**, com os
// ingredientes que o backtest grava por observação.
//
// **A regra é a da decisão 103**, e foi fixada antes de medir: o prêmio do
// retorno esperado sai da **primeira ordenação que passar** no critério da
// decisão 96 — `t` corrigido pela sobreposição acima do crítico dela **e**
// Newey-West acima de 2. Esta ferramenta não muda a regra: acrescenta um
// candidato e diz se ele passa.
//
// **As quatro são medidas nas mesmas observações.** Comparar ordenadores
// medidos em subconjuntos diferentes compararia coberturas.
//
//   npm run tool -- backtest-valuation --montagem aplicativo \
//       --com-deslistadas --trimestral
//   npm run tool -- multiples-ranking
import { existsSync, readFileSync } from 'node:fs';

import {
  compareNum,
  compareStr,
  type JsonObject,
  MultipleKind,
  PeerValuation,
  round,
  TransversalOrdering,
  TransversalScore,
  TransversalSignals,
} from '../src/core';
import { dartString, errln, jsonPretty, outln, writeText } from './lib/files';
import { Regression } from './validation/regression';

const inputFile = 'docs/validacao/backtest_trimestral.json';
const output = 'docs/validacao/multiplos_ordenacao.json';

/**
 * Mínimo de pares para uma mediana setorial da coorte ser usável — o mesmo
 * corte que a cascata cobra, e por isso vem dela.
 */
const minPeers = PeerValuation.minimumPeers;

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function median(v: readonly number[]): number {
  const o = [...v].sort(compareNum);
  const mid = Math.floor(o.length / 2);
  return o.length % 2 === 1 ? o[mid]! : (o[mid - 1]! + o[mid]!) / 2;
}

/** Uma observação com tudo o que as quatro ordenações pedem. */
interface Obs {
  cohort: string;
  upside: number;
  bookToMarket: number;
  earningsYield: number;
  multiples: number;
  returnRate: number;
}

/**
 * O potencial que os pares da coorte implicam, ou `null`.
 *
 * **Sem divisor e sem contagem de papéis**: o potencial é
 * `valor implicado ÷ valor de mercado − 1`, e os dois lados são da companhia
 * inteira. A ponte não entra, e por isso não há como ela entrar.
 */
function multiplesUpsideOf(m: JsonObject, mediansByKind: ReadonlyMap<MultipleKind, number>): number | null {
  const marketValue = num(m['valorDeMercado']);
  if (marketValue === null || marketValue <= 0) return null;

  const readings: number[] = [];

  const profit = num(m['lucro']);
  const pl = mediansByKind.get(MultipleKind.priceToEarnings);
  if (profit !== null && profit > 0 && pl !== undefined) readings.push((pl * profit) / marketValue - 1);

  const equity = num(m['patrimonio']);
  const priceToBookMedian = mediansByKind.get(MultipleKind.priceToBook);
  if (equity !== null && equity > 0 && priceToBookMedian !== undefined) readings.push((priceToBookMedian * equity) / marketValue - 1);

  const ebitda = num(m['ebitda']);
  const ev = mediansByKind.get(MultipleKind.evToEbitda);
  const debt = num(m['dividaLiquida']);
  if (ebitda !== null && ebitda > 0 && ev !== undefined && debt !== null) {
    const shareholder = ev * ebitda - debt;
    if (shareholder > 0) readings.push(shareholder / marketValue - 1);
  }

  if (readings.length === 0) return null;
  return median(readings);
}

/** As medianas de múltiplo de um grupo, com o mínimo de pares da cascata. */
function mediansOf(group: readonly JsonObject[]): Map<MultipleKind, number> {
  const out = new Map<MultipleKind, number>();
  const collect = (k: MultipleKind, f: (m: JsonObject) => number | null): void => {
    const v: number[] = [];
    for (const m of group) {
      const x = f(m);
      if (x !== null && x > 0) v.push(x);
    }
    if (v.length >= minPeers) out.set(k, median(v));
  };

  // `bookToMarket` é `1 ÷ (P/VP)` e `earningsYield` é `1 ÷ (P/L)`: os
  // dois já vinham do backtest, e invertê-los aqui evita gravar o mesmo
  // número duas vezes com nomes diferentes.
  collect(MultipleKind.priceToEarnings, (m) => {
    const ey = num(m['earningsYield']);
    return ey === null || ey <= 0 ? null : 1 / ey;
  });
  collect(MultipleKind.priceToBook, (m) => {
    const bm = num(m['bookToMarket']);
    return bm === null || bm <= 0 ? null : 1 / bm;
  });
  collect(MultipleKind.evToEbitda, (m) => num(m['firmaSobreEbitda']));
  return out;
}

export function main(_args: string[]): void {
  if (!existsSync(inputFile)) {
    errln(`sem ${inputFile}: rode o backtest trimestral antes.`);
    process.exitCode = 2;
    return;
  }
  const raw = JSON.parse(readFileSync(inputFile, 'utf8')) as unknown;
  const rows = (
    raw !== null && typeof raw === 'object' && !Array.isArray(raw)
      ? ((raw as JsonObject)['observacoes'] ?? (raw as JsonObject)['linhas'] ?? (raw as JsonObject)['dados'] ?? null)
      : raw
  ) as JsonObject[] | null;
  if (rows === null) {
    errln(`${inputFile} não tem a lista de observações esperada.`);
    process.exitCode = 2;
    return;
  }

  const result: Record<string, unknown> = { entrada: inputFile };
  for (const horizon of [12, 36]) {
    const returnField = `ret${horizon}tot`;

    // ------------------------------------------------------------------
    // 1) As medianas setoriais de cada coorte, da própria seção transversal
    // ------------------------------------------------------------------
    const byCohort = new Map<string, JsonObject[]>();
    for (const m of rows) {
      const key = dartString(m['coorte']);
      if (!byCohort.has(key)) byCohort.set(key, []);
      byCohort.get(key)!.push(m);
    }

    const obs: Obs[] = [];
    let withoutMedian = 0;
    for (const members of byCohort.values()) {
      // Por setor, e com recuo para o mercado inteiro da coorte — a mesma
      // hierarquia do pacote, sem o degrau do subsetor, que a coorte não tem.
      const bySector = new Map<string, JsonObject[]>();
      for (const m of members) {
        const sector = (m['setor'] as string | null | undefined) ?? null;
        if (sector === null) continue;
        if (!bySector.has(sector)) bySector.set(sector, []);
        bySector.get(sector)!.push(m);
      }

      const marketMedians = mediansOf(members);
      const sectorMediansByName = new Map([...bySector].map(([k, v]) => [k, mediansOf(v)] as const));

      for (const m of members) {
        const upsides = num(m['upside']);
        const bm = num(m['bookToMarket']);
        const ey = num(m['earningsYield']);
        const ret = num(m[returnField]);
        const sector = (m['setor'] as string | null | undefined) ?? null;
        if (upsides === null || bm === null || ey === null || ret === null) continue;
        if (sector === null) continue;

        // Setor quando ele reúne pares; mercado da coorte quando não.
        const sectorMedians = sectorMediansByName.get(sector) ?? new Map<MultipleKind, number>();
        const mediansByKind = new Map<MultipleKind, number>();
        for (const k of MultipleKind.values) {
          const v = sectorMedians.get(k) ?? marketMedians.get(k);
          if (v !== undefined) mediansByKind.set(k, v);
        }
        const mult = multiplesUpsideOf(m, mediansByKind);
        if (mult === null) {
          withoutMedian++;
          continue;
        }
        obs.push({
          cohort: dartString(m['coorte']),
          upside: upsides,
          bookToMarket: bm,
          earningsYield: ey,
          multiples: mult,
          returnRate: ret,
        });
      }
    }

    // ------------------------------------------------------------------
    // 2) As quatro ordenações, coorte a coorte, nas mesmas observações
    // ------------------------------------------------------------------
    const cohorts = new Map<string, Obs[]>();
    for (const o of obs) {
      if (!cohorts.has(o.cohort)) cohorts.set(o.cohort, []);
      cohorts.get(o.cohort)!.push(o);
    }
    const keys = [...cohorts.keys()].sort(compareStr);

    const series = new Map<string, number[]>([
      ['potencial', []],
      ['bookToMarket', []],
      ['earningsYield', []],
      ['multiplos', []],
      ['composto', []],
    ]);
    const byCohortOutput: Record<string, unknown>[] = [];

    for (const key of keys) {
      const group = cohorts.get(key)!;
      if (group.length < 10) continue;
      const zRet = Regression.standardizedRanks(group.map((o) => o.returnRate));
      const ic = (v: readonly number[]): number | null => Regression.pearson(Regression.standardizedRanks(v), zRet);

      const upsideIc = ic(group.map((o) => o.upside));
      const icBm = ic(group.map((o) => o.bookToMarket));
      const icEy = ic(group.map((o) => o.earningsYield));
      const icMult = ic(group.map((o) => o.multiples));
      // O composto é o do núcleo, com os três sinais da decisão 103 — o
      // múltiplo entra como quarto candidato **separado**, e não dentro dele:
      // mudar a composição seria mudar a regra depois de ver o resultado.
      const composite = TransversalScore.scores(
        new Map(
          group.map(
            (o, i) => [i, new TransversalSignals({ potential: o.upside, bookToMarket: o.bookToMarket, earningsYield: o.earningsYield })] as const,
          ),
        ),
        TransversalOrdering.composite,
      );
      const icComp = Regression.pearson(Regression.standardizedRanks(group.map((_, i) => composite.get(i) ?? 0.0)), zRet);

      const store = (name: string, v: number | null): void => {
        if (v !== null && Number.isFinite(v)) series.get(name)!.push(v);
      };

      store('potencial', upsideIc);
      store('bookToMarket', icBm);
      store('earningsYield', icEy);
      store('multiplos', icMult);
      store('composto', icComp);

      byCohortOutput.push({
        coorte: key,
        n: group.length,
        icPotencial: upsideIc,
        icBookToMarket: icBm,
        icEarningsYield: icEy,
        icMultiplos: icMult,
        icComposto: icComp,
      });
    }

    // A defasagem da sobreposição: coortes trimestrais e horizonte em meses.
    const lag = round(horizon / 3) - 1;
    const readings = new Map<string, Record<string, unknown>>();
    for (const [name, values] of series) {
      const v = Regression.summarize(values);
      const nw = Regression.neweyWestMean(values, lag);
      const overlapT = Regression.overlapAdjustedT(values, lag);
      const critical = overlapT === null ? null : Regression.overlapCritical(overlapT.n, overlapT.overlap);
      readings.set(name, {
        coortes: values.length,
        media: v?.mean ?? null,
        t: v?.t ?? null,
        tNeweyWest: nw?.t ?? null,
        tSobreposicao: overlapT?.t ?? null,
        criticoSobreposicao: critical,
        positivas: values.filter((x) => x > 0).length,
        ...(overlapT !== null && nw !== null && critical !== null ? { passaR3: overlapT.t > critical && nw.t > 2 } : {}),
      });
    }

    result[`h${horizon}`] = {
      observacoes: obs.length,
      semMedianaUsavel: withoutMedian,
      coortes: byCohortOutput.length,
      leituras: Object.fromEntries(readings),
      porCoorte: byCohortOutput,
    };

    outln('');
    outln(`-- ${horizon} meses: ${obs.length} observações, ${byCohortOutput.length} coortes --`);
    outln('  ordenação        média      t     Newey-West   t corrigido / crítico   positivas   passa');
    for (const name of ['multiplos', 'potencial', 'bookToMarket', 'earningsYield', 'composto']) {
      const l = readings.get(name)!;
      const f = (v: unknown, decimals = 3): string => (typeof v === 'number' ? v.toFixed(decimals) : '—');
      outln(
        `  ${name.padEnd(14)}  ${f(l['media']).padStart(7)}  ${f(l['t'], 2).padStart(6)}  ` +
          `${f(l['tNeweyWest'], 2).padStart(11)}   ${f(l['tSobreposicao'], 2).padStart(10)} / ` +
          `${f(l['criticoSobreposicao'], 2)}   ${`${l['positivas']} de ${l['coortes']}`.padStart(11)}   ` +
          (l['passaR3'] === true ? 'SIM' : 'não'),
      );
    }
  }

  writeText(output, jsonPretty(result, '  '));
  outln('');
  outln(`escrito ${output}`);
}
