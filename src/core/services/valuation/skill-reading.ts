import type { JsonObject } from '../../lang/json';
import { isJsonObject } from '../../lang/json';
import { isInt } from '../../lang/num';
import { TransversalOrdering } from '../portfolio/transversal-ordering';

/** Uma ordenação medida nas coortes: o IC médio e o critério da decisão 96. */
export class OrderingReading {
  /** Correlação de postos média entre a ordenação e o retorno. */
  readonly ic: number;

  /** `t` do IC corrigido pela sobreposição das janelas. */
  readonly overlapT: number;

  /** Crítico do `t` corrigido, simulado sob a mesma sobreposição. */
  readonly overlapCritical: number;

  /** `t` de Newey-West do IC. */
  readonly neweyWestT: number;

  /** Declara a leitura. */
  constructor(args: { ic: number; overlapT: number; overlapCritical: number; neweyWestT: number }) {
    this.ic = args.ic;
    this.overlapT = args.overlapT;
    this.overlapCritical = args.overlapCritical;
    this.neweyWestT = args.neweyWestT;
  }

  /**
   * O critério da decisão 96: o `t` corrigido acima do crítico dele e o de
   * Newey-West acima de [SkillReading.neweyWestFloor].
   */
  get demonstrated(): boolean {
    return this.overlapT > this.overlapCritical && this.neweyWestT > SkillReading.neweyWestFloor;
  }
}

/**
 * A habilidade de ordenar medida nas coortes da validação (itens B1.0 e B1).
 *
 * Duas perguntas, empacotadas com o aplicativo:
 *
 * - **O potencial acrescenta ao book-to-market?** O coeficiente dele
 *   condicionado ao B/M, com o `t` corrigido pela sobreposição e o crítico dela
 *   (decisão 96). É o critério do R3, e é o que a ressalva da tela de metas
 *   cita.
 * - **Qual ordenação tem habilidade?** O IC do composto, do book-to-market e do
 *   potencial, sobre as mesmas observações, e a regra fixada antes de medir que
 *   escolhe de qual sai o prêmio do retorno esperado — [premiumOrdering]
 *   (decisão 103).
 *
 * **É a leitura do motor do dia da medição, e não o veredito do C1**, que é
 * medido com as fases completas.
 */
export class SkillReading {
  /** Horizonte do retorno, em meses. */
  readonly months: number;

  /** Coortes da regressão. */
  readonly cohorts: number;

  /** Coeficiente médio do potencial condicionado ao book-to-market, em posto normalizado. */
  readonly conditionalCoefficient: number;

  /** `t` do coeficiente condicionado, corrigido pela sobreposição. */
  readonly overlapT: number;

  /** Crítico do `t` corrigido. */
  readonly overlapCritical: number;

  /** `t` de Newey-West do coeficiente condicionado. */
  readonly neweyWestT: number;

  /** As ordenações medidas lado a lado. */
  readonly orderings: ReadonlyMap<TransversalOrdering, OrderingReading>;

  /** Declara a leitura. */
  constructor(args: {
    months: number;
    cohorts: number;
    conditionalCoefficient: number;
    overlapT: number;
    overlapCritical: number;
    neweyWestT: number;
    orderings: ReadonlyMap<TransversalOrdering, OrderingReading>;
  }) {
    this.months = args.months;
    this.cohorts = args.cohorts;
    this.conditionalCoefficient = args.conditionalCoefficient;
    this.overlapT = args.overlapT;
    this.overlapCritical = args.overlapCritical;
    this.neweyWestT = args.neweyWestT;
    this.orderings = args.orderings;
  }

  /** O `t` de Newey-West que a decisão 96 exige junto do corrigido. */
  static readonly neweyWestFloor = 2;

  /**
   * A ordem em que a regra do B1 procura a ordenação do prêmio: o modelo
   * transversal declarado, o fator de uma linha e o potencial.
   */
  static readonly premiumPreference: readonly TransversalOrdering[] = [
    TransversalOrdering.composite,
    TransversalOrdering.bookToMarket,
    TransversalOrdering.potential,
  ];

  /** O critério do R3 pela decisão 96, sobre o potencial dado o B/M. */
  get demonstrated(): boolean {
    return this.overlapT > this.overlapCritical && this.neweyWestT > SkillReading.neweyWestFloor;
  }

  /** IC médio do potencial, ou `null` sem a leitura. */
  get potentialIc(): number | null {
    return this.orderings.get(TransversalOrdering.potential)?.ic ?? null;
  }

  /** IC médio do book-to-market, ou `null` sem a leitura. */
  get bookToMarketIc(): number | null {
    return this.orderings.get(TransversalOrdering.bookToMarket)?.ic ?? null;
  }

  /**
   * **A ordenação de que sai o prêmio do retorno esperado**, ou `null` para
   * nenhuma: a primeira de [premiumPreference] que passa no critério da
   * decisão 96. Sem nenhuma que passe, não há prêmio — afirmar desconto
   * relativo como retorno seria afirmar habilidade que a validação não mediu.
   */
  get premiumOrdering(): TransversalOrdering | null {
    for (const o of SkillReading.premiumPreference) {
      if (this.orderings.get(o)?.demonstrated ?? false) return o;
    }
    return null;
  }
}

function finiteNumbers(values: readonly unknown[]): values is number[] {
  return values.every((v) => typeof v === 'number') && (values as number[]).every((v) => Number.isFinite(v));
}

/**
 * Formato do pacote da habilidade, gravado por
 * `tool/conditional-regression.ts --trimestral` e lido pelo aplicativo.
 */
export const SkillReadingCodec = {
  /** Versão do formato: a 2 traz as ordenações lado a lado (item B1). */
  version: 2,

  /** A chave de cada ordenação no pacote. */
  key(o: TransversalOrdering): string {
    switch (o) {
      case TransversalOrdering.composite:
        return 'composto';
      case TransversalOrdering.bookToMarket:
        return 'bookToMarket';
      default:
        return 'potencial';
    }
  },

  /**
   * Lê o pacote, ou `null` se ele estiver malformado — leitura inventada
   * esconderia a ressalva.
   */
  decode(pkg: JsonObject): SkillReading | null {
    if (pkg['versao'] !== SkillReadingCodec.version) return null;
    const months = pkg['horizonteMeses'];
    const cohorts = pkg['coortes'];
    const datum = pkg['potencialDadoBookToMarket'];
    const orderings = pkg['ordenacoes'];
    if (!isInt(months) || !isInt(cohorts) || !isJsonObject(datum) || !isJsonObject(orderings)) {
      return null;
    }
    const head = [datum['coeficiente'], datum['tCorrigido'], datum['critico'], datum['tNeweyWest']];
    if (!head.every((v) => typeof v === 'number')) return null;
    if (!finiteNumbers(head)) return null;
    const [coefficient, t, critical, nw] = head;

    const readings = new Map<TransversalOrdering, OrderingReading>();
    for (const o of TransversalOrdering.values) {
      const m = orderings[SkillReadingCodec.key(o)];
      if (!isJsonObject(m)) return null;
      const row = [m['ic'], m['tCorrigido'], m['critico'], m['tNeweyWest']];
      if (!row.every((v) => typeof v === 'number')) return null;
      if (!finiteNumbers(row)) return null;
      const [ic, tc, cr, tn] = row;
      readings.set(o, new OrderingReading({ ic: ic!, overlapT: tc!, overlapCritical: cr!, neweyWestT: tn! }));
    }
    return new SkillReading({
      months,
      cohorts,
      conditionalCoefficient: coefficient!,
      overlapT: t!,
      overlapCritical: critical!,
      neweyWestT: nw!,
      orderings: readings,
    });
  },
};
