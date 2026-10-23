/**
 * Formato compacto dos documentos da CVM, para empacotar no aplicativo.
 *
 * **Por que existe.** A base ingerida tem 43 MB para 1.224 companhias, e o
 * aplicativo precisa só das 375 do universo, só dos campos que o motor lê. O
 * formato usa chaves curtas, omite campo nulo e grava número sem casas quando
 * ele é inteiro — os valores da CVM são inteiros em milhares de reais.
 *
 * **Por que mora no núcleo.** A ferramenta que empacota e o repositório que lê
 * no aplicativo precisam concordar byte a byte sobre o formato. Duas cópias
 * divergiriam na primeira mudança de campo, e a divergência não quebraria
 * nada: o campo sumiria em silêncio.
 */

import { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DateTime } from '../../lang/date-time';
import { asDouble, isJsonObject, type JsonObject } from '../../lang/json';
import { round, roundToDouble, tryParseInt } from '../../lang/num';
import { Ticker } from '../../value-objects/ticker';
import { CvmDocumentKind, CvmPeriodDocument } from './trailing-twelve-months';

/** Chave curta → leitor do campo no snapshot. */
const READERS: ReadonlyArray<readonly [string, (s: FundamentalsSnapshot) => number | null]> = [
  ['rev', (s) => s.totalRevenue],
  ['ebit', (s) => s.ebit],
  ['ebitda', (s) => s.ebitda],
  ['ni', (s) => s.netIncome],
  ['ibt', (s) => s.incomeBeforeTax],
  ['tax', (s) => s.incomeTaxExpense],
  ['ocf', (s) => s.operatingCashFlow],
  ['icf', (s) => s.investmentCashFlow],
  ['cash', (s) => s.cash],
  ['sti', (s) => s.shortTermInvestments],
  ['std', (s) => s.shortTermDebt],
  ['ltd', (s) => s.longTermDebt],
  ['eq', (s) => s.totalStockholderEquity],
  ['ppe', (s) => s.propertyPlantEquipment],
  ['intg', (s) => s.intangibleAssets],
  ['tca', (s) => s.totalCurrentAssets],
  ['cl', (s) => s.currentLiabilities],
  ['mi', (s) => s.minorityInterest],
  ['ta', (s) => s.totalAssets],
  ['tf', (s) => s.treasuryFraction],
];

function pad(n: number, width: number): string {
  return String(n).padStart(width, '0');
}

function day(d: DateTime): string {
  return `${pad(d.year, 4)}-${pad(d.month, 2)}-${pad(d.day, 2)}`;
}

function date(v: unknown): DateTime | null {
  if (typeof v !== 'string' || v.length < 10) return null;
  const p = v.substring(0, 10).split('-');
  if (p.length !== 3) return null;
  const y = tryParseInt(p[0]!);
  const m = tryParseInt(p[1]!);
  const d = tryParseInt(p[2]!);
  if (y === null || m === null || d === null) return null;
  return DateTime.utc(y, m, d);
}

/** Número compacto: inteiro quando é inteiro, e com casas só quando precisa. */
function compactNumber(v: number): number {
  return Math.abs(v) < 9e15 && Math.abs(v - roundToDouble(v)) < CvmDocumentCodec.integerTolerance ? round(v) : v;
}

function fields(s: FundamentalsSnapshot): JsonObject {
  const out: JsonObject = {};
  for (const [key, read] of READERS) {
    const v = read(s);
    if (v !== null && Number.isFinite(v)) out[key] = compactNumber(v);
  }
  return out;
}

function snapshot(t: Ticker, end: DateTime, c: JsonObject, received: DateTime | null = null): FundamentalsSnapshot {
  const n = (k: string): number | null => asDouble(c[k]);
  return new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: end,
    receiptDate: received,
    totalRevenue: n('rev'),
    ebit: n('ebit'),
    ebitda: n('ebitda'),
    netIncome: n('ni'),
    incomeBeforeTax: n('ibt'),
    incomeTaxExpense: n('tax'),
    operatingCashFlow: n('ocf'),
    investmentCashFlow: n('icf'),
    cash: n('cash'),
    shortTermInvestments: n('sti'),
    shortTermDebt: n('std'),
    longTermDebt: n('ltd'),
    totalStockholderEquity: n('eq'),
    propertyPlantEquipment: n('ppe'),
    intangibleAssets: n('intg'),
    totalCurrentAssets: n('tca'),
    currentLiabilities: n('cl'),
    minorityInterest: n('mi'),
    totalAssets: n('ta'),
    treasuryFraction: n('tf'),
  });
}

/** Leitura e escrita do formato compacto. */
export const CvmDocumentCodec = {
  /** Versão do formato. Muda quando uma chave muda de significado. */
  version: 1,

  /**
   * Tolerância para gravar um valor como inteiro.
   *
   * Os valores da CVM são reais inteiros por origem — o arquivo publica em
   * milhares, e a ingestão multiplica. Um bilionésimo de real fica ordens de
   * grandeza abaixo do centavo, e absorve o resíduo de ponto flutuante da
   * multiplicação sem comparar ponto flutuante por igualdade.
   */
  integerTolerance: 1e-9,

  /** Um documento no formato compacto. */
  encode(d: CvmPeriodDocument): JsonObject {
    const out: JsonObject = {
      k: d.kind === CvmDocumentKind.dfp ? 'D' : 'I',
      s: day(d.periodStart),
      e: day(d.periodEnd),
    };
    if (d.current.receiptDate !== null) out['r'] = day(d.current.receiptDate);
    out['c'] = fields(d.current);
    if (d.prior !== null) out['p'] = fields(d.prior);
    if (d.priorStart !== null) out['ps'] = day(d.priorStart);
    return out;
  },

  /** Lê um documento, ou `null` quando ele não tem o mínimo para existir. */
  decode(t: Ticker, m: JsonObject): CvmPeriodDocument | null {
    const ini = date(m['s']);
    const end = date(m['e']);
    const c = m['c'];
    if (ini === null || end === null || !isJsonObject(c)) return null;
    const kind = m['k'] === 'D' ? CvmDocumentKind.dfp : m['k'] === 'I' ? CvmDocumentKind.itr : null;
    if (kind === null) return null;
    const p = m['p'];
    return new CvmPeriodDocument({
      kind,
      periodStart: ini,
      periodEnd: end,
      current: snapshot(t, end, c, date(m['r'])),
      prior: isJsonObject(p) ? snapshot(t, DateTime.utc(end.year - 1, end.month, end.day), p) : null,
      priorStart: date(m['ps']),
    });
  },

  /** O pacote inteiro: versão, data de geração e documentos por ticker. */
  encodePackage(byTicker: ReadonlyMap<string, readonly CvmPeriodDocument[]>, args: { generatedAt: DateTime }): JsonObject {
    const tickers: JsonObject = {};
    for (const [key, value] of byTicker) tickers[key] = value.map((d) => CvmDocumentCodec.encode(d));
    return {
      versao: CvmDocumentCodec.version,
      geradoEm: day(args.generatedAt),
      tickers,
    };
  },

  /**
   * Lê o pacote. Devolve mapa vazio para versão desconhecida — um formato que
   * o leitor não entende não é lido pela metade.
   */
  decodePackage(pkg: JsonObject): Map<string, CvmPeriodDocument[]> {
    if (pkg['versao'] !== CvmDocumentCodec.version) return new Map();
    const tickers = pkg['tickers'];
    if (!isJsonObject(tickers)) return new Map();
    const out = new Map<string, CvmPeriodDocument[]>();
    for (const [key, docs] of Object.entries(tickers)) {
      const t = Ticker.tryParse(key);
      if (t === null || !Array.isArray(docs)) continue;
      const list: CvmPeriodDocument[] = [];
      for (const d of docs) {
        if (!isJsonObject(d)) continue;
        const doc = CvmDocumentCodec.decode(t, d);
        if (doc !== null) list.push(doc);
      }
      out.set(key, list);
    }
    return out;
  },
};
