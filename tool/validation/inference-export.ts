import { Inference } from '../../src/core';
import { writeReport } from './context';

/**
 * Desenho de uma série sintética, gerada sem qualquer fonte de aleatoriedade
 * do sistema.
 */
class Design {
  constructor(
    readonly name: string,
    readonly n: number,
    readonly slope: number,
    readonly noise: number,
    /** Autocorrelação de primeira ordem imposta ao resíduo. */
    readonly rho: number,
  ) {}

  /**
   * Constrói a série em log-nível: `y_i = 1 + slope·i + e_i`.
   *
   * O resíduo vem de um gerador congruencial escrito aqui, com semente fixa:
   * `Math.random` não aceita semente, e a sequência de qualquer gerador da
   * plataforma é detalhe de implementação, não contrato entre versões. Um
   * gerador de quatro linhas, escrito no arquivo, torna a série reproduzível
   * para sempre — e o que se quer provar não tem nada a ver com a qualidade do
   * ruído.
   */
  build(): number[] {
    let status = 20260907;
    const next = () => {
      // Os 31 bits baixos do produto só dependem dos 31 bits baixos dos
      // fatores: o `Math.imul` dá os 32 bits baixos exatos, onde o produto em
      // `number` passaria de 2⁵³ e perderia os bits que o gerador usa. É o
      // mesmo resultado do inteiro de 64 bits do Dart.
      status = (Math.imul(status, 1103515245) + 12345) & 0x7fffffff;
      return (status / 0x7fffffff) * 2 - 1; // em [-1, 1]
    };

    const ys: number[] = [];
    let previous = 0;
    for (let i = 0; i < this.n; i++) {
      const shock = next() * this.noise;
      const e = this.rho * previous + shock;
      previous = e;
      ys.push(1.0 + this.slope * i + e);
    }
    return ys;
  }
}

/**
 * Exporta as primitivas estatísticas do núcleo para conferência externa.
 *
 * **Por que existe.** O argumento que sustenta a estatística deste trabalho é
 * que o núcleo não tem NumPy nem SciPy, e por isso tudo que foi implementado à
 * mão é recalculado em Python e comparado — ver
 * [`cross_validation.py`](../../docs/validacao/cross_validation.py).
 *
 * Esse argumento tinha um buraco: `inference` chegou com a decisão 25
 * trazendo OLS, erro-padrão Newey-West com núcleo de Bartlett, quantil da t de
 * Student e R² crítico, e **nenhum deles** era conferido por fora. Os quantis
 * da t e o R² crítico batiam contra tabela publicada nos testes; o HAC não
 * tinha conferência alguma.
 *
 * Este exportador fecha o buraco. Ele gera séries sintéticas **determinísticas**
 * — sem relógio, sem gerador do sistema — roda as primitivas sobre elas e grava
 * os dados **junto** dos resultados. O Python lê os mesmos números e recalcula
 * com `statsmodels` e `scipy.stats`.
 *
 * Gravar o dado junto do resultado é deliberado: se cada lado gerasse a própria
 * amostra, a comparação dependeria de dois geradores pseudoaleatórios
 * produzirem a mesma sequência, o que é frágil e não tem nada a ver com o que
 * se quer provar.
 */
export const InferenceExport = {
  /**
   * Executa a exportação e escreve o arquivo.
   *
   * - [outputDir]: destino do arquivo.
   */
  run(args: { outputDir: string }): void {
    const cases: Record<string, unknown>[] = [];

    // Regressões: da quase determinística à quase pura de ruído, mais uma com
    // autocorrelação forte nos resíduos, que é o caso que o HAC existe para
    // tratar. Os tamanhos cobrem a faixa real da série de exercícios (8 a 16).
    const designs = [
      new Design('tendencia limpa', 16, 0.08, 0.01, 0.0),
      new Design('tendencia ruidosa', 16, 0.08, 0.12, 0.0),
      new Design('serie curta', 8, 0.05, 0.06, 0.0),
      new Design('residuo autocorrelacionado', 16, 0.06, 0.08, 0.7),
      new Design('sem tendencia', 14, 0.0, 0.1, 0.0),
      new Design('inclinacao negativa', 12, -0.04, 0.05, 0.3),
    ];

    for (const d of designs) {
      const xs = Array.from({ length: d.n }, (_, i) => i);
      const ys = d.build();
      const fit = Inference.ols(xs, ys);
      if (fit === null) continue;
      cases.push({
        nome: d.name,
        x: xs,
        y: ys,
        dart: {
          slope: fit.slope,
          intercept: fit.intercept,
          r2: fit.r2,
          slopeStdError: fit.slopeStdError,
          residualStdError: fit.residualStdError,
          sxx: fit.sxx,
          hacSlopeStdError: Inference.hacSlopeStdError(xs, fit),
        },
      });
    }

    // Mediana e MAD escalado, incluindo amostra contaminada — que é o motivo de
    // o MAD existir no lugar do desvio-padrão.
    const samples: Record<string, number[]> = {
      simetrica: [0.1, 0.12, 0.14, 0.16, 0.18],
      par: [0.1, 0.12, 0.14, 0.16],
      contaminada: [0.1, 0.12, 0.14, 0.16, 9.9],
      'com negativos': [-0.3, -0.05, 0.02, 0.11, 0.4, 0.55],
      constante: [0.07, 0.07, 0.07, 0.07],
    };
    const robustness = Object.entries(samples).map(([name, values]) => ({
      nome: name,
      valores: values,
      dart: { mediana: Inference.median(values), madEscalado: Inference.scaledMad(values) },
    }));

    // Quantis da t e R² crítico na faixa que as guardas usam.
    const quantiles = [0.9, 0.95, 0.975, 0.995].flatMap((p) => [4, 6, 10, 14, 20, 30].map((df) => ({ p, df, dart: Inference.studentT(p, df) })));
    const r2crit = [0.01, 0.05, 0.1, 0.2].flatMap((alpha) => [6, 8, 10, 12, 14, 16].map((n) => ({ n, alpha, dart: Inference.criticalR2(n, alpha) })));

    // A chave `dart` fica: é o nome que o `cross_validation.py` lê, e o que
    // ela guarda é o resultado do núcleo, hoje o porte em TypeScript.
    const payload = {
      gerado_por: 'tool/validation/inference-export.ts',
      observacao: 'Dados e resultados do núcleo. O Python recalcula sobre os MESMOS dados — nenhum gerador aleatório é compartilhado.',
      regressoes: cases,
      robustez: robustness,
      quantis_t: quantiles,
      r2_critico: r2crit,
      bartlett_lag_formula: 'L = floor(4 * (n/100)^(2/9))',
    };

    writeReport(`${args.outputDir}/inferencia_nucleo.json`, JSON.stringify(payload, null, '  '));
  },
};
