/**
 * Fila de auditorias pendentes por cota.
 *
 * O problema que ela resolve: quando a cota acaba, o gate nao pode bloquear o
 * trabalho -- ficar sem cota nao e defeito do codigo. Mas simplesmente liberar
 * e esquecer perderia a auditoria para sempre, e o commit entraria no historico
 * sem nunca ter sido olhado. A fila e o meio-termo: libera agora, audita depois.
 *
 * DECISAO DE PROJETO: a fila guarda o PAYLOAD INTEIRO, nao o intervalo de
 * commits. Guardar "HEAD~1..HEAD" seria menor e estaria errado -- ao drenar a
 * fila tres commits depois, `HEAD` ja e outro e a auditoria examinaria codigo
 * diferente do que foi liberado. Pior: auditoria de arvore de trabalho inclui
 * arquivo nao rastreado, que nao existe em commit algum e seria irrecuperavel.
 * O instantaneo custa disco e garante que o que foi liberado e o que sera
 * auditado.
 */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

/** Diretorio da fila, na raiz do repositorio. Ignorado pelo git. */
export const PENDING_DIR = '.qa-pending';

/**
 * Metadados de uma auditoria enfileirada.
 *
 * A fila guarda o **instantaneo** do que foi liberado, nao o intervalo de
 * commits: drenar tres commits depois audita o mesmo codigo que passou, e nao
 * o `HEAD` atual.
 */
export interface PendingEntry {
  /** Hash do payload: dedupe natural, e nome do arquivo do instantaneo. */
  id: string;
  /** Momento do enfileiramento, em ISO-8601. Ordena a fila. */
  queuedAt: string;
  /** Rotulo legivel do alvo, como aparecia no relatorio. */
  label: string;
  /** Modo do alvo, que decide a calibragem quando a fila for drenada. */
  mode: 'diff' | 'file' | 'screenshot';
  /** Arquivos que compunham o alvo. */
  files: string[];
  /** Commit em que a auditoria foi adiada -- so para diagnostico. */
  head: string;
  /** Por que ficou pendente. Hoje sempre cota; o campo antecipa outros casos. */
  reason: string;
}

interface StoredEntry extends PendingEntry {
  payload: string;
  instructions: string;
}

function dir(root: string): string {
  return join(root, PENDING_DIR);
}

function hashOf(payload: string): string {
  return createHash('sha256').update(payload, 'utf8').digest('hex').slice(0, 16);
}

/**
 * Enfileira uma auditoria adiada.
 *
 * Devolve `false` quando o mesmo payload ja estava na fila: o dedupe e por
 * conteudo, entao tentar de novo sem mudar nada nao acumula entradas.
 */
export function enqueue(
  root: string,
  entry: Omit<PendingEntry, 'id' | 'queuedAt'>,
  payload: string,
  instructions: string,
): { queued: boolean; id: string } {
  const id = hashOf(payload);
  const path = join(dir(root), `${id}.json`);
  if (existsSync(path)) return { queued: false, id };

  mkdirSync(dir(root), { recursive: true });
  const stored: StoredEntry = {
    ...entry,
    id,
    queuedAt: new Date().toISOString(),
    payload,
    instructions,
  };
  writeFileSync(path, JSON.stringify(stored, null, 2), 'utf8');
  return { queued: true, id };
}

/**
 * Lista a fila, do mais antigo para o mais recente.
 *
 * @param root Raiz do repositorio.
 * @returns Apenas os metadados -- payload e instrucoes ficam de fora, para que
 *   listar a fila nao carregue centenas de KB por entrada.
 *
 * **Nunca lanca.** Fila inexistente devolve vazio, e entrada corrompida e
 * pulada em silencio: um JSON truncado nao pode derrubar a listagem inteira,
 * que e justamente como o usuario descobre o que ficou pendente.
 */
export function listPending(root: string): PendingEntry[] {
  const d = dir(root);
  if (!existsSync(d)) return [];
  const out: PendingEntry[] = [];
  for (const file of readdirSync(d)) {
    if (!file.endsWith('.json')) continue;
    try {
      const stored = JSON.parse(
        readFileSync(join(d, file), 'utf8'),
      ) as StoredEntry;
      const { payload: _p, instructions: _i, ...meta } = stored;
      out.push(meta);
    } catch {
      // Entrada corrompida nao pode derrubar a listagem inteira.
    }
  }
  return out.sort((a, b) => a.queuedAt.localeCompare(b.queuedAt));
}

/**
 * Carrega uma entrada completa da fila, com payload e instrucoes.
 *
 * @param root Raiz do repositorio.
 * @param id Hash do payload, como aparece em `listPending`.
 * @returns A entrada, ou `undefined` se o arquivo nao existir.
 * @throws Se o arquivo existir mas nao for JSON valido. Ao contrario de
 *   `listPending`, aqui a corrupcao **e** fatal: nao ha como auditar um
 *   instantaneo ilegivel, e mascarar isso auditaria o alvo errado.
 */
export function loadPending(
  root: string,
  id: string,
): { payload: string; instructions: string; meta: PendingEntry } | undefined {
  const path = join(dir(root), `${id}.json`);
  if (!existsSync(path)) return undefined;
  const stored = JSON.parse(readFileSync(path, 'utf8')) as StoredEntry;
  const { payload, instructions, ...meta } = stored;
  return { payload, instructions, meta };
}

/**
 * Remove uma entrada da fila.
 *
 * Chamado quando a auditoria foi CONCLUIDA, tenha ela aprovado ou reprovado --
 * nos dois casos o codigo deixou de estar sem auditoria, que e o que a fila
 * rastreia. Um FAIL drenado vira relatorio na tela, nao entrada eterna.
 */
export function dequeue(root: string, id: string): void {
  const path = join(dir(root), `${id}.json`);
  if (existsSync(path)) rmSync(path);
}

/** Quantas auditorias esperam. Usado para avisar no fim de outras execucoes. */
export function pendingCount(root: string): number {
  return listPending(root).length;
}
