import { X } from 'lucide-react';
import { Dialog as D } from 'radix-ui';
import type { ReactNode } from 'react';

import { Button, IconButton } from './button';
import { cn } from './cn';

/** Caixa de diálogo centrada, para escolhas curtas. */
export function Dialog(props: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
  footer?: ReactNode;
  className?: string;
}) {
  return (
    <D.Root open={props.open} onOpenChange={props.onOpenChange}>
      <D.Portal>
        <D.Overlay className="fixed inset-0 z-40 bg-black/50 backdrop-blur-[2px] data-[state=closed]:animate-[overlay-out_140ms_ease-in] data-[state=open]:animate-[overlay-in_160ms_ease-out]" />
        <D.Content
          className={cn(
            'fixed left-1/2 top-1/2 z-50 max-h-[88dvh] w-[min(calc(100vw-32px),520px)] -translate-x-1/2 -translate-y-1/2 overflow-y-auto rounded-2xl border border-line bg-raised p-5 shadow-pop scrollbar-thin',
            'data-[state=closed]:animate-[pop-out_140ms_ease-in] data-[state=open]:animate-[pop-in_180ms_ease-out]',
            props.className,
          )}
        >
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <D.Title className="text-title-sm font-semibold text-fg">{props.title}</D.Title>
              {props.description !== undefined ? (
                <D.Description className="mt-1 text-body-sm leading-relaxed text-fg-2">{props.description}</D.Description>
              ) : (
                <D.Description className="sr-only">{props.title}</D.Description>
              )}
            </div>
            <D.Close asChild>
              <IconButton label="Fechar" bare className="-m-2">
                <X className="size-4" aria-hidden />
              </IconButton>
            </D.Close>
          </div>
          {props.children !== undefined && <div className="mt-4">{props.children}</div>}
          {props.footer !== undefined && <div className="mt-5 flex flex-wrap justify-end gap-2">{props.footer}</div>}
        </D.Content>
      </D.Portal>
    </D.Root>
  );
}

/** Confirmação de ação destrutiva: o botão perigoso nunca é o padrão do Enter. */
export function ConfirmDialog(props: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: ReactNode;
  description: ReactNode;
  confirmLabel: string;
  onConfirm: () => void;
  busy?: boolean;
}) {
  return (
    <Dialog
      open={props.open}
      onOpenChange={props.onOpenChange}
      title={props.title}
      description={props.description}
      footer={
        <>
          <Button autoFocus onClick={() => props.onOpenChange(false)}>
            Cancelar
          </Button>
          <Button variant="danger" disabled={props.busy} onClick={props.onConfirm}>
            {props.confirmLabel}
          </Button>
        </>
      }
    />
  );
}
