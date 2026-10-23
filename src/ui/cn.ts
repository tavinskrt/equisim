import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

/**
 * Junta classes e resolve conflito do Tailwind: `cn('px-2', cond && 'px-4')`
 * fica com `px-4`. Sem o `twMerge`, a ordem no CSS gerado decidiria — e ela
 * não é a ordem em que as classes foram escritas.
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
