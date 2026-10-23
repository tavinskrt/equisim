import { DropdownMenu as M } from 'radix-ui';
import type { ReactNode } from 'react';

import { cn } from './cn';

export const Menu = M.Root;
export const MenuTrigger = M.Trigger;

export function MenuContent({ children, align = 'end' }: { children: ReactNode; align?: 'start' | 'end' }) {
  return (
    <M.Portal>
      <M.Content
        align={align}
        sideOffset={6}
        collisionPadding={12}
        className="z-50 min-w-56 rounded-xl border border-line bg-raised p-1 shadow-pop"
      >
        {children}
      </M.Content>
    </M.Portal>
  );
}

export function MenuItem(props: { icon?: ReactNode; children: ReactNode; onSelect: () => void; tone?: 'danger'; hint?: ReactNode }) {
  return (
    <M.Item
      onSelect={props.onSelect}
      className={cn(
        'flex min-h-11 cursor-pointer select-none items-center gap-2.5 rounded-lg px-2.5 text-body-sm outline-none data-[highlighted]:bg-sunken',
        props.tone === 'danger' ? 'text-negative' : 'text-fg',
      )}
    >
      <span className="text-fg-3 [&>svg]:size-4" aria-hidden>
        {props.icon}
      </span>
      <span className="min-w-0 flex-1">{props.children}</span>
      {props.hint !== undefined && <span className="text-caption text-fg-3">{props.hint}</span>}
    </M.Item>
  );
}

export function MenuLabel({ children }: { children: ReactNode }) {
  return <M.Label className="px-2.5 pb-1 pt-2 text-caption text-fg-3">{children}</M.Label>;
}

export function MenuSeparator() {
  return <M.Separator className="my-1 h-px bg-divider" />;
}
