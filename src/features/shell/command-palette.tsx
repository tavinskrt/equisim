import { Command } from 'cmdk';
import { Moon, ScrollText, Search, SlidersHorizontal, Sun } from 'lucide-react';
import { Dialog } from 'radix-ui';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';

import { useUniverse } from '../../app/hooks';
import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { useStudy } from '../../app/state/study-store';
import { AuditRoutes } from '../../audit/audit-routes';
import { auditEnabled } from '../../audit/audit-bus';
import { Spinner } from '../../ui/feedback';
import { navItems } from './nav-items';
import { useAssetOverlay } from './use-asset-overlay';

const itemClass =
  'flex min-h-11 cursor-pointer select-none items-center gap-3 rounded-lg px-3 text-body-sm text-fg outline-none data-[selected=true]:bg-sunken';

/**
 * A busca global (⌘K / Ctrl+K): ativo, área ou comando. Escolher um ativo
 * abre o Raio-X dele **por cima da área corrente** — a busca não tira a pessoa
 * de onde ela está.
 */
export function CommandPalette(props: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const universe = useUniverse();
  const navigate = useNavigate();
  const overlay = useAssetOverlay();
  const theme = usePreferences((s) => s.theme);
  const mode = usePreferences((s) => s.mode);
  const study = useStudy((s) => s.study);
  const [query, setQuery] = useState('');

  useEffect(() => {
    if (!props.open) setQuery('');
  }, [props.open]);

  const inStudy = new Set([...study.principal.tickers, ...study.reserve.tickers].map((t) => t.value));
  const run = (action: () => void) => {
    props.onOpenChange(false);
    action();
  };

  return (
    <Dialog.Root open={props.open} onOpenChange={props.onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/50 data-[state=open]:animate-[overlay-in_140ms_ease-out]" />
        <Dialog.Content
          aria-describedby={undefined}
          className="fixed left-1/2 top-[8vh] z-50 w-[min(calc(100vw-24px),620px)] -translate-x-1/2 overflow-hidden rounded-2xl border border-line bg-raised shadow-pop data-[state=open]:animate-[pop-in_160ms_ease-out]"
        >
          <Dialog.Title className="sr-only">Buscar ativo ou comando</Dialog.Title>
          <Command label="Buscar ativo ou comando" loop>
            <div className="flex items-center gap-2 border-b border-divider px-4">
              <Search aria-hidden className="size-4 text-fg-3" />
              <Command.Input
                value={query}
                onValueChange={setQuery}
                autoFocus
                placeholder="Buscar ticker (ex.: PETR4), área ou comando"
                className="h-13 min-h-12 flex-1 bg-transparent text-body text-fg placeholder:text-fg-3 focus:outline-none"
              />
              <kbd className="hidden rounded border border-line px-1.5 text-caption text-fg-3 sm:inline">Esc</kbd>
            </div>
            <Command.List className="max-h-[min(60vh,440px)] overflow-y-auto p-2 scrollbar-thin">
              <Command.Empty className="px-3 py-6 text-center text-body-sm text-fg-2">
                Nada corresponde a “{query}”.
              </Command.Empty>
              {universe.status === 'pending' && (
                <Command.Loading>
                  <div className="flex items-center gap-2 px-3 py-3 text-body-sm text-fg-2">
                    <Spinner /> Carregando as ações da B3…
                  </div>
                </Command.Loading>
              )}
              {universe.status === 'error' && (
                <p className="px-3 py-3 text-body-sm text-negative">Não foi possível carregar a lista de ações da B3.</p>
              )}
              {universe.status === 'success' && (
                <Command.Group heading="Ativos" className="[&_[cmdk-group-heading]]:eyebrow [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-2">
                  {universe.data.map((t) => (
                    <Command.Item key={t.value} value={t.value} onSelect={() => run(() => overlay.open(t))} className={itemClass}>
                      <span className="num w-16 font-semibold">{t.value}</span>
                      <span className="flex-1 text-fg-3">Abrir o Raio-X</span>
                      {inStudy.has(t.value) && <span className="text-caption text-fg-3">no estudo</span>}
                    </Command.Item>
                  ))}
                </Command.Group>
              )}
              <Command.Group heading="Ir para" className="[&_[cmdk-group-heading]]:eyebrow [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-2">
                {navItems.map((n) => (
                  <Command.Item key={n.to} value={`ir ${n.label} ${n.description}`} onSelect={() => run(() => navigate(n.to))} className={itemClass}>
                    <n.icon aria-hidden className="size-4 text-fg-3" />
                    <span className="flex-1">{n.label}</span>
                    <span className="hidden text-caption text-fg-3 sm:inline">{n.description}</span>
                  </Command.Item>
                ))}
              </Command.Group>
              <Command.Group heading="Comandos" className="[&_[cmdk-group-heading]]:eyebrow [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-2">
                <Command.Item
                  value="tema claro escuro alternar"
                  onSelect={() => run(() => PreferencesActions.setTheme(theme === 'dark' ? 'light' : 'dark'))}
                  className={itemClass}
                >
                  {theme === 'dark' ? <Sun aria-hidden className="size-4 text-fg-3" /> : <Moon aria-hidden className="size-4 text-fg-3" />}
                  {theme === 'dark' ? 'Usar o tema claro' : 'Usar o tema escuro'}
                </Command.Item>
                <Command.Item
                  value="modo completo essencial analista detalhe"
                  onSelect={() => run(() => PreferencesActions.setMode(mode === 'guided' ? 'analyst' : 'guided'))}
                  className={itemClass}
                >
                  <SlidersHorizontal aria-hidden className="size-4 text-fg-3" />
                  {mode === 'guided' ? 'Mostrar tudo (modo Completo)' : 'Mostrar o essencial (modo Essencial)'}
                </Command.Item>
                {auditEnabled() && (
                  <Command.Item value="painel logs auditoria cálculo" onSelect={() => run(() => AuditRoutes.openInNewWindow())} className={itemClass}>
                    <ScrollText aria-hidden className="size-4 text-fg-3" />
                    Abrir o Painel de Logs de Cálculo
                  </Command.Item>
                )}
              </Command.Group>
            </Command.List>
          </Command>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
