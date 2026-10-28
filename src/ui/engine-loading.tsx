/*
 * Adaptado do "AI Text Loading" da Kokonut UI
 * (https://kokonutui.com/docs/components/ai-text-loading),
 * Copyright (c) 2025 kokonutUI, sob a licença MIT — o texto da licença está
 * em THIRD_PARTY_NOTICES.md. Mudou: os tokens do Equisim no lugar das cores
 * do Tailwind, o tamanho do texto, e sai o contador de segundos.
 */
import { AnimatePresence, type Variants } from 'motion/react';
import { useEffect, useState } from 'react';

import { cn } from './cn';
import { easeOut, m } from './motion';

// Intervalo entre letras vizinhas na onda, em segundos.
const WAVE_STEP = 0.07;

const wordVariants: Variants = {
  enter: {},
  shown: { transition: { staggerChildren: 0.018 } },
  exit: { opacity: 0, y: -6, filter: 'blur(3px)', transition: { duration: 0.15, ease: easeOut } },
};

const letterVariants: Variants = {
  enter: { opacity: 0, y: 8, filter: 'blur(4px)' },
  shown: { opacity: 1, y: 0, filter: 'blur(0px)', transition: { duration: 0.28, ease: easeOut } },
};

/**
 * **O motor trabalhando**, dito em palavras (decisão 155): enquanto a
 * avaliação não chega, as etapas do cálculo se revezam com uma onda leve de
 * brilho pelas letras, no lugar de um esqueleto mudo.
 *
 * O leitor de tela ouve só `label`, uma vez: as frases que se revezam são
 * visuais. A onda é CSS (`engine-wave` em `styles.css`), fora da linha
 * principal, e para com movimento reduzido.
 */
export function EngineLoading({ texts, label, className, interval = 1600 }: { texts: readonly string[]; label: string; className?: string; interval?: number }) {
  const [index, setIndex] = useState(0);
  const i = texts.length > 0 ? index % texts.length : 0;
  const text = texts[i] ?? '';

  useEffect(() => {
    if (texts.length < 2) return;
    const timer = setInterval(() => setIndex((n) => (n + 1) % texts.length), interval);
    return () => clearInterval(timer);
  }, [interval, texts.length]);

  return (
    <output aria-live="polite" className={cn('flex items-baseline gap-3 text-body font-semibold text-fg-2', className)}>
      <span className="sr-only">{label}</span>
      <span aria-hidden className="relative flex">
        <AnimatePresence initial={false} mode="popLayout">
          <m.span key={i} className="flex min-w-max whitespace-pre" initial="enter" animate="shown" exit="exit" variants={wordVariants}>
            {Array.from(text).map((char, k) => (
              // Letras de uma frase fixa, nunca reordenadas: a posição é a identidade.
              <m.span key={k} className="inline-block" variants={letterVariants}>
                <span className="engine-wave inline-block" style={{ animationDelay: `${k * WAVE_STEP}s` }}>
                  {char}
                </span>
              </m.span>
            ))}
          </m.span>
        </AnimatePresence>
      </span>
    </output>
  );
}
