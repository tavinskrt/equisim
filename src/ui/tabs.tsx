import { Tabs as T } from 'radix-ui';
import type { ReactNode } from 'react';

import { cn } from './cn';

export const Tabs = T.Root;
export const TabPanel = T.Content;

/** Abas sublinhadas, roláveis na horizontal quando não cabem. */
export function TabList(props: { items: readonly { value: string; label: ReactNode }[]; label: string; className?: string }) {
  return (
    <T.List aria-label={props.label} className={cn('flex gap-1 overflow-x-auto border-b border-divider scrollbar-thin', props.className)}>
      {props.items.map((i) => (
        <T.Trigger
          key={i.value}
          value={i.value}
          className="relative min-h-11 shrink-0 px-3 text-body-sm font-medium text-fg-2 transition-colors hover:text-fg data-[state=active]:text-fg data-[state=active]:after:absolute data-[state=active]:after:inset-x-2 data-[state=active]:after:-bottom-px data-[state=active]:after:h-0.5 data-[state=active]:after:rounded-full data-[state=active]:after:bg-brand"
        >
          {i.label}
        </T.Trigger>
      ))}
    </T.List>
  );
}
