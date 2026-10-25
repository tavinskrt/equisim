/**
 * Gera `docs/estado.md` a partir do REPOSITORIO.
 *
 *     node scripts/gerar-estado.mjs
 *
 * Este arquivo existe por causa de um defeito especifico e ja observado: o
 * `PLANO_ARQUITETURA.md` mantinha o estado das fases a mao, com marcadores
 * "CONCLUIDA (19/08/2026)" e itens "- [x]". Nove commits depois, ele nao sabia
 * que as quatro Ondas de refatoracao de UI existiam. Estado escrito a mao
 * apodrece porque muda a cada commit e ninguem reescreve documento a cada
 * commit.
 *
 * A saida e DERIVADA, nunca redigida. Se um numero aqui esta errado, o conserto
 * e neste script -- editar `docs/estado.md` a mao seria recriar exatamente o
 * problema que ele resolve. Por isso o arquivo gerado abre com um aviso.
 *
 * POR QUE .mjs E NAO .ts: roda com `node` puro, sem passar pelo `tsx`. Nao ha
 * tipo interessante a declarar aqui, e a partida instantanea importa se um dia
 * isto entrar num hook para manter o arquivo fresco.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const DECISIONS = join(ROOT, 'docs', 'decisoes');
const REMARKS = join(ROOT, 'docs', 'apontamentos');
const OUTPUT = join(ROOT, 'docs', 'estado.md');

function git(args) {
  return execFileSync('git', args, {
    cwd: ROOT,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  }).trim();
}

/**
 * Leitor de frontmatter suficiente para o formato de `docs/decisoes/`.
 *
 * NAO e um parser de YAML, e nao pretende ser: entende escalar, bloco dobrado
 * (`>`) e lista de `- `. Um formato que exigisse mais que isso ja seria formato
 * demais para um registro que precisa ser escrito a mao sob pressao.
 */
function readFrontmatter(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) return null;

  const fields = {};
  const lines = m[1].split(/\r?\n/);
  let currentKey = null;
  let mode = null; // 'lista' | 'bloco'

  for (const line of lines) {
    const item = line.match(/^\s+-\s+(.*)$/);
    if (item && mode === 'lista' && currentKey) {
      fields[currentKey].push(item[1].trim());
      continue;
    }
    const continuation = line.match(/^\s{2,}(\S.*)$/);
    if (continuation && mode === 'bloco' && currentKey) {
      fields[currentKey] = (fields[currentKey] + ' ' + continuation[1]).trim();
      continue;
    }

    const pair = line.match(/^([a-z_]+):\s*(.*)$/i);
    if (!pair) continue;
    const [, key, value] = pair;
    currentKey = key;

    if (value === '' ) {
      fields[key] = [];
      mode = 'lista';
    } else if (value === '>' || value === '|') {
      fields[key] = '';
      mode = 'bloco';
    } else if (value === '[]' || value === '[ ]') {
      fields[key] = [];
      mode = null;
    } else {
      fields[key] = value.trim();
      mode = null;
    }
  }
  return fields;
}

function readDecisions() {
  if (!existsSync(DECISIONS)) return [];
  const parsed = readdirSync(DECISIONS)
    .filter((f) => /^\d{3}-.*\.md$/.test(f))
    .sort()
    .map((file) => ({
      file,
      fields: readFrontmatter(readFileSync(join(DECISIONS, file), 'utf8')),
    }));
  // **Caminho retirado não é caminho quebrado.** Decisão aceita não se edita,
  // e a que apaga um documento declara isso em `retira`: quem o tinha em
  // `afeta` perde esse objeto sem ser tocada, e o caminho sai da lista de
  // quebrados para a de retirados, com a decisão que o apagou.
  const retired = new Map();
  for (const { fields } of parsed) {
    if (!fields || !Array.isArray(fields.retira)) continue;
    for (const p of fields.retira) retired.set(p, Number(fields.numero));
  }
  return parsed.map(({ file, fields }) => {
      if (!fields) return { file, invalid: true };
      const affects = Array.isArray(fields.afeta) ? fields.afeta : [];
      const supersedes = (Array.isArray(fields.substitui) ? fields.substitui : [])
        .map(Number)
        .filter((n) => Number.isFinite(n));
      return {
        file,
        number: Number(fields.numero),
        title: fields.titulo ?? '(sem titulo)',
        status: fields.status ?? '(sem status)',
        origin: fields.origem ?? '(sem origem)',
        date: fields.data ?? '',
        affects,
        supersedes,
        // O unico teste que uma maquina consegue fazer sozinha: o caminho
        // existe? Se a decisao e RESPEITADA e semantico, e cabe a lente.
        broken: affects.filter(
          (p) => !existsSync(join(ROOT, p)) && !retired.has(p),
        ),
        retired: affects
          .filter((p) => !existsSync(join(ROOT, p)) && retired.has(p))
          .map((p) => ({ path: p, retiredBy: retired.get(p) })),
      };
    });
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
  const decisions = readDecisions();
  const remarks = existsSync(REMARKS)
    ? readdirSync(REMARKS).filter((f) => f.endsWith('.md') && f !== 'README.md')
    : [];

  const commit = git(['rev-parse', '--short', 'HEAD']);
  const now = new Date().toISOString().slice(0, 10);

  const L = [];
  L.push('# Estado do projeto');
  L.push('');
  L.push('> **Arquivo gerado. Não edite à mão.**');
  L.push('>');
  L.push('> Regenere com `node scripts/gerar-estado.mjs`. Se um número aqui está');
  L.push('> errado, o conserto é no script — editar este arquivo recria o');
  L.push('> problema que ele existe para resolver: estado escrito à mão apodrece');
  L.push('> porque muda a cada commit.');
  L.push('');
  L.push(`Gerado em ${now}, a partir de \`${commit}\`.`);
  L.push('');

  // --- Decisões -----------------------------------------------------------
  L.push('## Decisões registradas');
  L.push('');
  if (decisions.length === 0) {
    L.push('Nenhuma decisão registrada em `docs/decisoes/`.');
    L.push('');
    L.push('Isso não significa que o projeto não tenha decisões — significa que');
    L.push('elas ainda vivem em prosa dentro do parecer, que é exatamente a');
    L.push('condição que a lente `registro` do conselheiro existe para corrigir.');
  } else {
    const superseded = new Set();
    for (const d of decisions) {
      for (const target of d.supersedes ?? []) superseded.add(target);
    }
    const byStatus = {};
    for (const d of decisions) {
      const key = superseded.has(d.number) ? 'substituída' : d.status;
      byStatus[key] = (byStatus[key] ?? 0) + 1;
    }
    L.push(
      Object.entries(byStatus)
        .map(([s, n]) => `**${n}** ${s}`)
        .join(' · '),
    );
    L.push('');
    // **Quem foi substituído tem de aparecer substituído.** O campo
    // `substitui` mora em quem substitui, e a tabela mostrava só o `status` de
    // cada decisão — de modo que a 39, substituída pela 102, continuava
    // constando como `aceita`. Quem lesse o estado — pessoa ou lente — via
    // decisão morta como viva, e a lente `rumo` reabriu o mesmo item duas
    // rodadas seguidas por causa disto.
    const supersededBy = new Map();
    for (const d of decisions) {
      for (const target of d.supersedes ?? []) {
        const list = supersededBy.get(target) ?? [];
        list.push(d.number);
        supersededBy.set(target, list);
      }
    }

    L.push('| # | Título | Status | Origem | Data |');
    L.push('|---|---|---|---|---|');
    for (const d of decisions) {
      const supersedingList = supersededBy.get(d.number);
      const status = supersedingList
        ? `substituída pela ${supersedingList.sort((a, b) => a - b).join(', ')}`
        : d.status;
      L.push(`| ${d.number} | ${d.title} | ${status} | ${d.origin} | ${d.date} |`);
    }

    const withRetired = decisions.filter((d) => d.retired?.length > 0);
    if (withRetired.length > 0) {
      L.push('');
      L.push('### Caminhos retirados');
      L.push('');
      L.push(
        'Decisões cujo `afeta` cita caminho que uma decisão posterior apagou ' +
          '(campo `retira`). A decisão antiga não se edita; perdeu esse objeto.',
      );
      L.push('');
      for (const d of withRetired) {
        for (const r of d.retired) {
          L.push(`- decisão ${d.number} → \`${r.path}\`, retirado pela ${r.retiredBy}`);
        }
      }
    }

    const withBreak = decisions.filter((d) => d.broken?.length > 0);
    if (withBreak.length > 0) {
      L.push('');
      L.push('### Referências quebradas');
      L.push('');
      L.push('Decisões cujo `afeta` aponta para caminho que não existe mais.');
      L.push('');
      for (const d of withBreak) {
        for (const p of d.broken) {
          L.push(`- decisão ${d.number} → \`${p}\``);
        }
      }
    }
  }
  L.push('');

  // --- Caixa de entrada ---------------------------------------------------
  L.push('## Caixa de entrada');
  L.push('');
  L.push(
    remarks.length === 0
      ? 'Vazia.'
      : `${remarks.length} apontamento(s) não convertidos em decisão:\n\n` +
          remarks.map((a) => `- \`${a}\``).join('\n'),
  );
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
  process.stdout.write(
    `docs/estado.md gerado -- ${decisions.length} decisao(oes), ` +
      `${remarks.length} apontamento(s).\n`,
  );
}

generate();
