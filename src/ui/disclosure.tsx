import { ChevronDown } from 'lucide-react';
import { Collapsible } from 'radix-ui';
import { type ReactNode, useState } from 'react';

import { cn } from './cn';

/** Seção recolhível: o detalhe que nem todo leitor quer, a um toque. */
export function Disclosure(props: {
  title: ReactNode;
  summary?: ReactNode;
  children: ReactNode;
  defaultOpen?: boolean;
  className?: string;
  trailing?: ReactNode;
}) {
  const [open, setOpen] = useState(props.defaultOpen ?? false);
  return (
    <Collapsible.Root open={open} onOpenChange={setOpen} className={cn('rounded-xl border border-line bg-surface', props.className)}>
      <div className="flex items-center gap-1 pr-2">
        <Collapsible.Trigger className="flex min-h-12 flex-1 items-center gap-2 rounded-xl px-4 py-2.5 text-left">
          <ChevronDown aria-hidden className={cn('size-4 shrink-0 text-fg-3 transition-transform', open && 'rotate-180')} />
          <span className="min-w-0 flex-1">
            <span className="block text-body font-semibold text-fg">{props.title}</span>
            {props.summary !== undefined && <span className="mt-0.5 block text-body-sm text-fg-2">{props.summary}</span>}
          </span>
        </Collapsible.Trigger>
        {props.trailing}
      </div>
      <Collapsible.Content className="px-4 pb-4">{props.children}</Collapsible.Content>
    </Collapsible.Root>
  );
}
