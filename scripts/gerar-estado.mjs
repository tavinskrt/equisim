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
const DECISOES = join(ROOT, 'docs', 'decisoes');
const APONTAMENTOS = join(ROOT, 'docs', 'apontamentos');
const SAIDA = join(ROOT, 'docs', 'estado.md');

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
function lerFrontmatter(texto) {
  const m = texto.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) return null;

  const campos = {};
  const linhas = m[1].split(/\r?\n/);
  let chaveAtual = null;
  let modo = null; // 'lista' | 'bloco'

  for (const linha of linhas) {
    const item = linha.match(/^\s+-\s+(.*)$/);
    if (item && modo === 'lista' && chaveAtual) {
      campos[chaveAtual].push(item[1].trim());
      continue;
    }
    const continuacao = linha.match(/^\s{2,}(\S.*)$/);
    if (continuacao && modo === 'bloco' && chaveAtual) {
      campos[chaveAtual] = (campos[chaveAtual] + ' ' + continuacao[1]).trim();
      continue;
    }

    const par = linha.match(/^([a-z_]+):\s*(.*)$/i);
    if (!par) continue;
    const [, chave, valor] = par;
    chaveAtual = chave;

    if (valor === '' ) {
      campos[chave] = [];
      modo = 'lista';
    } else if (valor === '>' || valor === '|') {
      campos[chave] = '';
      modo = 'bloco';
    } else if (valor === '[]' || valor === '[ ]') {
      campos[chave] = [];
      modo = null;
    } else {
      campos[chave] = valor.trim();
      modo = null;
    }
  }
  return campos;
}

function lerDecisoes() {
  if (!existsSync(DECISOES)) return [];
  return readdirSync(DECISOES)
    .filter((f) => /^\d{3}-.*\.md$/.test(f))
    .sort()
    .map((arquivo) => {
      const campos = lerFrontmatter(readFileSync(join(DECISOES, arquivo), 'utf8'));
      if (!campos) return { arquivo, invalida: true };
      const afeta = Array.isArray(campos.afeta) ? campos.afeta : [];
      return {
        arquivo,
        numero: Number(campos.numero),
        titulo: campos.titulo ?? '(sem titulo)',
        status: campos.status ?? '(sem status)',
        origem: campos.origem ?? '(sem origem)',
        data: campos.data ?? '',
        afeta,
        // O unico teste que uma maquina consegue fazer sozinha: o caminho
        // existe? Se a decisao e RESPEITADA e semantico, e cabe a lente.
        quebrados: afeta.filter((p) => !existsSync(join(ROOT, p))),
      };
    });
}

function contarLinhas(caminhos, excluirSufixos = []) {
  const existentes = caminhos.filter((c) => existsSync(join(ROOT, c)));
  if (existentes.length === 0) return { arquivos: 0, linhas: 0 };
  const lista = git(['ls-files', '--', ...existentes])
    .split('\n')
    .filter((f) => f !== '' && !excluirSufixos.some((s) => f.endsWith(s)));
  let linhas = 0;
  for (const f of lista) {
    linhas += readFileSync(join(ROOT, f), 'utf8').split('\n').length;
  }
  return { arquivos: lista.length, linhas };
}

const GERADOS = ['.g.dart', '.freezed.dart', '.mocks.dart'];

const SUPERFICIE = [
  ['Nucleo de dominio', ['packages/equisim_core/lib']],
  ['Apresentacao', ['lib/presentation', 'lib/views', 'lib/controllers']],
  ['Camada de dados', ['lib/data']],
  ['Testes do app', ['test']],
  ['Testes do nucleo', ['packages/equisim_core/test']],
  ['Ferramentas de QA', ['scripts']],
];

function gerar() {
  const decisoes = lerDecisoes();
  const apontamentos = existsSync(APONTAMENTOS)
    ? readdirSync(APONTAMENTOS).filter((f) => f.endsWith('.md') && f !== 'README.md')
    : [];

  const commit = git(['rev-parse', '--short', 'HEAD']);
  const agora = new Date().toISOString().slice(0, 10);

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
  L.push(`Gerado em ${agora}, a partir de \`${commit}\`.`);
  L.push('');

  // --- Decisões -----------------------------------------------------------
  L.push('## Decisões registradas');
  L.push('');
  if (decisoes.length === 0) {
    L.push('Nenhuma decisão registrada em `docs/decisoes/`.');
    L.push('');
    L.push('Isso não significa que o projeto não tenha decisões — significa que');
    L.push('elas ainda vivem em prosa dentro do parecer, que é exatamente a');
    L.push('condição que a lente `registro` do conselheiro existe para corrigir.');
  } else {
    const porStatus = {};
    for (const d of decisoes) {
      porStatus[d.status] = (porStatus[d.status] ?? 0) + 1;
    }
    L.push(
      Object.entries(porStatus)
        .map(([s, n]) => `**${n}** ${s}`)
        .join(' · '),
    );
    L.push('');
    L.push('| # | Título | Status | Origem | Data |');
    L.push('|---|---|---|---|---|');
    for (const d of decisoes) {
      L.push(`| ${d.numero} | ${d.titulo} | ${d.status} | ${d.origem} | ${d.data} |`);
    }

    const comQuebra = decisoes.filter((d) => d.quebrados?.length > 0);
    if (comQuebra.length > 0) {
      L.push('');
      L.push('### Referências quebradas');
      L.push('');
      L.push('Decisões cujo `afeta` aponta para caminho que não existe mais.');
      L.push('');
      for (const d of comQuebra) {
        for (const p of d.quebrados) {
          L.push(`- decisão ${d.numero} → \`${p}\``);
        }
      }
    }
  }
  L.push('');

  // --- Caixa de entrada ---------------------------------------------------
  L.push('## Caixa de entrada');
  L.push('');
  L.push(
    apontamentos.length === 0
      ? 'Vazia.'
      : `${apontamentos.length} apontamento(s) não convertidos em decisão:\n\n` +
          apontamentos.map((a) => `- \`${a}\``).join('\n'),
  );
  L.push('');

  // --- Superfície ---------------------------------------------------------
  L.push('## Superfície medida');
  L.push('');
  L.push('Linhas versionadas, excluindo artefatos gerados.');
  L.push('');
  L.push('| Domínio | Arquivos | Linhas |');
  L.push('|---|---:|---:|');
  for (const [nome, caminhos] of SUPERFICIE) {
    const { arquivos, linhas } = contarLinhas(caminhos, GERADOS);
    L.push(`| ${nome} | ${arquivos} | ${linhas.toLocaleString('pt-BR')} |`);
  }
  L.push('');

  // --- História -----------------------------------------------------------
  L.push('## Histórico recente');
  L.push('');
  L.push('```');
  L.push(git(['log', '-15', '--format=%ad  %h  %s', '--date=short']));
  L.push('```');
  L.push('');

  writeFileSync(SAIDA, L.join('\n'), 'utf8');
  process.stdout.write(
    `docs/estado.md gerado -- ${decisoes.length} decisao(oes), ` +
      `${apontamentos.length} apontamento(s).\n`,
  );
}

gerar();
