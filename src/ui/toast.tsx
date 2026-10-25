import { CheckCircle2, Info, OctagonAlert, X } from 'lucide-react';
import { useEffect } from 'react';
import { create } from 'zustand';

import { cn } from './cn';

type ToastTone = 'info' | 'success' | 'error';

interface ToastItem {
  readonly id: number;
  readonly message: string;
  readonly tone: ToastTone;
}

const useToasts = create<{ items: readonly ToastItem[] }>(() => ({ items: [] }));
let nextId = 1;

/** Mensagem transitória. Erro dura mais: precisa ser lido, não só visto. */
export function toast(message: string, tone: ToastTone = 'info'): void {
  const id = nextId++;
  useToasts.setState((s) => ({ items: [...s.items.slice(-2), { id, message, tone }] }));
  setTimeout(() => dismiss(id), tone === 'error' ? 6000 : 3500);
}

function dismiss(id: number): void {
  useToasts.setState((s) => ({ items: s.items.filter((t) => t.id !== id) }));
}

const icons = {
  info: <Info aria-hidden className="size-4 shrink-0 text-pending" />,
  success: <CheckCircle2 aria-hidden className="size-4 shrink-0 text-positive" />,
  error: <OctagonAlert aria-hidden className="size-4 shrink-0 text-negative" />,
};

/** A pilha de mensagens. `aria-live` faz o leitor de tela anunciar cada uma. */
export function Toaster() {
  const items = useToasts((s) => s.items);
  useEffect(() => () => useToasts.setState({ items: [] }), []);
  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 bottom-20 z-[60] flex flex-col items-center gap-2 px-4 md:bottom-6 md:items-end md:px-6"
    >
      {items.map((t) => (
        <div
          key={t.id}
          role={t.tone === 'error' ? 'alert' : 'status'}
          className={cn(
            'pointer-events-auto flex w-full max-w-sm animate-[toast-in_200ms_ease-out] items-start gap-2.5 rounded-xl border border-line bg-raised px-3.5 py-3 text-body-sm text-fg shadow-pop',
          )}
        >
          {icons[t.tone]}
          <p className="min-w-0 flex-1 leading-relaxed">{t.message}</p>
          <button
            type="button"
            aria-label="Dispensar"
            onClick={() => dismiss(t.id)}
            className="-m-2 inline-flex size-9 items-center justify-center rounded-md text-fg-3 hover:text-fg"
          >
            <X aria-hidden className="size-3.5" />
          </button>
        </div>
      ))}
    </div>
  );
}
