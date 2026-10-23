import { Slider as S } from 'radix-ui';
import { useId, type ReactNode } from 'react';

import { cn } from './cn';

/**
 * Controle deslizante com rótulo e valor formatado. O valor também é anunciado
 * formatado (`aria-valuetext`): "R$ 1.500,00", e não "1500".
 */
export function Slider(props: {
  label: ReactNode;
  value: number;
  onChange: (value: number) => void;
  min: number;
  max: number;
  step: number;
  format: (value: number) => string;
  hint?: ReactNode;
  className?: string;
  /** Marca de referência no trilho (ex.: o CDI), em valor do controle. */
  marker?: { value: number; label: string };
}) {
  const id = useId();
  const pct = (v: number) => ((v - props.min) / (props.max - props.min)) * 100;
  return (
    <div className={cn('space-y-2', props.className)}>
      <div className="flex items-baseline justify-between gap-3">
        <label id={id} className="text-body-sm font-medium text-fg-2">
          {props.label}
        </label>
        <output htmlFor={id} className="num text-body font-semibold text-fg">
          {props.format(props.value)}
        </output>
      </div>
      <S.Root
        aria-labelledby={id}
        value={[props.value]}
        min={props.min}
        max={props.max}
        step={props.step}
        onValueChange={(v) => props.onChange(v[0] ?? props.value)}
        className="relative flex h-11 w-full touch-none select-none items-center"
      >
        <S.Track className="relative h-1.5 grow overflow-hidden rounded-full bg-sunken">
          <S.Range className="absolute h-full rounded-full bg-brand" />
        </S.Track>
        {props.marker !== undefined && props.marker.value >= props.min && props.marker.value <= props.max && (
          <span
            aria-hidden
            title={props.marker.label}
            className="pointer-events-none absolute top-1/2 h-3.5 w-0.5 -translate-y-1/2 rounded bg-fg-3"
            style={{ left: `${pct(props.marker.value)}%` }}
          />
        )}
        <S.Thumb
          aria-valuetext={props.format(props.value)}
          className="block size-5 rounded-full border-2 border-brand bg-raised shadow-card transition-transform hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        />
      </S.Root>
      {props.hint !== undefined && <p className="text-caption text-fg-3">{props.hint}</p>}
    </div>
  );
}
