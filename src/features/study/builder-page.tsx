import {
  type Announcements,
  DndContext,
  type DragEndEvent,
  DragOverlay,
  type DragStartEvent,
  KeyboardSensor,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import { Landmark } from 'lucide-react';
import { useState } from 'react';

import type { ConcentrationReport, Ticker } from '../../core';
import { Fmt } from '../../copy';
import { concentrationOf, StudyActions, useStudy } from '../../app/state/study-store';
import { Banner } from '../../ui/banner';
import { AssetPickerSheet } from './asset-picker-sheet';
import { dropIds, PortfolioColumn } from './portfolio-column';
import { SectorDonut } from './sector-donut';
import { StudySummary } from './study-summary';

function concentrationMessage(report: ConcentrationReport): string {
  const parts = report.concentrated
    .map((e) => `${e.sector.label} (${e.count} ativos, ${Fmt.percent(e.weight, { decimals: 0 })})`)
    .join(' · ');
  return `Concentração setorial na carteira Principal: ${parts}. É um aviso, não um impedimento.`;
}

const announcements: Announcements = {
  onDragStart: ({ active }) => `${(active.data.current?.['ticker'] as Ticker | undefined)?.value ?? 'Ativo'} pego.`,
  onDragOver: ({ over }) =>
    over === null ? 'Fora das carteiras.' : over.id === dropIds.principal ? 'Sobre a Principal.' : 'Sobre a Reserva.',
  onDragEnd: ({ active, over }) => {
    const t = (active.data.current?.['ticker'] as Ticker | undefined)?.value ?? 'Ativo';
    return over === null ? `${t} solto fora das carteiras; nada mudou.` : `${t} solto na ${over.id === dropIds.principal ? 'Principal' : 'Reserva'}.`;
  },
  onDragCancel: () => 'Arraste cancelado; nada mudou.',
};

/**
 * **O Montador** da dupla carteira. O gesto central é arrastar um ativo entre
 * Principal e Reserva; como o recálculo de pesos e concentração custa
 * microssegundos, tudo responde no mesmo quadro do gesto.
 */
export function BuilderPage() {
  const study = useStudy((s) => s.study);
  const concentration = concentrationOf(study.principal);
  const [picker, setPicker] = useState<{ open: boolean; toPrincipal: boolean }>({ open: false, toPrincipal: true });
  const [dragging, setDragging] = useState<Ticker | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    // No toque, um atraso curto separa o arraste da rolagem da página.
    useSensor(TouchSensor, { activationConstraint: { delay: 180, tolerance: 8 } }),
    useSensor(KeyboardSensor),
  );

  const onDragStart = (e: DragStartEvent) => setDragging((e.active.data.current?.['ticker'] as Ticker | undefined) ?? null);
  const onDragEnd = (e: DragEndEvent) => {
    setDragging(null);
    const ticker = e.active.data.current?.['ticker'] as Ticker | undefined;
    const fromPrincipal = e.active.data.current?.['fromPrincipal'] as boolean | undefined;
    if (ticker === undefined || e.over === null) return;
    const toPrincipal = e.over.id === dropIds.principal;
    if (toPrincipal === fromPrincipal) return;
    StudyActions.swap(ticker, toPrincipal);
  };

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-title font-semibold text-fg">Estudo</h1>
        <p className="mt-1 text-body-sm text-fg-2">
          Monte a Principal e guarde candidatos na Reserva. Arraste entre as duas — ou use o botão de troca — e abra qualquer ativo
          para ver o Raio-X.
        </p>
      </div>
      <StudySummary />
      {concentration.hasAlert && (
        <Banner tone="caution" icon={<Landmark aria-hidden className="mt-0.5 size-4 shrink-0" />}>
          {concentrationMessage(concentration)}
        </Banner>
      )}
      <DndContext
        sensors={sensors}
        onDragStart={onDragStart}
        onDragEnd={onDragEnd}
        onDragCancel={() => setDragging(null)}
        accessibility={{
          announcements,
          screenReaderInstructions: {
            draggable:
              'Para mover o ativo, pressione espaço ou Enter, use as setas para chegar à outra carteira e pressione espaço de novo. Esc cancela.',
          },
        }}
      >
        <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_300px]">
          <PortfolioColumn portfolio={study.principal} isPrincipal onAdd={() => setPicker({ open: true, toPrincipal: true })} />
          <PortfolioColumn portfolio={study.reserve} isPrincipal={false} onAdd={() => setPicker({ open: true, toPrincipal: false })} />
          <div className="lg:col-span-2 xl:col-span-1 xl:col-start-3 xl:row-start-1">
            <SectorDonut portfolio={study.principal} />
          </div>
        </div>
        <DragOverlay dropAnimation={null}>
          {dragging === null ? null : (
            <div className="w-48 rounded-xl border border-brand bg-raised px-4 py-3 text-body font-bold text-fg shadow-pop">{dragging.value}</div>
          )}
        </DragOverlay>
      </DndContext>
      <AssetPickerSheet open={picker.open} toPrincipal={picker.toPrincipal} onOpenChange={(open) => setPicker((p) => ({ ...p, open }))} />
    </div>
  );
}
