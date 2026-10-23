/** Alavancagem de mercado medida na mesma janela em que o beta é estimado. */

import { DateTime } from '../../lang/date-time';
import { intDiv } from '../../lang/num';
import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import type { PricePoint } from '../../entities/price-series';
import type { DateRange } from '../../value-objects/date-range';
import { Inference } from '../valuation/inference';

const MS_PER_DAY = 86400000;

/** Dias desde a época, contados em UTC — imune a horário de verão. */
function inDays(d: DateTime): number {
  return intDiv(DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch, MS_PER_DAY);
}

/**
 * A alavancagem que o beta observado carrega.
 *
 * **Por que existe.** O beta é covariância de cinco anos de retorno diário, e
 * portanto reflete a estrutura de capital **daqueles cinco anos**.
 * Desalavancá-lo com a foto de hoje mistura janelas. Medido em 11/09/2026
 * sobre 124 ativos: o fator da janela difere do de hoje em mais de 10% em
 * **50** deles e em mais de 25% em **24**.
 *
 * **A mediana e não a média**: o que se quer é a estrutura típica do período,
 * não a pior dela.
 */
export const MarketLeverage = {
  /**
   * Distância máxima, em dias, entre o fim do exercício e o pregão usado.
   * Vinte dias cobrem feriado prolongado e recesso sem alcançar o exercício
   * vizinho.
   */
  maxDistantSessionDays: 20,

  /** Exercícios mínimos na janela para a mediana descrever alguma coisa. */
  minFiscalYears: 3,

  /**
   * Mediana de `dívida líquida ÷ valor de mercado` nos exercícios da janela.
   *
   * O valor de mercado de cada exercício é o **preço do pregão mais próximo
   * do fechamento** vezes a contagem de ações **daquele exercício**. Devolve
   * `null` com menos de [minFiscalYears] pares utilizáveis.
   */
  overWindow(args: {
    snapshots: readonly FundamentalsSnapshot[];
    prices: readonly PricePoint[];
    window: DateRange;
  }): number | null {
    if (args.prices.length === 0) return null;
    const ratios: number[] = [];
    for (const s of args.snapshots) {
      if (!args.window.contains(s.fiscalPeriodEnd)) continue;
      const shares = s.sharesOutstandingAsOf;
      if (shares === null || shares <= 0) continue;

      let nearest: PricePoint | null = null;
      let smallestDistance = MarketLeverage.maxDistantSessionDays + 1;
      const end = inDays(s.fiscalPeriodEnd);
      for (const p of args.prices) {
        const d = Math.abs(inDays(p.date) - end);
        if (d < smallestDistance) {
          smallestDistance = d;
          nearest = p;
        }
      }
      if (nearest === null) continue;

      const marketValueOf = nearest.close * shares;
      const debtToEquity = s.debtToMarketEquity(marketValueOf);
      if (debtToEquity !== null) ratios.push(debtToEquity);
    }
    if (ratios.length < MarketLeverage.minFiscalYears) return null;
    const m = Inference.median(ratios);
    return m !== null && Number.isFinite(m) ? m : null;
  },
};
