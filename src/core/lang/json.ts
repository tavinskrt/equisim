/**
 * Leitura de JSON com as coerções do Dart.
 *
 * O original lia mapas decodificados com `as num?`, `as String?` e
 * `is Map<String, dynamic>`. Os auxiliares daqui reproduzem esses testes —
 * inclusive o de lançar quando o tipo não é o declarado, que é o que o
 * `as` fazia.
 */

import { str } from './num';

/** Mapa de JSON decodificado — o `Map<String, dynamic>` do original. */
export type JsonObject = Record<string, unknown>;

/** `v is Map<String, dynamic>` para um valor vindo de `jsonDecode`. */
export function isJsonObject(v: unknown): v is JsonObject {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** Erro de coerção, como o `TypeError` do `as` do Dart. */
export class JsonTypeError extends TypeError {
  constructor(value: unknown, expected: string) {
    super(`type '${describe(value)}' is not a subtype of type '${expected}' in type cast`);
    this.name = 'TypeError';
  }
}

function describe(value: unknown): string {
  if (typeof value === 'string') return 'String';
  if (typeof value === 'boolean') return 'bool';
  if (typeof value === 'number') return Number.isInteger(value) ? 'int' : 'double';
  if (Array.isArray(value)) return 'List<dynamic>';
  if (typeof value === 'object' && value !== null) return '_JsonMap';
  return typeof value;
}

/** `(v as num?)?.toDouble()`: `null` para ausente, lança para não número. */
export function asDouble(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return v;
  throw new JsonTypeError(v, 'num?');
}

/** `v as num` — obrigatório. */
export function asNumRequired(v: unknown): number {
  if (typeof v === 'number') return v;
  throw new JsonTypeError(v, 'num');
}

/** `(v as num?)?.toInt()`: trunca como o `toInt` do Dart. */
export function asInt(v: unknown): number | null {
  const d = asDouble(v);
  if (d === null) return null;
  if (!Number.isFinite(d)) throw new Error(`Unsupported operation: ${String(d)}`);
  return Math.trunc(d);
}

/** `v as String?`. */
export function asString(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'string') return v;
  throw new JsonTypeError(v, 'String?');
}

/** `v as bool?`. */
export function asBool(v: unknown): boolean | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'boolean') return v;
  throw new JsonTypeError(v, 'bool?');
}

/** `v is num ? v.toDouble() : null` — a leitura tolerante, que não lança. */
export function numOrNull(v: unknown): number | null {
  return typeof v === 'number' ? v : null;
}

/** `v is String ? v : null`. */
export function stringOrNull(v: unknown): string | null {
  return typeof v === 'string' ? v : null;
}

/** Interpolação `'$v'` do Dart para um valor de JSON. */
export function interpolateJson(v: unknown): string {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number') return str(v);
  if (typeof v === 'string') return v;
  if (typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return `[${v.map(interpolateJson).join(', ')}]`;
  if (typeof v === 'object') {
    return `{${Object.entries(v as JsonObject)
      .map(([k, x]) => `${k}: ${interpolateJson(x)}`)
      .join(', ')}}`;
  }
  return String(v);
}
