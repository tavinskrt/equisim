// B8 — o tamanho da reapresentação no *point-in-time*.
//
// **O defeito.** A ingestão adota a **última versão** de cada documento da CVM,
// e 24,8% dos anuais têm mais de uma. A data que viaja com o documento é a de
// recebimento **daquela** versão. Numa avaliação datada, o corte
// *point-in-time* compara essa data com a data da coorte: quando a última
// versão chegou depois, o exercício inteiro some, e a coorte recua para a fonte
// de mercado — embora a versão **original** estivesse pública na época.
//
// A evidência que abriu o item: a DFP de 2023 da USIM3 tem recebimento em
// 16/01/2025; em 04/09/2024 aquele ano ficava sem CVM.
//
// **Consertar exige a base bruta** — guardar cada versão com a data dela é
// trabalho de ingestão, e `data/cvm` não sobrevive ao clone (item C5). **Medir
// não exige**: o pacote versionado traz a data de recebimento de cada
// documento, e com ela dá para contar quantos exercícios cada coorte perde por
// chegarem tarde demais.
//
// **O atraso regulamentar é a régua.** A DFP vence três meses depois do fecho
// do exercício; o ITR, 45 dias depois do fecho do trimestre. Recebimento além
// disso é entrega atrasada ou reapresentação — o pacote não distingue as duas,
// e o documento diz isso.
//
// Este programa **não vai à rede** e não precisa da entrada congelada: ele lê
// só `public/assets/cvm/documentos.json`, que é versionado.
//
// Uso:
//   npm run tool -- restatement
import { existsSync } from 'node:fs';

import { compareNum, CvmDocumentCodec, CvmDocumentKind, DateTime, Duration, intDiv, type JsonObject, round } from '../src/core';
import { dartString, errln, jsonPretty, outln, readJson, writeText } from './lib/files';

const packageFile = 'public/assets/cvm/documentos.json';
const output = 'docs/validacao/reapresentacao.json';

/**
 * Prazo regulamentar de entrega, em dias corridos depois do fecho.
 *
 * A DFP vence em três meses; o ITR, em 45 dias. Os números são de calendário,
 * e a folga de alguns dias não muda a leitura: o que este corte separa é
 * entrega no prazo de documento que chegou meses — ou anos — depois.
 */
const dfpDeadline = 92;
const itrDeadline = 45;

/**
 * As datas de coorte da validação trimestral (C1c): fim de cada trimestre de
 * 31/03/2018 a 30/09/2025.
 */
function cohorts(): DateTime[] {
  const out: DateTime[] = [];
  for (let year = 2018; year <= 2025; year++) {
    for (const month of [3, 6, 9, 12]) {
      const end = DateTime.local(year, month + 1, 0);
      if (end.isBefore(DateTime.local(2018, 3, 31))) continue;
      if (end.isAfter(DateTime.local(2025, 9, 30))) continue;
      out.push(end);
    }
  }
  return out;
}

function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = intDiv(s.length, 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function quantile(v: readonly number[], p: number): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  return s[round(p * (s.length - 1))]!;
}

const day = (d: DateTime): string => d.toIso8601String().slice(0, 10);

export function main(_args: string[]): void {
  if (!existsSync(packageFile)) {
    errln(`${packageFile} não existe. Rode antes:`);
    errln('  npm run tool -- cvm-package');
    process.exitCode = 2;
    return;
  }
  const docs = CvmDocumentCodec.decodePackage(readJson<JsonObject>(packageFile));

  // --- O atraso de cada documento ------------------------------------------
  const dfpDelay: number[] = [];
  const itrDelay: number[] = [];
  let withoutDate = 0;
  let lateDfp = 0;
  let lateItr = 0;
  const worst: { ticker: string; end: string; received: string; days: number }[] = [];

  for (const [ticker, list] of docs) {
    for (const d of list) {
      const received = d.current.receiptDate;
      if (received === null) {
        withoutDate++;
        continue;
      }
      const days = received.difference(d.periodEnd).inDays;
      const dfp = d.kind === CvmDocumentKind.dfp;
      (dfp ? dfpDelay : itrDelay).push(days);
      if (days > (dfp ? dfpDeadline : itrDeadline)) {
        if (dfp) {
          lateDfp++;
        } else {
          lateItr++;
        }
        worst.push({ ticker, end: day(d.periodEnd), received: day(received), days });
      }
    }
  }
  worst.sort((a, b) => compareNum(b.days, a.days));

  // --- Quanto cada coorte perde --------------------------------------------
  //
  // Um exercício "devia estar público" na coorte quando o prazo regulamentar
  // dele já venceu antes dela. Some quando a **única** versão que o pacote tem
  // chegou depois — e é exatamente o que a versão original teria evitado.
  const byCohort: Record<string, unknown>[] = [];
  for (const date of cohorts()) {
    let shouldBe = 0;
    let lost = 0;
    const lostTickers = new Set<string>();
    for (const [ticker, list] of docs) {
      for (const d of list) {
        const received = d.current.receiptDate;
        if (received === null) continue;
        const term = d.periodEnd.add(new Duration({ days: d.kind === CvmDocumentKind.dfp ? dfpDeadline : itrDeadline }));
        if (!term.isBefore(date)) continue;
        shouldBe++;
        if (received.isAfter(date)) {
          lost++;
          lostTickers.add(ticker);
        }
      }
    }
    byCohort.push({
      coorte: day(date),
      deviamEstarPublicos: shouldBe,
      perdidosPelaVersaoTardia: lost,
      fracao: shouldBe === 0 ? null : lost / shouldBe,
      tickersAtingidos: lostTickers.size,
    });
  }

  const result = {
    medidoEm: day(DateTime.local(2026, 9, 14)),
    fonte: packageFile,
    documentos: dfpDelay.length + itrDelay.length,
    semDataDeRecebimento: withoutDate,
    atrasoEmDias: {
      dfp: {
        n: dfpDelay.length,
        p50: median(dfpDelay),
        p90: quantile(dfpDelay, 0.9),
        max: dfpDelay.length === 0 ? null : dfpDelay.reduce((a, b) => (a > b ? a : b)),
        foraDoPrazo: lateDfp,
        prazoEmDias: dfpDeadline,
      },
      itr: {
        n: itrDelay.length,
        p50: median(itrDelay),
        p90: quantile(itrDelay, 0.9),
        max: itrDelay.length === 0 ? null : itrDelay.reduce((a, b) => (a > b ? a : b)),
        foraDoPrazo: lateItr,
        prazoEmDias: itrDeadline,
      },
    },
    porCoorte: byCohort,
    pioresAtrasos: worst.slice(0, 15).map((p) => ({
      ticker: p.ticker,
      fimDoExercicio: p.end,
      recebidoEm: p.received,
      diasDeAtraso: p.days,
    })),
  };

  writeText(output, jsonPretty(result));
  printReport(result);
  errln(`\nescrito ${output}`);
}

function printReport(r: {
  documentos: number;
  semDataDeRecebimento: number;
  atrasoEmDias: Record<string, Record<string, number | null>>;
  porCoorte: Record<string, unknown>[];
  pioresAtrasos: Record<string, unknown>[];
}): void {
  const n = (v: number | null | undefined, c = 0): string => (v === null || v === undefined ? '—' : v.toFixed(c));

  outln('\n=== B8 — O TAMANHO DA REAPRESENTAÇÃO ===');
  outln(`documentos no pacote: ${r.documentos}   sem data de recebimento: ${r.semDataDeRecebimento}`);

  outln('\n-- atraso entre o fecho e o recebimento, em dias --');
  for (const k of ['dfp', 'itr']) {
    const m = r.atrasoEmDias[k]!;
    outln(
      `  ${k.toUpperCase().padEnd(4)} n=${m['n']}  p50 ${n(m['p50'])}  p90 ${n(m['p90'])}  máx ${n(m['max'])}   ` +
        `além do prazo de ${m['prazoEmDias']} dias: ${m['foraDoPrazo']}`,
    );
  }

  outln('\n-- o que cada coorte perde por versão tardia --');
  outln('  coorte       deviam estar   perdidos   fração   tickers');
  for (const c of r.porCoorte) {
    const f = c['fracao'] as number | null;
    outln(
      `  ${dartString(c['coorte'])}   ${dartString(c['deviamEstarPublicos']).padStart(10)}   ` +
        `${dartString(c['perdidosPelaVersaoTardia']).padStart(8)}   ` +
        `${f === null ? '   —' : `${(f * 100).toFixed(1)}%`.padStart(6)}   ${dartString(c['tickersAtingidos']).padStart(6)}`,
    );
  }

  outln('\n-- os piores atrasos --');
  for (const p of r.pioresAtrasos) {
    outln(
      `  ${dartString(p['ticker']).padEnd(8)} fecho ${dartString(p['fimDoExercicio'])}  ` +
        `recebido ${dartString(p['recebidoEm'])}  ${dartString(p['diasDeAtraso'])} dias`,
    );
  }
}
