// Decisão 159 — empacota o preço justo ponto no tempo das coortes trimestrais
// para o acompanhamento da carteira na tela da Meta.
//
// A compra de um mês passado só pode usar o que era público naquele mês. As
// coortes de `docs/validacao/backtest_trimestral.json` já são ponto no tempo:
// cada uma avaliou o universo com os balanços entregues à CVM até a data dela
// (`PointInTimeView`). O pacote leva, por coorte e por ativo avaliado, o
// potencial e o preço da coorte — o resto do registro (retornos futuros,
// recusas, sinais) fica de fora: o aplicativo não pode ver o retorno que a
// coorte mediu depois. O `ke` também fica: ver `UpsideCohortsCodec`.
//
// Uso:
//   npm run tool -- backtest-valuation --trimestral   (refaz as coortes)
//   npm run tool -- upside-cohorts-package
import { statSync } from 'node:fs';

import { DateTime, UpsideCohortsCodec, type UpsideCohort, type UpsideCohortEntry } from '../src/core';
import { fail, flagValue, outln, readJson, writeText } from './lib/files';

const source = 'docs/validacao/backtest_trimestral.json';
const output = 'public/assets/validacao/upside_coortes.json';

interface CohortRow {
  readonly coorte: string;
  readonly ticker: string;
  readonly upside: number | null;
  readonly preco: number | null;
}

export function main(args: string[]): void {
  let rows: CohortRow[];
  try {
    rows = readJson<CohortRow[]>(flagValue(args, '--entrada') ?? source);
  } catch {
    fail(`Sem ${source}. Rode antes: npm run tool -- backtest-valuation --trimestral`);
  }
  const byCohort = new Map<string, Map<string, UpsideCohortEntry>>();
  let kept = 0;
  let refused = 0;
  for (const r of rows) {
    if (r.upside === null || r.preco === null || !(r.preco > 0) || !Number.isFinite(r.upside)) {
      refused++;
      continue;
    }
    let cohort = byCohort.get(r.coorte);
    if (cohort === undefined) {
      cohort = new Map();
      byCohort.set(r.coorte, cohort);
    }
    cohort.set(r.ticker, { upside: r.upside, price: r.preco });
    kept++;
  }
  const cohorts: UpsideCohort[] = [...byCohort.entries()]
    .map(([date, entries]) => ({ date: DateTime.parse(`${date}T00:00:00Z`), entries }))
    .sort((a, b) => a.date.compareTo(b.date));
  if (cohorts.length === 0) fail(`Nenhuma coorte com ativo avaliado em ${source}.`);
  // A data de geração é a do empacotamento, ou a informada: o arquivo de
  // origem não guarda quando as coortes foram refeitas.
  const informed = flagValue(args, '--gerado-em');
  const generatedAt = informed === null ? DateTime.now() : DateTime.parse(`${informed}T00:00:00Z`);
  writeText(output, JSON.stringify(UpsideCohortsCodec.encode(cohorts, { generatedAt })));
  outln(`  coortes: ${cohorts.length} (${cohorts[0]!.date.toIso8601String().slice(0, 10)} a ${cohorts[cohorts.length - 1]!.date.toIso8601String().slice(0, 10)})`);
  outln(`  avaliações: ${kept}  fora (recusadas ou sem preço): ${refused}`);
  outln(`  tamanho: ${(statSync(output).size / 1024).toFixed(0)} KB`);
  outln(`  gravado ${output}`);
}
