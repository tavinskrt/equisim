import { createStore, del, get, set, update, type UseStore } from 'idb-keyval';

/**
 * Armazenamento chave-valor assíncrono sob o cache.
 *
 * Duas implementações: [IdbKeyValueStore], sobre o IndexedDB do navegador, e
 * [MemoryKeyValueStore], para teste e para o Node das ferramentas. A interface
 * é mínima de propósito — ler, gravar, apagar e **atualizar numa transação** —
 * porque é tudo o que o cache precisa, e quanto menor ela, menos as duas
 * implementações podem divergir.
 */
export interface KeyValueStore {
  get<T>(key: string): Promise<T | undefined>;
  set(key: string, value: unknown): Promise<void>;
  del(key: string): Promise<void>;
  /**
   * Lê, transforma e grava **na mesma transação**. É o que torna o `upsert`
   * aditivo seguro com duas abas gravando ao mesmo tempo: sem a transação, a
   * segunda leitura veria o estado anterior à primeira gravação e a desfaria.
   */
  update<T>(key: string, updater: (old: T | undefined) => T): Promise<void>;
}

/** Cache no IndexedDB do navegador, num banco próprio do Equisim. */
export class IdbKeyValueStore implements KeyValueStore {
  private readonly store: UseStore;

  constructor(dbName = 'equisim-cache', storeName = 'linhas') {
    this.store = createStore(dbName, storeName);
  }

  get<T>(key: string): Promise<T | undefined> {
    return get<T>(key, this.store);
  }

  set(key: string, value: unknown): Promise<void> {
    return set(key, value, this.store);
  }

  del(key: string): Promise<void> {
    return del(key, this.store);
  }

  update<T>(key: string, updater: (old: T | undefined) => T): Promise<void> {
    return update<T>(key, updater, this.store);
  }
}

/**
 * Cache em memória, com a mesma semântica de cópia do IndexedDB.
 *
 * Os valores são clonados na gravação e na leitura (`structuredClone`), como
 * o IndexedDB faz: sem isso, quem alterasse a lista lida alteraria o cache, e
 * o teste passaria aqui e falharia no navegador.
 */
export class MemoryKeyValueStore implements KeyValueStore {
  private readonly data = new Map<string, unknown>();

  /** Quando `true`, toda operação lança — simula banco que não abre. */
  failing = false;

  private guard(): void {
    if (this.failing) throw new Error('armazenamento indisponível');
  }

  async get<T>(key: string): Promise<T | undefined> {
    this.guard();
    const v = this.data.get(key);
    return v === undefined ? undefined : (structuredClone(v) as T);
  }

  async set(key: string, value: unknown): Promise<void> {
    this.guard();
    this.data.set(key, structuredClone(value));
  }

  async del(key: string): Promise<void> {
    this.guard();
    this.data.delete(key);
  }

  async update<T>(key: string, updater: (old: T | undefined) => T): Promise<void> {
    this.guard();
    const old = this.data.get(key);
    this.data.set(key, structuredClone(updater(old === undefined ? undefined : (structuredClone(old) as T))));
  }

  /** Chaves gravadas, para conferência em teste. */
  keys(): string[] {
    return [...this.data.keys()];
  }
}
