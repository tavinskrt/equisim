// As companhias deslistadas, prontas para entrar nas coortes (item C1b).
//
// Tudo o que o A3.4 deixou em `data/b3/deslistadas_contagem.json` — contagem de
// ações por data, eventos localizados no preço, eventos não localizados e
// proventos —, mais o fechamento e o volume do COTAHIST filtrados pelo ISIN do
// papel, os documentos da CVM pelo CNPJ e o setor: o da B3, quando o portal
// responde para a companhia, e o representante do setor de atividade da FCA
// (`cvm-sector.ts`) quando não responde.
//
// **Uma coorte vê só o que existia na data dela.** O preço é ajustado pelos
// eventos com data ex até o fim da janela pedida, e não pelos posteriores; a
// contagem é a vigente na data; a CVM é a recebida até ali.
import { existsSync } from 'node:fs';

import {
  Asset,
  B3CashDividends,
  B3Classification,
  CashDividend,
  CashDividendKind,
  CvmDocumentKind,
  type CvmPeriodDocument,
  CvmSeries,
  DateRange,
  DateTime,
  Duration,
  err,
  type FundamentalsRepository,
  FundamentalsSnapshot,
  InsufficientData,
  ok,
  PointInTimeView,
  type PriceRepository,
  PricePoint,
  PriceSeries,
  type Result,
  Sector,
  ShareEvent,
  Ticker,
} from '../../src/core';
import { readRawCotahist, type TradingDay } from '../b3/dividends';
import { loadDocuments } from '../cvm/documents';
import { CvmSector } from '../cvm/cvm-sector';
import { readJson } from '../lib/files';
import { CapitalClasses, MarketValue } from './as-of-base';
import { type AcceptedCount, checkCount } from './checked-count';

/** Um papel de companhia deslistada. */
export class DelistedSecurity {
  /**
   * Maior razão entre pregões vizinhos que a série ajustada ainda pode ter
   * sem ser tratada como evento que escapou.
   */
  static readonly maxJump = 3.0;

  /**
   * Distância máxima, em dias corridos, entre os dois pregões do salto: além
   * disso é suspensão, e o preço de volta é o que o papel passou a valer.
   */
  static readonly jumpDays = 90;

  readonly ticker: Ticker;
  readonly cnpj: string;
  readonly name: string;
  /** Pregões brutos do COTAHIST, com volume financeiro. */
  readonly tradingDays: readonly TradingDay[];
  /** Eventos localizados no preço e inferidos, um por data ex. */
  readonly events: readonly ShareEvent[];
  /** Aprovações de evento declarado com pregão e sem data ex no preço. */
  readonly notLocated: readonly DateTime[];
  /** Contagem total de ações, em ordem de vigência. */
  readonly count: readonly AcceptedCount[];
  /** Proventos da classe do papel. */
  readonly dividends: readonly CashDividend[];
  readonly classification: B3Classification | null;
  /** `b3`, `cvm` ou `nenhuma`. */
  readonly sectorOrigin: 'b3' | 'cvm' | 'nenhuma';
  /** Divisão do capital entre ordinárias e preferenciais (item C3). */
  readonly classes: CapitalClasses;

  constructor(args: {
    ticker: Ticker;
    cnpj: string;
    name: string;
    tradingDays: readonly TradingDay[];
    events: readonly ShareEvent[];
    notLocated: readonly DateTime[];
    count: readonly AcceptedCount[];
    dividends: readonly CashDividend[];
    classification: B3Classification | null;
    sectorOrigin: 'b3' | 'cvm' | 'nenhuma';
    classes: CapitalClasses;
  }) {
    this.ticker = args.ticker;
    this.cnpj = args.cnpj;
    this.name = args.name;
    this.tradingDays = args.tradingDays;
    this.events = args.events;
    this.notLocated = args.notLocated;
    this.count = args.count;
    this.dividends = args.dividends;
    this.classification = args.classification;
    this.sectorOrigin = args.sectorOrigin;
    this.classes = args.classes;
  }

  /** Contagem vigente em [date], ou `null` antes do primeiro ponto. */
  sharesAt(date: DateTime): number | null {
    const day = DateTime.utc(date.year, date.month, date.day);
    let last: number | null = null;
    for (const p of this.count) {
      if (p.since.isAfter(day)) break;
      last = p.shares;
    }
    return last;
  }

  /**
   * Série de preço na base de [until]: eventos com data ex depois dele não
   * ajustam, porque não tinham acontecido. O volume vira ações, para que
   * `fechamento × volume` continue sendo o financeiro do dia.
   */
  series(window: DateRange, until: DateTime): PriceSeries {
    const end = DateTime.utc(until.year, until.month, until.day);
    const eventsUntil = this.events.filter((e) => !e.exDate.isAfter(end));
    const points: PricePoint[] = [];
    for (const p of this.tradingDays) {
      if (!window.contains(p.date)) continue;
      let c = p.close;
      for (const e of eventsUntil) if (p.date.isBefore(e.exDate)) c /= e.factor;
      const fin = p.tradedValue;
      points.push(new PricePoint({ date: p.date, close: c, volume: fin === null || c <= 0 ? null : fin / c }));
    }
    return new PriceSeries({ ticker: this.ticker, points });
  }

  private jumpsMemo: DateTime[] | null = null;

  /**
   * Pregões em que a série **já ajustada** muda mais de [maxJump] vezes
   * em relação ao pregão anterior, a até [jumpDays] dias dele.
   *
   * São os eventos que o FRE não declarou e o preço não permitiu inferir —
   * o grupamento de 2024 da KRSA3 e da NGRD3, a TOYB3 dividida por 270 mil
   * em 2015 —, e a série não está ajustada por eles. O ajuste divide todos os
   * pregões antes da data ex pelo mesmo fator, então a razão entre vizinhos
   * não depende da base: a lista vale para qualquer data de coorte.
   */
  get jumps(): readonly DateTime[] {
    if (this.jumpsMemo !== null) return this.jumpsMemo;
    const s = this.series(new DateRange(DateTime.utc(1990), DateTime.utc(2100)), DateTime.utc(2100)).points;
    const out: DateTime[] = [];
    for (let i = 1; i < s.length; i++) {
      const a = s[i - 1]!;
      const b = s[i]!;
      if (
        a.close > 0 &&
        b.close > 0 &&
        b.date.difference(a.date).inDays <= DelistedSecurity.jumpDays &&
        Math.abs(Math.log(b.close / a.close)) > Math.log(DelistedSecurity.maxJump)
      ) {
        out.push(b.date);
      }
    }
    this.jumpsMemo = out;
    return out;
  }

  /** `true` quando algum evento não localizado cai em `[from, until]`. */
  eventNotLocatedBetween(from: DateTime, until: DateTime): boolean {
    return this.notLocated.some((d) => !d.isBefore(from) && !d.isAfter(until));
  }

  /**
   * `true` quando `(from, until]` atravessa evento não localizado ou salto: a
   * série não estaria ajustada por ele, e a janela sai.
   */
  suspiciousWindow(from: DateTime, until: DateTime): boolean {
    return this.eventNotLocatedBetween(from, until) || this.jumps.some((d) => d.isAfter(from) && !d.isAfter(until));
  }
}

type JsonMap = Record<string, unknown>;

const day = (s: string) => DateTime.parse(`${s.slice(0, 10)}T00:00:00Z`);

export class Delisted {
  private constructor(
    readonly securities: Map<string, DelistedSecurity>,
    /** Documentos da CVM por ticker de deslistada. */
    readonly documents: Map<string, CvmPeriodDocument[]>,
    readonly cvmSector: CvmSector | null,
    /**
     * Entradas da contagem descartadas pela conferência contra o salto do preço
     * (item B43), somadas nas companhias.
     */
    readonly discardedCounts: number,
  ) {}

  private byCnpjMemo: Map<string, DelistedSecurity[]> | null = null;

  /** Papéis de cada companhia, para o valor de mercado espécie a espécie. */
  get byCnpj(): Map<string, DelistedSecurity[]> {
    if (this.byCnpjMemo !== null) return this.byCnpjMemo;
    const out = new Map<string, DelistedSecurity[]>();
    for (const p of this.securities.values()) {
      const list = out.get(p.cnpj) ?? [];
      list.push(p);
      out.set(p.cnpj, list);
    }
    this.byCnpjMemo = out;
    return out;
  }

  /**
   * Valor de mercado da companhia de [security] em [date], com os papéis dela e a
   * contagem da data (item C3). `null` sem contagem ou sem papel de espécie
   * negociando.
   */
  marketValueOf(security: DelistedSecurity, date: DateTime): MarketValue | null {
    const shares = security.sharesAt(date);
    if (shares === null) return null;
    return MarketValue.atDate({
      shares,
      commonFraction: security.classes.at(date),
      securities: new Map((this.byCnpj.get(security.cnpj) ?? [security]).map((p) => [p.ticker.value, p.tradingDays] as const)),
      date,
    });
  }

  /**
   * Lê as deslistadas. `null` sem os arquivos do A3.4.
   *
   * - [listedClassification]: CNPJ da listada → classificação da B3, para
   *   medir o setor da CVM.
   * - [until]: a data de corte da conferência da contagem (item B43) — a âncora
   *   é a contagem mais recente até ela.
   */
  static read(listedClassification: Map<string, B3Classification>, until: DateTime): Delisted | null {
    const bridgeFile = 'data/b3/ponte_deslistadas.json';
    const countFile = 'data/b3/deslistadas_contagem.json';
    if (!existsSync(bridgeFile) || !existsSync(countFile)) return null;
    const bridge = readJson<Record<string, JsonMap>>(bridgeFile);
    const a34 = readJson<Record<string, JsonMap>>(countFile);
    const cvmSector = CvmSector.read(listedClassification);

    const isins = new Map<string, string>();
    const tickersByCnpj = new Map<string, string[]>();
    for (const [cnpj, entry] of Object.entries(bridge)) {
      for (const [code, security] of Object.entries(entry['papeis'] as JsonMap)) {
        if (Ticker.tryParse(code) === null) continue;
        isins.set(code, (security as JsonMap)['isin'] as string);
        const list = tickersByCnpj.get(cnpj) ?? [];
        list.push(code);
        tickersByCnpj.set(cnpj, list);
      }
    }
    const cotahist = readRawCotahist(new Set(isins.keys()), isins);
    const documents = loadDocuments('data/cvm_exercicios.json', {
      onlyTickers: new Set(isins.keys()),
      tickersByCnpj,
      withOldVersions: true,
    });

    const securities = new Map<string, DelistedSecurity>();
    let discarded = 0;
    for (const [cnpj, tickers] of tickersByCnpj) {
      const registry = a34[cnpj];
      if (registry === undefined) continue;
      // A contagem do formulário conferida contra o salto do preço dos papéis
      // da companhia (item B43, decisão 143): a correção que repete a contagem
      // de antes de um grupamento sai.
      const checked = checkCount(
        (registry['contagem'] as JsonMap[]).map((p) => ({
          since: day(p['desde'] as string),
          shares: Number(p['acoes']),
          source: (p['fonte'] as string | null | undefined) ?? null,
        })),
        tickers.map((t) => cotahist.get(t)).filter((s): s is TradingDay[] => s !== undefined && s.length > 1),
        until,
      );
      discarded += checked.discarded.length;
      const count = checked.accepted;
      if (count.length === 0) continue;

      const file = `data/b3/complemento_deslistadas/${cnpj.replace(/[./-]/g, '')}.json`;
      const supplement = existsSync(file) ? readJson<JsonMap>(file) : {};
      const fromB3 = B3Classification.parse((supplement['detalhe'] as JsonMap | undefined)?.['industryClassification']);
      const fromCvm = fromB3 === null ? (cvmSector?.classificationOf(cnpj) ?? null) : null;

      for (const t of tickers) {
        const data = (registry['papeis'] as JsonMap)[t] as JsonMap | undefined;
        const tradingDays = cotahist.get(t);
        if (data === undefined || data === null || tradingDays === undefined || tradingDays.length < 2) continue;

        // Eventos de mesma data ex: fica o que o preço observado explica.
        const byDate = new Map<string, { date: DateTime; factors: number[] }>();
        for (const ev of data['eventos'] as JsonMap[]) {
          const d = day(ev['dataEx'] as string);
          const entry = byDate.get(d.key) ?? { date: d, factors: [] };
          entry.factors.push(Number(ev['fator']));
          byDate.set(d.key, entry);
        }
        const events: ShareEvent[] = [];
        for (const { date: exDate, factors } of byDate.values()) {
          const observed = Delisted.ratioAtDate(tradingDays, exDate);
          let best = factors[0]!;
          if (factors.length > 1 && observed !== null) {
            for (const f of factors) {
              if (Math.abs(Math.log(f) - Math.log(observed)) < Math.abs(Math.log(best) - Math.log(observed))) best = f;
            }
          }
          events.push(new ShareEvent({ exDate, factor: best, observedRatio: observed ?? best }));
        }
        events.sort((a, b) => a.exDate.compareTo(b.exDate));

        const shareClass = B3CashDividends.shareClassOf(t);
        const dividends: CashDividend[] =
          shareClass === null
            ? []
            : (data['proventos'] as JsonMap[]).map(
                (p) =>
                  new CashDividend({
                    shareClass,
                    kind: CashDividendKind.fromKey(p['tipo'] as string),
                    // A data com é o pregão anterior à ex; a conta do retorno total
                    // só usa a data ex e o preço com direito.
                    lastDateWithRights: day(p['dataEx'] as string).subtract(new Duration({ days: 1 })),
                    exDate: day(p['dataEx'] as string),
                    amount: Number(p['valor']),
                    closeWithRights: p['precoComDireito'] === null || p['precoComDireito'] === undefined ? null : Number(p['precoComDireito']),
                  }),
              );

        securities.set(
          t,
          new DelistedSecurity({
            ticker: Ticker.parse(t),
            cnpj,
            name: (bridge[cnpj]?.['nome'] as string | undefined) ?? t,
            tradingDays,
            events,
            notLocated: (data['eventosNaoLocalizados'] as string[]).map(day),
            count,
            dividends,
            classification: fromB3 ?? fromCvm,
            sectorOrigin: fromB3 !== null ? 'b3' : fromCvm !== null ? 'cvm' : 'nenhuma',
            classes: CapitalClasses.fromJson(registry['classes'] as unknown[] | undefined),
          }),
        );
      }
    }
    return new Delisted(securities, documents, cvmSector, discarded);
  }

  /** `P_anterior / P_ex` na data ex: o fator que o preço observou. */
  private static ratioAtDate(s: readonly TradingDay[], ex: DateTime): number | null {
    for (let i = 1; i < s.length; i++) {
      if (s[i]!.date.isAtSameMomentAs(ex)) {
        const a = s[i - 1]!.close;
        const b = s[i]!.close;
        return a > 0 && b > 0 ? a / b : null;
      }
    }
    return null;
  }
}

/**
 * Fundamentos de uma deslistada numa data de coorte.
 *
 * A CVM dá as demonstrações; o que ela não dá — valor de mercado e contagem,
 * que a decisão 70 manda nunca tirar dela — vem de exercícios de mercado
 * sintéticos, um por DFP recebida até a data: a contagem do FRE no fim do
 * exercício, a contagem vigente na data e o valor de mercado da companhia na
 * data. É a mesma reconstrução que a coorte faz com as listadas, cuja fonte
 * repete o valor de mercado de hoje em todo exercício.
 *
 * **O valor de mercado é o da companhia, espécie a espécie** (item C3), e não
 * `contagem × preço do papel`, que dava razão de unidade 1 por construção. Sem
 * ele, recua para o produto.
 */
export class DelistedFundamentals implements FundamentalsRepository {
  constructor(
    readonly security: DelistedSecurity,
    readonly documents: readonly CvmPeriodDocument[],
    readonly date: DateTime,
    /** Fechamento bruto do papel na data. */
    readonly price: number,
    readonly options: {
      /** Valor de mercado da companhia na data, de [Delisted.marketValueOf]. */
      marketValueOf?: number | null;
      /** Série de doze meses ancorada no trimestre (item C1c), ou a de DFPs. */
      anchored?: boolean;
    } = {},
  ) {}

  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const view = new PointInTimeView(this.date);
    const published = (s: FundamentalsSnapshot) => view.isPublished(s);
    const today = this.security.sharesAt(this.date);
    if (today === null || today <= 0) {
      return err(new InsufficientData(`sem contagem de ${t.value} na data`, { subject: t.value }));
    }
    const market = CvmSeries.inForceAt(this.documents, published)
      .filter((d) => d.kind === CvmDocumentKind.dfp)
      .map(
        (d) =>
          new FundamentalsSnapshot({
            ticker: t,
            fiscalPeriodEnd: d.periodEnd,
            sharesOutstanding: today,
            sharesOutstandingAsOf: this.security.sharesAt(d.periodEnd),
            marketCap: this.options.marketValueOf ?? today * this.price,
          }),
      );
    return ok([
      ...CvmSeries.build({
        documents: this.documents,
        market,
        published,
        anchored: this.options.anchored ?? false,
        // A mesma série do aplicativo: o ano corrente anualizado (decisão 153).
        yearToDate: CvmSeries.yearToDateByDefault,
      }).series,
    ]);
  }

  async profile(t: Ticker): Promise<Result<Asset>> {
    const c = this.security.classification;
    return ok(
      new Asset({
        ticker: t,
        name: this.security.name,
        sector: c === null ? Sector.fromKey('', { label: '' }) : new Sector({ key: c.sectorKey, label: c.sector }),
        industry: c === null || c.industry === '' ? null : c.industry,
      }),
    );
  }

  async universe(): Promise<Result<Ticker[]>> {
    return ok([]);
  }
}

/** Preços de uma deslistada, na base da data da coorte. */
export class DelistedPrices implements PriceRepository {
  constructor(
    readonly security: DelistedSecurity,
    readonly until: DateTime,
  ) {}

  async daily(_t: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return ok(this.security.series(range, this.until));
  }

  async dailyBatch(tickers: readonly Ticker[], range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>> {
    return ok(new Map(tickers.map((t) => [t, this.security.series(range, this.until)] as const)));
  }

  adjustedCloseRaw(t: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return this.daily(t, range);
  }
}
