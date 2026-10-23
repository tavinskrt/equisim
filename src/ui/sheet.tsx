import { X } from 'lucide-react';
import { Dialog as D } from 'radix-ui';
import type { ReactNode } from 'react';

import { IconButton } from './button';
import { cn } from './cn';

/**
 * Painel sobreposto: **desliza da direita** a partir de 768 px e **sobe de
 * baixo** abaixo disso, onde a lateral espremeria o conteúdo. É a casa do
 * Raio-X do ativo e das listas de escolha.
 */
export function Sheet(props: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: ReactNode;
  description?: ReactNode;
  /** Ações à direita do título, antes do fechar. */
  actions?: ReactNode;
  children: ReactNode;
  /** Largura no desktop. */
  width?: 'md' | 'lg' | 'xl';
  /** Rodapé fixo — no celular, a faixa do resultado. */
  footer?: ReactNode;
  className?: string;
}) {
  const width = { md: 'md:w-[min(100vw,480px)]', lg: 'md:w-[min(100vw,640px)]', xl: 'md:w-[min(100vw,820px)]' }[
    props.width ?? 'lg'
  ];
  return (
    <D.Root open={props.open} onOpenChange={props.onOpenChange}>
      <D.Portal>
        <D.Overlay className="fixed inset-0 z-40 bg-black/45 data-[state=closed]:animate-[overlay-out_160ms_ease-in] data-[state=open]:animate-[overlay-in_180ms_ease-out]" />
        <D.Content
          className={cn(
            'fixed z-50 flex flex-col border-line bg-canvas shadow-pop outline-none',
            'max-md:inset-x-0 max-md:bottom-0 max-md:max-h-[92dvh] max-md:rounded-t-2xl max-md:border-t',
            'max-md:data-[state=closed]:animate-[sheet-up-out_180ms_ease-in] max-md:data-[state=open]:animate-[sheet-up-in_240ms_cubic-bezier(0.2,0.8,0.2,1)]',
            'md:inset-y-0 md:right-0 md:border-l',
            'md:data-[state=closed]:animate-[sheet-right-out_180ms_ease-in] md:data-[state=open]:animate-[sheet-right-in_240ms_cubic-bezier(0.2,0.8,0.2,1)]',
            width,
            props.className,
          )}
        >
          <div className="mx-auto mt-2 h-1 w-9 rounded-full bg-line-strong md:hidden" aria-hidden />
          <header className="flex items-start gap-2 border-b border-divider px-4 py-3 sm:px-5">
            <div className="min-w-0 flex-1 py-1.5">
              <D.Title className="truncate text-title-sm font-semibold text-fg">{props.title}</D.Title>
              {props.description !== undefined ? (
                <D.Description className="mt-0.5 text-body-sm text-fg-2">{props.description}</D.Description>
              ) : (
                <D.Description className="sr-only">{props.title}</D.Description>
              )}
            </div>
            {props.actions}
            <D.Close asChild>
              <IconButton label="Fechar">
                <X className="size-[18px]" aria-hidden />
              </IconButton>
            </D.Close>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain scrollbar-thin">{props.children}</div>
          {props.footer !== undefined && (
            <div className="safe-bottom border-t border-divider bg-surface px-4 py-2.5 sm:px-5">{props.footer}</div>
          )}
        </D.Content>
      </D.Portal>
    </D.Root>
  );
}
