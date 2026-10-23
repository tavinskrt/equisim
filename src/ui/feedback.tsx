import { Loader2 } from 'lucide-react';
import type { ReactNode } from 'react';

import { cn } from './cn';

/** Estado vazio: o que falta e o que fazer. */
export function EmptyState(props: { icon?: ReactNode; title: ReactNode; message?: ReactNode; action?: ReactNode; className?: string }) {
  return (
    <div className={cn('flex flex-col items-center justify-center px-4 py-8 text-center', props.className)}>
      {props.icon !== undefined && (
        <div className="mb-3 flex size-10 items-center justify-center rounded-full bg-sunken text-fg-3" aria-hidden>
          {props.icon}
        </div>
      )}
      <p className="text-body font-semibold text-fg">{props.title}</p>
      {props.message !== undefined && <p className="mt-1 max-w-sm text-body-sm text-fg-2">{props.message}</p>}
      {props.action !== undefined && <div className="mt-4">{props.action}</div>}
    </div>
  );
}

/** Espaço reservado com a geometria do conteúdo final, para a linha não saltar. */
export function Skeleton({ className, label }: { className?: string; label?: string }) {
  return <span role={label ? 'status' : undefined} aria-label={label} className={cn('skeleton inline-block h-4', className)} />;
}

export function Spinner({ className, label = 'Carregando' }: { className?: string; label?: string }) {
  return (
    <span role="status" aria-label={label} className="inline-flex">
      <Loader2 aria-hidden className={cn('size-4 animate-spin text-fg-3', className)} />
    </span>
  );
}
