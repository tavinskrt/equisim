import { ChevronDown, LineChart } from 'lucide-react';
import { Collapsible } from 'radix-ui';
import { useState } from 'react';

import { type BaseNormalization, BaseNormalizationOutcome } from '../../core';
import { Fmt, NormalizationCopy } from '../../copy';
import { Badge } from '../../ui/badge';
import { Banner } from '../../ui/banner';
import { cn } from '../../ui/cn';
import type { Tone } from '../../ui/tone';

/**
 * A normalização do lucro de partida: **o motor usou o último exercício, ou o
 * corrigiu pelo ciclo?** Abre sozinha quando houve correção, que é quando a
 * pergunta importa.
 */
export function NormalizationPanel({ normalization: n, editable = false }: { normalization: BaseNormalization; editable?: boolean }) {
  const outcome = n.outcome;
  const [open, setOpen] = useState(
    outcome === BaseNormalizationOutcome.upward ||
      outcome === BaseNormalizationOutcome.downward ||
      outcome === BaseNormalizationOutcome.rebuilt,
  );
  const tone: Tone =
    outcome === BaseNormalizationOutcome.upward
      ? 'positive'
      : outcome === BaseNormalizationOutcome.downward
        ? 'negative'
        : outcome === BaseNormalizationOutcome.healthLocked || outcome === BaseNormalizationOutcome.rebuilt
          ? 'caution'
          : 'neutral';
  const test = NormalizationCopy.test(n);
  const account = NormalizationCopy.account(n);
  const warnings = NormalizationCopy.warnings(n);

  return (
    <Collapsible.Root open={open} onOpenChange={setOpen} className="rounded-xl border border-line bg-sunken">
      <Collapsible.Trigger className="flex min-h-12 w-full items-center gap-3 rounded-xl p-3 text-left">
        <LineChart aria-hidden className="size-[18px] shrink-0 text-positive" />
        <span className="min-w-0 flex-1">
          <span className="block text-body-sm font-semibold text-fg">{NormalizationCopy.question(n)}</span>
          <Badge tone={tone} className="mt-1">
            {NormalizationCopy.badge(n)}
          </Badge>
        </span>
        <ChevronDown aria-hidden className={cn('size-4 shrink-0 text-fg-2 transition-transform', open && 'rotate-180')} />
      </Collapsible.Trigger>
      <Collapsible.Content className="space-y-3 px-3 pb-3 text-body-sm">
        <p className="text-fg">{NormalizationCopy.answer(n)}</p>
        <p className="text-caption text-fg-2">{NormalizationCopy.rule(n)}</p>
        {n.cycleWindow.length > 0 && n.latestReturn !== null && <CycleBars n={n} />}
        {test !== null && <p className="text-caption text-fg">{test}</p>}
        {account !== null && <p className="text-caption text-fg">{account}</p>}
        {warnings.map((w, i) => (
          <Banner key={i}>{w}</Banner>
        ))}
        <p className="text-caption text-fg-3">
          {editable
            ? 'Discorda do motor? Digite o lucro que quiser no campo acima — ou use o do último exercício.'
            : 'Discorda do motor? Em “Simular minhas premissas”, digite o lucro que quiser — ou use o do último exercício.'}
        </p>
      </Collapsible.Content>
    </Collapsible.Root>
  );
}

/** O retorno de cada ano do ciclo, o do último exercício e o típico — em barras a partir do zero. */
function CycleBars({ n }: { n: BaseNormalization }) {
  const typical = n.cycleReturn;
  const last = n.latestReturn!;
  const values = [...n.cycleWindow.map((p) => p.value), last, ...(typical === null ? [] : [typical])];
  const lo = Math.min(0, ...values);
  const hi = Math.max(lo + 1e-9, ...values) * 1.08;
  const pos = (v: number) => Math.min(Math.max((v - lo) / (hi - lo), 0), 1) * 100;
  const name = NormalizationCopy.returnRate(n.lane);
  const rows = [
    ...n.cycleWindow.map((p) => ({ label: String(p.year), value: p.value, highlight: false })),
    { label: NormalizationCopy.period(n), value: last, highlight: true },
  ];
  return (
    <figure>
      <figcaption className="mb-1.5 text-caption text-fg-2">
        {name.charAt(0).toUpperCase() + name.slice(1)}, ano a ano
      </figcaption>
      <table className="w-full border-separate border-spacing-y-1">
        <caption className="sr-only">
          O {name} de cada ano; último exercício destacado; típico (mediana){' '}
          {typical === null ? 'sem medida' : Fmt.percent(typical, { decimals: 1 })}.
        </caption>
        <tbody>
          {rows.map((r, i) => {
            const zero = pos(0);
            const tip = pos(r.value);
            return (
              <tr key={`${r.label}-${i}`} className={cn(r.highlight && 'font-semibold')}>
                <th scope="row" className={cn('num w-12 text-left text-caption font-normal', r.highlight ? 'font-bold text-fg' : 'text-fg-2')}>
                  {r.label}
                </th>
                <td>
                  <div className="relative h-3.5" aria-hidden>
                    <div
                      className="absolute inset-y-0.5 rounded-[3px]"
                      style={{
                        left: `${Math.min(zero, tip)}%`,
                        width: `${Math.max(Math.abs(tip - zero), 0.8)}%`,
                        background: r.highlight
                          ? 'var(--brand)'
                          : r.value < 0
                            ? 'color-mix(in oklab, var(--negative) 60%, transparent)'
                            : 'var(--border-strong)',
                      }}
                    />
                    {typical !== null && (
                      <div className="absolute inset-y-0 w-0.5 -translate-x-1/2 bg-positive" style={{ left: `${pos(typical)}%` }} />
                    )}
                  </div>
                </td>
                <td className={cn('num w-16 text-right text-caption', r.highlight ? 'font-bold text-fg' : 'text-fg-2')}>
                  {Fmt.percent(r.value, { decimals: 1 })}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-caption text-fg-2" aria-hidden>
        <span className="inline-flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm bg-line-strong" /> anos do ciclo
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm bg-brand" /> último exercício
        </span>
        {typical !== null && (
          <span className="inline-flex items-center gap-1.5">
            <span className="h-2.5 w-0.5 bg-positive" /> típico (mediana): {Fmt.percent(typical, { decimals: 1 })}
          </span>
        )}
      </div>
    </figure>
  );
}
