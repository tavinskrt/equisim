import { create } from 'zustand';

import type { AuthUser } from '../auth';
import { getRuntime } from '../runtime';

/** Onde a sessão está. */
export type SessionStatus = 'loading' | 'signedOut' | 'signedIn';

export interface SessionState {
  readonly status: SessionStatus;
  readonly user: AuthUser | null;
  /**
   * `true` quando os dados do usuário ficam **neste navegador**: sem Firebase,
   * ou por escolha de seguir sem conta. Os estudos não acompanham a pessoa
   * para outro aparelho, e a tela diz isso.
   */
  readonly local: boolean;
}

/** O usuário do modo local: um só por navegador. */
export const localUser: AuthUser = { uid: 'local', email: null, displayName: 'Neste navegador' };

const localChoiceKey = 'equisim:modo-local';

export const useSession = create<SessionState>(() => ({ status: 'loading', user: null, local: false }));

/** O identificador do usuário da sessão, ou `null`. */
export function currentUserId(): string | null {
  return useSession.getState().user?.uid ?? null;
}

/** Os lugares de gravação da sessão: os da conta, ou os do navegador. */
export function activeStores() {
  const runtime = getRuntime();
  const { local, user } = useSession.getState();
  if (user === null) return null;
  return local || runtime.cloudStores === null ? runtime.localStores : runtime.cloudStores;
}

/**
 * Liga a sessão à porta de autenticação. Sem porta, o aplicativo abre direto
 * em modo local; com porta, a escolha anterior de seguir sem conta é lembrada.
 * Devolve o desligamento.
 */
export function startSession(): () => void {
  const runtime = getRuntime();
  if (runtime.auth === null) {
    useSession.setState({ status: 'signedIn', user: localUser, local: true });
    return () => {};
  }
  // Até o fluxo emitir, vale a sessão já restaurada.
  const restored = runtime.auth.current();
  if (restored !== null) useSession.setState({ status: 'signedIn', user: restored, local: false });
  return runtime.auth.onChange((user) => {
    if (user !== null) {
      runtime.preferences.remove(localChoiceKey);
      useSession.setState({ status: 'signedIn', user, local: false });
    } else if (runtime.preferences.get(localChoiceKey) === 'sim') {
      useSession.setState({ status: 'signedIn', user: localUser, local: true });
    } else {
      useSession.setState({ status: 'signedOut', user: null, local: false });
    }
  });
}

/** Segue sem conta: os dados ficam neste navegador. */
export function continueLocally(): void {
  getRuntime().preferences.set(localChoiceKey, 'sim');
  useSession.setState({ status: 'signedIn', user: localUser, local: true });
}

/** Sai da conta, ou do modo local. */
export async function signOutSession(): Promise<void> {
  const runtime = getRuntime();
  runtime.preferences.remove(localChoiceKey);
  const { local } = useSession.getState();
  if (!local && runtime.auth !== null) await runtime.auth.signOut();
  useSession.setState({
    status: runtime.auth === null ? 'signedIn' : 'signedOut',
    user: runtime.auth === null ? localUser : null,
    local: runtime.auth === null,
  });
}
