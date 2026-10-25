/**
 * A volta entre o veredito de vantagem competitiva e a taxa de equilíbrio.
 *
 * **Por que mora fora da cascata.** O veredito do moat usa a taxa terminal
 * para medir o excedente, e a taxa terminal sai de um ponto fixo que depende
 * do retorno terminal que o veredito concede. A cascata repõe a pergunta até
 * ela parar de mudar, com teto declarado (decisão 51) — e o caminho em que o
 * teto é alcançado, com o par ainda alternando, não tinha teste: fabricar um
 * ativo exatamente na fronteira do veredito é frágil, e a primeira mudança de
 * parâmetro o tiraria de lá sem aviso (lente `risco`, item D3).
 *
 * Extraída como função pura de três funções, a volta é testável com um
 * veredito sintético que alterna para sempre, e a cascata continua fazendo a
 * mesma conta — o gabarito confere isso bit a bit.
 */

import { ValuationParameters } from './growth-guards';

/** O que a volta devolveu. */
export class MoatFixedPoint<V, R> {
  /** O último veredito adotado — consistente com [rates]. */
  readonly verdict: V;

  /** O retorno terminal que [verdict] concede, ou `null` sem moat. */
  readonly moat: number | null;

  /** As taxas resolvidas contra [moat]. */
  readonly rates: R;

  /** Quantos passes a volta deu, contando o primeiro, que veio de fora. */
  readonly passes: number;

  /** `true` quando o veredito refeito deixou de mudar. */
  readonly stable: boolean;

  /**
   * `true` quando a volta parou porque o veredito seguinte pedia uma taxa que
   * o ponto fixo não fechou.
   */
  readonly solverFailed: boolean;

  private constructor(args: {
    verdict: V;
    moat: number | null;
    rates: R;
    passes: number;
    stable: boolean;
    solverFailed: boolean;
  }) {
    this.verdict = args.verdict;
    this.moat = args.moat;
    this.rates = args.rates;
    this.passes = args.passes;
    this.stable = args.stable;
    this.solverFailed = args.solverFailed;
  }

  /**
   * Repõe a pergunta até o veredito parar de mudar, ou até [maxPasses].
   *
   * - [verdict], [moat], [rates]: o par do primeiro passe, já consistente.
   * - [reassess]: o veredito refeito contra as taxas do passe.
   * - [moatOf]: o retorno terminal que um veredito concede — com a
   *   imposição externa, quando houver.
   * - [solve]: as taxas contra um retorno terminal; `null` quando o ponto
   *   fixo não fecha.
   *
   * **O veredito só é adotado com a taxa dele.** Adotá-lo antes de saber se o
   * solucionador fecha deixaria o retorno terminal de um passe casado com o
   * caminho de taxas do anterior. Por isso, na parada, o par devolvido é
   * sempre o último consistente entre si.
   */
  static iterate<V, R>(args: {
    verdict: V;
    moat: number | null;
    rates: R;
    reassess: (rates: R) => V;
    moatOf: (verdict: V) => number | null;
    solve: (moat: number | null) => R | null;
    maxPasses?: number;
  }): MoatFixedPoint<V, R> {
    let { verdict, moat, rates } = args;
    const maxPasses = args.maxPasses ?? ValuationParameters.moatMaxPasses;
    let passes = 1;
    let stable = false;
    let solverFailed = false;
    while (passes < maxPasses) {
      const redone = args.reassess(rates);
      const newPackage = args.moatOf(redone);
      const changed =
        (newPackage === null) !== (moat === null) ||
        (newPackage !== null && moat !== null && Math.abs(newPackage - moat) > 1e-9);
      if (!changed) {
        stable = true;
        break;
      }
      const next = args.solve(newPackage);
      if (next === null) {
        solverFailed = true;
        break;
      }
      verdict = redone;
      moat = newPackage;
      rates = next;
      passes++;
    }
    return new MoatFixedPoint<V, R>({ verdict, moat, rates, passes, stable, solverFailed });
  }
}
