import { reduce } from '../../lang/iter';
import { tradingDaysPerYear } from './returns';

/**
 * Estatísticas de risco de uma série de retornos.
 *
 * Todas devem ser calculadas sobre a série **TWR neutralizada de aportes**,
 * nunca sobre a curva bruta de patrimônio: no dia do aporte a curva bruta dá
 * um salto que seria contabilizado como retorno de mercado.
 */
export class RiskMetrics {
  /** Desvio-padrão amostral anualizado, em fração. */
  readonly volatility: number;

  /** Pior queda de pico a vale, em fração negativa. */
  readonly maxDrawdown: number;

  /** (CAGR − taxa livre de risco) / volatilidade. */
  readonly sharpe: number;

  /** Como o Sharpe, mas penalizando apenas o desvio negativo. */
  readonly sortino: number;

  /** CAGR / |máximo drawdown|. */
  readonly calmar: number;

  constructor(args: { volatility: number; maxDrawdown: number; sharpe: number; sortino: number; calmar: number }) {
    this.volatility = args.volatility;
    this.maxDrawdown = args.maxDrawdown;
    this.sharpe = args.sharpe;
    this.sortino = args.sortino;
    this.calmar = args.calmar;
  }

  static readonly empty = new RiskMetrics({ volatility: 0, maxDrawdown: 0, sharpe: 0, sortino: 0, calmar: 0 });

  /**
   * Calcula o conjunto a partir do índice TWR e do CAGR já apurado.
   * [riskFreeRate] é a taxa livre de risco **anual** do período — deve vir do
   * CDI observado, não de uma constante.
   */
  static fromIndex(args: {
    twrIndex: readonly number[];
    cagr: number;
    riskFreeRate: number;
    periodsPerYear?: number;
  }): RiskMetrics {
    const { twrIndex, cagr, riskFreeRate } = args;
    const periodsPerYear = args.periodsPerYear ?? tradingDaysPerYear;
    if (twrIndex.length < 2) return RiskMetrics.empty;

    const periodReturns: number[] = [];
    for (let i = 1; i < twrIndex.length; i++) {
      if (twrIndex[i - 1]! > 0) {
        periodReturns.push(twrIndex[i]! / twrIndex[i - 1]! - 1.0);
      }
    }

    const vol = RiskMetrics.annualizedVolatility(periodReturns, { periodsPerYear });
    const downside = RiskMetrics.annualizedDownsideDeviation(periodReturns, { periodsPerYear });
    const mdd = RiskMetrics.maxDrawdownOf(twrIndex);

    const excess = cagr - riskFreeRate;
    return new RiskMetrics({
      volatility: vol,
      maxDrawdown: mdd,
      sharpe: vol > 0 ? excess / vol : 0.0,
      sortino: downside > 0 ? excess / downside : 0.0,
      calmar: mdd < 0 ? cagr / Math.abs(mdd) : 0.0,
    });
  }

  /**
   * Desvio-padrão **amostral** (n−1) anualizado. A série observada é uma
   * amostra do processo gerador, não a população.
   */
  static annualizedVolatility(periodReturns: readonly number[], options: { periodsPerYear?: number } = {}): number {
    const periodsPerYear = options.periodsPerYear ?? tradingDaysPerYear;
    if (periodReturns.length < 2) return 0.0;
    const mean = reduce(periodReturns, (a, b) => a + b) / periodReturns.length;
    let sumSquares = 0.0;
    for (const r of periodReturns) {
      const d = r - mean;
      sumSquares += d * d;
    }
    const variance = sumSquares / (periodReturns.length - 1);
    return Math.sqrt(variance) * Math.sqrt(periodsPerYear);
  }

  /**
   * Semidesvio abaixo de [target], anualizado, pela definição de Sortino e
   * Satchell: `DD = √( (1/N) · Σ min(rᵢ − alvo, 0)² )`. O divisor é o número
   * **total** de observações.
   */
  static annualizedDownsideDeviation(
    periodReturns: readonly number[],
    options: { target?: number; periodsPerYear?: number } = {},
  ): number {
    const target = options.target ?? 0.0;
    const periodsPerYear = options.periodsPerYear ?? tradingDaysPerYear;
    if (periodReturns.length < 2) return 0.0;
    let sumSquares = 0.0;
    for (const r of periodReturns) {
      const shortfall = r - target;
      if (shortfall < 0) sumSquares += shortfall * shortfall;
    }
    if (sumSquares <= 0) return 0.0;
    const variance = sumSquares / periodReturns.length;
    return Math.sqrt(variance) * Math.sqrt(periodsPerYear);
  }

  /** Máximo drawdown, em fração negativa (−0,35 = queda de 35%). */
  static maxDrawdownOf(series: readonly number[]): number {
    if (series.length === 0) return 0.0;
    let peak = series[0]!;
    let worst = 0.0;
    for (const value of series) {
      if (value > peak) peak = value;
      if (peak > 0) {
        const drawdown = (value - peak) / peak;
        if (drawdown < worst) worst = drawdown;
      }
    }
    return worst;
  }
}
