import { auditBus, auditEnabled } from '../audit/audit-bus';
import { IdbKeyValueStore, type KeyValueStore, MemoryKeyValueStore } from '../data/cache/key-value-store';
import { KeyValueManualValuationStore, FirestoreManualValuationStore } from '../data/persistence/manual-valuation-store';
import { FirestorePortfolioStore, LocalPortfolioStore } from '../data/persistence/portfolio-store';
import { FirebaseAuthGateway, initFirebase } from './auth';
import { browserPreferences, configureRuntime } from './runtime';
import { Services, type UserStores } from './services';
import { PreferencesActions, usePreferences } from './state/preferences-store';
import { SavedValuationsActions } from './state/saved-valuations-store';
import { startSession, useSession } from './state/session-store';
import { readDraft, StudyActions } from './state/study-store';

/**
 * Lê um arquivo de `public/` pelo caminho relativo — os pacotes de dados
 * versionados. A falha de leitura é a ausência do pacote, que cada leitura
 * trata como o comportamento anterior a ele.
 */
async function loadPublicText(path: string): Promise<string> {
  const response = await fetch(`${import.meta.env.BASE_URL}${path}`);
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
  return response.text();
}

/**
 * O IndexedDB pode não abrir (janela privada do Firefox antigo, dados de site
 * bloqueados). Aí o cache e o modo local ficam em memória — valem pela aba —,
 * e o aplicativo segue em vez de morrer na partida.
 */
async function openStore(dbName: string, storeName: string): Promise<KeyValueStore> {
  const store = new IdbKeyValueStore(dbName, storeName);
  try {
    await store.get('__sonda__');
    return store;
  } catch {
    return new MemoryKeyValueStore();
  }
}

/**
 * Monta o aplicativo da janela de operação: a raiz de dependências, o
 * Firebase (ou o modo local), as preferências, a sessão e o barramento da
 * auditoria. Devolve o desligamento das assinaturas.
 */
export async function bootOperator(): Promise<() => void> {
  const env = import.meta.env;
  const [cacheStore, localStore] = await Promise.all([
    openStore('equisim-cache', 'linhas'),
    openStore('equisim-local', 'dados'),
  ]);

  const services = new Services({
    loadText: loadPublicText,
    env: {
      proxyUrl: env.VITE_BRAPI_PROXY_URL ?? null,
      token: env.VITE_BRAPI_TOKEN ?? null,
      baseUrl: env.VITE_BRAPI_BASE_URL ?? null,
    },
    cacheStore,
    isWeb: true,
  });

  const firebase = initFirebase({ VITE_EQUISIM_LOCAL: env.VITE_EQUISIM_LOCAL });
  const localStores: UserStores = {
    portfolios: new LocalPortfolioStore(localStore),
    valuations: new KeyValueManualValuationStore(localStore),
  };
  const cloudStores: UserStores | null = firebase.ok
    ? {
        portfolios: new FirestorePortfolioStore(firebase.firestore),
        valuations: new FirestoreManualValuationStore(firebase.firestore),
      }
    : null;

  configureRuntime({
    services,
    auth: firebase.ok ? new FirebaseAuthGateway(firebase.auth, firebase.firestore) : null,
    authUnavailableReason: firebase.ok ? null : firebase.reason,
    cloudStores,
    localStores,
    preferences: browserPreferences,
  });

  PreferencesActions.hydrate();
  const draft = readDraft();
  if (draft !== null) StudyActions.load(draft);

  // A auditoria liga o coletor do núcleo **antes** do primeiro cálculo: o que
  // acontece antes de o painel abrir é justamente o que se quer replayar.
  if (auditEnabled()) auditBus.start('emitter');

  const stopSession = startSession();

  // Ao entrar (ou mudar de conta), recarrega o que é do usuário: estudos,
  // valuations confirmados — que vão ao painel de logs — e a preferência de
  // tema da conta.
  let lastUid: string | null = null;
  const reactToSession = (uid: string | null, local: boolean) => {
    if (uid === lastUid) return;
    lastUid = uid;
    void StudyActions.refreshSaved();
    void SavedValuationsActions.load();
    if (uid !== null && !local) void PreferencesActions.syncThemeWithAccount(uid);
  };
  const initial = useSession.getState();
  reactToSession(initial.user?.uid ?? null, initial.local);
  const stopWatch = useSession.subscribe((s) => reactToSession(s.user?.uid ?? null, s.local));

  return () => {
    stopSession();
    stopWatch();
  };
}

/**
 * Monta só o painel de logs: sem Firebase, sem sessão e sem a raiz de
 * dependências — a janela paralela não calcula, para não poluir a própria
 * auditoria.
 */
export function bootInspector(): void {
  // Sem `configureRuntime`: as preferências caem no armazenamento do navegador.
  PreferencesActions.hydrate();
  auditBus.start('inspector');
}

/** Aplica o tema ao documento, e acompanha a troca. */
export function bindThemeToDocument(): () => void {
  const apply = (theme: 'dark' | 'light') => {
    document.documentElement.dataset.theme = theme;
    const meta = document.querySelector('meta[name="theme-color"]');
    meta?.setAttribute('content', theme === 'dark' ? '#0B1116' : '#F4F6F8');
  };
  apply(usePreferences.getState().theme);
  return usePreferences.subscribe((s, prev) => {
    if (s.theme !== prev.theme) apply(s.theme);
  });
}
