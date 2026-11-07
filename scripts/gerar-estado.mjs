/**
 * Gera `docs/estado.md` a partir do REPOSITORIO.
 *
 *     node scripts/gerar-estado.mjs
 *
 * Estado escrito a mao apodrece: muda a cada commit, e ninguem reescreve
 * documento a cada commit. A saida aqui e DERIVADA, nunca redigida -- a versao
 * do `package.json`, as versoes do `CHANGELOG.md`, a superficie medida e o
 * historico do git. Se um numero aqui esta errado, o conserto e neste script, e
 * por isso o arquivo gerado abre com um aviso.
 *
 * POR QUE .mjs E NAO .ts: roda com `node` puro, sem passar pelo `tsx`. Nao ha
 * tipo interessante a declarar aqui, e a partida instantanea importa se um dia
 * isto entrar num hook para manter o arquivo fresco. Pelo mesmo motivo ele le o
 * `CHANGELOG.md` gerado, e nao importa `src/data/changelog.ts`.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const CHANGELOG = join(ROOT, 'CHANGELOG.md');
const PACKAGE = join(ROOT, 'package.json');
const OUTPUT = join(ROOT, 'docs', 'estado.md');

function git(args) {
  return execFileSync('git', args, {
    cwd: ROOT,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  }).trim();
}

/**
 * As versoes do `CHANGELOG.md`, na ordem em que aparecem (da mais recente para
 * a mais antiga): cabecalho `## [MAJOR.MINOR.PATCH] - AAAA-MM-DD`, seguido do
 * titulo em italico e das categorias `### ...` com os itens.
 */
function readReleases() {
  if (!existsSync(CHANGELOG)) return [];
  const releases = [];
  let current = null;
  for (const line of readFileSync(CHANGELOG, 'utf8').split(/\r?\n/)) {
    const head = /^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})$/.exec(line);
    if (head) {
      current = { version: head[1], date: head[2], title: '', items: 0 };
      releases.push(current);
      continue;
    }
    if (/^## /.test(line)) {
      current = null;
      continue;
    }
    if (current === null) continue;
    const title = /^_(.+)_$/.exec(line);
    if (title && current.title === '') current.title = title[1];
    else if (/^- /.test(line)) current.items += 1;
  }
  return releases;
}

function countLines(filePaths, excludeSuffixes = []) {
  const existing = filePaths.filter((c) => existsSync(join(ROOT, c)));
  if (existing.length === 0) return { files: 0, lines: 0 };
  const list = git(['ls-files', '--', ...existing])
    .split('\n')
    .filter((f) => f !== '' && !excludeSuffixes.some((s) => f.endsWith(s)))
    // `git ls-files` lista o INDICE, que nem sempre bate com o disco: um
    // arquivo renomeado no diretorio de trabalho e ainda nao encenado aparece
    // aqui com o nome antigo. Ler sem conferir derrubava o gerador inteiro por
    // um estado de trabalho perfeitamente normal -- aconteceu ao separar o
    // `golden_capture` da suite. Contar so o que existe e o comportamento
    // certo: este arquivo mede o repositorio, nao valida o indice.
    .filter((f) => existsSync(join(ROOT, f)));
  let lines = 0;
  for (const f of list) {
    lines += readFileSync(join(ROOT, f), 'utf8').split('\n').length;
  }
  return { files: list.length, lines };
}

// Saida de compilacao que acabe no indice nao conta como codigo do projeto.
const GENERATED = ['.d.ts', '.map'];

const SURFACE = [
  ['Nucleo de dominio', ['src/core']],
  ['Apresentacao', ['src/features', 'src/ui', 'src/app', 'src/copy', 'src/main.tsx', 'src/router.tsx', 'src/styles.css']],
  ['Camada de dados', ['src/data']],
  ['Auditoria', ['src/audit']],
  ['Ferramentas de medicao', ['tool']],
  ['Testes do app', ['test/app', 'test/audit', 'test/data', 'test/ui', 'test/tool']],
  ['Testes do nucleo', ['test/core', 'test/parity']],
  ['Ferramentas de QA', ['scripts']],
];

function generate() {
  const releases = readReleases();
  const version = JSON.parse(readFileSync(PACKAGE, 'utf8')).version;
  const commit = git(['rev-parse', '--short', 'HEAD']);
  const now = new Date().toISOString().slice(0, 10);

  const L = [];
  L.push('# Estado do projeto');
  L.push('');
  L.push('> **Arquivo gerado. Não edite à mão.**');
  L.push('>');
  L.push('> Regenere com `npm run estado`. Se um número aqui está errado, o');
  L.push('> conserto é no script — editar este arquivo recria o problema que ele');
  L.push('> existe para resolver: estado escrito à mão apodrece porque muda a');
  L.push('> cada commit.');
  L.push('');
  L.push(`Gerado em ${now}, a partir de \`${commit}\`.`);
  L.push('');

  // --- Versão -------------------------------------------------------------
  L.push('## Versão');
  L.push('');
  const latest = releases[0];
  L.push(`Versão do \`package.json\`: **${version}**.`);
  if (latest === undefined) {
    L.push('');
    L.push('O `CHANGELOG.md` não tem versão publicada. Regenere com `npm run changelog`.');
  } else if (latest.version !== version) {
    L.push('');
    L.push(
      `**Divergência:** a versão mais recente do \`CHANGELOG.md\` é ${latest.version}. ` +
        'As duas têm de ser a mesma (`test/data/changelog.test.ts` reprova).',
    );
  }
  L.push('');
  L.push('| Versão | Data | Tema | Itens |');
  L.push('|---|---|---|---:|');
  for (const r of releases) L.push(`| ${r.version} | ${r.date} | ${r.title} | ${r.items} |`);
  L.push('');

  // --- Superfície ---------------------------------------------------------
  L.push('## Superfície medida');
  L.push('');
  L.push('Linhas versionadas, excluindo artefatos gerados.');
  L.push('');
  L.push('| Domínio | Arquivos | Linhas |');
  L.push('|---|---:|---:|');
  for (const [name, filePaths] of SURFACE) {
    const { files, lines } = countLines(filePaths, GENERATED);
    L.push(`| ${name} | ${files} | ${lines.toLocaleString('pt-BR')} |`);
  }
  L.push('');

  // --- História -----------------------------------------------------------
  L.push('## Histórico recente');
  L.push('');
  L.push('```');
  L.push(git(['log', '-15', '--format=%ad  %h  %s', '--date=short']));
  L.push('```');
  L.push('');

  writeFileSync(OUTPUT, L.join('\n'), 'utf8');
  process.stdout.write(`docs/estado.md gerado -- versao ${version}, ${releases.length} versao(oes) no changelog.\n`);
}

generate();
