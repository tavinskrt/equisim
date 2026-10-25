import { CircleHelp } from 'lucide-react';
import { Popover } from 'radix-ui';
import type { ReactNode } from 'react';

import { cn } from './cn';

export interface HintEntry {
  readonly term: string;
  readonly meaning: ReactNode;
}

/**
 * O glossário no ponto de uso: um "?" que abre no **toque** e no clique — ao
 * contrário da dica flutuante, que no celular não existe.
 */
export function HintPopover(props: {
  title: string;
  intro?: ReactNode;
  entries?: readonly HintEntry[];
  children?: ReactNode;
  className?: string;
  /** Rótulo acessível; padrão: "Explicar: <título>". */
  label?: string;
  size?: 'sm' | 'md';
}) {
  return (
    <Popover.Root>
      <Popover.Trigger asChild>
        <button
          type="button"
          aria-label={props.label ?? `Explicar: ${props.title}`}
          className={cn(
            'inline-flex shrink-0 items-center justify-center rounded-full text-fg-3 transition-colors hover:text-fg data-[state=open]:text-brand',
            // Alvo de 44 px com o desenho pequeno: a margem negativa evita que
            // o alvo empurre a linha onde o ícone mora.
            props.size === 'md' ? 'size-11' : '-m-3 size-10',
            props.className,
          )}
        >
          <CircleHelp aria-hidden className={props.size === 'md' ? 'size-[18px]' : 'size-[15px]'} />
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content
          sideOffset={4}
          collisionPadding={12}
          className="z-50 max-h-[min(70vh,520px)] w-[min(92vw,380px)] overflow-y-auto rounded-xl border border-line bg-raised p-4 text-body-sm shadow-pop scrollbar-thin"
        >
          <p className="text-title-sm font-semibold text-fg">{props.title}</p>
          {props.intro !== undefined && <div className="mt-1.5 leading-relaxed text-fg-2">{props.intro}</div>}
          {props.entries !== undefined && props.entries.length > 0 && (
            <dl className="mt-3 space-y-2.5">
              {props.entries.map((e) => (
                <div key={e.term}>
                  <dt className="font-semibold text-fg">{e.term}</dt>
                  <dd className="mt-0.5 leading-relaxed text-fg-2">{e.meaning}</dd>
                </div>
              ))}
            </dl>
          )}
          {props.children}
          <Popover.Arrow className="fill-raised" />
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
