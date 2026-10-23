// Regressão múltipla e estatística de ordem para os utilitários de validação.
//
// **Por que não está no núcleo.** `Inference` resolve regressão **simples** —
// é o que as guardas da decisão 25 pedem, e ampliá-la para o caso multivariado
// acrescentaria superfície ao motor por necessidade que é de análise, não de
// avaliação. O núcleo continua com o que a cascata usa.
//
// **Por que não é NumPy.** A máquina do projeto não tem o ecossistema
// científico de Python instalado — conferido em 09/09/2026: nem `numpy`, nem
// `scipy`, nem `statsmodels`. A conferência cruzada que a §2.10 das limitações
// descreve não pôde ser estendida a este arquivo, e isso está declarado no
// relatório que ele alimenta.
//
// O tamanho do problema aqui é pequeno — quatro colunas, algumas centenas de
// linhas — e a solução por equações normais com pivoteamento parcial é exata o
// bastante. Não use isto para sistema mal condicionado sem conferir antes.
import { compareNum, floor } from '../../src/core';

/** Saída de uma regressão múltipla `y = b0 + Σ bj·xj`. */
export interface MultiOls {
  /** Coeficientes, com o intercepto na posição 0. */
  readonly coefficients: number[];
  /** Erros-padrão, alinhados com [coefficients]. */
  readonly stdErrors: number[];
  /** Estatísticas t, alinhadas com [coefficients]. */
  readonly tStats: number[];
  /** Coeficiente de determinação. */
  readonly r2: number;
  /** Observações usadas. */
  readonly n: number;
  /** Resíduos, alinhados com a entrada. */
  readonly residuals: number[];
}

/** Média, desvio e `t` de uma série — o segundo passo de Fama-MacBeth. */
export interface Summary {
  readonly mean: number;
  readonly sd: number;
  readonly t: number;
  readonly n: number;
  readonly positive: number;
}

/**
 * Gerador splitmix64, escrito igual em `tool/recusas_custo.py`.
 *
 * O crítico da sobreposição sai de uma simulação, e as ferramentas e o Python
 * têm de chegar ao mesmo número: o `Math.random` e o `random` do Python são
 * geradores diferentes. Este é pequeno, de período 2⁶⁴ e com a mesma sequência
 * nos dois. Em `BigInt` com `asUintN(64, …)`, que é a aritmética modular do
 * inteiro de 64 bits; o `number` do JavaScript não a tem.
 */
export class SplitMix64 {
  private state: bigint;

  constructor(seed: number | bigint) {
    this.state = BigInt.asUintN(64, BigInt(seed));
  }

  /** Próximo inteiro de 64 bits, sem sinal. */
  nextInt(): bigint {
    this.state = BigInt.asUintN(64, this.state + 0x9e3779b97f4a7c15n);
    let z = this.state;
    z = BigInt.asUintN(64, (z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n);
    z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 0x94d049bb133111ebn);
    return z ^ (z >> 31n);
  }

  /** Uniforme em [0, 1), com os 53 bits altos. */
  nextDouble(): number {
    return Number(this.nextInt() >> 11n) * (1.0 / 9007199254740992);
  }
}

const nullDistributions = new Map<string, number[]>();

/** Estatística que os utilitários de validação compartilham. */
export class Regression {
  /**
   * Postos médios, com empate resolvido pela média das posições.
   *
   * Empate é a regra e não a exceção nestes dados: potencial recusado,
   * fator ausente e retorno truncado produzem valores repetidos, e atribuir
   * posições arbitrárias a eles enviesaria a correlação.
   */
  static ranks(values: readonly number[]): number[] {
    const n = values.length;
    const idx = Array.from({ length: n }, (_, i) => i).sort((a, b) => compareNum(values[a]!, values[b]!));
    const out = new Array<number>(n).fill(0);
    let i = 0;
    while (i < n) {
      let j = i;
      // `compareNum` e não `===`: o empate que interessa é o que a **ordenação
      // acima** considerou empate. Além de evitar igualdade estrita de ponto
      // flutuante, ele dá tratamento determinístico a `-0` contra `0` e a
      // `NaN`, que com `===` cairiam em posições dependentes da ordem de entrada.
      while (j + 1 < n && compareNum(values[idx[j + 1]!]!, values[idx[i]!]!) === 0) j++;
      const mean = (i + j) / 2 + 1;
      for (let k = i; k <= j; k++) out[idx[k]!] = mean;
      i = j + 1;
    }
    return out;
  }

  /** Correlação de Pearson. `null` sem dispersão em qualquer das séries. */
  static pearson(xs: readonly number[], ys: readonly number[]): number | null {
    const n = xs.length;
    if (n < 3 || ys.length !== n) return null;
    let sx = 0;
    let sy = 0;
    for (let i = 0; i < n; i++) {
      sx += xs[i]!;
      sy += ys[i]!;
    }
    const mx = sx / n;
    const my = sy / n;
    let sxy = 0;
    let sxx = 0;
    let syy = 0;
    for (let i = 0; i < n; i++) {
      const dx = xs[i]! - mx;
      const dy = ys[i]! - my;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
    }
    if (sxx <= 0 || syy <= 0) return null;
    return sxy / Math.sqrt(sxx * syy);
  }

  /** Correlação de ordem de Spearman — Pearson sobre os postos. */
  static spearman(xs: readonly number[], ys: readonly number[]): number | null {
    return Regression.pearson(Regression.ranks(xs), Regression.ranks(ys));
  }

  /**
   * Postos reescalados para média zero e desvio um.
   *
   * É a forma em que os coeficientes de uma coorte são comparáveis com os de
   * outra: sem isso, o coeficiente carrega o tamanho da seção transversal.
   */
  static standardizedRanks(values: readonly number[]): number[] {
    const r = Regression.ranks(values);
    const n = r.length;
    // Com `n = 1` a variância divide por zero e devolve `NaN`, e o teste
    // `sd <= 0` abaixo **não** o pega: em IEEE-754 toda comparação com `NaN`
    // é falsa. O retorno seria uma lista de `NaN` que contamina em silêncio
    // todo somatório a jusante.
    if (n < 2) return new Array<number>(n).fill(0);
    let s = 0;
    for (const v of r) s += v;
    const m = s / n;
    let ss = 0;
    for (const v of r) ss += (v - m) * (v - m);
    const sd = Math.sqrt(ss / (n - 1));
    if (sd <= 0) return new Array<number>(n).fill(0);
    return r.map((v) => (v - m) / sd);
  }

  /**
   * Mínimos quadrados com intercepto, por equações normais.
   *
   * - [columns]: regressores, cada um com `n` observações.
   * - [y]: resposta.
   *
   * Devolve `null` quando não há graus de liberdade ou o sistema é singular —
   * o que aqui significa regressor constante ou colinearidade exata.
   */
  static ols(columns: readonly (readonly number[])[], y: readonly number[]): MultiOls | null {
    const n = y.length;
    const k = columns.length + 1;
    if (n <= k) return null;
    for (const c of columns) if (c.length !== n) return null;

    // X'X e X'y, com a coluna de uns na posição 0.
    const x = (j: number, i: number) => (j === 0 ? 1.0 : columns[j - 1]![i]!);

    const xtx = Array.from({ length: k }, () => new Array<number>(k).fill(0));
    const xty = new Array<number>(k).fill(0);
    for (let a = 0; a < k; a++) {
      for (let b = 0; b < k; b++) {
        let s = 0;
        for (let i = 0; i < n; i++) s += x(a, i) * x(b, i);
        xtx[a]![b] = s;
      }
      let s = 0;
      for (let i = 0; i < n; i++) s += x(a, i) * y[i]!;
      xty[a] = s;
    }

    const inv = inverse(xtx);
    if (inv === null) return null;

    const beta = new Array<number>(k).fill(0);
    for (let a = 0; a < k; a++) {
      let s = 0;
      for (let b = 0; b < k; b++) s += inv[a]![b]! * xty[b]!;
      beta[a] = s;
    }

    let sy = 0;
    for (const v of y) sy += v;
    const my = sy / n;
    let sse = 0;
    let sst = 0;
    const res = new Array<number>(n).fill(0);
    for (let i = 0; i < n; i++) {
      let yhat = 0;
      for (let a = 0; a < k; a++) yhat += beta[a]! * x(a, i);
      const e = y[i]! - yhat;
      res[i] = e;
      sse += e * e;
      sst += (y[i]! - my) * (y[i]! - my);
    }
    const sigma2 = sse / (n - k);
    const se = Array.from({ length: k }, (_, a) => Math.sqrt(sigma2 * inv[a]![a]!));

    return {
      coefficients: beta,
      stdErrors: se,
      tStats: se.map((s, a) => (s > 0 ? beta[a]! / s : Number.NaN)),
      r2: sst > 0 ? 1 - sse / sst : Number.NaN,
      n,
      residuals: res,
    };
  }

  /**
   * Resíduo de [target] depois de projetá-lo em [columns].
   *
   * É o que isola a informação **própria** de um ordenador: o que sobra dele
   * quando o que os outros explicam já foi retirado.
   */
  static residualize(target: readonly number[], columns: readonly (readonly number[])[]): number[] | null {
    return Regression.ols(columns, target)?.residuals ?? null;
  }

  /**
   * Média, desvio e `t` de uma série de coeficientes de coorte.
   *
   * É o segundo passo de Fama-MacBeth. **O `t` supõe coortes independentes**,
   * e janelas de 36 meses medidas de ano em ano se sobrepõem em dois terços —
   * quem o lê precisa da ressalva junto.
   */
  static summarize(values: readonly number[]): Summary | null {
    const v = values.filter((x) => Number.isFinite(x));
    if (v.length < 2) return null;
    let s = 0;
    for (const x of v) s += x;
    const m = s / v.length;
    let ss = 0;
    for (const x of v) ss += (x - m) * (x - m);
    const sd = Math.sqrt(ss / (v.length - 1));
    return {
      mean: m,
      sd,
      t: sd > 0 ? m / (sd / Math.sqrt(v.length)) : Number.NaN,
      n: v.length,
      positive: v.filter((x) => x > 0).length,
    };
  }

  /**
   * `t` da média de uma série de coeficientes de coorte com erro-padrão de
   * Newey-West (item C1a).
   *
   * Coortes anuais medidas em 36 meses se sobrepõem por dois anos, e o
   * retorno de uma carrega o choque das duas vizinhas: os coeficientes saem
   * autocorrelados, e o `t` de [summarize] superestima a confiança. A variância
   * de longo prazo soma as autocovariâncias até [lags], com o núcleo de
   * Bartlett `w_j = 1 − j/(L+1)`, que a mantém não negativa:
   *
   * ```
   * V̂(média) = [γ₀ + 2 Σ_{j=1}^{L} w_j γ_j] / k · k/(k−1)
   * γ_j = (1/k) Σ_{t=j+1}^{k} (x_t − x̄)(x_{t−j} − x̄)
   * ```
   *
   * O fator `k/(k−1)` faz `lags = 0` devolver exatamente o `t` de
   * [summarize] — é a conferência de que as duas contas são a mesma no caso
   * sem sobreposição. A ordem dos valores é a das coortes: **a série tem de
   * vir em ordem de data**.
   *
   * Devolve `null` com menos de duas coortes ou variância não positiva.
   */
  static neweyWestMean(values: readonly number[], lags: number): { mean: number; se: number; t: number; n: number; lags: number } | null {
    const v = values.filter((x) => Number.isFinite(x));
    const k = v.length;
    if (k < 2 || lags < 0) return null;
    let s = 0;
    for (const x of v) s += x;
    const m = s / k;
    const gamma = (j: number) => {
      let sum = 0;
      for (let t = j; t < k; t++) sum += (v[t]! - m) * (v[t - j]! - m);
      return sum / k;
    };

    const l = lags < k ? lags : k - 1;
    let lrv = gamma(0);
    for (let j = 1; j <= l; j++) lrv += 2 * (1 - j / (l + 1)) * gamma(j);
    const variance = ((lrv / k) * k) / (k - 1);
    if (!(variance > 0) || !Number.isFinite(variance)) return null;
    const se = Math.sqrt(variance);
    return { mean: m, se, t: m / se, n: k, lags: l };
  }

  /**
   * `t` da média de uma série de coeficientes de coorte **corrigido pela
   * estrutura da sobreposição**, e não estimado dela (item C1c).
   *
   * Coortes trimestrais medidas em 36 meses compartilham até 33 meses de
   * retorno: a coorte `t` e a `t+j` têm correlação `ρ_j = 1 − j/(L+1)` quando o
   * que as move são choques independentes mês a mês, com `L = h/Δ − 1`
   * sobreposições. É a correlação que a sobreposição **produz**, antes de
   * qualquer persistência do sinal. Sob ela, duas coisas erram no `t` de
   * [summarize], e as duas são contas fechadas em `k` e `L`:
   *
   * ```
   * E[s²] = σ² · c,   c = 1 − 2/(k(k−1)) · Σ_{j=1}^{L} (k−j) ρ_j
   * V(média) = σ²/k · F,   F = 1 + 2 Σ_{j=1}^{L} (1 − j/k) ρ_j
   * t corrigido = t de summarize · √(c/F)
   * ```
   *
   * **Por que ao lado do Newey-West, e não no lugar.** O Newey-West estima as
   * autocovariâncias da própria série, e com 22 coortes e 11 defasagens a
   * estimativa é ruído — com cinco coortes anuais ela saiu negativa e
   * estreitou o erro (decisão 93). Esta correção não estima nada: vale o que a
   * sobreposição impõe, e o critério do R3 fica com o menor dos dois.
   *
   * Com `L = 0` devolve o `t` de [summarize]. Devolve `null` com menos de duas
   * coortes, `L` negativo ou desvio nulo.
   */
  static overlapAdjustedT(values: readonly number[], overlap: number): { t: number; c: number; f: number; n: number; overlap: number } | null {
    const base = Regression.summarize(values);
    if (base === null || overlap < 0 || !Number.isFinite(base.t)) return null;
    const k = base.n;
    const l = overlap < k ? overlap : k - 1;
    let sumC = 0;
    let sumF = 0;
    for (let j = 1; j <= l; j++) {
      const rho = 1 - j / (l + 1);
      sumC += (k - j) * rho;
      sumF += (1 - j / k) * rho;
    }
    const c = 1 - (2 / (k * (k - 1))) * sumC;
    const f = 1 + 2 * sumF;
    if (!(c > 0) || !(f > 0)) return null;
    return { t: base.t * Math.sqrt(c / f), c, f, n: k, overlap: l };
  }

  /**
   * Nível unilateral de `t > 2` sob a normal: `1 − Φ(2)`. É o que o critério
   * do R3 pede, escrito como probabilidade.
   */
  static readonly r3Tail = 0.022750131948179195;

  /**
   * Distribuição, sob a hipótese nula, do `t` de [overlapAdjustedT] para `k`
   * coortes com `L` sobreposições: [draws] séries de somas sobrepostas de
   * choques normais independentes, média zero, ordenadas.
   *
   * **Por que simular.** A correção acerta a variância da média, mas o desvio
   * no denominador tem poucos graus de liberdade efetivos, e o `t` corrigido
   * tem cauda mais pesada que a normal — medido: o percentil 95 de `|t|` é
   * 2,66 com 22 coortes e 11 sobreposições, e 3,14 com cinco coortes anuais e
   * duas. O limiar de `t > 2` tem de vir da mesma distribuição. A semente é
   * fixa: o crítico é o mesmo em toda execução.
   */
  static overlapNull(k: number, overlap: number, options: { draws?: number; seed?: number } = {}): number[] {
    const draws = options.draws ?? 20000;
    const seed = options.seed ?? 20260915;
    const l = overlap < k ? overlap : k - 1;
    const key = `${k}|${l}|${draws}|${seed}`;
    const cached = nullDistributions.get(key);
    if (cached !== undefined) return cached;
    const rng = new SplitMix64(seed);
    const normal = () => {
      // Box-Muller: u em (0, 1] para o logaritmo.
      const u = 1 - rng.nextDouble();
      const v = rng.nextDouble();
      return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
    };

    const out: number[] = [];
    const shocks = new Array<number>(k + l).fill(0);
    while (out.length < draws) {
      for (let i = 0; i < shocks.length; i++) shocks[i] = normal();
      const series: number[] = [];
      for (let t = 0; t < k; t++) {
        let sum = 0;
        for (let m = t; m <= t + l; m++) sum += shocks[m]!;
        series.push(sum);
      }
      const r = Regression.overlapAdjustedT(series, l);
      if (r !== null && Number.isFinite(r.t)) out.push(r.t);
    }
    out.sort(compareNum);
    nullDistributions.set(key, out);
    return out;
  }

  /**
   * Crítico unilateral do `t` corrigido com o nível de [tail] — por padrão, o
   * de `t > 2` sob a normal.
   */
  static overlapCritical(k: number, overlap: number, tail: number = Regression.r3Tail): number {
    const nullDistribution = Regression.overlapNull(k, overlap);
    const i = Math.min(Math.max(floor((1 - tail) * nullDistribution.length), 0), nullDistribution.length - 1);
    return nullDistribution[i]!;
  }

  /**
   * Probabilidade unilateral, sob a nula da sobreposição, de um `t` corrigido
   * pelo menos tão alto quanto [t].
   */
  static overlapPValue(t: number, k: number, overlap: number): number {
    const nullDistribution = Regression.overlapNull(k, overlap);
    let lo = 0;
    let hi = nullDistribution.length;
    while (lo < hi) {
      const m = (lo + hi) >> 1;
      if (nullDistribution[m]! < t) lo = m + 1;
      else hi = m;
    }
    return (nullDistribution.length - lo) / nullDistribution.length;
  }
}

/** Inversa por Gauss-Jordan com pivoteamento parcial. `null` se singular. */
function inverse(a: readonly (readonly number[])[]): number[][] | null {
  const n = a.length;
  const m = a.map((row, i) => [...row, ...Array.from({ length: n }, (_, j) => (i === j ? 1.0 : 0.0))]);
  for (let c = 0; c < n; c++) {
    let piv = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(m[r]![c]!) > Math.abs(m[piv]![c]!)) piv = r;
    if (Math.abs(m[piv]![c]!) < 1e-12) return null;
    const tmp = m[c]!;
    m[c] = m[piv]!;
    m[piv] = tmp;
    const d = m[c]![c]!;
    for (let j = 0; j < 2 * n; j++) m[c]![j]! /= d;
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      // Sem atalho para multiplicador nulo: pular exigiria comparar um
      // `number` com zero, e a subtração de `0 · x` não custa nada numa
      // matriz desta ordem. O atalho era economia de nada paga com
      // igualdade estrita de ponto flutuante.
      const f = m[r]![c]!;
      for (let j = 0; j < 2 * n; j++) m[r]![j]! -= f * m[c]![j]!;
    }
  }
  return m.map((row) => row.slice(n));
}
