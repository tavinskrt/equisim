/**
 * Comparação estrutural entre o gabarito do Dart e a saída do TypeScript.
 *
 * Número com número por `Object.is` — o que distingue `-0` de `0`, que o
 * `toEqual` comum também distingue, mas aqui com o caminho da primeira
 * divergência no relatório, que é o que se precisa para achá-la.
 */
export interface Divergence {
  readonly path: string;
  readonly expected: unknown;
  readonly actual: unknown;
}

export function diff(expected: unknown, actual: unknown, path = '$', out: Divergence[] = [], max = 50): Divergence[] {
  if (out.length >= max) return out;
  if (typeof expected === 'number' && typeof actual === 'number') {
    if (!Object.is(expected, actual)) out.push({ path, expected, actual });
    return out;
  }
  if (expected === null || actual === null || typeof expected !== 'object' || typeof actual !== 'object') {
    if (!Object.is(expected, actual)) out.push({ path, expected, actual });
    return out;
  }
  if (Array.isArray(expected) !== Array.isArray(actual)) {
    out.push({ path, expected, actual });
    return out;
  }
  if (Array.isArray(expected) && Array.isArray(actual)) {
    if (expected.length !== actual.length) out.push({ path: `${path}.length`, expected: expected.length, actual: actual.length });
    const len = Math.min(expected.length, actual.length);
    for (let i = 0; i < len; i++) diff(expected[i], actual[i], `${path}[${i}]`, out, max);
    return out;
  }
  const e = expected as Record<string, unknown>;
  const a = actual as Record<string, unknown>;
  const ek = Object.keys(e);
  const ak = Object.keys(a);
  if (ek.join('\u0000') !== ak.join('\u0000')) {
    const missing = ek.filter((k) => !(k in a));
    const extra = ak.filter((k) => !(k in e));
    if (missing.length > 0 || extra.length > 0) {
      out.push({ path: `${path}{keys}`, expected: missing, actual: extra });
    } else {
      out.push({ path: `${path}{order}`, expected: ek, actual: ak });
    }
  }
  for (const k of ek) {
    if (k in a) diff(e[k], a[k], `${path}.${k}`, out, max);
  }
  return out;
}
