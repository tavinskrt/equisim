import { ScrollText, Search } from 'lucide-react';
import { useEffect, useState } from 'react';
import { NavLink, Outlet } from 'react-router';

import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { StudyActions, useStudy } from '../../app/state/study-store';
import { auditEnabled } from '../../audit/audit-bus';
import { AuditRoutes } from '../../audit/audit-routes';
import { IconButton } from '../../ui/button';
import { cn } from '../../ui/cn';
import { Segmented } from '../../ui/segmented';
import { toast } from '../../ui/toast';
import { AssetXRay } from '../asset/asset-xray';
import { AccountMenu } from './account-menu';
import { CommandPalette } from './command-palette';
import { ContextBar } from './context-bar';
import { navItems } from './nav-items';
import { useAssetOverlay } from './use-asset-overlay';

/** O símbolo do Equisim: a curva que sobe, sobre o verde da marca. */
export function Logo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" aria-hidden className={cn('size-8', className)}>
      <rect width="32" height="32" rx="9" fill="var(--brand)" />
      <path d="M7 21.5l5.5-5.5 4 3.5L25 11" fill="none" stroke="var(--on-brand)" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="25" cy="11" r="2.2" fill="var(--on-brand)" />
    </svg>
  );
}

/**
 * A casca: cabeçalho com as áreas, a busca e o modo; a barra do estudo; a área
 * corrente; e, por cima de qualquer área, o Raio-X do ativo.
 */
export function AppShell() {
  const [paletteOpen, setPaletteOpen] = useState(false);
  const mode = usePreferences((s) => s.mode);
  const lastError = useStudy((s) => s.lastError);
  const overlay = useAssetOverlay();

  // ⌘K / Ctrl+K abre a busca de qualquer lugar.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPaletteOpen((o) => !o);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // A recusa de uma edição do estudo (teto de 15, ativo repetido, gravação
  // que falhou) vira mensagem, e o erro é consumido.
  useEffect(() => {
    if (lastError === null) return;
    toast(lastError, 'error');
    StudyActions.clearError();
  }, [lastError]);

  return (
    <div className="flex min-h-dvh flex-col">
      <a
        href="#conteudo"
        className="sr-only z-[70] rounded-md bg-brand px-3 py-2 font-semibold text-on-brand focus:not-sr-only focus:fixed focus:left-3 focus:top-3"
      >
        Pular para o conteúdo
      </a>
      <header className="sticky top-0 z-30 border-b border-line bg-canvas/85 backdrop-blur-md supports-[backdrop-filter]:bg-canvas/70">
        <div className="mx-auto flex h-14 max-w-[1440px] items-center gap-2 px-3 sm:px-6">
          <NavLink to="/estudo" className="flex items-center gap-2 rounded-lg pr-2" aria-label="Equisim — início">
            <Logo />
            <span className="hidden text-body font-bold tracking-tight text-fg sm:inline">Equisim</span>
          </NavLink>
          <nav aria-label="Áreas" className="ml-2 hidden items-center gap-0.5 md:flex">
            {navItems.map((n) => (
              <NavLink
                key={n.to}
                to={n.to}
                className={({ isActive }) =>
                  cn(
                    'inline-flex min-h-10 items-center gap-2 rounded-lg px-3 text-body-sm font-medium transition-colors',
                    isActive ? 'bg-sunken text-fg' : 'text-fg-2 hover:bg-sunken/60 hover:text-fg',
                  )
                }
              >
                <n.icon aria-hidden className="size-4" />
                {n.label}
              </NavLink>
            ))}
          </nav>
          <div className="ml-auto flex items-center gap-1">
            <button
              type="button"
              onClick={() => setPaletteOpen(true)}
              aria-label="Buscar ativo ou comando (Ctrl+K)"
              className="hidden min-h-10 items-center gap-2 rounded-lg border border-line bg-sunken px-3 text-body-sm text-fg-3 transition-colors hover:border-line-strong hover:text-fg-2 sm:inline-flex lg:w-64"
            >
              <Search aria-hidden className="size-4" />
              <span className="flex-1 text-left">Buscar ativo…</span>
              <kbd className="hidden rounded border border-line px-1.5 text-caption lg:inline">Ctrl K</kbd>
            </button>
            <IconButton label="Buscar ativo ou comando" className="sm:hidden" onClick={() => setPaletteOpen(true)}>
              <Search aria-hidden className="size-[18px]" />
            </IconButton>
            <Segmented
              label="Profundidade da interface"
              size="sm"
              value={mode}
              onChange={PreferencesActions.setMode}
              className="ml-1 hidden sm:inline-flex"
              options={[
                { value: 'guided', label: 'Essencial' },
                { value: 'analyst', label: 'Completo' },
              ]}
            />
            {auditEnabled() && (
              <IconButton label="Abrir Painel de Logs de Cálculo" onClick={() => AuditRoutes.openInNewWindow()}>
                <ScrollText aria-hidden className="size-[18px]" />
              </IconButton>
            )}
            <AccountMenu />
          </div>
        </div>
      </header>
      <ContextBar />

      <main id="conteudo" className="mx-auto w-full max-w-[1440px] flex-1 px-4 pb-28 pt-4 sm:px-6 md:pb-10">
        {/* No celular o modo mora aqui: o cabeçalho não tem largura. */}
        <div className="mb-3 flex justify-end sm:hidden">
          <Segmented
            label="Profundidade da interface"
            size="sm"
            value={mode}
            onChange={PreferencesActions.setMode}
            options={[
              { value: 'guided', label: 'Essencial' },
              { value: 'analyst', label: 'Completo' },
            ]}
          />
        </div>
        <Outlet />
      </main>

      <nav
        aria-label="Áreas"
        className="safe-bottom fixed inset-x-0 bottom-0 z-30 border-t border-line bg-surface/95 backdrop-blur-md md:hidden"
      >
        <div className="grid grid-cols-4">
          {navItems.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              className={({ isActive }) =>
                cn('flex min-h-14 flex-col items-center justify-center gap-0.5 text-caption font-medium', isActive ? 'text-positive' : 'text-fg-3')
              }
            >
              <n.icon aria-hidden className="size-5" />
              {n.short}
            </NavLink>
          ))}
        </div>
      </nav>

      <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} />
      <AssetXRay ticker={overlay.ticker} onClose={overlay.close} />
    </div>
  );
}
