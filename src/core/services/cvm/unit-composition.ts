/** A composição declarada de uma unit, do Formulário Cadastral da CVM (item B16). */

import type { DateTime } from '../../lang/date-time';
import { asInt, asString, isJsonObject, type JsonObject } from '../../lang/json';
import { compareNum, parseInt_ } from '../../lang/num';

/**
 * Quantas ações a unit reúne, **segundo a companhia**, num ano do formulário.
 *
 * **Por que existe.** A razão de unidade era inferida do valor de mercado —
 * `contagem × preço da unit ÷ valor de mercado` —, e essa razão só devolve o
 * número de ações da unit quando ordinária e preferencial valem o mesmo.
 * Medida nas coortes contra esta composição, ela erra 79 de 220 observações:
 * em 49 cai em 1, e a unit é avaliada como ação; em 12 cai no inteiro errado
 * dentro da folga de 5% — a ENGI11 com 4 em vez de 5 —, sem aviso; em 18 a
 * espécie não negocia e o valor de mercado volta a ser a contagem vezes o
 * preço da unit, o que devolve 1 por construção. Ver
 * `docs/validacao/ponte_por_papel.md` §3.
 *
 * **A fonte é primária e datada.** O quadro de valores mobiliários da FCA
 * (`fca_cia_aberta_valor_mobiliario_<ano>.csv`) traz, para cada unit, a coluna
 * `Composicao_BDR_Unit` em texto livre — "1 ON e 4 PN", "1 KLBN3 + 4 KLBN4",
 * "2 ações preferenciais e 1 ação ordinária". Um formulário por ano, de modo
 * que a composição de uma avaliação datada é a do formulário mais recente
 * **até** a data dela.
 */
export class UnitComposition {
  /** Ano do formulário de onde a composição foi lida. */
  readonly year: number;

  /** Ações reunidas na unit. Sempre ≥ 1. */
  readonly shares: number;

  /**
   * O texto como a companhia o declarou. Viaja junto para que o rastro de
   * auditoria mostre a fonte, e não só o número.
   */
  readonly declared: string;

  constructor(args: { year: number; shares: number; declared: string }) {
    this.year = args.year;
    this.shares = args.shares;
    this.declared = args.declared;
  }
}

/**
 * Quantidade seguida de espécie de ação. Recibo e bônus de subscrição não
 * são ação e não casam.
 *
 * O código de negociação entra com **três ou quatro letras**: a ENGI11 de
 * 2018 declara "1 ENG3 e 4 ENGI4", e exigir quatro letras somava só o 4.
 */
const TERM =
  /(\d+)\s*(?:A[CÇ][OÕ]ES\s+|A[CÇ][AÃ]O\s+)?(?:ON\b|PN[A-Z]?\b|ORDIN[AÁ]RIAS?|PREFERENCIA(?:IS|L)|[A-Z]{3,4}[3-8]\b)/g;

/** Leitura do texto livre e serialização do pacote. */
export const UnitCompositionCodec = {
  /** Versão do formato do pacote. */
  version: 1,

  /**
   * Teto de ações por unit, o mesmo de `ValuationCascade.maxSharesPerUnit`.
   *
   * As units da B3 vão até 5 — 1 ON e 4 PN. O teto existe para que um texto
   * mal lido não vire divisor absurdo.
   */
  maxShares: 10,

  /**
   * Ações numa unit, somando as quantidades declaradas antes de cada espécie.
   *
   * "1 ON e 4 PN" dá 5, "2 ações preferenciais e 1 ação ordinária" dá 3,
   * "1 KLBN3 + 4 KLBN4" dá 5, "1 ENG3 e 4 ENGI4" dá 5.
   *
   * **Recibo de subscrição não é ação**: a BMGB11 declara "1 PN + 3 Recibos de
   * Subscrição" e tem uma ação. Devolve `null` quando o texto não tem
   * quantidade de espécie reconhecível, e quando a soma passa de [maxShares] —
   * nos dois casos quem chama recua para a razão medida, declarando.
   */
  parse(text: string): number | null {
    let sum = 0;
    for (const m of text.toUpperCase().matchAll(TERM)) {
      sum += parseInt_(m[1]!);
    }
    if (sum < 1 || sum > UnitCompositionCodec.maxShares) return null;
    return sum;
  },

  /**
   * A composição declarada mais recente **até** [asOf], ou `null`.
   *
   * Formulário posterior à data da avaliação não entra: numa coorte de 2019 a
   * composição de 2024 seria conhecimento futuro. Ano do formulário contra ano
   * da avaliação, e não data contra data, porque a FCA é anual e a entrega
   * varia de mês.
   */
  at(declared: readonly UnitComposition[], asOf: DateTime): UnitComposition | null {
    let best: UnitComposition | null = null;
    for (const c of declared) {
      if (c.year > asOf.year) continue;
      if (best === null || c.year > best.year) best = c;
    }
    return best;
  },

  /** Grava o pacote: composições por código de unit, por ano. */
  encodePackage(byTicker: ReadonlyMap<string, readonly UnitComposition[]>, args: { generatedAt: DateTime }): JsonObject {
    const units: JsonObject = {};
    for (const [key, value] of byTicker) {
      units[key] = [...value]
        .sort((a, b) => compareNum(a.year, b.year))
        .map((c) => ({ ano: c.year, acoes: c.shares, texto: c.declared }));
    }
    return {
      versao: UnitCompositionCodec.version,
      geradoEm: args.generatedAt.toIso8601String().substring(0, 10),
      units,
    };
  },

  /**
   * Lê o pacote. Entrada malformada é **pulada**, e não derruba a leitura: uma
   * unit sem composição recua para a razão medida, que é o comportamento
   * anterior.
   */
  decodePackage(pkg: JsonObject): Map<string, UnitComposition[]> {
    const out = new Map<string, UnitComposition[]>();
    const units = pkg['units'];
    if (!isJsonObject(units)) return out;
    for (const [key, list] of Object.entries(units)) {
      if (!Array.isArray(list)) continue;
      const compositions: UnitComposition[] = [];
      for (const x of list) {
        if (!isJsonObject(x)) continue;
        const year = asInt(x['ano']);
        const shares = asInt(x['acoes']);
        if (year === null || shares === null || shares < 1 || shares > UnitCompositionCodec.maxShares) {
          continue;
        }
        compositions.push(new UnitComposition({ year, shares, declared: asString(x['texto']) ?? '' }));
      }
      if (compositions.length > 0) out.set(key, compositions);
    }
    return out;
  },
};
