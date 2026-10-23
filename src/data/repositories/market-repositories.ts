import {
  Asset,
  type BenchmarkRepository,
  type DateRange,
  DateTime,
  err,
  FundamentalsSnapshot,
  type FundamentalsRepository,
  InsufficientData,
  type MacroRepository,
  ok,
  PricePoint,
  type PriceRepository,
  PriceSeries,
  RatePoint,
  RateSeries,
  type Result,
  Sector,
  type Ticker,
  TimeBasis,
} from '../../core';
import type {
  MarketCache,
  CachedFundamentals,
  CachedProfile,
  FundamentalsUpsert,
} from '../cache/cache-database';
import { CACHED_FUNDAMENTAL_FIELDS } from '../cache/cache-database';
import { CachePolicy } from '../cache/cache-policy';
import { BcbDatasource } from '../datasources/bcb-datasource';
import type { BrapiDatasource } from '../datasources/brapi-datasource';
import { BrapiJson } from '../dtos/brapi-dtos';

/**
 * Executa uma operação de cache tolerando falha.
 *
 * O cache é **otimização, não requisito**: acelera e torna os resultados
 * reprodutíveis, mas a aplicação precisa funcionar sem ele. Um banco que não
 * abre — IndexedDB bloqueado em janela anônima, cota esgotada, permissão
 * negada — não pode derrubar a camada de dados inteira.
 */
async function tryCache<T>(operation: () => Promise<T>): Promise<T | null> {
  try {
    return await operation();
  } catch {
    return null;
  }
}

async function freshIn(db: MarketCache | null, key: string, ttl: Parameters<MarketCache['isFresh']>[1]): Promise<boolean> {
  if (db === null) return false;
  return (await tryCache(() => db.isFresh(key, ttl))) ?? false;
}

/** Cotações, com cache local opcional. */
export class PriceRepositoryImpl implements PriceRepository {
  /** Fonte remota das cotações. */
  readonly remote: BrapiDatasource;

  /** `null` quando o cache não pôde ser inicializado. Tudo passa a vir da rede. */
  readonly cache: MarketCache | null;

  /**
   * Declara o repositório. Passar `cache: null` desliga o cache sem alterar
   * o comportamento observável, só o desempenho.
   */
  constructor(args: { remote: BrapiDatasource; cache: MarketCache | null }) {
    this.remote = args.remote;
    this.cache = args.cache;
  }

  async daily(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    const batch = await this.dailyBatch([ticker], range);
    return batch.flatMap((map) => {
      const series = map.get(ticker);
      if (series === undefined) return err(new InsufficientData(`Sem cotações para ${ticker.value}.`));
      return ok(series);
    });
  }

  async dailyBatch(tickers: readonly Ticker[], range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>> {
    if (tickers.length === 0) return ok(new Map());

    const out = new Map<Ticker, PriceSeries>();
    const missing: Ticker[] = [];

    for (const ticker of tickers) {
      const fresh = await freshIn(this.cache, CachePolicy.pricesKey(ticker.value), CachePolicy.historicalPrices);
      if (!fresh) {
        missing.push(ticker);
        continue;
      }
      const cached = await this.seriesFromCache(ticker, range);
      if (cached === null) {
        missing.push(ticker);
        continue;
      }
      out.set(ticker, cached);
    }

    if (missing.length === 0) return ok(out);

    // Um único lote para tudo que faltou.
    const fetched = await this.remote.historicalBatch(missing);
    if (fetched.isErr) {
      // Rede fora: recorre ao cache VENCIDO antes de desistir. Ele é o motivo
      // de o cache existir — e vencido aqui não significa errado, significa
      // sem os pregões mais recentes, porque a gravação é aditiva (ver
      // `CacheDatabase.isFresh`). A série chega mais curta, e o encurtamento
      // já é anunciado pelo backtest.
      let recovered = 0;
      for (const ticker of missing) {
        const stale = await this.seriesFromCache(ticker, range);
        if (stale !== null) {
          out.set(ticker, stale);
          recovered++;
        }
      }
      // **Recuperação parcial não é sucesso** (lente `dados`, 21/09/2026).
      // Devolver `Ok` com o lote incompleto engolia o motivo — limite de
      // requisições, credencial, rede fora — e a falha reaparecia adiante
      // como "ativo sem cotação", que é o sintoma e não a causa. O recuo ao
      // cache vencido vale quando ele cobre **tudo** que faltou; quando não
      // cobre, quem manda é o erro da rede.
      return recovered === missing.length ? ok(out) : err(fetched.failureOrNull!);
    }

    const arrived = fetched.unwrap();
    for (const [ticker, series] of arrived) {
      const saved = await this.persist(ticker, series);
      // **O que sai é o disco, e não o que a rede trouxe.** A gravação é
      // aditiva e a fonte devolve uma janela fixa de dez anos: quando o banco
      // já acumulou mais do que ela, devolver o recorte da resposta encurtaria
      // a série no caminho de SUCESSO — pior do que o caminho degradado, que
      // lê o disco. Sem cache, o recorte da resposta é tudo o que há; e sem a
      // gravação, também — o disco ficou com o que tinha, talvez noutra base.
      out.set(ticker, (saved ? await this.seriesFromCache(ticker, range) : null) ?? slice(series, range));
    }
    // O lote pode responder e deixar um ativo de fora — série corrompida
    // daquele papel, papel que a fonte deixou de devolver. Para ele a rede
    // falhou do mesmo jeito, e o histórico em disco serve pela mesma razão
    // do caminho acima (decisão 77).
    for (const ticker of missing) {
      if (arrived.has(ticker)) continue;
      const stale = await this.seriesFromCache(ticker, range);
      if (stale !== null) out.set(ticker, stale);
    }
    return ok(out);
  }

  adjustedCloseRaw(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>> {
    return this.daily(ticker, range);
  }

  /**
   * Série guardada em disco no recorte pedido, **sem olhar a validade**.
   *
   * Separado da checagem de frescor de propósito: o caminho normal só entra
   * aqui com cache válido, e o caminho degradado — rede fora — entra com ele
   * vencido. Devolve `null` quando não há cache, ele não abre, ou não há
   * linha alguma no intervalo.
   */
  private async seriesFromCache(ticker: Ticker, range: DateRange): Promise<PriceSeries | null> {
    const db = this.cache;
    if (db === null) return null;
    const rows = await tryCache(() =>
      db.pricesIn(ticker.value, BrapiJson.isoDay(range.start), BrapiJson.isoDay(range.end)),
    );
    if (rows === null || rows.length === 0) return null;
    return new PriceSeries({
      ticker,
      points: rows.map(
        (r) =>
          new PricePoint({
            date: DateTime.parse(r.date),
            close: r.close,
            adjustedClose: r.adjustedClose,
            volume: r.volume,
          }),
      ),
    });
  }

  /**
   * Diferença relativa a partir da qual o disco e a rede estão em **bases de
   * ações diferentes** (lente `risco`, 21/09/2026).
   *
   * Meio por cento: acima disso não é arredondamento de centavo nem correção
   * de fechamento, é evento societário. O menor desdobramento usual já move a
   * série por um fator inteiro, de modo que o corte não precisa ser fino — ele
   * precisa não disparar em ruído.
   */
  static readonly baseTolerance = 0.005;

  /**
   * O disco e a resposta discordam no mesmo pregão?
   *
   * **A base da fonte é a de hoje**: o `close` vem ajustado por todo evento
   * até agora, numa janela de dez anos. O que está em disco fora dessa janela
   * foi ajustado até o dia em que foi baixado — e um desdobramento no meio
   * deixa as duas metades em bases diferentes, com um degrau exatamente na
   * borda. Misturar bases é o defeito que a decisão 97 mediu nas coortes; aqui
   * ele entraria pelo cache.
   *
   * **O primeiro pregão que os dois têm, e não o primeiro da resposta**
   * (decisão 134). Comparar só o primeiro dia da resposta dava "sem evento"
   * sempre que ele faltasse no disco — um feriado lido de outro jeito, um
   * pregão que a busca anterior não trouxe —, e o histórico em outra base
   * ficava. Um evento entre duas buscas reajusta todo pregão anterior a ele,
   * de modo que o primeiro dia em comum basta para enxergá-lo.
   */
  private async baseChanged(ticker: Ticker, incoming: PriceSeries): Promise<boolean> {
    const db = this.cache;
    if (db === null || incoming.points.length === 0) return false;
    const rows = await tryCache(() =>
      db.pricesIn(
        ticker.value,
        BrapiJson.isoDay(incoming.points[0]!.date),
        BrapiJson.isoDay(incoming.points[incoming.points.length - 1]!.date),
      ),
    );
    if (rows === null || rows.length === 0) return false;
    const onDisk = new Map<string, number>();
    for (const r of rows) onDisk.set(r.date, r.close);
    for (const p of incoming.points) {
      const before = onDisk.get(BrapiJson.isoDay(p.date));
      if (before === undefined || before <= 0 || !Number.isFinite(p.close) || p.close <= 0) continue;
      return Math.abs(p.close / before - 1) > PriceRepositoryImpl.baseTolerance;
    }
    return false;
  }

  /**
   * Grava a resposta no disco e diz se o disco ficou com ela.
   *
   * `false` sem cache, quando a gravação falha e quando a base mudou e o
   * apagamento falhou: gravar por cima, nesse caso, deixaria as duas bases no
   * disco — o defeito da decisão 134 por outro caminho (lente `dados`,
   * 01/10/2026). Sem a gravação o carimbo de validade também não é renovado,
   * e a próxima busca tenta de novo.
   */
  private async persist(ticker: Ticker, series: PriceSeries): Promise<boolean> {
    const db = this.cache;
    if (db === null) return false;
    // **Duas bases não se somam.** Quando um pregão que a fonte devolve já
    // está em disco com outro preço, todo o disco daquele ativo é de outra base
    // e sai — perder profundidade é menos grave que servir uma série com degrau
    // que ninguém vê. **Todo, e não só o que antecede a resposta** (lente
    // `dados`, decisão 134): o pregão que a resposta omite no meio da janela
    // ficava em disco na escala velha, e o upsert não o alcançava.
    if (await this.baseChanged(ticker, series)) {
      const deleted = await tryCache(async () => {
        await db.deletePricesOf(ticker.value);
        return true;
      });
      if (deleted !== true) return false;
    }
    const saved = await tryCache(async () => {
      await db.upsertPrices(
        ticker.value,
        series.points.map((p) => ({
          date: BrapiJson.isoDay(p.date),
          close: p.close,
          adjustedClose: p.adjustedClose,
          volume: p.volume,
        })),
      );
      await db.touch(CachePolicy.pricesKey(ticker.value));
      return true;
    });
    return saved === true;
  }
}

function slice(series: PriceSeries, range: DateRange): PriceSeries {
  return new PriceSeries({ ticker: series.ticker, points: series.points.filter((p) => range.contains(p.date)) });
}

/**
 * O campo que a resposta trouxe, ou ausente — e o ausente **não apaga** o que
 * está em disco (lente `risco`, 27/09/2026).
 *
 * A fonte tolera uma rota com corpo de forma errada e devolve os exercícios
 * sem aquela demonstração. Gravar `null` nesses campos trocava o valor bom do
 * disco por nulo, e o cache — que existe para servir quando a fonte falha —
 * ficava pior que a resposta. Com o campo ausente, o `upsert` só mexe no que
 * chegou.
 */
function upsertRow(s: FundamentalsSnapshot): FundamentalsUpsert {
  const row: FundamentalsUpsert = { fiscalPeriodEnd: BrapiJson.isoDay(s.fiscalPeriodEnd) };
  for (const field of CACHED_FUNDAMENTAL_FIELDS) {
    const v = s[field];
    if (v !== null) row[field] = v;
  }
  return row;
}

/** Fundamentos e perfil cadastral. */
export class FundamentalsRepositoryImpl implements FundamentalsRepository {
  /** Fonte remota dos fundamentos e do perfil. */
  readonly remote: BrapiDatasource;

  /**
   * Cache local, ou `null` quando indisponível.
   *
   * **O universo de tickers não passa por aqui**: `universe()` delega direto
   * ao remoto, sem cache.
   */
  readonly cache: MarketCache | null;

  constructor(args: { remote: BrapiDatasource; cache: MarketCache | null }) {
    this.remote = args.remote;
    this.cache = args.cache;
  }

  async history(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const db = this.cache;
    if (await freshIn(db, CachePolicy.fundamentalsKey(ticker.value), CachePolicy.fundamentals)) {
      const rows = await tryCache(() => db!.fundamentalsOf(ticker.value));
      if (rows !== null && rows.length > 0) return ok(rows.map((r) => toDomain(ticker, r)));
    }

    const fetched = await this.remote.fundamentalsHistory(ticker);
    if (fetched.isErr) {
      // Rede fora: exercício antigo em disco é melhor que avaliação nenhuma.
      // O recorte *point-in-time* é aplicado adiante por `PointInTimeView`,
      // então um exercício defasado não vira número novo — vira, no máximo,
      // o aviso de avaliação desatualizada que a cascata já emite.
      const stale = db === null ? null : await tryCache(() => db.fundamentalsOf(ticker.value));
      if (stale !== null && stale.length > 0) return ok(stale.map((r) => toDomain(ticker, r)));
      return fetched;
    }

    const snapshots = fetched.unwrap();
    if (db === null) return ok(snapshots);
    await tryCache(async () => {
      await db.upsertFundamentals(ticker.value, snapshots.map(upsertRow));
      await db.touch(CachePolicy.fundamentalsKey(ticker.value));
    });
    // **O que volta é o banco depois do upsert, e não só o que a rede trouxe**
    // (lente `dados`, 20/09/2026). A fonte devolve uma janela; o banco guarda
    // a união do que já se viu. Devolver a janela logo depois de atualizar e a
    // união um minuto depois faz a mesma chamada ter profundidades diferentes
    // conforme o TTL — e a série de exercícios é o que forma a base de capital
    // e o crescimento. A leitura do cache é a mesma do caminho fresco.
    const reread = await tryCache(() => db.fundamentalsOf(ticker.value));
    if (reread !== null && reread.length >= snapshots.length) return ok(reread.map((r) => toDomain(ticker, r)));
    return ok(snapshots);
  }

  async profile(ticker: Ticker): Promise<Result<Asset>> {
    const db = this.cache;
    if (await freshIn(db, CachePolicy.profileKey(ticker.value), CachePolicy.profile)) {
      const row = await tryCache(() => db!.profileOf(ticker.value));
      if (row !== null) return ok(assetFrom(ticker, row));
    }

    const fetched = await this.remote.profile(ticker);
    if (fetched.isErr) {
      // Nome e setor mudam de ano em ano, não de hora em hora: o perfil
      // vencido é o dado degradado mais barato de aceitar.
      const stale = db === null ? null : await tryCache(() => db.profileOf(ticker.value));
      if (stale !== null) return ok(assetFrom(ticker, stale));
      return fetched;
    }

    const asset = fetched.unwrap();
    if (db === null) return ok(asset);
    await tryCache(async () => {
      await db.upsertProfile(ticker.value, {
        name: asset.name,
        sectorKey: asset.sector.isUnknown ? null : asset.sector.key,
        sectorLabel: asset.sector.isUnknown ? null : asset.sector.label,
        industry: asset.industry,
      });
      await db.touch(CachePolicy.profileKey(ticker.value));
    });
    return ok(asset);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.remote.universe();
  }
}

function assetFrom(ticker: Ticker, row: CachedProfile): Asset {
  return new Asset({
    ticker,
    name: row.name,
    sector:
      row.sectorKey === null ? Sector.unknown : Sector.fromKey(row.sectorKey, { label: row.sectorLabel ?? row.sectorKey }),
    industry: row.industry,
  });
}

function toDomain(ticker: Ticker, r: CachedFundamentals): FundamentalsSnapshot {
  const fields: Record<string, number | null> = {};
  for (const field of CACHED_FUNDAMENTAL_FIELDS) fields[field] = r[field] ?? null;
  return new FundamentalsSnapshot({ ticker, fiscalPeriodEnd: DateTime.parse(r.fiscalPeriodEnd), ...fields });
}

/** Índice de mercado. */
export class BenchmarkRepositoryImpl implements BenchmarkRepository {
  /**
   * Declara o repositório. **Sem cache**, ao contrário dos demais: a série do
   * índice é buscada uma vez por sessão e não justifica a via local.
   */
  constructor(readonly remote: BrapiDatasource) {}

  async ibovespa(range: DateRange): Promise<Result<PriceSeries>> {
    const fetched = await this.remote.ibovespa();
    return fetched.map((series) => slice(series, range));
  }
}

/** Variáveis macroeconômicas do Banco Central. */
export class MacroRepositoryImpl implements MacroRepository {
  /** Fonte remota das séries do Banco Central. */
  readonly remote: BcbDatasource;

  /** Cache local, ou `null` quando indisponível. */
  readonly cache: MarketCache | null;

  constructor(args: { remote: BcbDatasource; cache: MarketCache | null }) {
    this.remote = args.remote;
    this.cache = args.cache;
  }

  riskFreeDaily(range: DateRange): Promise<Result<RateSeries>> {
    return this.series(BcbDatasource.seriesCdiDaily, range);
  }

  inflationMonthly(range: DateRange): Promise<Result<RateSeries>> {
    return this.series(BcbDatasource.seriesIpcaMonthly, range);
  }

  activityIndexMonthly(range: DateRange): Promise<Result<RateSeries>> {
    return this.series(BcbDatasource.seriesIbcBrMonthly, range);
  }

  /**
   * Série macro guardada em disco no recorte pedido, **sem olhar a validade**.
   *
   * Serve aos dois caminhos: o normal, que só chega aqui com cache válido, e o
   * degradado, que chega com ele vencido porque a fonte falhou. Devolve `null`
   * quando não há cache, ele não abre, ou não há linha no intervalo.
   */
  private async macroFromCache(
    seriesId: number,
    range: DateRange,
    options: { requireCoverage?: boolean } = {},
  ): Promise<RateSeries | null> {
    const db = this.cache;
    if (db === null) return null;
    const rows = await tryCache(() =>
      db.macroIn(seriesId, BrapiJson.isoDay(range.start), BrapiJson.isoDay(range.end)),
    );
    if (rows === null || rows.length === 0) return null;

    const series = new RateSeries(
      rows.map((r) => new RatePoint({ date: DateTime.parse(r.date), rate: r.value })),
      { basis: BcbDatasource.basisOf(seriesId) },
    );

    // **A validade é por série, e o recorte é por janela.** Sem esta
    // conferência, um gráfico de seis meses grava o CDI, marca a série como
    // fresca, e a simulação de dez anos que vier depois recebe seis meses
    // **achando que recebeu dez anos** — e apura o CAGR decenal sobre eles.
    // A ponta final não é exigível: uma série de publicação lenta termina
    // onde o Banco Central parou.
    if (options.requireCoverage === true && !MacroRepositoryImpl.coversStart(series, range, seriesId)) return null;
    return series;
  }

  /**
   * O cache começa cedo o bastante para a janela pedida?
   *
   * A folga acomoda fim de semana e feriado no começo da janela: dez dias na
   * série diária, dois meses na mensal.
   *
   * **Ela não acomoda série que nasce depois da janela pedida** — o IBC-Br não
   * existe antes de 2003, e pedir 1990 invalida o cache dele em toda leitura,
   * porque o cache nunca vai cobrir um início que a fonte não publica (lente
   * `dados`, 20/09/2026). Não é alcançável hoje: as séries que o motor lê —
   * CDI, IPCA — começam muito antes das janelas de dez anos que ele pede.
   * Resolver pede guardar o primeiro ponto que a fonte publica, e não
   * inferi-lo da janela.
   */
  static coversStart(s: RateSeries, range: DateRange, seriesId: number): boolean {
    if (s.points.length === 0) return false;
    // **Compara dia civil, e não instante.** Somar horas absolutas faria a
    // folga valer 9 ou 11 dias conforme o horário de verão. As datas aqui são
    // datas, não momentos.
    const first = s.points[0]!.date;
    const days = BcbDatasource.basisOf(seriesId) === TimeBasis.monthly ? 62 : 10;
    const limit = DateTime.utc(range.start.year, range.start.month, range.start.day + days);
    const start = DateTime.utc(first.year, first.month, first.day);
    return !start.isAfter(limit);
  }

  private async series(seriesId: number, range: DateRange): Promise<Result<RateSeries>> {
    const db = this.cache;
    if (await freshIn(db, CachePolicy.macroKey(seriesId), CachePolicy.macro)) {
      // No caminho normal a cobertura é exigida: cache curto vai à rede.
      const current = await this.macroFromCache(seriesId, range, { requireCoverage: true });
      if (current !== null) return ok(current);
    }

    const fetched = await this.remote.series(seriesId, range);
    if (fetched.isErr) {
      // SGS fora do ar, lento ou devolvendo erro: recorre ao cache **vencido**
      // antes de desistir, como já fazia a série de preços. Dado velho em
      // disco é melhor que avaliação nenhuma — e sem isso a indisponibilidade
      // transitória do Banco Central derrubava simulação inteira por falta de
      // um CDI que estava salvo no dia anterior.
      //
      // **A cobertura do início é exigida aqui também.** Vencido autoriza
      // faltar a ponta, e não o começo: sem a exigência, três meses guardados
      // por um gráfico serviam a simulação de dez anos justamente quando a
      // fonte caía, e o CAGR decenal saía sobre eles sem aviso. Sem cache que
      // cubra a janela, a falha da fonte é reportada.
      const stale = await this.macroFromCache(seriesId, range, { requireCoverage: true });
      if (stale !== null) return ok(stale);
      return fetched;
    }

    const series = fetched.unwrap();
    if (db === null) return ok(series);
    await tryCache(async () => {
      // Um ponto por linha: não há duas listas a indexar em paralelo.
      await db.upsertMacro(
        seriesId,
        series.points.map((p) => ({ date: BrapiJson.isoDay(p.date), value: p.rate })),
      );
      await db.touch(CachePolicy.macroKey(seriesId));
    });
    // **O que sai é o banco depois do upsert, e não só o que a rede trouxe**
    // (lente `dados`, 21/09/2026) — a mesma correção que os fundamentos
    // receberam. O SGS responde a janela pedida; o banco guarda a união do
    // que já se viu, e é sobre essa série que o CAGR decenal é apurado.
    //
    // A cobertura do início **não** é exigida aqui: o que acabou de vir da
    // fonte é o que há, e recusá-lo por não cobrir a janela devolveria a falha
    // no caminho de sucesso.
    const reread = await this.macroFromCache(seriesId, range, { requireCoverage: false });
    if (reread !== null && reread.points.length >= series.points.length) return ok(reread);
    return ok(series);
  }
}
