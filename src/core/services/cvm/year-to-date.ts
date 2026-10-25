/**
 * O ano corrente anualizado: o acumulado do último ITR vezes `12 ÷ meses`.
 *
 * **O problema que isto resolve** (decisão 153). Entre uma DFP e a seguinte,
 * o lucro de partida da cascata ficava congelado no exercício anterior, mesmo
 * com dois ou três ITRs do ano corrente já públicos. O BBAS3 em 25/10/2026
 * partia do lucro de 2025, com o 1S26 publicado desde 12/08/2026.
 *
 * **O que isto faz.** Monta **um** ponto a mais no fim da série anual: os
 * fluxos do acumulado do ano anualizados, e o balanço na data do ITR. Os
 * exercícios anteriores continuam sendo as DFPs, de modo que a janela do
 * ciclo, a tendência e a trava de saúde comparam o ano corrente com anos
 * completos.
 *
 * **O que isto não faz, e por quê.** Não reescreve a série, como a ancorada
 * da decisão 73: a CVM não publica o ITR de 2025, e a série anualizada de
 * todos os anos teria o buraco que aquela decisão recusa. E não corrige
 * sazonalidade: anualizar é supor que o resto do ano repete o acumulado.
 */

import { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DateTime, Duration } from '../../lang/date-time';
import { round } from '../../lang/num';
import { CvmDocumentKind, type CvmPeriodDocument, TrailingTwelveMonths } from './trailing-twelve-months';

/** Duas datas no mesmo dia civil, dentro da folga dos doze meses. */
function close(a: DateTime, b: DateTime): boolean {
  const dayA = DateTime.utc(a.year, a.month, a.day);
  const dayB = DateTime.utc(b.year, b.month, b.day);
  return Math.abs(dayA.difference(dayB).inDays) <= TrailingTwelveMonths.toleranceDays;
}

/** Montagem do ano corrente anualizado. */
export const YearToDate = {
  /** Dias de um mês médio, para contar os meses de um acumulado. */
  daysPerMonth: 365.25 / 12,

  /**
   * Meses do acumulado, arredondados: 90 dias são 3, 181 são 6, 273 são 9.
   * Contar pelo calendário erraria o exercício que não começa no dia 1.
   */
  months(start: DateTime, end: DateTime): number {
    const days = DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1;
    return round(days / YearToDate.daysPerMonth);
  },

  /**
   * O acumulado de [itr] anualizado em [months] meses.
   *
   * **Fluxo vezes `12 ÷ meses`, estoque como está.** O balanço é o da data do
   * ITR: é o mais recente publicado, e anualizá-lo inventaria um balanço que
   * ninguém fechou. Campo de fluxo ausente fica ausente (decisão 52). LPA não
   * se anualiza: é por ação, e a cascata não o lê deste ponto.
   */
  annualize(itr: CvmPeriodDocument, months: number): FundamentalsSnapshot {
    const y = itr.current;
    const k = 12 / months;
    const scaled = (v: number | null): number | null => (v === null ? null : v * k);
    return new FundamentalsSnapshot({
      ticker: y.ticker,
      fiscalPeriodEnd: itr.periodEnd,
      receiptDate: y.receiptDate,
      annualizedMonths: months,
      // --- fluxo: o acumulado anualizado ---
      totalRevenue: scaled(y.totalRevenue),
      ebit: scaled(y.ebit),
      ebitda: scaled(y.ebitda),
      netIncome: scaled(y.netIncome),
      incomeBeforeTax: scaled(y.incomeBeforeTax),
      incomeTaxExpense: scaled(y.incomeTaxExpense),
      interestExpense: scaled(y.interestExpense),
      nopat: scaled(y.nopat),
      operatingCashFlow: scaled(y.operatingCashFlow),
      investmentCashFlow: scaled(y.investmentCashFlow),
      freeCashFlow: scaled(y.freeCashFlow),
      equityIncomeResult: scaled(y.equityIncomeResult),
      earningsPerShare: null,
      // --- estoque: na data do ITR ---
      cash: y.cash,
      shortTermInvestments: y.shortTermInvestments,
      shortTermDebt: y.shortTermDebt,
      longTermDebt: y.longTermDebt,
      totalStockholderEquity: y.totalStockholderEquity,
      propertyPlantEquipment: y.propertyPlantEquipment,
      intangibleAssets: y.intangibleAssets,
      totalCurrentAssets: y.totalCurrentAssets,
      currentLiabilities: y.currentLiabilities,
      realizedShareCapital: y.realizedShareCapital,
      profitReserves: y.profitReserves,
      minorityInterest: y.minorityInterest,
      totalAssets: y.totalAssets,
      treasuryShares: y.treasuryShares,
      treasuryFraction: y.treasuryFraction,
    });
  },

  /**
   * O ano corrente anualizado, do ITR mais recente do exercício que segue a
   * última DFP de [documents], ou `null`.
   *
   * [documents] já vem filtrado pela publicidade e pela versão vigente
   * (`CvmSeries.inForceAt`). **Recusa** o ITR que não começa no dia seguinte
   * ao fim da DFP — exercício social que mudou, ou acumulado de outro ano —,
   * e o acumulado de doze meses ou mais, que já é exercício completo.
   */
  latest(documents: readonly CvmPeriodDocument[]): FundamentalsSnapshot | null {
    let lastAnnual: CvmPeriodDocument | null = null;
    for (const d of documents) {
      if (d.kind !== CvmDocumentKind.dfp) continue;
      if (lastAnnual === null || d.periodEnd.isAfter(lastAnnual.periodEnd)) lastAnnual = d;
    }
    if (lastAnnual === null) return null;

    const nextStart = lastAnnual.periodEnd.add(new Duration({ days: 1 }));
    let chosen: CvmPeriodDocument | null = null;
    for (const d of documents) {
      if (d.kind !== CvmDocumentKind.itr) continue;
      if (!d.periodEnd.isAfter(lastAnnual.periodEnd)) continue;
      if (!close(d.periodStart, nextStart)) continue;
      if (chosen === null || d.periodEnd.isAfter(chosen.periodEnd)) chosen = d;
    }
    if (chosen === null) return null;

    const months = YearToDate.months(chosen.periodStart, chosen.periodEnd);
    if (months < 1 || months >= 12) return null;
    return YearToDate.annualize(chosen, months);
  },
};
