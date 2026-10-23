import * as core from '../../core';
import { DartEnum, Ticker } from '../../core';

/**
 * Codificação de objetos do núcleo para atravessar `postMessage`.
 *
 * O clone estruturado do navegador copia dados, mas **perde o protótipo**: a
 * `ValuationInputs` que chega ao Web Worker seria um objeto sem métodos, e a
 * cascata quebraria no primeiro `series.closeAsOf(...)`. Esta codificação
 * etiqueta cada instância com o **nome de exportação** da classe no núcleo e a
 * reconstrói do outro lado sobre o protótipo certo.
 *
 * **Nome de exportação, e não `constructor.name`.** O build minificado renomeia
 * classes, mas não as chaves do objeto de módulo (`import * as core`): elas
 * são a superfície pública do pacote. O registro abaixo é montado dessa forma
 * dos dois lados, e por isso concorda mesmo com o código minificado.
 *
 * Três casos especiais preservam identidade, que o núcleo usa como igualdade:
 *
 * - **enums** (`DartEnum`) voltam como a instância estática de mesmo nome — o
 *   núcleo compara `lane === ValuationLane.firm`;
 * - **`Ticker`** volta pelo `Ticker.parse`, que o reinterna — `Map<Ticker, …>`
 *   compara por identidade;
 * - `Map` e `Set` são percorridos, porque suas chaves e valores também podem
 *   ser instâncias.
 *
 * Classe que o núcleo não exporta, ou função dentro do objeto, lança
 * [StructuredCodecError]: o executor então desiste do Worker e calcula em
 * linha, com o mesmo resultado.
 */

/** O objeto não pode atravessar a fronteira sem perder significado. */
export class StructuredCodecError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StructuredCodecError';
  }
}

type Constructor = abstract new (...args: never[]) => unknown;

interface Registry {
  readonly nameOf: Map<Constructor, string>;
  readonly byName: Map<string, Constructor>;
}

let registry: Registry | null = null;

function buildRegistry(): Registry {
  const nameOf = new Map<Constructor, string>();
  const byName = new Map<string, Constructor>();
  for (const [exportName, value] of Object.entries(core)) {
    if (typeof value !== 'function' || value.prototype === undefined) continue;
    const ctor = value as Constructor;
    byName.set(exportName, ctor);
    if (!nameOf.has(ctor)) nameOf.set(ctor, exportName);
  }
  return { nameOf, byName };
}

function reg(): Registry {
  return (registry ??= buildRegistry());
}

/** Forma codificada: só dados que o clone estruturado copia sem perda. */
export type Encoded =
  | null
  | boolean
  | number
  | string
  | undefined
  | { readonly $a: Encoded[] }
  | { readonly $o: Record<string, Encoded> }
  | { readonly $m: Array<[Encoded, Encoded]> }
  | { readonly $s: Encoded[] }
  | { readonly $e: string; readonly $n: string }
  | { readonly $t: string }
  | { readonly $c: string; readonly $f: Record<string, Encoded> };

function encodeFields(value: object, seen: Set<object>): Record<string, Encoded> {
  const fields: Record<string, Encoded> = {};
  for (const key of Object.keys(value)) {
    fields[key] = encodeValue((value as Record<string, unknown>)[key], seen);
  }
  return fields;
}

function encodeValue(value: unknown, seen: Set<object>): Encoded {
  if (value === null || value === undefined) return value;
  const kind = typeof value;
  if (kind === 'number' || kind === 'string' || kind === 'boolean') return value as number | string | boolean;
  if (kind === 'function') throw new StructuredCodecError('Função não atravessa a fronteira do Worker.');
  if (kind !== 'object') throw new StructuredCodecError(`Valor de tipo ${kind} não suportado.`);
  const obj = value as object;
  if (seen.has(obj)) throw new StructuredCodecError('Referência circular não suportada.');
  seen.add(obj);
  try {
    if (Array.isArray(obj)) return { $a: obj.map((v) => encodeValue(v, seen)) };
    if (obj instanceof Map) return { $m: [...obj].map(([k, v]) => [encodeValue(k, seen), encodeValue(v, seen)]) };
    if (obj instanceof Set) return { $s: [...obj].map((v) => encodeValue(v, seen)) };
    if (obj instanceof Ticker) return { $t: obj.value };
    const proto: unknown = Object.getPrototypeOf(obj);
    if (proto === Object.prototype || proto === null) return { $o: encodeFields(obj, seen) };
    const ctor = (proto as { constructor: Constructor }).constructor;
    const name = reg().nameOf.get(ctor);
    if (name === undefined) throw new StructuredCodecError('Classe que o núcleo não exporta não atravessa o Worker.');
    if (obj instanceof DartEnum) return { $e: name, $n: obj.name };
    return { $c: name, $f: encodeFields(obj, seen) };
  } finally {
    seen.delete(obj);
  }
}

function decodeValue(value: Encoded): unknown {
  if (value === null || value === undefined || typeof value !== 'object') return value;
  if ('$a' in value) return value.$a.map(decodeValue);
  if ('$o' in value) return decodeFields(value.$o, {});
  if ('$m' in value) return new Map(value.$m.map(([k, v]) => [decodeValue(k), decodeValue(v)]));
  if ('$s' in value) return new Set(value.$s.map(decodeValue));
  if ('$t' in value) return Ticker.parse(value.$t);
  if ('$e' in value) {
    const ctor = reg().byName.get(value.$e) as unknown as { values?: readonly DartEnum[] } | undefined;
    const found = ctor?.values?.find((v) => v.name === value.$n);
    if (found === undefined) throw new StructuredCodecError(`Enum desconhecido: ${value.$e}.${value.$n}`);
    return found;
  }
  const ctor = reg().byName.get(value.$c);
  if (ctor === undefined) throw new StructuredCodecError(`Classe desconhecida: ${value.$c}`);
  return decodeFields(value.$f, Object.create(ctor.prototype as object) as Record<string, unknown>);
}

function decodeFields(fields: Record<string, Encoded>, target: Record<string, unknown>): Record<string, unknown> {
  for (const key of Object.keys(fields)) target[key] = decodeValue(fields[key]);
  return target;
}

export const StructuredCodec = {
  /** Codifica [value]; lança [StructuredCodecError] no que não atravessa. */
  encode(value: unknown): Encoded {
    return encodeValue(value, new Set());
  },

  /** Reconstrói o valor codificado, com os protótipos e as identidades do núcleo. */
  decode<T>(value: Encoded): T {
    return decodeValue(value) as T;
  },
} as const;
