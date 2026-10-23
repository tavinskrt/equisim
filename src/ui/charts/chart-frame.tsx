import { BarChart3, Table2 } from 'lucide-react';
import { type ReactNode, useState } from 'react';

import { Card } from '../card';
import { cn } from '../cn';
import { Segmented } from '../segmented';

export interface LegendItem {
  readonly key: string;
  readonly label: string;
  readonly color: string;
  /** Traço tracejado na legenda, quando a série é tracejada. */
  readonly dashed?: boolean;
  /** Forma do marcador, para o gráfico de dispersão (codificação redundante). */
  readonly shape?: 'line' | 'circle' | 'square' | 'diamond';
}

/** A legenda: sempre presente com duas séries ou mais — identidade nunca é só cor. */
export function Legend({ items, className }: { items: readonly LegendItem[]; className?: string }) {
  return (
    <ul className={cn('flex flex-wrap gap-x-4 gap-y-1.5 text-caption text-fg-2', className)}>
      {items.map((i) => (
        <li key={i.key} className="inline-flex items-center gap-1.5">
          <LegendSwatch item={i} />
          {i.label}
        </li>
      ))}
    </ul>
  );
}

function LegendSwatch({ item }: { item: LegendItem }) {
  const shape = item.shape ?? 'line';
  if (shape === 'line') {
    return (
      <svg width="16" height="8" aria-hidden className="shrink-0">
        <line x1="1" y1="4" x2="15" y2="4" stroke={item.color} strokeWidth="2" strokeDasharray={item.dashed ? '3 2' : undefined} strokeLinecap="round" />
      </svg>
    );
  }
  return (
    <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden className="shrink-0">
      {shape === 'circle' && <circle cx="5" cy="5" r="4" fill={item.color} />}
      {shape === 'square' && <rect x="1" y="1" width="8" height="8" rx="1.5" fill={item.color} />}
      {shape === 'diamond' && <path d="M5 0.5 9.5 5 5 9.5 0.5 5Z" fill={item.color} />}
    </svg>
  );
}

/**
 * A moldura de um gráfico: título, legenda e **a alternância para tabela**.
 * A tabela é a via de quem não enxerga a cor, de quem imprime e de quem quer
 * o número exato — o gráfico mostra a forma, a tabela mostra o valor.
 */
export function ChartFrame(props: {
  title: ReactNode;
  subtitle?: ReactNode;
  legend?: readonly LegendItem[];
  actions?: ReactNode;
  chart: ReactNode;
  table: ReactNode;
  footer?: ReactNode;
  className?: string;
  /** Altura do gráfico; a tabela rola dentro da mesma área. */
  height?: number;
}) {
  const [view, setView] = useState<'chart' | 'table'>('chart');
  return (
    <Card className={cn('p-4 sm:p-5', props.className)}>
      <div className="flex flex-wrap items-start gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="text-title-sm font-semibold text-fg">{props.title}</h2>
          {props.subtitle !== undefined && <p className="mt-0.5 text-body-sm text-fg-2">{props.subtitle}</p>}
        </div>
        <div className="flex items-center gap-1">
          {props.actions}
          <Segmented
            size="sm"
            label="Ver como"
            value={view}
            onChange={setView}
            options={[
              { value: 'chart', label: <BarChart3 aria-hidden className="size-4" />, ariaLabel: 'Gráfico' },
              { value: 'table', label: <Table2 aria-hidden className="size-4" />, ariaLabel: 'Tabela' },
            ]}
          />
        </div>
      </div>
      {props.legend !== undefined && props.legend.length > 1 && view === 'chart' && <Legend items={props.legend} className="mt-3" />}
      <div className="mt-3" style={view === 'chart' && props.height !== undefined ? { height: props.height } : undefined}>
        {view === 'chart' ? props.chart : <div className="max-h-[420px] overflow-auto scrollbar-thin">{props.table}</div>}
      </div>
      {props.footer !== undefined && <div className="mt-3 text-caption text-fg-3">{props.footer}</div>}
    </Card>
  );
}

/** A caixa do tooltip: valores em tinta de texto, e o traço colorido carrega a identidade. */
export function TooltipBox(props: { title: ReactNode; rows: readonly { key: string; label: string; value: string; color?: string }[] }) {
  return (
    <div className="min-w-44 rounded-lg border border-line bg-raised px-3 py-2 text-body-sm shadow-pop">
      <p className="mb-1 text-caption font-semibold text-fg-2">{props.title}</p>
      <ul className="space-y-0.5">
        {props.rows.map((r) => (
          <li key={r.key} className="flex items-center gap-2">
            {r.color !== undefined && <span aria-hidden className="h-0.5 w-3 rounded" style={{ background: r.color }} />}
            <span className="flex-1 text-fg-2">{r.label}</span>
            <span className="num font-semibold text-fg">{r.value}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Estilo comum dos eixos: tinta terciária, sem linha de eixo, sem marca. */
export const axisProps = {
  tick: { fill: 'var(--fg-3)', fontSize: 11 },
  axisLine: false,
  tickLine: false,
} as const;

/** Tabela simples de dados de gráfico. */
export function DataTable(props: { caption: string; columns: readonly string[]; rows: readonly (readonly string[])[] }) {
  return (
    <table className="w-full text-body-sm">
      <caption className="sr-only">{props.caption}</caption>
      <thead className="sticky top-0 bg-surface">
        <tr className="border-b border-divider">
          {props.columns.map((c, i) => (
            <th key={c} scope="col" className={cn('px-2 py-2 text-caption font-medium text-fg-2', i === 0 ? 'text-left' : 'text-right')}>
              {c}
            </th>
          ))}
        </tr>
      </thead>
      <tbody className="num">
        {props.rows.map((r, ri) => (
          <tr key={ri} className="border-b border-divider last:border-0">
            {r.map((v, i) => (
              <td key={i} className={cn('whitespace-nowrap px-2 py-1.5', i === 0 ? 'text-left text-fg-2' : 'text-right text-fg')}>
                {v}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
