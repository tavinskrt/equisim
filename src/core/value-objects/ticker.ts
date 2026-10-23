import { FormatException } from '../lang/num';

/**
 * Código de negociação de uma ação da B3.
 *
 * O universo é definido por `/v2/tickers?type=stock`, que já exclui fundos
 * (verificado: 781 ações contra 332 FIIs, interseção vazia). Não há, portanto,
 * inferência de classe a partir do sufixo — Units como `TAEE11` são ações.
 *
 * **Instância única por código.** O Dart comparava tickers por valor, e os
 * usava como chave de mapa. Aqui cada código tem uma instância só (um cache
 * interno), de modo que `Map<Ticker, …>` e `Set<Ticker>` do JavaScript, que
 * comparam por identidade, se comportam como os do Dart.
 */
export class Ticker {
  /**
   * Código normalizado, sempre em maiúsculas e sem espaços. Só construtores
   * validantes produzem instâncias, então esta invariante é garantida.
   */
  readonly value: string;

  private constructor(value: string) {
    this.value = value;
  }

  private static readonly cache = new Map<string, Ticker>();

  /**
   * Raiz de quatro caracteres iniciada por letra, seguida do código da classe.
   *
   * A raiz aceita dígitos porque a B3 os usa: **B3SA3**, a própria bolsa, tem
   * "3" na segunda posição. Tickers do mercado fracionário (`PETR4F`) são
   * rejeitados naturalmente, porque o sufixo não é dígito.
   */
  private static readonly pattern = /^[A-Z][A-Z0-9]{3}\d{1,2}$/;

  /**
   * Normaliza e valida. Lança [FormatException] em entrada inválida.
   *
   * Use em fronteira de dados confiável — resposta de API, valor persistido.
   * Para entrada digitada, prefira [Ticker.tryParse].
   */
  static parse(raw: string): Ticker {
    const normalized = raw.trim().toUpperCase();
    const cached = Ticker.cache.get(normalized);
    if (cached !== undefined) return cached;
    if (!Ticker.pattern.test(normalized)) {
      throw new FormatException(`Ticker inválido: "${raw}"`);
    }
    const created = new Ticker(normalized);
    Ticker.cache.set(normalized, created);
    return created;
  }

  /** Retorna `null` em vez de lançar — para entrada de usuário. */
  static tryParse(raw: string): Ticker | null {
    try {
      return Ticker.parse(raw);
    } catch (e) {
      if (e instanceof FormatException) return null;
      throw e;
    }
  }

  compareTo(other: Ticker): number {
    return this.value === other.value ? 0 : this.value < other.value ? -1 : 1;
  }

  equals(other: unknown): boolean {
    return other instanceof Ticker && other.value === this.value;
  }

  toString(): string {
    return this.value;
  }
}
