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

import type { Lente, Material } from './lentes.ts';

/**
 * Teto de payload -- quase tres vezes o do auditor.
 *
 * A diferenca e de natureza, nao de generosidade. O auditor examina um diff:
 * cortar arquivo que ele nao ia ler mesmo nao muda o veredito. O conselheiro
 * examina COESAO de um dominio inteiro, e um dominio pela metade produz
 * conclusao errada com cara de certa -- ele diria que falta um tipo que existe
 * no arquivo que nao coube.
 *
 * Por isso o corte tambem grita: ver `AVISO_TRUNCAGEM`.
 */
export const MAX_PAYLOAD_CHARS = 500_000;

/** O material de uma lente, montado e pronto para o provider. */
export interface AdvisorTarget {
  lente: Lente;
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

/** Lista os arquivos versionados sob os caminhos dados. */
function listar(root: string, caminhos: string[]): string[] {
  const existentes = caminhos.filter((c) => existsSync(join(root, c)));
  if (existentes.length === 0) return [];
  return git(['ls-files', '--', ...existentes], root)
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '');
}

/**
 * O arquivo casa com algum dos padroes de exclusao?
 *
 * Os padroes em uso sao todos da forma `*.sufixo`, entao sufixo basta. Um
 * glob completo aqui seria maquinaria para um caso que nao existe.
 */
function excluido(arquivo: string, padroes: string[]): boolean {
  return padroes.some((p) =>
    p.startsWith('*') ? arquivo.endsWith(p.slice(1)) : arquivo === p,
  );
}

/** Um bloco de material, ja rotulado. */
interface Bloco {
  /** Caminho ou rotulo, para a lista de `files`. */
  origem: string;
  texto: string;
}

function blocoDeArquivo(root: string, caminho: string): Bloco | null {
  const absoluto = join(root, caminho);
  if (!existsSync(absoluto)) return null;
  const conteudo = readFileSync(absoluto, 'utf8');
  return {
    origem: caminho,
    texto: `===== ARQUIVO: ${caminho} =====\n${conteudo}\n`,
  };
}

function blocosDeMaterial(root: string, material: Material): Bloco[] {
  switch (material.tipo) {
    case 'arquivo': {
      const bloco = blocoDeArquivo(root, material.caminho);
      if (!bloco) {
        if (material.opcional) return [];
        throw new Error(
          `Material obrigatorio ausente: ${material.caminho}\n` +
            'Corrija o descritor da lente ou crie o arquivo.',
        );
      }
      return [bloco];
    }

    case 'diretorio': {
      if (!existsSync(join(root, material.caminho))) {
        if (material.opcional) return [];
        throw new Error(`Diretorio obrigatorio ausente: ${material.caminho}`);
      }
      const extensoes = material.extensoes;
      const excluir = material.excluir ?? [];
      return listar(root, [material.caminho])
        .filter((f) => !extensoes || extensoes.some((e) => f.endsWith(e)))
        .filter((f) => !excluido(f, excluir))
        .map((f) => blocoDeArquivo(root, f))
        .filter((b): b is Bloco => b !== null);
    }

    case 'arvore-completa': {
      const excluir = material.excluirPrefixos ?? [];
      const arquivos = git(['ls-files'], root)
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => l !== '' && !excluir.some((p) => l.startsWith(p)));
      return [
        {
          origem: '(arvore completa do repositorio)',
          texto:
            '===== ARVORE COMPLETA DO REPOSITORIO =====\n' +
            'TODOS os arquivos versionados' +
            (excluir.length > 0
              ? `, exceto os diretorios de plataforma (${excluir.join(' ')}),\n` +
                'que o `flutter create` gera e ninguem edita a mao.\n'
              : '.\n') +
            'Esta lista e COMPLETA no escopo declarado: se um caminho nao esta\n' +
            'aqui, ele nao esta no repositorio. O conteudo dos arquivos nao foi\n' +
            'enviado, salvo os que aparecem em bloco proprio.\n\n' +
            arquivos.join('\n') +
            '\n',
        },
      ];
    }

    case 'arvore': {
      const arquivos = listar(root, material.raizes);
      return [
        {
          origem: `(arvore de ${material.raizes.join(', ')})`,
          texto:
            `===== ARVORE DE ARQUIVOS: ${material.raizes.join(', ')} =====\n` +
            'Somente os caminhos. O conteudo destes arquivos NAO foi enviado,\n' +
            'salvo quando aparecer em bloco proprio mais abaixo.\n\n' +
            arquivos.join('\n') +
            '\n',
        },
      ];
    }

    case 'git-log': {
      const log = git(
        [
          'log',
          `-${material.quantidade}`,
          '--format=%ad  %h  %s',
          '--date=short',
        ],
        root,
      );
      return [
        {
          origem: `(git log, ${material.quantidade} commits)`,
          texto: `===== HISTORICO RECENTE =====\n${log}\n`,
        },
      ];
    }
  }
}

const AVISO_TRUNCAGEM = [
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
export function collectLente(root: string, lente: Lente): AdvisorTarget {
  const blocos: Bloco[] = [];
  for (const material of lente.materiais) {
    blocos.push(...blocosDeMaterial(root, material));
  }

  const incluidos: string[] = [];
  const omitidos: string[] = [];
  let payload = '';

  for (const bloco of blocos) {
    // O corte e por bloco INTEIRO, nunca no meio de um: arquivo pela metade
    // faria o modelo apontar tensao em codigo que ele nao viu terminar.
    if (payload.length + bloco.texto.length > MAX_PAYLOAD_CHARS) {
      omitidos.push(bloco.origem);
      continue;
    }
    payload += bloco.texto + '\n';
    incluidos.push(bloco.origem);
  }

  if (omitidos.length > 0) {
    payload += AVISO_TRUNCAGEM + omitidos.map((o) => `  - ${o}`).join('\n') + '\n';
  }

  return {
    lente,
    label: `lente ${lente.id} -- ${incluidos.length} bloco(s)`,
    payload,
    files: incluidos,
    truncated: omitidos.length > 0,
  };
}
