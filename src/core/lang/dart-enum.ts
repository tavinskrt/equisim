/**
 * Base dos enums portados do Dart.
 *
 * O Dart tem enum com campo, método e interface; o `enum` do TypeScript não.
 * Cada enum do motor vira, portanto, uma classe com instâncias estáticas,
 * preservando o que o original oferecia: [name], [index], a lista `values` e o
 * `toString` no formato `Tipo.valor`.
 */
export abstract class DartEnum {
  /** Nome do valor no código, como o `name` do Dart. */
  readonly name: string;

  /** Posição na declaração, como o `index` do Dart. */
  readonly index: number;

  protected constructor(name: string, index: number) {
    this.name = name;
    this.index = index;
  }

  /** Nome do tipo, para o `toString` no formato do Dart. */
  protected abstract get typeName(): string;

  toString(): string {
    return `${this.typeName}.${this.name}`;
  }
}

/**
 * Valor que se grava pela própria chave, e não pelo nome do identificador.
 *
 * Os enums cujo texto sai do código — no pacote de dados, no rastro de
 * auditoria, num relatório — implementam esta interface, para que o nome do
 * valor possa mudar sem mudar o que se grava. `AuditJson.safe` lê [key] antes
 * de `name`.
 */
export interface WireKeyed {
  /** O texto gravado. */
  readonly key: string;
  /** Marca estrutural: só quem declara a interface é tratado como tal. */
  readonly wireKeyed: true;
}

/** `true` quando [value] implementa [WireKeyed]. */
export function isWireKeyed(value: unknown): value is WireKeyed {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { wireKeyed?: unknown }).wireKeyed === true &&
    typeof (value as { key?: unknown }).key === 'string'
  );
}
