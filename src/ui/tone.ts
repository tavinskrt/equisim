import type { Trend } from '../copy';

/**
 * O papel semântico de uma cor. **Cor de estado nunca vai sozinha**: quem a
 * usa leva também ícone ou rótulo (WCAG 1.4.1), e as cores são reservadas —
 * `positive` não vira "série 4" num gráfico.
 */
export type Tone = Trend | 'pending' | 'blocked' | 'reserve' | 'brand';

export const toneText: Record<Tone, string> = {
  positive: 'text-positive',
  negative: 'text-negative',
  caution: 'text-caution',
  neutral: 'text-fg',
  pending: 'text-pending',
  blocked: 'text-blocked',
  reserve: 'text-reserve dark:text-reserve-muted',
  brand: 'text-brand',
};

/** Superfície tingida + texto do mesmo papel: os pares medidos em 4,5:1 ou mais. */
export const toneSurface: Record<Tone, string> = {
  positive: 'bg-positive-surface text-positive',
  negative: 'bg-negative-surface text-negative',
  caution: 'bg-caution-surface text-caution',
  neutral: 'bg-sunken text-fg-2',
  pending: 'bg-pending-surface text-pending',
  blocked: 'bg-sunken text-blocked',
  reserve: 'bg-reserve-surface text-reserve dark:text-reserve-muted',
  brand: 'bg-brand-surface text-positive',
};

export const toneBorder: Record<Tone, string> = {
  positive: 'border-positive/40',
  negative: 'border-negative/40',
  caution: 'border-caution/40',
  neutral: 'border-line',
  pending: 'border-pending/40',
  blocked: 'border-line',
  reserve: 'border-reserve/40',
  brand: 'border-brand/40',
};
