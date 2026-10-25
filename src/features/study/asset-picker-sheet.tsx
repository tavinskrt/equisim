import { Check, Plus, Search, SearchX } from 'lucide-react';
import { useDeferredValue, useState } from 'react';

import type { Ticker } from '../../core';
import { useUniverse } from '../../app/hooks';
import { useStudy } from '../../app/state/study-store';
import { Button } from '../../ui/button';
import { Disclosure } from '../../ui/disclosure';
import { EmptyState, Spinner } from '../../ui/feedback';
import { Sheet } from '../../ui/sheet';
import { toast } from '../../ui/toast';
import { useAssetOverlay } from '../shell/use-asset-overlay';
import { addToStudy } from './add-to-study';
import { PortaZeroExplainer } from './porta-zero';

/**
 * **Inclusão rápida**: busca por ticker no universo da B3 e inclui na
 * carteira escolhida, com a Porta 0 explicada antes da escolha.
 */
export function AssetPickerSheet(props: { open: boolean; onOpenChange: (open: boolean) => void; toPrincipal: boolean }) {
  const universe = useUniverse();
  const study = useStudy((s) => s.study);
  const overlay = useAssetOverlay();
  const [query, setQuery] = useState('');
  const deferred = useDeferredValue(query.trim().toUpperCase());
  const [busy, setBusy] = useState<string | null>(null);

  const used = new Set([...study.principal.tickers, ...study.reserve.tickers]);
  const filtered =
    universe.status === 'success' ? universe.data.filter((t) => deferred === '' || t.value.startsWith(deferred)).slice(0, 200) : [];

  const add = async (t: Ticker, toPrincipal: boolean) => {
    setBusy(t.value);
    const ok = await addToStudy(t, toPrincipal);
    setBusy(null);
    if (ok) toast(`${t.value} entrou na ${toPrincipal ? 'Principal' : 'Reserva'}.`, 'success');
  };

  return (
    <Sheet
      open={props.open}
      onOpenChange={(o) => {
        props.onOpenChange(o);
        if (!o) setQuery('');
      }}
      title={props.toPrincipal ? 'Adicionar à Principal' : 'Adicionar à Reserva'}
      description="Ações da B3 — fundos imobiliários estão fora do escopo"
      width="md"
    >
      <div className="sticky top-0 z-10 space-y-3 border-b border-divider bg-canvas px-4 py-3 sm:px-5">
        <div className="relative">
          <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-fg-3" />
          <label htmlFor="picker-search" className="sr-only">
            Buscar ticker
          </label>
          <input
            id="picker-search"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Buscar ticker (ex.: PETR4)"
            autoCapitalize="characters"
            autoComplete="off"
            className="block min-h-11 w-full rounded-lg border border-line bg-sunken pl-9 pr-3 text-body text-fg placeholder:text-fg-3 focus:border-brand focus:outline-none"
          />
        </div>
        <Disclosure title="O que o motor avalia" summary="A Porta 0: liquidez, histórico, patrimônio e continuidade">
          <PortaZeroExplainer className="bg-surface" />
        </Disclosure>
      </div>
      <div className="px-2 py-2 sm:px-3">
        {universe.status === 'pending' && (
          <div className="flex justify-center py-10">
            <Spinner label="Carregando a lista de ações" />
          </div>
        )}
        {universe.status === 'error' && (
          <EmptyState title="Universo indisponível" message="Não foi possível carregar a lista de ações da B3." />
        )}
        {universe.status === 'success' && filtered.length === 0 && (
          <EmptyState icon={<SearchX className="size-5" />} title="Nada encontrado" message={`Nenhuma ação corresponde a “${deferred}”.`} />
        )}
        <ul>
          {filtered.map((t) => {
            const isUsed = used.has(t);
            return (
              <li key={t.value} className="flex items-center gap-2 rounded-lg px-2 hover:bg-sunken/60">
                <button
                  type="button"
                  className="min-h-12 flex-1 text-left"
                  onClick={() => overlay.open(t)}
                  aria-label={`Abrir o Raio-X de ${t.value}`}
                >
                  <span className={`num text-body-sm font-semibold ${isUsed ? 'text-fg-3' : 'text-fg'}`}>{t.value}</span>
                  {isUsed && <span className="ml-2 text-caption text-fg-3">já está no estudo</span>}
                </button>
                {isUsed ? (
                  <Check aria-hidden className="mr-3 size-4 text-fg-3" />
                ) : (
                  <Button
                    size="sm"
                    variant={props.toPrincipal ? 'primary' : 'reserve'}
                    disabled={busy !== null}
                    icon={busy === t.value ? <Spinner className="text-current" /> : <Plus aria-hidden className="size-4" />}
                    onClick={() => add(t, props.toPrincipal)}
                    aria-label={`Adicionar ${t.value} à ${props.toPrincipal ? 'Principal' : 'Reserva'}`}
                  >
                    Adicionar
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </Sheet>
  );
}
