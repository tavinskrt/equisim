/**
 * Registro de empresas listadas da B3: contagem oficial de ações e eventos.
 *
 * **De onde vem.** A página de empresas listadas da B3 é servida por um
 * endpoint que devolve, por emissor, a quantidade de ações por classe e os
 * eventos societários com fator e data-com. É o **registro declarado** que o
 * item A3.1 pedia: o fator do evento vem escrito, e não inferido do preço como
 * em `CorporateEvents` (decisão 75).
 *
 * **Duas convenções de fator, conferidas contra o preço.** Sobre os eventos de
 * 2010 em diante dos 297 emissores do universo, confrontados com a razão de
 * fechamento do COTAHIST na data ex (14/09/2026):
 *
 * | rótulo | o fator é | exemplo |
 * |---|---|---|
 * | `DESDOBRAMENTO` | **acréscimo percentual** | `900` = 1 para 10 |
 * | `BONIFICACAO` | **acréscimo percentual** | `25` = +25% |
 * | `GRUPAMENTO` | **multiplicador** | `0,05` = 20 para 1 |
 *
 * **E os eventos da mesma data se compõem.** A B3 escreve um desdobramento de
 * 1 para 2 como grupamento de 10 para 1 **e** desdobramento de 1 para 20, no
 * mesmo dia — CPFE3 em 2011, VIVT3 e TIMS3 em 2025. Lido evento a evento, o
 * fator erra por 10x ou 100x; composto, bate com o preço em **93,4% de 243
 * eventos a 15%**, e o que sobra é o mercado andando no dia do grupamento de
 * papel em crise, e par incompleto no próprio registro.
 *
 * **O que o registro não diz.** Só emissor listado hoje: companhia deslistada
 * não está lá, e para ela a inferência pelo preço continua sendo a fonte.
 * Cisão, incorporação e resgate trazem fator em outra convenção e não mudam a
 * contagem do mesmo papel de forma multiplicativa — ficam de fora.
 */

import { DateTime } from '../../lang/date-time';
import { asDouble, interpolateJson, isJsonObject, type JsonObject } from '../../lang/json';
import { isInt, tryParseDouble, tryParseInt } from '../../lang/num';
import { BrazilianCalendar } from '../../time/brazilian-calendar';

/** Um evento de ações declarado pela B3, já composto por data e ISIN. */
export class OfficialShareEvent {
  /** ISIN do papel afetado. */
  readonly isin: string;

  /** Último dia com direito — a data-com. */
  readonly lastDateWithRights: DateTime;

  /** Primeiro pregão depois da data-com: a data ex. */
  readonly exDate: DateTime;

  /** Ações depois ÷ ações antes, composto sobre os eventos do mesmo dia. */
  readonly factor: number;

  /** Rótulos que compuseram o fator, na ordem do registro. */
  readonly labels: readonly string[];

  /** Declara o evento. */
  constructor(args: {
    isin: string;
    lastDateWithRights: DateTime;
    exDate: DateTime;
    factor: number;
    labels: readonly string[];
  }) {
    this.isin = args.isin;
    this.lastDateWithRights = args.lastDateWithRights;
    this.exDate = args.exDate;
    this.factor = args.factor;
    this.labels = args.labels;
  }
}

/**
 * Classificação setorial oficial da B3: setor econômico, subsetor e segmento
 * (item A5).
 *
 * **Por emissor, e não por papel.** A fonte de preços classifica papel a
 * papel e deixa buracos — SANB11 vinha classificada e SANB4 não, e BRSR6 e
 * PINE4 chegavam sem setor e escapavam da Porta 1 (limitações §2.14). A B3
 * classifica a companhia, e todas as classes herdam.
 *
 * Vem do `GetDetail` do portal de empresas listadas, como texto
 * `Setor / Subsetor / Segmento` — com a pontuação da B3, que escreve
 * "Petróleo. Gás e Biocombustíveis" com ponto onde caberia vírgula.
 */
export class B3Classification {
  /** Setor econômico — "Financeiro", "Utilidade Pública". */
  readonly sector: string;

  /** Subsetor — "Intermediários Financeiros", "Energia Elétrica". */
  readonly subsector: string | null;

  /** Segmento — "Bancos", "Energia Elétrica". */
  readonly segment: string | null;

  /** Declara a classificação. */
  constructor(args: { sector: string; subsector?: string | null; segment?: string | null }) {
    this.sector = args.sector;
    this.subsector = args.subsector ?? null;
    this.segment = args.segment ?? null;
  }

  /** Lê o texto `Setor / Subsetor / Segmento`, ou `null` sem setor. */
  static parse(raw: unknown): B3Classification | null {
    if (typeof raw !== 'string') return null;
    const parts = raw
      .split('/')
      .filter((p) => p.trim().length > 0)
      .map((p) => p.trim());
    if (parts.length === 0) return null;
    return new B3Classification({
      sector: parts[0]!,
      subsector: parts.length > 1 ? parts[1]! : null,
      segment: parts.length > 2 ? parts.slice(2).join(' / ') : null,
    });
  }

  /**
   * Chave do setor, no formato das chaves que o motor compara: minúsculas,
   * sem acento, palavras unidas por hífen — "Materiais Básicos" vira
   * `materiais-basicos`, "Consumo não Cíclico" vira `consumo-nao-ciclico`.
   */
  get sectorKey(): string {
    return B3Classification.slug(this.sector);
  }

  /**
   * Subsetor e segmento, como a B3 escreve: "Intermediários Financeiros /
   * Bancos". É o que o motor lê como subsetor.
   */
  get industry(): string {
    return [this.subsector, this.segment].filter((x): x is string => x !== null).join(' / ');
  }

  /** O texto inteiro, na ordem da B3. */
  get label(): string {
    return [this.sector, this.subsector, this.segment].filter((x): x is string => x !== null).join(' / ');
  }

  /** Minúsculas, sem acento, com hífen no lugar de tudo que não é letra ou dígito. */
  static slug(s: string): string {
    const accented = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const plain = 'aaaaaeeeeiiiiooooouuuuc';
    let b = '';
    let hyphen = false;
    for (let c of s.toLowerCase()) {
      const i = accented.indexOf(c);
      if (i >= 0) c = plain[i]!;
      const u = c.charCodeAt(0);
      const alphanumeric = (u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39);
      if (alphanumeric) {
        if (hyphen && b.length > 0) b += '-';
        b += c;
        hyphen = false;
      } else {
        hyphen = true;
      }
    }
    return b;
  }
}

/** Um emissor no registro. */
export class B3Issuer {
  /** Código de quatro letras — `PETR` para PETR3 e PETR4. */
  readonly code: string;

  /**
   * Quantidade total de ações emitidas, **com as em tesouraria**.
   *
   * Conferido em 14/09/2026 contra o capital integralizado declarado à CVM:
   * bate com o total em 260 de 293 emissores, e com o total líquido de
   * tesouraria em 3.
   */
  readonly totalShares: number | null;

  /** Ações ordinárias. */
  readonly commonShares: number | null;

  /** Ações preferenciais. */
  readonly preferredShares: number | null;

  /** Dia em que o registro foi consultado. A contagem é a desse dia. */
  readonly consultedOn: DateTime;

  /** Eventos de ações, em ordem de data ex. */
  readonly events: readonly OfficialShareEvent[];

  /**
   * Classificação setorial oficial, ou `null` quando o detalhe do emissor não
   * foi consultado.
   */
  readonly classification: B3Classification | null;

  /** Declara o emissor. */
  constructor(args: {
    code: string;
    totalShares: number | null;
    commonShares: number | null;
    preferredShares: number | null;
    consultedOn: DateTime;
    events: readonly OfficialShareEvent[];
    classification?: B3Classification | null;
  }) {
    this.code = args.code;
    this.totalShares = args.totalShares;
    this.commonShares = args.commonShares;
    this.preferredShares = args.preferredShares;
    this.consultedOn = args.consultedOn;
    this.events = args.events;
    this.classification = args.classification ?? null;
  }
}

function positive(v: number | null): number | null {
  return v !== null && v > 0 ? v : null;
}

/** Leitura do registro. */
export const B3Registry = {
  /**
   * Número no formato da B3: ponto de milhar e vírgula decimal —
   * `5.730.834.040`, `0,05000000000`.
   */
  parseNumber(v: unknown): number | null {
    if (typeof v === 'number') return v;
    if (typeof v !== 'string') return null;
    const s = v.trim();
    if (s.length === 0) return null;
    return tryParseDouble(s.replaceAll('.', '').replaceAll(',', '.'));
  },

  /** Data no formato `dd/mm/aaaa`. */
  parseDate(v: unknown): DateTime | null {
    if (typeof v !== 'string') return null;
    const p = v.trim().split('/');
    if (p.length !== 3) return null;
    const d = tryParseInt(p[0]!);
    const m = tryParseInt(p[1]!);
    const a = tryParseInt(p[2]!);
    if (d === null || m === null || a === null) return null;
    return DateTime.utc(a, m, d);
  },

  /**
   * Ações depois ÷ ações antes para um evento, ou `null` quando o rótulo não
   * muda a contagem de forma multiplicativa.
   */
  multiplier(label: string, factor: number): number | null {
    if (!Number.isFinite(factor) || factor <= 0) return null;
    switch (label) {
      case 'DESDOBRAMENTO':
      case 'BONIFICACAO':
        return 1 + factor / 100;
      case 'GRUPAMENTO':
        return factor;
      default:
        return null;
    }
  },

  /**
   * Eventos de ações de uma lista `stockDividends`, compostos por ISIN e
   * data-com.
   *
   * O registro repete o mesmo evento uma vez por papel emitido (`assetIssued`)
   * — um grupamento de ON aparece para cada recibo e direito ligado a ela.
   * Entradas idênticas em ISIN, data, rótulo e fator contam uma vez.
   */
  events(stockDividends: readonly unknown[]): readonly OfficialShareEvent[] {
    const seen = new Set<string>();
    const byKey = new Map<string, { isin: string; recordDate: DateTime; labels: string[]; factor: number }>();
    for (const raw of stockDividends) {
      if (!isJsonObject(raw)) continue;
      const label = raw['label'];
      const isin = raw['isinCode'];
      const recordDate = B3Registry.parseDate(raw['lastDatePrior']);
      const rawFactor = B3Registry.parseNumber(raw['factor']);
      if (typeof label !== 'string' || typeof isin !== 'string' || isin.length === 0) continue;
      if (recordDate === null || rawFactor === null) continue;
      const m = B3Registry.multiplier(label, rawFactor);
      if (m === null) continue;
      const seenKey = `${isin}|${recordDate.toIso8601String()}|${label}|${interpolateJson(raw['factor'])}`;
      if (seen.has(seenKey)) continue;
      seen.add(seenKey);
      const key = `${isin}|${recordDate.toIso8601String()}`;
      const before = byKey.get(key);
      byKey.set(
        key,
        before === undefined
          ? { isin, recordDate, labels: [label], factor: m }
          : { isin, recordDate, labels: [...before.labels, label], factor: before.factor * m },
      );
    }
    const out = [...byKey.values()]
      .map(
        (e) =>
          new OfficialShareEvent({
            isin: e.isin,
            lastDateWithRights: e.recordDate,
            exDate: BrazilianCalendar.nextTradingSession(e.recordDate),
            factor: e.factor,
            labels: Object.freeze([...e.labels]),
          }),
      )
      .sort((a, b) => a.exDate.compareTo(b.exDate));
    return Object.freeze(out);
  },

  /**
   * Um emissor a partir da resposta do endpoint, ou `null` sem código.
   *
   * [detail] é a resposta do `GetDetail` do mesmo emissor, de onde sai a
   * classificação setorial.
   */
  issuer(json: JsonObject, args: { consultedOn: DateTime; detail?: JsonObject | null }): B3Issuer | null {
    const code = json['code'];
    if (typeof code !== 'string' || code.trim().length === 0) return null;
    const rawEvents = json['stockDividends'];
    const { consultedOn } = args;
    return new B3Issuer({
      code: code.trim(),
      totalShares: positive(B3Registry.parseNumber(json['totalNumberShares'])),
      commonShares: B3Registry.parseNumber(json['numberCommonShares']),
      preferredShares: B3Registry.parseNumber(json['numberPreferredShares']),
      consultedOn: DateTime.utc(consultedOn.year, consultedOn.month, consultedOn.day),
      events: Array.isArray(rawEvents) ? B3Registry.events(rawEvents) : [],
      classification: B3Classification.parse(args.detail?.['industryClassification']),
    });
  },
};

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
 * Formato de pacote do registro, para empacotar no aplicativo.
 *
 * Mora no núcleo pela mesma razão do `CvmDocumentCodec`: a ferramenta que
 * grava e o repositório que lê precisam concordar sobre o formato, e duas
 * cópias divergiriam em silêncio.
 */
export const B3RegistryCodec = {
  /**
   * Versão do formato. Muda quando uma chave muda de significado.
   *
   * A 2 acrescenta `classificacao`. A 1 continua legível — sem a chave, o
   * emissor fica sem classificação, que é o que ela era.
   */
  version: 2,

  /** O pacote inteiro. */
  encodePackage(issuers: Iterable<B3Issuer>, args: { generatedAt: DateTime }): JsonObject {
    const out: JsonObject = {};
    for (const e of issuers) {
      const entry: JsonObject = { consultadoEm: codecDay(e.consultedOn) };
      if (e.classification !== null) entry['classificacao'] = e.classification.label;
      if (e.totalShares !== null) entry['total'] = e.totalShares;
      if (e.commonShares !== null) entry['on'] = e.commonShares;
      if (e.preferredShares !== null) entry['pn'] = e.preferredShares;
      entry['eventos'] = e.events.map((x) => ({
        isin: x.isin,
        dataCom: codecDay(x.lastDateWithRights),
        dataEx: codecDay(x.exDate),
        fator: x.factor,
        rotulos: x.labels,
      }));
      out[e.code] = entry;
    }
    return { versao: B3RegistryCodec.version, geradoEm: codecDay(args.generatedAt), emissores: out };
  },

  /**
   * Lê o pacote. Versão desconhecida devolve mapa vazio: formato que o leitor
   * não entende não é lido pela metade.
   */
  decodePackage(pkg: JsonObject): Map<string, B3Issuer> {
    const version = pkg['versao'];
    if (!isInt(version) || version < 1 || version > B3RegistryCodec.version) return new Map();
    const issuers = pkg['emissores'];
    if (!isJsonObject(issuers)) return new Map();
    const out = new Map<string, B3Issuer>();
    for (const [key, v] of Object.entries(issuers)) {
      if (!isJsonObject(v)) continue;
      const consultedAt = codecDate(v['consultadoEm']);
      if (consultedAt === null) continue;
      const events: OfficialShareEvent[] = [];
      const rawSessions = v['eventos'];
      if (Array.isArray(rawSessions)) {
        for (const x of rawSessions) {
          if (!isJsonObject(x)) continue;
          const isin = x['isin'];
          const withInput = codecDate(x['dataCom']);
          const ex = codecDate(x['dataEx']);
          const factor = asDouble(x['fator']);
          const labels = x['rotulos'];
          if (typeof isin !== 'string' || withInput === null || ex === null) continue;
          if (factor === null || !Number.isFinite(factor) || factor <= 0) continue;
          events.push(
            new OfficialShareEvent({
              isin,
              lastDateWithRights: withInput,
              exDate: ex,
              factor,
              labels: Array.isArray(labels)
                ? Object.freeze(labels.filter((l): l is string => typeof l === 'string'))
                : [],
            }),
          );
        }
      }
      out.set(
        key,
        new B3Issuer({
          code: key,
          totalShares: asDouble(v['total']),
          commonShares: asDouble(v['on']),
          preferredShares: asDouble(v['pn']),
          consultedOn: consultedAt,
          events: Object.freeze(events.sort((a, b) => a.exDate.compareTo(b.exDate))),
          classification: B3Classification.parse(v['classificacao']),
        }),
      );
    }
    return out;
  },
};
