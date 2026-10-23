import { ArrowLeftRight, Plus, X } from 'lucide-react';
import { useState } from 'react';

import type { Ticker } from '../../core';
import { StudyActions, useStudy } from '../../app/state/study-store';
import { Badge } from '../../ui/badge';
import { Button } from '../../ui/button';
import { toast } from '../../ui/toast';
import { addToStudy } from './add-to-study';

/**
 * Onde o ativo está no estudo, e o que dá para fazer com ele daqui: incluir,
 * **promover da Reserva à Principal** (ou o contrário) e tirar.
 */
export function StudyMembership({ ticker, compact = false }: { ticker: Ticker; compact?: boolean }) {
  const study = useStudy((s) => s.study);
  const [busy, setBusy] = useState(false);
  const inPrincipal = study.principal.entries.has(ticker);
  const inReserve = study.reserve.entries.has(ticker);

  const add = async (toPrincipal: boolean) => {
    setBusy(true);
    const ok = await addToStudy(ticker, toPrincipal);
    setBusy(false);
    if (ok) toast(`${ticker.value} entrou na ${toPrincipal ? 'Principal' : 'Reserva'}.`, 'success');
  };

  if (!inPrincipal && !inReserve) {
    return (
      <div className="flex flex-wrap gap-2">
        <Button size="sm" variant="primary" disabled={busy} icon={<Plus aria-hidden className="size-4" />} onClick={() => add(true)}>
          {compact ? 'Principal' : 'Adicionar à Principal'}
        </Button>
        <Button size="sm" variant="reserve" disabled={busy} icon={<Plus aria-hidden className="size-4" />} onClick={() => add(false)}>
          {compact ? 'Reserva' : 'Adicionar à Reserva'}
        </Button>
      </div>
    );
  }
  return (
    <div className="flex flex-wrap items-center gap-2">
      <Badge tone={inPrincipal ? 'brand' : 'reserve'}>{inPrincipal ? 'Na Principal' : 'Na Reserva'}</Badge>
      <Button
        size="sm"
        variant={inPrincipal ? 'reserve' : 'primary'}
        icon={<ArrowLeftRight aria-hidden className="size-4" />}
        onClick={() => {
          if (StudyActions.swap(ticker, !inPrincipal)) {
            toast(inPrincipal ? `${ticker.value} foi para a Reserva.` : `${ticker.value} foi promovido à Principal.`, 'success');
          }
        }}
      >
        {inPrincipal ? 'Mover para a Reserva' : 'Promover à Principal'}
      </Button>
      <Button
        size="sm"
        variant="ghost"
        icon={<X aria-hidden className="size-4" />}
        onClick={() => StudyActions.removeAsset(ticker, inPrincipal)}
      >
        Tirar do estudo
      </Button>
    </div>
  );
}
