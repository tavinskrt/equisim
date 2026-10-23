// Validação preditiva do motor de avaliação, *point-in-time*.
//
// **A pergunta.** O potencial que o motor apura ordena o retorno que veio
// depois? Sem essa medição, o motor tem consistência interna e cobertura
// declarada — e nenhuma evidência de que serve para decidir.
//
// **Como.** Para cada data de coorte, a cascata roda com o que era público
// naquele dia: exercícios filtrados por `PointInTimeView`, preço e beta na
// janela que termina ali, âncoras macro resolvidas naquela data. O potencial
// resultante é confrontado com o retorno realizado nos 12 e nos 36 meses
// seguintes — 36 é o horizonte de convergência da decisão 26.
//
// **Contra o quê.** Sozinho, um coeficiente de correlação não diz se a
// sofisticação se paga. O potencial é medido lado a lado com dois fatores
// ingênuos que usam os mesmos dados e nenhuma modelagem: o valor patrimonial
// sobre o preço e o lucro sobre o preço. Se o motor não os supera, a cascata
// inteira está cobrando um custo de complexidade que não entrega.
//
// **Vieses que esta medição NÃO remove**, e que o relatório declara:
//
// 1. *Sobrevivência.* Sem `--com-deslistadas`, o universo é o que está listado
//    hoje. Com ele, entram as companhias da ponte do A3.2 (item C1b) — e as que
//    a fonte de preços não traz, como a Tupy (item C1d).
// 2. *Reapresentação.* Os exercícios vêm como a fonte os publica hoje, não
//    como estavam no dia da coorte (B8).
// 3. *Provento.* O retorno de referência continua o de preço, e ao lado dele
//    sai o **retorno total** — `ret12tot` e `ret36tot` —, com os proventos da
//    B3 reinvestidos na data ex (item A4, decisão 89).
//
// **Duas montagens.** `mercado` é a das medições de 11/09/2026: só a fonte de
// preços, com a taxa de dois pontos — e com o defeito de base descrito abaixo,
// mantido para reproduzir aquelas medições. `aplicativo` é a montagem do
// aplicativo **na data de cada coorte**, peça a peça:
//
// - a curva do Tesouro daquele dia (decisão 74);
// - a CVM mesclada, com os documentos recebidos até ali (decisões 69 a 81) —
//   pela série de DFPs, que é o padrão, e pela ancorada no trimestre ao lado;
// - o setor da B3 (decisão 87);
// - o prazo das outorgas do Formulário de Referência recebido até ali
//   (decisão 88, `tool/cvm/grants-by-date.ts`);
// - o beta sobre retorno total, com os proventos da B3 (decisão 89);
// - **o preço, a contagem e o valor de mercado na base da data** (item C3,
//   `tool/cohorts/as-of-base.ts`): a série da fonte vem ajustada por todo
//   evento até hoje, e a coorte a multiplicava pela contagem do exercício, na
//   base daquele ano. Agora a série é levada à base da data pelo COTAHIST, a
//   contagem é a do Formulário de Referência na data — corrente e oficial, o
//   papel do registro da B3 no aplicativo — e o valor de mercado é o da
//   companhia, espécie a espécie, que é o que a razão de unidade mede.
//
// Na montagem `aplicativo` cada linha leva também o que o C2 e o C0 medem: a
// banda dos cenários discretos, os quantis da distribuição de Monte Carlo com
// os sorteios padrão do aplicativo (só nas coortes de 30/09), a liquidez da
// Porta 0 e, para ativo recusado, o potencial sem o corte de liquidez.
//
// **Coortes.** Anuais, em 30/09 de 2018 a 2025, ou trimestrais com
// `--trimestral` (item C1c): o último dia de cada trimestre, de 31/03/2018 a
// 30/09/2025. A primeira é 2018 porque a Porta 0 exige oito exercícios
// publicados, e a CVM começa em 2010.
//
// Uso:
//   npm run tool -- backtest-valuation                        # mercado
//   npm run tool -- backtest-valuation --montagem aplicativo
//   npm run tool -- backtest-valuation --montagem aplicativo \
//       --com-deslistadas --trimestral [--contrafactual-base] [--amostra N]
//
// `--amostra N` limita o universo e as deslistadas aos N primeiros, para
// conferir a montagem em minutos antes da execução inteira; a saída vai para
// `docs/validacao/backtest_amostra.json` e não substitui nenhuma medição.
//
// **A medição do item B46**, sobre a montagem do aplicativo:
//
//   npm run tool -- backtest-valuation --montagem aplicativo \
//       --com-deslistadas --trimestral --premio-estatal 0.005,0.01,0.02,0.03
//   python tool/estatais_backtest.py
//
// `--premio-estatal` avalia de novo cada observação de companhia de controle
// estatal na data (`public/assets/cvm/controle.json`) com cada prêmio a mais no
// custo do capital próprio, e grava o potencial de cada um no campo
// `potencialComPremioEstatal`; o resto da observação é o da montagem padrão.
// Para conferir em minutos, `--so-estatais` observa só elas — o prior do beta
// continua resolvido sobre o universo inteiro — e não lê deslistadas; exige
// `--saida`, que troca o arquivo de destino, para não sobrescrever a medição
// oficial.
import { existsSync } from 'node:fs';

import {
  type Asset,
  type B3Classification,
  B3RegistryCodec,
  type BenchmarkRepository,
  CalibratedBand,
  CapmInputs,
  type CashDividend,
  CashDividendsCodec,
  compareStr,
  ConcessionTermsCodec,
  CorporateEvents,
  type CvmPeriodDocument,
  CvmSeries,
  DateRange,
  DateTime,
  EligibilityGate,
  Err,
  FinancialSectors,
  type FundamentalsRepository,
  FundamentalsSnapshot,
  GrowthGuards,
  ImpliedPremiumCodec,
  InsufficientData,
  type JsonObject,
  MarketAnchors,
  MarketPremiumSource,
  OfficialShareCount,
  Ok,
  parseDouble,
  parseInt_,
  PointInTimeView,
  PrepareValuationInputs,
  type PriceRepository,
  PriceSeries,
  type QuotedShares,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  type Result,
  ScenarioBand,
  type ShareEvent,
  ShareholderControl,
  ShareholderControlHistory,
  type ShareIssue,
  StochasticScenarios,
  str,
  Ticker,
  toStringAsFixed,
  toStringAsPrecision,
  TotalReturn,
  TreasuryCurve,
  UnitCompositionCodec,
  ValuationCascade,
  type ValuationInputs,
} from '../src/core';
import { OfficialSectorFundamentalsRepository } from '../src/data/repositories/b3-registry-repository';
import { dividendsOf, readDividends, readRawCotahist, type TradingDay, tradingDayFrom, tradingDayUntil } from './b3/dividends';
import {
  baseFactorOf,
  CapitalClasses,
  chain,
  companyCodes,
  kindOf,
  MarketValue,
  seriesOnDateBasis,
  sessionMargin,
} from './cohorts/as-of-base';
import { type AcceptedCount, checkCount, type CountEntry, type DiscardedCount } from './cohorts/checked-count';
import { Delisted, DelistedFundamentals, DelistedPrices, type DelistedSecurity } from './cohorts/delisted';
import { issuancesWithoutEvent, notAdjustedBySource, ShareEvents, sharesWithEvents } from './cohorts/share-events';
import { readTreasury } from './curve-link';
import { loadDocuments } from './cvm/documents';
import { FcaCodes } from './cvm/fca-codes';
import { FreIssuances } from './cvm/fre-issues';
import { GrantsByDate } from './cvm/grants-by-date';
import { dartString, errln, jsonPretty, readJson, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

/**
 * CVM mesclada à série de mercado já reescalada, com o que era público na
 * data da coorte.
 */
class CvmAtDate implements FundamentalsRepository {
  constructor(
    readonly inner: FundamentalsRepository,
    readonly hist: FundamentalsSnapshot[],
    readonly docs: readonly CvmPeriodDocument[] | null,
    readonly date: DateTime,
    /** Série de doze meses ancorada no trimestre mais recente (A1.8, C1c). */
    readonly anchored = false,
  ) {}

  async history(_t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const ownDocs = this.docs;
    if (ownDocs === null || ownDocs.length === 0) return new Ok(this.hist);
    const view = new PointInTimeView(this.date);
    const merged = CvmSeries.build({
      documents: ownDocs,
      market: this.hist,
      published: (s) => view.isPublished(s),
      anchored: this.anchored,
    }).series;
    return new Ok([...merged]);
  }

  profile(t: Ticker): Promise<Result<Asset>> {
    return this.inner.profile(t);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.inner.universe();
  }
}

/** Sorteios da distribuição, iguais ao padrão do aplicativo. */
const draws = 10000;

/**
 * Índice buscado uma vez e reaproveitado.
 *
 * `BenchmarkRepositoryImpl` vai à rede a cada chamada, e o backtest a faria
 * milhares de vezes.
 */
class MemoBenchmark implements BenchmarkRepository {
  private full: PriceSeries | null = null;

  constructor(readonly inner: BenchmarkRepository) {}

  async ibovespa(range: DateRange): Promise<Result<PriceSeries>> {
    if (this.full === null) {
      const r = await this.inner.ibovespa(new DateRange(DateTime.local(2000, 1, 1), DateTime.local(2100, 1, 1)));
      if (r.isErr) return r;
      this.full = r.unwrap();
    }
    const full = this.full;
    return new Ok(new PriceSeries({ ticker: full.ticker, points: full.points.filter((p) => range.contains(p.date)) }));
  }
}

/** Fundamentos buscados uma vez por ativo e reaproveitados entre coortes. */
class MemoFundamentals implements FundamentalsRepository {
  private readonly hist = new Map<string, Result<FundamentalsSnapshot[]>>();
  private readonly prof = new Map<string, Result<Asset>>();
  private uni: Result<Ticker[]> | null = null;

  constructor(readonly inner: FundamentalsRepository) {}

  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    let r = this.hist.get(t.value);
    if (r === undefined) {
      r = await this.inner.history(t);
      this.hist.set(t.value, r);
    }
    return r;
  }

  async profile(t: Ticker): Promise<Result<Asset>> {
    let r = this.prof.get(t.value);
    if (r === undefined) {
      r = await this.inner.profile(t);
      this.prof.set(t.value, r);
    }
    return r;
  }

  async universe(): Promise<Result<Ticker[]>> {
    this.uni ??= await this.inner.universe();
    return this.uni;
  }
}

/**
 * Preços buscados uma vez por ativo, na janela inteira, e recortados em
 * memória para cada coorte.
 */
class MemoPrices implements PriceRepository {
  private readonly all = new Map<string, PriceSeries | null>();

  constructor(readonly inner: PriceRepository) {}

  private async load(t: Ticker): Promise<PriceSeries | null> {
    if (this.all.has(t.value)) return this.all.get(t.value) ?? null;
    const r = await this.inner.daily(t, new DateRange(DateTime.local(2010, 1, 1), DateTime.local(2026, 9, 4)));
    const s = r.isOk ? r.unwrap() : null;
    this.all.set(t.value, s);
    return s;
  }

  async daily(t: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    const s = await this.load(t);
    if (s === null) return new Err(new InsufficientData(`sem preços de ${t.value}`, { subject: t.value }));
    return new Ok(new PriceSeries({ ticker: s.ticker, points: s.points.filter((p) => range.contains(p.date)) }));
  }

  async dailyBatch(tickers: readonly Ticker[], range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>> {
    const out = new Map<Ticker, PriceSeries>();
    for (const t of tickers) {
      const r = await this.daily(t, range);
      if (r.isOk) out.set(t, r.unwrap());
    }
    return new Ok(out);
  }

  adjustedCloseRaw(t: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return this.inner.adjustedCloseRaw(t, range);
  }
}

/**
 * Uma série já montada — a da fonte na base da data da coorte —, recortada
 * pela janela pedida.
 */
class FixedSeries implements PriceRepository {
  constructor(readonly series: PriceSeries) {}

  private slice(range: DateRange): PriceSeries {
    return new PriceSeries({ ticker: this.series.ticker, points: this.series.points.filter((p) => range.contains(p.date)) });
  }

  async daily(_t: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return new Ok(this.slice(range));
  }

  async dailyBatch(tickers: readonly Ticker[], range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>> {
    return new Ok(new Map(tickers.map((t) => [t, this.slice(range)])));
  }

  adjustedCloseRaw(t: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return this.daily(t, range);
  }
}

/**
 * Reescreve o valor de mercado de cada exercício para a escala da data da
 * coorte, **na montagem `mercado`**.
 *
 * A fonte repete o valor de mercado **de hoje** em todos os exercícios —
 * conferido: ele não varia entre linhas em nenhum dos 363 ativos do cache.
 * Deixá-lo assim daria ao motor, numa avaliação de 2018, a capitalização de
 * 2026. A reconstrução usa a contagem do exercício vezes o preço da coorte.
 *
 * **Carrega o defeito de base do item C3**: o preço da fonte está na base de
 * ações de hoje, e a contagem, na do exercício. Fica assim para reproduzir as
 * medições de 11/09/2026; a montagem `aplicativo` usa [rescaleAtDate].
 */
function rescale(snaps: readonly FundamentalsSnapshot[], priceAtDate: number): FundamentalsSnapshot[] {
  return withMarket(
    snaps,
    (s) => s.sharesOutstandingAsOf,
    (s) =>
      s.sharesOutstandingAsOf !== null && s.sharesOutstandingAsOf > 0 && priceAtDate > 0 ? s.sharesOutstandingAsOf * priceAtDate : null,
  );
}

/**
 * O valor de mercado e a contagem corrente **da data** em todo exercício
 * (item C3): a contagem do Formulário de Referência e o valor de mercado da
 * companhia espécie a espécie. Sem contagem da data, recua para a contagem do
 * exercício vezes o preço bruto da data — na base certa, e com a razão de
 * unidade de volta a 1 por construção, o que a linha declara.
 */
function rescaleAtDate(
  snaps: readonly FundamentalsSnapshot[],
  args: { sharesAtDate: number | null; marketValueOf: number | null; rawPrice: number },
): FundamentalsSnapshot[] {
  return withMarket(
    snaps,
    (s) => args.sharesAtDate ?? s.sharesOutstandingAsOf,
    (s) => {
      if (args.marketValueOf !== null) return args.marketValueOf;
      const n = s.sharesOutstandingAsOf;
      return n !== null && n > 0 && args.rawPrice > 0 ? n * args.rawPrice : null;
    },
  );
}

/**
 * Cada exercício refeito campo a campo, como o original fazia: os campos que
 * ele não listava — participação de minoritários, resultado de equivalência,
 * data de recebimento, tesouraria e ativo total — saem vazios, e ficam assim
 * para reproduzir as medições.
 */
function withMarket(
  snaps: readonly FundamentalsSnapshot[],
  current: (s: FundamentalsSnapshot) => number | null,
  value: (s: FundamentalsSnapshot) => number | null,
): FundamentalsSnapshot[] {
  return snaps.map(
    (s) =>
      new FundamentalsSnapshot({
        ticker: s.ticker,
        fiscalPeriodEnd: s.fiscalPeriodEnd,
        totalRevenue: s.totalRevenue,
        ebit: s.ebit,
        ebitda: s.ebitda,
        netIncome: s.netIncome,
        incomeBeforeTax: s.incomeBeforeTax,
        incomeTaxExpense: s.incomeTaxExpense,
        interestExpense: s.interestExpense,
        earningsPerShare: s.earningsPerShare,
        nopat: s.nopat,
        cash: s.cash,
        shortTermInvestments: s.shortTermInvestments,
        shortTermDebt: s.shortTermDebt,
        longTermDebt: s.longTermDebt,
        totalStockholderEquity: s.totalStockholderEquity,
        bookValuePerShare: s.bookValuePerShare,
        propertyPlantEquipment: s.propertyPlantEquipment,
        intangibleAssets: s.intangibleAssets,
        totalCurrentAssets: s.totalCurrentAssets,
        currentLiabilities: s.currentLiabilities,
        realizedShareCapital: s.realizedShareCapital,
        profitReserves: s.profitReserves,
        operatingCashFlow: s.operatingCashFlow,
        investmentCashFlow: s.investmentCashFlow,
        freeCashFlow: s.freeCashFlow,
        // A contagem corrente da fonte sai: ela é de hoje, e na coorte não
        // existia.
        sharesOutstanding: current(s),
        sharesOutstandingAsOf: s.sharesOutstandingAsOf,
        marketCap: value(s),
        enterpriseToEbitda: null,
      }),
  );
}

function priceAt(s: PriceSeries, date: DateTime): number | null {
  let last: number | null = null;
  for (const p of s.points) {
    if (p.date.isAfter(date)) break;
    last = p.close;
  }
  return last;
}

function adjustedAt(s: PriceSeries, date: DateTime): number | null {
  let last: number | null = null;
  for (const p of s.points) {
    if (p.date.isAfter(date)) break;
    last = p.adjustedClose ?? p.close;
  }
  return last;
}

/**
 * Contagem por data e divisão entre espécies de cada listada, gravadas por
 * `tool/b3-delisted-count.ts` (item C3), com a conferência contra o salto do
 * preço (item B43, decisão 143).
 */
class ListedCount {
  private checkedResult: { accepted: AcceptedCount[]; discarded: DiscardedCount[] } | null = null;

  constructor(
    readonly raw: CountEntry[],
    readonly classes: CapitalClasses,
  ) {}

  /**
   * A contagem conferida contra o salto do preço dos [securities] da
   * companhia, com âncora na mais recente até [until]. A primeira chamada fixa
   * o resultado: os papéis de uma companhia são os mesmos em toda coorte.
   */
  checked(securities: Iterable<readonly TradingDay[]>, until: DateTime): { accepted: AcceptedCount[]; discarded: DiscardedCount[] } {
    this.checkedResult ??= checkCount(this.raw, securities, until);
    return this.checkedResult;
  }

  static read(): Map<string, ListedCount> | null {
    const path = 'data/b3/listadas_contagem.json';
    if (!existsSync(path)) return null;
    const out = new Map<string, ListedCount>();
    const json = readJson<Record<string, { contagem: { desde: string; acoes: number; fonte?: string | null }[]; classes?: unknown[] | null }>>(path);
    for (const [key, v] of Object.entries(json)) {
      out.set(
        key,
        new ListedCount(
          v.contagem.map((p) => ({
            since: DateTime.parse(`${p.desde}T00:00:00Z`),
            shares: Number(p.acoes),
            source: p.fonte ?? null,
          })),
          CapitalClasses.fromJson(v.classes ?? null),
        ),
      );
    }
    return out;
  }
}

/**
 * A data `meses` depois de [t], no mesmo dia — ou no último dia do mês, quando
 * ele não existe: 31/03 mais três meses é 30/06, e não 01/07.
 */
function addMonths(t: DateTime, months: number): DateTime {
  const total = t.month - 1 + months;
  const year = t.year + Math.floor(total / 12);
  const month = (total % 12) + 1;
  const lastDay = DateTime.local(year, month + 1, 0).day;
  return DateTime.local(year, month, t.day > lastDay ? lastDay : t.day);
}

const day = (d: DateTime): string => d.toIso8601String().slice(0, 10);

/**
 * Arredonda os números a seis algarismos significativos, para que a saída
 * trimestral caiba no repositório; nenhuma medição usa mais que isso.
 *
 * O Dart só arredondava `double`. Aqui todo número passa, e o efeito é o
 * mesmo: os inteiros da linha — contagens de eventos, janela do beta — ficam
 * muito abaixo de um milhão, onde seis algarismos não mudam nada.
 */
function compact(v: unknown): unknown {
  if (typeof v === 'number') {
    // Zero passa pelo mesmo caminho: `toStringAsPrecision` o devolve zero.
    if (!Number.isFinite(v)) return v;
    return Number(toStringAsPrecision(v, 6));
  }
  if (Array.isArray(v)) return v.map(compact);
  if (v !== null && typeof v === 'object') {
    return Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, compact(x)]));
  }
  return v;
}

/** Primeira coorte da réplica fora da amostra (decisão 129). */
export const firstC7Cohort = DateTime.local(2025, 12, 31);

/**
 * As coortes do C7: o último dia de cada trimestre, de 31/12/2025 até o
 * último que o fim dos dados cobre.
 */
export function c7Cohorts(dataEnd: DateTime): DateTime[] {
  const out: DateTime[] = [];
  for (let d = firstC7Cohort; !d.isAfter(dataEnd); d = DateTime.local(d.year, d.month + 4, 0)) out.push(d);
  return out;
}

/** Os mesmos campos de uma observação, na ordem em que o arquivo os grava. */
type Row = Record<string, unknown>;

export async function main(args: string[]): Promise<void> {
  const argAfter = (flag: string): string | null => {
    const i = args.indexOf(flag);
    return i >= 0 ? (args[i + 1] ?? null) : null;
  };
  const assemblyIndex = args.indexOf('--montagem');
  const app = assemblyIndex >= 0 && args[assemblyIndex + 1] === 'aplicativo';
  const withDelisted = args.includes('--com-deslistadas');
  const quarterly = args.includes('--trimestral');
  const counterfactualBase = args.includes('--contrafactual-base');
  const sampleArg = argAfter('--amostra');
  const sample = args.includes('--amostra') ? parseInt_(sampleArg ?? '') : null;
  // A medição do item B46: prêmios a mais no Ke das estatais.
  const stateOwnedPremiumArg = args.includes('--premio-estatal') ? (argAfter('--premio-estatal') ?? '') : null;
  const stateOwnedPremiums = stateOwnedPremiumArg === null ? [] : stateOwnedPremiumArg.split(',').map((x) => parseDouble(x));
  const stateOwnedOnly = args.includes('--so-estatais');
  const output = args.includes('--saida') ? argAfter('--saida') : null;
  // **A réplica fora da amostra** (item C7, decisões 129 e 133): as coortes a
  // partir de 31/12/2025, que nenhuma decisão do motor viu, na mesma montagem
  // da amostra do R3. Saem em `data/c7/coortes.json`, e quem as sela é
  // `tool/c7-seal.ts` — este modo não escreve nada versionado.
  const c7 = args.includes('--c7');
  // O fim dos dados é o da base restaurada; a leitura do C7, anos depois,
  // passa a data da base de então para que os retornos das coortes novas
  // existam.
  const endArg = args.includes('--fim-dos-dados') ? argAfter('--fim-dos-dados') : null;
  const dataEnd = endArg !== null ? DateTime.parse(endArg) : DateTime.local(2026, 9, 4);
  if ((withDelisted || quarterly || counterfactualBase) && !app) {
    errln('--com-deslistadas, --trimestral e --contrafactual-base exigem --montagem aplicativo');
    process.exit(2);
  }
  if (((stateOwnedPremiums.length > 0 || stateOwnedOnly) && !app) || (stateOwnedOnly && output === null)) {
    errln('--premio-estatal e --so-estatais exigem --montagem aplicativo, e --so-estatais exige --saida');
    process.exit(2);
  }
  if ((c7 && !(app && quarterly && withDelisted)) || (c7 && (counterfactualBase || sample !== null))) {
    errln('--c7 é a montagem da amostra do R3: exige --montagem aplicativo --com-deslistadas --trimestral, e nada mais');
    process.exit(2);
  }
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  const prices = new MemoPrices(ctx.prices);
  const fundamentals = new MemoFundamentals(ctx.fundamentals);
  const benchmark = new MemoBenchmark(ctx.benchmark);

  // Peças da montagem do aplicativo, lidas uma vez.
  const treasury = app ? readTreasury('data/tesouro/precotaxatesourodireto.csv') : null;
  const cvmDocs = app ? loadDocuments('data/cvm_exercicios.json', { withOldVersions: true }) : null;
  const registry = app ? B3RegistryCodec.decodePackage(readJson<JsonObject>('public/assets/b3/emissores.json')) : null;
  // **O prêmio de mercado de cada coorte** (decisão 142): a média de dez anos
  // do prêmio implícito, do pacote que o aplicativo lê. A série é medida
  // trimestre a trimestre, cada um com o dado da data dele, e a média de cada
  // coorte usa só os trimestres até ela.
  const premiumPackage = app ? ImpliedPremiumCodec.decode(readJson<JsonObject>('public/assets/mercado/premio_implicito.json')) : null;
  if (app && premiumPackage === null) {
    errln('sem public/assets/mercado/premio_implicito.json utilizável: rode npm run tool -- implied-premium --so-serie');
    process.exit(2);
  }
  // O controle acionário de cada emissor, do FCA (item B46): a ressalva da
  // montagem do aplicativo, na data de cada coorte, e a medição do item.
  const controlFile = 'public/assets/cvm/controle.json';
  const control = app && existsSync(controlFile) ? (ShareholderControlHistory.decode(readJson<JsonObject>(controlFile))?.byIssuer ?? null) : null;
  const stateOwnedAtDate = (x: Ticker, d: DateTime): boolean => {
    const p = control?.get(x.value.slice(0, 4));
    return p !== undefined && ShareholderControlHistory.at(p, d) === ShareholderControl.state;
  };

  const dividendsPackage = app ? CashDividendsCodec.decode(readJson<JsonObject>('public/assets/b3/proventos.json')) : null;
  const grants = app ? GrantsByDate.read() : null;
  if (app && grants === null) {
    errln('sem data/cvm/fre: rode python tool/cvm_baixar.py --docs FRE');
    process.exit(2);
  }
  if (app) {
    // O prazo lido na data de montagem do pacote tem de ser o do pacote.
    const pkg = ConcessionTermsCodec.decode(readJson<JsonObject>('public/assets/cvm/outorgas.json'));
    let equal = 0;
    for (const [key, term] of pkg) {
      const parsed = grants!.atDate(key, DateTime.local(2026, 9, 14));
      if (parsed !== null && parsed.end.equals(term.end)) equal++;
    }
    errln(`outorgas por data contra o pacote: ${equal} de ${pkg.size} iguais em 14/09/2026`);
  }
  const shareClass = (t: Ticker): B3Classification | null =>
    registry?.get(t.value.length >= 4 ? t.value.slice(0, 4) : '')?.classification ?? null;

  // A base da data das listadas (item C3): a ponte ticker → CNPJ, os códigos
  // que a FCA declara e a contagem por data do Formulário de Referência.
  const listedBridge = app
    ? new Map(Object.entries(readJson<{ ponte: Record<string, string> }>('docs/validacao/ponte_cvm.json').ponte))
    : new Map<string, string>();
  const fca = app ? FcaCodes.read() : null;
  const listedCounts = app ? ListedCount.read() : null;
  // Entradas descartadas pela conferência da contagem, por companhia (B43).
  const discardedByCnpj = new Map<string, number>();
  if (app && listedCounts === null) {
    errln('sem data/b3/listadas_contagem.json: rode npm run tool -- b3-delisted-count');
    process.exit(2);
  }

  // As deslistadas (item C1b), com o setor da B3 ou o representante do setor
  // da CVM, medido nas listadas.
  let delisted: Delisted | null = null;
  if (withDelisted) {
    const byCnpj = new Map<string, B3Classification>();
    for (const [ticker, cnpj] of listedBridge) {
      const c = registry!.get(ticker.length >= 4 ? ticker.slice(0, 4) : '')?.classification ?? null;
      if (c !== null) byCnpj.set(cnpj, c);
    }
    delisted = Delisted.read(byCnpj, dataEnd);
    if (delisted === null) {
      errln('sem data/b3/deslistadas_contagem.json: rode npm run tool -- b3-delisted-count');
      process.exit(2);
    }
    const origin = new Map<string, number>();
    for (const p of delisted.securities.values()) origin.set(p.sectorOrigin, (origin.get(p.sectorOrigin) ?? 0) + 1);
    const c = delisted.cvmSector?.agreement() ?? null;
    errln(
      `deslistadas: ${delisted.securities.size} papéis; setor ${dartString(origin)}; ` +
        `${delisted.discardedCounts} entradas da contagem descartadas pela conferência contra o preço (B43)`,
    );
    if (c !== null) {
      errln(
        `setor da CVM nas listadas, sem a companhia: ${c.listed} listadas, ${c.withoutReference} sem referência; ` +
          `Porta 1 ${c.financial}, ciclo ${c.cyclical}, concessão ${c.concession}, as três ${c.totalCount}`,
      );
    }
  }

  const cohorts: DateTime[] = [];
  if (c7) {
    cohorts.push(...c7Cohorts(dataEnd));
  } else if (quarterly) {
    for (let year = 2018; year <= 2025; year++) {
      for (const month of [3, 6, 9, 12]) if (!(year === 2025 && month > 9)) cohorts.push(DateTime.local(year, month + 1, 0));
    }
  } else {
    for (let year = 2018; year <= 2025; year++) cohorts.push(DateTime.local(year, 9, 30));
  }

  try {
    const wholeUniverse = (await fundamentals.universe()).unwrap();
    const universe = sample === null ? wholeUniverse : wholeUniverse.slice(0, sample);
    errln(`universo: ${universe.length} ativos, ${cohorts.length} coortes`);
    // Proventos da B3 e fechamento bruto do COTAHIST: o retorno total (A4) e,
    // na montagem do aplicativo, a base da data de cada papel e de cada
    // espécie da companhia (C3).
    const dividends = readDividends();
    // Os códigos de cada companhia: os tickers do universo ligados ao CNPJ, os
    // que a FCA declara e as espécies da raiz de cada um.
    const tickersOfCnpj = new Map<string, Set<string>>();
    for (const [ticker, cnpj] of listedBridge) {
      let set = tickersOfCnpj.get(cnpj);
      if (set === undefined) tickersOfCnpj.set(cnpj, (set = new Set()));
      set.add(ticker);
    }
    const tickerCodes = new Map<string, Set<string>>();
    for (const t of universe) {
      const cnpj = listedBridge.get(t.value);
      tickerCodes.set(
        t.value,
        companyCodes([
          t.value,
          ...(cnpj === undefined ? [] : (tickersOfCnpj.get(cnpj) ?? [])),
          ...(cnpj === undefined ? [] : (fca?.byCnpj.get(cnpj) ?? [])),
        ]),
      );
    }
    const allCodes = new Set<string>();
    for (const c of tickerCodes.values()) for (const x of c) allCodes.add(x);
    const raw = readRawCotahist(allCodes);
    // Pregões de cada código encadeados pelos códigos anteriores da companhia.
    const chained = new Map<string, TradingDay[]>();
    const rawOf = (code: string, ofCompany: Set<string>): TradingDay[] => {
      let s = chained.get(code);
      if (s === undefined) chained.set(code, (s = chain(code, ofCompany, raw)));
      return s;
    };

    // **Os eventos de ações e as emissões por valor** (itens B28, B29 e B30).
    // Os eventos corrigem a série da fonte onde ela não ajustou e a contagem
    // do FRE onde ela não absorveu; as emissões entram no patrimônio da ponte.
    const freIssuances = app ? FreIssuances.read() : null;
    const shareEvents = app ? ShareEvents.read({ issuances: freIssuances }) : null;
    if (app && freIssuances === null) {
      errln('sem data/cvm/fre: as emissões por valor ficam de fora — rode python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre');
    }
    const eventsOf = new Map<string, ShareEvent[]>();
    const securityEvents = (ticker: string): ShareEvent[] => {
      let e = eventsOf.get(ticker);
      if (e === undefined) {
        e = shareEvents!.ofSecurity({
          cnpj: listedBridge.get(ticker) ?? null,
          ticker,
          rawSessions: rawOf(ticker, tickerCodes.get(ticker) ?? new Set([ticker])),
        });
        eventsOf.set(ticker, e);
      }
      return e;
    };
    const completeSeries = new Map<string, PriceSeries>();
    const unadjustedOf = new Map<string, ShareEvent[]>();
    // As emissões por valor conhecidas na data: o quadro de aumentos do FRE,
    // até 2023, e a variação do capital integralizado que nenhum evento de
    // ações explica no preço, depois (item B28).
    const issuancesOf = (cnpj: string | null, t: DateTime, rawSessions: readonly TradingDay[], events: readonly ShareEvent[]): ShareIssue[] => {
      if (cnpj === null || freIssuances === null) return [];
      return [...freIssuances.known(cnpj, t), ...issuancesWithoutEvent(freIssuances.byCapitalChange(cnpj, t), rawSessions, events)];
    };

    const declaredEventsOf = new Map<string, ShareEvent[]>();

    const rows: Row[] = [];
    const listedTickers = new Set<string>();
    const withoutBase = new Map<string, number>();
    for (const t of cohorts) {
      const annual = t.month === 9;
      const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark, asOf: t })).getOrElse(MarketAnchors.fallback2026);
      const cohortCurve = app ? TreasuryCurve.at(treasury!, t) : null;
      if (app && cohortCurve === null) errln(`  ${day(t)}: sem curva do Tesouro na data`);
      const cohortPremium = premiumPackage?.normalizedAt(t) ?? null;
      if (app && cohortPremium === null) {
        errln(`  ${day(t)}: sem a média do prêmio implícito; vale o parametrizado de 5,5%`);
      }
      const premium = cohortPremium ?? CapmInputs.defaultMarketPremium;
      const premiumOrigin = cohortPremium === null ? MarketPremiumSource.parameterized : MarketPremiumSource.impliedNormalized;

      let evaluated = 0;
      let evaluatedDelisted = 0;
      const valueByCnpj = new Map<string, MarketValue | null>();

      // **O prior transversal do beta da coorte** (item B11). Sem ele não há
      // beta desalavancado, e a montagem padrão media um motor — beta cru e
      // WACC estático — que não é o que as decisões 40 a 46 descrevem. É
      // resolvido **na data da coorte**, sobre o universo listado dela: um
      // prior de hoje seria conhecimento futuro.
      const cohortPrior = app
        ? await ResolveBetaPrior.call({
            tickers: universe,
            prices,
            fundamentals,
            benchmark,
            asOf: t,
            dividendsFor: (x) => dividendsOf(dividends, x.value),
          })
        : null;
      if (app && cohortPrior === null) errln(`  ${day(t)}: sem prior do beta`);

      // A medição de uma observação, para listada e deslistada: o que muda
      // entre as duas é de onde vêm o preço, os fundamentos e os proventos.
      const observe = async (o: {
        ticker: Ticker;
        series: PriceSeries;
        p0: number;
        priceAtDate: number;
        source: FundamentalsRepository;
        anchoredSource: FundamentalsRepository | null;
        prices: PriceRepository;
        securityRaw: readonly TradingDay[] | null;
        securityDividendsList: readonly CashDividend[];
        betaDividends: readonly CashDividend[] | null;
        contractEnd: DateTime | null;
        officialCount: OfficialShareCount | null;
        sharesInUnit: number | null;
        onEvaluated: () => void;
        invalidWindow?: ((from: DateTime, until: DateTime) => boolean) | null;
        extras?: Row;
        counterfactual?: (() => Promise<Row>) | null;
        issuances?: readonly ShareIssue[];
      }): Promise<void> => {
        const { ticker, series, p0, securityRaw } = o;
        const invalidWindow = o.invalidWindow ?? null;
        const prepare = (marketPremium: number): Promise<Result<ValuationInputs>> =>
          PrepareValuationInputs.call({
            ticker,
            prices: o.prices,
            fundamentals: o.source,
            benchmark,
            riskFreeRate: anchors.currentRiskFreeRate,
            asOf: t,
            marketPremium,
            premiumSource: premiumOrigin,
            perpetualGrowthCap: anchors.nominalEconomyGrowth,
            inflation: anchors.inflationCagr,
            terminalRiskFreeRate: anchors.riskFreeCagr,
            projectionYears: 10,
            riskFreeCurve: cohortCurve,
            officialShares: o.officialCount,
            concessionEnd: o.contractEnd,
            dividends: o.betaDividends,
            betaPrior: cohortPrior,
            declaredSharesPerUnit: o.sharesInUnit,
            // As emissões por valor do FRE conhecidas na data (item B28).
            shareIssues: o.issuances ?? [],
            // O controle estatal na data: só a ressalva (item B46).
            stateControlled: stateOwnedAtDate(ticker, t),
          });
        const prep = await prepare(premium);
        if (prep.isErr) return;
        const inputs = prep.unwrap();

        const r = ValuationCascade.evaluate(inputs);
        const upside = r.isOk ? r.unwrap().upside : null;
        if (upside !== null) o.onEvaluated();

        // **O prêmio a mais das estatais** (item B46). Soma-se ao prêmio de
        // mercado na proporção do beta — `β × (prêmio + x ÷ β) = β × prêmio +
        // x` —, o que é exato no Ke de hoje; no caminho realavancado, o
        // acréscimo anda com `β_t ÷ β`.
        const withStateOwnedPremium: Record<string, number | null> = {};
        // Beta perto de zero faria `x ÷ β` explodir: a observação fica sem a
        // variante, e não com um prêmio infinito.
        if (stateOwnedPremiums.length > 0 && stateOwnedAtDate(ticker, t) && Math.abs(inputs.capm.beta) > 0.01) {
          for (const x of stateOwnedPremiums) {
            const other = await prepare(premium + x / inputs.capm.beta);
            const otherResult = other.isErr ? null : ValuationCascade.evaluate(other.unwrap());
            withStateOwnedPremium[str(x)] = otherResult?.valueOrNull?.upside ?? null;
          }
        }

        // Banda de Monte Carlo com os sorteios do aplicativo — só nas coortes
        // de 30/09, as que o C2 mediu —, e o potencial do recusado sem o corte
        // de liquidez.
        let quantiles: number[] | null = null;
        if (app && annual && r.isOk) {
          const mc = ValuationCascade.evaluate(inputs, {
            scenarioBuilder: (base) => StochasticScenarios.around(base),
            monteCarloSamples: draws,
          });
          const dist = mc.isOk ? mc.unwrap().distribution : null;
          if (dist !== null && !dist.isEmpty) {
            quantiles = [];
            for (let q = 0; q <= 100; q++) quantiles.push(dist.percentile(q / 100));
          }
        }
        const scenarios = r.isOk ? r.unwrap().discreteScenarios : null;
        let withoutLiquidity: number | null = null;
        if (app && r.isErr) {
          const counter = ValuationCascade.evaluate(inputs.withoutPrices());
          if (counter.isOk) withoutLiquidity = counter.unwrap().upside;
        }
        const windowSeries = inputs.prices;
        const liquidity = windowSeries === null ? null : EligibilityGate.medianTradedValue(windowSeries);
        // Fração dos últimos pregões da janela de liquidez sem negócio.
        let withoutTrading: number | null = null;
        if (windowSeries !== null && windowSeries.points.length >= 20) {
          const pts = windowSeries.points;
          const ini = pts.length > EligibilityGate.liquidityWindowDays ? pts.length - EligibilityGate.liquidityWindowDays : 0;
          const window = pts.slice(ini);
          withoutTrading = window.filter((p) => (p.volume ?? 0) <= 0).length / window.length;
        }

        // Fatores ingênuos, sobre o mesmo exercício que o motor usou — na
        // montagem do aplicativo, a série mesclada com a CVM.
        const view = new PointInTimeView(t);
        const factors = (fundamentalsSeries: readonly FundamentalsSnapshot[]) => {
          const pub = view.published(fundamentalsSeries);
          const last = pub.length === 0 ? null : pub[pub.length - 1]!;
          const pl = last?.equityBookValue ?? null;
          const marketValue = last?.marketCap ?? null;
          const netIncome = last?.netIncome ?? null;
          return {
            bm: pl !== null && marketValue !== null && marketValue > 0 ? pl / marketValue : null,
            ey: netIncome !== null && marketValue !== null && marketValue > 0 ? netIncome / marketValue : null,
            last,
          };
        };

        const naiveFactors = factors(inputs.fundamentals);
        const pub = view.published(inputs.fundamentals);

        // A ponte por papel como o motor a faz, pelas funções públicas dele
        // (item C3): a razão de unidade e a origem do divisor.
        let unitRatio: number | null = null;
        let divisor: QuotedShares | null = null;
        const last = naiveFactors.last;
        if (app && last !== null) {
          unitRatio = ValuationCascade.quotedUnitRatio({
            sharesOutstanding: last.sharesOutstanding,
            marketCap: last.marketCap,
            marketPrice: inputs.marketPrice,
          });
          divisor = ValuationCascade.quotedShares({
            latest: last,
            marketPrice: inputs.marketPrice,
            sharesPerQuote: unitRatio,
            published: pub,
            official: inputs.officialShares,
            asOf: t,
          });
        }

        // A série ancorada no trimestre, sobre os mesmos insumos (item C1c).
        let anchored: Row = {};
        if (o.anchoredSource !== null) {
          const h = await o.anchoredSource.history(ticker);
          if (h.isOk) {
            const anchoredSeries = h.unwrap();
            // **Pela cópia do núcleo** (item B27): a versão à mão perdia a
            // composição declarada da unit, a taxa de referência do crédito e
            // a janela do beta, e a leitura ancorada saía com outro divisor
            // nas units.
            const anchoredResult = ValuationCascade.evaluate(inputs.withFundamentals(anchoredSeries));
            const anchoredFactors = factors(anchoredSeries);
            const pubA = view.published(anchoredSeries);
            anchored = {
              upsideAncorada: anchoredResult.isOk ? anchoredResult.unwrap().upside : null,
              justoAncorada: anchoredResult.isOk ? anchoredResult.unwrap().fairValue.reais : null,
              recusaAncorada: anchoredResult.isOk ? null : (anchoredResult.failureOrNull?.message ?? null),
              fimDoExercicioAncorada: pubA.length === 0 ? null : day(pubA[pubA.length - 1]!.fiscalPeriodEnd),
              bookToMarketAncorada: anchoredFactors.bm,
              earningsYieldAncorada: anchoredFactors.ey,
            };
          }
        }

        const returnRate = (months: number, adjusted = false): number | null => {
          const d = addMonths(t, months);
          if (d.isAfter(dataEnd)) return null;
          if (invalidWindow !== null && invalidWindow(t, d)) return null;
          const priceStart = adjusted ? adjustedAt(series, t) : p0;
          const priceEnd = adjusted ? adjustedAt(series, d) : priceAt(series, d);
          if (priceStart === null || priceEnd === null || priceStart <= 0) return null;
          return priceEnd / priceStart - 1;
        };

        // Retorno de preço vezes o reinvestimento dos proventos da classe no
        // fechamento bruto da data ex. Sem COTAHIST do papel, não há total.
        const total = (months: number): number | null => {
          const price = returnRate(months);
          if (price === null || securityRaw === null) return null;
          const f = reinvestmentFactor(o.securityDividendsList, t, addMonths(t, months), securityRaw);
          return (1 + price) * f - 1;
        };

        // O mesmo retorno total **começando um mês depois** da coorte (C0). O
        // sinal escalado pelo preço — B/M, potencial — divide pelo mesmo
        // fechamento em que o retorno começa, e em papel ilíquido esse
        // fechamento é ruído: quem saiu barato por acaso volta, e qualquer
        // sinal que dependa do preço "prevê" a volta. Pular o mês separa a
        // reversão do fechamento do que o sinal sabe.
        const totalSkippingOneMonth = (months: number): number | null => {
          if (securityRaw === null) return null;
          const from = addMonths(t, 1);
          const until = addMonths(t, months);
          if (until.isAfter(dataEnd)) return null;
          if (invalidWindow !== null && invalidWindow(t, until)) return null;
          const priceStart = priceAt(series, from);
          const priceEnd = priceAt(series, until);
          if (priceStart === null || priceEnd === null || priceStart <= 0) return null;
          const f = reinvestmentFactor(o.securityDividendsList, from, until, securityRaw);
          return (priceEnd / priceStart) * f - 1;
        };

        // Roteamento, para separar quem chegou ao acionista por qual porta.
        // A Porta 1 é setorial; a Porta 3 é o fluxo da firma não sustentado.
        const sector = inputs.sectorKey;
        const gate1 = FinancialSectors.isFinancial({ sectorKey: sector, industry: inputs.industry });
        const sustained = GrowthGuards.firmFlowIsSustained(pub);

        const result = r.valueOrNull;
        const row: Row = {
          coorte: app ? day(t) : t.year,
          ticker: ticker.value,
          ...(o.extras ?? {}),
          preco: o.priceAtDate,
          upside,
        };
        if (Object.keys(withStateOwnedPremium).length > 0) row['potencialComPremioEstatal'] = withStateOwnedPremium;
        Object.assign(row, {
          setor: sector,
          porta1: gate1,
          fluxoSustentado: sustained,
          porta3: !gate1 && !sustained,
          ressalvas: result === null ? null : result.diagnostics!.caveats.map((c) => c.key),
          pesoTerminal: result === null ? null : result.diagnostics!.terminalShare,
          modelo: result === null ? null : result.model.name,
          recusa: result !== null ? null : (r.failureOrNull?.message ?? null),
          bookToMarket: naiveFactors.bm,
          earningsYield: naiveFactors.ey,
          // **Os ingredientes do múltiplo de pares** (item B22, decisão 123).
          // `bookToMarket` é `1 ÷ (P/VP)` e `earningsYield` é `1 ÷ (P/L)`:
          // dois dos três já estavam aqui, e faltava a firma sobre EBITDA.
          //
          // **A mediana é de quem calcula, e não daqui**: ela tem de sair da
          // seção transversal **da própria coorte**, ou o sinal carrega o
          // múltiplo de 2026 numa observação de 2018 — conhecimento futuro
          // pela porta da frente. Por isso o que a coorte grava é o
          // ingrediente, e `conditional-regression.ts` monta a mediana.
          firmaSobreEbitda: (() => {
            const u = naiveFactors.last;
            const marketValue = u?.marketCap ?? null;
            const ebitda = u?.ebitda ?? null;
            if (u === null || marketValue === null || marketValue <= 0) return null;
            if (ebitda === null || ebitda <= 0) return null;
            return (marketValue + u.netDebt) / ebitda;
          })(),
          ebitda: naiveFactors.last?.ebitda ?? null,
          dividaLiquida: naiveFactors.last?.netDebt ?? null,
          lucro: naiveFactors.last?.netIncome ?? null,
          patrimonio: naiveFactors.last?.equityBookValue ?? null,
          valorDeMercado: naiveFactors.last?.marketCap ?? null,
          ret12: returnRate(12),
          ret36: returnRate(36),
          ret12aj: returnRate(12, true),
          ret36aj: returnRate(36, true),
          ret12tot: total(12),
          ret36tot: total(36),
        });
        if (app) {
          Object.assign(row, {
            justo: result === null ? null : result.fairValue.reais,
            pessimista: scenarios === null ? null : (scenarios.get(ScenarioBand.bear)?.reais ?? null),
            otimista: scenarios === null ? null : (scenarios.get(ScenarioBand.bull)?.reais ?? null),
            ke: result === null ? null : result.diagnostics!.costOfEquity,
            premioDeMercado: inputs.capm.marketPremium,
            mcQuantis: quantiles,
            // A janela que a série de fato deu ao beta (item B17): a fonte
            // devolve dez anos, e a coorte de 2018 pede cinco que ela não
            // tem. Sem isto, a janela curta entrava sem aparecer.
            janelaDoBeta: inputs.betaWindowYears,
            liquidez: liquidity,
            upsideSemLiquidez: withoutLiquidity,
            semNegocio: withoutTrading,
            // A escala da forma do C2b, pela mesma função que o aplicativo
            // usa sobre a mesma janela (`cobertura_banda.md` §9).
            volatilidade: windowSeries === null ? null : CalibratedBand.trailingVolatility(windowSeries),
            ret12totPulo: totalSkippingOneMonth(12),
            ret36totPulo: totalSkippingOneMonth(36),
            fimDoContrato: inputs.concessionEnd === null ? null : inputs.concessionEnd.toIso8601String().slice(0, 10),
            fimDoExercicio: pub.length === 0 ? null : day(pub[pub.length - 1]!.fiscalPeriodEnd),
            acoesNaData: o.officialCount?.total ?? null,
            // O capital emitido depois do balanço que entrou na ponte (B28).
            capitalPosterior: result === null ? null : (result.diagnostics?.postStatementCapital ?? null),
            valorDeMercado: last?.marketCap ?? null,
            razaoDeUnidade: unitRatio,
            origemDoDivisor: divisor?.source.name ?? null,
            divisorDiverge: divisor?.diverge ?? null,
            ...anchored,
          });
          if (o.counterfactual) Object.assign(row, await o.counterfactual());
        }
        rows.push(row);
      };

      const listedCnpjsAtDate = new Set<string>();
      const tickersAtDate = new Set<string>();
      let i = 0;
      for (const ticker of universe) {
        i++;
        if (i % 50 === 0) process.stderr.write(`  ${day(t)}: ${i}/${universe.length}   \r`);
        if (stateOwnedOnly && !stateOwnedAtDate(ticker, t)) continue;

        const seriesResult = await prices.daily(ticker, new DateRange(DateTime.local(2010, 1, 1), dataEnd));
        if (seriesResult.isErr) continue;
        // **O ajuste que a fonte deixou de fazer** (item B29): a bonificação
        // que ela não ajustou é uma queda que não aconteceu, e entrava no
        // retorno de toda janela que a atravessa, no beta e na volatilidade.
        // O fator entre o bruto e a fonte diz, sem ruído, quais ficaram assim.
        const sourceSeries = seriesResult.unwrap();
        let series = sourceSeries;
        if (app) {
          let complete = completeSeries.get(ticker.value);
          if (complete === undefined) {
            const without = notAdjustedBySource(
              sourceSeries,
              rawOf(ticker.value, tickerCodes.get(ticker.value) ?? new Set([ticker.value])),
              securityEvents(ticker.value),
            );
            unadjustedOf.set(ticker.value, without);
            complete = CorporateEvents.applyToSeries(sourceSeries, without);
            completeSeries.set(ticker.value, complete);
          }
          series = complete;
        }
        const p0 = priceAt(series, t);
        if (p0 === null || p0 <= 0) continue;

        const historyResult = await fundamentals.history(ticker);
        if (historyResult.isErr) continue;

        if (!app) {
          const hist = rescale(historyResult.unwrap(), p0);
          await observe({
            ticker,
            series,
            p0,
            priceAtDate: p0,
            source: new ScaledFundamentals(fundamentals, hist),
            anchoredSource: null,
            prices,
            securityRaw: raw.get(ticker.value) ?? null,
            securityDividendsList: dividendsOf(dividends, ticker.value),
            betaDividends: null,
            contractEnd: null,
            officialCount: null,
            // A montagem antiga não passa pela FCA, e a razão de unidade dela
            // continua sendo a medida — é o ponto de comparação.
            sharesInUnit: null,
            onEvaluated: () => evaluated++,
          });
          continue;
        }

        // A base da data (item C3). Sem pregão do papel no COTAHIST até dez
        // dias antes, não há preço da data, e a observação sai.
        const ofCompany = tickerCodes.get(ticker.value) ?? new Set([ticker.value]);
        const rawSessions = rawOf(ticker.value, ofCompany);
        const base = baseFactorOf({ source: series, rawSessions, date: t });
        if (base === null) {
          withoutBase.set(day(t), (withoutBase.get(day(t)) ?? 0) + 1);
          continue;
        }
        const rawPrice = base.tradingDay.close;
        const seriesAtDate = seriesOnDateBasis(series, rawSessions, base.factor);
        const cnpj = listedBridge.get(ticker.value) ?? null;
        const count = cnpj === null ? null : (listedCounts!.get(cnpj) ?? null);
        const companySecurities = new Map<string, TradingDay[]>();
        for (const c of ofCompany) {
          const kind = kindOf(c);
          if (kind === 'common' || kind === 'preferred') companySecurities.set(c, rawOf(c, ofCompany));
        }
        // A contagem do FRE conferida contra o salto do preço (B43): a
        // correção que repete a contagem de antes de um grupamento sai, e o
        // grupamento que só a correção registrou passa a valer no dia do
        // salto.
        const checked = count?.checked(companySecurities.values(), dataEnd) ?? null;
        if (cnpj !== null && checked !== null) discardedByCnpj.set(cnpj, checked.discarded.length);
        // A contagem com o evento que o FRE ainda não absorveu (B30): o quadro
        // de eventos parou em 2022, e o desdobramento de 2024 do BB só entrou
        // no formulário em 2025.
        const withEvents = checked === null ? null : sharesWithEvents(checked.accepted, t, securityEvents(ticker.value));
        const shares = withEvents?.shares ?? null;
        let value: MarketValue | null = null;
        if (cnpj !== null && shares !== null) {
          if (!valueByCnpj.has(cnpj)) {
            valueByCnpj.set(
              cnpj,
              MarketValue.atDate({ shares, commonFraction: count!.classes.at(t), securities: companySecurities, date: t }),
            );
          }
          value = valueByCnpj.get(cnpj) ?? null;
        }
        const hist = rescaleAtDate(historyResult.unwrap(), {
          sharesAtDate: shares,
          marketValueOf: value?.value ?? null,
          rawPrice,
        });
        const docs = cvmDocs!.get(ticker.value) ?? null;
        const sourceOf = (anchored: boolean): FundamentalsRepository =>
          new OfficialSectorFundamentalsRepository({
            inner: new CvmAtDate(fundamentals, hist, docs, t, anchored),
            classification: async (x) => shareClass(x),
          });
        const betaDividends = CashDividendsCodec.forTicker(dividendsPackage!, ticker.value);
        const contractEnd = grants!.atDate(ticker.value, t)?.end ?? null;

        // O contrafactual da base (item C3): a montagem da rodada anterior —
        // preço e volume da fonte, contagem do exercício, sem contagem
        // oficial — sobre o mesmo ativo e a mesma data, só nas coortes de
        // 30/09.
        const counterfactual = async (): Promise<Row> => {
          const oldSeries = rescale(historyResult.unwrap(), p0);
          const prep = await PrepareValuationInputs.call({
            ticker,
            prices,
            fundamentals: new OfficialSectorFundamentalsRepository({
              inner: new CvmAtDate(fundamentals, oldSeries, docs, t),
              classification: async (x) => shareClass(x),
            }),
            benchmark,
            riskFreeRate: anchors.currentRiskFreeRate,
            asOf: t,
            marketPremium: premium,
            premiumSource: premiumOrigin,
            perpetualGrowthCap: anchors.nominalEconomyGrowth,
            inflation: anchors.inflationCagr,
            terminalRiskFreeRate: anchors.riskFreeCagr,
            projectionYears: 10,
            riskFreeCurve: cohortCurve,
            concessionEnd: contractEnd,
            dividends: betaDividends,
          });
          if (prep.isErr) return { recusaBaseAntiga: 'sem insumos' };
          const ins = prep.unwrap();
          const cr = ValuationCascade.evaluate(ins);
          const pubOld = new PointInTimeView(t).published(ins.fundamentals);
          const u = pubOld.length === 0 ? null : pubOld[pubOld.length - 1]!;
          const pl = u?.equityBookValue ?? null;
          const marketValue = u?.marketCap ?? null;
          return {
            upsideBaseAntiga: cr.isOk ? cr.unwrap().upside : null,
            recusaBaseAntiga: cr.isOk ? null : (cr.failureOrNull?.message ?? null),
            bookToMarketBaseAntiga: pl !== null && marketValue !== null && marketValue > 0 ? pl / marketValue : null,
            liquidezBaseAntiga: ins.prices === null ? null : EligibilityGate.medianTradedValue(ins.prices),
          };
        };

        listedTickers.add(ticker.value);
        tickersAtDate.add(ticker.value);
        if (cnpj !== null) listedCnpjsAtDate.add(cnpj);
        let declared = declaredEventsOf.get(ticker.value);
        if (declared === undefined) {
          declared = shareEvents!.ofSecurity({ cnpj, ticker: ticker.value, rawSessions, withCount: false });
          declaredEventsOf.set(ticker.value, declared);
        }
        const extras: Row = {};
        if (delisted !== null) extras['deslistada'] = false;
        extras['fatorDeBase'] = base.factor;
        // Os eventos que a fonte não ajustou e foram ajustados (B29), e se a
        // contagem da data recebeu evento que o FRE não tinha (B30).
        extras['eventosSemAjusteNaFonte'] = unadjustedOf.get(ticker.value)?.length ?? 0;
        if (withEvents !== null && withEvents.applied.length > 0) {
          extras['contagemComEvento'] = withEvents.applied.map((e) => `${day(e.exDate)}×${str(e.factor)}`);
        }
        // O pregão da data veio de um código anterior da companhia.
        if (!(raw.get(ticker.value)?.includes(base.tradingDay) ?? false)) extras['pregaoDeOutroCodigo'] = true;
        extras['origemDoValorDeMercado'] = value?.origin ?? (shares === null ? 'contagemDoExercicio' : 'semPregaoDeEspecie');
        await observe({
          ticker,
          series,
          p0,
          priceAtDate: rawPrice,
          source: sourceOf(false),
          anchoredSource: quarterly ? sourceOf(true) : null,
          prices: new FixedSeries(seriesAtDate),
          securityRaw: rawSessions,
          securityDividendsList: dividendsOf(dividends, ticker.value),
          betaDividends,
          contractEnd,
          officialCount: shares === null ? null : new OfficialShareCount({ total: shares, asOf: t }),
          // A composição declarada da unit na FCA vigente na data (item B16).
          sharesInUnit: cnpj === null ? null : (UnitCompositionCodec.at(fca?.unitsByCnpj.get(cnpj) ?? [], t)?.shares ?? null),
          onEvaluated: () => evaluated++,
          issuances: issuancesOf(cnpj, t, rawSessions, declared),
          extras,
          counterfactual: counterfactualBase && annual ? counterfactual : null,
        });
      }

      // As deslistadas da ponte (item C1b): só o papel que negociava na data,
      // e sem evento declarado e não localizado, nem salto que a série
      // ajustada não explica, na janela do beta — ela não estaria ajustada
      // por eles. No horizonte do retorno, a janela que os atravessa fica sem
      // retorno. O papel que já entrou como listado nesta coorte não entra de
      // novo.
      let excludedByEvent = 0;
      let delistedAtDate = 0;
      let repeated = 0;
      const delistedSecurities: DelistedSecurity[] = delisted === null ? [] : [...delisted.securities.values()];
      const toVisit = stateOwnedOnly ? [] : sample === null ? delistedSecurities : delistedSecurities.slice(0, sample);
      for (const security of toVisit) {
        const tradingDay = tradingDayUntil(security.tradingDays, t, sessionMargin);
        if (tradingDay === null || tradingDay.close <= 0) continue;
        if (tickersAtDate.has(security.ticker.value) || listedCnpjsAtDate.has(security.cnpj)) {
          repeated++;
          continue;
        }
        delistedAtDate++;
        if (security.suspiciousWindow(DateTime.utc(t.year - 5, t.month, t.day), t)) {
          excludedByEvent++;
          continue;
        }
        const finalSeries = security.series(new DateRange(DateTime.local(2010, 1, 1), dataEnd), dataEnd);
        const p0 = priceAt(finalSeries, t);
        if (p0 === null || p0 <= 0) continue;
        const value = delisted!.marketValueOf(security, t);
        const shares = security.sharesAt(t);
        const docs = delisted!.documents.get(security.ticker.value) ?? [];
        await observe({
          ticker: security.ticker,
          series: finalSeries,
          p0,
          priceAtDate: tradingDay.close,
          source: new DelistedFundamentals(security, docs, t, tradingDay.close, { marketValueOf: value?.value ?? null }),
          anchoredSource: quarterly
            ? new DelistedFundamentals(security, docs, t, tradingDay.close, { marketValueOf: value?.value ?? null, anchored: true })
            : null,
          prices: new DelistedPrices(security, t),
          securityRaw: security.tradingDays,
          securityDividendsList: security.dividends,
          betaDividends: security.dividends,
          contractEnd: grants!.atDateByCnpj(security.cnpj, t)?.end ?? null,
          officialCount: shares === null ? null : new OfficialShareCount({ total: shares, asOf: t }),
          sharesInUnit: UnitCompositionCodec.at(fca?.unitsByCnpj.get(security.cnpj) ?? [], t)?.shares ?? null,
          onEvaluated: () => evaluatedDelisted++,
          invalidWindow: (from, until) => security.suspiciousWindow(from, until),
          issuances: issuancesOf(security.cnpj, t, security.tradingDays, security.events),
          extras: {
            deslistada: true,
            cnpj: security.cnpj,
            origemDoSetor: security.sectorOrigin,
            origemDoValorDeMercado: value?.origin ?? 'contagemVezesPreco',
          },
        });
      }
      if (delisted !== null) {
        errln(
          `  ${day(t)}: deslistadas negociando ${delistedAtDate}, ${excludedByEvent} fora por evento não localizado ou salto, ` +
            `${repeated} já listadas, ${evaluatedDelisted} avaliadas`,
        );
      }
      errln(
        `  ${day(t)}: ${evaluated} avaliados de ${universe.length}` +
          `${app ? `, ${withoutBase.get(day(t)) ?? 0} sem pregão na data` : ''}` +
          `   (rf=${toStringAsFixed(anchors.currentRiskFreeRate * 100, 2)}%, ` +
          `rf_inf=${toStringAsFixed(anchors.riskFreeCagr * 100, 2)}%, ` +
          `prêmio=${toStringAsFixed(premium * 100, 2)}%)`,
      );
    }
    if (discardedByCnpj.size > 0) {
      const withDiscard = [...discardedByCnpj.values()].filter((n) => n > 0);
      errln(
        `contagem conferida contra o preço (B43): ${withDiscard.length} de ${discardedByCnpj.size} listadas com ` +
          `${withDiscard.reduce((a, b) => a + b, 0)} entradas descartadas`,
      );
    }

    const destination =
      output ??
      (c7
        ? 'data/c7/coortes.json'
        : sample !== null
          ? 'docs/validacao/backtest_amostra.json'
          : !app
            ? 'docs/validacao/backtest_valuation.json'
            : quarterly
              ? 'docs/validacao/backtest_trimestral.json'
              : withDelisted
                ? 'docs/validacao/backtest_aplicativo_deslistadas.json'
                : 'docs/validacao/backtest_aplicativo.json');
    writeText(destination, app ? JSON.stringify(compact(rows)) : jsonPretty(rows, ' '));
    errln(`escrito ${destination} (${rows.length} observações)`);
    if (app && quarterly && withDelisted && sample === null && !c7 && output === null) {
      // O universo que as coortes observam como listado: é o que a ponte das
      // deslistadas (`tool/b3_ponte.py`) exclui, para não dar duas pontas à
      // mesma companhia (item C1d).
      writeText(
        'docs/validacao/universo_coortes.json',
        jsonPretty({ geradoPor: 'tool/backtest-valuation.ts', tickers: [...listedTickers].sort(compareStr) }, ' '),
      );
    }
  } finally {
    await ctx.dispose();
  }
}

/**
 * O fator de reinvestimento dos proventos entre [from] e [until], com o
 * fechamento bruto do primeiro pregão a até cinco dias da data ex.
 */
function reinvestmentFactor(dividends: readonly CashDividend[], from: DateTime, until: DateTime, securityRaw: readonly TradingDay[]): number {
  return TotalReturn.factor({
    dividends,
    from,
    until,
    closeOnExDate: (d) => tradingDayFrom(securityRaw, d, 5)?.close ?? null,
  }).factor;
}

/** Devolve o histórico já reescalado, mantendo o resto do repositório. */
class ScaledFundamentals implements FundamentalsRepository {
  constructor(
    readonly inner: FundamentalsRepository,
    readonly hist: FundamentalsSnapshot[],
  ) {}

  async history(_t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    return new Ok(this.hist);
  }

  profile(t: Ticker): Promise<Result<Asset>> {
    return this.inner.profile(t);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.inner.universe();
  }
}
