import { Slot } from 'radix-ui';
import { type ButtonHTMLAttributes, forwardRef, type ReactNode } from 'react';

import { cn } from './cn';
import { Tooltip } from './tooltip';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'reserve';
type Size = 'sm' | 'md' | 'lg';

const variants: Record<Variant, string> = {
  // O verde da marca é **só preenchimento**: no claro ele não chega a 4,5:1
  // sobre o branco, e o texto sobre ele usa `on-brand` — tinta escura nos dois
  // temas (6,15:1 no claro, 7,96:1 no escuro).
  primary: 'bg-brand text-on-brand hover:brightness-110 active:brightness-95 font-semibold',
  secondary: 'bg-surface text-fg border border-line hover:border-line-strong hover:bg-raised',
  ghost: 'text-fg-2 hover:text-fg hover:bg-sunken',
  danger: 'bg-negative-surface text-negative border border-negative/30 hover:border-negative/60 font-semibold',
  reserve: 'bg-reserve-surface text-reserve dark:text-reserve-muted border border-reserve/30 hover:border-reserve/60 font-semibold',
};

// A altura mínima de 44 px é a do alvo de toque (WCAG 2.5.5); `sm` mantém o
// alvo pelo `min-h` e encolhe só o desenho.
const sizes: Record<Size, string> = {
  sm: 'min-h-9 px-3 text-body-sm gap-1.5 rounded-lg',
  md: 'min-h-11 px-4 text-body gap-2 rounded-lg',
  lg: 'min-h-12 px-5 text-body gap-2 rounded-xl',
};

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  asChild?: boolean;
  icon?: ReactNode;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'secondary', size = 'md', asChild = false, icon, className, children, type, ...rest },
  ref,
) {
  const Comp = asChild ? Slot.Root : 'button';
  return (
    <Comp
      ref={ref}
      type={asChild ? undefined : (type ?? 'button')}
      className={cn(
        'inline-flex select-none items-center justify-center whitespace-nowrap transition-[background,border-color,color,filter] duration-150 disabled:opacity-50',
        variants[variant],
        sizes[size],
        className,
      )}
      {...rest}
    >
      {asChild ? (
        children
      ) : (
        <>
          {icon}
          {children}
        </>
      )}
    </Comp>
  );
});

export interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /** Nome acessível **e** dica visual: botão só de ícone precisa dos dois. */
  label: string;
  tone?: 'default' | 'brand' | 'danger' | 'reserve';
  /** Sem a dica flutuante — quando o rótulo já está visível ao lado. */
  bare?: boolean;
}

const iconTones = {
  default: 'text-fg-2 hover:text-fg',
  brand: 'text-brand hover:brightness-110',
  danger: 'text-fg-3 hover:text-negative',
  reserve: 'text-reserve dark:text-reserve-muted hover:brightness-110',
};

/** Botão de ícone com alvo de 44 × 44 px, qualquer que seja o tamanho do ícone. */
export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { label, tone = 'default', bare = false, className, children, type, ...rest },
  ref,
) {
  const button = (
    <button
      ref={ref}
      type={type ?? 'button'}
      aria-label={label}
      className={cn(
        'inline-flex size-11 shrink-0 items-center justify-center rounded-lg transition-colors hover:bg-sunken disabled:opacity-40',
        iconTones[tone],
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
  return bare ? button : <Tooltip content={label}>{button}</Tooltip>;
});
