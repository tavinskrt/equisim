import type { Duration } from '../../core';
import type { KeyValueStore } from './key-value-store';

/** Cotação diária guardada. Um fechamento por ticker por pregão. */
export interface CachedPrice {
  /**
   * Data do pregão em `AAAA-MM-DD`, para que a comparação lexicográfica
   * coincida com a cronológica em consultas de intervalo, sem conversão.
   */
  date: string;
  close: number;
  adjustedClose: number | null;
  /**
   * Volume negociado no pregão, em quantidade de papéis. Entra com a decisão
   * 25: a Porta 0 filtra por volume financeiro médio, e sem ele o corte de
   * liquidez não é computável.
   */
  volume: number | null;
}

/**
 * Campos numéricos guardados de cada exercício, na ordem das colunas do
 * cache anterior. Os que a decisão 25 passou a exigir (NOPAT publicado, o
 * lado operacional do capital investido e o que distingue emissão de
 * bonificação) e os dois termos da ponte da decisão 49 estão aqui desde o
 * começo deste armazenamento.
 */
export const CACHED_FUNDAMENTAL_FIELDS = [
  'totalRevenue',
  'ebit',
  'ebitda',
  'netIncome',
  'incomeBeforeTax',
  'incomeTaxExpense',
  'interestExpense',
  'earningsPerShare',
  'cash',
  'shortTermInvestments',
  'shortTermDebt',
  'longTermDebt',
  'totalStockholderEquity',
  'bookValuePerShare',
  'operatingCashFlow',
  'investmentCashFlow',
  'freeCashFlow',
  'sharesOutstanding',
  // Contagem de ações **do exercício**, antes da sobrescrita pela corrente.
  // Sem ela não há patrimônio nem capital investido reconstituíveis.
  'sharesOutstandingAsOf',
  'marketCap',
  'enterpriseToEbitda',
  'nopat',
  'propertyPlantEquipment',
  'intangibleAssets',
  'totalCurrentAssets',
  'currentLiabilities',
  'realizedShareCapital',
  'profitReserves',
  'minorityInterest',
  'equityIncomeResult',
] as const;

export type CachedFundamentalField = (typeof CACHED_FUNDAMENTAL_FIELDS)[number];

/** Exercício guardado: fim do exercício em `AAAA-MM-DD` e os campos tipados. */
export type CachedFundamentals = { fiscalPeriodEnd: string } & Record<CachedFundamentalField, number | null>;

/**
 * Exercício a gravar. Campo **ausente** (`undefined`) não toca o que está em
 * disco; campo `null` só é gravado em linha nova. É o `Value.absent()` do
 * cache anterior (lente `risco`, 27/09/2026).
 */
export type FundamentalsUpsert = { fiscalPeriodEnd: string } & Partial<Record<CachedFundamentalField, number | null>>;

/** Perfil cadastral e classificação setorial. */
export interface CachedProfile {
  name: string;
  sectorKey: string | null;
  sectorLabel: string | null;
  industry: string | null;
}

/** Taxa de uma série macro do SGS, já em fração (0,000374 = 0,0374% ao dia). */
export interface CachedMacroRate {
  date: string;
  value: number;
}

/**
 * O que os repositórios de mercado usam do cache. É a forma pública de
 * [CacheDatabase], e existe para as ferramentas de `tool/`, que no Node gravam
 * no SQLite com as tabelas do cache do aplicativo Flutter — e assim leem o
 * `validation_cache.sqlite` que as execuções em Dart deixaram.
 */
export type MarketCache = Pick<
  CacheDatabase,
  | 'isFresh'
  | 'touch'
  | 'invalidate'
  | 'pricesIn'
  | 'upsertPrices'
  | 'deletePricesOf'
  | 'fundamentalsOf'
  | 'upsertFundamentals'
  | 'profileOf'
  | 'upsertProfile'
  | 'macroIn'
  | 'upsertMacro'
>;

/**
 * Cache local das séries de mercado.
 *
 * Substitui o banco SQLite do aplicativo anterior por linhas agrupadas em um
 * armazenamento chave-valor: cada ativo tem **uma** lista de cotações, uma de
 * exercícios e um perfil; cada série do SGS tem uma lista de taxas; e cada
 * recurso tem o carimbo de quando foi buscado. A semântica é a mesma das
 * tabelas de antes — chave primária `(ticker, data)`, gravação aditiva,
 * consulta por intervalo inclusivo em ordem cronológica.
 *
 * **Não há migração do cache anterior**, e é deliberado: ele morava noutro
 * banco, e é reconstruível a partir da rede. A versão abaixo existe para a
 * próxima mudança de forma — ao abrir um cache de outra versão, ele é
 * descartado por inteiro, porque descartar é sempre seguro aqui.
 */
export class CacheDatabase {
  /** Versão da forma das linhas. Outra versão em disco é descartada. */
  static readonly schemaVersion = 1;

  private static readonly versionKey = 'meta:versao';

  private ready: Promise<void> | null = null;

  /**
   * - [store]: onde as linhas moram — IndexedDB no navegador, memória em
   *   teste e no Node.
   * - [now]: relógio do controle de validade, em milissegundos desde a época.
   *   É controle de cache, não cálculo, e por isso não viola o determinismo
   *   do domínio; injetável para o teste avançar o tempo.
   */
  constructor(
    private readonly store: KeyValueStore,
    private readonly now: () => number = () => Date.now(),
  ) {}

  private async open(): Promise<void> {
    this.ready ??= (async () => {
      const version = await this.store.get<number>(CacheDatabase.versionKey);
      if (version === CacheDatabase.schemaVersion) return;
      // Forma desconhecida: as chaves de linha mudam com a forma, e por isso
      // só o carimbo de versão precisa ser trocado — o que estava nas chaves
      // antigas fica órfão e nunca mais é lido.
      await this.store.set(CacheDatabase.versionKey, CacheDatabase.schemaVersion);
    })();
    try {
      await this.ready;
    } catch (e) {
      this.ready = null;
      throw e;
    }
  }

  private static rowsKey(kind: string, id: string | number): string {
    return `v${CacheDatabase.schemaVersion}:${kind}:${id}`;
  }

  // ------------------------------------------------------------------ TTL --

  /**
   * Verdadeiro se o recurso está em cache e ainda dentro da validade.
   *
   * A validade governa a **ponta da série**, não as linhas já guardadas:
   * responder `false` provoca uma rebusca que soma dias novos aos antigos, e
   * nunca um descarte. Recurso nunca buscado devolve `false`.
   */
  async isFresh(key: string, ttl: Duration): Promise<boolean> {
    await this.open();
    const fetchedAt = await this.store.get<number>(CacheDatabase.rowsKey('entrada', key));
    if (fetchedAt === undefined) return false;
    return this.now() - fetchedAt < ttl.inMilliseconds;
  }

  /**
   * Marca o recurso como buscado agora, reiniciando sua validade.
   *
   * Chamar **depois** de gravar as linhas: entre a marcação e a gravação, uma
   * falha deixaria o cache com validade renovada e conteúdo velho.
   */
  async touch(key: string): Promise<void> {
    await this.open();
    await this.store.set(CacheDatabase.rowsKey('entrada', key), this.now());
  }

  /** Invalida o carimbo de um recurso — a próxima leitura vai à fonte. */
  async invalidate(key: string): Promise<void> {
    await this.open();
    await this.store.del(CacheDatabase.rowsKey('entrada', key));
  }

  // --------------------------------------------------------------- Preços --

  /**
   * Cotações de um ativo no intervalo, em ordem cronológica, bordas
   * inclusivas em `AAAA-MM-DD`. Lista vazia quando não há nada em cache — o
   * que é indistinguível de um intervalo realmente sem pregões.
   */
  async pricesIn(ticker: string, startIso: string, endIso: string): Promise<CachedPrice[]> {
    await this.open();
    const rows = (await this.store.get<CachedPrice[]>(CacheDatabase.rowsKey('precos', ticker))) ?? [];
    return rows.filter((r) => r.date >= startIso && r.date <= endIso);
  }

  /** Insere ou atualiza cotações em lote, pela chave `(ticker, date)`. */
  async upsertPrices(ticker: string, rows: readonly CachedPrice[]): Promise<void> {
    await this.open();
    await this.store.update<CachedPrice[]>(CacheDatabase.rowsKey('precos', ticker), (old) => {
      const byDate = new Map<string, CachedPrice>();
      for (const r of old ?? []) byDate.set(r.date, r);
      for (const r of rows) byDate.set(r.date, { ...r });
      return sortedBy([...byDate.values()], (r) => r.date);
    });
  }

  /**
   * Apaga **todas** as cotações de um ativo.
   *
   * Existe para a rebase do preço: a fonte devolve o fechamento já ajustado
   * por todo evento societário até hoje, numa janela de dez anos. O que está
   * em disco foi ajustado até a data em que **foi baixado**, e um
   * desdobramento entre duas buscas deixa as duas bases misturadas — um
   * degrau silencioso na série. Todas, e não só as anteriores à janela: o
   * pregão que a resposta omite no meio dela também é da base velha (decisão
   * 134). Ver `PriceRepositoryImpl`.
   */
  async deletePricesOf(ticker: string): Promise<void> {
    await this.open();
    await this.store.del(CacheDatabase.rowsKey('precos', ticker));
  }

  // ----------------------------------------------------------- Fundamentos --

  /** Exercícios de um ativo, do mais antigo ao mais recente. */
  async fundamentalsOf(ticker: string): Promise<CachedFundamentals[]> {
    await this.open();
    return (await this.store.get<CachedFundamentals[]>(CacheDatabase.rowsKey('fundamentos', ticker))) ?? [];
  }

  /**
   * Insere ou atualiza exercícios em lote, pela chave
   * `(ticker, fiscalPeriodEnd)`. Campo ausente na linha nova não apaga o que
   * está em disco.
   */
  async upsertFundamentals(ticker: string, rows: readonly FundamentalsUpsert[]): Promise<void> {
    await this.open();
    await this.store.update<CachedFundamentals[]>(CacheDatabase.rowsKey('fundamentos', ticker), (old) => {
      const byPeriod = new Map<string, CachedFundamentals>();
      for (const r of old ?? []) byPeriod.set(r.fiscalPeriodEnd, r);
      for (const r of rows) {
        const base = byPeriod.get(r.fiscalPeriodEnd) ?? emptyFundamentals(r.fiscalPeriodEnd);
        const merged: CachedFundamentals = { ...base };
        for (const field of CACHED_FUNDAMENTAL_FIELDS) {
          const v = r[field];
          if (v !== undefined) merged[field] = v;
        }
        byPeriod.set(r.fiscalPeriodEnd, merged);
      }
      return sortedBy([...byPeriod.values()], (r) => r.fiscalPeriodEnd);
    });
  }

  // --------------------------------------------------------------- Perfil --

  /** Perfil cadastral de um ativo, ou `null` se não estiver em cache. */
  async profileOf(ticker: string): Promise<CachedProfile | null> {
    await this.open();
    return (await this.store.get<CachedProfile>(CacheDatabase.rowsKey('perfil', ticker))) ?? null;
  }

  /** Insere ou atualiza o perfil de um ativo. */
  async upsertProfile(ticker: string, row: CachedProfile): Promise<void> {
    await this.open();
    await this.store.set(CacheDatabase.rowsKey('perfil', ticker), { ...row });
  }

  // ---------------------------------------------------------------- Macro --

  /**
   * Taxas de uma série macro no intervalo, em ordem cronológica.
   *
   * - [seriesId]: código SGS do Banco Central (12 = CDI, 433 = IPCA).
   * - [startIso], [endIso]: bordas inclusivas, em `AAAA-MM-DD`.
   */
  async macroIn(seriesId: number, startIso: string, endIso: string): Promise<CachedMacroRate[]> {
    await this.open();
    const rows = (await this.store.get<CachedMacroRate[]>(CacheDatabase.rowsKey('macro', seriesId))) ?? [];
    return rows.filter((r) => r.date >= startIso && r.date <= endIso);
  }

  /** Insere ou atualiza taxas macro em lote, pela chave `(seriesId, date)`. */
  async upsertMacro(seriesId: number, rows: readonly CachedMacroRate[]): Promise<void> {
    await this.open();
    await this.store.update<CachedMacroRate[]>(CacheDatabase.rowsKey('macro', seriesId), (old) => {
      const byDate = new Map<string, CachedMacroRate>();
      for (const r of old ?? []) byDate.set(r.date, r);
      for (const r of rows) byDate.set(r.date, { ...r });
      return sortedBy([...byDate.values()], (r) => r.date);
    });
  }
}

function emptyFundamentals(fiscalPeriodEnd: string): CachedFundamentals {
  const row = { fiscalPeriodEnd } as CachedFundamentals;
  for (const field of CACHED_FUNDAMENTAL_FIELDS) row[field] = null;
  return row;
}

function sortedBy<T>(rows: T[], key: (r: T) => string): T[] {
  return rows.sort((a, b) => {
    const ka = key(a);
    const kb = key(b);
    return ka < kb ? -1 : ka > kb ? 1 : 0;
  });
}
