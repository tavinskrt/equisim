import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

/**
 * Contraste da paleta, medido no `styles.css` que vai para o navegador — a
 * porta do `contrast_test.dart`. A fórmula é a de luminância relativa da WCAG
 * 2.2 (https://www.w3.org/TR/WCAG22/#dfn-relative-luminance), e os pisos são os
 * do Flutter: 7:1 para o texto que se lê e para perda e ressalva, 4,5:1 (AA)
 * para o resto.
 *
 * Se uma cor mudou de propósito, remeça e atualize o comentário de razão ao
 * lado dela no `styles.css`.
 */

const css = readFileSync('src/styles.css', 'utf8');

function tokens(selector: string): Record<string, string> {
  const start = css.indexOf(selector);
  expect(start, `bloco ${selector} ausente do styles.css`).toBeGreaterThanOrEqual(0);
  const body = css.slice(start, css.indexOf('}', start));
  return Object.fromEntries([...body.matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})\b/g)].map((m) => [m[1]!, m[2]!.toLowerCase()]));
}

const themes = {
  escuro: tokens(":root[data-theme='dark'] {"),
  claro: tokens(":root[data-theme='light'] {"),
};

type Rgb = readonly [number, number, number];
const rgb = (hex: string): Rgb => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)) as unknown as Rgb;

function luminance([r, g, b]: Rgb): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

export function contrast(a: string | Rgb, b: string | Rgb): number {
  const la = luminance(typeof a === 'string' ? rgb(a) : a);
  const lb = luminance(typeof b === 'string' ? rgb(b) : b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** `color-mix(in srgb, a p%, b)`: interpolação canal a canal no sRGB com gama. */
const mix = (a: string, p: number, b: string): Rgb => {
  const [x, y] = [rgb(a), rgb(b)];
  return [0, 1, 2].map((i) => Math.round(x[i]! * p + y[i]! * (1 - p))) as unknown as Rgb;
};

const surfaces = ['canvas', 'surface', 'raised', 'sunken'] as const;

/** Tinta → piso, e as superfícies próprias onde ela também aparece. */
const inks: readonly { ink: string; floor: number; also?: readonly string[]; only?: 'escuro' | 'claro' }[] = [
  { ink: 'fg', floor: 7, also: ['brand-surface', 'reserve-surface'] },
  { ink: 'fg-2', floor: 7 },
  { ink: 'fg-3', floor: 4.5 },
  { ink: 'positive', floor: 4.5, also: ['positive-surface', 'brand-surface'] },
  { ink: 'negative', floor: 7, also: ['negative-surface'] },
  { ink: 'caution', floor: 7, also: ['caution-surface'] },
  { ink: 'pending', floor: 4.5, also: ['pending-surface'] },
  { ink: 'blocked', floor: 4.5 },
  // A Reserva escreve com `text-reserve dark:text-reserve-muted`: cada tema
  // com a sua tinta. O azul de série do escuro não chega a 4,5:1 no cartão.
  { ink: 'reserve', floor: 4.5, also: ['reserve-surface'], only: 'claro' },
  { ink: 'reserve-muted', floor: 4.5, also: ['reserve-surface'], only: 'escuro' },
  { ink: 'json-key', floor: 4.5 },
  { ink: 'json-string', floor: 4.5 },
  { ink: 'json-number', floor: 4.5 },
  { ink: 'json-bool', floor: 4.5 },
];

describe('Contraste da paleta', () => {
  for (const [name, t] of Object.entries(themes)) {
    describe(`tema ${name}`, () => {
      for (const { ink, floor, also = [], only } of inks) {
        if (only !== undefined && only !== name) continue;
        it(`${ink} atinge ${floor}:1 em toda superfície`, () => {
          for (const bg of [...surfaces, ...also]) {
            const ratio = contrast(t[ink]!, t[bg]!);
            expect(ratio, `tema ${name}: --${ink} ${t[ink]} sobre --${bg} ${t[bg]} dá ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(floor);
          }
        });
      }

      it('o rótulo do botão primário atinge o AA sobre o verde da marca', () => {
        // O Flutter escrevia branco sobre #00b37e no claro: 2,71:1.
        expect(contrast(t['on-brand']!, t['brand']!)).toBeGreaterThanOrEqual(4.5);
      });

      it('o número da célula do mapa de correlação se lê em qualquer ρ', () => {
        // A célula mistura o polo com o cinza do meio em até 60% (|ρ| = 1).
        for (const pole of ['div-low', 'div-high']) {
          for (let p = 0; p <= 0.6 + 1e-9; p += 0.05) {
            const cell = mix(t[pole]!, p, t['div-mid']!);
            const ratio = contrast(t['fg']!, cell);
            expect(ratio, `tema ${name}: --fg sobre ${pole} a ${Math.round(p * 100)}% dá ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(4.5);
          }
        }
      });

      it('todo token de tinta existe no bloco do tema', () => {
        for (const { ink, only } of inks) if (only === undefined || only === name) expect(t[ink], `--${ink}`).toMatch(/^#[0-9a-f]{6}$/);
      });
    });
  }

  it('a marca não é tinta de texto no claro', () => {
    // Se a marca passou a ter contraste de texto, a exclusão pode ser revista
    // — mas conscientemente, e não por acidente.
    expect(contrast(themes.claro['brand']!, themes.claro['surface']!)).toBeLessThan(4.5);
  });
});

describe('Escala tipográfica', () => {
  const sizes = [...css.matchAll(/--text-([\w-]+):\s*([\d.]+)px;/g)].map((m) => ({ role: m[1]!, px: Number(m[2]) }));

  it('a escala está declarada', () => {
    expect(sizes.map((s) => s.role)).toEqual(expect.arrayContaining(['caption', 'label', 'body-sm', 'body', 'title-sm', 'title', 'num-lg', 'display']));
  });

  it('nenhum tamanho é fracionário', () => {
    // Meio pixel não é um degrau perceptível de hierarquia.
    for (const s of sizes) expect(Number.isInteger(s.px), `${s.role}: ${s.px}px`).toBe(true);
  });

  it('nenhum tamanho fica abaixo de 11 px', () => {
    for (const s of sizes) expect(s.px, s.role).toBeGreaterThanOrEqual(11);
  });

  it('o utilitário de número carrega algarismos tabulares', () => {
    // Sem eles a vírgula decimal desalinha de uma linha para a outra numa
    // coluna alinhada à direita.
    const num = /@utility num \{([^}]*)\}/.exec(css)?.[1] ?? '';
    expect(num).toContain('font-variant-numeric: tabular-nums');
  });
});
