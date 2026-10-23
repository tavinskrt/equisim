import 'katex/dist/katex.min.css';

import { Download, Hourglass, Moon, Pause, Play, RefreshCw, Search, Sigma, Sun, Trash2 } from 'lucide-react';
import { ToggleGroup } from 'radix-ui';
import { type ReactNode, useDeferredValue, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';

import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { auditBus } from '../../audit/audit-bus';
import { AUDIT_FILTERS, type AuditFilter, auditFileName, buildAuditDocument, downloadText, matchesFilter, matchesQuery } from '../../audit/audit-export';
import { cn } from '../../ui/cn';
import { toast } from '../../ui/toast';
import { EventCard } from './event-card';

const filterLabels: Record<AuditFilter, string> = {
  todos: 'Todos',
  calculos: 'Cálculos',
  'valuations-confirmados': 'Valuations confirmados',
  rede: 'Rede',
};

/**
 * **O Painel de Auditoria de Cálculos**, em `/logs`. Janela paralela, só de
 * leitura: recebe pelo `BroadcastChannel` o que a janela principal calcula, e
 * pede o histórico ao abrir — o painel costuma ser aberto depois das
 * primeiras consultas.
 */
export function LogsApp() {
  const snapshot = useSyncExternalStore(auditBus.subscribe, auditBus.getSnapshot);
  const theme = usePreferences((s) => s.theme);
  const [filter, setFilter] = useState<AuditFilter>('todos');
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query);
  const [autoScroll, setAutoScroll] = useState(true);
  const lastCount = useRef(snapshot.history.length);

  const visible = useMemo(
    () => snapshot.history.filter((e) => matchesFilter(e, filter) && matchesQuery(e, deferredQuery)),
    [snapshot.history, filter, deferredQuery],
  );

  useEffect(() => {
    document.title = 'Equisim — Auditoria de Cálculos';
  }, []);

  // Evento novo com o acompanhamento ligado: rola até ele.
  useEffect(() => {
    const grew = snapshot.history.length > lastCount.current;
    lastCount.current = snapshot.history.length;
    if (grew && autoScroll) {
      requestAnimationFrame(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' }));
    }
  }, [snapshot.history.length, autoScroll]);

  const exportAudit = () => {
    const doc = buildAuditDocument({
      events: visible,
      historySize: snapshot.history.length,
      filter,
      query,
      discardedCalculations: snapshot.discardedCalculations,
      discardedNetwork: snapshot.discardedNetwork,
    });
    const text = JSON.stringify(doc, null, 2);
    if (downloadText(auditFileName(), text)) {
      toast(`Auditoria exportada: ${visible.length} eventos.`, 'success');
      return;
    }
    navigator.clipboard
      ?.writeText(text)
      .then(() => toast(`Auditoria copiada para a área de transferência (${visible.length} eventos).`, 'success'))
      .catch(() => toast('O navegador não permitiu baixar nem copiar a auditoria.', 'error'));
  };

  const total = snapshot.history.length;
  const discarded = snapshot.discardedCalculations > 0 || snapshot.discardedNetwork > 0;

  return (
    <div className="min-h-dvh bg-canvas">
      <header className="z-20 border-b sm:sticky sm:top-0 border-line bg-surface/95 px-4 pb-3 pt-3.5 backdrop-blur-md">
        <div className="mx-auto max-w-5xl">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
            <h1 className="inline-flex items-center gap-2 text-title-sm font-bold text-fg">
              <Sigma aria-hidden className="size-5 text-positive" />
              Painel de Auditoria de Cálculos
            </h1>
            <StatusPill tone={snapshot.crossWindow ? 'ok' : 'warn'}>{snapshot.crossWindow ? 'Canal entre janelas ativo' : 'Entrega local (mesma janela)'}</StatusPill>
            <StatusPill tone={snapshot.role === 'emitter' ? 'ok' : 'neutral'}>{snapshot.role === 'emitter' ? 'Esta janela calcula' : 'Modo inspeção'}</StatusPill>
            {snapshot.role === 'inspector' && !snapshot.peerConnected && <StatusPill tone="warn">Aguardando a janela principal</StatusPill>}
            <span className="text-caption text-fg-3" aria-live="polite">
              {visible.length === total ? `${total} evento(s)` : `${visible.length} de ${total} evento(s)`}
            </span>
            {discarded && (
              <span className="text-caption font-medium text-caution">
                {snapshot.discardedCalculations} cálculo(s) e {snapshot.discardedNetwork} de rede descartados
              </span>
            )}
          </div>
          <div className="mt-2.5 flex flex-wrap items-center gap-2">
            <ConsoleButton icon={<Trash2 aria-hidden className="size-3.5" />} onClick={() => auditBus.clear()}>
              Limpar Logs
            </ConsoleButton>
            <ConsoleButton
              icon={autoScroll ? <Pause aria-hidden className="size-3.5" /> : <Play aria-hidden className="size-3.5" />}
              active={!autoScroll}
              onClick={() => setAutoScroll((a) => !a)}
            >
              {autoScroll ? 'Pausar Auto-scroll' : 'Retomar Auto-scroll'}
            </ConsoleButton>
            <ConsoleButton icon={<Download aria-hidden className="size-3.5" />} onClick={exportAudit}>
              Exportar Auditoria (JSON)
            </ConsoleButton>
            {snapshot.role === 'inspector' && (
              <ConsoleButton icon={<RefreshCw aria-hidden className="size-3.5" />} onClick={() => auditBus.requestReplay()}>
                Recarregar histórico
              </ConsoleButton>
            )}
            <ConsoleButton
              icon={theme === 'dark' ? <Sun aria-hidden className="size-3.5" /> : <Moon aria-hidden className="size-3.5" />}
              onClick={() => PreferencesActions.setTheme(theme === 'dark' ? 'light' : 'dark')}
            >
              {theme === 'dark' ? 'Modo claro' : 'Modo escuro'}
            </ConsoleButton>
          </div>
          <div className="mt-2.5 flex flex-wrap items-center gap-2">
            <ToggleGroup.Root
              type="single"
              aria-label="Filtrar eventos"
              value={filter}
              onValueChange={(v) => v !== '' && setFilter(v as AuditFilter)}
              className="flex flex-wrap gap-1.5"
            >
              {AUDIT_FILTERS.map((f) => (
                <ToggleGroup.Item
                  key={f}
                  value={f}
                  className="min-h-9 rounded-full border border-line px-3 text-label text-fg-2 hover:text-fg data-[state=on]:border-brand data-[state=on]:bg-brand-surface data-[state=on]:font-bold data-[state=on]:text-positive"
                >
                  {filterLabels[f]}
                </ToggleGroup.Item>
              ))}
            </ToggleGroup.Root>
            <label className="relative ml-auto block w-full sm:w-64">
              <span className="sr-only">Filtrar por ativo ou fórmula</span>
              <Search aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-fg-3" />
              <input
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Filtrar por ativo ou fórmula…"
                className="block min-h-10 w-full rounded-lg border border-line bg-sunken pl-8 pr-3 text-body-sm text-fg placeholder:text-fg-3 focus:border-brand focus:outline-none"
              />
            </label>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-5xl px-4 pb-8 pt-3">
        {visible.length === 0 ? (
          <div className="flex flex-col items-center px-6 py-16 text-center">
            <Hourglass aria-hidden className="size-9 text-fg-3" />
            <p className="mt-3.5 text-title-sm font-bold text-fg">{total === 0 ? 'Aguardando execuções' : 'Nenhum evento neste filtro'}</p>
            <p className="mt-2 max-w-md text-body-sm leading-relaxed text-fg-3">
              {total > 0
                ? 'Troque o filtro ou apague a busca para ver os outros eventos.'
                : snapshot.crossWindow
                  ? 'Volte à janela principal e abra um ativo, a meta ou o backtest. Cada requisição à API e cada fórmula avaliada aparece aqui no instante em que acontece.'
                  : 'Use a aplicação normalmente: as execuções aparecem aqui assim que ocorrerem.'}
            </p>
          </div>
        ) : (
          <ol className="space-y-2">
            {visible.map((e, i) => (
              <li key={e.transactionId}>
                <EventCard event={e} ordinal={i + 1} />
              </li>
            ))}
          </ol>
        )}
      </main>
    </div>
  );
}

function StatusPill({ tone, children }: { tone: 'ok' | 'warn' | 'neutral'; children: ReactNode }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-caption',
        tone === 'ok' && 'border-brand/35 bg-brand-surface text-positive',
        tone === 'warn' && 'border-caution/35 bg-caution-surface text-caution',
        tone === 'neutral' && 'border-line bg-sunken text-fg-2',
      )}
    >
      <span aria-hidden className={cn('size-1.5 rounded-full', tone === 'ok' ? 'bg-positive' : tone === 'warn' ? 'bg-caution' : 'bg-fg-3')} />
      {children}
    </span>
  );
}

function ConsoleButton(props: { icon: ReactNode; children: ReactNode; onClick: () => void; active?: boolean }) {
  return (
    <button
      type="button"
      onClick={props.onClick}
      aria-pressed={props.active}
      className={cn(
        'inline-flex min-h-10 items-center gap-1.5 rounded-lg border px-3 text-label transition-colors',
        props.active ? 'border-caution/40 bg-caution-surface text-caution' : 'border-line bg-sunken text-fg hover:border-line-strong',
      )}
    >
      {props.icon}
      {props.children}
    </button>
  );
}
