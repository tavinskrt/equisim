/** O prazo das outorgas, lido do Formulário de Referência da CVM (item A6). */

import { DateTime } from '../../lang/date-time';
import { asInt, isJsonObject, type JsonObject } from '../../lang/json';
import { compareNum, intDiv, parseInt_, tryParseInt } from '../../lang/num';

const MONTHS: ReadonlyMap<string, number> = new Map([
  ['janeiro', 1],
  ['jan', 1],
  ['fevereiro', 2],
  ['fev', 2],
  ['marco', 3],
  ['mar', 3],
  ['abril', 4],
  ['abr', 4],
  ['maio', 5],
  ['mai', 5],
  ['junho', 6],
  ['jun', 6],
  ['julho', 7],
  ['jul', 7],
  ['agosto', 8],
  ['ago', 8],
  ['setembro', 9],
  ['set', 9],
  ['outubro', 10],
  ['out', 10],
  ['novembro', 11],
  ['nov', 11],
  ['dezembro', 12],
  ['dez', 12],
]);

const DAY_MONTH_YEAR = /(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?!\d)/g;
const MONTH_NAME_YEAR =
  /\b(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\s*(?:de|\/)\s*(\d{4})\b/g;
const MONTH_YEAR = /(?<![\d./-])(\d{1,2})\/(\d{4})\b/g;
const YEAR = /(?<![\d./-])((?:19|20)\d{2})(?![\d./-])/g;
const STARTING_FROM = /(\d{1,3})\s*anos?\s*,?\s*(?:contados\s*)?a\s*partir/;

function makeDate(year: number, month: number, day: number): DateTime | null {
  const a = year < 100 ? 2000 + year : year;
  if (month < 1 || month > 12 || day < 1 || day > 31 || a < 1900 || a > 2200) {
    return null;
  }
  const d = DateTime.utc(a, month, day);
  // A data normaliza 31/02 para março; data que não existe é recusada.
  return d.month === month ? d : null;
}

function endOfMonth(year: number, month: number): DateTime | null {
  if (month < 1 || month > 12 || year < 1900 || year > 2200) return null;
  return DateTime.utc(year, month + 1, 0);
}

/** Minúsculas, sem acento. O FRE mistura "Março", "MARCO" e "março". */
function normalize(s: string): string {
  const accented = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const plain = 'aaaaaeeeeiiiiooooouuuuc';
  let b = '';
  for (const c of s.toLowerCase()) {
    const i = accented.indexOf(c);
    b += i >= 0 ? plain[i]! : c;
  }
  return b.trim();
}

/** Resumo de [FreConcessionTerm.summarize]. */
export interface ConcessionSummary {
  readonly end: DateTime | null;
  readonly contracts: number;
  readonly readCount: number;
  readonly inForceCount: number;
}

/**
 * Fim de contrato de concessão a partir do texto livre do Formulário de
 * Referência.
 *
 * O quadro de ativos intangíveis do FRE (item 9.1.b) lista cada concessão com
 * uma coluna `Duracao` **em texto livre**: "até julho/2045", "De 11/08/2017 até
 * 11/08/2047", "30 anos, a partir de 03/2019", "2028, prorrogável até 2058",
 * "Prazo indeterminado". Não há campo de data, e não há peso por contrato.
 *
 * **O que o prazo corta.** O terminal neutro que a decisão 50 impõe a toda
 * concessão recusa o valor do capital novo, mas mantém para sempre o excedente
 * do capital existente. O contrato que acaba paga esse excedente só até o fim
 * e devolve o capital — pela amortização, pela indenização do não amortizado
 * ou por renovação ao custo de capital. Onde o capital rende exatamente o
 * custo dele, o prazo não muda nada. Ver `DcfAssumptions.contractYearsAfterHorizon`
 * e a decisão 88.
 */
export const FreConcessionTerm = {
  /**
   * Fim do contrato descrito por [duration], ou `null` quando o texto não dá
   * uma data absoluta.
   *
   * Recusa, e não adivinha: "Prazo indeterminado", "Vide item 9.1", e prazo
   * relativo sem início ("6 anos") devolvem `null`.
   *
   * - "N anos, a partir de <data>" soma N anos ao início.
   * - Com "prorrogável", vale o prazo **antes** da prorrogação: é o que o
   *   contrato garante hoje, e a renovação refaz a tarifa.
   * - Havendo várias datas — "de X a Y" —, vale a última.
   * - Mês sem dia é o último dia do mês; ano sozinho, 31 de dezembro.
   */
  endOf(duration: string | null): DateTime | null {
    if (duration === null) return null;
    let text = normalize(duration);
    if (text.length === 0 || text.includes('indeterminad')) return null;

    // "prorrogável", "prorrogação" e a abreviação "Prorr." do formulário.
    const renewalIndex = text.indexOf('prorr');
    if (renewalIndex >= 0) text = text.substring(0, renewalIndex);

    const dates: { pos: number; date: DateTime }[] = [];
    for (const m of text.matchAll(DAY_MONTH_YEAR)) {
      const d = makeDate(parseInt_(m[3]!), parseInt_(m[2]!), parseInt_(m[1]!));
      if (d !== null) dates.push({ pos: m.index, date: d });
    }
    for (const m of text.matchAll(MONTH_NAME_YEAR)) {
      const d = endOfMonth(parseInt_(m[2]!), MONTHS.get(m[1]!)!);
      if (d !== null) dates.push({ pos: m.index, date: d });
    }
    for (const m of text.matchAll(MONTH_YEAR)) {
      const d = endOfMonth(parseInt_(m[2]!), parseInt_(m[1]!));
      if (d !== null) dates.push({ pos: m.index, date: d });
    }

    const startingFrom = STARTING_FROM.exec(text);
    if (startingFrom !== null) {
      const start = dates.filter((d) => d.pos > startingFrom.index);
      if (start.length === 0) return null;
      const i = start[0]!.date;
      return DateTime.utc(i.year + parseInt_(startingFrom[1]!), i.month, i.day);
    }

    if (dates.length === 0) {
      for (const m of text.matchAll(YEAR)) {
        dates.push({ pos: m.index, date: DateTime.utc(parseInt_(m[1]!), 12, 31) });
      }
    }
    if (dates.length === 0) return null;
    dates.sort((a, b) => compareNum(a.pos, b.pos));
    return dates[dates.length - 1]!.date;
  },

  /**
   * Resumo das concessões de uma companhia num documento.
   *
   * - [durations]: a coluna `Duracao` de cada concessão do documento.
   * - [reference]: data de referência do documento. Contrato que já tinha
   *   acabado nela não conta — o FRE repete contrato vencido e renovado com o
   *   prazo antigo, como a distribuição da Cemig "até fevereiro de 2016" no
   *   formulário de 2019.
   *
   * [end] é a **mediana** dos fins vigentes. Sem peso por contrato no FRE, a
   * mediana é a leitura que um contrato pequeno e extremo não arrasta.
   */
  summarize(durations: Iterable<string | null>, reference: DateTime): ConcessionSummary {
    let contracts = 0;
    let readCount = 0;
    const inForceEnds: DateTime[] = [];
    for (const d of durations) {
      contracts++;
      const end = FreConcessionTerm.endOf(d);
      if (end === null) continue;
      readCount++;
      if (end.isAfter(reference)) inForceEnds.push(end);
    }
    if (inForceEnds.length === 0) {
      return { end: null, contracts, readCount, inForceCount: 0 };
    }
    inForceEnds.sort((a, b) => a.compareTo(b));
    // Mediana baixa com número par: a data tem de ser uma das observadas.
    const median = inForceEnds[intDiv(inForceEnds.length - 1, 2)]!;
    return { end: median, contracts, readCount, inForceCount: inForceEnds.length };
  },
};

/** O prazo lido para um ativo, com o que sustenta a leitura. */
export class ConcessionTerm {
  /** Mediana dos fins das outorgas vigentes. */
  readonly end: DateTime;

  /** Concessões listadas no documento. */
  readonly contracts: number;

  /** Delas, com data de fim legível. */
  readonly parsed: number;

  /** Delas, ainda vigentes na data de referência do documento. */
  readonly active: number;

  /** Data de referência do Formulário de Referência lido. */
  readonly reference: DateTime;

  /** Declara o prazo. */
  constructor(args: { end: DateTime; contracts: number; parsed: number; active: number; reference: DateTime }) {
    this.end = args.end;
    this.contracts = args.contracts;
    this.parsed = args.parsed;
    this.active = args.active;
    this.reference = args.reference;
  }
}

function pad(n: number, width: number): string {
  return String(n).padStart(width, '0');
}

function codecDay(d: DateTime): string {
  return `${pad(d.year, 4)}-${pad(d.month, 2)}-${pad(d.day, 2)}`;
}

function codecDate(v: unknown): DateTime | null {
  if (typeof v !== 'string' || v.length < 10) return null;
  const p = v.substring(0, 10).split('-');
  if (p.length !== 3) return null;
  const a = tryParseInt(p[0]!);
  const m = tryParseInt(p[1]!);
  const d = tryParseInt(p[2]!);
  if (a === null || m === null || d === null) return null;
  return DateTime.utc(a, m, d);
}

/**
 * Formato do pacote de prazos, para empacotar no aplicativo (item A6).
 *
 * Mora no núcleo pela mesma razão do `CvmDocumentCodec`: a ferramenta que
 * grava e o repositório que lê precisam concordar sobre o formato.
 */
export const ConcessionTermsCodec = {
  /** Versão do formato. */
  version: 1,

  /** O pacote inteiro. */
  encode(terms: ReadonlyMap<string, ConcessionTerm>, args: { generatedAt: DateTime }): JsonObject {
    const tickers: JsonObject = {};
    for (const [key, value] of terms) {
      tickers[key] = {
        fim: codecDay(value.end),
        contratos: value.contracts,
        lidos: value.parsed,
        vigentes: value.active,
        referencia: codecDay(value.reference),
      };
    }
    return { versao: ConcessionTermsCodec.version, geradoEm: codecDay(args.generatedAt), tickers };
  },

  /** Lê o pacote. Versão desconhecida devolve mapa vazio. */
  decode(pkg: JsonObject): Map<string, ConcessionTerm> {
    if (pkg['versao'] !== ConcessionTermsCodec.version) return new Map();
    const tickers = pkg['tickers'];
    if (!isJsonObject(tickers)) return new Map();
    const out = new Map<string, ConcessionTerm>();
    for (const [key, v] of Object.entries(tickers)) {
      if (!isJsonObject(v)) continue;
      const end = codecDate(v['fim']);
      const ref = codecDate(v['referencia']);
      if (end === null || ref === null) continue;
      out.set(
        key,
        new ConcessionTerm({
          end,
          contracts: asInt(v['contratos']) ?? 0,
          parsed: asInt(v['lidos']) ?? 0,
          active: asInt(v['vigentes']) ?? 0,
          reference: ref,
        }),
      );
    }
    return out;
  },
};
