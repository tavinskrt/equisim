/**
 * Faixa calibrada do preço justo (decisão 92): a incerteza medida nas coortes
 * de validação, e não a imaginada pelos cenários.
 */

import type { PriceSeries } from '../../entities/price-series';
import { isJsonObject, type JsonObject } from '../../lang/json';
import { isInt } from '../../lang/num';
import { Money } from '../../value-objects/money';
import { tradingDaysPerYear } from '../metrics/returns';
import { RiskMetrics } from '../metrics/risk-metrics';

interface BandTableCommon {
  months: number;
  nominal: number;
  observations: number;
  firstCohort: number;
  lastCohort: number;
  outOfSampleCoverage: number | null;
  outOfSampleObservations: number;
}

/**
 * Tabela de uma faixa calibrada, para um horizonte e uma cobertura nominal.
 *
 * **Fechada em duas formas.** A v1 multiplica o preço justo por dois fatores
 * fixos; a v2 desloca o preço de mercado pelo desconto que o modelo mede e
 * abre a faixa pela volatilidade do próprio ativo.
 */
export abstract class CalibratedBandTable {
  /** Horizonte da faixa, em meses. */
  readonly months: number;

  /** Cobertura nominal — `0,80` quer dizer que 80% das coortes caíram dentro. */
  readonly nominal: number;

  /** Observações que calibraram a tabela. */
  readonly observations: number;

  /** Ano da primeira coorte usada na calibragem. */
  readonly firstCohort: number;

  /** Ano da última coorte usada na calibragem. */
  readonly lastCohort: number;

  /** Cobertura medida **fora da amostra** de calibragem, ou `null` sem coorte reservada. */
  readonly outOfSampleCoverage: number | null;

  /** Observações fora da amostra. */
  readonly outOfSampleObservations: number;

  protected constructor(args: BandTableCommon) {
    this.months = args.months;
    this.nominal = args.nominal;
    this.observations = args.observations;
    this.firstCohort = args.firstCohort;
    this.lastCohort = args.lastCohort;
    this.outOfSampleCoverage = args.outOfSampleCoverage;
    this.outOfSampleObservations = args.outOfSampleObservations;
  }

  /** `true` quando os parâmetros formam uma faixa de verdade. */
  abstract get isUsable(): boolean;
}

/** Faixa v1: `[justo × fatorInferior, justo × fatorSuperior]`. */
export class FairValueBandTable extends CalibratedBandTable {
  readonly lowerFactor: number;
  readonly upperFactor: number;

  constructor(args: BandTableCommon & { lowerFactor: number; upperFactor: number }) {
    super(args);
    this.lowerFactor = args.lowerFactor;
    this.upperFactor = args.upperFactor;
  }

  override get isUsable(): boolean {
    return (
      Number.isFinite(this.lowerFactor) &&
      Number.isFinite(this.upperFactor) &&
      this.lowerFactor > 0 &&
      this.upperFactor > this.lowerFactor
    );
  }
}

/**
 * Faixa v2: `P₀ · exp(a + b·ln(justo/P₀) + σ·z)`.
 *
 * `a` e `b` medem quanto do desconto apontado pelo modelo o mercado fechou no
 * horizonte; `σ` é a volatilidade anual do próprio ativo; `z` são os quantis
 * empíricos do resíduo padronizado.
 */
export class VolatilityBandTable extends CalibratedBandTable {
  readonly a: number;
  readonly b: number;
  readonly zLower: number;
  readonly zUpper: number;

  constructor(args: BandTableCommon & { a: number; b: number; zLower: number; zUpper: number }) {
    super(args);
    this.a = args.a;
    this.b = args.b;
    this.zLower = args.zLower;
    this.zUpper = args.zUpper;
  }

  override get isUsable(): boolean {
    return (
      Number.isFinite(this.a) &&
      Number.isFinite(this.b) &&
      Number.isFinite(this.zLower) &&
      Number.isFinite(this.zUpper) &&
      this.zUpper > this.zLower
    );
  }
}

/** Aplicação da faixa calibrada ao preço justo de um ativo. */
export const CalibratedBand = {
  /** Janela da volatilidade: um ano de pregões. */
  volatilityWindow: tradingDaysPerYear,

  /** Mínimo de retornos na janela para a volatilidade valer. */
  volatilityMinimumReturns: 120,

  /**
   * Volatilidade anual dos log-retornos do último ano, ou `null` com menos de
   * [volatilityMinimumReturns] retornos válidos.
   */
  trailingVolatility(prices: PriceSeries): number | null {
    const pts = prices.points;
    const start = Math.max(1, pts.length - CalibratedBand.volatilityWindow);
    const returns: number[] = [];
    for (let i = start; i < pts.length; i++) {
      const prev = pts[i - 1]!;
      const cur = pts[i]!;
      if (prev.close > 0 && cur.close > 0) returns.push(Math.log(cur.close / prev.close));
    }
    if (returns.length < CalibratedBand.volatilityMinimumReturns) return null;
    const v = RiskMetrics.annualizedVolatility(returns);
    return Number.isFinite(v) ? v : null;
  },

  /**
   * Faixa para [fairValue], ou `null` quando ela não se forma.
   *
   * A v2 exige [marketPrice] positivo e [volatility] finita e positiva: sem
   * elas a faixa é recusada, e não aproximada.
   */
  of(
    fairValue: Money,
    table: CalibratedBandTable,
    options: { marketPrice?: Money | null; volatility?: number | null } = {},
  ): { low: Money; high: Money } | null {
    if (fairValue.cents <= 0 || !table.isUsable) return null;
    if (table instanceof FairValueBandTable) {
      return { low: fairValue.times(table.lowerFactor), high: fairValue.times(table.upperFactor) };
    }
    if (table instanceof VolatilityBandTable) {
      const p0 = options.marketPrice?.reais ?? null;
      const volatility = options.volatility ?? null;
      if (p0 === null || p0 <= 0 || volatility === null || !Number.isFinite(volatility)) {
        return null;
      }
      if (volatility <= 0) return null;
      const center = table.a + table.b * Math.log(fairValue.reais / p0);
      const low = p0 * Math.exp(center + volatility * table.zLower);
      const high = p0 * Math.exp(center + volatility * table.zUpper);
      if (!Number.isFinite(low) || !Number.isFinite(high) || low <= 0) return null;
      return { low: Money.fromReais(low), high: Money.fromReais(high) };
    }
    return null;
  },

  /** Tabela do horizonte [months] e da cobertura [nominal], ou `null`. */
  select(
    tables: readonly CalibratedBandTable[],
    args: { months: number; nominal: number },
  ): CalibratedBandTable | null {
    for (const t of tables) {
      if (t.months === args.months && Math.abs(t.nominal - args.nominal) < 0.005) return t;
    }
    return null;
  },
};

/** Leitura do pacote `assets/validacao/faixa_calibrada.json`. */
export const CalibratedBandCodec = {
  fairValueVersion: 1,
  volatilityVersion: 2,

  /**
   * Tabelas utilizáveis do pacote. Versão desconhecida devolve lista vazia;
   * linha malformada ou inutilizável é descartada sozinha.
   */
  decode(pkg: JsonObject): CalibratedBandTable[] {
    const version = pkg['versao'];
    if (version !== CalibratedBandCodec.fairValueVersion && version !== CalibratedBandCodec.volatilityVersion) {
      return [];
    }
    const bands = pkg['faixas'];
    if (!Array.isArray(bands)) return [];
    const out: CalibratedBandTable[] = [];
    for (const f of bands) {
      if (!isJsonObject(f)) continue;
      const months = f['meses'];
      const nominal = f['nominal'];
      const observations = f['observacoes'];
      const first = f['primeiraCoorte'];
      const last = f['ultimaCoorte'];
      const outside = f['coberturaForaDaAmostra'];
      const outOfSampleCount = f['observacoesForaDaAmostra'];
      if (
        !isInt(months) ||
        typeof nominal !== 'number' ||
        !isInt(observations) ||
        !isInt(first) ||
        !isInt(last) ||
        (outside !== null && outside !== undefined && typeof outside !== 'number') ||
        !isInt(outOfSampleCount)
      ) {
        continue;
      }
      const common: BandTableCommon = {
        months,
        nominal,
        observations,
        firstCohort: first,
        lastCohort: last,
        outOfSampleCoverage: typeof outside === 'number' ? outside : null,
        outOfSampleObservations: outOfSampleCount,
      };
      let t: CalibratedBandTable;
      if (version === CalibratedBandCodec.fairValueVersion) {
        const lower = f['fatorInferior'];
        const upper = f['fatorSuperior'];
        if (typeof lower !== 'number' || typeof upper !== 'number') continue;
        t = new FairValueBandTable({ ...common, lowerFactor: lower, upperFactor: upper });
      } else {
        const a = f['a'];
        const b = f['b'];
        const zi = f['zInferior'];
        const zs = f['zSuperior'];
        if (typeof a !== 'number' || typeof b !== 'number' || typeof zi !== 'number' || typeof zs !== 'number') {
          continue;
        }
        t = new VolatilityBandTable({ ...common, a, b, zLower: zi, zUpper: zs });
      }
      if (t.isUsable) out.push(t);
    }
    return out;
  },
};
