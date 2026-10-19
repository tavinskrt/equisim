/**
 * Coleta do material de uma lente.
 *
 * Generico de proposito: uma lente descreve o que quer por descritores (ver
 * `lentes.ts`) e este modulo os interpreta. Acrescentar lente nao deve exigir
 * escrever coletor novo -- se exigir, o conjunto de descritores e que esta
 * incompleto.
 *
 * DUAS DIFERENCAS DELIBERADAS EM RELACAO AO COLETOR DO AUDITOR:
 *
 * 1. NAO ha numeracao de linha. O auditor a injeta porque seu contrato exige
 *    `arquivo:linha` em todo achado. O conselheiro cita `subject` e copia
 *    `evidence`; numero de linha nao entra no contrato dele, e numerar so
 *    gastaria token em payload que ja e grande.
 *
 * 2. O teto e maior. Ver `MAX_PAYLOAD_CHARS` abaixo.
 *
 * A listagem sai de `git ls-files`, nao de varredura do sistema de arquivos:
 * assim `build/`, `node_modules/` e o resto do `.gitignore` ficam de fora sem
 * lista de exclusao propria, e o que o modelo ve e o que o repositorio versiona.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import type { Lens, Material } from './lentes.ts';

/**
 * Teto de payload -- quase tres vezes o do auditor.
 *
 * A diferenca e de natureza, nao de generosidade. O auditor examina um diff:
 * cortar arquivo que ele nao ia ler mesmo nao muda o veredito. O conselheiro
 * examina COESAO de um dominio inteiro, e um dominio pela metade produz
 * conclusao errada com cara de certa -- ele diria que falta um tipo que existe
 * no arquivo que nao coube.
 *
 * Por isso o corte tambem grita: ver `TRUNCATION_NOTICE`.
 */
export const MAX_PAYLOAD_CHARS = 500_000;

/** O material de uma lente, montado e pronto para o provider. */
export interface AdvisorTarget {
  lens: Lens;
  /** Descricao legivel da origem, para o cabecalho do relatorio. */
  label: string;
  /** Texto enviado ao modelo. */
  payload: string;
  /** Arquivos efetivamente incluidos. */
  files: string[];
  /** `true` quando o payload bateu no teto e foi cortado por arquivo inteiro. */
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
 * Lista os arquivos sob os caminhos dados: os versionados **e os novos que o
 * `.gitignore` nao exclui**.
 *
 * So os versionados, como era, deixava a lente cega para o que a rodada acabou
 * de escrever: em 24/09/2026 as decisoes 131 a 134, os testes novos e o
 * `tool/c7/` nao chegaram a lente nenhuma, porque ainda nao tinham commit -- e
 * o conselheiro roda justamente antes do commit. O `.gitignore` continua
 * barrando `data/`, `.env*` e o resto que nao e do projeto.
 */
function listFiles(root: string, filePaths: string[]): string[] {
  const existing = filePaths.filter((c) => existsSync(join(root, c)));
  if (existing.length === 0) return [];
  // O indice ainda lista o arquivo apagado e nao commitado; a lente o leria
  // como presente (28/09/2026: `docs/refinamento-do-valuation.md`, retirado
  // pela decisao 141, voltou como "nao foi apagado"). So o que existe no disco.
  return git(['ls-files', '--cached', '--others', '--exclude-standard', '--', ...existing], root)
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '' && existsSync(join(root, l)));
}

/**
 * O arquivo casa com algum dos padroes de exclusao?
 *
 * Os padroes em uso sao todos da forma `*.sufixo`, entao sufixo basta. Um
 * glob completo aqui seria maquinaria para um caso que nao existe.
 */
function isExcluded(file: string, patterns: string[]): boolean {
  return patterns.some((p) =>
    p.startsWith('*') ? file.endsWith(p.slice(1)) : file === p,
  );
}

/** Um bloco de material, ja rotulado. */
interface Block {
  /** Caminho ou rotulo, para a lista de `files`. */
  origin: string;
  text: string;
}

function fileBlock(root: string, filePath: string): Block | null {
  const absolute = join(root, filePath);
  if (!existsSync(absolute)) return null;
  const content = readFileSync(absolute, 'utf8');
  return {
    origin: filePath,
    text: `===== ARQUIVO: ${filePath} =====\n${content}\n`,
  };
}

function materialBlocks(root: string, material: Material): Block[] {
  switch (material.kind) {
    case 'arquivo': {
      const block = fileBlock(root, material.filePath);
      if (!block) {
        if (material.optional) return [];
        throw new Error(
          `Material obrigatorio ausente: ${material.filePath}\n` +
            'Corrija o descritor da lente ou crie o arquivo.',
        );
      }
      return [block];
    }

    case 'diretorio': {
      if (!existsSync(join(root, material.filePath))) {
        if (material.optional) return [];
        throw new Error(`Diretorio obrigatorio ausente: ${material.filePath}`);
      }
      const extensions = material.extensions;
      const exclude = material.exclude ?? [];
      const files = listFiles(root, [material.filePath])
        .filter((f) => !extensions || extensions.some((e) => f.endsWith(e)))
        .filter((f) => !isExcluded(f, exclude))
        .sort();
      if (material.newestFirst) files.reverse();
      return files
        .map((f) => fileBlock(root, f))
        .filter((b): b is Block => b !== null);
    }

    case 'arvore-completa': {
      const exclude = material.excludePrefixes ?? [];
      // Os novos que o `.gitignore` nao exclui tambem: a arvore que a lente
      // `registro` confronta com o registro e a do commit que vem, e nao a do
      // ultimo (ver [listFiles]).
      // Tambem so o que existe no disco: o apagado e nao commitado ainda esta
      // no indice (ver [listFiles]).
      const files = git(['ls-files', '--cached', '--others', '--exclude-standard'], root)
        .split('\n')
        .map((l) => l.trim())
        .filter(
          (l) =>
            l !== '' &&
            !exclude.some((p) => l.startsWith(p)) &&
            existsSync(join(root, l)),
        );
      return [
        {
          origin: '(arvore completa do repositorio)',
          text:
            '===== ARVORE COMPLETA DO REPOSITORIO =====\n' +
            'TODOS os arquivos versionados' +
            (exclude.length > 0
              ? `, exceto os diretorios de plataforma (${exclude.join(' ')}),\n` +
                'que o `flutter create` gera e ninguem edita a mao.\n'
              : '.\n') +
            'Esta lista e COMPLETA no escopo declarado: se um caminho nao esta\n' +
            'aqui, ele nao esta no repositorio. O conteudo dos arquivos nao foi\n' +
            'enviado, salvo os que aparecem em bloco proprio.\n\n' +
            files.join('\n') +
            '\n',
        },
      ];
    }

    case 'arvore': {
      const files = listFiles(root, material.roots);
      return [
        {
          origin: `(arvore de ${material.roots.join(', ')})`,
          text:
            `===== ARVORE DE ARQUIVOS: ${material.roots.join(', ')} =====\n` +
            'Somente os caminhos. O conteudo destes arquivos NAO foi enviado,\n' +
            'salvo quando aparecer em bloco proprio mais abaixo.\n\n' +
            files.join('\n') +
            '\n',
        },
      ];
    }

    case 'alterados': {
      // O que a rodada mexeu: o modificado contra o ultimo commit e o novo que
      // o `.gitignore` nao exclui. Vem antes do resto na lente que o pede,
      // porque o corte e na ordem dos blocos -- ver [collectLens].
      const existing = material.roots.filter((c) => existsSync(join(root, c)));
      if (existing.length === 0) return [];
      const modified = git(['diff', '--name-only', 'HEAD', '--', ...existing], root);
      const added = git(
        ['ls-files', '--others', '--exclude-standard', '--', ...existing],
        root,
      );
      const extensions = material.extensions;
      const exclude = material.exclude ?? [];
      const files = [...new Set([...modified.split('\n'), ...added.split('\n')])]
        .map((l) => l.trim())
        .filter((l) => l !== '' && existsSync(join(root, l)))
        .filter((f) => !extensions || extensions.some((e) => f.endsWith(e)))
        .filter((f) => !isExcluded(f, exclude))
        .sort();
      return files
        .map((f) => fileBlock(root, f))
        .filter((b): b is Block => b !== null);
    }

    case 'git-log': {
      const log = git(
        [
          'log',
          `-${material.count}`,
          '--format=%ad  %h  %s',
          '--date=short',
        ],
        root,
      );
      return [
        {
          origin: `(git log, ${material.count} commits)`,
          text: `===== HISTORICO RECENTE =====\n${log}\n`,
        },
      ];
    }
  }
}

const TRUNCATION_NOTICE = [
  '',
  '!!! ATENCAO -- MATERIAL INCOMPLETO !!!',
  '',
  'O payload bateu no teto de tamanho e foi cortado. Os arquivos listados',
  'abaixo NAO foram enviados. Voce esta vendo o dominio pela metade.',
  '',
  'Consequencia direta para a sua resposta: NAO conclua que algo esta ausente',
  'do projeto. Ausencia do material nao e ausencia do repositorio. Se uma',
  'tensao dependeria de ver o que nao veio, nao a reporte.',
  '',
].join('\n');

/** Monta o material da lente. */
export function collectLens(root: string, lens: Lens): AdvisorTarget {
  const blocks: Block[] = [];
  for (const material of lens.materials) {
    blocks.push(...materialBlocks(root, material));
  }

  const included: string[] = [];
  const omitted: string[] = [];
  let payload = '';
  // Um arquivo que dois descritores pedem -- o alterado e o diretorio dele --
  // vai uma vez so, na posicao do primeiro.
  const seen = new Set<string>();

  for (const block of blocks) {
    if (seen.has(block.origin)) continue;
    seen.add(block.origin);
    // O corte e por bloco INTEIRO, nunca no meio de um: arquivo pela metade
    // faria o modelo apontar tensao em codigo que ele nao viu terminar.
    if (payload.length + block.text.length > MAX_PAYLOAD_CHARS) {
      omitted.push(block.origin);
      continue;
    }
    payload += block.text + '\n';
    included.push(block.origin);
  }

  if (omitted.length > 0) {
    payload += TRUNCATION_NOTICE + omitted.map((o) => `  - ${o}`).join('\n') + '\n';
  }

  return {
    lens,
    label: `lente ${lens.id} -- ${included.length} bloco(s)`,
    payload,
    files: included,
    truncated: omitted.length > 0,
  };
}
