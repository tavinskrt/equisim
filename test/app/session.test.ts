import { beforeEach, describe, expect, it } from 'vitest';

import type { AuthGateway, AuthUser } from '../../src/app/auth';
import { getRuntime } from '../../src/app/runtime';
import { PreferencesActions, usePreferences } from '../../src/app/state/preferences-store';
import {
  activeStores,
  continueLocally,
  currentUserId,
  localUser,
  signOutSession,
  startSession,
  useSession,
} from '../../src/app/state/session-store';
import { testRuntime } from './harness';

/** Porta de autenticação de mentira: a sessão corrente separada do fluxo. */
class FakeAuth implements AuthGateway {
  listener: ((u: AuthUser | null) => void) | null = null;
  theme: boolean | null = null;
  writes: boolean[] = [];
  signedOut = false;
  constructor(public currentUser: AuthUser | null = null) {}
  current() {
    return this.currentUser;
  }
  onChange(l: (u: AuthUser | null) => void) {
    this.listener = l;
    return () => {
      this.listener = null;
    };
  }
  emit(u: AuthUser | null) {
    this.currentUser = u;
    this.listener?.(u);
  }
  async signIn() {}
  async signUp() {}
  async sendPasswordReset() {}
  async signOut() {
    this.signedOut = true;
    this.emit(null);
  }
  async changePassword() {}
  async updateProfile() {}
  async deleteAccount() {}
  async readThemePreference() {
    return this.theme;
  }
  async writeThemePreference(_uid: string, isLight: boolean) {
    this.writes.push(isLight);
  }
}

const ana: AuthUser = { uid: 'usuario-1', email: 'ana@exemplo.com', displayName: 'Ana' };

beforeEach(() => useSession.setState({ status: 'loading', user: null, local: false }));

describe('A sessão', () => {
  it('identifica a sessão restaurada antes do fluxo emitir', () => {
    // Regressão do Flutter: "salvar estudo" concluía não haver ninguém logado.
    testRuntime({ user: null, auth: new FakeAuth(ana) });
    useSession.setState({ status: 'loading', user: null, local: false });
    startSession();
    expect(currentUserId()).toBe('usuario-1');
  });

  it('o fluxo manda depois de emitir — sair derruba a sessão', () => {
    const auth = new FakeAuth(ana);
    testRuntime({ user: null, auth });
    startSession();
    auth.emit(null);
    expect(currentUserId()).toBeNull();
    expect(useSession.getState().status).toBe('signedOut');
  });

  it('sem Firebase, abre direto em modo local, com os dados no navegador', () => {
    testRuntime({ user: null, auth: null, cloudStores: null });
    useSession.setState({ status: 'loading', user: null, local: false });
    startSession();
    expect(useSession.getState().user).toEqual(localUser);
    expect(useSession.getState().local).toBe(true);
    expect(activeStores()).toBe(getRuntime().localStores);
  });

  it('seguir sem conta é lembrado na próxima abertura, e sair esquece', async () => {
    const auth = new FakeAuth(null);
    testRuntime({ user: null, auth });
    startSession();
    auth.emit(null);
    expect(useSession.getState().status).toBe('signedOut');
    continueLocally();
    expect(activeStores()).toBe(getRuntime().localStores);
    // Reabrir: o fluxo emite "ninguém", e a escolha local vale.
    startSession();
    auth.emit(null);
    expect(useSession.getState().local).toBe(true);
    await signOutSession();
    expect(useSession.getState().status).toBe('signedOut');
    expect(auth.signedOut, 'quem estava em modo local não sai da conta').toBe(false);
  });

  it('com conta, os lugares de gravação são os da nuvem', () => {
    const auth = new FakeAuth(ana);
    testRuntime({ user: null, auth });
    startSession();
    expect(activeStores()).toBe(getRuntime().cloudStores);
  });
});

describe('O tema', () => {
  it('abre no escuro sem preferência, e lê a guardada antes de pintar', () => {
    const runtime = testRuntime();
    PreferencesActions.hydrate();
    expect(usePreferences.getState().theme).toBe('dark');
    runtime.preferences.set('equisim:tema', 'light');
    PreferencesActions.hydrate();
    expect(usePreferences.getState().theme).toBe('light');
  });

  it('ao entrar, a preferência da conta vale; sem ela, a atual vai para a conta', async () => {
    const auth = new FakeAuth(ana);
    testRuntime({ auth });
    PreferencesActions.hydrate();
    auth.theme = true;
    await PreferencesActions.syncThemeWithAccount('usuario-1');
    expect(usePreferences.getState().theme).toBe('light');

    auth.theme = null;
    usePreferences.setState({ theme: 'dark' });
    await PreferencesActions.syncThemeWithAccount('usuario-1');
    expect(auth.writes).toEqual([false]);
  });

  it('trocar o tema com conta grava na conta; em modo local, só no navegador', () => {
    const auth = new FakeAuth(ana);
    const runtime = testRuntime({ auth });
    PreferencesActions.setTheme('light');
    expect(auth.writes).toEqual([true]);
    expect(runtime.preferences.get('equisim:tema')).toBe('light');
    useSession.setState({ local: true, user: localUser });
    PreferencesActions.setTheme('dark');
    expect(auth.writes).toEqual([true]);
  });
});
