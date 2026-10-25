// A série do motor pré-registrado do C7, produzida pelo commit dele (item C7,
// decisões 133 e 138).
//
// **Quando o motor muda, a selagem do dia sela a série «motor da data».** A
// série pré-registrada das coortes novas tem de sair do motor que selou
// primeiro — e o motor não é só o núcleo: é o pipeline inteiro daquele commit,
// com as ferramentas que montavam as coortes. Este programa acha o commit pela
// impressão do índice, monta um `git worktree` dele fora do repositório, liga a
// base bruta — que o git não versiona — por junção, roda nele o backtest em
// modo `--c7` e sela o resultado com a impressão pré-registrada.
//
// **O motor pré-registrado é o núcleo em Dart** (decisão 152): o commit dele
// tem o `pubspec.yaml` e o `tool/backtest_valuation.dart`, e por isso este
// programa roda nele o `flutter pub get` e o `dart run` — o SDK do Flutter
// precisa estar no PATH. Um motor pré-registrado já em TypeScript rodaria com
// `npm ci` e `npm run tool -- backtest-valuation`; a escolha é pela árvore em
// que a impressão foi achada.
//
// **É também a prova de que o selo se reproduz.** As coortes já seladas são
// refeitas pelo mesmo commit, sobre a mesma base, e conferidas contra o selo:
// divergência zero é o motor pré-registrado reproduzido ao último dígito.
//
// Uso, a cada trimestre fechado, **depois** de `npm run tool -- c7-seal`:
//   npm run tool -- c7-preregistered [--fim-dos-dados AAAA-MM-DD] [--hoje AAAA-MM-DD]
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { DateTime } from '../src/core';
import { commitOfFingerprint, dartTree, Engine, Index, ProtocolViolated, seal, sealsDir } from './c7/protocol';
import { errln, fail, flagValue, outln } from './lib/files';

/**
 * O que o backtest lê e o git não versiona: pastas ligadas por junção, e
 * arquivos copiados — o cache da fonte de mercado é escrito pelo backtest, e
 * cada árvore precisa do seu.
 */
const baseDirs = ['data/b3', 'data/cvm', 'data/tesouro', 'data/gabarito'];
const baseFiles = ['data/cvm_exercicios.json', 'data/cvm_versoes.json', 'docs/validacao/validation_cache.sqlite'];

const exists = (path: string) => {
  try {
    lstatSync(path);
    return true;
  } catch {
    return false;
  }
};

export async function main(args: string[]): Promise<void> {
  const folder = sealsDir;
  const index = Index.read(folder);
  const preRegistered = index.preRegisteredEngine;
  if (preRegistered === null) fail('Nenhuma coorte selada: rode antes npm run tool -- c7-seal.');
  const found = await commitOfFingerprint(preRegistered.fingerprint);
  if (found === null) {
    fail(
      `O núcleo de impressão ${preRegistered.fingerprint} ainda não está em commit nenhum. Commite a selagem antes: o worktree precisa do commit.`,
    );
  }
  const { commit, tree: engineTree } = found;
  outln(`motor pré-registrado: ${preRegistered.fingerprint.slice(0, 12)}… no commit ${commit.slice(0, 7)}`);

  const root = process.cwd();
  const tree = join(tmpdir(), `equisim_c7_${commit.slice(0, 8)}`);
  if (!existsSync(tree)) run('git', ['worktree', 'add', '--detach', tree, commit], root);
  for (const p of baseDirs) {
    const destination = join(root, p);
    const link = join(tree, p);
    if (!existsSync(destination) || exists(link)) continue;
    mkdirSync(dirname(link), { recursive: true });
    // `junction` vale no Windows sem privilégio de administrador; nos outros
    // sistemas o tipo é ignorado e sai um link simbólico.
    symlinkSync(destination, link, 'junction');
  }
  for (const a of baseFiles) {
    const origin = join(root, a);
    if (!existsSync(origin)) continue;
    const copy = join(tree, a);
    mkdirSync(dirname(copy), { recursive: true });
    copyFileSync(origin, copy);
  }

  const end = flagValue(args, '--fim-dos-dados');
  // A credencial da fonte de mercado vai pelo ambiente do processo, e não por
  // cópia do `.env`: segredo não se espalha em pasta temporária.
  const token = fromEnv(join(root, '.env'), 'BRAPI_TOKEN');
  const env = { ...process.env, ...(token === null ? {} : { BRAPI_TOKEN: token }) };
  const backtestArgs = ['--montagem', 'aplicativo', '--com-deslistadas', '--trimestral', '--c7', ...(end === null ? [] : ['--fim-dos-dados', end])];
  if (engineTree === dartTree) {
    run('flutter', ['pub', 'get'], tree);
    run('dart', ['run', 'tool/backtest_valuation.dart', ...backtestArgs], tree, env);
  } else {
    run('npm', ['ci'], tree);
    run('npm', ['run', 'tool', '--', 'backtest-valuation', ...backtestArgs], tree, env);
  }

  const rows = JSON.parse(readFileSync(join(tree, 'data/c7/coortes.json'), 'utf8')) as Record<string, unknown>[];
  const today = flagValue(args, '--hoje') ?? DateTime.now().toIso8601String().slice(0, 10);
  try {
    const r = await seal({ rows, engine: new Engine(preRegistered.fingerprint, commit), folder, today });
    outln(`== Série pré-registrada, pelo commit ${commit.slice(0, 7)} ==`);
    outln(`  seladas agora: ${r.sealedCohorts.length === 0 ? 'nenhuma' : r.sealedCohorts.join(', ')}`);
    outln(`  já seladas, conferidas: ${r.alreadySealed.length === 0 ? 'nenhuma' : r.alreadySealed.join(', ')}`);
    if (r.divergent.size === 0 && r.alreadySealed.length > 0) outln('  o selo se reproduz: nenhuma previsão refeita diverge');
    for (const [cohort, n] of r.divergent) {
      outln(`  ! ${cohort}: ${n} previsões refeitas divergem do selo — o selo não muda, e a divergência precisa de explicação`);
    }
  } catch (e) {
    if (!(e instanceof ProtocolViolated)) throw e;
    errln(e.toString());
    process.exit(1);
  }
  outln(`  worktree mantido em ${tree} — git worktree remove --force para apagar`);
}

/** O valor de [key] no arquivo `.env` em [path], ou `null`. */
function fromEnv(path: string, key: string): string | null {
  if (!existsSync(path)) return null;
  for (const row of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const t = row.trim();
    if (t === '' || t.startsWith('#')) continue;
    const i = t.indexOf('=');
    if (i <= 0 || t.slice(0, i).trim() !== key) continue;
    const v = t.slice(i + 1).trim();
    return v === '' ? null : v;
  }
  return null;
}

/**
 * Roda um programa com as duas saídas ligadas às deste processo — o backtest
 * escreve o progresso no erro — e encerra se ele falhar.
 */
function run(exe: string, args: readonly string[], directory: string, env?: NodeJS.ProcessEnv): void {
  const p = spawnSync(exe, args, { cwd: directory, stdio: 'inherit', shell: process.platform === 'win32', env });
  if (p.status !== 0) {
    errln(`${exe} ${args.join(' ')} falhou (${p.status ?? p.error?.message}) em ${directory}`);
    process.exit(1);
  }
}
