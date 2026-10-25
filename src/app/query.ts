import { useCallback, useEffect, useSyncExternalStore } from 'react';

/** O estado de uma consulta assíncrona, como a tela o lê. */
export type QueryState<T> =
  | { readonly status: 'pending'; readonly data: undefined; readonly error: undefined }
  | { readonly status: 'success'; readonly data: T; readonly error: undefined }
  | { readonly status: 'error'; readonly data: undefined; readonly error: unknown };

const pending: QueryState<never> = Object.freeze({ status: 'pending', data: undefined, error: undefined });

interface Entry {
  state: QueryState<unknown>;
  promise: Promise<unknown> | null;
  readonly listeners: Set<() => void>;
}

/**
 * Cache de consultas assíncronas por chave.
 *
 * Existe porque a mesma avaliação é lida por várias telas — o Raio-X, a linha
 * da carteira, o retorno esperado — e cada uma pedir a sua repetiria a conta
 * e o evento no painel de logs. Aqui a primeira leitura vale para todas, até
 * alguém invalidar a chave.
 *
 * É pequeno de propósito: dedupe, assinatura e invalidação por prefixo, sobre
 * `useSyncExternalStore` do React — sem dependência nova.
 */
export class QueryClient {
  private readonly entries = new Map<string, Entry>();

  private entry(key: string): Entry {
    let e = this.entries.get(key);
    if (e === undefined) {
      e = { state: pending, promise: null, listeners: new Set() };
      this.entries.set(key, e);
    }
    return e;
  }

  /** O estado atual da chave. Estável entre chamadas enquanto nada muda. */
  stateOf<T>(key: string): QueryState<T> {
    return this.entry(key).state as QueryState<T>;
  }

  subscribe(key: string, listener: () => void): () => void {
    const e = this.entry(key);
    e.listeners.add(listener);
    return () => e.listeners.delete(listener);
  }

  /**
   * Busca a chave se ela ainda não foi buscada, e devolve o valor. Duas
   * chamadas simultâneas compartilham a mesma promessa.
   */
  fetch<T>(key: string, load: () => Promise<T>): Promise<T> {
    const e = this.entry(key);
    if (e.state.status === 'success') return Promise.resolve(e.state.data as T);
    if (e.promise !== null) return e.promise as Promise<T>;
    const promise = load().then(
      (data) => {
        if (e.promise === promise) this.set(e, { status: 'success', data, error: undefined });
        return data;
      },
      (error: unknown) => {
        if (e.promise === promise) this.set(e, { status: 'error', data: undefined, error });
        throw error;
      },
    );
    e.promise = promise;
    if (e.state.status === 'error') this.set(e, pending);
    return promise;
  }

  /** Descarta as chaves que começam com [prefix]; quem as observa busca de novo. */
  invalidate(prefix: string): void {
    for (const [key, e] of this.entries) {
      if (!key.startsWith(prefix)) continue;
      e.promise = null;
      this.set(e, pending);
    }
  }

  private set(e: Entry, state: QueryState<unknown>): void {
    e.state = state;
    if (state.status !== 'pending') e.promise = null;
    for (const l of [...e.listeners]) l();
  }
}

/** O cache da sessão. */
export const queryClient = new QueryClient();

/**
 * Lê uma consulta e a busca quando ninguém buscou. Com `key` nula, fica em
 * espera sem buscar — é como a tela diz "ainda não há o que perguntar".
 */
export function useQuery<T>(key: string | null, load: () => Promise<T>, client: QueryClient = queryClient): QueryState<T> & {
  refetch: () => void;
} {
  const subscribe = useCallback(
    (listener: () => void) => (key === null ? () => {} : client.subscribe(key, listener)),
    [client, key],
  );
  const getSnapshot = useCallback(() => (key === null ? pending : client.stateOf<T>(key)), [client, key]);
  const state = useSyncExternalStore(subscribe, getSnapshot, getSnapshot) as QueryState<T>;

  useEffect(() => {
    if (key === null) return;
    if (client.stateOf(key).status === 'pending') client.fetch(key, load).catch(() => {});
    // `load` muda a cada render; a chave é que diz se a pergunta mudou.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [client, key, state.status]);

  const refetch = useCallback(() => {
    if (key === null) return;
    client.invalidate(key);
  }, [client, key]);

  return { ...state, refetch };
}
