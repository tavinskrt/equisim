// Conferência da estatística usada pelos utilitários de validação.
//
// `tool/validation/regression.ts` foi escrito à mão porque a máquina do
// projeto não tem NumPy nem statsmodels. Sem conferência, ele seria uma
// segunda implementação não verificada logo abaixo de um núcleo que fez
// questão de verificar a primeira.
//
// **A referência é o próprio núcleo.** `Inference.ols` já está conferido
// contra `statsmodels` na ordem de 1e-14 (docs/validacao/conferencia_inferencia.md),
// e no caso de **um** regressor a regressão múltipla tem de reproduzi-lo
// exatamente — inclusive erro-padrão e R². É referência independente de
// verdade, e não a mesma conta escrita duas vezes: os caminhos são diferentes
// (fórmula fechada de mínimos quadrados simples contra inversão de X'X).
import { describe, expect, it } from 'vitest';

import { Inference, SeededRandom } from '../../src/core';
import { Regression, SplitMix64 } from '../../tool/validation/regression';
import { expectClose } from '../core/helpers';

describe('Regression.ols contra Inference.ols do núcleo', () => {
  it('reproduz inclinação, intercepto, erro-padrão e R² com 1 regressor', () => {
    const xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    const ys = [2.1, 3.9, 6.2, 7.8, 10.3, 11.9, 14.4, 15.8, 18.1, 20.4, 21.7, 24.2];

    const reference = Inference.ols(xs, ys)!;
    const measured = Regression.ols([xs], ys)!;

    expectClose(measured.coefficients[1], reference.slope, 1e-10);
    expectClose(measured.coefficients[0], reference.intercept, 1e-10);
    expectClose(measured.stdErrors[1], reference.slopeStdError, 1e-10);
    expectClose(measured.r2, reference.r2, 1e-10);
    expect(measured.n).toBe(reference.n);
  });

  it('recupera coeficientes conhecidos sem resíduo', () => {
    // y = 3 + 2·x1 − 0,5·x2, exato. Um solucionador correto devolve os três
    // com R² igual a 1.
    const x1 = [1, 2, 3, 4, 5, 6, 7, 8];
    const x2 = [4, 1, 7, 2, 9, 3, 8, 5];
    const y = x1.map((v, i) => 3 + 2 * v - 0.5 * x2[i]!);

    const f = Regression.ols([x1, x2], y)!;
    expectClose(f.coefficients[0], 3.0, 1e-9);
    expectClose(f.coefficients[1], 2.0, 1e-9);
    expectClose(f.coefficients[2], -0.5, 1e-9);
    expectClose(f.r2, 1.0, 1e-9);
  });

  it('devolve nulo em colinearidade exata', () => {
    const x1 = [1, 2, 3, 4, 5, 6];
    const x2 = x1.map((v) => 2 * v);
    expect(Regression.ols([x1, x2], [1, 2, 3, 4, 5, 7])).toBeNull();
  });

  it('devolve nulo sem graus de liberdade', () => {
    expect(
      Regression.ols(
        [
          [1.0, 2.0],
          [3.0, 1.0],
        ],
        [1.0, 2.0],
      ),
    ).toBeNull();
  });
});

describe('postos e correlação de ordem', () => {
  it('empate recebe a média das posições', () => {
    expect(Regression.ranks([10, 20, 20, 40])).toEqual([1.0, 2.5, 2.5, 4.0]);
  });

  it('Spearman é 1 em transformação monótona', () => {
    const xs = [1, 2, 3, 4, 5, 6, 7];
    const ys = xs.map((v) => v * v * v);
    expectClose(Regression.spearman(xs, ys), 1.0, 1e-12);
  });

  it('Spearman é −1 na ordem invertida', () => {
    expectClose(Regression.spearman([1, 2, 3, 4, 5], [5, 4, 3, 2, 1]), -1.0, 1e-12);
  });

  it('amostra unitária não devolve NaN silencioso', () => {
    // Com n = 1 a variância divide por zero. O `NaN` resultante atravessaria
    // qualquer guarda escrita como `sd <= 0`, porque toda comparação com
    // `NaN` é falsa, e contaminaria os somatórios a jusante.
    const z = Regression.standardizedRanks([7.0]);
    expect(z).toHaveLength(1);
    expect(Number.isNaN(z[0])).toBe(false);
    expect(z[0]).toBe(0.0);
    expect(Regression.standardizedRanks([])).toEqual([]);
  });

  it('postos padronizados têm média zero e desvio um', () => {
    const z = Regression.standardizedRanks([3, 1, 4, 1, 5, 9, 2, 6]);
    const mean = z.reduce((a, b) => a + b) / z.length;
    let ss = 0.0;
    for (const v of z) ss += (v - mean) * (v - mean);
    expectClose(mean, 0.0, 1e-12);
    expectClose(ss / (z.length - 1), 1.0, 1e-12);
  });
});

describe('Regression.residualize', () => {
  it('resíduo é ortogonal aos regressores', () => {
    const x1 = [1, 3, 2, 5, 4, 7, 6, 9, 8, 10];
    const target = [2, 5, 3, 9, 6, 14, 11, 20, 15, 21];
    const r = Regression.residualize(target, [x1])!;
    let product = 0.0;
    let sum = 0.0;
    for (let i = 0; i < r.length; i++) {
      product += r[i]! * x1[i]!;
      sum += r[i]!;
    }
    expectClose(product, 0.0, 1e-9);
    expectClose(sum, 0.0, 1e-9);
  });
});

describe('Regression.summarize', () => {
  it('média, desvio e t de uma série conhecida', () => {
    const s = Regression.summarize([0.1, 0.2, 0.3, 0.4, 0.5])!;
    expectClose(s.mean, 0.3, 1e-12);
    // desvio amostral de {0,1..0,5} é 0,1581138830...
    expectClose(s.sd, 0.15811388300841897, 1e-12);
    expectClose(s.t, 0.3 / (0.15811388300841897 / 2.23606797749979), 1e-9);
    expect(s.positive).toBe(5);
  });
});

describe('Regression.neweyWestMean — item C1a', () => {
  it('sem defasagem é exatamente o t de summarize', () => {
    const v = [0.12, -0.03, 0.08, 0.15, 0.02, 0.07];
    const naive = Regression.summarize(v)!;
    const nw = Regression.neweyWestMean(v, 0)!;
    expectClose(nw.mean, naive.mean, 1e-15);
    expectClose(nw.t, naive.t, 1e-12);
  });

  it('reproduz a conta à mão com uma defasagem', () => {
    // {1..5}: média 3; γ₀ = 10/5 = 2; γ₁ = (2 + 0 + 0 + 2)/5 = 0,8;
    // w₁ = 1/2; variância de longo prazo 2 + 2·½·0,8 = 2,8; da média,
    // 2,8/5 · 5/4 = 0,7.
    const nw = Regression.neweyWestMean([1, 2, 3, 4, 5], 1)!;
    expectClose(nw.se, 0.8366600265340756, 1e-12);
    expectClose(nw.t, 3 / 0.8366600265340756, 1e-12);
  });

  it('autocorrelação positiva alarga o erro, e a negativa estreita', () => {
    const persistent = [0.1, 0.12, 0.11, 0.3, 0.32, 0.31];
    const alternatingValues = [0.1, 0.3, 0.1, 0.3, 0.1, 0.3];
    expect(Regression.neweyWestMean(persistent, 2)!.se).toBeGreaterThan(Regression.neweyWestMean(persistent, 0)!.se);
    expect(Regression.neweyWestMean(alternatingValues, 1)!.se).toBeLessThan(Regression.neweyWestMean(alternatingValues, 0)!.se);
  });

  it('defasagem além da série é truncada, e uma coorte não tem t', () => {
    expect(Regression.neweyWestMean([0.1, 0.2, 0.4], 9)!.lags).toBe(2);
    expect(Regression.neweyWestMean([0.1], 0)).toBeNull();
  });
});

describe('Regression.overlapAdjustedT — item C1c', () => {
  it('sem sobreposição é exatamente o t de summarize', () => {
    const v = [0.12, -0.03, 0.08, 0.15, 0.02, 0.07];
    expectClose(Regression.overlapAdjustedT(v, 0)!.t, Regression.summarize(v)!.t, 1e-12);
  });

  it('reproduz c e F à mão com cinco coortes anuais de 36 meses', () => {
    // ρ₁ = 2/3, ρ₂ = 1/3.
    // c = 1 − 2/(5·4)·(4·2/3 + 3·1/3) = 1 − 0,1·11/3 = 19/30.
    // F = 1 + 2·(4/5·2/3 + 3/5·1/3) = 1 + 2·(8/15 + 3/15) = 37/15.
    const v = [0.12, -0.03, 0.08, 0.15, 0.02];
    const r = Regression.overlapAdjustedT(v, 2)!;
    expectClose(r.c, 19 / 30, 1e-12);
    expectClose(r.f, 37 / 15, 1e-12);
    expectClose(r.t, Regression.summarize(v)!.t * Math.sqrt(19 / 30 / (37 / 15)), 1e-12);
  });

  it('o crítico mantém o nível sob séries sobrepostas de outro gerador', () => {
    // Nula construída por outro caminho — somas parciais e diferenças, com
    // outra semente —, e não pela mesma função que gera o crítico.
    const k = 22;
    const l = 11;
    const series = 3000;
    const rng = new SeededRandom(4242);
    const normal = (): number => {
      const u = 1 - rng.nextDouble();
      return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rng.nextDouble());
    };

    const critical = Regression.overlapCritical(k, l, 0.05);
    let rejects = 0;
    let naiveRejects = 0;
    for (let s = 0; s < series; s++) {
      const accumulated = [0];
      for (let i = 0; i < k + l; i++) accumulated.push(accumulated[accumulated.length - 1]! + normal());
      const x: number[] = [];
      for (let t = 0; t < k; t++) x.push(accumulated[t + l + 1]! - accumulated[t]!);
      if (Regression.overlapAdjustedT(x, l)!.t > critical) rejects++;
      if (Regression.summarize(x)!.t > 1.645) naiveRejects++;
    }
    // Erro de Monte Carlo de 0,4 p.p.: a banda é de três desvios.
    expect(rejects / series).toBeGreaterThanOrEqual(0.038);
    expect(rejects / series).toBeLessThanOrEqual(0.062);
    // E o t de sempre rejeita a nula verdadeira muito mais que 5%.
    expect(naiveRejects / series).toBeGreaterThan(0.2);
  });

  it('sem sobreposição, o crítico é o quantil da t de Student', () => {
    // Com L = 0 o t corrigido é o t de sempre, e a nula dele é a t de Student
    // com k − 1 graus de liberdade: 2,5165 para seis, no nível de t > 2 sob a
    // normal — integrado à parte, e não pela simulação.
    expectClose(Regression.overlapCritical(7, 0), 2.5165, 0.05);
  });

  it('o gerador é o splitmix64 de referência, igual ao do Python', () => {
    const g = new SplitMix64(0);
    expect(g.nextInt()).toBe(0xe220a8397b1dcdafn);
    expect(g.nextInt()).toBe(0x6e789e6aa1b965f4n);
    expect(g.nextInt()).toBe(0x06c45d188009454fn);
  });

  it('o p-valor sobe quando o t cai, e o crítico é o do nível pedido', () => {
    const critical = Regression.overlapCritical(22, 11);
    expectClose(Regression.overlapPValue(critical, 22, 11), Regression.r3Tail, 0.002);
    expectClose(Regression.overlapPValue(0, 22, 11), 0.5, 0.02);
    expect(critical).toBeGreaterThan(2);
  });
});
