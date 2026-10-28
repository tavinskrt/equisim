import { useReducedMotion } from 'motion/react';
import { useEffect, useState } from 'react';

import { cn } from '../../ui/cn';
import { m } from '../../ui/motion';

export interface IndexedSection {
  readonly id: string;
  readonly label: string;
}

/**
 * **O índice da página do ativo** (decisão 155, a ideia do Scroll Index da
 * Kokonut UI): as seções do Raio-X numa coluna fixa, com a que está à vista
 * marcada por uma barra que desliza até ela.
 *
 * O clique rola até a seção **sem mexer na URL**: um `#ancora` entraria no
 * histórico, e o Voltar da página passaria a percorrer as seções em vez de
 * devolver a pessoa de onde ela veio.
 */
export function SectionIndex({ sections, className }: { sections: readonly IndexedSection[]; className?: string }) {
  const reduced = useReducedMotion() === true;
  const [present, setPresent] = useState<readonly IndexedSection[]>([]);
  const [active, setActive] = useState<string | null>(null);
  const key = sections.map((s) => s.id).join('|');

  // Um cartão sem conteúdo (sem ressalvas, sem valuation salvo) deixa o
  // invólucro vazio, e o índice não lista o que a página não mostra. Os
  // salvos chegam depois da avaliação, então a lista se refaz quando a página
  // muda.
  useEffect(() => {
    const scan = () => {
      const now = sections.filter((s) => {
        const el = document.getElementById(s.id);
        return el !== null && el.childElementCount > 0;
      });
      setPresent((old) => (old.map((s) => s.id).join('|') === now.map((s) => s.id).join('|') ? old : now));
    };
    scan();
    if (typeof MutationObserver === 'undefined') return;
    const mutations = new MutationObserver(scan);
    mutations.observe(document.body, { childList: true, subtree: true });
    return () => mutations.disconnect();
    // `key` resume a lista: refaz só quando as seções mudam, e não a cada nova
    // referência do mesmo arranjo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const presentKey = present.map((s) => s.id).join('|');
  useEffect(() => {
    if (present.length === 0) return;
    setActive((a) => (a !== null && present.some((s) => s.id === a) ? a : present[0]!.id));
    if (typeof IntersectionObserver === 'undefined') return;
    const visible = new Set<string>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) visible.add(e.target.id);
          else visible.delete(e.target.id);
        }
        // A seção à vista mais alta na página é a corrente.
        const top = present.find((s) => visible.has(s.id));
        if (top !== undefined) setActive(top.id);
      },
      // A faixa de leitura: abaixo do cabeçalho grudado, acima da metade de baixo da tela.
      { rootMargin: '-72px 0px -45% 0px' },
    );
    for (const s of present) {
      const el = document.getElementById(s.id);
      if (el !== null) observer.observe(el);
    }
    return () => observer.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [presentKey]);

  const go = (id: string) => {
    const el = document.getElementById(id);
    if (el === null) return;
    el.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' });
    setActive(id);
  };

  if (present.length < 2) return null;
  return (
    <nav aria-label="Seções do Raio-X" className={className}>
      <p className="eyebrow mb-2 px-3">Nesta página</p>
      <ul className="relative space-y-0.5 border-l border-divider">
        {present.map((s) => {
          const on = s.id === active;
          return (
            <li key={s.id} className="relative">
              {on && (
                <m.span
                  aria-hidden
                  className="absolute -left-px inset-y-1 w-0.5 rounded-full bg-brand"
                  initial={{ opacity: 0, scaleY: 0.4 }}
                  animate={{ opacity: 1, scaleY: 1 }}
                  transition={{ duration: 0.2 }}
                />
              )}
              <button
                type="button"
                aria-current={on ? 'location' : undefined}
                onClick={() => go(s.id)}
                className={cn(
                  'block w-full rounded-r-md py-1.5 pl-3 pr-2 text-left text-body-sm transition-colors',
                  on ? 'font-medium text-fg' : 'text-fg-3 hover:text-fg-2',
                )}
              >
                {s.label}
              </button>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
