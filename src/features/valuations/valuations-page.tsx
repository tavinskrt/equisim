import { BadgeCheck, ScanSearch, Search, SlidersHorizontal } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router';

import { SavedValuationsActions, useSavedValuations } from '../../app/state/saved-valuations-store';
import { useSession } from '../../app/state/session-store';
import type { ManualValuationRecord } from '../../core';
import { Fmt } from '../../copy';
import { Badge } from '../../ui/badge';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card } from '../../ui/card';
import { EmptyState, Skeleton } from '../../ui/feedback';
import { TextField } from '../../ui/field';
import { TickerLogo } from '../../ui/ticker-logo';
import { useOpenAsset } from '../shell/use-open-asset';
import { SavedValuationItem } from './saved-valuation-item';

interface Group {
  readonly ticker: string;
  /** Do mais recente para o mais antigo, como o armazenamento entrega. */
  readonly records: readonly ManualValuationRecord[];
}

/** Agrupa por ativo, com o ativo do valuation mais recente primeiro. */
export function groupByTicker(records: readonly ManualValuationRecord[]): Group[] {
  const groups = new Map<string, ManualValuationRecord[]>();
  for (const r of records) {
    const list = groups.get(r.ticker.value) ?? [];
    list.push(r);
    groups.set(r.ticker.value, list);
  }
  return [...groups.entries()].map(([ticker, list]) => ({ ticker, records: list }));
}

/**
 * **Meus valuations confirmados** (decisões 150 e 151): tudo o que foi
 * confirmado na edição, por ativo. Cada um guarda as premissas e o resultado do
 * dia em que foi salvo; o mais recente de cada ativo é o "seu" que aparece nas
 * linhas do estudo e na régua de preço.
 */
export function ValuationsPage() {
  const saved = useSavedValuations();
  const local = useSession((s) => s.local);
  const [filter, setFilter] = useState('');
  const groups = useMemo(() => groupByTicker(saved.records), [saved.records]);
  const query = filter.trim().toUpperCase();
  const shown = query === '' ? groups : groups.filter((g) => g.ticker.includes(query));

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-title font-semibold text-fg">Meus valuations</h1>
        <p className="mt-1 text-body-sm text-fg-2">
          Os valuations que você confirmou na edição, por ativo. Cada um guarda as premissas e o resultado do dia em que foi salvo — e também foi ao painel de logs.
        </p>
      </div>
      {local && <Banner>Neste navegador: os valuations ficam guardados aqui, e não acompanham você para outro aparelho. Entre numa conta para levá-los junto.</Banner>}

      {saved.status === 'error' && (
        <Banner tone="negative" action={<Button size="sm" onClick={() => void SavedValuationsActions.load()}>Tentar de novo</Button>}>
          Não foi possível carregar os seus valuations agora{saved.error !== null ? ` — ${saved.error}` : ''}.
        </Banner>
      )}

      {(saved.status === 'idle' || saved.status === 'loading') && saved.records.length === 0 ? (
        <div className="space-y-3" aria-busy>
          <span className="sr-only" role="status">
            Carregando os seus valuations
          </span>
          {[0, 1].map((i) => (
            <Card key={i} className="p-5">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="mt-3 h-6 w-48" />
              <Skeleton className="mt-2 h-3 w-full" />
            </Card>
          ))}
        </div>
      ) : groups.length === 0 ? (
        saved.status !== 'error' && (
          <Card>
            <EmptyState
              icon={<BadgeCheck aria-hidden className="size-6" />}
              title="Nenhum valuation confirmado ainda"
              message='Abra um ativo pelo Raio-X (Ctrl K, ou o código na carteira), use "Simular minhas premissas" e confirme: ele aparece aqui, nas linhas do estudo como "seu" e no painel de logs.'
              action={
                <Button asChild variant="secondary">
                  <Link to="/estudo">Ir ao estudo</Link>
                </Button>
              }
            />
          </Card>
        )
      ) : (
        <>
          {groups.length > 3 && (
            <TextField
              label="Filtrar por ativo"
              placeholder="PETR4"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              leading={<Search aria-hidden className="size-4" />}
              className="max-w-xs"
              autoCapitalize="characters"
            />
          )}
          <p className="text-caption text-fg-3" aria-live="polite">
            {shown.length} {shown.length === 1 ? 'ativo' : 'ativos'} · {shown.reduce((n, g) => n + g.records.length, 0)} valuations
          </p>
          <div className="grid items-start gap-4 xl:grid-cols-2">
            {shown.map((g) => (
              <TickerGroup key={g.ticker} group={g} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function TickerGroup({ group }: { group: Group }) {
  const open = useOpenAsset();
  const latest = group.records[0]!;
  return (
    <Card className="p-4 sm:p-5">
      <div className="flex flex-wrap items-start gap-2">
        <TickerLogo ticker={latest.ticker} size="lg" />
        <div className="min-w-0 flex-1">
          <h2 className="text-title-sm font-bold text-fg">{group.ticker}</h2>
          <p className="text-caption text-fg-2">
            {group.records.length === 1 ? '1 valuation' : `${group.records.length} valuations`} · o mais recente, de {Fmt.date(latest.savedAt)}, é o seu nas linhas do
            estudo
          </p>
        </div>
        <Badge tone="brand">seu {Fmt.money(latest.fairValuePerShare)}</Badge>
      </div>
      <div className="mt-2 flex flex-wrap gap-2">
        <Button size="sm" variant="ghost" icon={<ScanSearch aria-hidden className="size-4" />} onClick={() => open(latest.ticker)}>
          Raio-X
        </Button>
        <Button asChild size="sm" variant="ghost">
          <Link to={`/ativo/${group.ticker}/simular`}>
            <SlidersHorizontal aria-hidden className="size-4" />
            Simular de novo
          </Link>
        </Button>
      </div>
      <div className="mt-2 divide-y divide-divider">
        {group.records.map((r) => (
          <SavedValuationItem key={r.id} record={r} todayLane="unknown" />
        ))}
      </div>
    </Card>
  );
}
