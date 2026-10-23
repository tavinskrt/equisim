import { readFileSync } from 'node:fs';

import { DateTime } from '../../src/core';
import type { AuthGateway, AuthUser } from '../../src/app/auth';
import { configureRuntime, memoryPreferences, type Runtime } from '../../src/app/runtime';
import { Services, type ServicesOptions, type UserStores } from '../../src/app/services';
import { useSession } from '../../src/app/state/session-store';
import { MemoryKeyValueStore } from '../../src/data/cache/key-value-store';
import { KeyValueManualValuationStore } from '../../src/data/persistence/manual-valuation-store';
import { LocalPortfolioStore } from '../../src/data/persistence/portfolio-store';
import { HttpError } from '../../src/data/network/http';

/** Lê um arquivo de `public/`, como o navegador o serviria. */
export function readPublicText(path: string): Promise<string> {
  return Promise.resolve(new TextDecoder('utf-8').decode(readFileSync(`public/${path}`)));
}

/** Os lugares de gravação em memória, com os mesmos formatos e mensagens dos reais. */
export function memoryStores(): UserStores {
  let n = 0;
  return {
    portfolios: new LocalPortfolioStore(new MemoryKeyValueStore(), () => 1_700_000_000_000 + n, () => `estudo-${++n}`),
    valuations: new KeyValueManualValuationStore(new MemoryKeyValueStore(), () => {}),
  };
}

/** Uma raiz de dependências sem rede: os pacotes vêm de `public/`, e a rede falha. */
export function offlineServices(overrides: Partial<ServicesOptions> = {}): Services {
  return new Services({
    loadText: readPublicText,
    cacheStore: null,
    clock: () => DateTime.local(2026, 10, 1),
    workerFactory: null,
    isWeb: true,
    warn: () => {},
    retrySleep: async () => {},
    transport: async (request) => {
      throw new HttpError('connectionError', request, { message: 'sem rede no teste' });
    },
    ...overrides,
  });
}

/**
 * Monta o ambiente do aplicativo para um teste: raiz sem rede, gravação em
 * memória e a sessão já identificada (ou não, com `user: null`).
 */
export function testRuntime(
  args: {
    user?: AuthUser | null;
    local?: boolean;
    cloudStores?: UserStores | null;
    localStores?: UserStores;
    auth?: AuthGateway | null;
    services?: Services;
  } = {},
): Runtime {
  const runtime: Runtime = {
    services: args.services ?? offlineServices(),
    auth: args.auth ?? null,
    authUnavailableReason: null,
    cloudStores: args.cloudStores === undefined ? memoryStores() : args.cloudStores,
    localStores: args.localStores ?? memoryStores(),
    preferences: memoryPreferences(),
  };
  configureRuntime(runtime);
  const user = args.user === undefined ? { uid: 'usuario-1', email: 'a@b.c', displayName: 'Ana' } : args.user;
  useSession.setState({ status: user === null ? 'signedOut' : 'signedIn', user, local: args.local ?? false });
  return runtime;
}
