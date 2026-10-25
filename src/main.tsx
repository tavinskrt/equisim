import './styles.css';

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from 'react-router';

import { bindThemeToDocument, bootInspector, bootOperator } from './app/boot';
import { AuditRoutes } from './audit/audit-routes';
import { Toaster } from './ui/toast';
import { TooltipProvider } from './ui/tooltip';

const root = createRoot(document.getElementById('root')!);

/**
 * A partida. A janela de `/logs` sobe **só o painel** — sem Firebase, sem
 * sessão, sem a raiz de dependências —, para não disparar cálculo próprio que
 * poluiria a auditoria que ela existe para mostrar.
 */
async function start(): Promise<void> {
  if (AuditRoutes.isLogsWindow(window.location.pathname, import.meta.env.BASE_URL)) {
    bootInspector();
    bindThemeToDocument();
    const { LogsApp } = await import('./features/logs/logs-app');
    root.render(
      <StrictMode>
        <TooltipProvider>
          <LogsApp />
          <Toaster />
        </TooltipProvider>
      </StrictMode>,
    );
    return;
  }

  await bootOperator();
  bindThemeToDocument();
  const { router } = await import('./router');
  root.render(
    <StrictMode>
      <TooltipProvider>
        <RouterProvider router={router} />
        <Toaster />
      </TooltipProvider>
    </StrictMode>,
  );
}

start().catch((e: unknown) => {
  // Sem a partida não há interface; a mensagem diz o que houve em vez de uma tela branca.
  console.error(e);
  const message = e instanceof Error ? e.message : String(e);
  const box = document.createElement('div');
  box.setAttribute('role', 'alert');
  box.style.cssText = 'max-width:520px;margin:15vh auto;padding:24px;font-family:system-ui,sans-serif;color:var(--fg);';
  box.innerHTML = '<h1 style="font-size:20px;margin:0 0 8px">O Equisim não conseguiu iniciar</h1><p style="margin:0 0 16px;color:var(--fg-2)"></p><button type="button" style="min-height:44px;padding:0 16px;border-radius:8px;border:1px solid var(--border);background:var(--surface);color:var(--fg)">Recarregar</button>';
  box.querySelector('p')!.textContent = message;
  box.querySelector('button')!.addEventListener('click', () => window.location.reload());
  document.getElementById('root')!.replaceChildren(box);
});
