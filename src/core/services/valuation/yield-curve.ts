/**
 * Curva de juros prefixada do Tesouro, montada das LTN e NTN-F do dia.
 *
 * Interpolação **linear no log do fator de desconto** — a forma que mantém
 * os forwards constantes por trecho e nunca os faz negativos entre dois
 * vértices positivos.
 */

import { isJsonObject, type JsonObject } from '../../lang/json';
import type { DateTime as DateTimeType } from '../../lang/date-time';
import { DateTime } from '../../lang/date-time';
import { compareNum, round, tryParseDouble, tryParseInt } from '../../lang/num';
import { BrazilianCalendar } from '../../time/brazilian-calendar';

/** Vértice da curva: prazo em anos de 252 dias úteis e taxa anual composta. */
export class CurveVertex {
  readonly years: number;
  readonly rate: number;

  constructor(years: number, rate: number) {
    this.years = years;
    this.rate = rate;
  }
}

/** Curva à vista com os forwards que ela implica. */
export class YieldCurve {
  /** Data-base das cotações que formaram a curva. */
  readonly referenceDate: DateTimeType;

  /** Vértices em ordem crescente de prazo. **Imutável.** */
  readonly vertices: readonly CurveVertex[];

  private constructor(referenceDate: DateTimeType, vertices: readonly CurveVertex[]) {
    this.referenceDate = referenceDate;
    this.vertices = vertices;
  }

  /** Menos que três vértices não descrevem curva — descrevem um ponto. */
  static readonly minVertices = 3;

  /**
   * Curva dos [vertices] válidos, ou `null` com menos de [minVertices].
   *
   * Descarta prazo não positivo e taxa fora de `(−50%, 100%)`. Em prazo
   * repetido fica o primeiro vértice informado.
   */
  static of(referenceDate: DateTimeType, vertices: Iterable<CurveVertex>): YieldCurve | null {
    // Chave inteira, em dias úteis: dois títulos de mesmo vencimento caem no
    // mesmo dia, e `double` não serve de chave de mapa.
    const byMaturity = new Map<number, CurveVertex>();
    for (const v of vertices) {
      if (!Number.isFinite(v.years) || v.years <= 0) continue;
      if (!Number.isFinite(v.rate) || v.rate <= -0.5 || v.rate >= 1.0) continue;
      const key = round(v.years * 252);
      if (!byMaturity.has(key)) byMaturity.set(key, v);
    }
    if (byMaturity.size < YieldCurve.minVertices) return null;
    const sortedRows = [...byMaturity.values()].sort((a, b) => compareNum(a.years, b.years));
    return new YieldCurve(referenceDate, Object.freeze(sortedRows));
  }

  private lnDiscount(t: number): number {
    if (t <= 0) return 0;
    const v = this.vertices;
    const head = v[0]!;
    // Antes do primeiro vértice: taxa à vista plana.
    if (t <= head.years) return -t * Math.log(1 + head.rate);
    for (let i = 1; i < v.length; i++) {
      const cur = v[i]!;
      if (t <= cur.years) {
        const prev = v[i - 1]!;
        const l0 = -prev.years * Math.log(1 + prev.rate);
        const l1 = -cur.years * Math.log(1 + cur.rate);
        const w = (t - prev.years) / (cur.years - prev.years);
        return l0 + (l1 - l0) * w;
      }
    }
    // Além do último vértice: segue o forward do último segmento.
    const a = v[v.length - 2]!;
    const b = v[v.length - 1]!;
    const la = -a.years * Math.log(1 + a.rate);
    const lb = -b.years * Math.log(1 + b.rate);
    const slope = (lb - la) / (b.years - a.years);
    return lb + slope * (t - b.years);
  }

  /** Taxa à vista anual composta para o prazo [t], em anos. */
  spotRate(t: number): number {
    if (t <= 0) return this.vertices[0]!.rate;
    return Math.exp(-this.lnDiscount(t) / t) - 1;
  }

  /** Forward anual composto entre [t0] e [t1]. Com `t1 ≤ t0`, a taxa à vista de [t0]. */
  forwardRate(t0: number, t1: number): number {
    if (t1 <= t0) return this.spotRate(t0);
    return Math.exp((this.lnDiscount(t0) - this.lnDiscount(t1)) / (t1 - t0)) - 1;
  }

  /** Forwards de um ano para os anos `1..n`. */
  annualForwards(n: number): number[] {
    const out: number[] = [];
    for (let t = 1; t <= n; t++) out.push(this.forwardRate(t - 1.0, t));
    return out;
  }

  /** Forward do ano seguinte ao horizonte explícito: o da perpetuidade. */
  terminalRate(n: number): number {
    return this.forwardRate(n, n + 1.0);
  }
}

/** Cotação de um título prefixado num dia. */
export class TreasuryQuote {
  /** Nome do título como o Tesouro o publica. */
  readonly type: string;
  readonly maturity: DateTimeType;
  readonly baseDate: DateTimeType;

  /** Taxa de compra anual, em fração. */
  readonly rate: number;

  constructor(args: { type: string; maturity: DateTimeType; baseDate: DateTimeType; rate: number }) {
    this.type = args.type;
    this.maturity = args.maturity;
    this.baseDate = args.baseDate;
    this.rate = args.rate;
  }
}

/** Monta a curva do dia a partir das cotações publicadas. */
export const TreasuryCurve = {
  ltn: 'Tesouro Prefixado',
  ntnF: 'Tesouro Prefixado com Juros Semestrais',

  /** Quantos dias corridos a última data-base ainda vale sem cotação nova. */
  fallbackDays: 7,

  /**
   * Curva da data-base mais recente até [asOf], dentro de [fallbackDays], ou
   * `null`. Nunca usa cotação posterior a [asOf].
   */
  at(quotes: Iterable<TreasuryQuote>, asOf: DateTimeType): YieldCurve | null {
    const list = [...quotes];
    const day = DateTime.utc(asOf.year, asOf.month, asOf.day);
    let base: DateTimeType | null = null;
    for (const q of list) {
      const b = DateTime.utc(q.baseDate.year, q.baseDate.month, q.baseDate.day);
      if (b.isAfter(day)) continue;
      if (day.difference(b).inDays > TreasuryCurve.fallbackDays) continue;
      if (base === null || b.isAfter(base)) base = b;
    }
    if (base === null) return null;
    const baseDay = base;
    const sameDay = list.filter(
      (q) => q.baseDate.year === baseDay.year && q.baseDate.month === baseDay.month && q.baseDate.day === baseDay.day,
    );
    // Da liquidação ao vencimento, em dias úteis do calendário que se
    // conhecia na data-base — é a conta do PU do próprio Tesouro.
    const settlement = BrazilianCalendar.treasurySettlement(baseDay);
    const years = (q: TreasuryQuote): number =>
      BrazilianCalendar.businessDaysBetween(settlement, q.maturity, { knownAt: baseDay }) / 252;
    const vertices: CurveVertex[] = [];
    // LTN primeiro: em prazo repetido, fica o cupom zero.
    for (const q of sameDay) if (q.type === TreasuryCurve.ltn) vertices.push(new CurveVertex(years(q), q.rate));
    for (const q of sameDay) if (q.type === TreasuryCurve.ntnF) vertices.push(new CurveVertex(years(q), q.rate));
    return YieldCurve.of(baseDay, vertices);
  },
};

/** Leitura do CSV público do Tesouro Direto (`PrecoTaxaTesouroDireto.csv`). */
export const TreasuryCsv = {
  date(s: string): DateTimeType | null {
    const p = s.trim().split('/');
    if (p.length !== 3) return null;
    const d = tryParseInt(p[0]!);
    const m = tryParseInt(p[1]!);
    const a = tryParseInt(p[2]!);
    if (d === null || m === null || a === null) return null;
    return DateTime.utc(a, m, d);
  },

  /** Cotação de uma linha `tipo;vencimento;dataBase;taxa;…`, ou `null`. */
  parseLine(row: string): TreasuryQuote | null {
    const c = row.split(';');
    if (c.length < 4) return null;
    const kind = c[0]!.trim();
    if (kind !== TreasuryCurve.ltn && kind !== TreasuryCurve.ntnF) return null;
    const maturity = TreasuryCsv.date(c[1]!);
    const base = TreasuryCsv.date(c[2]!);
    const rate = tryParseDouble(c[3]!.trim().replaceAll(',', '.'));
    if (maturity === null || base === null || rate === null || rate <= 0) return null;
    return new TreasuryQuote({ type: kind, maturity, baseDate: base, rate: rate / 100 });
  },

  /** Cotações válidas das [rows], na ordem do arquivo. */
  parse(rows: Iterable<string>): TreasuryQuote[] {
    const out: TreasuryQuote[] = [];
    for (const l of rows) {
      const q = TreasuryCsv.parseLine(l);
      if (q !== null) out.push(q);
    }
    return out;
  },

  /** Data-base de uma linha, sem validar o resto dela. */
  baseDateOf(row: string): DateTimeType | null {
    const c = row.split(';');
    return c.length < 3 ? null : TreasuryCsv.date(c[2]!);
  },
};

function isoDay(d: DateTimeType): string {
  return (
    `${String(d.year).padStart(4, '0')}-` +
    `${String(d.month).padStart(2, '0')}-` +
    `${String(d.day).padStart(2, '0')}`
  );
}

/** Pacote empacotado das cotações (`assets/tesouro/prefixados.json`). */
export const TreasuryQuotesCodec = {
  version: 1,

  encode(quotes: Iterable<TreasuryQuote>, args: { generatedAt: DateTimeType }): JsonObject {
    const cotacoes: JsonObject[] = [];
    for (const q of quotes) {
      cotacoes.push({ tipo: q.type, vencimento: isoDay(q.maturity), dataBase: isoDay(q.baseDate), taxa: q.rate });
    }
    return { versao: TreasuryQuotesCodec.version, geradoEm: isoDay(args.generatedAt), cotacoes };
  },

  decode(json: JsonObject): TreasuryQuote[] {
    if (json['versao'] !== TreasuryQuotesCodec.version) return [];
    const rawQuotes = json['cotacoes'];
    if (!Array.isArray(rawQuotes)) return [];
    const date = (v: unknown): DateTimeType | null => {
      if (typeof v !== 'string' || v.length < 10) return null;
      return DateTime.tryParse(`${v.substring(0, 10)}T00:00:00Z`);
    };
    const out: TreasuryQuote[] = [];
    for (const b of rawQuotes) {
      if (!isJsonObject(b)) continue;
      const kind = b['tipo'];
      const maturity = date(b['vencimento']);
      const base = date(b['dataBase']);
      const rate = b['taxa'];
      if (typeof kind !== 'string' || maturity === null || base === null || typeof rate !== 'number') {
        continue;
      }
      if (!Number.isFinite(rate) || rate <= -0.5 || rate >= 1) continue;
      out.push(new TreasuryQuote({ type: kind, maturity, baseDate: base, rate }));
    }
    return out;
  },
};
