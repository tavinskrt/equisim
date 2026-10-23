import { round, str, toStringAsFixed, UnsupportedError } from '../lang/num';

/**
 * Valor monetário representado em **centavos inteiros**.
 *
 * Dinheiro nunca é `double` no domínio: somas repetidas de `double` acumulam
 * erro de ponto flutuante, e num backtest com 120 aportes o desvio é visível.
 * Preços de mercado continuam sendo `double` (são cotações, não saldos).
 *
 * **Consequência para comparação.** Por serem inteiros, a igualdade e os
 * operadores de ordem são exatos aqui — a proibição usual de comparar dinheiro
 * com `==` vale para representação em ponto flutuante, não para esta.
 *
 * **Regra de arredondamento.** [times] arredonda por `round()` do Dart, e
 * [Money.fromReais] pelo decimal escrito (ver lá) — nos dois casos *meio
 * afastado de zero*, e não *meio para cima*: `round(-2.5) === -3`.
 *
 * **O que esta classe não faz.** Não distribui resto. Quem divide dinheiro
 * entre vários destinos precisa tratar o resíduo explicitamente no ponto da
 * divisão.
 */
export class Money {
  /** Quantidade de centavos. É a única representação canônica do valor. */
  readonly cents: number;

  /**
   * Constrói a partir da quantidade de centavos, sem validação. Valores
   * negativos são legítimos e representam saída de caixa.
   */
  constructor(cents: number) {
    this.cents = cents;
  }

  /**
   * Converte um valor em reais para centavos, arredondando **o decimal
   * escrito** meio afastado de zero.
   *
   * **É a fronteira do `double` para o dinheiro.** Até 22/09/2026 ela fazia
   * `(reais * 100).round()`, e o produto em ponto flutuante perdia o meio:
   * `1.005 * 100` resulta em `100.49999999999999`, e R$ 1,005 virava R$ 1,00
   * (item B21, decisão 125). Agora o arredondamento é feito sobre a **menor
   * representação decimal** do `double`: `1.005` dá 101 centavos, `2.675` dá
   * 268, `-1.005` dá −101; `0.1 + 0.2` dá 30.
   *
   * Lança [UnsupportedError] se [reais] for `NaN` ou infinito.
   */
  static fromReais(reais: number): Money {
    return new Money(Money.centsOf(reais));
  }

  /** Centavos de [reais], arredondando o decimal escrito meio afastado de zero. */
  private static centsOf(reais: number): number {
    if (Number.isInteger(reais)) return reais * 100;
    const d = reais;
    if (!Number.isFinite(d)) {
      throw new UnsupportedError('Infinity or NaN toInt');
    }
    const magnitude = Math.abs(d);
    // Acima de 1e15 o `double` já não tem casa de centavo, e o produto é
    // inteiro; abaixo de 1e-6 `toString` usa notação científica, e o valor é
    // menos de meio centavo.
    if (magnitude >= 1e15) return round(d * 100);
    if (magnitude < 1e-6) return 0;
    const parts = str(magnitude).split('.');
    const fraction = (parts.length > 1 ? parts[1]! : '').padEnd(3, '0');
    let c = parseInt(parts[0]!, 10) * 100 + parseInt(fraction.substring(0, 2), 10);
    // O terceiro dígito decide: 5 ou mais é meio centavo ou além.
    if (fraction.charCodeAt(2) >= 0x35) c += 1;
    return d < 0 ? -c : c;
  }

  /** Zero absoluto. Ponto neutro da soma. */
  static readonly zero = new Money(0);

  /**
   * Valor em reais, para exibição e para cálculo em ponto flutuante.
   * **Fronteira de apresentação.**
   */
  get reais(): number {
    return this.cents / 100.0;
  }

  /** `true` quando o valor é exatamente zero centavo. */
  get isZero(): boolean {
    return this.cents === 0;
  }

  /** `true` quando o valor é **estritamente** maior que zero. */
  get isPositive(): boolean {
    return this.cents > 0;
  }

  /** Soma exata, em aritmética inteira. */
  plus(other: Money): Money {
    return new Money(this.cents + other.cents);
  }

  /** Subtração exata, em aritmética inteira. O resultado pode ser negativo. */
  minus(other: Money): Money {
    return new Money(this.cents - other.cents);
  }

  /**
   * Multiplica por um fator adimensional, arredondando o resultado meio
   * afastado de zero. **O resto é perdido.**
   *
   * Lança [UnsupportedError] se [factor] for `NaN` ou infinito.
   */
  times(factor: number): Money {
    return new Money(round(this.cents * factor));
  }

  /** Inverte o sinal. Exato. */
  negate(): Money {
    return new Money(-this.cents);
  }

  /** Menor ou igual a [other]. */
  lte(other: Money): boolean {
    return this.cents <= other.cents;
  }

  compareTo(other: Money): number {
    return this.cents < other.cents ? -1 : this.cents > other.cents ? 1 : 0;
  }

  equals(other: unknown): boolean {
    return other instanceof Money && other.cents === this.cents;
  }

  toString(): string {
    return `R$ ${toStringAsFixed(this.reais, 2)}`;
  }
}
