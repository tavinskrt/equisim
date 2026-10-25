import { StateError } from '../lang/num';
import type { Failure } from './failure';

/**
 * Resultado de uma operação que pode falhar, sem usar exceções para fluxo de
 * controle esperado.
 *
 * A convenção do pacote é que **falta de dado e violação de invariante são
 * [Failure], não exceção**. Exceção fica reservada para defeito de
 * programação. Quem chama um `Result` decide o que fazer; quem provoca uma
 * exceção tem um bug a corrigir.
 */
abstract class ResultBase<T> {
  /** `true` quando é [Ok]. */
  get isOk(): boolean {
    return this instanceof Ok;
  }

  /** `true` quando é [Err]. */
  get isErr(): boolean {
    return this instanceof Err;
  }

  /**
   * Valor, ou `null` se for falha.
   *
   * **Ambíguo para `T` anulável**: use [isOk] ou [fold] quando o valor puder
   * ser nulo legitimamente.
   */
  get valueOrNull(): T | null {
    return this instanceof Ok ? (this.value as T) : null;
  }

  /** Falha, ou `null` se for sucesso. */
  get failureOrNull(): Failure | null {
    return this instanceof Err ? this.failure : null;
  }

  /** Valor, ou lança [StateError]. Use apenas em testes ou após checar [isOk]. */
  unwrap(): T {
    if (this instanceof Ok) return this.value as T;
    throw new StateError(`unwrap() em Err: ${(this as unknown as Err<T>).failure}`);
  }

  /**
   * Valor, ou [fallback] se for falha. **Descarta a falha em silêncio.**
   */
  getOrElse(fallback: T): T {
    return this.valueOrNull ?? fallback;
  }

  /** Transforma o valor de sucesso, preservando a falha. */
  map<R>(transform: (value: T) => R): Result<R> {
    if (this instanceof Ok) return new Ok<R>(transform(this.value as T));
    return new Err<R>((this as unknown as Err<T>).failure);
  }

  /** Encadeia outra operação que também pode falhar, sem aninhar. */
  flatMap<R>(transform: (value: T) => Result<R>): Result<R> {
    if (this instanceof Ok) return transform(this.value as T);
    return new Err<R>((this as unknown as Err<T>).failure);
  }

  /**
   * Colapsa os dois lados num único valor, tratando ambos explicitamente.
   * Exatamente uma das duas funções é chamada.
   */
  fold<R>(onOk: (value: T) => R, onErr: (failure: Failure) => R): R {
    if (this instanceof Ok) return onOk(this.value as T);
    return onErr((this as unknown as Err<T>).failure);
  }
}

/** Ramo de sucesso de um [Result]. */
export class Ok<T> extends ResultBase<T> {
  readonly kind = 'ok' as const;

  /** O valor produzido pela operação. */
  readonly value: T;

  constructor(value: T) {
    super();
    this.value = value;
  }

  override toString(): string {
    return `Ok(${String(this.value)})`;
  }
}

/** Ramo de falha de um [Result]. */
export class Err<T> extends ResultBase<T> {
  readonly kind = 'err' as const;

  /** O motivo da falha, já tipado. */
  readonly failure: Failure;

  constructor(failure: Failure) {
    super();
    this.failure = failure;
  }

  override toString(): string {
    return `Err(${this.failure.toString()})`;
  }
}

/** União selada: `switch (r.kind)` é exaustivo. */
export type Result<T> = Ok<T> | Err<T>;

/** Atalho para `Ok(value)`. */
export function ok<T>(value: T): Ok<T> {
  return new Ok(value);
}

/** Atalho para `Err(failure)`, com o tipo do sucesso livre. */
export function err<T = never>(failure: Failure): Err<T> {
  return new Err<T>(failure);
}
