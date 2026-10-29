import { useMotionTemplate, useMotionValue, useReducedMotion, useSpring } from 'motion/react';
import type { PointerEvent, ReactNode } from 'react';

import { cn } from './cn';
import { m } from './motion';

/** Inclinação máxima, em graus: o bastante para dar volume, pouco para não ler torto. */
const MAX_TILT = 3;
const spring = { stiffness: 260, damping: 26, mass: 0.6 };

/**
 * **Profundidade à moda do Linear** (decisão 155): o cartão inclina poucos
 * graus seguindo o ponteiro, em perspectiva, e um brilho acompanha o cursor
 * por cima da superfície. É CSS 3D (`perspective`, `rotateX`, `rotateY`)
 * movido por mola — sem biblioteca 3D.
 *
 * Só reage a mouse e caneta: no toque, o dedo cobriria o que inclina. Com
 * movimento reduzido o cartão fica parado e o brilho não aparece.
 *
 * `glow` é a cor do brilho, uma variável de cor do tema (`var(--positive)`).
 */
export function Tilt({ children, className, glow = 'var(--brand)' }: { children: ReactNode; className?: string; glow?: string }) {
  const reduced = useReducedMotion() === true;
  const rx = useSpring(0, spring);
  const ry = useSpring(0, spring);
  const px = useMotionValue(50);
  const py = useMotionValue(50);
  const lit = useSpring(0, spring);
  const background = useMotionTemplate`radial-gradient(420px circle at ${px}% ${py}%, color-mix(in oklab, ${glow} 14%, transparent), transparent 70%)`;

  const move = (e: PointerEvent<HTMLDivElement>) => {
    if (reduced || e.pointerType === 'touch') return;
    const r = e.currentTarget.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return;
    const fx = (e.clientX - r.left) / r.width;
    const fy = (e.clientY - r.top) / r.height;
    ry.set((fx - 0.5) * 2 * MAX_TILT);
    rx.set(-(fy - 0.5) * 2 * MAX_TILT);
    px.set(fx * 100);
    py.set(fy * 100);
    lit.set(1);
  };
  const leave = () => {
    rx.set(0);
    ry.set(0);
    lit.set(0);
  };

  return (
    <div className={cn('[perspective:1200px]', className)}>
      <m.div
        className="relative h-full rounded-xl [transform-style:preserve-3d]"
        style={reduced ? undefined : { rotateX: rx, rotateY: ry }}
        onPointerMove={move}
        onPointerLeave={leave}
      >
        {children}
        {!reduced && (
          <m.div aria-hidden className="pointer-events-none absolute inset-0 rounded-xl" style={{ background, opacity: lit }} />
        )}
      </m.div>
    </div>
  );
}
