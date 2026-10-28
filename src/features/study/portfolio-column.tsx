import { useDraggable, useDroppable } from '@dnd-kit/core';
import { ArrowLeftRight, GripVertical, Inbox, PlusCircle, Scale, X } from 'lucide-react';

import { type ManualValuationRecord, Portfolio, type PortfolioEntry } from '../../core';
import { Fmt } from '../../copy';
import { userValuationOf, useSavedValuations } from '../../app/state/saved-valuations-store';
import { StudyActions } from '../../app/state/study-store';
import { IconButton } from '../../ui/button';
import { cn } from '../../ui/cn';
import { EmptyState } from '../../ui/feedback';
import { HintPopover } from '../../ui/hint';
import { TickerLogo } from '../../ui/ticker-logo';
import { useAssetOverlay } from '../shell/use-asset-overlay';
import { PotentialCell } from './potential-cell';

/** O identificador de soltura de cada coluna. */
export const dropIds = { principal: 'carteira-principal', reserve: 'carteira-reserva' } as const;

/**
 * Uma carteira, que é ao mesmo tempo alvo de soltura. O gesto central é
 * arrastar um ativo para a outra; **o botão de troca faz o mesmo** para quem
 * usa teclado, leitor de tela ou toque impreciso.
 */
export function PortfolioColumn(props: { portfolio: Portfolio; isPrincipal: boolean; onAdd: () => void }) {
  const { portfolio, isPrincipal } = props;
  const { setNodeRef, isOver, active } = useDroppable({ id: isPrincipal ? dropIds.principal : dropIds.reserve });
  const draggingFromOther = active !== null && !portfolio.entries.has(active.data.current?.['ticker']);
  const highlight = isOver && draggingFromOther;
  const records = useSavedValuations((s) => s.records);

  return (
    <section
      ref={setNodeRef}
      aria-labelledby={isPrincipal ? 'col-principal' : 'col-reserva'}
      className={cn(
        'rounded-xl border bg-surface p-4 shadow-card transition-colors sm:p-5',
        highlight ? 'border-brand bg-brand-surface/40' : isPrincipal ? 'border-brand/35' : 'border-reserve/30',
      )}
    >
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <h2 id={isPrincipal ? 'col-principal' : 'col-reserva'} className="flex items-center gap-2 text-title-sm font-semibold text-fg">
            <span aria-hidden className={cn('size-2.5 rounded-full', isPrincipal ? 'bg-brand' : 'bg-reserve')} />
            {isPrincipal ? 'Carteira Principal' : 'Carteira Reserva'}
          </h2>
          <p className="mt-0.5 text-body-sm text-fg-2">
            {isPrincipal ? `Portfólio vigente · ${portfolio.length} / ${Portfolio.maxAssets}` : 'Candidatos a substituição'}
          </p>
        </div>
        <div className="-my-2 flex items-center">
          <HintPopover
            size="md"
            title="Colunas desta lista"
            intro="O potencial vem do valuation de cada ativo, recalculado a cada abertura da tela."
            entries={[
              {
                term: 'Peso',
                meaning:
                  'Fatia do aporte destinada ao ativo. Não há rebalanceamento: o peso define para onde vai cada aporte, e a partir daí a posição deriva com o mercado.',
              },
              {
                term: 'Potencial',
                meaning:
                  'Distância entre a cotação e o preço justo estimado pelo modelo, em percentual, com o preço justo logo abaixo. É a discordância entre o modelo e o mercado — não um retorno previsto, e sem prazo para se realizar.',
              },
              {
                term: 'Seu valuation',
                meaning:
                  'Quando você confirmou um valuation que discorda do motor, o potencial e o preço justo são os seus, marcados “seu” no lugar de “justo”, contra a cotação de hoje. Confirmar os números do motor devolve o ativo ao preço do motor.',
              },
              {
                term: 'Marca ⚠',
                meaning:
                  'Potencial acima de 100% em qualquer direção, ou avaliação com ressalvas. Costuma indicar exercício-base atípico, crescimento no teto da banda de sanidade ou demonstrativo incompleto. Abra o Raio-X para ver as premissas.',
              },
            ]}
          />
          {portfolio.length > 1 && (
            <IconButton label="Equiponderar" onClick={() => StudyActions.equalize(isPrincipal)}>
              <Scale aria-hidden className="size-[18px]" />
            </IconButton>
          )}
          <IconButton label="Adicionar ativo" tone={isPrincipal ? 'brand' : 'reserve'} onClick={props.onAdd}>
            <PlusCircle aria-hidden className="size-5" />
          </IconButton>
        </div>
      </div>

      {portfolio.isEmpty ? (
        <EmptyState
          className="min-h-40"
          icon={<Inbox className="size-5" />}
          title={highlight ? 'Solte aqui' : 'Nenhum ativo'}
          message={isPrincipal ? 'Adicione ativos ou arraste da Reserva.' : 'Guarde aqui os candidatos a entrar na Principal.'}
        />
      ) : (
        <div className="mt-3">
          <div className="hidden grid-cols-[28px_1fr_120px_96px_88px] items-center gap-2 px-1 pb-1.5 sm:grid" aria-hidden>
            <span />
            <span className="eyebrow">Ativo</span>
            <span className="eyebrow">Peso</span>
            <span className="eyebrow text-right">Potencial</span>
            <span />
          </div>
          <ul className="divide-y divide-divider">
            {[...portfolio.entries.values()].map((entry) => (
              <AssetRow key={entry.ticker.value} entry={entry} isPrincipal={isPrincipal} mine={userValuationOf(records, entry.ticker)} />
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}

function AssetRow({ entry, isPrincipal, mine }: { entry: PortfolioEntry; isPrincipal: boolean; mine: ManualValuationRecord | null }) {
  const overlay = useAssetOverlay();
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `${isPrincipal ? 'p' : 'r'}:${entry.ticker.value}`,
    data: { ticker: entry.ticker, fromPrincipal: isPrincipal },
  });
  const weight = entry.weight.value;
  return (
    <li
      ref={setNodeRef}
      className={cn(
        'grid grid-cols-[28px_1fr_auto] items-center gap-x-2 gap-y-1 py-2 sm:grid-cols-[28px_1fr_120px_96px_88px]',
        isDragging && 'opacity-30',
      )}
    >
      <button
        type="button"
        className="-ml-2 inline-flex size-11 cursor-grab touch-none items-center justify-center rounded-md text-fg-3 hover:text-fg active:cursor-grabbing"
        aria-label={`Arrastar ${entry.ticker.value} para a ${isPrincipal ? 'Reserva' : 'Principal'}`}
        {...attributes}
        {...listeners}
      >
        <GripVertical aria-hidden className="size-4" />
      </button>
      <button
        type="button"
        onClick={() => overlay.open(entry.ticker)}
        className="flex min-w-0 items-center gap-2 rounded-md py-1 text-left hover:bg-sunken/60"
      >
        <TickerLogo ticker={entry.ticker} size="sm" />
        <span className="min-w-0">
          <span className="block truncate text-body-sm font-bold text-fg">{entry.ticker.value}</span>
          <span className="block truncate text-caption text-fg-3">
            {entry.sector.isUnknown ? 'Setor não classificado' : entry.sector.label}
          </span>
        </span>
      </button>
      {/* No celular, peso e potencial descem para a segunda linha, com rótulo. */}
      <div className="col-span-3 col-start-2 row-start-2 flex items-center gap-3 sm:col-span-1 sm:col-start-3 sm:row-start-1">
        <span className="text-caption text-fg-3 sm:hidden">peso</span>
        <div className="flex flex-1 items-center gap-2">
          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-sunken" aria-hidden>
            <div
              className={cn('h-full rounded-full', isPrincipal ? 'bg-brand' : 'bg-reserve')}
              style={{ width: `${Math.min(weight, 1) * 100}%` }}
            />
          </div>
          <span className="num w-14 text-right text-body-sm text-fg">{Fmt.weight(weight)}</span>
        </div>
        <span className="text-caption text-fg-3 sm:hidden">potencial</span>
        <span className="sm:hidden">
          <PotentialCell ticker={entry.ticker} mine={mine} />
        </span>
      </div>
      <div className="hidden justify-end sm:flex">
        <PotentialCell ticker={entry.ticker} mine={mine} />
      </div>
      <div className="col-start-3 row-start-1 flex justify-end sm:col-start-5">
        <IconButton
          label={isPrincipal ? `Mover ${entry.ticker.value} para a Reserva` : `Promover ${entry.ticker.value} à Principal`}
          tone={isPrincipal ? 'reserve' : 'brand'}
          onClick={() => StudyActions.swap(entry.ticker, !isPrincipal)}
        >
          <ArrowLeftRight aria-hidden className="size-4" />
        </IconButton>
        <IconButton label={`Remover ${entry.ticker.value}`} tone="danger" onClick={() => StudyActions.removeAsset(entry.ticker, isPrincipal)}>
          <X aria-hidden className="size-4" />
        </IconButton>
      </div>
    </li>
  );
}
