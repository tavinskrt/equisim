/**
 * Proventos em dinheiro declarados pela B3, e o retorno total que eles formam
 * (item A4, decisão 89).
 *
 * **De onde vem.** O `GetListedCashDividends` do portal de empresas listadas
 * devolve, por emissor, o histórico inteiro de proventos em dinheiro — desde
 * 1995 nos 297 emissores do universo, 18.651 eventos em 14/09/2026 —, com a
 * classe da ação, a data-com, o valor, o rótulo e o fechamento anterior à data
 * ex. O registro do `GetListedSupplementCompany`, que o item A3.1 usa, só traz
 * os últimos doze meses.
 *
 * **A unidade.** `valueCash` e `closingPricePriorExDate` vêm na unidade de
 * cotação da época — por ação, ou por lote de mil nos anos em que a B3 cotava
 * assim (`quotedPerShares = 1000`, 2.744 eventos). Os dois são divididos por
 * ela: o provento sai por ação.
 */

import { DartEnum, type WireKeyed } from '../../lang/dart-enum';
import { DateTime } from '../../lang/date-time';
import { asDouble, asString, isJsonObject, type JsonObject } from '../../lang/json';
import { ArgumentError, tryParseInt } from '../../lang/num';
import { BrazilianCalendar } from '../../time/brazilian-calendar';
import { B3Registry } from './b3-registry';

/** Natureza do provento, pelo rótulo da B3. */
export class CashDividendKind extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** `DIVIDENDO` — isento para a pessoa física. */
  static readonly dividend = new CashDividendKind('dividend', 0, 'dividendo');

  /** `JRS CAP PROPRIO` — juros sobre capital próprio, com 15% retidos na fonte. */
  static readonly interestOnEquity = new CashDividendKind('interestOnEquity', 1, 'jurosSobreCapital');

  /** `RENDIMENTO` — isento, como o dividendo. */
  static readonly income = new CashDividendKind('income', 2, 'rendimento');

  /** `REST CAP DIN` — restituição de capital em dinheiro. */
  static readonly capitalRefund = new CashDividendKind('capitalRefund', 3, 'restituicaoDeCapital');

  static readonly values: readonly CashDividendKind[] = [
    CashDividendKind.dividend,
    CashDividendKind.interestOnEquity,
    CashDividendKind.income,
    CashDividendKind.capitalRefund,
  ];

  /**
   * Chave gravada nas saídas — pacote de dados, rastro de auditoria,
   * relatório. É dado, e não nome de código: renomear o valor não a muda.
   */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'CashDividendKind';
  }

  /**
   * O valor cuja [key] é [key] — o que `values.byName` fazia com o nome.
   *
   * Lança [ArgumentError], como `byName`, quando nenhum valor tem a chave.
   */
  static fromKey(key: string): CashDividendKind {
    for (const k of CashDividendKind.values) {
      if (k.key === key) return k;
    }
    throw new ArgumentError(`Invalid argument (name): Nenhum valor do enum com essa chave: "${key}"`);
  }
}

/** Um provento em dinheiro, por ação. */
export class CashDividend {
  /** Classe da ação na convenção da B3: `ON`, `PN`, `PNA`, `PNB`, `UNT`. */
  readonly shareClass: string;

  /** Natureza, pelo rótulo. */
  readonly kind: CashDividendKind;

  /** Último dia com direito — a data-com. */
  readonly lastDateWithRights: DateTime;

  /** Primeiro pregão depois da data-com: a data ex. */
  readonly exDate: DateTime;

  /** Valor bruto por ação, em reais. */
  readonly amount: number;

  /** Fechamento por ação no último dia com direito, quando a B3 o informa. */
  readonly closeWithRights: number | null;

  /** Declara o provento. */
  constructor(args: {
    shareClass: string;
    kind: CashDividendKind;
    lastDateWithRights: DateTime;
    exDate: DateTime;
    amount: number;
    closeWithRights?: number | null;
  }) {
    this.shareClass = args.shareClass;
    this.kind = args.kind;
    this.lastDateWithRights = args.lastDateWithRights;
    this.exDate = args.exDate;
    this.amount = args.amount;
    this.closeWithRights = args.closeWithRights ?? null;
  }

  /**
   * Valor que chega ao acionista pessoa física: o juro sobre capital próprio
   * perde os 15% retidos, e o resto é isento.
   */
  get netAmount(): number {
    return this.kind === CashDividendKind.interestOnEquity
      ? this.amount * (1 - B3CashDividends.jcpWithholding)
      : this.amount;
  }
}

const LABELS: ReadonlyMap<string, CashDividendKind> = new Map([
  ['DIVIDENDO', CashDividendKind.dividend],
  ['JRS CAP PROPRIO', CashDividendKind.interestOnEquity],
  ['RENDIMENTO', CashDividendKind.income],
  ['REST CAP DIN', CashDividendKind.capitalRefund],
]);

/** Leitura dos proventos da B3. */
export const B3CashDividends = {
  /** Imposto retido na fonte sobre juros sobre capital próprio. */
  jcpWithholding: 0.15,

  /**
   * Lê a lista `results` do `GetListedCashDividends`.
   *
   * Linha sem classe, sem data-com legível, sem valor positivo ou com rótulo
   * desconhecido fica de fora: provento inventado entraria no retorno.
   */
  parse(results: Iterable<unknown>): CashDividend[] {
    const out: CashDividend[] = [];
    for (const r of results) {
      if (!isJsonObject(r)) continue;
      const shareClass = asString(r['typeStock'])?.trim() ?? null;
      const label = asString(r['corporateAction'])?.trim();
      const kind = label === undefined ? undefined : LABELS.get(label);
      const withInput = B3Registry.parseDate(r['lastDatePriorEx']);
      const lot = B3Registry.parseNumber(r['quotedPerShares']) ?? 1;
      const value = B3Registry.parseNumber(r['valueCash']);
      if (shareClass === null || shareClass.length === 0 || kind === undefined || withInput === null) {
        continue;
      }
      if (value === null || !(value > 0) || !(lot > 0)) continue;
      const price = B3Registry.parseNumber(r['closingPricePriorExDate']);
      out.push(
        new CashDividend({
          shareClass,
          kind,
          lastDateWithRights: withInput,
          exDate: BrazilianCalendar.nextTradingSession(withInput),
          amount: value / lot,
          closeWithRights: price !== null && price > 0 ? price / lot : null,
        }),
      );
    }
    out.sort((a, b) => a.exDate.compareTo(b.exDate));
    return out;
  },

  /**
   * Classe da ação de [ticker], pelo sufixo numérico, ou `null`.
   *
   * 3 é ordinária, 4 preferencial, 5 a 8 preferenciais de classe A a D, e 11
   * a unit.
   */
  shareClassOf(ticker: string): string | null {
    const m = /(\d+)$/.exec(ticker.trim());
    switch (m?.[1]) {
      case '3':
        return 'ON';
      case '4':
        return 'PN';
      case '5':
        return 'PNA';
      case '6':
        return 'PNB';
      case '7':
        return 'PNC';
      case '8':
        return 'PND';
      case '11':
        return 'UNT';
      default:
        return null;
    }
  },
};

/** Saída de [TotalReturn.factor]. */
export interface TotalReturnFactor {
  readonly factor: number;
  readonly applied: number;
  readonly approximated: number;
  readonly withoutPrice: number;
}

/** Retorno total a partir do retorno de preço e dos proventos do período. */
export const TotalReturn = {
  /**
   * Fator de reinvestimento dos proventos com data ex em `(de, ate]`.
   *
   * O retorno total diário é `(P_t + D_t)/P_{t−1}`, e o produto dele no
   * período é o retorno de preço vezes `Π (1 + D_i / P_ex,i)` — o provento
   * reinvestido no fechamento da data ex. **Por isso o fator não depende de
   * ajuste por desdobramento**: provento e preço da data ex estão na mesma
   * base, a daquele dia, e multiplicam um retorno de preço que já foi
   * ajustado por evento.
   *
   * - [closeOnExDate]: fechamento **bruto**, por ação, no primeiro pregão a
   *   partir da data ex. `null` quando a série não tem o pregão — papel que
   *   trocou de código, como ESTC3 para YDUQ3, só tem no COTAHIST o código
   *   novo. Aí vale o preço com direito que a B3 publica, menos o provento: a
   *   aproximação erra pelo quanto o mercado andou no dia ex vezes o
   *   rendimento, e é contada em `approximated`. Sem nenhum dos dois, o
   *   provento fica de fora e é contado em `withoutPrice`.
   * - [net]: `true` desconta o imposto retido do juro sobre capital próprio.
   *
   * **Proventos da mesma data ex entram juntos** (lente `nucleo`,
   * 25/09/2026): o retorno do dia é `(P_ex + D_1 + D_2)/P_com`, e o fator é
   * `1 + (D_1 + D_2)/P_ex`. Multiplicar `(1 + D_1/P_ex)(1 + D_2/P_ex)`
   * inventava o termo cruzado `D_1·D_2/P_ex²` — um provento rendendo sobre o
   * outro no mesmo dia —, e dividendo e juro sobre capital próprio saem
   * juntos com frequência. Os rendimentos do dia somam, como no índice.
   */
  factor(args: {
    dividends: Iterable<CashDividend>;
    from: DateTime;
    until: DateTime;
    closeOnExDate: (exDate: DateTime) => number | null;
    net?: boolean;
  }): TotalReturnFactor {
    const net = args.net ?? true;
    const d = DateTime.utc(args.from.year, args.from.month, args.from.day);
    const a = DateTime.utc(args.until.year, args.until.month, args.until.day);
    const byDay = new Map<string, CashDividend[]>();
    for (const x of args.dividends) {
      if (!x.exDate.isAfter(d) || x.exDate.isAfter(a)) continue;
      const day = DateTime.utc(x.exDate.year, x.exDate.month, x.exDate.day);
      let group = byDay.get(day.key);
      if (group === undefined) {
        group = [];
        byDay.set(day.key, group);
      }
      group.push(x);
    }
    let factor = 1.0;
    let applied = 0;
    let approximated = 0;
    let withoutPrice = 0;
    for (const group of byDay.values()) {
      const price = args.closeOnExDate(group[0]!.exDate);
      // O rendimento do dia sobre o preço ex; sem o pregão, sobre o preço com
      // direito, e o preço ex sai dele menos os proventos do dia: `D/P_ex` é
      // `(D/P_com) / (1 − ΣD/P_com)`.
      let overEx = 0.0;
      if (price !== null && price > 0) {
        for (const x of group) {
          overEx += (net ? x.netAmount : x.amount) / price;
        }
      } else {
        let withInput: number | null = null;
        for (const x of group) {
          withInput ??= x.closeWithRights;
        }
        let decline = 0.0;
        let paid = 0.0;
        if (withInput !== null && withInput > 0) {
          for (const x of group) {
            decline += x.amount / withInput;
            paid += (net ? x.netAmount : x.amount) / withInput;
          }
        }
        if (withInput === null || !(withInput > 0) || !(decline < 1)) {
          withoutPrice += group.length;
          continue;
        }
        overEx = paid / (1 - decline);
        approximated += group.length;
      }
      factor *= 1 + overEx;
      applied += group.length;
    }
    return { factor, applied, approximated, withoutPrice };
  },
};

/** Saída de [TotalReturnIndex.build]. */
export interface TotalReturnIndexResult {
  readonly index: number[];
  readonly applied: number;
  readonly withoutPrice: number;
}

/** Índice de retorno total sobre uma série de fechamentos (item A4). */
export const TotalReturnIndex = {
  /**
   * O índice, posição a posição com [closes], começando em 1.
   *
   * O retorno de cada pregão é `P_t/P_{t−1}`, mais o rendimento dos proventos
   * com data ex em `(t−1, t]`: `D/P_com`, com o preço **com direito** que a B3
   * publica. É a identidade `(P_ex + D)/P_com = P_ex/P_com + D/P_com` — e,
   * como `D` e `P_com` são brutos do mesmo dia, o rendimento não depende de a
   * série estar ajustada por desdobramento.
   *
   * Provento sem preço com direito fica de fora, contado em `withoutPrice`.
   */
  build(args: {
    dates: readonly DateTime[];
    closes: readonly number[];
    dividends: Iterable<CashDividend>;
    net?: boolean;
  }): TotalReturnIndexResult {
    const { dates, closes } = args;
    const net = args.net ?? true;
    const n = dates.length < closes.length ? dates.length : closes.length;
    const sortedDividends = [...args.dividends].sort((a, b) => a.exDate.compareTo(b.exDate));
    const index = new Array<number>(n).fill(1.0);
    let applied = 0;
    let withoutPrice = 0;
    let k = 0;
    const day = (d: DateTime): DateTime => DateTime.utc(d.year, d.month, d.day);
    // Proventos anteriores ao primeiro pregão não pertencem à série.
    while (k < sortedDividends.length && n > 0 && !sortedDividends[k]!.exDate.isAfter(day(dates[0]!))) {
      k++;
    }
    for (let i = 1; i < n; i++) {
      const today = day(dates[i]!);
      let income = 0.0;
      while (k < sortedDividends.length && !sortedDividends[k]!.exDate.isAfter(today)) {
        const p = sortedDividends[k++]!;
        const withInput = p.closeWithRights;
        if (withInput === null || !(withInput > 0)) {
          withoutPrice++;
          continue;
        }
        income += (net ? p.netAmount : p.amount) / withInput;
        applied++;
      }
      const previous = closes[i - 1]!;
      const r = previous > 0 ? closes[i]! / previous + income : 1.0;
      index[i] = index[i - 1]! * r;
    }
    return { index, applied, withoutPrice };
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
 * Formato do pacote de proventos, para empacotar no aplicativo (item A4).
 *
 * Mora no núcleo pela mesma razão do `B3RegistryCodec`: a ferramenta que grava
 * e o repositório que lê precisam concordar sobre o formato.
 */
export const CashDividendsCodec = {
  /** Versão do formato. */
  version: 1,

  /** O pacote inteiro, por emissor de quatro letras. */
  encode(byIssuer: ReadonlyMap<string, readonly CashDividend[]>, args: { generatedAt: DateTime }): JsonObject {
    const issuers: JsonObject = {};
    for (const [key, value] of byIssuer) {
      issuers[key] = value.map((p) => {
        const entry: JsonObject = {
          classe: p.shareClass,
          tipo: p.kind.key,
          dataCom: codecDay(p.lastDateWithRights),
          dataEx: codecDay(p.exDate),
          valor: p.amount,
        };
        if (p.closeWithRights !== null) entry['precoComDireito'] = p.closeWithRights;
        return entry;
      });
    }
    return { versao: CashDividendsCodec.version, geradoEm: codecDay(args.generatedAt), emissores: issuers };
  },

  /** Lê o pacote. Versão desconhecida devolve mapa vazio. */
  decode(pkg: JsonObject): Map<string, readonly CashDividend[]> {
    if (pkg['versao'] !== CashDividendsCodec.version) return new Map();
    const issuers = pkg['emissores'];
    if (!isJsonObject(issuers)) return new Map();
    const out = new Map<string, readonly CashDividend[]>();
    for (const [key, list] of Object.entries(issuers)) {
      if (!Array.isArray(list)) continue;
      const dividends: CashDividend[] = [];
      for (const x of list) {
        if (!isJsonObject(x)) continue;
        const shareClass = x['classe'];
        const kind = CashDividendKind.values.find((k) => k.key === x['tipo']) ?? null;
        const withInput = codecDate(x['dataCom']);
        const ex = codecDate(x['dataEx']);
        const value = asDouble(x['valor']);
        const price = asDouble(x['precoComDireito']);
        if (typeof shareClass !== 'string' || kind === null || withInput === null || ex === null) {
          continue;
        }
        if (value === null || !(value > 0)) continue;
        dividends.push(
          new CashDividend({
            shareClass,
            kind,
            lastDateWithRights: withInput,
            exDate: ex,
            amount: value,
            closeWithRights: price !== null && price > 0 ? price : null,
          }),
        );
      }
      dividends.sort((a, b) => a.exDate.compareTo(b.exDate));
      out.set(key, Object.freeze(dividends));
    }
    return out;
  },

  /** Os proventos da classe de [ticker], dentro de [byIssuer]. */
  forTicker(byIssuer: ReadonlyMap<string, readonly CashDividend[]>, ticker: string): CashDividend[] {
    if (ticker.length < 5) return [];
    const shareClass = B3CashDividends.shareClassOf(ticker);
    if (shareClass === null) return [];
    return (byIssuer.get(ticker.substring(0, 4)) ?? []).filter((p) => p.shareClass === shareClass);
  },
};
