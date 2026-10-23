import { cn } from './cn';

/** O símbolo do Equisim: a curva que sobe, sobre o verde da marca. */
export function Logo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" aria-hidden className={cn('size-8', className)}>
      <rect width="32" height="32" rx="9" fill="var(--brand)" />
      <path d="M7 21.5l5.5-5.5 4 3.5L25 11" fill="none" stroke="var(--on-brand)" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="25" cy="11" r="2.2" fill="var(--on-brand)" />
    </svg>
  );
}
