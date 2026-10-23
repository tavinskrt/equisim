import type { HTMLAttributes, ReactNode } from 'react';

import { cn } from './cn';

/** Cartão: a superfície que agrupa um assunto. */
export function Card({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('rounded-xl border border-line bg-surface shadow-card', className)} {...rest} />;
}

/** Cabeçalho de seção: título, subtítulo e ações à direita. */
export function SectionHeader(props: {
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  as?: 'h2' | 'h3' | 'h4';
  className?: string;
  id?: string;
}) {
  const H = props.as ?? 'h2';
  return (
    <div className={cn('flex items-start gap-3', props.className)}>
      <div className="min-w-0 flex-1">
        <H id={props.id} className="text-title-sm font-semibold text-fg">
          {props.title}
        </H>
        {props.subtitle !== undefined && <p className="mt-0.5 text-body-sm text-fg-2">{props.subtitle}</p>}
      </div>
      {props.actions !== undefined && <div className="-my-2 flex shrink-0 items-center gap-0.5">{props.actions}</div>}
    </div>
  );
}

/** Cartão com cabeçalho e corpo: o formato mais comum das telas. */
export function Panel(props: {
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
  as?: 'h2' | 'h3' | 'h4';
  id?: string;
}) {
  return (
    <Card className={cn('p-4 sm:p-5', props.className)} aria-labelledby={props.id}>
      <SectionHeader title={props.title} subtitle={props.subtitle} actions={props.actions} as={props.as} id={props.id} />
      <div className={cn('mt-4', props.bodyClassName)}>{props.children}</div>
    </Card>
  );
}

/** Linha divisória fina. */
export function Divider({ className }: { className?: string }) {
  return <hr className={cn('border-0 border-t border-divider', className)} />;
}
