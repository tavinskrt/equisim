// A ponte por papel na data da coorte (item C3).
//
// **Dois defeitos da montagem das coortes, e um é a causa do outro.**
//
// 1. **O preço da coorte estava na base de ações de hoje.** A fonte publica o
//    fechamento ajustado por todo evento de ações até hoje, e a coorte o
//    multiplicava pela contagem do exercício, que está na base daquele ano. A
//    MGLU3 de 30/09/2020 entrava a R$ 212,38: o fechamento do dia foi R$ 84,95,
//    e o desdobramento de 4 para 1 de outubro de 2020 e o grupamento de 10 para
//    1 de 2024 o levaram à base de hoje. O valor de mercado da coorte saía
//    errado pelo produto dos eventos posteriores — o mesmo fator no potencial
//    e no book-to-market —, e o volume da fonte, que não é ajustado, dava à
//    Porta 0 um financeiro errado pelo mesmo fator. Conferido em 15/09/2026:
//    697 de 2.247 observações das listadas com fechamento no COTAHIST estavam
//    fora da base da data por mais de 2%, e 386 por mais de 1,5 vez.
// 2. **A razão de unidade e o divisor colapsavam por construção** (limitações
//    §3.5): com `valor de mercado = contagem × preço` e a mesma contagem como
//    corrente, a unit saía com `u = 1` e as duas candidatas a divisor, iguais.
//
// **O que a coorte passa a montar**, para listada e deslistada:
//
// - a série de preço **na base da data**: a da fonte vezes o fator
//   `fechamento bruto ÷ fechamento da fonte` medido no último pregão até a
//   data, e o volume refeito do financeiro do COTAHIST;
// - a contagem de ações **da data**, do Formulário de Referência (A3.4), como
//   contagem corrente e como a contagem oficial que arbitra o divisor — o papel
//   que o registro da B3 tem no aplicativo;
// - o valor de mercado **da companhia**, espécie a espécie: a contagem de
//   ordinárias e de preferenciais vezes o fechamento bruto do papel mais
//   negociado de cada uma. É a convenção em que a unit mede `u` ações.
import {
  compareStr,
  DateTime,
  intDiv,
  PricePoint,
  PriceSeries,
  ShareCountHistory,
  tryParseDouble,
  tryParseInt,
} from '../../src/core';
import { type TradingDay, tradingDayUntil } from '../b3/dividends';

/** Espécie de um papel pelo número do ticker. */
export type ShareKind = 'common' | 'preferred' | 'unit';

/**
 * `common` para 3, `preferred` de 4 a 8, `unit` para 11; `null` para o
 * resto — recibo, bônus, BDR.
 */
export function kindOf(ticker: string): ShareKind | null {
  if (ticker.length < 5) return null;
  const n = tryParseInt(ticker.slice(4));
  if (n === null) return null;
  if (n === 3) return 'common';
  if (n >= 4 && n <= 8) return 'preferred';
  if (n === 11) return 'unit';
  return null;
}

/**
 * Os códigos de uma companhia: os conhecidos e, para a raiz de quatro letras
 * de cada um, os das espécies e da unit — `3` a `8` e `11`.
 *
 * A FCA nem sempre declara o código de cada espécie: a Alupar declara só a
 * ALUP11, e a ALUP3 e a ALUP4 negociam. O papel que não existe simplesmente
 * não tem pregão no COTAHIST.
 */
export function companyCodes(known: Iterable<string>): Set<string> {
  const out = new Set<string>();
  for (const c of known) {
    out.add(c);
    if (c.length > 4) for (const n of ['3', '4', '5', '6', '7', '8', '11']) out.add(`${c.slice(0, 4)}${n}`);
  }
  return out;
}

/**
 * Pregões de [ticker] encadeados pelos códigos anteriores da mesma espécie.
 *
 * A fonte publica a série inteira sob o código de hoje; o COTAHIST, sob o de
 * cada época. Entram os códigos que a companhia declarou na FCA com o mesmo
 * número de classe — `VVAR3` para a `BHIA3`. No pregão em que dois códigos
 * negociam, fica o de hoje.
 */
export function chain(ticker: string, codes: Iterable<string>, cotahist: ReadonlyMap<string, readonly TradingDay[]>): TradingDay[] {
  const shareClass = ticker.length > 4 ? ticker.slice(4) : '';
  const byDay = new Map<string, TradingDay>();
  const previousOnes = [...codes].filter((c) => c !== ticker && c.length > 4 && c.slice(4) === shareClass).sort(compareStr);
  for (const c of [...previousOnes, ticker]) {
    for (const p of cotahist.get(c) ?? []) byDay.set(p.date.key, p);
  }
  return [...byDay.values()].sort((a, b) => a.date.compareTo(b.date));
}

/**
 * Folga, em dias corridos, entre a data da coorte e o último pregão: além
 * disso o papel não negociava, e não há preço da data.
 */
export const sessionMargin = 10;

/**
 * O fator que leva a série da fonte à base de ações de [date].
 *
 * `fechamento bruto ÷ fechamento da fonte` no último pregão do COTAHIST até
 * [date], medido no mesmo dia da fonte. Não se reconstrói pelos eventos do
 * registro: o fator é o que a fonte aplicou, e o registro da B3 repete evento
 * — a BBAS3 de 2018 tem fator 2 no preço e produto 8 no registro.
 *
 * Devolve `null` sem pregão a até [sessionMargin] dias, ou sem fechamento da
 * fonte naquele dia.
 */
export function baseFactorOf(args: {
  source: PriceSeries;
  rawSessions: readonly TradingDay[];
  date: DateTime;
}): { factor: number; tradingDay: TradingDay } | null {
  const tradingDay = tradingDayUntil(args.rawSessions, args.date, sessionMargin);
  if (tradingDay === null || !(tradingDay.close > 0)) return null;
  const day = DateTime.utc(tradingDay.date.year, tradingDay.date.month, tradingDay.date.day);
  const points = args.source.points;
  for (let i = points.length - 1; i >= 0; i--) {
    const p = points[i]!;
    const d = DateTime.utc(p.date.year, p.date.month, p.date.day);
    if (d.isAfter(day)) continue;
    if (d.isBefore(day)) return null;
    if (!(p.close > 0)) return null;
    const f = tradingDay.close / p.close;
    return Number.isFinite(f) && f > 0 ? { factor: f, tradingDay } : null;
  }
  return null;
}

/**
 * A série da fonte na base de ações da data, pelo [factor] de [baseFactorOf].
 *
 * O fechamento é multiplicado pelo fator. O volume é refeito do financeiro do
 * COTAHIST no mesmo dia — `financeiro ÷ fechamento na base da data` —, para que
 * `fechamento × volume` continue sendo o financeiro que a Porta 0 mede: o
 * volume da fonte não é ajustado, e o fechamento é. Dia sem COTAHIST mantém o
 * volume da fonte, que nesse caso só erra se houve evento entre ele e a data.
 */
export function seriesOnDateBasis(source: PriceSeries, rawSessions: readonly TradingDay[], factor: number): PriceSeries {
  const tradedValue = new Map<string, number>();
  for (const p of rawSessions) if (p.tradedValue !== null) tradedValue.set(p.date.key, p.tradedValue);
  return new PriceSeries({
    ticker: source.ticker,
    points: source.points.map((p) => {
      const close = p.close * factor;
      const f = tradedValue.get(DateTime.utc(p.date.year, p.date.month, p.date.day).key);
      return new PricePoint({
        date: p.date,
        close,
        adjustedClose: p.adjustedClose,
        volume: f !== undefined && close > 0 ? f / close : p.volume,
      });
    }),
  });
}

/** Como o valor de mercado saiu — ver [MarketValue.origin]. */
export type MarketValueOrigin = 'especies' | 'umaEspecie' | 'semDivisao';

/** Valor de mercado da companhia em [date], espécie a espécie. */
export class MarketValue {
  /** Pregões considerados no financeiro que escolhe o papel de cada espécie. */
  static readonly tradedValueSessions = 21;

  constructor(
    /** Em reais. */
    readonly value: number,
    /**
     * Como saiu: `especies` com as duas espécies pelo preço delas,
     * `umaEspecie` com a companhia de uma espécie só ou a espécie sem pregão
     * pelo preço da outra, e `semDivisao` sem a divisão entre espécies.
     */
    readonly origin: MarketValueOrigin,
  ) {}

  /**
   * - [shares]: contagem total da data, somadas as espécies.
   * - [commonFraction]: ordinárias ÷ total na data, ou `null` sem divisão.
   * - [securities]: pregões brutos de cada papel da companhia, já encadeados.
   *
   * A preferencial com mais de uma classe listada — PNA e PNB — vai toda pelo
   * preço da mais negociada: o formulário não separa a contagem entre elas. A
   * unit não entra: ela é cesta das outras duas.
   *
   * Devolve `null` quando nenhum papel de espécie negociou até [sessionMargin]
   * dias antes da data.
   */
  static atDate(args: {
    shares: number;
    commonFraction: number | null;
    securities: ReadonlyMap<string, readonly TradingDay[]>;
    date: DateTime;
  }): MarketValue | null {
    const { shares, securities, date } = args;
    if (!(shares > 0)) return null;
    const best = (kind: ShareKind): { price: number; tradedValue: number } | null => {
      let m: { price: number; tradedValue: number } | null = null;
      for (const [code, s] of securities) {
        if (kindOf(code) !== kind) continue;
        const last = tradingDayUntil(s, date, sessionMargin);
        if (last === null || !(last.close > 0)) continue;
        // Posição do último pregão, por busca binária: a série é ordenada.
        let lo = 0;
        let hi = s.length;
        while (lo < hi) {
          const mid = intDiv(lo + hi, 2);
          if (s[mid]!.date.isAfter(last.date)) hi = mid;
          else lo = mid + 1;
        }
        const i = lo - 1;
        let fin = 0;
        for (let k = Math.max(0, i - MarketValue.tradedValueSessions + 1); k <= i; k++) fin += s[k]!.tradedValue ?? 0;
        if (m === null || fin > m.tradedValue) m = { price: last.close, tradedValue: fin };
      }
      return m;
    };

    const on = best('common');
    const pn = best('preferred');
    if (on === null && pn === null) return null;
    const f = args.commonFraction;
    if (f === null || !Number.isFinite(f) || f < 0 || f > 1) {
      const p = on === null || (pn !== null && pn.tradedValue > on.tradedValue) ? pn!.price : on.price;
      return new MarketValue(shares * p, 'semDivisao');
    }
    const pOn = on?.price ?? pn!.price;
    const pPn = pn?.price ?? on!.price;
    // A fração vem de uma razão de contagens: a espécie única é a fração a
    // uma folga de 0 ou de 1, e não a igualdade exata.
    const margin = 1e-9;
    const singleClass = f >= 1 - margin || f <= margin || on === null || pn === null;
    return new MarketValue(shares * (f * pOn + (1 - f) * pPn), singleClass ? 'umaEspecie' : 'especies');
  }
}

/** Um ponto da divisão do capital: desde quando vale a fração de ordinárias. */
export interface ClassSplit {
  readonly since: DateTime;
  readonly fraction: number;
}

/**
 * Divisão do capital entre ordinárias e preferenciais ao longo do tempo, do
 * quadro de capital social do Formulário de Referência.
 *
 * A mesma regra de data da contagem (`ShareCountHistory`): cada aprovação de
 * capital vale pela **primeira** declaração dela. Desdobramento e grupamento
 * não mudam a fração, e por isso a série é só das aprovações.
 */
export class CapitalClasses {
  private constructor(
    /** `(desde, fração de ordinárias)`, em ordem de data. */
    readonly points: readonly ClassSplit[],
  ) {}

  static fromFre(rows: Iterable<Record<string, string>>): CapitalClasses {
    const all = [...rows];
    for (const kind of ShareCountHistory.kinds) {
      const byReference = new Map<string, Record<string, string>[]>();
      for (const r of all) {
        if (r['Tipo_Capital']?.trim() !== kind) continue;
        const ref = `${r['Data_Referencia'] ?? 'null'}`;
        const list = byReference.get(ref) ?? [];
        list.push(r);
        byReference.set(ref, list);
      }
      if (byReference.size === 0) continue;
      // A maior versão de cada referência, em ordem de referência.
      const references = [...byReference.keys()].sort(compareStr);
      const points: ClassSplit[] = [];
      const seen: DateTime[] = [];
      for (const ref of references) {
        const doc = byReference.get(ref)!;
        const version = doc.map((r) => tryParseInt(r['Versao'] ?? '') ?? 0).reduce((a, b) => Math.max(a, b), 0);
        for (const r of doc) {
          if ((tryParseInt(r['Versao'] ?? '') ?? 0) !== version) continue;
          const v = r['Data_Autorizacao_Aprovacao'];
          const approval = v === undefined || v.length < 10 ? null : DateTime.tryParse(`${v.slice(0, 10)}T00:00:00Z`);
          const on = tryParseDouble(r['Quantidade_Acoes_Ordinarias'] ?? '');
          const pn = tryParseDouble(r['Quantidade_Acoes_Preferenciais'] ?? '');
          if (approval === null || on === null || pn === null) continue;
          if (on < 0 || pn < 0 || on + pn <= 0) continue;
          if (seen.some((a) => a.isAtSameMomentAs(approval))) continue;
          seen.push(approval);
          points.push({ since: approval, fraction: on / (on + pn) });
        }
      }
      points.sort((a, b) => a.since.compareTo(b.since));
      return new CapitalClasses(Object.freeze(points));
    }
    return new CapitalClasses([]);
  }

  /** Lê a série gravada por `b3-delisted-count.ts`. */
  static fromJson(list: readonly unknown[] | null | undefined): CapitalClasses {
    return new CapitalClasses(
      (list ?? []).map((raw) => {
        const p = raw as { desde: string; fracaoOrdinarias: number };
        return { since: DateTime.parse(`${p.desde.slice(0, 10)}T00:00:00Z`), fraction: Number(p.fracaoOrdinarias) };
      }),
    );
  }

  toJson(): { desde: string; fracaoOrdinarias: number }[] {
    return this.points.map((p) => ({ desde: p.since.toIso8601String().slice(0, 10), fracaoOrdinarias: p.fraction }));
  }

  /**
   * Fração de ordinárias em vigor em [date], ou a primeira declarada quando a
   * data vem antes dela — a divisão entre espécies muda pouco, e sem ela o
   * valor de mercado perde a espécie. `null` sem ponto nenhum.
   */
  at(date: DateTime): number | null {
    if (this.points.length === 0) return null;
    const d = DateTime.utc(date.year, date.month, date.day);
    let current = this.points[0]!.fraction;
    for (const p of this.points) {
      if (p.since.isAfter(d)) break;
      current = p.fraction;
    }
    return current;
  }
}
