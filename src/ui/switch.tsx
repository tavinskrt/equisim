import { Switch as S } from 'radix-ui';
import { useId, type ReactNode } from 'react';

import { cn } from './cn';

/** Interruptor com rótulo e descrição; a linha inteira é o alvo. */
export function Switch(props: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: ReactNode;
  description?: ReactNode;
  disabled?: boolean;
  className?: string;
}) {
  const id = useId();
  return (
    <div className={cn('flex items-start gap-3', props.className)}>
      <div className="min-w-0 flex-1">
        <label htmlFor={id} className="block cursor-pointer text-body font-medium text-fg">
          {props.label}
        </label>
        {props.description !== undefined && (
          <p id={`${id}-d`} className="mt-0.5 text-body-sm text-fg-2">
            {props.description}
          </p>
        )}
      </div>
      <S.Root
        id={id}
        checked={props.checked}
        onCheckedChange={props.onChange}
        disabled={props.disabled}
        aria-describedby={props.description !== undefined ? `${id}-d` : undefined}
        className="relative mt-0.5 inline-flex h-6 w-10 shrink-0 items-center rounded-full border border-line-strong bg-sunken transition-colors data-[state=checked]:border-brand data-[state=checked]:bg-brand disabled:opacity-50"
      >
        <S.Thumb className="block size-[18px] translate-x-[2px] rounded-full bg-fg-2 shadow transition-transform data-[state=checked]:translate-x-[18px] data-[state=checked]:bg-white" />
      </S.Root>
    </div>
  );
}
