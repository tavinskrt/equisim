import type { ReactNode } from 'react';

import { cn } from './cn';
import { type Tone, toneSurface } from './tone';

/** Pastilha de estado: superfície tingida, texto do mesmo papel e, de preferência, ícone. */
export function Badge(props: { tone?: Tone; icon?: ReactNode; children: ReactNode; className?: string; title?: string }) {
  return (
    <span
      title={props.title}
      className={cn(
        'inline-flex max-w-full items-center gap-1 rounded-full px-2 py-0.5 text-label font-semibold',
        toneSurface[props.tone ?? 'neutral'],
        props.className,
      )}
    >
      {props.icon}
      <span className="truncate">{props.children}</span>
    </span>
  );
}
