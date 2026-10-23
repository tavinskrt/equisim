import { AlertTriangle, CheckCircle2, Info, OctagonAlert } from 'lucide-react';
import type { ReactNode } from 'react';

import { cn } from './cn';
import { type Tone, toneBorder, toneSurface } from './tone';

const icons: Partial<Record<Tone, ReactNode>> = {
  caution: <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />,
  negative: <OctagonAlert aria-hidden className="mt-0.5 size-4 shrink-0" />,
  positive: <CheckCircle2 aria-hidden className="mt-0.5 size-4 shrink-0" />,
};

/**
 * Aviso em faixa. O ícone acompanha a cor — estado nunca é só cor — e o
 * papel `status` faz o leitor de tela anunciar o aviso que aparece depois.
 */
export function Banner(props: {
  tone?: Tone;
  icon?: ReactNode;
  title?: ReactNode;
  children: ReactNode;
  action?: ReactNode;
  className?: string;
  live?: boolean;
}) {
  const tone = props.tone ?? 'neutral';
  return (
    <div
      role={props.live ? 'status' : undefined}
      className={cn(
        'flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-body-sm',
        toneSurface[tone],
        toneBorder[tone],
        props.className,
      )}
    >
      {props.icon ?? icons[tone] ?? <Info aria-hidden className="mt-0.5 size-4 shrink-0" />}
      <div className="min-w-0 flex-1">
        {props.title !== undefined && <p className="font-semibold">{props.title}</p>}
        <div className={cn(tone === 'neutral' ? 'text-fg-2' : 'text-fg', 'leading-relaxed')}>{props.children}</div>
      </div>
      {props.action}
    </div>
  );
}
