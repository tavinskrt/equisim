import { Tooltip as T } from 'radix-ui';
import type { ReactNode } from 'react';

import { cn } from './cn';

/**
 * Dica flutuante. **Nunca é o único caminho para a informação**: no toque não
 * há hover, então o que importa para decidir vai na tela ou num HintPopover,
 * que abre no toque.
 */
export function Tooltip(props: { content: ReactNode; children: ReactNode; side?: 'top' | 'bottom' | 'left' | 'right'; className?: string }) {
  return (
    <T.Root delayDuration={350}>
      <T.Trigger asChild>{props.children}</T.Trigger>
      <T.Portal>
        <T.Content
          side={props.side ?? 'top'}
          sideOffset={6}
          collisionPadding={12}
          className={cn(
            'z-50 max-w-72 rounded-md border border-line bg-raised px-2.5 py-1.5 text-body-sm text-fg shadow-pop',
            props.className,
          )}
        >
          {props.content}
        </T.Content>
      </T.Portal>
    </T.Root>
  );
}

export const TooltipProvider = T.Provider;
