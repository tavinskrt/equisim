import { ToggleGroup } from 'radix-ui';
import type { ReactNode } from 'react';

import { cn } from './cn';

export interface SegmentOption<T extends string> {
  readonly value: T;
  readonly label: ReactNode;
  /** Rótulo acessível quando o visível é só ícone. */
  readonly ariaLabel?: string;
}

/** Controle segmentado: escolha única entre poucas opções, todas visíveis. */
export function Segmented<T extends string>(props: {
  value: T;
  onChange: (value: T) => void;
  options: readonly SegmentOption<T>[];
  label: string;
  size?: 'sm' | 'md';
  className?: string;
}) {
  return (
    <ToggleGroup.Root
      type="single"
      value={props.value}
      onValueChange={(v) => {
        // O Radix devolve vazio ao clicar no já selecionado; aqui sempre há um.
        if (v !== '') props.onChange(v as T);
      }}
      aria-label={props.label}
      className={cn('inline-flex rounded-lg border border-line bg-sunken p-0.5', props.className)}
    >
      {props.options.map((o) => (
        <ToggleGroup.Item
          key={o.value}
          value={o.value}
          aria-label={o.ariaLabel}
          className={cn(
            'inline-flex items-center justify-center gap-1.5 rounded-md px-3 font-medium text-fg-2 transition-colors hover:text-fg',
            'data-[state=on]:bg-raised data-[state=on]:text-fg data-[state=on]:shadow-card',
            props.size === 'sm' ? 'min-h-8 text-body-sm' : 'min-h-10 text-body-sm',
          )}
        >
          {o.label}
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}
