import { LazyMotion, MotionConfig, useMotionValueEvent, useReducedMotion, useSpring, type Variants } from 'motion/react';
import * as m from 'motion/react-m';
import { type ReactNode, useEffect, useState } from 'react';

import { cn } from './cn';

/**
 * O movimento da interface (decisão 155), pelo Motion
 * (https://motion.dev). Três regras valem para tudo o que mora aqui:
 *
 * 1. **`LazyMotion` estrito**: só o componente `m`, de ~5 kB, e o pacote
 *    `domAnimation`, baixado à parte depois da primeira pintura
 *    (`motion-features.ts`). O `motion.div` completo, de 43 kB, é recusado em
 *    tempo de execução — e o `domMax`, das animações de layout, fica de fora.
 * 2. **Movimento reduzido manda**: com a preferência do sistema ligada, o
 *    Motion corta transformação e layout e mantém só opacidade e cor, como o
 *    `styles.css` já faz com as animações CSS.
 * 3. **Movimento explica ou não existe**: curto (150–300 ms), na entrada do
 *    conteúdo, nunca em laço.
 */
export function MotionProvider({ children }: { children: ReactNode }) {
  return (
    <LazyMotion features={loadFeatures} strict>
      <MotionConfig reducedMotion="user">{children}</MotionConfig>
    </LazyMotion>
  );
}

const loadFeatures = () => import('./motion-features').then((r) => r.default);

/** A curva de saída rápida que assenta devagar, a mesma de todas as entradas. */
export const easeOut = [0.23, 1, 0.32, 1] as const;

/** Um bloco que entra subindo de leve e acendendo. */
const rise: Variants = {
  hidden: { opacity: 0, y: 8 },
  shown: { opacity: 1, y: 0, transition: { duration: 0.28, ease: easeOut } },
};

/** Entrada de um bloco isolado, ao montar. */
export function Reveal({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <m.div className={className} initial="hidden" animate="shown" variants={rise}>
      {children}
    </m.div>
  );
}

/**
 * Cascata: os filhos `StaggerItem` entram um depois do outro, de cima para
 * baixo, na ordem em que o olho deve lê-los.
 */
export function Stagger({ children, className, step = 0.05 }: { children: ReactNode; className?: string; step?: number }) {
  return (
    <m.div
      className={className}
      initial="hidden"
      animate="shown"
      variants={{ hidden: {}, shown: { transition: { staggerChildren: step } } }}
    >
      {children}
    </m.div>
  );
}

export function StaggerItem({ children, className, id }: { children: ReactNode; className?: string; id?: string }) {
  return (
    <m.div className={className} id={id} variants={rise}>
      {children}
    </m.div>
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
