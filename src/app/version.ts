/**
 * A versão do Equisim em uso, `MAJOR.MINOR.PATCH`.
 *
 * Vem do campo `version` do `package.json`, substituído no build pelo `define`
 * do Vite (`vite.config.ts`, e o mesmo em `vitest.config.ts`). Um teste
 * confere que ela é a da versão mais recente de `src/data/changelog.ts`.
 */
export const APP_VERSION: string = __EQUISIM_VERSION__;

/** A versão como aparece na tela: `v2.5.0`. */
export const APP_VERSION_LABEL = `v${APP_VERSION}`;
