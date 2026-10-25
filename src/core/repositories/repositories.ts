/**
 * Contratos de repositório do núcleo. A camada de dados os implementa; o
 * núcleo só os declara, e por isso continua sem rede nem I/O.
 */

import type { Asset } from '../entities/asset';
import type { FundamentalsSnapshot } from '../entities/fundamentals';
import type { PriceSeries } from '../entities/price-series';
import type { Result } from '../failures/result';
import { DartEnum } from '../lang/dart-enum';
import type { DateTime } from '../lang/date-time';
import type { DateRange } from '../value-objects/date-range';
import type { Ticker } from '../value-objects/ticker';

/**
 * Frequência de uma série de taxas, e quantos períodos dela cabem num ano.
 * **Existe para que a base não viaje por parâmetro** (decisão 59).
 */
export class TimeBasis extends DartEnum {
  /** Dias úteis, base em que o BCB publica o CDI. */
  static readonly businessDaily = new TimeBasis('businessDaily', 0, 252);

  /** Meses, base do IPCA e do IBC-Br. */
  static readonly monthly = new TimeBasis('monthly', 1, 12);

  static readonly values: readonly TimeBasis[] = [TimeBasis.businessDaily, TimeBasis.monthly];

  /** Períodos desta base que cabem num ano. */
  readonly periodsPerYear: number;

  private constructor(name: string, index: number, periodsPerYear: number) {
    super(name, index);
    this.periodsPerYear = periodsPerYear;
  }

  protected get typeName(): string {
    return 'TimeBasis';
  }
}

/**
 * Um ponto de uma série de taxas: a data e a taxa daquele período. **Existe
 * para que a data e a taxa não possam se separar** (decisão 59).
 */
export class RatePoint {
  /** Data do período. */
  readonly date: DateTime;

  /** Taxa do período, em fração (0.0004 = 0,04% no dia). */
  readonly rate: number;

  constructor(args: { date: DateTime; rate: number }) {
    this.date = args.date;
    this.rate = args.rate;
  }
}

/** Série de taxas (CDI, IPCA), já convertidas para fração. */
export class RateSeries {
  /** Pontos da série, **em ordem de data**. */
  readonly points: readonly RatePoint[];

  /** Frequência dos pontos. É ela que define a base da anualização. */
  readonly basis: TimeBasis;

  /**
   * Declara a série, **ordenando por data**, como `PriceSeries` faz: com os
   * pontos fora de ordem, [tail] recortaria a fatia errada em silêncio.
   */
  constructor(points: readonly RatePoint[], options: { basis?: TimeBasis } = {}) {
    this.points = Object.freeze([...points].sort((a, b) => a.date.compareTo(b.date)));
    this.basis = options.basis ?? TimeBasis.businessDaily;
  }

  /** Datas dos períodos. **Vista derivada.** */
  get dates(): DateTime[] {
    return this.points.map((p) => p.date);
  }

  /** Taxas dos períodos. **Vista derivada.** */
  get rates(): number[] {
    return this.points.map((p) => p.rate);
  }

  /** `true` quando não há nenhum ponto. */
  get isEmpty(): boolean {
    return this.points.length === 0;
  }

  /** Os [n] últimos pontos, ou a série inteira se ela for mais curta. */
  tail(n: number): RateSeries {
    return n >= this.points.length
      ? this
      : new RateSeries(this.points.slice(this.points.length - n), { basis: this.basis });
  }

  /** Fator acumulado do período: `Π(1 + rᵢ) − 1`. */
  get accumulated(): number {
    let factor = 1.0;
    for (const p of this.points) factor *= 1 + p.rate;
    return factor - 1;
  }

  /**
   * Taxa anual equivalente, na base que a própria série declara, por
   * **composição** sobre o fator acumulado. `0.0` para série vazia e `-1.0`
   * quando o fator acumulado é não positivo.
   */
  annualized(): number {
    if (this.points.length === 0) return 0.0;
    const years = this.points.length / this.basis.periodsPerYear;
    if (years <= 0) return 0.0;
    const factor = 1 + this.accumulated;
    if (factor <= 0) return -1.0;
    return Math.pow(factor, 1 / years) - 1;
  }
}

/**
 * Acesso a cotações. Ausência de dado é [Result] de falha, **nunca exceção
 * nem lista vazia**. A série devolvida pode ser mais curta que a janela pedida.
 */
export interface PriceRepository {
  /** Cotações diárias de um ativo na janela pedida, pontas inclusivas. */
  daily(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>>;

  /** Busca em lote. O mapa devolvido pode ser **parcial**. */
  dailyBatch(tickers: readonly Ticker[], range: DateRange): Promise<Result<Map<Ticker, PriceSeries>>>;

  /** `adjustedClose` bruto da fonte — **apenas conferência**, nunca cálculo. */
  adjustedCloseRaw(ticker: Ticker, range: DateRange): Promise<Result<PriceSeries>>;
}

/**
 * Acesso a fundamentos. Devolve a série completa; o recorte temporal é
 * responsabilidade de `PointInTimeView`.
 */
export interface FundamentalsRepository {
  /** Todos os exercícios disponíveis do ativo, em ordem cronológica. */
  history(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>>;

  /** Cadastro do ativo: nome, setor, subsetor. */
  profile(ticker: Ticker): Promise<Result<Asset>>;

  /** Universo de ativos negociáveis. */
  universe(): Promise<Result<Ticker[]>>;
}

/** Séries macroeconômicas. */
export interface MacroRepository {
  /** CDI diário, em fração, na base de dias úteis. */
  riskFreeDaily(range: DateRange): Promise<Result<RateSeries>>;

  /** IPCA mensal, em fração. */
  inflationMonthly(range: DateRange): Promise<Result<RateSeries>>;

  /** IBC-Br mensal, em variação. */
  activityIndexMonthly(range: DateRange): Promise<Result<RateSeries>>;
}

/** Índice de referência. */
export interface BenchmarkRepository {
  /** Série do Ibovespa na janela pedida. */
  ibovespa(range: DateRange): Promise<Result<PriceSeries>>;
}
