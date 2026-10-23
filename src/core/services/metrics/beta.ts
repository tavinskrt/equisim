import type { DateTime } from '../../lang/date-time';
import { generate, reduce } from '../../lang/iter';
import { toStringAsFixed } from '../../lang/num';
import { ComputationFailure, InsufficientData } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { type PairedReturns, PairedReturnsBuilder } from '../../value-objects/paired-series';

/**
 * Beta estimado localmente, com a janela declarada junto do valor.
 *
 * O beta publicado pela fonte é descartado de propósito: sua janela e seu
 * índice de referência não são documentados, o que é incompatível com
 * reprodutibilidade acadêmica.
 */
export class BetaEstimate {
  /** Coeficiente angular da regressão contra o mercado. `1.0` é neutro. */
  readonly beta: number;

  /** Coeficiente de correlação de Pearson com o mercado. */
  readonly correlation: number;

  /** Quantidade de observações pareadas usadas. */
  readonly observations: number;

  /**
   * Erro-padrão da inclinação. `null` quando não é estimável.
   *
   * **Sai da mesma regressão, e é o que separa beta de número.** A AZUL3
   * devolve `β = 109.108` com `ρ = 0,11` sobre 142 pregões, e erro-padrão de
   * **83.228** (10/09/2026).
   */
  readonly standardError: number | null;

  constructor(args: { beta: number; correlation: number; observations: number; standardError?: number | null }) {
    this.beta = args.beta;
    this.correlation = args.correlation;
    this.observations = args.observations;
    this.standardError = args.standardError ?? null;
  }

  toString(): string {
    return `β=${toStringAsFixed(this.beta, 4)} (ρ=${toStringAsFixed(this.correlation, 3)}, n=${this.observations})`;
  }
}

function pearson(x: readonly number[], y: readonly number[]): number {
  const n = Math.min(x.length, y.length);
  if (n < 2) return 0.0;
  let meanX = 0.0;
  let meanY = 0.0;
  for (let i = 0; i < n; i++) {
    meanX += x[i]!;
    meanY += y[i]!;
  }
  meanX /= n;
  meanY /= n;

  let sxy = 0.0;
  let sxx = 0.0;
  let syy = 0.0;
  for (let i = 0; i < n; i++) {
    const dx = x[i]! - meanX;
    const dy = y[i]! - meanY;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  const denominator = Math.sqrt(sxx * syy);
  return denominator > 0 ? sxy / denominator : 0.0;
}

/**
 * Estimação local de beta e correlação.
 *
 * Todas as estatísticas usam divisor **amostral** (n−1), uniforme com
 * [RiskMetrics].
 *
 * **A correção de negociação não síncrona foi medida e recusada** (decisão
 * 57): Dimson devolve 0,978 do beta diário na mediana dos 127 avaliados, e
 * custa 74% mais erro-padrão. **Se o corte de liquidez for afrouxado, este
 * item volta.** Ver `docs/validacao/beta_sincronia.md`.
 */
export const BetaCalculator = {
  /**
   * β = Cov(R_ativo, R_mercado) / Var(R_mercado).
   *
   * Devolve [InsufficientData] abaixo do mínimo de observações (padrão 30);
   * [ComputationFailure] quando a variância do mercado é nula. A correlação
   * sai `0.0`, e não `NaN`, quando o denominador é nulo.
   */
  estimate(args: { returns: PairedReturns; minimumObservations?: number }): Result<BetaEstimate> {
    const minimumObservations = args.minimumObservations ?? 30;
    const assetReturns = args.returns.asset;
    const marketReturns = args.returns.market;
    const n = args.returns.length;
    if (n < minimumObservations) {
      return err(new InsufficientData(`Beta exige ao menos ${minimumObservations} observações; recebidas ${n}.`));
    }

    const meanAsset = reduce(assetReturns, (a, b) => a + b) / n;
    const meanMarket = reduce(marketReturns, (a, b) => a + b) / n;

    let covariance = 0.0;
    let marketVariance = 0.0;
    let assetVariance = 0.0;
    for (let i = 0; i < n; i++) {
      const assetDeviation = assetReturns[i]! - meanAsset;
      const marketDeviation = marketReturns[i]! - meanMarket;
      covariance += assetDeviation * marketDeviation;
      marketVariance += marketDeviation * marketDeviation;
      assetVariance += assetDeviation * assetDeviation;
    }
    covariance /= n - 1;
    marketVariance /= n - 1;
    assetVariance /= n - 1;

    if (marketVariance <= 0) {
      return err(new ComputationFailure('Variância do mercado nula: série de referência constante.'));
    }

    const beta = covariance / marketVariance;
    const denominator = Math.sqrt(assetVariance * marketVariance);
    const correlation = denominator > 0 ? covariance / denominator : 0.0;

    // `SE(β) = |β| · √((1 − ρ²) / (ρ² · (n − 2)))` — a identidade que liga
    // erro-padrão a correlação e tamanho de amostra.
    const r2 = correlation * correlation;
    const se = n > 2 && r2 > 0 && r2 < 1 ? Math.abs(beta) * Math.sqrt((1 - r2) / (r2 * (n - 2))) : null;

    return ok(
      new BetaEstimate({
        beta,
        correlation,
        observations: n,
        standardError: se !== null && Number.isFinite(se) ? se : null,
      }),
    );
  },

  /**
   * Pareia duas séries datadas pelas datas em comum e devolve os retornos.
   *
   * Datas presentes em apenas uma das séries são **descartadas**, e o retorno
   * é calculado entre pontos consecutivos *do pareamento*. Complexidade O(n + m).
   */
  alignReturns(args: {
    assetDates: readonly DateTime[];
    assetIndex: readonly number[];
    marketDates: readonly DateTime[];
    marketIndex: readonly number[];
  }): PairedReturns {
    const marketByDate = new Map<string, number>();
    for (let i = 0; i < args.marketDates.length; i++) {
      marketByDate.set(args.marketDates[i]!.key, args.marketIndex[i]!);
    }

    const paired = new PairedReturnsBuilder();
    let previousAsset: number | null = null;
    let previousMarket: number | null = null;

    for (let i = 0; i < args.assetDates.length; i++) {
      const marketValue = marketByDate.get(args.assetDates[i]!.key);
      if (marketValue === undefined) continue;
      const assetValue = args.assetIndex[i]!;
      if (previousAsset !== null && previousMarket !== null && previousAsset > 0 && previousMarket > 0) {
        paired.add({
          asset: assetValue / previousAsset - 1.0,
          market: marketValue / previousMarket - 1.0,
        });
      }
      previousAsset = assetValue;
      previousMarket = marketValue;
    }

    return paired.build();
  },

  /**
   * Matriz de correlação entre séries de retorno pareadas. Simétrica `k × k`
   * com diagonal `1.0` (ou `0.0` para séries de menos de dois pontos).
   * Complexidade O(k²·n).
   */
  correlationMatrix(returns: readonly (readonly number[])[]): number[][] {
    const k = returns.length;
    const matrix = generate(k, () => new Array<number>(k).fill(0.0));
    for (let i = 0; i < k; i++) {
      for (let j = i; j < k; j++) {
        const rho = pearson(returns[i]!, returns[j]!);
        matrix[i]![j] = rho;
        matrix[j]![i] = rho;
      }
    }
    return matrix;
  },
};

