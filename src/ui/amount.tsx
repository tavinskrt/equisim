import type { HTMLAttributes } from 'react';

import { cn } from './cn';
import { type Tone, toneText } from './tone';

/**
 * Número com papel: cifra tabular e a cor do sentido. **A cor não é a única
 * pista** — o sinal ("+", "−") vai no próprio texto, formatado pelo `Fmt`.
 */
export function Amount({
  tone = 'neutral',
  className,
  ...rest
}: HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return <span className={cn('num', toneText[tone], className)} {...rest} />;
}
