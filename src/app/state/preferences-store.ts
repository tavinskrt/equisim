import { create } from 'zustand';

import { type BacktestSettings, clampWindowYears, defaultBacktestSettings } from '../backtest';
import { getRuntime, hasRuntime } from '../runtime';
import { defaultValuationSettings, type ValuationSettings } from '../valuation';
import { useSession } from './session-store';

/**
 * Profundidade da interface.
 *
 * - `guided` (Essencial): o veredito em linguagem simples e o que decide.
 * - `analyst` (Completo): tudo o que o motor mostra — modelo, taxas,
 *   normalização, múltiplos, sensibilidade, ressalvas, métricas inteiras.
 *
 * Os números são os mesmos nos dois: o modo muda o que aparece, nunca a conta.
 */
export type DetailMode = 'guided' | 'analyst';

export type ThemeMode = 'dark' | 'light';

export interface PreferencesState {
  readonly mode: DetailMode;
  readonly theme: ThemeMode;
  readonly valuation: ValuationSettings;
  readonly backtest: BacktestSettings;
}

const keys = { mode: 'equisim:modo', theme: 'equisim:tema' } as const;

function initialTheme(): ThemeMode {
  // O aplicativo abre no escuro, como o Flutter, salvo escolha guardada.
  const stored = hasRuntime() ? getRuntime().preferences.get(keys.theme) : null;
  return stored === 'light' ? 'light' : 'dark';
}

function initialMode(): DetailMode {
  const stored = hasRuntime() ? getRuntime().preferences.get(keys.mode) : null;
  return stored === 'analyst' ? 'analyst' : 'guided';
}

export const usePreferences = create<PreferencesState>(() => ({
  mode: 'guided',
  theme: 'dark',
  valuation: defaultValuationSettings,
  backtest: defaultBacktestSettings,
}));

export const PreferencesActions = {
  /** Lê as preferências guardadas. Chamado na partida, depois do ambiente montado. */
  hydrate(): void {
    usePreferences.setState({ mode: initialMode(), theme: initialTheme() });
  },

  setMode(mode: DetailMode): void {
    usePreferences.setState({ mode });
    if (hasRuntime()) getRuntime().preferences.set(keys.mode, mode);
  },

  /**
   * Troca o tema, guarda no navegador e, com conta, no documento do usuário —
   * a mesma preferência `isLightMode` que o aplicativo Flutter gravava.
   */
  setTheme(theme: ThemeMode): void {
    usePreferences.setState({ theme });
    if (!hasRuntime()) return;
    const runtime = getRuntime();
    runtime.preferences.set(keys.theme, theme);
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
