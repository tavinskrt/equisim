import { clamp, compareNum, floor } from '../../src/core';

/**
 * Percentil pelo método do índice truncado — `ordenado[⌊n·p⌋]`, preso ao
 * último —, o mesmo das medições do registro. `NaN` com a lista vazia.
 */
export function truncatedQuantile(v: readonly number[], p: number): number {
  if (v.length === 0) return Number.NaN;
  const o = [...v].sort(compareNum);
  return o[clamp(floor(o.length * p), 0, o.length - 1)]!;
}

/** A mediana pelo mesmo índice truncado: `ordenado[⌊n/2⌋]`. */
export const truncatedMedian = (v: readonly number[]): number => truncatedQuantile(v, 0.5);

/** Percentual com uma casa, em seis colunas; `NaN` vira travessão. */
export const pctColumn = (v: number): string => (Number.isNaN(v) ? '   —  ' : `${(v * 100).toFixed(1).padStart(6)}%`);
