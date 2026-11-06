import { create } from 'zustand';

import { type BacktestSettings, clampWindowYears, defaultBacktestSettings } from '../backtest';
import { browserPreferences, getRuntime, hasRuntime, type PreferenceStorage } from '../runtime';
import { defaultValuationSettings, type ValuationSettings } from '../valuation';
import { useSession } from './session-store';

export type ThemeMode = 'dark' | 'light';

export interface PreferencesState {
  readonly theme: ThemeMode;
  readonly valuation: ValuationSettings;
  readonly backtest: BacktestSettings;
}

const keys = { theme: 'equisim:tema' } as const;

/**
 * Onde as preferências moram: as do ambiente montado, ou as do navegador na
 * janela do painel de logs, que sobe sem a raiz de dependências.
 */
function storage(): PreferenceStorage {
  return hasRuntime() ? getRuntime().preferences : browserPreferences;
}

function initialTheme(): ThemeMode {
  // O aplicativo abre no escuro, como o Flutter, salvo escolha guardada.
  const stored = storage().get(keys.theme);
  return stored === 'light' ? 'light' : 'dark';
}

export const usePreferences = create<PreferencesState>(() => ({
  theme: 'dark',
  valuation: defaultValuationSettings,
  backtest: defaultBacktestSettings,
}));

export const PreferencesActions = {
  /** Lê as preferências guardadas. Chamado na partida, depois do ambiente montado. */
  hydrate(): void {
    usePreferences.setState({ theme: initialTheme() });
  },

  /**
   * Troca o tema, guarda no navegador e, com conta, no documento do usuário —
   * a mesma preferência `isLightMode` que o aplicativo Flutter gravava.
   */
  setTheme(theme: ThemeMode): void {
    usePreferences.setState({ theme });
    storage().set(keys.theme, theme);
    if (!hasRuntime()) return;
    const runtime = getRuntime();
    const { user, local } = useSession.getState();
    if (user !== null && !local && runtime.auth !== null) {
      runtime.auth.writeThemePreference(user.uid, theme === 'light').catch(() => {
        // A preferência na nuvem é conveniência; a local já valeu.
      });
    }
  },

  /**
   * Sincroniza o tema com a conta ao entrar: a da nuvem vale quando existe;
   * sem ela, a atual é gravada lá.
   */
  async syncThemeWithAccount(uid: string): Promise<void> {
    const runtime = getRuntime();
    if (runtime.auth === null) return;
    try {
      const cloud = await runtime.auth.readThemePreference(uid);
      if (cloud === null) {
        await runtime.auth.writeThemePreference(uid, usePreferences.getState().theme === 'light');
        return;
      }
      const theme: ThemeMode = cloud ? 'light' : 'dark';
      usePreferences.setState({ theme });
      runtime.preferences.set(keys.theme, theme);
    } catch {
      // Sem a nuvem, vale a preferência do navegador.
    }
  },

  /** Alterna entre os três cenários discretos e o Monte Carlo — o único ajuste da avaliação. */
  setMonteCarlo(monteCarlo: boolean): void {
    usePreferences.setState((s) => ({ valuation: { ...s.valuation, monteCarlo } }));
  },

  /** A janela do backtest, travada entre 1 e 10 anos. */
  setWindowYears(years: number): void {
    usePreferences.setState((s) => ({ backtest: { ...s.backtest, windowYears: clampWindowYears(years) } }));
  },
};
