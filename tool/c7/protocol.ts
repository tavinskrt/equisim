// O protocolo da réplica fora da amostra (item C7, decisões 129 e 133).
//
// **O que ele garante.** A única via pela qual o R3 poderia vir a passar é dado
// que nenhuma decisão do motor viu, lido pelo instrumento que já existe, nas
// datas fixadas antes de vê-lo. Três coisas estragariam isso, e cada uma tem
// uma trava aqui:
//
// 1. **mexer na previsão depois de ver o desfecho** — as previsões de cada
//    coorte são **seladas** num arquivo que nunca é reescrito, com o hash do
//    git dele no índice, antes de o retorno existir; a leitura usa a previsão
//    selada, e não uma refeita;
// 2. **espiar antes da data** — a leitura recusa aplicar o critério antes de
//    30/09/2029 (12 meses) e 30/09/2031 (36 meses), e até lá diz só quantas
//    coortes já estão seladas e maduras;
// 3. **juntar as coortes antigas para passar** — só entra coorte a partir de
//    31/12/2025, e a leitura recusa observação anterior em vez de filtrá-la
//    em silêncio.
//
// **O motor é identificado pela impressão**, e não por data: o hash do git de
// cada fonte do núcleo, num manifesto ordenado, e o hash do manifesto. É o
// mesmo hash que o git dá aos blobs, e por isso a impressão de um selo pode ser
// reencontrada em qualquer commit futuro. Quando o motor muda, a selagem segue
// numa segunda série — «motor da data» —, e a série do motor pré-registrado
// precisa ser produzida por ele, num `git worktree` do commit que o índice
// registra.
//
// **Duas árvores de núcleo** (decisão 152): o motor pré-registrado é o núcleo
// em Dart, `packages/equisim_core/lib/**/*.dart`, que o git guarda; o motor de
// hoje é o porte em TypeScript, `src/core/**/*.ts`. A impressão é a mesma conta
// sobre cada árvore, e a busca do commit de uma impressão procura nas duas.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';

import { compareStr, DateTime, intDiv } from '../../src/core';
import { skillHorizon } from '../conditional-regression';
import { jsonPretty } from '../lib/files';

/** Primeira coorte da réplica. */
export const firstCohort = '2025-12-31';

/** Datas de leitura fixadas pela decisão 129, antes de qualquer coorte nova. */
export const readingDates: ReadonlyMap<number, DateTime> = new Map([
  [12, DateTime.local(2029, 9, 30)],
  [36, DateTime.local(2031, 9, 30)],
]);

/** Onde os selos moram: é versionado, e é essa a prova de quando foram feitos. */
export const sealsDir = 'docs/validacao/c7';

/** Uma árvore de fontes do núcleo, com a extensão das fontes. */
export interface EngineTree {
  readonly root: string;
  readonly extension: string;
}

/** O núcleo de hoje: o porte em TypeScript. */
export const currentTree: EngineTree = { root: 'src/core', extension: '.ts' };

/** O núcleo em Dart, que produziu o motor pré-registrado e vive no histórico. */
export const dartTree: EngineTree = { root: 'packages/equisim_core/lib', extension: '.dart' };

/**
 * O que uma previsão selada guarda — e nada de desfecho. Os sinais das cinco
 * ordenações (o múltiplo de pares sai de `firmaSobreEbitda` e das grandezas
 * ao lado, com a mediana da própria coorte) e o que identifica a observação.
 */
export const sealedFields: readonly string[] = [
  'coorte',
  'ticker',
  'deslistada',
  'setor',
  'preco',
  'justo',
  'upside',
  'modelo',
  'recusa',
  'bookToMarket',
  'earningsYield',
  'firmaSobreEbitda',
  'ebitda',
  'dividaLiquida',
  'lucro',
  'patrimonio',
  'valorDeMercado',
  'liquidez',
  'volatilidade',
  'ke',
  'fimDoExercicio',
];

type Json = Record<string, unknown>;

/** Falha do protocolo: o que foi pedido quebraria uma das três travas. */
export class ProtocolViolated extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ProtocolViolated';
  }

  override toString(): string {
    return `Protocolo do C7 violado: ${this.message}`;
  }
}

/** O motor que produziu uma previsão. */
export class Engine {
  constructor(
    /** Hash do manifesto das fontes do núcleo. Ver [engineFingerprint]. */
    readonly fingerprint: string,
    /** `HEAD` no momento da selagem. */
    readonly commit: string | null = null,
    /**
     * `false` quando o núcleo tinha mudança não commitada: a impressão ainda
     * identifica o motor, e o commit que a contém é o seguinte a `commit`.
     */
    readonly clean = true,
  ) {}

  toJson(): Json {
    return { impressao: this.fingerprint, commitBase: this.commit, arvoreLimpa: this.clean };
  }

  static fromJson(j: Json): Engine {
    return new Engine(j['impressao'] as string, (j['commitBase'] as string | null | undefined) ?? null, (j['arvoreLimpa'] as boolean | undefined) ?? true);
  }
}

async function git(args: readonly string[], options: { entry?: string; directory?: string } = {}): Promise<string> {
  const p = spawnSync('git', args, {
    cwd: options.directory,
    input: options.entry ?? '',
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
  if (p.status !== 0) throw new ProtocolViolated(`git ${args.join(' ')} falhou: ${p.stderr ?? p.error?.message ?? ''}`);
  return p.stdout.trim();
}

/** Hash do git de um arquivo — o mesmo que o blob dele teria num commit. */
export function fileHash(path: string): Promise<string> {
  return git(['hash-object', path]);
}

function sourcesUnder(dir: string, extension: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = `${dir}/${name}`;
    if (statSync(path).isDirectory()) out.push(...sourcesUnder(path, extension));
    else if (name.endsWith(extension)) out.push(path.replaceAll('\\', '/'));
  }
  return out;
}

/**
 * A impressão do motor: o hash do manifesto `caminho hash` das fontes da
 * árvore do núcleo, em ordem de caminho.
 */
export async function engineFingerprint(tree: EngineTree = currentTree): Promise<string> {
  const sources = sourcesUnder(tree.root, tree.extension).sort(compareStr);
  const hashes = (await git(['hash-object', '--stdin-paths'], { entry: sources.join('\n') })).split('\n');
  if (hashes.length !== sources.length) {
    throw new ProtocolViolated(`o git devolveu ${hashes.length} hashes para ${sources.length} fontes`);
  }
  const manifest = sources.map((s, i) => `${s} ${hashes[i]}`).join('\n');
  return git(['hash-object', '--stdin'], { entry: `${manifest}\n` });
}

/**
 * A impressão do núcleo **num commit**, pela árvore dele — a mesma conta de
 * [engineFingerprint] sobre uma árvore de trabalho limpa naquele commit.
 */
export async function commitFingerprint(commit: string, tree: EngineTree = currentTree): Promise<string> {
  const output = await git(['ls-tree', '-r', commit, '--', tree.root]);
  const sources: { path: string; hash: string }[] = [];
  for (const l of output.split('\n')) {
    const tab = l.indexOf('\t');
    if (tab < 0) continue;
    const path = l.slice(tab + 1);
    if (!path.endsWith(tree.extension)) continue;
    const fields = l.slice(0, tab).split(' ');
    if (fields.length < 3) continue;
    sources.push({ path, hash: fields[2]! });
  }
  sources.sort((a, b) => compareStr(a.path, b.path));
  const manifest = sources.map((f) => `${f.path} ${f.hash}`).join('\n');
  return git(['hash-object', '--stdin'], { entry: `${manifest}\n` });
}

/**
 * O commit **mais antigo** cujo núcleo tem a impressão [fingerprint], com a
 * árvore em que ela foi achada, ou `null` quando ela ainda não está em commit
 * nenhum.
 *
 * A impressão só muda quando o núcleo muda, e por isso basta olhar os commits
 * que o tocaram; o primeiro que casa é o que a introduziu, e todo commit
 * seguinte que não tocou o núcleo tem a mesma. Procura no núcleo em
 * TypeScript e no em Dart, que o histórico guarda.
 */
export async function commitOfFingerprint(fingerprint: string): Promise<{ commit: string; tree: EngineTree } | null> {
  for (const tree of [currentTree, dartTree]) {
    const commits = (await git(['log', '--reverse', '--format=%H', '--', tree.root])).split('\n').filter((c) => c.trim() !== '');
    for (const c of commits) if ((await commitFingerprint(c, tree)) === fingerprint) return { commit: c, tree };
  }
  return null;
}

/** O motor desta árvore de trabalho. */
export async function currentEngine(): Promise<Engine> {
  return new Engine(
    await engineFingerprint(),
    await git(['rev-parse', 'HEAD']),
    (await git(['status', '--porcelain', '--', currentTree.root])) === '',
  );
}

/** As previsões seladas de uma coorte, sem nenhum campo de desfecho. */
export function predictionsOf(cohort: string, rows: readonly Json[]): Json[] {
  const out: Json[] = [];
  for (const l of rows) {
    if (l['coorte'] !== cohort) continue;
    const p: Json = {};
    // O campo ausente na linha entra nulo, como o `l[c]` do mapa em Dart.
    for (const c of sealedFields) p[c] = l[c] ?? null;
    out.push(p);
  }
  out.sort((a, b) => compareStr(a['ticker'] as string, b['ticker'] as string));
  for (const p of out) {
    if (Object.keys(p).some((k) => k.startsWith('ret'))) throw new ProtocolViolated('campo de desfecho numa previsão selada');
  }
  return out;
}

/**
 * A forma canônica de uma previsão, para comparar a selada com a refeita.
 *
 * O selo pode ter sido gravado pelo Dart, que escreve `2.0` onde o JavaScript
 * escreve `2`: comparar o texto do arquivo com o texto refeito acusaria
 * divergência que não existe. As duas passam pelo mesmo `JSON.stringify`.
 */
const canonical = (p: unknown) => JSON.stringify(p);

/** O índice dos selos. */
export class Index {
  constructor(
    public preRegisteredEngine: Engine | null = null,
    readonly seals: Json[] = [],
  ) {}

  private static file(folder: string): string {
    return `${folder}/indice.json`;
  }

  static read(folder: string): Index {
    const f = Index.file(folder);
    if (!existsSync(f)) return new Index();
    const j = JSON.parse(readFileSync(f, 'utf8')) as Json;
    return new Index(
      j['motorPreRegistrado'] === null || j['motorPreRegistrado'] === undefined ? null : Engine.fromJson(j['motorPreRegistrado'] as Json),
      [...(j['selos'] as Json[])],
    );
  }

  save(folder: string): void {
    mkdirSync(folder, { recursive: true });
    const dates: Json = {};
    for (const [months, d] of readingDates) dates[`${months}m`] = d.toIso8601String().slice(0, 10);
    writeFileSync(
      Index.file(folder),
      `${jsonPretty({
        protocolo: 'decisão 129, operacionalizada pela 133',
        primeiraCoorte: firstCohort,
        datasDeLeitura: dates,
        motorPreRegistrado: this.preRegisteredEngine?.toJson() ?? null,
        selos: this.seals,
      })}\n`,
    );
  }

  /** Os selos de um motor, por coorte. */
  ofFingerprint(fingerprint: string): Map<string, Json> {
    const out = new Map<string, Json>();
    for (const s of this.seals) if (s['motor'] === fingerprint) out.set(s['coorte'] as string, s);
    return out;
  }
}

/**
 * Confere o hash de todo arquivo selado contra o índice. Um arquivo mexido
 * depois de selado é violação, e nada segue.
 */
export async function checkSeals(folder: string, index: Index): Promise<void> {
  for (const s of index.seals) {
    const f = `${folder}/${s['arquivo']}`;
    if (!existsSync(f)) throw new ProtocolViolated(`o selo ${s['arquivo']} sumiu`);
    const h = await fileHash(f);
    if (h !== s['hash']) throw new ProtocolViolated(`o selo ${s['arquivo']} foi alterado depois de selado: hash ${h}, índice ${s['hash']}`);
  }
}

/** O que a selagem fez. */
export class Sealing {
  readonly sealedCohorts: string[] = [];
  readonly alreadySealed: string[] = [];
  /**
   * Coortes já seladas cujas previsões, refeitas agora pelo mesmo motor, não
   * batem com o selo — e quantas observações divergem. O selo não muda.
   */
  readonly divergent = new Map<string, number>();
  series: 'preRegistrado' | 'motorDaData' = 'preRegistrado';
}

/**
 * Sela as coortes de [rows] que ainda não têm selo deste [engine].
 *
 * Nunca reescreve um selo. A primeira selagem registra o motor
 * pré-registrado; um motor diferente dele sela numa segunda série.
 */
export async function seal(args: { rows: readonly Json[]; engine: Engine; folder: string; today: string }): Promise<Sealing> {
  const { rows, engine, folder, today } = args;
  const index = Index.read(folder);
  await checkSeals(folder, index);
  index.preRegisteredEngine ??= engine;
  const preRegistered = index.preRegisteredEngine.fingerprint === engine.fingerprint;
  const result = new Sealing();
  result.series = preRegistered ? 'preRegistrado' : 'motorDaData';

  const cohorts = [...new Set(rows.map((l) => l['coorte'] as string))].sort(compareStr);
  const oldVersions = cohorts.filter((c) => compareStr(c, firstCohort) < 0);
  if (oldVersions.length > 0) {
    throw new ProtocolViolated(`coortes anteriores a ${firstCohort} não são da réplica: ${oldVersions.join(', ')}`);
  }
  const existing = index.ofFingerprint(engine.fingerprint);
  for (const c of cohorts) {
    const predictions = predictionsOf(c, rows);
    const alreadyThere = existing.get(c);
    if (alreadyThere !== undefined) {
      result.alreadySealed.push(c);
      const sealedJson = JSON.parse(readFileSync(`${folder}/${alreadyThere['arquivo']}`, 'utf8')) as Json;
      const before = new Map((sealedJson['previsoes'] as Json[]).map((p) => [p['ticker'], canonical(p)] as const));
      const n = predictions.filter((p) => before.get(p['ticker']) !== canonical(p)).length;
      if (n > 0) result.divergent.set(c, n);
      continue;
    }
    const name = preRegistered ? `previsoes_${c}.json` : `previsoes_${c}_${engine.fingerprint.slice(0, 8)}.json`;
    const f = `${folder}/${name}`;
    if (existsSync(f)) throw new ProtocolViolated(`${name} existe sem entrada no índice`);
    mkdirSync(folder, { recursive: true });
    writeFileSync(
      f,
      `${jsonPretty({
        coorte: c,
        serie: result.series,
        motor: engine.toJson(),
        seladoEm: today,
        observacoes: predictions.length,
        previsoes: predictions,
      })}\n`,
    );
    index.seals.push({
      coorte: c,
      arquivo: name,
      hash: await fileHash(f),
      motor: engine.fingerprint,
      serie: result.series,
      seladoEm: today,
      observacoes: predictions.length,
    });
    result.sealedCohorts.push(c);
  }
  index.save(folder);
  return result;
}

/**
 * Duas previsões diferem? Por tolerância relativa, e nunca por igualdade de
 * `number` (regra R6); `null` só é igual a `null`.
 */
function differ(a: unknown, b: unknown): boolean {
  if (typeof a === 'number' && typeof b === 'number') {
    const scale = Math.abs(b) > 1 ? Math.abs(b) : 1;
    return Math.abs(a - b) > 1e-9 * scale;
  }
  return (a === null || a === undefined) !== (b === null || b === undefined);
}

/** Soma [months] ao último dia de um mês, ficando no último dia. */
export function endOfMonth(d: DateTime, months: number): DateTime {
  return DateTime.local(d.year, d.month + months + 1, 0);
}

/**
 * O que a leitura pode dizer antes da data: quantas coortes estão seladas e
 * quantas já têm o retorno do horizonte, sem estatística alguma.
 */
export function situation(args: { folder: string; today: DateTime; dataEnd: DateTime }): Json {
  const index = Index.read(args.folder);
  const preRegistered = index.preRegisteredEngine;
  const sealedCohorts = preRegistered === null ? [] : [...index.ofFingerprint(preRegistered.fingerprint).keys()].sort(compareStr);
  const byEngine = new Map<string, string[]>();
  for (const s of index.seals) {
    const list = byEngine.get(s['motor'] as string) ?? [];
    list.push(s['coorte'] as string);
    byEngine.set(s['motor'] as string, list);
  }
  const engines: Json = {};
  // As séries de motores posteriores ao pré-registrado (decisão 133).
  for (const [engine, cohorts] of byEngine) if (engine !== preRegistered?.fingerprint) engines[engine] = cohorts.sort(compareStr);
  const out: Json = {
    motorPreRegistrado: preRegistered?.toJson() ?? null,
    coortesSeladas: sealedCohorts,
    motoresDaData: engines,
  };
  for (const [months, date] of readingDates) {
    out[`${months}m`] = {
      dataDaLeitura: date.toIso8601String().slice(0, 10),
      aberta: !args.today.isBefore(date),
      coortesMaduras: sealedCohorts.filter((c) => !endOfMonth(DateTime.parse(c), months).isAfter(args.dataEnd)).length,
    };
  }
  return out;
}

/**
 * A leitura de um horizonte, pelo instrumento do R3, sobre as previsões
 * **seladas** do motor pré-registrado e os retornos realizados de [rows].
 *
 * Recusa antes da data fixada, recusa observação anterior à primeira coorte
 * e recusa selo alterado. Diz quantas previsões refeitas em [rows] divergem
 * das seladas — a leitura usa as seladas de qualquer jeito.
 */
export async function read(args: { months: number; folder: string; today: DateTime; rows: readonly Json[] }): Promise<Json> {
  const { months, folder, today, rows } = args;
  const date = readingDates.get(months);
  if (date === undefined) throw new ProtocolViolated(`horizonte ${months} não registrado`);
  if (today.isBefore(date)) {
    throw new ProtocolViolated(
      `a leitura de ${months} meses está fixada para ${date.toIso8601String().slice(0, 10)}; antes disso só a situação pode ser consultada`,
    );
  }
  const index = Index.read(folder);
  await checkSeals(folder, index);
  const preRegistered = index.preRegisteredEngine;
  if (preRegistered === null) throw new ProtocolViolated('nenhuma coorte selada');

  if (rows.some((l) => compareStr(l['coorte'] as string, firstCohort) < 0)) {
    throw new ProtocolViolated(`juntar coortes anteriores a ${firstCohort} às novas é proibido (decisão 129)`);
  }
  const field = `ret${months}tot`;
  const returnRate = new Map(rows.map((l) => [`${l['coorte']}|${l['ticker']}`, l] as const));

  /** As previsões seladas de um motor, com o retorno realizado ao lado. */
  const ofSeries = (fingerprint: string) => {
    const observations: Json[] = [];
    let divergent = 0;
    const seals = index.ofFingerprint(fingerprint);
    for (const c of [...seals.keys()].sort(compareStr)) {
      const sealedJson = JSON.parse(readFileSync(`${folder}/${seals.get(c)!['arquivo']}`, 'utf8')) as Json;
      for (const p of sealedJson['previsoes'] as Json[]) {
        const r = returnRate.get(`${c}|${p['ticker']}`);
        if (r !== undefined && differ(r['upside'], p['upside'])) divergent++;
        observations.push({ ...p, [field]: r?.[field] ?? null });
      }
    }
    return { obs: observations, divergent };
  };

  const preRegisteredSeries = ofSeries(preRegistered.fingerprint);
  // **As duas versões, como a decisão 129 pede**: a do motor pré-registrado é
  // a leitura do C7; a de cada motor posterior, selada em série própria, vem ao
  // lado — para que a réplica não vire reajuste, e para que se veja o que as
  // correções depois do selo fizeram.
  const others = [...new Set(index.seals.filter((s) => s['motor'] !== preRegistered.fingerprint).map((s) => s['motor'] as string))].sort(
    compareStr,
  );
  const lag = intDiv(months, 3) - 1;
  const engines: Json = {};
  for (const m of others) engines[m] = skillHorizon(ofSeries(m).obs, field, lag);
  return {
    horizonteEmMeses: months,
    motorPreRegistrado: preRegistered.toJson(),
    previsoesRefeitasQueDivergem: preRegisteredSeries.divergent,
    leitura: skillHorizon(preRegisteredSeries.obs, field, lag),
    motoresDaData: engines,
  };
}
