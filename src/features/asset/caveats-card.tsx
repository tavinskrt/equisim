import type { ReactNode } from 'react';

import type { ValuationResult } from '../../core';
import { DomainCopy } from '../../copy';
import { Banner } from '../../ui/banner';
import { Panel } from '../../ui/card';

/** As ressalvas: a qualidade da estimativa faz parte do resultado. */
export function CaveatsCard({ result }: { result: ValuationResult }) {
  const caveats = result.diagnostics?.caveats ?? [];
  if (caveats.length === 0 && result.warnings.length === 0) return null;
  return (
    <Panel title="Ressalvas" subtitle="A qualidade da estimativa faz parte do resultado">
      {caveats.length > 0 && (
        <ul className="mb-3 space-y-1 text-body-sm text-fg-2">
          {caveats.map((c) => (
            <li key={c.name} className="flex gap-2">
              <span aria-hidden className="text-fg-3">
                •
              </span>
              {DomainCopy.caveat(c)}
            </li>
          ))}
        </ul>
      )}
      <div className="space-y-2">
        {result.warnings.map((w, i) => (
          <Banner key={i}>{emphasized(w)}</Banner>
        ))}
      </div>
    </Panel>
  );
}

/**
 * Os avisos do núcleo marcam ênfase com `**palavra**`, como no Markdown; o
 * Flutter mostrava os asteriscos. Aqui viram negrito — e só isso: o texto
 * vem do motor, nunca do usuário, e nada mais é interpretado.
 */
export function emphasized(text: string): ReactNode {
  const parts = text.split(/\*\*(.+?)\*\*/g);
  if (parts.length === 1) return text;
  return parts.map((part, i) => (i % 2 === 1 ? <strong key={i} className="font-semibold text-fg">{part}</strong> : part));
}
