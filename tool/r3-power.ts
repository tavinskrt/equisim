// O poder do teste do R3: que habilidade o critério da decisão 96 conseguiria
// ver com a amostra que há (itens C1 e C6).
//
// O R3 reprovou: nenhuma das cinco ordenações passa. Isso só diz algo sobre o
// motor se o teste **pudesse** ter passado — um teste que só detecta efeitos
// que nenhum preditor real tem reprova tudo, e a reprovação não distingue
// «não há habilidade» de «não dá para ver». Esta ferramenta mede a diferença.
//
// **O modelo.** A série de coeficientes de coorte é `μ + e_t`, com `e_t` a soma
// de `L + 1` choques normais independentes — a estrutura que a sobreposição de
// coortes trimestrais produz, e a mesma da nula de
// `Regression.overlapNull`. O desvio de `e_t` sai do observado em cada
// ordenação, **corrigido pela sobreposição**: sob ela `E[s²] = σ²·c`, e usar o
// `s` cru subestimaria o ruído e inflaria o poder. `μ` é o efeito verdadeiro.
// Para cada `μ`, o poder é a fração de séries simuladas em que o critério da
// decisão 96 passa: `t` corrigido acima do crítico simulado **e** Newey-West
// acima de 2.
//
// Três leituras por ordenação:
//
// - **efeito mínimo detectável** (80% de poder) com as coortes que há;
// - **limite superior** do efeito, unilateral, ao nível do próprio critério:
//   o maior `μ` que a amostra não consegue descartar;
// - **quantas coortes** o teste pediria para detectar, a 80%, um efeito igual à
//   média observada — e em que ano os retornos delas estariam disponíveis.
//
// Semente fixa: o mesmo número em toda execução.
//
// Uso:
//   npm run tool -- conditional-regression --trimestral   # a série, se faltar
//   npm run tool -- r3-power
import { existsSync } from 'node:fs';

import { DateTime, intDiv } from '../src/core';
import { errln, fail, jsonPretty, outln, readJson, writeText } from './lib/files';
import { Regression, SplitMix64 } from './validation/regression';

const source = 'docs/validacao/habilidade_trimestral.json';
const output = 'docs/validacao/poder_r3.json';

/** Sorteios por avaliação de poder. */
const draws = 4000;
const seed = 20260922;

/** Primeira coorte trimestral do backtest. */
const first = DateTime.utc(2018, 3, 31);

/** Ordenações medidas, com o campo por coorte em `habilidade_trimestral.json`. */
const orderings = new Map([
  ['potencialDadoBm', 'coefPotencialDadoBm'],
  ['icPotencial', 'icPotencial'],
  ['icBookToMarket', 'icBookToMarket'],
  ['icEarningsYield', 'icEarningsYield'],
  ['icComposto', 'icComposto'],
]);

/** Normal padrão (Box–Muller) pelo gerador compartilhado com a nula. */
class Normal {
  private readonly rng: SplitMix64;
  constructor(seed: number) {
    this.rng = new SplitMix64(seed);
  }
  next(): number {
    const u = 1 - this.rng.nextDouble();
    const v = this.rng.nextDouble();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }
}

/** Fração de séries simuladas em que o critério do R3 passa. */
export function power(args: { mu: number; deviation: number; k: number; overlap: number; critical: number; seed?: number }): number {
  const { mu, deviation, k, overlap, critical } = args;
  const z = new Normal(args.seed ?? seed);
  const scale = deviation / Math.sqrt(overlap + 1);
  const shocks = new Array<number>(k + overlap).fill(0);
  let passes = 0;
  for (let s = 0; s < draws; s++) {
    for (let i = 0; i < shocks.length; i++) shocks[i] = z.next();
    const series: number[] = [];
    for (let t = 0; t < k; t++) {
      let sum = 0;
      for (let m = t; m <= t + overlap; m++) sum += shocks[m]!;
      series.push(mu + scale * sum);
    }
    const overlapT = Regression.overlapAdjustedT(series, overlap);
    const nw = Regression.neweyWestMean(series, overlap);
    if (overlapT !== null && nw !== null && overlapT.t > critical && nw.t > 2) passes++;
  }
  return passes / draws;
}

/**
 * O menor `μ` com poder de pelo menos [target], por bisseção. O poder é
 * monótono em `μ` porque a mesma semente reusa os mesmos choques.
 */
export function minimumEffect(args: { deviation: number; k: number; overlap: number; critical: number; target?: number }): number {
  const target = args.target ?? 0.8;
  let lo = 0.0;
  let hi = 4 * args.deviation;
  for (let i = 0; i < 30; i++) {
    const m = (lo + hi) / 2;
    const p = power({ mu: m, deviation: args.deviation, k: args.k, overlap: args.overlap, critical: args.critical });
    if (p < target) {
      lo = m;
    } else {
      hi = m;
    }
  }
  return hi;
}

/** Data em que a coorte de índice [k] (base 1) tem o retorno do horizonte. */
export function availableAt(k: number, months: number): DateTime {
  const quarters = k - 1 + intDiv(months, 3);
  const year = first.year + intDiv(first.month - 1 + 3 * quarters, 12);
  const month = ((first.month - 1 + 3 * quarters) % 12) + 1;
  return DateTime.utc(year, month + 1, 0);
}

type Json = Record<string, unknown>;

function horizon(sample: Json, months: number, overlap: number): Json {
  const byCohort = sample['porCoorte'] as Json[];
  const out: Json = {};
  for (const [name, field] of orderings) {
    const series = byCohort.filter((c) => typeof c[field] === 'number').map((c) => c[field] as number);
    const base = Regression.summarize(series);
    const overlapT = Regression.overlapAdjustedT(series, overlap);
    if (base === null || overlapT === null) continue;
    const k = base.n;
    const critical = Regression.overlapCritical(k, overlap);
    // Erro da média corrigido pela sobreposição: t_corrigido = média ÷ erro.
    const error = (base.sd / Math.sqrt(k)) * Math.sqrt(overlapT.f / overlapT.c);
    // σ da série sob a sobreposição: o `s` observado tem esperança `σ·√c`.
    const sigma = base.sd / Math.sqrt(overlapT.c);
    const mde = minimumEffect({ deviation: sigma, k, overlap, critical });

    // Quantas coortes para ver, a 80%, um efeito igual à média observada.
    let requiredCohorts: number | null = null;
    if (base.mean > 0) {
      for (let kk = k; kk <= k + 4 * 40; kk += 4) {
        const c = Regression.overlapCritical(kk, overlap);
        const p = power({ mu: base.mean, deviation: sigma, k: kk, overlap, critical: c });
        if (p >= 0.8) {
          requiredCohorts = kk;
          break;
        }
      }
    }
    out[name] = {
      coortes: k,
      media: base.mean,
      desvioPorCoorte: base.sd,
      erroCorrigido: error,
      tCorrigido: overlapT.t,
      critico: critical,
      sigmaCorrigido: sigma,
      // Conferência: com efeito zero o poder é o nível do teste.
      poderSemEfeito: power({ mu: 0, deviation: sigma, k, overlap, critical }),
      poderNoEfeitoObservado: power({ mu: base.mean, deviation: sigma, k, overlap, critical }),
      efeitoMinimoDetectavel80: mde,
      limiteSuperior: base.mean + critical * error,
      coortesPara80NoEfeitoObservado: requiredCohorts,
      retornosDisponiveisEm: requiredCohorts === null ? null : availableAt(requiredCohorts, months).toIso8601String().slice(0, 10),
    };
  }
  return out;
}

export function main(_args: string[]): void {
  if (!existsSync(source)) fail(`Falta ${source}. Rode antes: npm run tool -- conditional-regression --trimestral`);
  const d = readJson<Json>(source);
  const sample = (h: string): Json => ((d[h] as Json)['trimestral'] as Json)['comDeslistadas'] as Json;

  const result: Json = {
    fonte: source,
    sorteios: draws,
    semente: seed,
    modelo: 'série de coorte = μ + soma de L+1 choques normais iid, desvio observado; poder = P(t corrigido > crítico e Newey-West > 2)',
    h36: horizon(sample('h36'), 36, 11),
    h12: horizon(sample('h12'), 12, 3),
  };
  writeText(output, jsonPretty(result));

  const n = (v: unknown, decimals = 3): string => (v === null || v === undefined ? '—' : (v as number).toFixed(decimals));
  for (const h of ['h36', 'h12']) {
    outln(`\n== ${h} ==`);
    outln('ordenação          média  σ      erro   nível  poder  MDE80  lim.sup  coortes  disponível');
    for (const [name, value] of Object.entries(result[h] as Json)) {
      const v = value as Json;
      outln(
        `${name.padEnd(17)}  ${n(v['media'])}  ${n(v['sigmaCorrigido'])}  ${n(v['erroCorrigido'])}  ` +
          `${n(v['poderSemEfeito'], 3)}  ${n(v['poderNoEfeitoObservado'], 2)}   ${n(v['efeitoMinimoDetectavel80'])}  ` +
          `${n(v['limiteSuperior'])}   ${(v['coortesPara80NoEfeitoObservado'] as number | null) ?? '—'}` +
          `      ${(v['retornosDisponiveisEm'] as string | null) ?? '—'}`,
      );
    }
  }
  errln(`\nescrito ${output}`);
}
