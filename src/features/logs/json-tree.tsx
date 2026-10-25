import { ChevronDown, ChevronRight, Copy } from 'lucide-react';
import { useState } from 'react';

import { cn } from '../../ui/cn';
import { toast } from '../../ui/toast';
import { formatAuditNumber } from './format';

/**
 * Um payload em árvore: cada objeto e lista recolhe, os dois primeiros níveis
 * abrem sozinhos, e as cores separam chave, texto, número e booleano — com o
 * nulo em alerta, porque dado ausente é o que se procura numa auditoria.
 */
export function JsonPanel({ label, value }: { label: string; value: Record<string, unknown> }) {
  const copy = () => {
    const text = JSON.stringify(value, null, 2);
    navigator.clipboard
      ?.writeText(text)
      .then(() => toast(`${label} copiado.`, 'success'))
      .catch(() => toast('O navegador não permitiu copiar.', 'error'));
  };
  return (
    <div className="overflow-hidden rounded-lg border border-line bg-sunken">
      <div className="flex items-center border-b border-line pl-3">
        <span className="flex-1 font-mono text-caption font-bold text-fg-3">{label}</span>
        <button type="button" onClick={copy} aria-label={`Copiar ${label}`} title={`Copiar ${label}`} className="inline-flex size-11 items-center justify-center text-fg-3 hover:text-fg">
          <Copy aria-hidden className="size-3.5" />
        </button>
      </div>
      <div className="overflow-x-auto px-3 py-2 scrollbar-thin">
        <JsonNode value={value} depth={0} />
      </div>
    </div>
  );
}

function JsonNode({ value, depth, name }: { value: unknown; depth: number; name?: string }) {
  const [open, setOpen] = useState(depth < 2);
  const key = name !== undefined && <span className="text-json-key">{name}: </span>;

  if (value !== null && typeof value === 'object') {
    const isList = Array.isArray(value);
    const entries: [string, unknown][] = isList ? value.map((v, i) => [String(i), v]) : Object.entries(value as Record<string, unknown>);
    const [o, c] = isList ? ['[', ']'] : ['{', '}'];
    const summary = isList ? `${entries.length} item(ns)` : `${entries.length} campo(s)`;
    return (
      <div className="font-mono text-label leading-relaxed">
        <button
          type="button"
          onClick={() => setOpen((x) => !x)}
          aria-expanded={open}
          className="-ml-1 inline-flex items-center gap-0.5 rounded px-0.5 text-left whitespace-nowrap hover:bg-raised"
        >
          {open ? <ChevronDown aria-hidden className="size-3.5 text-fg-3" /> : <ChevronRight aria-hidden className="size-3.5 text-fg-3" />}
          {key}
          <span className="text-fg-3">{open ? o : `${o} … ${c}`}</span>
          <span className="ml-1.5 text-caption text-fg-3">{summary}</span>
        </button>
        {open && (
          <>
            <div className="ml-4 border-l border-divider pl-2">
              {entries.map(([k, v]) => (
                <JsonNode key={k} name={k} value={v} depth={depth + 1} />
              ))}
            </div>
            <span className="ml-3.5 text-fg-3">{c}</span>
          </>
        )}
      </div>
    );
  }

  return (
    // Quebra as linhas: o motivo de uma recusa passa de 300 caracteres e ficava
    // escondido além da borda do painel, numa rolagem lateral.
    <div className="py-px pl-[2ch] -indent-[2ch] font-mono text-label whitespace-pre-wrap break-words select-text">
      {key}
      <span className={cn(scalarClass(value))}>{scalarText(value)}</span>
    </div>
  );
}

function scalarText(v: unknown): string {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'string') return `"${v}"`;
  if (typeof v === 'number') return formatAuditNumber(v);
  return String(v);
}

function scalarClass(v: unknown): string {
  if (v === null || v === undefined) return 'text-caution';
  if (typeof v === 'string') return 'text-json-string';
  if (typeof v === 'number') return 'text-json-number';
  if (typeof v === 'boolean') return 'text-json-bool';
  return 'text-fg';
}
