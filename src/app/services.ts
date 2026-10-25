import {
  type Asset,
  type CalibratedBandTable,
  CapitalEvents,
  CapmInputs,
  type CashDividend,
  DateRange,
  DateTime,
  MarketAnchors,
  MarketPremiumSource,
  type OfficialShareCount,
  type PeerMultipleSet,
  ResolveMarketAnchors,
  type SkillReading,
  type Ticker,
} from '../core';
import { CacheDatabase } from '../data/cache/cache-database';
import type { KeyValueStore } from '../data/cache/key-value-store';
import { type ApiEnvironment, ApiConfig } from '../data/config/api-config';
import { AssetPaths } from '../data/config/asset-paths';
import { DistressedRegistry } from '../data/config/distressed-registry';
import { BcbDatasource } from '../data/datasources/bcb-datasource';
import { BrapiDatasource } from '../data/datasources/brapi-datasource';
import { TreasuryDatasource } from '../data/datasources/treasury-datasource';
import { ApiClient } from '../data/network/api-client';
import type { HttpTransport } from '../data/network/http';
import type { ManualValuationStore } from '../data/persistence/manual-valuation-store';
import type { PortfolioStore } from '../data/persistence/portfolio-store';
import { B3RegistryRepository, OfficialSectorFundamentalsRepository } from '../data/repositories/b3-registry-repository';
import { type BetaPriorReading, BetaPriorRepository } from '../data/repositories/beta-prior-repository';
import { CalibratedBandRepository } from '../data/repositories/calibrated-band-repository';
import { CapitalEventsRepository } from '../data/repositories/capital-events-repository';
import { CashDividendsRepository } from '../data/repositories/cash-dividends-repository';
import { ConcessionTermRepository } from '../data/repositories/concession-term-repository';
import { CvmFundamentalsRepository } from '../data/repositories/cvm-fundamentals-repository';
import { type MarketPremiumReading, MarketPremiumRepository } from '../data/repositories/market-premium-repository';
import {
  BenchmarkRepositoryImpl,
  FundamentalsRepositoryImpl,
  MacroRepositoryImpl,
  PriceRepositoryImpl,
} from '../data/repositories/market-repositories';
import type { PackageLoader } from '../data/repositories/package-loader';
import { PeerMultiplesRepository } from '../data/repositories/peer-multiples-repository';
import { type CurveReading, RiskFreeCurveRepository } from '../data/repositories/risk-free-curve-repository';
import { ShareholderControlRepository } from '../data/repositories/shareholder-control-repository';
import { SkillReadingRepository } from '../data/repositories/skill-reading-repository';
import { UnitCompositionRepository } from '../data/repositories/unit-composition-repository';
import { ValuationRunner, type WorkerFactory } from '../data/runner/valuation-runner';
import { AuditNetworkInterceptor } from '../audit/audit-network-interceptor';

/**
 * O que a raiz de composição recebe de fora.
 *
 * Tudo que depende do ambiente — de onde vêm os pacotes, onde mora o cache,
 * que relógio vale — chega por aqui. É o que permite montar o mesmo grafo no
 * navegador, no Node das ferramentas de `tool/` e no teste.
 */
export interface ServicesOptions {
  /** Lê um arquivo servido junto do aplicativo (`public/`), pelo caminho relativo. */
  readonly loadText: (path: string) => Promise<string>;
  /** Variáveis de acesso à brapi. */
  readonly env?: ApiEnvironment;
  /** Onde o cache de rede mora. `null` dispensa o cache — é otimização, não requisito. */
  readonly cacheStore?: KeyValueStore | null;
  /**
   * O relógio do aplicativo. **A camada de aplicativo é o lugar de perguntar a
   * data**, e o núcleo recebe a data pronta (CLAUDE.md, §3.2).
   */
  readonly clock?: () => DateTime;
  /** Fábrica do Worker da avaliação; `null` resolve em linha. */
  readonly workerFactory?: WorkerFactory;
  /**
   * `true` no navegador, que não lê o arquivo do Tesouro: a curva vem só do
   * pacote do build (decisão 86).
   */
  readonly isWeb?: boolean;
  /** Registro de aviso de infraestrutura. */
  readonly warn?: (message: string) => void;
  /** Transporte HTTP; omitido, o `fetch` do ambiente. Injetável para o teste. */
  readonly transport?: HttpTransport;
  /** Espera entre repetições; injetável para o teste não dormir de verdade. */
  readonly retrySleep?: (ms: number) => Promise<void>;
}

/** Os dois lugares onde o usuário guarda o que é dele. */
export interface UserStores {
  readonly portfolios: PortfolioStore;
  readonly valuations: ManualValuationStore;
}

/** Memoriza uma leitura sem argumento: a primeira chamada vale pela sessão. */
function once<T>(read: () => Promise<T>): () => Promise<T> {
  let cached: Promise<T> | null = null;
  return () => (cached ??= read());
}

/** Memoriza uma leitura por ativo. */
function perTicker<T>(read: (t: Ticker) => Promise<T>): (t: Ticker) => Promise<T> {
  const cache = new Map<Ticker, Promise<T>>();
  return (t) => {
    let hit = cache.get(t);
    if (hit === undefined) {
      hit = read(t);
      cache.set(t, hit);
    }
    return hit;
  };
}

/** Lê um pacote, e a falha de leitura é a ausência dele. */
function packageAt(loadText: (path: string) => Promise<string>, path: string): PackageLoader {
  return () => loadText(path);
}

/**
 * **Raiz de composição.** O grafo de dependências do aplicativo, montado à
 * mão: são poucas peças, e explícitas elas se leem melhor do que atrás de um
 * contêiner de injeção — o mesmo argumento que o `lib/di/providers.dart` do
 * aplicativo Flutter registrava.
 *
 * Cada leitura de pacote é **transparente sem o pacote**: a falha vira o
 * comportamento anterior ao pacote, declarado em ressalva, e nunca derruba a
 * avaliação. Cada leitura é feita uma vez por sessão.
 */
export class Services {
  readonly config: ApiConfig;
  readonly client: ApiClient;
  /** Cache local. **Pode ser `null`**: sem ele, a aplicação só volta à rede mais vezes. */
  readonly cache: CacheDatabase | null;
  readonly brapi: BrapiDatasource;
  readonly bcb: BcbDatasource;
  readonly prices: PriceRepositoryImpl;
  readonly cvm: CvmFundamentalsRepository;
  readonly fundamentals: OfficialSectorFundamentalsRepository;
  readonly benchmark: BenchmarkRepositoryImpl;
  readonly macro: MacroRepositoryImpl;
  readonly b3Registry: B3RegistryRepository;
  readonly runner: ValuationRunner;
  readonly clock: () => DateTime;

  private readonly betaPriorRepository: BetaPriorRepository;
  private readonly marketPremiumRepository: MarketPremiumRepository;
  private readonly peerMultiplesRepository: PeerMultiplesRepository;
  private readonly unitCompositionRepository: UnitCompositionRepository;
  private readonly shareholderControlRepository: ShareholderControlRepository;
  private readonly cashDividendsRepository: CashDividendsRepository;
  private readonly concessionTermRepository: ConcessionTermRepository;
  private readonly capitalEventsRepository: CapitalEventsRepository;
  private readonly calibratedBandRepository: CalibratedBandRepository;
  private readonly skillReadingRepository: SkillReadingRepository;
  private readonly riskFreeCurveRepository: RiskFreeCurveRepository;
  private readonly loadText: (path: string) => Promise<string>;
  private readonly warn: (message: string) => void;

  constructor(options: ServicesOptions) {
    this.loadText = options.loadText;
    this.clock = options.clock ?? (() => DateTime.now());
    this.warn = options.warn ?? ((m) => console.warn(m));
    const pkg = (path: string) => packageAt(this.loadText, path);

    this.config = ApiConfig.resolve(options.env ?? {});
    if (this.config.credentialIsExposed) {
      this.warn(
        '⚠️  Credencial da brapi lida de VITE_BRAPI_TOKEN, que o Vite embarca no bundle. ' +
          'Para distribuição use o proxy de custódia (VITE_BRAPI_PROXY_URL).',
      );
    }
    this.client = new ApiClient(this.config, {
      ...(options.transport ? { transport: options.transport } : {}),
      ...(options.retrySleep ? { retrySleep: options.retrySleep } : {}),
    });
    // O interceptador de auditoria fica sempre montado: ele próprio verifica se
    // há alguém ouvindo e, quando não há, não chega a construir o evento.
    this.client.pipeline.interceptors.push(new AuditNetworkInterceptor());

    this.cache = options.cacheStore ? new CacheDatabase(options.cacheStore) : null;
    this.brapi = new BrapiDatasource(this.client);
    this.bcb = new BcbDatasource(this.client);
    this.prices = new PriceRepositoryImpl({ remote: this.brapi, cache: this.cache });
    this.benchmark = new BenchmarkRepositoryImpl(this.brapi);
    this.macro = new MacroRepositoryImpl({ remote: this.bcb, cache: this.cache });
    this.b3Registry = new B3RegistryRepository({ loadPackage: pkg(AssetPaths.b3Registry) });
    this.cvm = new CvmFundamentalsRepository({
      market: new FundamentalsRepositoryImpl({ remote: this.brapi, cache: this.cache }),
      loadPackage: pkg(AssetPaths.cvmPackage),
      today: this.clock,
    });
    // O setor é o da B3, por emissor (item A5, decisão 87).
    this.fundamentals = new OfficialSectorFundamentalsRepository({
      inner: this.cvm,
      classification: (t) => this.b3Registry.classificationFor(t),
    });
    this.runner = new ValuationRunner(options.workerFactory);

    this.betaPriorRepository = new BetaPriorRepository({ loadPackage: pkg(AssetPaths.betaPrior), today: this.clock });
    this.marketPremiumRepository = new MarketPremiumRepository({
      loadPackage: pkg(AssetPaths.marketPremium),
      today: this.clock,
    });
    this.peerMultiplesRepository = new PeerMultiplesRepository({ loadPackage: pkg(AssetPaths.peerMultiples) });
    this.unitCompositionRepository = new UnitCompositionRepository({
      loadPackage: pkg(AssetPaths.unitComposition),
      today: this.clock,
    });
    this.shareholderControlRepository = new ShareholderControlRepository({
      loadPackage: pkg(AssetPaths.shareholderControl),
      today: this.clock,
    });
    this.cashDividendsRepository = new CashDividendsRepository({ loadPackage: pkg(AssetPaths.cashDividends) });
    this.concessionTermRepository = new ConcessionTermRepository({ loadPackage: pkg(AssetPaths.concessionTerms) });
    this.capitalEventsRepository = new CapitalEventsRepository({ loadPackage: pkg(AssetPaths.capitalEvents) });
    this.calibratedBandRepository = new CalibratedBandRepository({ loadPackage: pkg(AssetPaths.calibratedBand) });
    this.skillReadingRepository = new SkillReadingRepository({ loadPackage: pkg(AssetPaths.skillReading) });
    this.riskFreeCurveRepository = new RiskFreeCurveRepository({
      // Na web o navegador não lê o arquivo do Tesouro, e o aplicativo nem
      // tenta: a curva vem só do pacote do build (decisão 86).
      remote: options.isWeb === false ? new TreasuryDatasource(this.client) : null,
      loadPackage: pkg(AssetPaths.treasuryQuotes),
    });
  }

  // ------------------------------------------------------- Dados de mercado --

  /**
   * Âncoras de CDI e Ibovespa, calculadas das séries observadas. Sem rede, os
   * valores medidos em 19/08/2026 mantêm a tela utilizável.
   */
  readonly marketAnchors = once(async (): Promise<MarketAnchors> => {
    const result = await ResolveMarketAnchors.call({
      macro: this.macro,
      benchmark: this.benchmark,
      asOf: this.clock(),
    });
    return result.isOk ? result.unwrap() : MarketAnchors.fallback2026;
  });

  /**
   * Taxa livre de risco anual **da janela informada** (decisão 58): o Sharpe
   * compara o retorno de uma janela com a renda fixa dela. Recua para o CAGR
   * decenal do CDI quando a série da janela não vem.
   */
  private readonly windowRates = new Map<string, Promise<number>>();

  riskFreeRateForWindow(window: DateRange): Promise<number> {
    const key = window.toString();
    let hit = this.windowRates.get(key);
    if (hit === undefined) {
      hit = (async () => {
        const series = await this.macro.riskFreeDaily(window);
        if (series.isOk && !series.unwrap().isEmpty) return series.unwrap().annualized();
        return (await this.marketAnchors()).riskFreeCagr;
      })();
      this.windowRates.set(key, hit);
    }
    return hit;
  }

  /** Registro de ativos em recuperação judicial: a Porta 0 os recusa. */
  readonly distressedRegistry = once(async (): Promise<DistressedRegistry> => {
    try {
      return await DistressedRegistry.load(() => this.loadText(DistressedRegistry.assetPath));
    } catch {
      return DistressedRegistry.empty;
    }
  });

  /** Universo de ações da B3, para a busca. */
  readonly universe = once(async (): Promise<Ticker[]> => {
    const result = await this.fundamentals.universe();
    return result.isOk ? result.unwrap() : [];
  });

  /** Perfil cadastral de um ativo, ou `null`. */
  readonly profile = perTicker(async (t: Ticker): Promise<Asset | null> => {
    const result = await this.fundamentals.profile(t);
    return result.isOk ? result.unwrap() : null;
  });

  // -------------------------------------------------------- Pacotes do build --

  /**
   * O prior do beta e a ressalva quando ele não pôde ser usado (item B11). Sem
   * prior o motor é outro — beta cru e WACC estático —, e a ressalva diz qual.
   */
  readonly betaPriorReading = once(async (): Promise<BetaPriorReading> => {
    try {
      return await this.betaPriorRepository.reading();
    } catch {
      return { prior: null, note: null };
    }
  });

  /**
   * O prêmio de mercado do pacote, de onde veio e a ressalva (decisão 142). É
   * o mesmo prêmio no desconto e no retorno esperado da carteira.
   */
  readonly marketPremiumReading = once(async (): Promise<MarketPremiumReading> => {
    try {
      return await this.marketPremiumRepository.reading();
    } catch {
      return {
        premium: CapmInputs.defaultMarketPremium,
        source: MarketPremiumSource.parameterized,
        note: null,
      };
    }
  });

  /** Curva de juros da avaliação de hoje e, sem ela, a razão (decisões 84 e 86). */
  readonly riskFreeCurveReading = once(async (): Promise<CurveReading> => {
    try {
      return await this.riskFreeCurveRepository.readAt(this.clock());
    } catch {
      return { curve: null, note: null };
    }
  });

  /** Faixas do valor realizado medidas nas coortes (decisão 92). Vazio sem pacote. */
  readonly calibratedBands = once(async (): Promise<CalibratedBandTable[]> => {
    try {
      return await this.calibratedBandRepository.tables();
    } catch {
      return [];
    }
  });

  /** A habilidade do potencial medida nas coortes (decisão 96), ou `null`. */
  readonly skillReading = once(async (): Promise<SkillReading | null> => {
    try {
      return await this.skillReadingRepository.reading();
    } catch {
      return null;
    }
  });

  /** A ressalva de cobertura da CVM para a avaliação de um ativo, ou `null`. */
  readonly cvmCoverageNote = perTicker((t) => this.cvm.coverageNote(t));

  /** Contagem oficial de ações do emissor (decisão 83). */
  readonly officialShares = perTicker(async (t): Promise<OfficialShareCount | null> => {
    try {
      return await this.b3Registry.officialSharesFor(t);
    } catch {
      return null;
    }
  });

  /** `true` quando o emissor é de controle estatal hoje (item B46). */
  readonly stateControlled = perTicker(async (t): Promise<boolean> => {
    try {
      return await this.shareholderControlRepository.isStateControlled(t);
    } catch {
      return false;
    }
  });

  /** Fim do contrato de concessão, ou `null` (decisão 88). */
  readonly concessionEnd = perTicker(async (t): Promise<DateTime | null> => {
    try {
      return await this.concessionTermRepository.endFor(t);
    } catch {
      return null;
    }
  });

  /** Proventos da classe: o beta sai do retorno total (decisão 89). */
  readonly dividends = perTicker(async (t): Promise<CashDividend[]> => {
    try {
      return await this.cashDividendsRepository.dividendsFor(t);
    } catch {
      return [];
    }
  });

  /** Ações na unit pela composição declarada na FCA (item B16), ou `null`. */
  readonly declaredSharesPerUnit = perTicker(async (t): Promise<number | null> => {
    try {
      return await this.unitCompositionRepository.sharesPerUnitFor(t);
    } catch {
      return null;
    }
  });

  /** As medianas de múltiplos dos pares (item B5), ou `null`. */
  readonly peerMultiples = perTicker(async (t): Promise<PeerMultipleSet | null> => {
    try {
      return await this.peerMultiplesRepository.forTicker(t);
    } catch {
      return null;
    }
  });

  /** Emissões e eventos de ações (itens B28 e B29). */
  readonly capitalEvents = perTicker(async (t): Promise<CapitalEvents> => {
    try {
      return await this.capitalEventsRepository.eventsFor(t);
    } catch {
      return new CapitalEvents();
    }
  });

  /** A janela que termina hoje e começa [years] anos antes. */
  windowEndingToday(years: number): DateRange {
    const today = this.clock();
    return new DateRange(DateTime.local(today.year - years, today.month, today.day), today);
  }
}
