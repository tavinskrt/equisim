import { domAnimation, LazyMotion, MotionConfig, useMotionValueEvent, useReducedMotion, useSpring } from 'motion/react';
import * as m from 'motion/react-m';
import { type ReactNode, useEffect, useState } from 'react';

import { cn } from './cn';

/**
 * O movimento da interface (decisão 155), pelo Motion
 * (https://motion.dev). Quatro regras valem para tudo o que mora aqui:
 *
 * 1. **`LazyMotion` estrito**: só o componente `m` e o pacote `domAnimation`.
 *    O `motion.div` completo, de 43 kB, é recusado em tempo de execução — e o
 *    `domMax`, das animações de layout, fica de fora. Os recursos vão no
 *    pacote principal, e não num pedaço baixado depois: um pedaço que falha
 *    (rede, ou o build velho de uma aba aberta antes de uma publicação)
 *    deixaria parado no estado inicial tudo o que é `m.*`.
 * 2. **Conteúdo nunca depende de JavaScript para aparecer**: a entrada das
 *    áreas e a cascata dos cartões são animação CSS (`rise-in` e `stagger`
 *    em `styles.css`). Uma animação do Motion só corre a cada quadro de tela,
 *    e numa aba em segundo plano não há quadro: um `opacity: 0` inicial
 *    esconderia a página até a aba voltar à frente.
 * 3. **Movimento reduzido manda**: com a preferência do sistema ligada, o
 *    Motion corta transformação e layout e mantém só opacidade e cor, e o
 *    `styles.css` encurta as animações CSS para um quadro.
 * 4. **Movimento explica ou não existe**: curto (150–300 ms), na entrada do
 *    conteúdo, nunca em laço.
 */
export function MotionProvider({ children }: { children: ReactNode }) {
  return (
    <LazyMotion features={domAnimation} strict>
      <MotionConfig reducedMotion="user">{children}</MotionConfig>
    </LazyMotion>
  );
}

/** A curva de saída rápida que assenta devagar, a mesma de todas as entradas. */
export const easeOut = [0.23, 1, 0.32, 1] as const;

/** Entrada de um bloco isolado, ao montar: sobe de leve e acende (CSS). */
export function Reveal({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('rise-in', className)}>{children}</div>;
}

/**
 * Cascata: os filhos entram um depois do outro, de cima para baixo, na ordem
 * em que o olho deve lê-los. O atraso de cada um vem da posição dele
 * (`.stagger > :nth-child(n)` em `styles.css`).
 */
export function Stagger({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('stagger', className)}>{children}</div>;
}

export function StaggerItem({ children, className, id }: { children: ReactNode; className?: string; id?: string }) {
  return (
    <div className={className} id={id}>
      {children}
    </div>
  );
}

/**
 * Um número que **conta até o valor** quando aparece e quando muda.
 *
 * O texto final está sempre na árvore de acessibilidade, e a contagem é só
 * visual (`aria-hidden`): o leitor de tela lê `R$ 36,12` uma vez, e não cada
 * quadro. Com movimento reduzido, o número aparece pronto.
 */
export function CountUp({ value, format, className }: { value: number; format: (v: number) => string; className?: string }) {
  const reduced = useReducedMotion() === true;
  const finite = Number.isFinite(value);
  // Uma mola sem quique: assenta no valor em ~0,6 s, sem passar dele — um
  // preço que ultrapassa e volta pareceria outro número.
  const spring = useSpring(reduced || !finite ? value : 0, { stiffness: 90, damping: 24, mass: 0.7, restDelta: 1e-4 });
  const [shown, setShown] = useState(spring.get());
  useMotionValueEvent(spring, 'change', setShown);

  useEffect(() => {
    if (reduced || !finite) spring.jump(value);
    else spring.set(value);
  }, [value, reduced, finite, spring]);

  return (
    <span className={cn('relative', className)}>
      <span aria-hidden>{format(reduced || !finite ? value : shown)}</span>
      <span className="sr-only">{format(value)}</span>
    </span>
  );
}

export { m };
