/**
 * Semântica numérica do motor.
 *
 * O motor nasceu em Dart e rodava na web compilado para JavaScript (dart2js).
 * Lá, todo número já era o `double` do JavaScript — o que garante que soma,
 * produto, `Math.pow`, `Math.log` e `Math.exp` daqui dão o mesmo resultado bit
 * a bit que davam lá. O que o Dart **não** herdava do JavaScript, e que por
 * isso precisa ser reproduzido à mão, mora neste arquivo:
 *
 * - o arredondamento `round()`, que é *meio afastado de zero* (o `Math.round`
 *   do JavaScript é *meio para cima*: `Math.round(-2.5) === -2`);
 * - o resto `%`, que no Dart é euclidiano e nunca negativo
 *   (`(-1) % 3 === 2`, contra `-1` no JavaScript);
 * - a divisão inteira `~/`, que trunca e lança diante de divisor zero;
 * - `toInt`, `floor`, `ceil`, que lançam diante de `NaN` e infinito;
 * - `compareTo`, que ordena `-0.0` antes de `0.0` e põe `NaN` no topo;
 * - `clamp`, que usa esse `compareTo`;
 * - a escrita `toString`, que grafa `-0.0` em vez de `0`;
 * - `toStringAsFixed`, que preserva o sinal de `-0.0`.
 *
 * Referência: o código de cada função é transcrito de
 * `sdk/lib/_internal/js_runtime/lib/js_number.dart` e `js_helper.dart`, do SDK
 * do Dart 3.13, que é o que o aplicativo Flutter usava na web.
 */

const MIN_INT32 = -0x80000000;
const MAX_INT32 = 0x7fffffff;

/** Erro do Dart para operação sem resultado inteiro (`NaN.toInt()`). */
export class UnsupportedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UnsupportedError';
  }
}

/** Erro do Dart para argumento inválido. */
export class ArgumentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ArgumentError';
  }
}

/** Erro do Dart para estado inválido (`unwrap()` sobre falha, por exemplo). */
export class StateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StateError';
  }
}

/** Erro do Dart para texto que não se converte (`int.parse('abc')`). */
export class FormatException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FormatException';
  }
}

/** Erro do Dart para índice ou faixa fora do domínio. */
export class RangeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RangeError';
  }
}

/** `true` para `-0.0` e para qualquer negativo — o `isNegative` do Dart. */
export function isNegative(x: number): boolean {
  return x === 0 ? 1 / x < 0 : x < 0;
}

/** `round()` do Dart: meio afastado de zero, e lança para `NaN` e infinito. */
export function round(x: number): number {
  if (x > 0) {
    if (x !== Infinity) return Math.round(x);
  } else if (x > -Infinity) {
    return 0 - Math.round(0 - x);
  }
  throw new UnsupportedError(`${x}.round()`);
}

/** `roundToDouble()` do Dart: meio afastado de zero, sem lançar. */
export function roundToDouble(x: number): number {
  return x < 0 ? -Math.round(-x) : Math.round(x);
}

/** `toInt()` / `truncate()` do Dart: trunca em direção a zero. */
export function toInt(x: number): number {
  if (x >= MIN_INT32 && x <= MAX_INT32) return x | 0;
  if (Number.isFinite(x)) return Math.trunc(x) + 0;
  throw new UnsupportedError(`${x}.toInt()`);
}

/** `floor()` do Dart, que lança para `NaN` e infinito. */
export function floor(x: number): number {
  const d = Math.floor(x);
  if (Number.isFinite(d)) return d + 0;
  throw new UnsupportedError(`${x}.floor()`);
}

/** `ceil()` do Dart, que lança para `NaN` e infinito. */
export function ceil(x: number): number {
  const d = Math.ceil(x);
  if (Number.isFinite(d)) return d + 0;
  throw new UnsupportedError(`${x}.ceil()`);
}

/** Resto euclidiano `a % b` do Dart: nunca negativo. */
export function mod(a: number, b: number): number {
  const result = a % b;
  if (result === 0) return 0;
  if (result > 0) return result;
  return b < 0 ? result - b : result + b;
}

/** `remainder` do Dart: o `%` do JavaScript, com o sinal do dividendo. */
export function remainder(a: number, b: number): number {
  return a % b;
}

/**
 * Divisão inteira `a ~/ b` do Dart: trunca em direção a zero.
 *
 * Lança [UnsupportedError] quando o quociente não é finito — divisor zero,
 * inclusive —, como o Dart.
 */
export function intDiv(a: number, b: number): number {
  const quotient = a / b;
  if (quotient >= MIN_INT32 && quotient <= MAX_INT32) return quotient | 0;
  if (quotient > 0) {
    if (quotient !== Infinity) return Math.floor(quotient);
  } else if (quotient > -Infinity) {
    return Math.ceil(quotient);
  }
  throw new UnsupportedError(`Result of truncating division is ${quotient}: ${a} ~/ ${b}`);
}

/**
 * `compareTo` de número do Dart.
 *
 * Difere da subtração em dois pontos: `-0.0` vem antes de `0.0`, e `NaN` é
 * maior que tudo (e igual a si mesmo). É o que `List.sort()` sem comparador
 * usava para números.
 */
export function compareNum(a: number, b: number): number {
  if (a < b) return -1;
  if (a > b) return 1;
  if (a === b) {
    if (a === 0) {
      const aNeg = isNegative(a);
      const bNeg = isNegative(b);
      if (aNeg === bNeg) return 0;
      return aNeg ? -1 : 1;
    }
    return 0;
  }
  if (Number.isNaN(a)) return Number.isNaN(b) ? 0 : 1;
  return -1;
}

/** `compareTo` de texto do Dart: ordem das unidades UTF-16, como o `<` do JavaScript. */
export function compareStr(a: string, b: string): number {
  return a === b ? 0 : a < b ? -1 : 1;
}

/** `compareTo` de booleano não existe no Dart; usado só onde o original converte. */
export function compareBool(a: boolean, b: boolean): number {
  return a === b ? 0 : a ? 1 : -1;
}

/**
 * `clamp(lower, upper)` do Dart.
 *
 * Lança [ArgumentError] se `lower > upper`. Com `NaN` na entrada devolve
 * `upper`, porque o `compareTo` do Dart põe `NaN` acima de tudo.
 */
export function clamp(x: number, lower: number, upper: number): number {
  if (compareNum(lower, upper) > 0) {
    throw new ArgumentError(`Invalid argument(s): ${str(lower)}`);
  }
  if (compareNum(x, lower) < 0) return lower;
  if (compareNum(x, upper) > 0) return upper;
  return x;
}

/** `abs()` do Dart. */
export function abs(x: number): number {
  return Math.abs(x);
}

/** `sign` de `double` do Dart: `-1.0`, `0.0`, `1.0` ou `NaN`. */
export function sign(x: number): number {
  return x > 0 ? 1 : x < 0 ? -1 : x;
}

/**
 * Escrita de um número como o Dart a fazia na web (`'$x'` e `x.toString()`).
 *
 * É a do JavaScript, salvo `-0.0`, que o Dart grafa com o sinal.
 */
export function str(x: number): string {
  if (x === 0 && 1 / x < 0) return '-0.0';
  return '' + x;
}

/** `toStringAsFixed` do Dart, que preserva o sinal de `-0.0`. */
export function toStringAsFixed(x: number, fractionDigits: number): string {
  if (fractionDigits < 0 || fractionDigits > 20) {
    throw new RangeError(`fractionDigits: ${fractionDigits}`);
  }
  const result = x.toFixed(fractionDigits);
  if (x === 0 && isNegative(x)) return `-${result}`;
  return result;
}

/** `toStringAsPrecision` do Dart, que preserva o sinal de `-0.0`. */
export function toStringAsPrecision(x: number, precision: number): string {
  if (precision < 1 || precision > 21) {
    throw new RangeError(`precision: ${precision}`);
  }
  const result = x.toPrecision(precision);
  if (x === 0 && isNegative(x)) return `-${result}`;
  return result;
}

/** `toStringAsExponential` do Dart, que preserva o sinal de `-0.0`. */
export function toStringAsExponential(x: number, fractionDigits?: number): string {
  const result = fractionDigits === undefined ? x.toExponential() : x.toExponential(fractionDigits);
  if (x === 0 && isNegative(x)) return `-${result}`;
  return result;
}

/** `toRadixString` de inteiro do Dart. */
export function toRadixString(x: number, radix: number): string {
  return x.toString(radix);
}

const INT_PATTERN = /^\s*[+-]?((0x[a-f0-9]+)|(\d+)|([a-z0-9]+))\s*$/i;

/** `int.tryParse` do Dart na web: decimal ou hexadecimal `0x`, com espaço nas pontas. */
export function tryParseInt(source: string, radix?: number): number | null {
  const match = INT_PATTERN.exec(source);
  if (match === null) return null;
  const decimalMatch = match[3];
  if (radix === undefined) {
    if (decimalMatch !== undefined) return parseInt(source, 10);
    if (match[2] !== undefined) return parseInt(source, 16);
    return null;
  }
  if (radix === 10 && decimalMatch !== undefined) return parseInt(source, 10);
  const digits = (match[1] ?? '').toLowerCase();
  const body = radix === 16 && digits.startsWith('0x') ? digits.slice(2) : digits;
  for (const ch of body) {
    const v = parseInt(ch, 36);
    if (Number.isNaN(v) || v >= radix) return null;
  }
  return parseInt(source, radix);
}

/** `int.parse` do Dart: como [tryParseInt], lançando [FormatException]. */
export function parseInt_(source: string, radix?: number): number {
  const v = tryParseInt(source, radix);
  if (v === null) throw new FormatException(source);
  return v;
}

const DOUBLE_PATTERN = /^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/;

/** `double.tryParse` do Dart na web. */
export function tryParseDouble(source: string): number | null {
  if (!DOUBLE_PATTERN.test(source)) return null;
  const result = parseFloat(source);
  if (Number.isNaN(result)) {
    const trimmed = source.trim();
    if (trimmed === 'NaN' || trimmed === '+NaN' || trimmed === '-NaN') return result;
    return null;
  }
  return result;
}

/** `double.parse` do Dart: como [tryParseDouble], lançando [FormatException]. */
export function parseDouble(source: string): number {
  const v = tryParseDouble(source);
  if (v === null) throw new FormatException(`Invalid double: ${source}`);
  return v;
}

/** `num.tryParse` do Dart: inteiro primeiro, depois `double`. */
export function tryParseNum(source: string): number | null {
  return tryParseInt(source) ?? tryParseDouble(source);
}

/** `true` quando o número é inteiro — o `is int` do Dart compilado para a web. */
export function isInt(x: unknown): x is number {
  return typeof x === 'number' && Number.isInteger(x);
}

/** `true` para número finito. */
export function isFinite(x: number): boolean {
  return Number.isFinite(x);
}

/** `math.max` do Dart na web. */
export function max(a: number, b: number): number {
  return Math.max(a, b);
}

/** `math.min` do Dart na web. */
export function min(a: number, b: number): number {
  return Math.min(a, b);
}

/** `math.pow` do Dart na web. */
export function pow(x: number, exponent: number): number {
  return Math.pow(x, exponent);
}
