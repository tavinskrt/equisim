import { ToggleGroup } from 'radix-ui';
import { type ReactNode, useLayoutEffect, useRef, useState } from 'react';

import { cn } from './cn';
import { m } from './motion';

export interface SegmentOption<T extends string> {
  readonly value: T;
  readonly label: ReactNode;
  /** Rótulo acessível quando o visível é só ícone. */
  readonly ariaLabel?: string;
}

interface Plate {
  readonly x: number;
  readonly width: number;
}

/**
 * Controle segmentado: escolha única entre poucas opções, todas visíveis.
 *
 * A placa da opção escolhida **desliza** até a nova escolha (decisão 155, a
 * ideia do Smooth Tab da Kokonut UI), em vez de sumir de uma e acender na
 * outra: o olho acompanha o que mudou. Enquanto a placa não foi medida — na
 * primeira pintura, ou num ambiente sem layout —, a opção escolhida pinta o
 * próprio fundo, e o controle nunca fica sem a marca da escolha.
 */
export function Segmented<T extends string>(props: {
  value: T;
  onChange: (value: T) => void;
  options: readonly SegmentOption<T>[];
  label: string;
  size?: 'sm' | 'md';
  className?: string;
}) {
  const root = useRef<HTMLDivElement>(null);
  const [plate, setPlate] = useState<Plate | null>(null);

  useLayoutEffect(() => {
    const el = root.current;
    if (el === null) return;
    const measure = () => {
      const on = el.querySelector<HTMLElement>('[data-state="on"]');
      if (on === null || on.offsetWidth === 0) {
        setPlate(null);
        return;
      }
      setPlate({ x: on.offsetLeft, width: on.offsetWidth });
    };
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, [props.value, props.options.length]);

  return (
    <ToggleGroup.Root
      ref={root}
      type="single"
      value={props.value}
      onValueChange={(v) => {
        // O Radix devolve vazio ao clicar no já selecionado; aqui sempre há um.
        if (v !== '') props.onChange(v as T);
      }}
      aria-label={props.label}
      className={cn('relative inline-flex rounded-lg border border-line bg-sunken p-0.5', props.className)}
    >
      {plate !== null && (
        <m.span
          aria-hidden
          className="pointer-events-none absolute inset-y-0.5 left-0 rounded-md bg-raised shadow-card"
          // Sem estado inicial: a placa nasce no lugar, e só as trocas animam.
          initial={false}
          animate={{ x: plate.x, width: plate.width }}
          transition={{ type: 'spring', stiffness: 520, damping: 40, mass: 0.8 }}
        />
      )}
      {props.options.map((o) => (
        <ToggleGroup.Item
          key={o.value}
          value={o.value}
          aria-label={o.ariaLabel}
          className={cn(
            'relative inline-flex items-center justify-center gap-1.5 rounded-md px-3 font-medium text-fg-2 transition-colors hover:text-fg',
            'data-[state=on]:text-fg',
            plate === null && 'data-[state=on]:bg-raised data-[state=on]:shadow-card',
            props.size === 'sm' ? 'min-h-8 text-body-sm' : 'min-h-10 text-body-sm',
          )}
        >
          {o.label}
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}
