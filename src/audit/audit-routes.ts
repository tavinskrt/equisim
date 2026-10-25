/**
 * Endereçamento do painel de auditoria.
 *
 * **Rota de caminho, e não de fragmento.** O Flutter web usava `#/logs` porque
 * o servidor de desenvolvimento dele não reescrevia rotas. O Vite serve o
 * `index.html` para qualquer caminho em desenvolvimento, e o Firebase Hosting
 * faz o mesmo pela regra de `rewrites` do `firebase.json` — então `/logs`
 * recarrega sem configuração adicional.
 */
export const AuditRoutes = {
  /** Rota dedicada do painel. */
  logs: '/logs',

  /**
   * `true` quando a aplicação foi aberta diretamente no painel.
   *
   * A janela paralela é uma segunda instância completa da aplicação.
   * Detectar isso no arranque permite subir só o painel — sem Firebase, sem
   * sessão, sem a casca de navegação —, o que a impede de disparar cálculos
   * próprios que poluiriam a própria auditoria.
   */
  isLogsWindow(pathname: string, base = '/'): boolean {
    const root = base.endsWith('/') ? base.slice(0, -1) : base;
    const path = pathname.split('?')[0]!.replace(/\/+$/, '');
    return path === `${root}${AuditRoutes.logs}`;
  },

  /** Abre o painel numa guia nova. Devolve `false` fora do navegador. */
  openInNewWindow(): boolean {
    if (typeof window === 'undefined') return false;
    const base = import.meta.env.BASE_URL.replace(/\/$/, '');
    // Sem `noopener`: o painel não precisa de `window.opener`, mas a guia
    // nova precisa ser da mesma origem para o canal funcionar — e é.
    window.open(`${window.location.origin}${base}${AuditRoutes.logs}`, 'equisim-auditoria');
    return true;
  },
};
