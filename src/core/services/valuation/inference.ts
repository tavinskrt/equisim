/**
 * Primitivas de inferência para as guardas da cascata de avaliação.
 *
 * **Por que existe.** As guardas da decisão 25 substituem limiares fixos por
 * estatísticas derivadas do próprio ativo, e isso exige regressão, erro-padrão
 * robusto e quantil da t de Student. O núcleo é TypeScript puro com zero
 * dependências de runtime — travado por `test/core/purity.test.ts` —, então
 * nada disso pode vir de pacote.
 *
 * **O limite que estas funções não superam.** A série de fundamentos tem no
 * máximo 16 exercícios. Tudo aqui é assintoticamente justificado e nenhum
 * p-valor deve ser lido como probabilidade exata: são estatísticas de
 * **triagem**, calibradas para separar casos, não para inferência publicável.
 * Medido: com `n = 8`, o estimador HAC chegou a inflar `|t|` em 2,2 vezes,
 * porque monta a variância a partir de somas de 6 e 7 termos. É a razão de o
 * teste de tendência rodar sobre a série completa, e não sobre a janela do
 * ciclo.
 */

import { floor, intDiv, max } from '../../lang/num';
import { sortedNums } from '../../lang/iter';

/** Saída de uma regressão linear simples `y = b0 + b1·x`. */
export class OlsFit {
  /** Inclinação estimada. */
  readonly slope: number;

  /** Intercepto estimado. */
  readonly intercept: number;

  /** Resíduos, alinhados posição a posição com a entrada. */
  readonly residuals: readonly number[];

  /** Coeficiente de determinação. */
  readonly r2: number;

  /** Erro-padrão da inclinação, sob homocedasticidade. */
  readonly slopeStdError: number;

  /** `Σ(x − x̄)²`. Viaja porque o estimador HAC precisa dele. */
  readonly sxx: number;

  /** Erro-padrão da regressão, `√(Σê²/(n−2))`. */
  readonly residualStdError: number;

  /** Observações efetivamente usadas. */
  readonly n: number;

  constructor(args: {
    slope: number;
    intercept: number;
    residuals: readonly number[];
    r2: number;
    slopeStdError: number;
    sxx: number;
    residualStdError: number;
    n: number;
  }) {
    this.slope = args.slope;
    this.intercept = args.intercept;
    this.residuals = args.residuals;
    this.r2 = args.r2;
    this.slopeStdError = args.slopeStdError;
    this.sxx = args.sxx;
    this.residualStdError = args.residualStdError;
    this.n = args.n;
  }

  /** Graus de liberdade do teste da inclinação. */
  get degreesOfFreedom(): number {
    return this.n - 2;
  }
}

function tCdf(t: number, df: number): number {
  const x = df / (df + t * t);
  const p = 0.5 * incompleteBeta(df / 2.0, 0.5, x);
  return t > 0 ? 1.0 - p : p;
}

/** Beta incompleta regularizada `I_x(a, b)`, por fração continuada. */
function incompleteBeta(a: number, b: number, x: number): number {
  if (x <= 0) return 0.0;
  if (x >= 1) return 1.0;
  const lb = lnGamma(a + b) - lnGamma(a) - lnGamma(b) + a * Math.log(x) + b * Math.log(1 - x);
  if (x < (a + 1) / (a + b + 2)) {
    return (Math.exp(lb) * betaContinuedFraction(a, b, x)) / a;
  }
  return 1.0 - (Math.exp(lb) * betaContinuedFraction(b, a, 1 - x)) / b;
}

function betaContinuedFraction(a: number, b: number, x: number): number {
  const maxIt = 200;
  const eps = 3e-16;
  const fpMin = 1e-300;
  const qab = a + b;
  const qap = a + 1.0;
  const qam = a - 1.0;
  let c = 1.0;
  let d = 1.0 - (qab * x) / qap;
  if (Math.abs(d) < fpMin) d = fpMin;
  d = 1.0 / d;
  let h = d;
  for (let m = 1; m <= maxIt; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1.0 + aa * d;
    if (Math.abs(d) < fpMin) d = fpMin;
    c = 1.0 + aa / c;
    if (Math.abs(c) < fpMin) c = fpMin;
    d = 1.0 / d;
    h *= d * c;
    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1.0 + aa * d;
    if (Math.abs(d) < fpMin) d = fpMin;
    c = 1.0 + aa / c;
    if (Math.abs(c) < fpMin) c = fpMin;
    d = 1.0 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1.0) < eps) break;
  }
  return h;
}

const LANCZOS_COEFFICIENTS: readonly number[] = [
  76.18009172947146,
  -86.50532032941677,
  24.01409824083091,
  -1.231739572450155,
  0.1208650973866179e-2,
  -0.5395239384953e-5,
];

/** Logaritmo da função gama, por aproximação de Lanczos. */
function lnGamma(x: number): number {
  let y = x;
  const tmp = x + 5.5 - (x + 0.5) * Math.log(x + 5.5);
  let ser = 1.000000000190015;
  for (let j = 0; j < 6; j++) {
    ser += LANCZOS_COEFFICIENTS[j]! / ++y;
  }
  return -tmp + Math.log((2.5066282746310005 * ser) / x);
}

/** Estatística descritiva e inferencial sem dependência externa. */
export const Inference = {
  /**
   * Mediana de [values]. Devolve `null` para lista vazia.
   *
   * Preferida à média em toda a cascata: o ponto de ruptura da média é `1/n`,
   * e o exercício atípico que se quer conter é justamente o que a desloca.
   */
  median(values: readonly number[]): number | null {
    if (values.length === 0) return null;
    const s = sortedNums(values);
    const m = intDiv(s.length, 2);
    return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
  },

  /**
   * Desvio absoluto mediano escalado, estimador robusto de escala.
   *
   * O fator `1,4826 = 1/Φ⁻¹(0,75)` torna o MAD consistente com o desvio-padrão
   * sob normalidade. Ponto de ruptura de 50%: metade da amostra pode estar
   * contaminada sem mover o resultado.
   *
   * Devolve `null` quando a amostra é curta demais ou colapsa num ponto — caso
   * em que não há escala a estimar, e o chamador deve tratar como ausência.
   */
  scaledMad(values: readonly number[]): number | null {
    if (values.length < 3) return null;
    const m = Inference.median(values);
    if (m === null) return null;
    const deviations = values.map((v) => Math.abs(v - m));
    const mad = Inference.median(deviations);
    if (mad === null || mad <= 0) return null;
    const s = 1.4826 * mad;
    return Number.isFinite(s) && s > 0 ? s : null;
  },

  /**
   * Regressão linear simples por mínimos quadrados.
   *
   * Devolve `null` com menos de três pontos ou sem dispersão em `x`, casos em
   * que a inclinação não é identificável.
   */
  ols(xs: readonly number[], ys: readonly number[]): OlsFit | null {
    const n = xs.length;
    if (n < 3 || ys.length !== n) return null;

    let mx = 0.0;
    let my = 0.0;
    for (let i = 0; i < n; i++) {
      mx += xs[i]!;
      my += ys[i]!;
    }
    mx /= n;
    my /= n;

    let sxx = 0.0;
    let sxy = 0.0;
    let syy = 0.0;
    for (let i = 0; i < n; i++) {
      const dx = xs[i]! - mx;
      const dy = ys[i]! - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    if (sxx <= 0) return null;

    const b1 = sxy / sxx;
    const b0 = my - b1 * mx;
    const res: number[] = [];
    for (let i = 0; i < n; i++) res.push(ys[i]! - (b0 + b1 * xs[i]!));

    let sse = 0.0;
    for (const e of res) {
      sse += e * e;
    }
    const s2 = sse / (n - 2);
    const syx = Math.sqrt(s2);
    const seB1 = Math.sqrt(s2 / sxx);
    const r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : 0.0;

    if (!Number.isFinite(b1) || !Number.isFinite(seB1)) return null;
    return new OlsFit({
      slope: b1,
      intercept: b0,
      residuals: res,
      r2,
      slopeStdError: seB1,
      sxx,
      residualStdError: syx,
      n,
    });
  },

  /**
   * Erro-padrão da inclinação robusto a heterocedasticidade e autocorrelação.
   *
   * Estimador de Newey-West com núcleo de Bartlett:
   *
   * ```
   * V̂(β̂₁) = S_xx⁻¹ · Ω̂ · S_xx⁻¹
   * Ω̂ = Σ x_t² ê_t² + 2 Σ_{j=1}^{L} w_j Σ_t x_t ê_t x_{t−j} ê_{t−j}
   * w_j = 1 − j/(L+1)
   * ```
   *
   * A banda segue a regra `L = ⌊4(n/100)^{2/9}⌋`, e Ω̂ recebe a correção de
   * amostra pequena `n/(n−2)`. Os pesos de Bartlett garantem `Ω̂ ≥ 0`, o que
   * impede variância negativa — o motivo de o núcleo triangular ser o padrão.
   *
   * Devolve `null` quando a variância estimada não é utilizável.
   */
  hacSlopeStdError(xs: readonly number[], fit: OlsFit): number | null {
    const n = fit.n;
    if (xs.length !== n || n < 4) return null;

    let mx = 0.0;
    for (const x of xs) {
      mx += x;
    }
    mx /= n;
    const x = xs.map((v) => v - mx);
    const e = fit.residuals;

    const l = max(1, floor(4 * Math.pow(n / 100.0, 2 / 9)));

    let omega = 0.0;
    for (let t = 0; t < n; t++) {
      const xe = x[t]! * e[t]!;
      omega += xe * xe;
    }
    for (let j = 1; j <= l && j < n; j++) {
      const w = 1.0 - j / (l + 1.0);
      let sum = 0.0;
      for (let t = j; t < n; t++) {
        sum += x[t]! * e[t]! * x[t - j]! * e[t - j]!;
      }
      omega += 2.0 * w * sum;
    }
    omega *= n / (n - 2.0);

    if (omega <= 0 || !Number.isFinite(omega)) return null;
    const se = Math.sqrt(omega) / fit.sxx;
    return Number.isFinite(se) && se > 0 ? se : null;
  },

  /**
   * Quantil da distribuição t de Student com [df] graus de liberdade.
   *
   * Obtido invertendo a função beta incompleta regularizada por bissecção.
   * Conferido contra tabela: `t(14; 0,975) = 2,1448`, `t(6; 0,975) = 2,4469`,
   * `t(10; 0,95) = 1,8125`.
   *
   * - [p]: probabilidade acumulada, em `(0, 1)`.
   * - [df]: graus de liberdade, ao menos 1.
   */
  studentT(p: number, df: number): number {
    if (df < 1 || p <= 0 || p >= 1) return Number.NaN;
    if (p < 0.5) return -Inference.studentT(1 - p, df);

    let lo = 0.0;
    let hi = 1e3;
    for (let i = 0; i < 200; i++) {
      const mid = (lo + hi) / 2;
      if (tCdf(mid, df) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  },

  /**
   * R² crítico de uma regressão simples, ao nível [alpha].
   *
   * Da identidade `F = [R²/(1−R²)]·(n−2)` com um só regressor, `F = t²`, o que
   * dá em forma fechada:
   *
   * ```
   * R²_crit(n, α) = t² / (t² + n − 2),   t = t_{n−2, 1−α/2}
   * ```
   *
   * Existe para tornar visível por que um limiar fixo não serve: com `n = 8` o
   * valor é 0,50, e com `n = 16` é 0,25. Um corte único é simultaneamente laxo
   * numa ponta e estrito na outra.
   */
  criticalR2(n: number, alpha: number): number {
    if (n < 3) return 1.0;
    const df = n - 2;
    const t = Inference.studentT(1 - alpha / 2, df);
    const t2 = t * t;
    return t2 / (t2 + df);
  },
};
