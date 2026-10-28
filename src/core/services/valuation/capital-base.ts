/** Séries de capital, retorno e retenção que alimentam as guardas da Porta 2. */

import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DartEnum } from '../../lang/dart-enum';
import { sortedNums, sublist } from '../../lang/iter';
import { clamp, intDiv } from '../../lang/num';
import { Inference } from './inference';

/**
 * De quem é o fluxo que se desconta.
 *
 * Decide a base de capital, o retorno medido sobre ela e o desconto aplicado —
 * as três coisas andam juntas e não se combinam entre vias.
 */
export class ValuationLane extends DartEnum {
  /** Fluxo da firma: capital investido, ROIC, WACC, com ponte de dívida. */
  static readonly firm = new ValuationLane('firm', 0);

  /** Fluxo do acionista: patrimônio líquido, ROE, Ke, sem ponte. */
  static readonly shareholder = new ValuationLane('shareholder', 1);

  static readonly values: readonly ValuationLane[] = [ValuationLane.firm, ValuationLane.shareholder];

  protected get typeName(): string {
    return 'ValuationLane';
  }
}

/** Um exercício com base de capital e lucro na convenção da via. */
export class CapitalPoint {
  /** Ano fiscal. */
  readonly year: number;

  /** Base de capital no fecho do exercício. */
  readonly base: number;

  /**
   * Lucro do exercício na convenção da via: NOPAT na firma, lucro líquido no
   * acionista. `null` quando a fonte não publica.
   */
  readonly profit: number | null;

  /**
   * `true` no ano corrente anualizado (decisão 153): o lucro é de um ano, mas
   * a base é a da data do ITR, e a variação dela até aqui não é anual.
   */
  readonly partial: boolean;

  constructor(args: { year: number; base: number; profit: number | null; partial?: boolean }) {
    this.year = args.year;
    this.base = args.base;
    this.profit = args.profit;
    this.partial = args.partial ?? false;
  }
}

/** Um valor anual — o registro `({int year, double value})` do original. */
export interface YearValue {
  readonly year: number;
  readonly value: number;
}

/**
 * Descarta o ponto que destoa da **mediana dos vizinhos próximos**.
 *
 * A referência é a mediana de até [CapitalSeries.neighbourRadius] pontos de
 * cada lado, e não o vizinho imediato. A diferença importa na ponta: com um
 * vizinho só, um exercício legítimo adjacente a uma falha da fonte seria
 * descartado junto — o bom seria julgado contra o ruim, e os dois cairiam.
 */
function cleanByNeighbour(s: readonly CapitalPoint[]): readonly CapitalPoint[] {
  if (s.length < 4) return s;
  const ok: CapitalPoint[] = [];
  for (let i = 0; i < s.length; i++) {
    const neighbors: number[] = [];
    for (let j = i - CapitalSeries.neighbourRadius; j <= i + CapitalSeries.neighbourRadius; j++) {
      if (j === i || j < 0 || j >= s.length) continue;
      neighbors.push(s[j]!.base);
    }
    if (neighbors.length < 2) {
      ok.push(s[i]!);
      continue;
    }
    const sortedNeighbors = sortedNums(neighbors);
    const m = intDiv(sortedNeighbors.length, 2);
    const reference =
      sortedNeighbors.length % 2 === 1 ? sortedNeighbors[m]! : (sortedNeighbors[m - 1]! + sortedNeighbors[m]!) / 2;
    if (reference <= 0) {
      ok.push(s[i]!);
      continue;
    }
    const ratio = s[i]!.base / reference;
    if (ratio < 1 / CapitalSeries.neighbourFactor || ratio > CapitalSeries.neighbourFactor) continue;
    ok.push(s[i]!);
  }
  return ok;
}

/**
 * Série de capital de um ativo, já limpa e na convenção de uma via.
 *
 * **A limpeza é por vizinhança, não por mediana global.** Um corte contra a
 * mediana de toda a série descarta anos legítimos de empresa que cresceu ordens
 * de magnitude: a PRIO3 multiplicou a base por trinta em oito anos, e o filtro
 * global apagava os exercícios recentes — os únicos que descrevem a empresa de
 * hoje. O critério de vizinhança pega o que se quer pegar, que é falha pontual
 * da fonte: o `bookValue` da ABEV3 em 2012 vem R$ 0,062 contra R$ 2,81 no ano
 * seguinte.
 */
export class CapitalSeries {
  /** Exercícios utilizáveis, em ordem cronológica. */
  readonly points: readonly CapitalPoint[];

  /** Via cuja convenção a série segue. */
  readonly lane: ValuationLane;

  constructor(args: { points: readonly CapitalPoint[]; lane: ValuationLane }) {
    this.points = args.points;
    this.lane = args.lane;
  }

  /**
   * Fator de destoamento tolerado contra a vizinhança.
   *
   * **Deliberadamente largo.** Este filtro existe para falha da fonte, que é de
   * ordem de grandeza — o `bookValue` da ABEV3 em 2012 vem R$ 0,062 contra
   * R$ 2,81 no ano seguinte, um fator de 45. Salto real de base, como o de uma
   * incorporação, fica entre 2 e 9 vezes e **precisa passar**: quem o julga é a
   * guarda de comparabilidade, que mede quanto da expansão veio de capital
   * externo. Um filtro apertado o apagaria antes, e a guarda mediria uma série
   * da qual o próprio evento já teria sido removido.
   */
  static readonly neighbourFactor = 8.0;

  /**
   * Monta a série a partir dos exercícios publicados.
   *
   * - [snapshots]: exercícios em ordem cronológica, já filtrados por
   *   publicação.
   * - [lane]: convenção a aplicar.
   * - [firmTaxRate]: alíquota estrutural da via da firma, de
   *   [structuralTaxRate]. Nula reproduz o comportamento anterior, que é a
   *   alíquota estatutária embutida pela fonte no `NOPAT` publicado.
   */
  static build(
    snapshots: readonly FundamentalsSnapshot[],
    lane: ValuationLane,
    options: { firmTaxRate?: number | null } = {},
  ): CapitalSeries {
    const firmTaxRate = options.firmTaxRate ?? null;
    const rawSessions: CapitalPoint[] = [];
    for (const s of snapshots) {
      const base = lane === ValuationLane.firm ? s.investedCapital : s.equityBookValue;
      if (base === null || base <= 0) continue;
      rawSessions.push(
        new CapitalPoint({
          year: s.fiscalPeriodEnd.year,
          base,
          profit: lane === ValuationLane.firm ? s.nopatAtRate(firmTaxRate) : s.netIncome,
          partial: s.isAnnualized,
        }),
      );
    }
    return new CapitalSeries({ points: cleanByNeighbour(rawSessions), lane });
  }

  /**
   * Exercícios mínimos com alíquota medível para a estrutural ser usada.
   *
   * Cinco. Abaixo disso a mediana descreve poucos anos e um único exercício
   * atípico a domina — e o recuo, que é a estatutária, é conservador na
   * direção que este projeto já assume.
   */
  static readonly minTaxObservations = 5;

  /**
   * Alíquota **estrutural** de imposto do ativo: a mediana dos exercícios.
   *
   * **Mediana e não último exercício, de propósito.** É ela que separa
   * incentivo estrutural de evento: prejuízo fiscal compensado num ano move a
   * alíquota daquele ano e não a mediana de quinze. Medido em 10/09/2026, a
   * dispersão robusta dentro da empresa é de 7,5 p.p. na mediana — a alíquota
   * brasileira é regime, e um regime é o que se projeta.
   *
   * Confinada em `[0, alíquota estatutária]`. O teto existe porque pagar mais
   * que a marginal em perpetuidade é transitório — reversão de diferido,
   * operação no exterior —, e a fonte já aplicou a estatutária; ir além
   * penalizaria duas vezes.
   *
   * Devolve `null` com menos de [minTaxObservations] exercícios medíveis, o
   * que faz o chamador recuar para o `NOPAT` publicado.
   */
  static structuralTaxRate(
    snapshots: readonly FundamentalsSnapshot[],
    args: { statutoryRate: number },
  ): number | null {
    const rates: number[] = [];
    for (const s of snapshots) {
      const t = s.effectiveTaxRate;
      if (t !== null && Number.isFinite(t)) rates.push(t);
    }
    if (rates.length < CapitalSeries.minTaxObservations) return null;
    const m = Inference.median(rates);
    if (m === null || !Number.isFinite(m)) return null;
    return clamp(m, 0.0, args.statutoryRate);
  }

  /** Quantos vizinhos de cada lado formam a referência local. */
  static readonly neighbourRadius = 2;

  /** Exercícios na série. */
  get length(): number {
    return this.points.length;
  }

  /** `true` quando não há pontos suficientes para qualquer estatística. */
  get isTooShort(): boolean {
    return this.points.length < 4;
  }

  /**
   * Base do exercício mais recente.
   *
   * É contra ela que o retorno do ciclo é aplicado quando o exercício
   * corrente vem no prejuízo: `fluxo-base = retorno do ciclo × capital de
   * hoje` é a mesma conta que o fator de normalização faz, escrita de um
   * jeito que sobrevive a um denominador não positivo (decisão 53).
   */
  get latestBase(): number | null {
    return this.points.length === 0 ? null : this.points[this.points.length - 1]!.base;
  }

  /**
   * Variações anuais da base, só entre exercícios **consecutivos**.
   *
   * Buraco na série interrompe o par: comparar 2019 com 2021 como se fosse um
   * ano mediria dois anos de crescimento. Pelo mesmo motivo o ano corrente
   * anualizado fica de fora: a base dele está a meses da anterior, e não a um
   * ano (decisão 153).
   */
  get annualVariations(): number[] {
    const v: number[] = [];
    for (let i = 1; i < this.points.length; i++) {
      const a = this.points[i - 1]!;
      const b = this.points[i]!;
      if (b.year - a.year !== 1 || a.base <= 0 || b.partial) continue;
      v.push(b.base / a.base - 1);
    }
    return v;
  }

  /**
   * Retorno sobre a base de **abertura**, por exercício.
   *
   * Abertura e não fecho: o lucro do ano foi produzido pelo capital que existia
   * no começo dele. Usar o fecho subestima o retorno de quem cresceu.
   *
   * **Exercício de prejuízo entra, com o sinal que tem.** Descartá-lo era viés
   * de sobrevivência dentro da própria empresa: a mediana do ciclo passava a
   * descrever apenas os anos bons dela, e o ciclo é justamente o que alterna
   * bons e maus. Medido em 07/09/2026 sobre o universo elegível, 52 dos 120
   * avaliados tinham ao menos um exercício descartado, e a mediana do ciclo
   * saía inflada em até 33 pontos percentuais — a CVCB3 acusava 33,8% de ROIC
   * mediano contra 0,55% com os quatro anos de prejuízo no lugar, e a MGLU3
   * 22,4% contra 11,2%. Como o fator de normalização é `ciclo / atual` e o DCF
   * é homogêneo de grau 1 no fluxo-base, o viés ia inteiro para o preço justo.
   *
   * Exercício **sem lucro publicado** continua fora: ausência de dado não é
   * retorno nulo, e incluí-la como zero inventaria observação.
   */
  get returns(): YearValue[] {
    const r: YearValue[] = [];
    for (let i = 1; i < this.points.length; i++) {
      const a = this.points[i - 1]!;
      const b = this.points[i]!;
      if (b.year - a.year !== 1 || a.base <= 0) continue;
      const l = b.profit;
      if (l === null) continue;
      r.push({ year: b.year, value: l / a.base });
    }
    return r;
  }

  /**
   * Retenção observada por exercício, em `[0, 1]`.
   *
   * `ΔBase / lucro` — a fração do lucro que ficou na empresa. Confinada porque
   * valor fora do intervalo não é retenção: acima de 1 houve capital externo,
   * abaixo de 0 houve distribuição além do lucro, e os dois casos são tratados
   * pela guarda de comparabilidade, não aqui. O ano corrente anualizado fica
   * de fora: a base dele variou por meses, e o lucro é de um ano.
   */
  get retentions(): number[] {
    const b: number[] = [];
    for (let i = 1; i < this.points.length; i++) {
      const a = this.points[i - 1]!;
      const c = this.points[i]!;
      if (c.year - a.year !== 1 || a.base <= 0 || c.partial) continue;
      const l = c.profit;
      if (l === null || l <= 0) continue;
      b.push(clamp((c.base - a.base) / l, 0.0, 1.0));
    }
    return b;
  }

  /**
   * Mediana do retorno na janela do ciclo, excluindo o exercício corrente.
   *
   * - [window]: exercícios do ciclo. O corrente fica de fora porque é
   *   justamente ele que se quer comparar contra o ciclo.
   */
  cycleReturn(args: { window: number }): number | null {
    const r = this.returns;
    if (r.length < 4) return null;
    const ini = r.length - 1 - args.window;
    const windowValues = sublist(r, ini < 0 ? 0 : ini, r.length - 1);
    if (windowValues.length < 3) return null;
    return Inference.median(windowValues.map((x) => x.value));
  }

  /**
   * Fração dos retornos da janela do ciclo que são positivos.
   *
   * **Separa o vale do declínio.** A mediana do ciclo pode sair positiva com
   * metade dos anos no prejuízo — e nesse caso ela descreve uma empresa que
   * alterna, não uma que caiu num ano ruim. Medido em 11/09/2026: a AZEV4
   * tinha mediana de retorno sobre patrimônio de +10,2% com quatro dos oito
   * exercícios negativos.
   *
   * Devolve `null` com a mesma janela curta que [cycleReturn] recusa, para
   * que as duas medidas nunca discordem sobre haver ciclo.
   */
  positiveShare(args: { window: number }): number | null {
    const r = this.returns;
    if (r.length < 4) return null;
    const ini = r.length - 1 - args.window;
    const windowValues = sublist(r, ini < 0 ? 0 : ini, r.length - 1);
    if (windowValues.length < 3) return null;
    return windowValues.filter((x) => x.value > 0).length / windowValues.length;
  }

  /** Retorno do exercício mais recente. */
  get latestReturn(): number | null {
    const r = this.returns;
    return r.length === 0 ? null : r[r.length - 1]!.value;
  }

  /** Retenção mediana observada, ou `null` sem pares suficientes. */
  get medianRetention(): number | null {
    const b = this.retentions;
    return b.length < 5 ? null : Inference.median(b);
  }
}
