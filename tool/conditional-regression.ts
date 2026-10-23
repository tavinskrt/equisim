// Regressão condicional — o potencial informa o que os fatores ingênuos não
// informam?
//
// **A pergunta.** A validação preditiva mediu o coeficiente de informação do
// potencial em 0,170 contra 0,213 do valor patrimonial sobre preço e 0,186 do
// lucro sobre preço, em 36 meses. O motor ordena, e **não** supera dois
// fatores de uma linha. Isso deixa aberta a única pergunta que decide se a
// cascata se paga: o que ela vê é o que o P/B e o L/P já viam, ou é
// informação própria?
//
// Correlação isolada não responde. Três ordenadores correlacionados entre si
// podem ter o mesmo IC e conteúdo idêntico. O que separa é a regressão
// **conjunta**: com os três dentro, o coeficiente do potencial sobrevive?
//
// **Como.** Fama-MacBeth em dois passos. Em cada coorte, uma regressão
// transversal do retorno realizado nos três ordenadores; depois, a média dos
// coeficientes entre coortes, com o `t` do segundo passo. Tudo em postos
// padronizados — o potencial tem cauda pesadíssima (um ativo chega a +477%) e
// regressão de nível sobre ele mediria o extremo, não a relação.
//
// A **IC incremental** é a mesma pergunta por outro caminho, e é a mais fácil
// de ler: retira-se do potencial o que P/B e L/P explicam, e mede-se a
// correlação de ordem do resíduo com o retorno. É o sinal que sobra depois de
// pagar o que já estava disponível de graça.
//
// **A ressalva que viaja junto.** Cinco coortes anuais de 36 meses não são
// cinco observações independentes: as janelas se sobrepõem em dois terços. O
// `t` do segundo passo superestima a confiança, e o que a medição sustenta é
// o sinal e a consistência, não um nível de significância.
//
// Entrada: `docs/validacao/backtest_valuation.json`, produzido por
// `npm run tool -- backtest-valuation`. Este utilitário **não vai à rede**.
//
// Uso:
//   npm run tool -- conditional-regression
//   npm run tool -- conditional-regression --aplicativo   # C1a e C1b, anuais
//   npm run tool -- conditional-regression --trimestral   # C1c, C1d e C3
//   npm run tool -- conditional-regression --pacote-habilidade  # B1.0
//
// `--trimestral` grava também `public/assets/validacao/habilidade.json`, a
// leitura que a tela de metas mostra (item B1.0); `--pacote-habilidade` regrava
// só o pacote, a partir de `docs/validacao/habilidade_trimestral.json`, sem
// remedir.
import { existsSync, writeFileSync } from 'node:fs';

import {
  compareNum,
  compareStr,
  DateTime,
  intDiv,
  SkillReadingCodec,
  TransversalOrdering,
  TransversalScore,
  TransversalSignals,
} from '../src/core';
import { DomainCopy } from '../src/copy/domain-copy';
import { errln, fail, jsonPretty, outln, readJson } from './lib/files';
import { Regression, type Summary } from './validation/regression';

type Row = Record<string, unknown>;
type Json = Record<string, unknown>;

/** Uma observação utilizável: os três ordenadores e o retorno, todos presentes. */
export interface Obs {
  /**
   * A data da coorte, ou o ano nas saídas anuais antigas: em ordem de texto é
   * a ordem de data nos dois formatos.
   */
  readonly cohort: string;
  readonly ticker: string;
  readonly upside: number;
  readonly bookToMarket: number;
  readonly earningsYield: number;
  readonly returnRate: number;
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

interface LoadOptions {
  upside?: string;
  bookToMarket?: string;
  earningsYield?: string;
  require?: readonly string[];
  filter?: (m: Row) => boolean;
}

/**
 * Lê as observações de um horizonte, mantendo só as linhas completas.
 *
 * O recorte é **conjunto** de propósito: comparar ordenadores medidos em
 * subconjuntos diferentes compararia coberturas, e não ordenadores.
 * - [upside], [bookToMarket], [earningsYield]: os campos lidos — os da série
 *   de DFPs por padrão; os `…Ancorada` e `…BaseAntiga` nas comparações.
 * - [require]: campos que têm de estar presentes, para que duas leituras sejam
 *   medidas sobre as mesmas observações.
 */
function load(raw: readonly unknown[], returnField: string, options: LoadOptions = {}): Obs[] {
  const out: Obs[] = [];
  for (const row of raw) {
    const m = row as Row;
    if (options.filter !== undefined && !options.filter(m)) continue;
    if ((options.require ?? []).some((c) => num(m[c]) === null)) continue;
    const upsides = num(m[options.upside ?? 'upside']);
    const bm = num(m[options.bookToMarket ?? 'bookToMarket']);
    const ey = num(m[options.earningsYield ?? 'earningsYield']);
    const ret = num(m[returnField]);
    if (upsides === null || bm === null || ey === null || ret === null) continue;
    out.push({
      cohort: `${m['coorte']}`,
      ticker: m['ticker'] as string,
      upside: upsides,
      bookToMarket: bm,
      earningsYield: ey,
      returnRate: ret,
    });
  }
  return out;
}

/**
 * **O instrumento do R3, para quem o reaplica** — a leitura do C7
 * (`tool/c7-reading.ts`). É a mesma função que mede as coortes de 2018 a
 * 2025: reimplementá-la ao lado daria dois instrumentos, e a réplica só vale
 * se o instrumento for o mesmo.
 *
 * - [rows]: observações no formato do backtest — `coorte`, `upside`,
 *   `bookToMarket`, `earningsYield` e o campo de retorno.
 * - [field]: `ret12tot` ou `ret36tot`.
 * - [lag]: `meses ÷ 3 − 1` nas coortes trimestrais.
 */
export function skillHorizon(rows: readonly unknown[], field: string, lag: number): Json {
  return horizon(rows, field, { lag });
}

/** O que uma coorte devolve. */
export class PerCohort {
  constructor(
    readonly cohort: string,
    readonly n: number,
    /** Coeficientes da regressão conjunta, em postos padronizados. */
    readonly upsideCoef: number | null,
    readonly coefBookToMarket: number | null,
    readonly coefEarningsYield: number | null,
    readonly upsideT: number | null,
    readonly r2: number | null,
    /** Coeficiente do potencial condicionado **só** ao P/B — o critério do R3. */
    readonly upsideCoefGivenBm: number | null,
    /** Coeficiente da regressão só com o potencial — equivalente ao IC. */
    readonly aloneCoef: number | null,
    /** Correlação de ordem do resíduo do potencial com o retorno. */
    readonly icIncremental: number | null,
    /**
     * O IC do potencial **ortogonalizado ao book-to-market sozinho** — o item
     * B2, ao pé da letra.
     *
     * [icIncremental] tira do potencial o que o P/B **e** o L/P explicam; este
     * tira só o que o P/B explica. A distinção importa: o P/B é o fator contra
     * o qual a §0 do plano mediu o motor, e é ele que o B2 nomeia. Publicar os
     * dois evita que a grandeza de acompanhamento mude de definição entre
     * rodadas sem ninguém notar.
     */
    readonly incrementalIcGivenBm: number | null,
    /** IC simples de cada ordenador, para conferir contra o relatório anterior. */
    readonly upsideIc: number | null,
    readonly icBookToMarket: number | null,
    readonly icEarningsYield: number | null,
    /**
     * IC do composto — a média dos escores robustos dos três sinais, pela mesma
     * função que o aplicativo usa (item B1, `ordenacao_lado_a_lado.md` §1).
     */
    readonly compositeIc: number | null,
  ) {}

  toJson(): Json {
    return {
      coorte: this.cohort,
      n: this.n,
      coefPotencial: this.upsideCoef,
      coefBookToMarket: this.coefBookToMarket,
      coefEarningsYield: this.coefEarningsYield,
      tPotencial: this.upsideT,
      r2: this.r2,
      coefPotencialDadoBm: this.upsideCoefGivenBm,
      coefSozinho: this.aloneCoef,
      icIncremental: this.icIncremental,
      icIncrementalDadoBm: this.incrementalIcGivenBm,
      icPotencial: this.upsideIc,
      icBookToMarket: this.icBookToMarket,
      icEarningsYield: this.icEarningsYield,
      icComposto: this.compositeIc,
    };
  }
}

function runCohort(cohort: string, obs: readonly Obs[]): PerCohort {
  const upsides = obs.map((o) => o.upside);
  const bm = obs.map((o) => o.bookToMarket);
  const ey = obs.map((o) => o.earningsYield);
  const ret = obs.map((o) => o.returnRate);

  const zUpside = Regression.standardizedRanks(upsides);
  const zBm = Regression.standardizedRanks(bm);
  const zEy = Regression.standardizedRanks(ey);
  const zRet = Regression.standardizedRanks(ret);

  const joint = Regression.ols([zUpside, zBm, zEy], zRet);
  const givenBm = Regression.ols([zUpside, zBm], zRet);
  const alone = Regression.ols([zUpside], zRet);
  const residual = Regression.residualize(zUpside, [zBm, zEy]);
  const residualGivenBm = Regression.residualize(zUpside, [zBm]);
  // O composto com a seção da coorte, pela função do núcleo.
  const composite = TransversalScore.scores(
    new Map(
      obs.map(
        (o, i) =>
          [i, new TransversalSignals({ potential: o.upside, bookToMarket: o.bookToMarket, earningsYield: o.earningsYield })] as const,
      ),
    ),
    TransversalOrdering.composite,
  );

  return new PerCohort(
    cohort,
    obs.length,
    joint?.coefficients[1] ?? null,
    joint?.coefficients[2] ?? null,
    joint?.coefficients[3] ?? null,
    joint?.tStats[1] ?? null,
    joint?.r2 ?? null,
    givenBm?.coefficients[1] ?? null,
    alone?.coefficients[1] ?? null,
    residual === null ? null : Regression.spearman(residual, ret),
    residualGivenBm === null ? null : Regression.spearman(residualGivenBm, ret),
    Regression.spearman(upsides, ret),
    Regression.spearman(bm, ret),
    Regression.spearman(ey, ret),
    Regression.spearman(
      obs.map((_, i) => composite.get(i)!),
      ret,
    ),
  );
}

/**
 * - [lag]: coortes vizinhas cujas janelas se sobrepõem — `h/12 − 1` em
 *   coortes anuais, `h/3 − 1` nas trimestrais —, para o `t` de Newey-West
 *   (item C1a) e para a correção da sobreposição (item C1c).
 */
function horizon(raw: readonly unknown[], field: string, options: LoadOptions & { lag?: number } = {}): Json {
  const lag = options.lag ?? 0;
  const obs = load(raw, field, options);
  const byCohort = new Map<string, Obs[]>();
  for (const o of obs) {
    const list = byCohort.get(o.cohort) ?? [];
    list.push(o);
    byCohort.set(o.cohort, list);
  }
  const cohorts = [...byCohort.keys()].sort(compareStr);

  const rows: PerCohort[] = [];
  for (const c of cohorts) {
    // Menos de 30 ativos numa seção transversal não sustenta três regressores
    // com postos: o erro-padrão fica maior que o coeficiente por construção.
    if (byCohort.get(c)!.length < 30) continue;
    rows.push(runCohort(c, byCohort.get(c)!));
  }

  const col = (f: (l: PerCohort) => number | null) => rows.map(f).filter((v): v is number => v !== null);

  const js = (f: (l: PerCohort) => number | null): Json | null => {
    const v = Regression.summarize(col(f));
    if (v === null) return null;
    // `rows` está em ordem de coorte: é a ordem que a autocovariância exige.
    return {
      media: v.mean,
      desvio: v.sd,
      t: v.t,
      ...tReadings(col(f), lag),
      coortes: v.n,
      positivas: v.positive,
    };
  };

  return {
    observacoes: obs.length,
    coortesUsadas: rows.length,
    porCoorte: rows.map((l) => l.toJson()),
    famaMacBeth: {
      potencialConjunto: js((l) => l.upsideCoef),
      potencialDadoBm: js((l) => l.upsideCoefGivenBm),
      bookToMarketConjunto: js((l) => l.coefBookToMarket),
      earningsYieldConjunto: js((l) => l.coefEarningsYield),
      potencialSozinho: js((l) => l.aloneCoef),
      icIncremental: js((l) => l.icIncremental),
      icIncrementalDadoBm: js((l) => l.incrementalIcGivenBm),
      icPotencial: js((l) => l.upsideIc),
      icBookToMarket: js((l) => l.icBookToMarket),
      icEarningsYield: js((l) => l.icEarningsYield),
      icComposto: js((l) => l.compositeIc),
    },
  };
}

function printHorizon(title: string, h: Json): void {
  outln(`\n=== ${title} ===`);
  outln(`${h['observacoes']} observações, ${h['coortesUsadas']} coortes com n ≥ 30`);

  outln('\ncoorte    n   IC pot  IC P/B  IC L/P |  coef pot   t   IC increm');
  const f = (v: unknown, d = 3) => (v === null || v === undefined ? '   —  ' : (v as number).toFixed(d));
  for (const c of h['porCoorte'] as Json[]) {
    outln(
      `  ${c['coorte']}  ${String(c['n']).padStart(3)}   ${f(c['icPotencial'])}   ${f(c['icBookToMarket'])}   ` +
        `${f(c['icEarningsYield'])} |   ${f(c['coefPotencial'])}  ${f(c['tPotencial'], 2).padStart(6)}     ${f(c['icIncremental'])}`,
    );
  }

  const fmb = h['famaMacBeth'] as Json;
  const row = (label: string, key: string) => {
    const v = fmb[key] as Json | null;
    if (v === null || v === undefined) {
      outln(`  ${label.padEnd(34)} —`);
      return;
    }
    const nw = v['tNeweyWest'] as number | undefined;
    const overlapT = v['tSobreposicao'] as number | undefined;
    const critical = v['criticoSobreposicao'] as number | undefined;
    const p = v['pSobreposicao'] as number | undefined;
    outln(
      `  ${label.padEnd(34)} média=${(v['media'] as number).toFixed(3)}  t=${(v['t'] as number).toFixed(2)}  ` +
        `${nw === undefined ? '' : `t_NW(${v['defasagem']})=${nw.toFixed(2)}  `}` +
        `${overlapT === undefined || critical === undefined || p === undefined ? '' : `t_sob=${overlapT.toFixed(2)}/${critical.toFixed(2)} p=${p.toFixed(3)}  `}` +
        `positivas=${v['positivas']}/${v['coortes']}`,
    );
  };

  outln('\nsegundo passo de Fama-MacBeth:');
  row('IC do potencial (referência)', 'icPotencial');
  row('IC do P/B', 'icBookToMarket');
  row('IC do L/P', 'icEarningsYield');
  row('IC do COMPOSTO', 'icComposto');
  row('coef. do potencial sozinho', 'potencialSozinho');
  row('coef. do potencial DADO O P/B', 'potencialDadoBm');
  row('coef. do potencial COM P/B e L/P', 'potencialConjunto');
  row('coef. do P/B com os outros', 'bookToMarketConjunto');
  row('coef. do L/P com os outros', 'earningsYieldConjunto');
  row('IC INCREMENTAL do potencial', 'icIncremental');
  row('IC ORTOGONALIZADO ao P/B (B2)', 'icIncrementalDadoBm');
}

export async function main(args: string[]): Promise<void> {
  if (args.includes('--aplicativo')) return app();
  if (args.includes('--trimestral')) return quarterly();
  if (args.includes('--custos')) return costs();
  if (args.includes('--pacote-habilidade')) return skillPackage(readJson<Json>('docs/validacao/habilidade_trimestral.json'));
  const file = 'docs/validacao/backtest_valuation.json';
  if (!existsSync(file)) fail('Falta docs/validacao/backtest_valuation.json. Rode antes: npm run tool -- backtest-valuation');

  const raw = readJson<unknown[]>(file);
  errln(`${raw.length} linhas lidas`);

  const result: Json = {
    gerado: DateTime.now().toIso8601String(),
    fonte: 'docs/validacao/backtest_valuation.json',
    h36: horizon(raw, 'ret36'),
    h12: horizon(raw, 'ret12'),
    // Leitura secundária, sobre a série ajustada. A §1.2 das limitações mede
    // desvio mediano de 9,1% entre o ajuste da fonte e o fluxo de proventos
    // publicado, e é por isso que ela não é a principal.
    h36ajustado: horizon(raw, 'ret36aj'),
  };

  // Retorno total, com os proventos da B3 reinvestidos na data ex (item A4,
  // decisão 89). Vem de `tool/dividends-check.ts`, que grava as mesmas
  // coortes com `ret12tot` e `ret36tot`.
  const withTotal = 'docs/validacao/backtest_valuation_total.json';
  if (existsSync(withTotal)) {
    const total = readJson<unknown[]>(withTotal);
    result['h36total'] = horizon(total, 'ret36tot');
    result['h12total'] = horizon(total, 'ret12tot');
  }

  writeFileSync('docs/validacao/regressao_condicional.json', jsonPretty(result));

  printHorizon('36 MESES', result['h36'] as Json);
  printHorizon('12 MESES', result['h12'] as Json);
  printHorizon('36 MESES — série ajustada (secundária, ver §1.2 das limitações)', result['h36ajustado'] as Json);
  if (result['h36total'] !== undefined) {
    printHorizon('36 MESES — retorno total, proventos da B3', result['h36total'] as Json);
    printHorizon('12 MESES — retorno total, proventos da B3', result['h12total'] as Json);
  }

  errln('\nescrito docs/validacao/regressao_condicional.json');
}

/**
 * As leituras do `t` de uma série de coeficientes de coorte em ordem de data.
 *
 * **O critério do R3 (decisão 96).** O `t` corrigido pela estrutura da
 * sobreposição, contra o crítico que a mesma estrutura dá ao nível de `t > 2`,
 * **e** o Newey-West acima de 2. O corrigido não estima nada da série; o
 * Newey-West pega a persistência que vá além da sobreposição.
 */
function tReadings(series: readonly number[], lag: number): Json {
  const nw = Regression.neweyWestMean(series, lag);
  const overlapT = Regression.overlapAdjustedT(series, lag);
  const critical = overlapT === null ? null : Regression.overlapCritical(overlapT.n, overlapT.overlap);
  const out: Json = {};
  if (nw !== null) {
    out['tNeweyWest'] = nw.t;
    out['defasagem'] = nw.lags;
  }
  if (overlapT !== null) out['tSobreposicao'] = overlapT.t;
  if (critical !== null) out['criticoSobreposicao'] = critical;
  if (overlapT !== null) out['pSobreposicao'] = Regression.overlapPValue(overlapT.t, overlapT.n, overlapT.overlap);
  if (overlapT !== null && nw !== null && critical !== null) out['passaR3'] = overlapT.t > critical && nw.t > 2;
  return out;
}

/**
 * Média, entre coortes, de uma diferença entre duas leituras medidas nas mesmas
 * observações, com as mesmas leituras do `t`.
 */
function difference(series: readonly number[], lag: number): Json | null {
  const v: Summary | null = Regression.summarize(series);
  if (v === null) return null;
  return { media: v.mean, t: v.t, ...tReadings(series, lag), coortes: v.n, positivas: v.positive };
}

/**
 * A série ancorada no trimestre contra a de DFPs, nas mesmas observações e com
 * o mesmo B/M da série anual como controle (item C1c).
 *
 * Três perguntas: qual ordena mais sozinha (IC), qual ordena mais dado o B/M,
 * e se uma acrescenta à outra — o coeficiente da ancorada com a anual e o B/M
 * na mesma regressão, e o inverso.
 */
function anchoredComparison(raw: readonly unknown[], field: string, lag: number): Json {
  const require = ['upside', 'upsideAncorada', 'bookToMarket', 'earningsYield'];
  const annual = horizon(raw, field, { lag, require });
  const anchored = horizon(raw, field, { lag, upside: 'upsideAncorada', require });
  const anchoredWithOwnBm = horizon(raw, field, {
    lag,
    upside: 'upsideAncorada',
    bookToMarket: 'bookToMarketAncorada',
    earningsYield: 'earningsYieldAncorada',
    require,
  });

  // Por coorte: a diferença de IC e as regressões cruzadas.
  const byCohort = new Map<string, Row[]>();
  for (const l of raw) {
    const m = l as Row;
    if ([...require, field].some((c) => num(m[c]) === null)) continue;
    const key = `${m['coorte']}`;
    const list = byCohort.get(key) ?? [];
    list.push(m);
    byCohort.set(key, list);
  }
  const diffIc: number[] = [];
  const anchoredGivenAnnual: number[] = [];
  const annualGivenAnchored: number[] = [];
  let moved = 0;
  let total = 0;
  for (const c of [...byCohort.keys()].sort(compareStr)) {
    const g = byCohort.get(c)!;
    if (g.length < 30) continue;
    const col = (k: string) => g.map((m) => num(m[k])!);
    const ret = col(field);
    const a = col('upside');
    const q = col('upsideAncorada');
    total += g.length;
    for (let i = 0; i < a.length; i++) if (Math.abs(a[i]! - q[i]!) > 1e-9) moved++;
    const icQ = Regression.spearman(q, ret);
    const icA = Regression.spearman(a, ret);
    if (icQ !== null && icA !== null) diffIc.push(icQ - icA);
    const r = Regression.ols(
      [Regression.standardizedRanks(q), Regression.standardizedRanks(a), Regression.standardizedRanks(col('bookToMarket'))],
      Regression.standardizedRanks(ret),
    );
    if (r !== null) {
      anchoredGivenAnnual.push(r.coefficients[1]!);
      annualGivenAnchored.push(r.coefficients[2]!);
    }
  }
  const fm = (h: Json, k: string) => ((h['famaMacBeth'] as Json)[k] as Json | null) ?? null;
  return {
    observacoes: annual['observacoes'],
    fracaoComPotencialDiferente: total === 0 ? null : moved / total,
    icAnual: fm(annual, 'icPotencial'),
    icAncorada: fm(anchored, 'icPotencial'),
    diferencaDeIc: difference(diffIc, lag),
    anualDadoBm: fm(annual, 'potencialDadoBm'),
    ancoradaDadoBm: fm(anchored, 'potencialDadoBm'),
    ancoradaDadoSeuBm: fm(anchoredWithOwnBm, 'potencialDadoBm'),
    ancoradaDadaAnualEBm: difference(anchoredGivenAnnual, lag),
    anualDadaAncoradaEBm: difference(annualGivenAnchored, lag),
  };
}

/**
 * Coortes trimestrais, com as deslistadas da ponte ampliada, na montagem na
 * base da data (itens C1c, C1d e C3).
 *
 * Tudo sai da **mesma execução** de `npm run tool -- backtest-valuation
 * --montagem aplicativo --com-deslistadas --trimestral --contrafactual-base`.
 * **Não é o veredito do R3**: a medição da habilidade fica para o fim das
 * fases, a pedido do usuário em 15/09/2026. O que sai aqui é o instrumento
 * calibrado, e a leitura dele.
 */
function quarterly(): void {
  const source = 'docs/validacao/backtest_trimestral.json';
  if (!existsSync(source)) {
    fail(
      `Falta ${source}. Rode antes: npm run tool -- backtest-valuation --montagem aplicativo --com-deslistadas --trimestral --contrafactual-base`,
    );
  }
  const allRows = readJson<unknown[]>(source);
  const listedOnly = (m: Row) => m['deslistada'] !== true;
  const september = (m: Row) => `${m['coorte']}`.endsWith('-09-30');
  errln(`${allRows.length} linhas`);

  const reading = (field: string, months: number): Json => ({
    trimestral: {
      comDeslistadas: horizon(allRows, field, { lag: intDiv(months, 3) - 1 }),
      semDeslistadas: horizon(allRows, field, { lag: intDiv(months, 3) - 1, filter: listedOnly }),
    },
    anualEm30deSetembro: {
      comDeslistadas: horizon(allRows, field, { lag: intDiv(months, 12) - 1, filter: september }),
      semDeslistadas: horizon(allRows, field, { lag: intDiv(months, 12) - 1, filter: (m) => listedOnly(m) && september(m) }),
    },
    ancoradaContraAnual: anchoredComparison(allRows, field, intDiv(months, 3) - 1),
  });

  // O contrafactual da base (item C3): as mesmas observações de 30/09 das
  // listadas, na montagem da rodada anterior e na da data.
  const base = (field: string, months: number): Json => {
    const require = ['upside', 'upsideBaseAntiga', 'bookToMarket', 'bookToMarketBaseAntiga'];
    const f = (m: Row) => listedOnly(m) && september(m);
    return {
      naData: horizon(allRows, field, { lag: intDiv(months, 12) - 1, require, filter: f }),
      baseAntiga: horizon(allRows, field, {
        lag: intDiv(months, 12) - 1,
        upside: 'upsideBaseAntiga',
        bookToMarket: 'bookToMarketBaseAntiga',
        require,
        filter: f,
      }),
    };
  };

  const result: Json = {
    gerado: DateTime.now().toIso8601String(),
    fonte: source,
    retorno: 'total, com os proventos da B3 reinvestidos na data ex',
    h36: reading('ret36tot', 36),
    h12: reading('ret12tot', 12),
    contrafactualDaBase: { h36: base('ret36tot', 36), h12: base('ret12tot', 12) },
  };
  writeFileSync('docs/validacao/habilidade_trimestral.json', jsonPretty(result));
  for (const h of ['h36', 'h12']) {
    const r = result[h] as Json;
    for (const g of ['trimestral', 'anualEm30deSetembro']) {
      for (const a of ['comDeslistadas', 'semDeslistadas']) printHorizon(`${h} — ${g} — ${a}`, (r[g] as Json)[a] as Json);
    }
    outln(`\n=== ${h} — ancorada contra anual ===`);
    outln(jsonPretty(r['ancoradaContraAnual']));
  }
  const counter = result['contrafactualDaBase'] as Json;
  for (const h of ['h36', 'h12']) {
    const b = counter[h] as Json;
    printHorizon(`${h} — base da data`, b['naData'] as Json);
    printHorizon(`${h} — base antiga`, b['baseAntiga'] as Json);
  }
  errln('\nescrito docs/validacao/habilidade_trimestral.json');
  skillPackage(result);
}

/** Caminho do pacote da habilidade que o aplicativo lê (item B1.0). */
const skillPackageFile = 'public/assets/validacao/habilidade.json';

/**
 * Grava a leitura que a tela de metas mostra: 36 meses, coortes trimestrais,
 * com as deslistadas — a amostra do R3 (decisões 93 e 96).
 *
 * O pacote leva os números, e não o veredito: o critério da decisão 96 e a
 * regra que escolhe a ordenação do prêmio (item B1, `ordenacao_lado_a_lado.md`
 * §1) moram em `SkillReading`, e o teste do pacote confere que eles concordam
 * com o `passaR3` desta medição.
 */
function skillPackage(result: Json): void {
  const m = (v: unknown) => v as Json;
  const sample = m(m(m(result['h36'])['trimestral'])['comDeslistadas']);
  const fm = m(sample['famaMacBeth']);
  const datum = m(fm['potencialDadoBm']);
  const reading = (key: string) => {
    const l = m(fm[key]);
    return { ic: l['media'], tCorrigido: l['tSobreposicao'], critico: l['criticoSobreposicao'], tNeweyWest: l['tNeweyWest'] };
  };

  const pkg = {
    versao: SkillReadingCodec.version,
    fonte: 'docs/validacao/habilidade_trimestral.json',
    medidoEm: `${result['gerado']}`.slice(0, 10),
    horizonteMeses: 36,
    coortes: datum['coortes'],
    observacoes: sample['observacoes'],
    potencialDadoBookToMarket: {
      coeficiente: datum['media'],
      tCorrigido: datum['tSobreposicao'],
      critico: datum['criticoSobreposicao'],
      tNeweyWest: datum['tNeweyWest'],
    },
    ordenacoes: {
      [SkillReadingCodec.key(TransversalOrdering.composite)]: reading('icComposto'),
      [SkillReadingCodec.key(TransversalOrdering.bookToMarket)]: reading('icBookToMarket'),
      [SkillReadingCodec.key(TransversalOrdering.potential)]: reading('icPotencial'),
    },
  };
  const readOrdering = SkillReadingCodec.decode(pkg);
  if (readOrdering === null) fail('A leitura da habilidade saiu malformada; o pacote não foi gravado.', 1);
  writeFileSync(skillPackageFile, JSON.stringify(pkg));
  const premium = readOrdering.premiumOrdering;
  errln(
    `escrito ${skillPackageFile} — potencial dado o B/M ${readOrdering.demonstrated ? 'comprovado' : 'não comprovado'}; prêmio do ` +
      `retorno esperado: ${premium === null ? 'nenhum, nenhuma ordenação passou' : DomainCopy.ordering(premium)}`,
  );
}

/**
 * A habilidade sobre a montagem do aplicativo por data, com e sem as
 * deslistadas, no retorno total (itens C1a e C1b).
 *
 * As duas amostras saem da **mesma execução** de
 * `npm run tool -- backtest-valuation --montagem aplicativo
 * --com-deslistadas`: comparar com uma execução anterior misturaria o efeito
 * das deslistadas com a deriva do dado de mercado.
 */
function app(): void {
  const source = 'docs/validacao/backtest_aplicativo_deslistadas.json';
  if (!existsSync(source)) {
    fail(`Falta ${source}. Rode antes: npm run tool -- backtest-valuation --montagem aplicativo --com-deslistadas`);
  }
  const allRows = readJson<Row[]>(source);
  const listed = allRows.filter((l) => l['deslistada'] !== true);
  errln(`${allRows.length} linhas, ${listed.length} de listadas`);

  const result: Json = {
    gerado: DateTime.now().toIso8601String(),
    fonte: source,
    retorno: 'total, com os proventos da B3 reinvestidos na data ex',
    h36: {
      semDeslistadas: horizon(listed, 'ret36tot', { lag: 2 }),
      comDeslistadas: horizon(allRows, 'ret36tot', { lag: 2 }),
    },
    h12: {
      semDeslistadas: horizon(listed, 'ret12tot'),
      comDeslistadas: horizon(allRows, 'ret12tot'),
    },
  };
  writeFileSync('docs/validacao/habilidade_aplicativo.json', jsonPretty(result));
  for (const h of ['h36', 'h12']) {
    for (const a of ['semDeslistadas', 'comDeslistadas']) {
      printHorizon(`${h === 'h36' ? '36' : '12'} MESES — ${a}`, (result[h] as Json)[a] as Json);
    }
  }
  errln('\nescrito docs/validacao/habilidade_aplicativo.json');
}

/**
 * A habilidade sobre o retorno **líquido** de custo de transação (item C4).
 *
 * O custo de ida e volta de cada observação sai de `tool/custos_spread.py`:
 * tarifa da B3 nas duas pontas e meio spread de Abdi e Ranaldo em cada uma.
 * O retorno líquido é `(1 + r)·fator − 1`, e o resto é a mesma medição de
 * `--trimestral` — coortes trimestrais com as deslistadas, 36 e 12 meses,
 * critério da decisão 96.
 *
 * **Custo uniforme não mexe no IC**, e isto não é descoberta: somar a mesma
 * constante a todos os retornos de uma coorte preserva a ordem. O que o custo
 * pode mudar é a ordem **quando ele varia com a liquidez** — e varia, de
 * 0,4% a 1,7% de spread entre os tercis. Por isso a medição importa.
 */
function costs(): void {
  const source = 'docs/validacao/backtest_trimestral.json';
  const costsFile = 'docs/validacao/custos_spread.json';
  for (const f of [source, costsFile]) {
    if (!existsSync(f)) {
      fail(
        `Falta ${f}. Rode antes: npm run tool -- backtest-valuation --montagem aplicativo --com-deslistadas --trimestral, ` +
          'python tool/b3_baixar.py --extremos --de 2017 e python tool/custos_spread.py',
      );
    }
  }
  const allRows = readJson<Row[]>(source);
  const byObs = readJson<{ porObservacao: Record<string, Json> }>(costsFile).porObservacao;
  let withoutCost = 0;
  for (const m of allRows) {
    const c = byObs[`${m['coorte']}|${m['ticker']}`];
    if (c === undefined) {
      withoutCost++;
      continue;
    }
    for (const h of ['12', '36']) {
      const r = num(m[`ret${h}tot`]);
      const f = num(c[`fator${h}`]);
      if (r !== null && f !== null) m[`ret${h}totLiq`] = (1 + r) * f - 1;
    }
  }

  /** Custo de ida e volta de cada observação, `1 − fator`, por horizonte. */
  const costOf = (o: Obs, h: string): number | null => {
    const f = num(byObs[`${o.cohort}|${o.ticker}`]?.[`fator${h}`]);
    return f === null ? null : 1 - f;
  };

  /**
   * Quintil de cima menos o de baixo, por coorte, em média igual.
   *
   * Com [cost], acrescenta a carteira **comprada e vendida**: a diferença
   * entre os líquidos já desconta o custo da ponta comprada, mas trata a
   * vendida como se o custo dela a favorecesse. Vender a descoberto e zerar
   * também paga spread e tarifa — o custo da perna vendida entra duas vezes,
   * uma para desfazer o sinal errado e outra para cobrá-lo.
   */
  const quintiles = (obs: readonly Obs[], key: (o: Obs) => number, cost?: (o: Obs) => number | null): Json => {
    const byCohort = new Map<string, Obs[]>();
    for (const o of obs) {
      const list = byCohort.get(o.cohort) ?? [];
      list.push(o);
      byCohort.set(o.cohort, list);
    }
    const diffs: number[] = [];
    const longShort: number[] = [];
    for (const g of byCohort.values()) {
      if (g.length < 30) continue;
      const s = [...g].sort((a, b) => compareNum(key(a), key(b)));
      const q = intDiv(s.length, 5);
      const mean = (xs: readonly number[]) => xs.reduce((a, b) => a + b) / xs.length;
      const top = s.slice(s.length - q);
      const bottom = s.slice(0, q);
      const d = mean(top.map((o) => o.returnRate)) - mean(bottom.map((o) => o.returnRate));
      diffs.push(d);
      if (cost !== undefined) longShort.push(d - 2 * mean(bottom.map((o) => cost(o) ?? 0)));
    }
    const v = Regression.summarize(diffs);
    const cv = Regression.summarize(longShort);
    return {
      media: v?.mean ?? null,
      t: v?.t ?? null,
      coortes: diffs.length,
      ...(cv === null ? {} : { compradoVendido: { media: cv.mean, t: cv.t } }),
    };
  };

  const pair = (raw: string, net: string, months: number): Json => {
    const h = `${months}`;
    const lag = intDiv(months, 3) - 1;
    // As mesmas observações nas duas leituras: a bruta só entra onde a líquida
    // existe.
    const require = [raw, net];
    const reading = (field: string, withCost: boolean): Json => {
      const r = horizon(allRows, field, { lag, require });
      const obs = load(allRows, field, { require });
      const returns = obs.map((o) => o.returnRate).sort(compareNum);
      const costList = obs.map((o) => costOf(o, h)).filter((c): c is number => c !== null).sort(compareNum);
      const cost = withCost ? (o: Obs) => costOf(o, h) : undefined;
      return {
        ...r,
        retornoMediano: returns.length === 0 ? null : returns[intDiv(returns.length, 2)],
        ...(withCost ? { custoIdaEVoltaMediano: costList.length === 0 ? null : costList[intDiv(costList.length, 2)] } : {}),
        quintilPotencial: quintiles(obs, (o) => o.upside, cost),
        quintilBookToMarket: quintiles(obs, (o) => o.bookToMarket, cost),
      };
    };
    return { bruto: reading(raw, false), liquido: reading(net, true) };
  };

  const result: Json = {
    gerado: DateTime.now().toIso8601String(),
    fonte: source,
    custos: costsFile,
    observacoesSemCusto: withoutCost,
    h36: pair('ret36tot', 'ret36totLiq', 36),
    h12: pair('ret12tot', 'ret12totLiq', 12),
  };
  writeFileSync('docs/validacao/custos_transacao.json', jsonPretty(result));

  for (const h of ['h36', 'h12']) {
    const r = result[h] as Json;
    outln(`\n=== ${h}: bruto contra líquido ===`);
    for (const k of ['bruto', 'liquido']) {
      const l = r[k] as Json;
      const fm = l['famaMacBeth'] as Json;
      const ic = (key: string) => {
        const v = fm[key] as Json | null;
        if (v === null || v === undefined) return '—';
        const overlapT = v['tSobreposicao'] as number | undefined;
        const nw = v['tNeweyWest'] as number | undefined;
        return (
          `${(v['media'] as number).toFixed(3)} (t_sob ${overlapT?.toFixed(2) ?? '—'}, NW ${nw?.toFixed(2) ?? '—'}, ` +
          `${v['passaR3'] === true ? 'PASSA' : 'não passa'})`
        );
      };

      const qp = l['quintilPotencial'] as Json;
      const qb = l['quintilBookToMarket'] as Json;
      const pct = (v: unknown) => (v === null || v === undefined ? '—' : `${((v as number) * 100).toFixed(2)}%`);
      outln(`  ${k}  n=${l['observacoes']}  retorno mediano ${pct(l['retornoMediano'])}`);
      outln(`    potencial dado o B/M  ${ic('potencialDadoBm')}`);
      outln(`    IC do potencial       ${ic('icPotencial')}`);
      outln(`    IC do B/M             ${ic('icBookToMarket')}`);
      outln(`    IC do L/P             ${ic('icEarningsYield')}`);
      outln(`    IC do composto        ${ic('icComposto')}`);
      const cv = (q: Json) => {
        const c = q['compradoVendido'] as Json | undefined;
        return c === undefined ? '' : ` (comprado-vendido ${pct(c['media'])})`;
      };
      outln(`    Q5−Q1 potencial ${pct(qp['media'])}${cv(qp)}  Q5−Q1 B/M ${pct(qb['media'])}${cv(qb)}`);
      if (l['custoIdaEVoltaMediano'] !== null && l['custoIdaEVoltaMediano'] !== undefined) {
        outln(`    custo de ida e volta mediano ${pct(l['custoIdaEVoltaMediano'])}`);
      }
    }
  }
  errln('\nescrito docs/validacao/custos_transacao.json');
}
