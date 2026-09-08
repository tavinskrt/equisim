/**
 * Coleta do material a ser auditado.
 *
 * Dois modos:
 *   --diff            unified diff (staged, ou contra um ref base)
 *   --file <caminho>  conteudo integral do arquivo, com numeracao de linha
 *
 * A numeracao de linha e deliberada: o modelo precisa citar `arquivo:linha`
 * para que o achado seja verificavel. Sem ela, os numeros vem alucinados.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { relative, resolve } from 'node:path';

/** Extensoes que o auditor entende. O resto e ruido. */
const AUDITABLE = [
  '*.dart',
  '*.ts',
  '*.tsx',
  '*.js',
  '*.mjs',
  '*.yaml',
  '*.yml',
  '*.json',
  '*.css',
  '*.html',
];

/**
 * Artefatos gerados ou volumosos. Auditar `*.g.dart` (saida do build_runner)
 * ou lockfiles so gasta token e produz achado falso -- ninguem edita isso a mao.
 */
const EXCLUDED = [
  ':(exclude)**/*.g.dart',
  ':(exclude)**/*.freezed.dart',
  ':(exclude)**/*.mocks.dart',
  ':(exclude)build/**',
  ':(exclude)**/node_modules/**',
  ':(exclude)pubspec.lock',
  ':(exclude)package-lock.json',
  ':(exclude).dart_tool/**',
  ':(exclude)lib/firebase_options.dart',
  // Dumps do executor de validacao. O `validacao_fora_da_amostra.json` tem
  // 162 KB e entrava no escopo por `*.json`: numa auditoria de diff ele
  // consumia a atencao do modelo inteira, e o veredito saiu descrevendo o dump
  // sem tocar no codigo que mudou junto. Nao e codigo de producao -- e saida
  // gerada por `dart run tool/validate.dart`.
  ':(exclude)docs/validacao/**',
];

/** Teto de payload. Acima disso o custo explode e a atencao do modelo dilui. */
export const MAX_PAYLOAD_CHARS = 180_000;

/** O material a auditar, ja montado e pronto para o provider. */
export interface AuditTarget {
  /**
   * `diff` muda a calibragem de severidade (ver rules.ts);
   * `screenshot` indica auditoria visual sem codigo anexado.
   */
  mode: 'diff' | 'file' | 'screenshot';
  /** Descricao legivel da origem, para o cabecalho do relatorio. */
  label: string;
  /** Texto enviado ao modelo. */
  payload: string;
  /** Arquivos efetivamente incluidos. */
  files: string[];
  /**
   * `true` quando o payload bateu em `MAX_PAYLOAD_CHARS` e foi cortado.
   *
   * O corte e por arquivo inteiro, nunca no meio de um: um arquivo pela metade
   * faria o modelo apontar defeito em codigo que ele nao viu terminar.
   */
  truncated: boolean;
}

function git(args: string[], cwd: string): string {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
}

/**
 * Raiz do repositorio que contem `startDir`.
 *
 * @param startDir Diretorio de partida, tipicamente `process.cwd()`.
 * @returns Caminho absoluto da raiz, sem quebra de linha.
 * @throws Se `startDir` nao estiver dentro de um repositorio git.
 */
export function repoRoot(startDir: string): string {
  return git(['rev-parse', '--show-toplevel'], startDir).trim();
}

/** Ref base utilizavel: HEAD~1 quando existe, senao a arvore vazia. */
function resolveBase(root: string, requested: string): string {
  try {
    git(['rev-parse', '--verify', `${requested}^{commit}`], root);
    return requested;
  } catch {
    // Repositorio com um unico commit: compara contra a arvore vazia.
    // Hash canonico do objeto tree vazio -- constante do git, valida em
    // qualquer plataforma (evita depender de /dev/null no Windows).
    return '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
  }
}

/** Como recortar o diff a auditar. */
export interface DiffOptions {
  /** Audita apenas o que esta em staging. Ignora `base` quando `true`. */
  staged: boolean;
  /** Ref base da comparacao. Cai para a arvore vazia se nao existir. */
  base: string;
  /** Linhas de contexto por trecho. Mais contexto ajuda o modelo a julgar. */
  contextLines: number;
}

/**
 * Monta o alvo a partir de um diff do git.
 *
 * Aplica a lista de caminhos auditaveis e a de exclusoes, de modo que arquivo
 * gerado, lock e configuracao de plataforma nunca cheguem ao modelo.
 *
 * @param root Raiz do repositorio.
 * @param opts Recorte desejado.
 * @returns Alvo em modo `diff` -- o que ativa a calibragem de severidade mais
 *   rigorosa do rulebook, em que so linha adicionada pode virar FAIL.
 * @throws Se o `git` falhar. Um `base` inexistente **nao** e erro: cai para o
 *   hash da arvore vazia, o que faz um repositorio de commit unico auditar
 *   tudo em vez de quebrar.
 */
export function collectDiff(root: string, opts: DiffOptions): AuditTarget {
  const pathspec = ['--', ...AUDITABLE, ...EXCLUDED];
  const common = [`--unified=${opts.contextLines}`, '--no-color', '--no-ext-diff'];

  let args: string[];
  let label: string;

  if (opts.staged) {
    args = ['diff', '--cached', ...common, ...pathspec];
    label = 'alteracoes em staging (git diff --cached)';
  } else {
    const base = resolveBase(root, opts.base);
    args = ['diff', ...common, base, ...pathspec];
    label = `alteracoes desde ${opts.base} (git diff ${opts.base})`;
  }

  let payload = git(args, root);
  const files = listChangedFiles(root, opts);

  // Arquivos novos entram apenas no modo working-tree. Em `--staged` seria
  // errado: eles nao estao no indice e nao fazem parte do commit em preparo.
  if (!opts.staged) {
    const untracked = untrackedPatch(root);
    if (untracked.files.length > 0) {
      payload += untracked.patch;
      files.push(...untracked.files);
      label += ` + ${untracked.files.length} arquivo(s) novo(s)`;
    }
  }

  const truncated = payload.length > MAX_PAYLOAD_CHARS;
  if (truncated) {
    payload =
      payload.slice(0, MAX_PAYLOAD_CHARS) +
      '\n\n[TRUNCADO: o diff excedeu o teto de payload. Audite arquivos ' +
      'individualmente com --file para cobertura completa.]\n';
  }

  return { mode: 'diff', label, payload, files, truncated };
}

/**
 * Arquivos novos ainda NAO rastreados pelo git.
 *
 * `git diff` nao os enxerga -- nem contra um ref, nem em staging. Sem este
 * tratamento, criar um arquivo e rodar a auditoria devolvia "APROVADO: nada
 * para auditar": um verde falso, o pior resultado possivel para um gate.
 *
 * Montamos o diff unificado a mao em vez de usar `git diff --no-index`, que
 * sai com codigo 1 quando ha diferenca e depende de `/dev/null` -- fragil no
 * Windows. O formato abaixo e o mesmo que o git emitiria para um arquivo novo,
 * com TODAS as linhas marcadas como adicionadas, que e a semantica correta.
 */
function untrackedPatch(root: string): { patch: string; files: string[] } {
  const pathspec = ['--', ...AUDITABLE, ...EXCLUDED];
  const files = git(
    ['ls-files', '--others', '--exclude-standard', ...pathspec],
    root,
  )
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l !== '');

  const chunks: string[] = [];
  for (const file of files) {
    let content: string;
    try {
      content = readFileSync(resolve(root, file), 'utf8');
    } catch {
      continue; // Arquivo sumiu entre o listing e a leitura.
    }
    const lines = content.split(/\r?\n/);
    // Um arquivo terminado em newline produz um ultimo elemento vazio que nao
    // corresponde a linha alguma.
    if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
    if (lines.length === 0) continue;

    chunks.push(
      `diff --git a/${file} b/${file}\n` +
        'new file mode 100644\n' +
        '--- /dev/null\n' +
        `+++ b/${file}\n` +
        `@@ -0,0 +1,${lines.length} @@\n` +
        lines.map((l) => `+${l}`).join('\n') +
        '\n',
    );
  }
  return { patch: chunks.join(''), files };
}

function listChangedFiles(root: string, opts: DiffOptions): string[] {
  const pathspec = ['--', ...AUDITABLE, ...EXCLUDED];
  const args = opts.staged
    ? ['diff', '--cached', '--name-only', ...pathspec]
    : ['diff', '--name-only', resolveBase(root, opts.base), ...pathspec];
  return git(args, root)
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l !== '');
}

/** Numera as linhas para que o modelo consiga citar `arquivo:linha`. */
function numberLines(content: string): string {
  const lines = content.split(/\r?\n/);
  const width = String(lines.length).length;
  return lines
    .map((line, i) => `${String(i + 1).padStart(width, ' ')} | ${line}`)
    .join('\n');
}

/**
 * Monta o alvo a partir de arquivos integrais.
 *
 * As linhas sao numeradas antes do envio, para que o modelo consiga citar
 * `arquivo:linha` -- sem isso os achados vem sem endereco.
 *
 * @param root Raiz do repositorio, base dos caminhos relativos.
 * @param paths Arquivos a incluir, na ordem em que devem entrar.
 * @returns Alvo em modo `file`, que usa a calibragem mais permissiva do
 *   rulebook, ja que nao ha "linha adicionada" a distinguir.
 * @throws Se algum caminho nao existir ou nao for arquivo. O teto de payload
 *   **nao** lanca: corta a lista e marca `truncated`.
 */
export function collectFiles(root: string, paths: string[]): AuditTarget {
  const chunks: string[] = [];
  const included: string[] = [];
  let total = 0;
  let truncated = false;

  for (const p of paths) {
    const abs = resolve(root, p);
    if (!existsSync(abs) || !statSync(abs).isFile()) {
      throw new Error(`Arquivo nao encontrado: ${p}`);
    }
    const rel = relative(root, abs).replace(/\\/g, '/');
    const body = numberLines(readFileSync(abs, 'utf8'));
    const chunk = `\n===== ARQUIVO: ${rel} =====\n${body}\n`;

    if (total + chunk.length > MAX_PAYLOAD_CHARS) {
      truncated = true;
      break;
    }
    chunks.push(chunk);
    included.push(rel);
    total += chunk.length;
  }

  return {
    mode: 'file',
    label:
      included.length === 1
        ? `arquivo ${included[0]}`
        : `${included.length} arquivos`,
    payload: chunks.join(''),
    files: included,
    truncated,
  };
}
