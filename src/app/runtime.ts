import type { AuthGateway } from './auth';
import type { Services, UserStores } from './services';

/**
 * O que o aplicativo montou na partida: a raiz de dependências, a porta da
 * autenticação e os dois lugares de gravação.
 *
 * Os estados (Zustand) leem daqui na hora da ação, e não na criação: é o que
 * deixa o teste montar um ambiente falso antes de exercitar um estado.
 */
export interface Runtime {
  readonly services: Services;
  /** `null` em modo local — sem Firebase configurado, ou com ele fora do ar. */
  readonly auth: AuthGateway | null;
  /** Por que o Firebase não subiu, quando não subiu. */
  readonly authUnavailableReason: string | null;
  /** Estudos e valuations na conta; `null` sem Firebase. */
  readonly cloudStores: UserStores | null;
  /** Estudos e valuations neste navegador — o **modo local**. */
  readonly localStores: UserStores;
  /** Armazenamento das preferências por pessoa (tema, modo, rascunho). */
  readonly preferences: PreferenceStorage;
}

/** Preferências pequenas, por pessoa, que podem sumir sem prejuízo. */
export interface PreferenceStorage {
  get(key: string): string | null;
  set(key: string, value: string): void;
  remove(key: string): void;
}

/**
 * `localStorage` protegido: em janela privada, com dados de site bloqueados ou
 * em pré-visualização, o acesso lança — e aí a preferência simplesmente não
 * persiste, sem derrubar a tela.
 */
export const browserPreferences: PreferenceStorage = {
  get(key) {
    try {
      return globalThis.localStorage?.getItem(key) ?? null;
    } catch {
      return null;
    }
  },
  set(key, value) {
    try {
      globalThis.localStorage?.setItem(key, value);
    } catch {
      // Sem armazenamento, a preferência vale só nesta aba.
    }
  },
  remove(key) {
    try {
      globalThis.localStorage?.removeItem(key);
    } catch {
      // Idem.
    }
  },
};

/** Preferências em memória, para teste e para o Node. */
export function memoryPreferences(): PreferenceStorage {
  const map = new Map<string, string>();
  return {
    get: (k) => map.get(k) ?? null,
    set: (k, v) => void map.set(k, v),
    remove: (k) => void map.delete(k),
  };
}

let current: Runtime | null = null;

export function configureRuntime(runtime: Runtime): void {
  current = runtime;
}

export function getRuntime(): Runtime {
  if (current === null) throw new Error('O ambiente do aplicativo não foi montado (configureRuntime).');
  return current;
}

export function hasRuntime(): boolean {
  return current !== null;
}
