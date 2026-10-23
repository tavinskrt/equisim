// O prêmio de risco implícito no preço do mercado, e a versão normalizada —
// medição, sem ligar nada no motor.
//
// **A pergunta.** O prêmio histórico (`tool/historical-premium.ts`) sai
// negativo na maior parte das datas: o que aconteceu não é o que o investidor
// esperava. O método que olha para a frente é o de Damodaran: a taxa de
// retorno que faz o valor de mercado das ações igualar o dinheiro que elas vão
// distribuir, menos a taxa livre de risco.
//
// **A conta, em cada data `t`.**
//
//     P      = valor de mercado somado das companhias
//     CF₀    = dividendos e JCP pagos nos doze meses anteriores, somados
//     g      = crescimento nominal da economia na data (o teto de `g∞` do motor)
//     r      = CF₀·(1 + g) ÷ P + g                 (Gordon)
//     prêmio = (1 + r) ÷ (1 + prefixado de 10 anos) − 1
//
// O modelo de Damodaran projeta cinco anos com o crescimento dos analistas e
// depois uma perpetuidade; sem consenso de analistas, os dois estágios usam o
// mesmo `g`, e o de dois estágios colapsa no de Gordon.
//
// **A versão normalizada** é a média dos prêmios implícitos trimestrais dos
// últimos cinco e dos últimos dez anos até a data — o que suaviza o ciclo, como
// a média de dez anos que Damodaran publica ao lado do implícito do mês.
//
// **De onde vem cada peça**, em datas trimestrais desde 31/03/2011:
//
// - valor de mercado: a contagem de ações do Formulário de Referência na data,
//   corrigida pelos eventos que ele não absorveu (B30), vezes o fechamento
//   bruto do COTAHIST de cada espécie — `MarketValue.atDate`, o mesmo do
//   backtest;
// - caixa distribuído: os proventos em dinheiro da B3 (`data/b3/complemento`),
//   pela soma dos rendimentos de cada provento na classe mais negociada
//   (`valor ÷ preço com direito`), vezes o valor de mercado da companhia;
// - crescimento: `ResolveMarketAnchors` na data (IPCA e IBC-Br de dez anos);
// - taxa livre de risco: o prefixado de dez anos da curva do Tesouro na data.
//
// **As companhias são as listadas hoje** (as dos proventos da B3). As que saíram
// da bolsa não têm os proventos no arquivo, e somar o valor delas sem o caixa
// derrubaria o rendimento. O agregado das datas antigas é, portanto, o das
// sobreviventes — declarado no relatório.
//
//   npm run tool -- implied-premium              # grava premio_implicito.json
//   npm run tool -- implied-premium --so-serie   # só a série e o pacote
import { existsSync } from 'node:fs';

import {
  CapmInputs,
  type CashDividend,
  compareNum,
  compareStr,
  DateRange,
  DateTime,
  Duration,
  ImpliedPremiumCodec,
  ImpliedPremiumPackage,
  ImpliedPremiumQuarter,
  type JsonObject,
  ResolveMarketAnchors,
  round,
  type ShareEvent,
  type Ticker,
  TreasuryCurve,
  ValuationCascade,
  type ValuationResult,
  type YieldCurve,
} from '../src/core';
import { dividendsOf, readDividends, readRawCotahist, type TradingDay, tradingDayUntil } from './b3/dividends';
import { CapitalClasses, chain, companyCodes, kindOf, MarketValue, sessionMargin } from './cohorts/as-of-base';
import { type AcceptedCount, checkCount, type CountEntry, largeCountChange } from './cohorts/checked-count';
import { sharesWithEvents, ShareEvents } from './cohorts/share-events';
import { readTreasury } from './curve-link';
import { FcaCodes } from './cvm/fca-codes';
import { FreIssuances } from './cvm/fre-issues';
import { errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';
import { LongIbovespa } from './validation/long-ibovespa';
import { Regression } from './validation/regression';

const output = 'docs/validacao/premio_implicito.json';

/** O pacote que o aplicativo e o backtest leem (decisão 142). */
const packageFile = 'public/assets/mercado/premio_implicito.json';
const reference = CapmInputs.defaultMarketPremium;

/** Fração mínima de trimestres presentes para uma média normalizada valer. */
const minCoverage = 0.8;

const pct = (v: number, decimals = 2): string => `${(v * 100).toFixed(decimals)}%`;

/** A mediana de [v], ou `null` sem valor — o JSON não grava NaN. */
function median(v: readonly number[]): number | null {
  const o = [...v].sort(compareNum);
  if (o.length === 0) return null;
  const m = Math.floor(o.length / 2);
  return o.length % 2 === 1 ? o[m]! : (o[m - 1]! + o[m]!) / 2;
}

const day10 = (d: DateTime): string => d.toIso8601String().substring(0, 10);

/** Uma entrada da contagem que o preço não confirmou, com a companhia. */
interface Discarded {
  cnpj: string;
  since: DateTime;
  shares: number;
  previous: number;
  source: string | null;
}

/**
 * A contagem por data de uma listada, como veio de
 * `data/b3/listadas_contagem.json`, com a fonte de cada entrada.
 */
class Count {
  constructor(
    readonly raw: CountEntry[],
    readonly classes: CapitalClasses,
  ) {}

  static read(): Map<string, Count> {
    const f = 'data/b3/listadas_contagem.json';
    if (!existsSync(f)) throw new Error(`sem ${f}: rode npm run tool -- b3-delisted-count`);
    const j = readJson<Record<string, { contagem: { desde: string; acoes: number; fonte?: string | null }[]; classes?: unknown[] | null }>>(f);
    const out = new Map<string, Count>();
    for (const [cnpj, v] of Object.entries(j)) {
      const raw = v.contagem
        .map((p) => ({ since: DateTime.parse(`${p.desde}T00:00:00Z`), shares: p.acoes, source: p.fonte ?? null }))
        .sort((a, b) => a.since.compareTo(b.since));
      out.set(cnpj, new Count(raw, CapitalClasses.fromJson(v.classes ?? null)));
    }
    return out;
  }
}

/** Uma companhia listada, com o que a conta precisa dela. */
interface Company {
  cnpj: string;
  /** Raiz de quatro letras de hoje: é por ela que os proventos são lidos. */
  root: string;
  /** A contagem conferida contra o preço, de `checkCount` (item B43). */
  accepted: AcceptedCount[];
  /** A data da primeira contagem do formulário, conferida ou não. */
  firstRaw: DateTime | null;
  classes: CapitalClasses;
  /** Pregões brutos de cada código de espécie, já encadeados. */
  securities: Map<string, TradingDay[]>;
  events: ShareEvent[];
}

/** O último pregão de [s] até [date], a até [sessionMargin] dias. */
const tradingDayUntilMargin = (s: readonly TradingDay[], date: DateTime): TradingDay | null => tradingDayUntil(s, date, sessionMargin);

/** Volume financeiro dos 21 pregões até [date]. */
function tradedValue(s: readonly TradingDay[], date: DateTime): number {
  let sum = 0.0;
  let n = 0;
  for (let i = s.length - 1; i >= 0 && n < 21; i--) {
    if (s[i]!.date.isAfter(date)) continue;
    sum += s[i]!.tradedValue ?? 0;
    n++;
  }
  return sum;
}

/** O agregado de uma data. */
class Aggregate {
  constructor(
    /** Valor de mercado somado, em centavos. */
    readonly valueInCents: number,
    /** Dinheiro distribuído nos doze meses, somado, em centavos. */
    readonly cashInCents: number,
    readonly companies: number,
    readonly withDividend: number,
    /** A companhia de maior valor na data, para conferir a escala. */
    readonly greatest: { root: string; value: number } | null,
    /** Valor e rendimento de cada companhia, para a conferência de `--datas`. */
    readonly byCompany: { root: string; value: number; income: number }[],
    /**
     * Raízes das companhias fora da soma porque a contagem da data não
     * concorda com o preço.
     */
    readonly excludedByCount: string[],
  ) {}

  /** Em reais, só para a saída. */
  get marketValue(): number {
    return this.valueInCents / 100;
  }

  get cash(): number {
    return this.cashInCents / 100;
  }

  get income(): number {
    return this.cashInCents / this.valueInCents;
  }
}

/**
 * O agregado da data [t].
 *
 * Proventos, contagem e pregões vêm em meia-noite UTC; a data do trimestre é
 * local, como a do motor (a curva e as âncoras leem [t]). As comparações com
 * os dados da ferramenta usam o mesmo dia em UTC, [day].
 */
function aggregate(t: DateTime, companies: readonly Company[], dividends: ReadonlyMap<string, readonly CashDividend[]>): Aggregate {
  const day = DateTime.utc(t.year, t.month, t.day);
  // As somas em centavos inteiros: o valor do mercado inteiro — R$ 5 trilhões
  // são 5 × 10¹⁴ centavos — fica longe dos 2⁵³ que o `number` representa
  // exato.
  let value = 0;
  let cash = 0;
  let n = 0;
  let withDividend = 0;
  let greatest: { root: string; value: number } | null = null;
  const byCompany: { root: string; value: number; income: number }[] = [];
  const excludedByCount: string[] = [];
  // Doze meses de calendário, e não 365 dias: no ano bissexto o dia do ano
  // anterior sairia da janela.
  const start = DateTime.utc(day.year - 1, day.month, day.day);
  for (const c of companies) {
    const shares = sharesWithEvents(c.accepted, day, c.events).shares;
    if (shares === null || !(shares > 0)) {
      // Havia contagem no formulário, e nenhuma que o preço confirmasse.
      if (c.firstRaw !== null && !c.firstRaw.isAfter(day) && [...c.securities.values()].some((s) => tradingDayUntilMargin(s, day) !== null)) {
        excludedByCount.push(c.root);
      }
      continue;
    }
    const marketValue = MarketValue.atDate({ shares, commonFraction: c.classes.at(day), securities: c.securities, date: day });
    if (marketValue === null || !(marketValue.value > 0)) continue;

    // A classe mais negociada na data é a que dá o rendimento: dividendo por
    // ação dividido pelo preço daquela ação.
    let principal: string | null = null;
    let best = -1.0;
    for (const [code, s] of c.securities) {
      if (tradingDayUntilMargin(s, day) === null) continue;
      const f = tradedValue(s, day);
      if (f > best) {
        best = f;
        principal = code;
      }
    }
    if (principal === null) continue;
    const shareClass = principal.substring(4);
    const events = dividendsOf(dividends, `${c.root}${shareClass}`);
    let income = 0.0;
    for (const p of events) {
      if (!p.exDate.isAfter(start) || p.exDate.isAfter(day)) continue;
      // Preço com direito publicado pela B3; sem ele, o fechamento bruto do
      // último pregão antes da data ex — as duas grandezas na base de ações
      // da época, como o valor do provento.
      const price =
        p.closeWithRights ?? tradingDayUntilMargin(c.securities.get(principal)!, p.exDate.subtract(new Duration({ days: 1 })))?.close ?? null;
      if (price === null || !(price > 0) || !(p.amount > 0)) continue;
      income += p.amount / price;
    }
    value += round(marketValue.value * 100);
    cash += round(income * marketValue.value * 100);
    byCompany.push({ root: c.root, value: marketValue.value, income });
    if (greatest === null || marketValue.value > greatest.value) greatest = { root: c.root, value: marketValue.value };
    n++;
    if (income > 0) withDividend++;
  }
  return new Aggregate(value, cash, n, withDividend, greatest, byCompany, excludedByCount);
}

/** O prefixado de dez anos da curva: a média geométrica dos forwards anuais. */
function fixedRate10(curve: YieldCurve | null): number | null {
  if (curve === null) return null;
  const fw = curve.annualForwards(10);
  if (fw.length === 0) return null;
  let factor = 1.0;
  for (const f of fw) factor *= 1 + f;
  return Math.pow(factor, 1 / fw.length) - 1;
}

/**
 * Os trimestres do pacote gravado que a série medida agora devolve diferentes.
 *
 * Compara o retorno implícito e o prefixado de cada trimestre presente nos
 * dois, com folga de 1e-9; sem pacote gravado, nada mudou.
 */
function changedQuarters(newPackage: ImpliedPremiumPackage): string[] {
  if (!existsSync(packageFile)) return [];
  const saved = ImpliedPremiumCodec.decode(readJson<JsonObject>(packageFile));
  if (saved === null) return [];
  // Pelo instante, e não pelo objeto: a chave de mapa do JavaScript é por
  // identidade.
  const byDate = new Map(saved.quarters.map((q) => [q.date.millisecondsSinceEpoch, q]));
  const out: string[] = [];
  for (const q of newPackage.quarters) {
    const g = byDate.get(q.date.millisecondsSinceEpoch);
    if (g === undefined) continue;
    if (Math.abs(g.impliedReturn - q.impliedReturn) > 1e-9 || Math.abs(g.riskFree - q.riskFree) > 1e-9) out.push(day10(q.date));
  }
  return out;
}

/**
 * As datas: o último dia de cada trimestre, de 31/03/2011 a 30/06/2026, e a
 * data da entrada congelada.
 */
function quarterDates(): DateTime[] {
  const out: DateTime[] = [];
  for (let year = 2011; year <= 2026; year++) {
    for (const month of [3, 6, 9, 12]) if (!(year === 2026 && month > 6)) out.push(DateTime.local(year, month + 1, 0));
  }
  out.push(frozenToday);
  return out;
}

class Reading {
  readonly fairValue = new Map<string, number>();
  readonly upside = new Map<string, number>();

  constructor(
    readonly label: string,
    readonly premium: number,
  ) {}
}

type SeriesRow = Record<string, unknown> & { data: string };

export async function main(args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    // -------------------------------------------------------------------
    // As companhias
    // -------------------------------------------------------------------
    const bridge = (readJson<Record<string, unknown>>('docs/validacao/ponte_cvm.json')['ponte'] ?? {}) as Record<string, string>;
    const discarded: Discarded[] = [];
    const counts = Count.read();
    const fca = FcaCodes.read();
    const dividends = readDividends();
    const shareEvents = ShareEvents.read({ issuances: FreIssuances.read() });

    const tickersOfCnpj = new Map<string, Set<string>>();
    for (const [ticker, cnpj] of Object.entries(bridge)) {
      let set = tickersOfCnpj.get(cnpj);
      if (set === undefined) tickersOfCnpj.set(cnpj, (set = new Set()));
      set.add(ticker);
    }
    const codesOf = new Map<string, Set<string>>();
    for (const [cnpj, tickers] of tickersOfCnpj) codesOf.set(cnpj, companyCodes([...tickers, ...(fca.byCnpj.get(cnpj) ?? [])]));
    const allCodes = new Set<string>();
    for (const s of codesOf.values()) for (const code of s) allCodes.add(code);
    const raw = readRawCotahist(allCodes);

    const companies: Company[] = [];
    let withoutDividend = 0;
    let withoutCount = 0;
    for (const [cnpj, tickers] of tickersOfCnpj) {
      const count = counts.get(cnpj);
      if (count === undefined) {
        withoutCount++;
        continue;
      }
      const sortedTickers = [...tickers].sort(compareStr);
      // A raiz dos proventos é a de hoje: entre os códigos da companhia, a que
      // tem arquivo na B3.
      const root = sortedTickers.map((t) => t.substring(0, 4)).find((r) => dividends.has(r)) ?? null;
      if (root === null) {
        withoutDividend++;
        continue;
      }
      const codes = codesOf.get(cnpj)!;
      const securities = new Map<string, TradingDay[]>();
      for (const code of codes) {
        const kind = kindOf(code);
        if (kind !== 'common' && kind !== 'preferred') continue;
        const s = chain(code, codes, raw);
        if (s.length > 0) securities.set(code, s);
      }
      if (securities.size === 0) continue;
      const principal = sortedTickers[0]!;
      const events = shareEvents.ofSecurity({ cnpj, ticker: principal, rawSessions: chain(principal, codes, raw) });
      const checked = checkCount(count.raw, securities.values(), DateTime.utc(frozenToday.year, frozenToday.month, frozenToday.day));
      for (const d of checked.discarded) {
        discarded.push({ cnpj, since: d.since, shares: d.shares, previous: d.acceptedAfter, source: d.source });
      }
      companies.push({
        cnpj,
        root,
        accepted: checked.accepted,
        firstRaw: count.raw[0]?.since ?? null,
        classes: count.classes,
        securities,
        events,
      });
    }
    errln(`contagem: ${discarded.length} entradas sem o salto do preço`);
    if (args.includes('--contagens')) {
      const rootOf = new Map(companies.map((x) => [x.cnpj, x.root]));
      for (const d of discarded) {
        outln(
          `  ${rootOf.get(d.cnpj) ?? 'null'}  ${day10(d.since)}  ${d.previous.toExponential(3)} -> ` +
            `${d.shares.toExponential(3)}  ${d.source ?? 'null'}`,
        );
      }
      for (const x of companies) {
        const a = x.accepted;
        const large: string[] = [];
        for (let i = 1; i < a.length; i++) {
          if (a[i]!.shares / a[i - 1]!.shares > largeCountChange || a[i - 1]!.shares / a[i]!.shares > largeCountChange) {
            large.push(`${day10(a[i]!.since)} ${a[i]!.shares.toExponential(3)}`);
          }
        }
        if (large.length > 0) outln(`  aceita pelo salto: ${x.root}  ${large.join('; ')}`);
      }
      return;
    }
    errln(`companhias: ${companies.length} (${withoutDividend} sem o histórico de proventos da B3, ${withoutCount} sem contagem por data)`);

    const treasury = readTreasury('data/tesouro/precotaxatesourodireto.csv');
    const today = frozenToday;
    const index = await LongIbovespa.build(c.ctx.benchmark, new DateRange(DateTime.local(today.year - 10, today.month, today.day), today));

    // -------------------------------------------------------------------
    // O prêmio implícito em cada data
    // -------------------------------------------------------------------
    outln('-- o prêmio implícito, data a data --');
    outln(
      '  data        companhias  valor (R$ bi)  rendimento  ' +
        'g nominal   r implícito  prefixado 10a   prêmio    r − Rf   maior     fora',
    );
    const series: SeriesRow[] = [];
    const datesOnly = args.filter((a) => a.startsWith('--datas=')).flatMap((a) => a.substring(8).split(',').map((d) => DateTime.parse(d)));
    for (const t of datesOnly.length === 0 ? quarterDates() : datesOnly) {
      const a = aggregate(t, companies, dividends);
      if (a.companies === 0 || !(a.marketValue > 0)) {
        outln(`  ${day10(t)}  sem dado`);
        continue;
      }
      const anchors = (await ResolveMarketAnchors.call({ macro: c.ctx.macro, benchmark: index, asOf: t })).unwrap();
      const g = anchors.nominalEconomyGrowth;
      const curve = TreasuryCurve.at(treasury, t);
      const rf = fixedRate10(curve);
      const r = a.income * (1 + g) + g;
      const premium = rf === null ? null : (1 + r) / (1 + rf) - 1;
      series.push({
        data: day10(t),
        companhias: a.companies,
        companhiasComProvento: a.withDividend,
        valorDeMercado: a.marketValue,
        caixaDistribuido: a.cash,
        rendimento: a.income,
        crescimentoNominal: g,
        retornoImplicito: r,
        prefixado10: rf,
        premio: premium,
        foraPelaContagem: a.excludedByCount,
        maiorCompanhia: a.greatest?.root ?? null,
        fatiaDaMaior: a.greatest === null ? null : a.greatest.value / a.marketValue,
        premioComGMenos1: rf === null ? null : (1 + a.income * (1 + g - 0.01) + g - 0.01) / (1 + rf) - 1,
        premioComGMais1: rf === null ? null : (1 + a.income * (1 + g + 0.01) + g + 0.01) / (1 + rf) - 1,
      });
      outln(
        `  ${day10(t)}  ` +
          `${String(a.companies).padStart(10)}  ` +
          `${(a.marketValue / 1e9).toFixed(0).padStart(13)}  ` +
          `${pct(a.income).padStart(10)}  ${pct(g).padStart(9)}   ` +
          `${pct(r).padStart(11)}  ${(rf === null ? '—' : pct(rf)).padStart(13)}   ` +
          `${(premium === null ? '—' : pct(premium)).padStart(7)}   ` +
          `${(rf === null ? '—' : pct(r - rf)).padStart(7)}   ` +
          `${a.greatest!.root} ${pct(a.greatest!.value / a.marketValue, 0)}   ` +
          `${a.excludedByCount.length}`,
      );
      if (datesOnly.length > 0) {
        const order = [...a.byCompany].sort((x, y) => compareNum(y.value, x.value));
        for (const p of order.slice(0, 12)) {
          outln(`      ${p.root}  R$ ${(p.value / 1e9).toFixed(1)} bi  ${pct(p.value / a.marketValue, 1)}  rendimento ${pct(p.income)}`);
        }
      }
    }

    // -------------------------------------------------------------------
    // A versão normalizada: médias de cinco e de dez anos
    // -------------------------------------------------------------------
    const entryDay = day10(today);
    for (const row of series) {
      const t = DateTime.parse(row.data);
      for (const years of [5, 10]) {
        const start = DateTime.local(t.year - years, t.month, t.day);
        const window: number[] = [];
        for (const l of series) {
          const d = DateTime.parse(l.data);
          // A data congelada não é trimestre: não entra na média dos
          // trimestres, só a recebe.
          if (d.isAfter(start) && !d.isAfter(t) && l['premio'] !== null && l.data !== entryDay) window.push(l['premio'] as number);
        }
        const expected = years * 4;
        row[`normalizado${years}`] = window.length >= expected * minCoverage ? window.reduce((x, y) => x + y) / window.length : null;
        row[`trimestresNaMedia${years}`] = window.length;
      }
    }

    // -------------------------------------------------------------------
    // O pacote: a série trimestral que o aplicativo e o backtest leem
    // (decisão 142). A média que o motor usa sai do núcleo, sobre `r − Rf`.
    // -------------------------------------------------------------------
    const pkg = new ImpliedPremiumPackage({
      generatedAt: DateTime.utc(today.year, today.month, today.day),
      quarters: series
        .filter((l) => l.data !== entryDay && l['retornoImplicito'] !== null && l['prefixado10'] !== null)
        .map(
          (l) =>
            new ImpliedPremiumQuarter({
              date: DateTime.parse(`${l.data}T00:00:00Z`),
              impliedReturn: l['retornoImplicito'] as number,
              riskFree: l['prefixado10'] as number,
            }),
        ),
    });
    for (const row of series) {
      const t = DateTime.parse(row.data);
      const r = (row['retornoImplicito'] as number | null) ?? null;
      const rf = (row['prefixado10'] as number | null) ?? null;
      row['premioSomado'] = r === null || rf === null ? null : r - rf;
      row['premioDoMotor'] = pkg.normalizedAt(t);
      row['trimestresDoMotor'] = pkg.window(t).length;
      // A média de cinco anos na mesma forma, só para comparação.
      const five = pkg.quarters
        .filter((q) => q.date.isAfter(DateTime.utc(t.year - 5, t.month, t.day)) && !q.date.isAfter(DateTime.utc(t.year, t.month, t.day)))
        .map((q) => q.premium);
      row['premioSomado5'] = five.length >= 20 * minCoverage ? five.reduce((x, y) => x + y) / five.length : null;
    }
    if (datesOnly.length === 0) {
      // **O passado não muda em silêncio** (item B48). Um trimestre já gravado
      // é fato histórico; se a série medida agora o devolve diferente, a causa
      // é dado que mudou por baixo — em 02/10/2026, as âncoras de 2011 e 2012
      // dependiam de a rede devolver o IBC-Br anterior à entrada congelada, e
      // sem ela o crescimento caía no recuo de 2026. Só regrava com
      // `--aceitar-mudanca-do-passado`, depois de entender a diferença.
      const changed = changedQuarters(pkg);
      if (changed.length > 0 && !args.includes('--aceitar-mudanca-do-passado')) {
        errln(
          `ERRO: ${changed.length} trimestre(s) já gravado(s) em ${packageFile} mudaram ` +
            `(${changed.slice(0, 6).join(', ')}${changed.length > 6 ? '…' : ''}); o pacote ` +
            'não foi regravado. Confira a causa e, se a mudança for intencional, ' +
            'rode de novo com --aceitar-mudanca-do-passado.',
        );
        process.exitCode = 1;
        return;
      }
      writeText(packageFile, JSON.stringify(ImpliedPremiumCodec.encode(pkg)));
      outln(
        `escrito ${packageFile}: ${pkg.quarters.length} trimestres; o prêmio do motor em ${entryDay} é ` +
          `${pct(pkg.normalizedAt(today) ?? Number.NaN)}`,
      );
    }

    outln('');
    // Na forma que o motor soma (`r − Rf`); as médias da forma de Fisher
    // ficam no JSON (`normalizado5`, `normalizado10`).
    outln('-- implícito e normalizado nas datas das coortes (r − Rf) --');
    outln('  data        implícito   média 5 anos   média 10 anos (o motor)');
    const f = (v: unknown): string => (v === null || v === undefined ? '—' : pct(v as number));
    for (const l of series) {
      if (DateTime.parse(l.data).year < 2018) continue;
      outln(`  ${l.data}  ${f(l['premioSomado']).padStart(9)}   ${f(l['premioSomado5']).padStart(12)}   ${f(l['premioDoMotor']).padStart(13)}`);
    }

    if (args.includes('--so-serie')) return;

    // -------------------------------------------------------------------
    // O que cada um faz ao aplicativo, sobre a entrada congelada
    // -------------------------------------------------------------------
    const ofEntry = series.findLast((l) => l.data === entryDay);
    if (ofEntry === undefined) throw new Error(`a série não tem a data da entrada congelada, ${entryDay}`);
    const fromEngine = pkg.normalizedAt(today);
    if (fromEngine === null) {
      errln('ERRO: a série não tem trimestres para a média de dez anos');
      process.exitCode = 1;
      return;
    }
    // A montagem do aplicativo lê o pacote que estava em disco quando a
    // entrada congelada foi montada; se a série medida agora for outra, a
    // conferência contra o gabarito compararia montagens diferentes.
    if (Math.abs(c.premium.value - fromEngine) > 1e-12) {
      errln(
        `ERRO: o pacote em disco dava ${pct(c.premium.value)} e a série medida agora dá ${pct(fromEngine)}. ` +
          'O pacote foi regravado: rode de novo, e regrave o gabarito antes (npm run tool -- cascade-golden).',
      );
      process.exitCode = 1;
      return;
    }
    // A média de cinco anos, na mesma forma `r − Rf`, para comparação.
    const fiveYears = pkg.quarters.filter((q) => q.date.isAfter(DateTime.utc(today.year - 5, today.month, today.day))).map((q) => q.premium);
    const implied = ofEntry['premioSomado'];
    const candidates: [string, number | null][] = [
      // A primeira é a do aplicativo (`premio` nulo: o do pacote), e é a que
      // se confere contra o gabarito.
      ['média de 10 anos — o motor', null],
      ['5,5% (até a decisão 142)', reference],
      ...(typeof implied === 'number' ? [['implícito', implied] as [string, number]] : []),
      ...(fiveYears.length >= 20 ? [['média de 5 anos', fiveYears.reduce((a, b) => a + b) / fiveYears.length] as [string, number]] : []),
    ];
    const readings: Reading[] = [];
    for (const [k, [label, premium]] of candidates.entries()) {
      const l = new Reading(label, premium ?? fromEngine);
      const evaluated = new Map<Ticker, ValuationResult | null>();
      let i = 0;
      for (const t of c.universe) {
        i++;
        if (i % 50 === 0) process.stderr.write(`  ${label}: ${i}/${c.universe.length}   \r`);
        const prep = await c.prepare(t, { premium });
        if (prep.isErr) continue;
        const r = ValuationCascade.evaluate(prep.unwrap());
        if (k === 0) evaluated.set(t, r.valueOrNull);
        if (r.isErr) continue;
        l.fairValue.set(t.value, r.unwrap().fairValue.cents);
        l.upside.set(t.value, r.unwrap().upside);
      }
      if (k === 0) {
        const div = await c.checkAgainstAnswerKey(evaluated);
        if (div !== null && div.length > 0) {
          errln(`ERRO: a montagem do aplicativo diverge do gabarito em ${div.length}: ${div.slice(0, 8).join(', ')}`);
          process.exitCode = 1;
          return;
        }
      }
      readings.push(l);
    }
    process.stderr.write('                                        \r');

    const base = readings[0]!;
    const effects: Record<string, unknown>[] = [];
    outln('');
    outln('-- o universo reavaliado sobre a entrada congelada --');
    outln('  prêmio                  avaliados   potencial mediano   acima de zero   preço justo vs o motor   postos');
    for (const l of readings) {
      const upsideValues = [...l.upside.values()];
      const common = [...l.fairValue.keys()].filter((k) => base.fairValue.has(k)).sort(compareStr);
      const changeList: number[] = [];
      for (const k of common) if (base.fairValue.get(k)! !== 0) changeList.push(l.fairValue.get(k)! / base.fairValue.get(k)! - 1);
      const rho =
        common.length < 3
          ? null
          : Regression.spearman(
              common.map((k) => base.upside.get(k)!),
              common.map((k) => l.upside.get(k)!),
            );
      const above = upsideValues.filter((p) => p > 0).length;
      const medianUpside = median(upsideValues);
      const medVar = median(changeList);
      outln(
        `  ${`${l.label} (${pct(l.premium)})`.padEnd(24)}` +
          `${String(l.fairValue.size).padStart(9)}   ` +
          `${(medianUpside === null ? '—' : pct(medianUpside)).padStart(17)}   ` +
          `${`${above} de ${upsideValues.length}`.padStart(13)}   ` +
          `${(medVar === null ? '—' : pct(medVar)).padStart(19)}   ` +
          `${rho === null ? '—' : rho.toFixed(3)}`,
      );
      const cases: Record<string, unknown> = {};
      for (const t of ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3']) {
        cases[t] = { justoCentavos: l.fairValue.get(t) ?? null, potencial: l.upside.get(t) ?? null };
      }
      effects.push({
        rotulo: l.label,
        premio: l.premium,
        avaliados: l.fairValue.size,
        potencialMediano: medianUpside,
        acimaDeZero: above,
        precoJustoMedianoContraReferencia: medVar,
        spearmanContraReferencia: rho,
        casos: cases,
      });
    }

    writeText(
      output,
      jsonPretty(
        {
          geradoPor: 'tool/implied-premium.ts',
          dataDaEntrada: day10(today),
          companhias: companies.length,
          contagensSemSalto: discarded.map((d) => ({
            cnpj: d.cnpj,
            desde: day10(d.since),
            acoes: d.shares,
            anterior: d.previous,
            fonte: d.source,
          })),
          serie: series,
          efeitos: effects,
        },
        ' ',
      ),
    );
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}
