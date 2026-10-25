import { ChevronDown, SlidersHorizontal, Trash2 } from 'lucide-react';
import { Collapsible } from 'radix-ui';
import { useState } from 'react';
import { Link } from 'react-router';

import {
  ManualField,
  ManualGrowthPath,
  ManualRatePath,
  ManualReinvestment,
  type ManualValuationRecord,
  type ValuationLane,
} from '../../core';
import { Fmt, ManualCopy } from '../../copy';
import { SavedValuationsActions } from '../../app/state/saved-valuations-store';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { cn } from '../../ui/cn';
import { ConfirmDialog } from '../../ui/dialog';
import { KeyValue } from '../../ui/metric';
import { toast } from '../../ui/toast';

const millions = (v: number) => `${v < 0 ? '−' : ''}R$ ${Fmt.ratio(Math.abs(v) / 1e6, 1)} mi`;

const stamp = (r: ManualValuationRecord) => `${Fmt.date(r.savedAt)} ${Fmt.time(r.savedAt)}`;

/**
 * Um valuation confirmado: o preço, o que foi trocado e, aberto, os números e
 * o resultado. **Reabrir** só vale quando a avaliação de hoje segue a mesma
 * via (firma ou acionista): os números de uma não cabem nos campos da outra.
 */
export function SavedValuationItem(props: {
  record: ManualValuationRecord;
  /**
   * A via da avaliação de hoje, para decidir se reabrir é possível; `null` sem
   * avaliação. `'unknown'` quando a lista não avaliou o ativo — a edição confere
   * a via ao abrir e avisa se ela mudou.
   */
  todayLane: ValuationLane | null | 'unknown';
  showTicker?: boolean;
}) {
  const { record } = props;
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const o = record.outcome;
  const upside = record.upside;
  const delta = record.engineDelta;
  const changed = record.changedFields;
  const canReopen = props.todayLane === 'unknown' || (props.todayLane !== null && props.todayLane === record.lane);

  const summary = [
    stamp(record),
    upside !== null ? `${Fmt.percent(upside, { decimals: 1, signed: true })} sobre o mercado de ${Fmt.money(record.marketPrice)}` : null,
    `${delta >= 0 ? '+' : '−'}${Fmt.money(Math.abs(delta))} contra o motor`,
  ]
    .filter((s): s is string => s !== null)
    .join(' · ');

  return (
    <Collapsible.Root open={open} onOpenChange={setOpen}>
      <Collapsible.Trigger className="flex min-h-14 w-full items-start gap-3 rounded-lg py-2 text-left">
        <span className="min-w-0 flex-1">
          <span className="flex flex-wrap items-baseline gap-x-2">
            {props.showTicker && <span className="text-body font-bold text-fg">{record.ticker.value}</span>}
            <span className="num text-title-sm font-semibold text-fg">{Fmt.money(o.fairValuePerShare)} por ação</span>
          </span>
          <span className="mt-0.5 block text-caption text-fg-2">{summary}</span>
          <span className="mt-0.5 block text-caption text-fg-3">
            {changed.length === 0
              ? 'Nenhum campo trocado: o preço do motor naquele dia.'
              : `Você trocou: ${changed.map((f) => ManualCopy.label(f, record.lane).toLowerCase()).join(', ')}.`}
          </span>
        </span>
        <ChevronDown aria-hidden className={cn('mt-1 size-4 shrink-0 text-fg-2 transition-transform', open && 'rotate-180')} />
      </Collapsible.Trigger>
      <Collapsible.Content className="space-y-4 pb-3 pt-1">
        <Section title="Seus números" rows={inputs(record)} />
        <Section title="O resultado" rows={outputs(record)} />
        {o.notices.map((n, i) => (
          <Banner key={i}>{ManualCopy.warning(n)}</Banner>
        ))}
        <div className="flex flex-wrap gap-2">
          {canReopen ? (
            <Button asChild size="sm" variant="secondary">
              <Link to={`/ativo/${record.ticker.value}/simular?registro=${encodeURIComponent(record.id)}`}>
                <SlidersHorizontal aria-hidden className="size-4" />
                Reabrir na edição
              </Link>
            </Button>
          ) : (
            <Button size="sm" disabled icon={<SlidersHorizontal aria-hidden className="size-4" />}>
              Reabrir na edição
            </Button>
          )}
          <Button size="sm" variant="danger" icon={<Trash2 aria-hidden className="size-4" />} onClick={() => setConfirming(true)}>
            Apagar
          </Button>
        </div>
        {!canReopen && (
          <p className="text-caption text-fg-3">
            {props.todayLane === null
              ? 'Sem a avaliação de hoje, não há campos onde reabrir este valuation.'
              : 'A avaliação de hoje mudou de via: os números deste valuation não cabem nos campos dela.'}
          </p>
        )}
      </Collapsible.Content>
      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title="Apagar este valuation?"
        description="Ele sai dos seus valuations salvos e não volta. O registro que ele deixou no painel de logs desta sessão continua lá."
        confirmLabel="Apagar"
        busy={busy}
        onConfirm={async () => {
          setBusy(true);
          const removed = await SavedValuationsActions.remove(record.id);
          setBusy(false);
          setConfirming(false);
          if (removed.isErr) toast(removed.failureOrNull!.message, 'error');
        }}
      />
    </Collapsible.Root>
  );
}

function Section({ title, rows }: { title: string; rows: readonly (readonly [string, string])[] }) {
  return (
    <div>
      <p className="eyebrow mb-1">{title}</p>
      <div className="divide-y divide-divider">
        {rows.map(([label, value]) => (
          <KeyValue key={label} label={label} value={value} />
        ))}
      </div>
    </div>
  );
}

function inputs(r: ManualValuationRecord): (readonly [string, string])[] {
  const p = r.premises;
  const label = (f: ManualField) => ManualCopy.label(f, r.lane);
  return [
    [label(ManualField.baseProfit), millions(p.baseProfit)],
    [
      label(ManualField.growth),
      `${Fmt.percent(p.growth)} no ano 1, ${p.growthPath === ManualGrowthPath.constant ? 'constante nos 10 anos' : 'caindo até a perpetuidade'}`,
    ],
    [label(ManualField.perpetualGrowth), Fmt.percent(p.perpetualGrowth)],
    [
      label(ManualField.discountRate),
      `${Fmt.percent(p.discountRate)} no ano 1, ${p.ratePath === ManualRatePath.constant ? 'uma taxa só' : 'seguindo a curva'}`,
    ],
    p.reinvestment === ManualReinvestment.byReturn
      ? [label(ManualField.returnOnCapital), Fmt.percent(p.returnOnCapital)]
      : [label(ManualField.retention), Fmt.percent(p.retention, { decimals: 1 })],
    [label(ManualField.terminalReturn), p.terminalReturn === null ? 'igual à taxa' : Fmt.percent(p.terminalReturn)],
  ];
}

function outputs(r: ManualValuationRecord): (readonly [string, string])[] {
  const o = r.outcome;
  const rows: (readonly [string, string])[] = [
    ['Valor presente dos 10 anos', millions(o.explicitPresentValue)],
    ['Valor presente da perpetuidade', millions(o.terminalPresentValue)],
  ];
  if (o.minorityInterest > 0) rows.push(['− Minoritários das controladas', millions(-o.minorityInterest)]);
  if (o.postStatementCapital > 0) rows.push(['+ Ações emitidas depois do balanço', millions(o.postStatementCapital)]);
  rows.push(
    ['Valor do patrimônio (VPL)', millions(o.equityValue)],
    ['Seu preço justo por ação', Fmt.money(o.fairValuePerShare)],
    ['Preço justo do motor naquele dia', Fmt.money(r.engineFairValue)],
    ['Preço de mercado naquele dia', Fmt.money(r.marketPrice)],
  );
  if (r.upside !== null) rows.push(['Seu potencial', Fmt.percent(r.upside, { decimals: 1, signed: true })]);
  rows.push(['Avaliação do motor de', Fmt.date(r.engineAsOf)]);
  return rows;
}

