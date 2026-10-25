import { InvalidInput } from '../failures/failure';
import { err, ok, type Result } from '../failures/result';

/**
 * Duas séries de retorno que **não podem** ter comprimentos diferentes.
 *
 * Existe para tirar a conferência de dimensão de dentro do cálculo: quem tem
 * um [PairedReturns] em mãos já sabe que as duas pontas casam. A regra vale
 * para o **comprimento**, não para o conteúdo.
 */
export class PairedReturns {
  /** Retornos do ativo, na ordem em que foram pareados. */
  readonly asset: readonly number[];

  /** Retornos do índice, alinhados a [asset] posição a posição. */
  readonly market: readonly number[];

  /** @internal Use [PairedReturnsBuilder]. */
  constructor(asset: readonly number[], market: readonly number[]) {
    this.asset = asset;
    this.market = market;
  }

  /** Quantidade de pares. */
  get length(): number {
    return this.asset.length;
  }
}

/**
 * Acumulador de [PairedReturns], um par por vez. Acrescentar os dois números
 * numa chamada só é o que torna o desalinhamento **inexprimível**.
 */
export class PairedReturnsBuilder {
  private readonly assetValues: number[] = [];
  private readonly marketValues: number[] = [];

  /** Acrescenta um par de retornos do mesmo período. */
  add(pair: { asset: number; market: number }): void {
    this.assetValues.push(pair.asset);
    this.marketValues.push(pair.market);
  }

  /** Fecha o acumulado. As listas são copiadas. */
  build(): PairedReturns {
    return new PairedReturns(Object.freeze([...this.assetValues]), Object.freeze([...this.marketValues]));
  }
}

/**
 * Trajetória de patrimônio com os fluxos externos de cada período.
 *
 * O patrimônio de cada período e o aporte que entrou nele viajam juntos.
 */
export class WealthPath {
  /** Patrimônio ao fim de cada período, em ordem cronológica. */
  readonly values: readonly number[];

  /**
   * Fluxo externo entrado em cada período, alinhado a [values].
   *
   * **Aporte é positivo aqui** — convenção oposta à de `CashFlow`, porque a
   * fórmula do TWR subtrai o fluxo do valor final do período.
   */
  readonly externalFlows: readonly number[];

  /** @internal Use [WealthPath.of] ou [WealthPathBuilder]. */
  constructor(values: readonly number[], externalFlows: readonly number[]) {
    this.values = values;
    this.externalFlows = externalFlows;
  }

  /** Constrói a partir de duas séries prontas; [InvalidInput] se divergirem. */
  static of(args: { values: readonly number[]; externalFlows: readonly number[] }): Result<WealthPath> {
    if (args.values.length !== args.externalFlows.length) {
      return err(
        new InvalidInput(
          'Patrimônio e fluxos externos com tamanhos diferentes ' +
            `(${args.values.length} × ${args.externalFlows.length}).`,
        ),
      );
    }
    return ok(new WealthPath(Object.freeze([...args.values]), Object.freeze([...args.externalFlows])));
  }
}

/** Acumulador de [WealthPath], um período por vez. */
export class WealthPathBuilder {
  private readonly values: number[] = [];
  private readonly flows: number[] = [];

  /** Fecha um período com o patrimônio apurado e o fluxo que entrou nele. */
  add(period: { value: number; externalFlow: number }): void {
    this.values.push(period.value);
    this.flows.push(period.externalFlow);
  }

  /** Fecha o acumulado, copiando as listas. */
  build(): WealthPath {
    return new WealthPath(Object.freeze([...this.values]), Object.freeze([...this.flows]));
  }
}
