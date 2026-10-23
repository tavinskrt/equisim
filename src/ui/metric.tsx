import type { ReactNode } from 'react';

import { cn } from './cn';
import { type Tone, toneText } from './tone';

/** Número de destaque com rótulo e nota: a peça das faixas de métricas. */
export function Metric(props: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  tone?: Tone;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
  /** Glossário ao lado do rótulo. */
  help?: ReactNode;
}) {
  const size = { sm: 'text-title-sm', md: 'text-num-lg', lg: 'text-display' }[props.size ?? 'md'];
  return (
    <div className={cn('min-w-0', props.className)}>
      <div className="flex items-center gap-1">
        <p className="eyebrow truncate">{props.label}</p>
        {props.help}
      </div>
      <p className={cn('num mt-1 font-semibold tracking-tight', size, toneText[props.tone ?? 'neutral'])}>{props.value}</p>
      {props.hint !== undefined && <p className="mt-0.5 text-caption text-fg-3">{props.hint}</p>}
    </div>
  );
}

/** Faixa de métricas: quebra em grade estreita, linha em tela larga. */
export function MetricRow({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('grid grid-cols-2 gap-x-4 gap-y-4 sm:grid-cols-[repeat(auto-fit,minmax(140px,1fr))]', className)}>{children}</div>;
}

/** Par rótulo-valor em linha, para listas de premissas. */
export function KeyValue(props: { label: ReactNode; value: ReactNode; hint?: ReactNode; tone?: Tone; className?: string }) {
  return (
    <div className={cn('flex items-baseline justify-between gap-3 py-1.5', props.className)}>
      <div className="min-w-0">
        <p className="text-body-sm text-fg-2">{props.label}</p>
        {props.hint !== undefined && <p className="text-caption text-fg-3">{props.hint}</p>}
      </div>
      <p className={cn('num shrink-0 text-right text-body-sm font-semibold', toneText[props.tone ?? 'neutral'])}>{props.value}</p>
    </div>
  );
}
