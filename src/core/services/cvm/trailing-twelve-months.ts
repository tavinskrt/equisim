/**
 * Últimos doze meses, e a série anual ancorada no trimestre mais recente.
 *
 * **O problema que isto resolve.** A §0.2 do plano mediu que o potencial do
 * motor é lento: autocorrelação de posto de +0,666 entre coortes anuais. Entre
 * duas DFPs o preço justo fica congelado e o potencial só se move com o preço.
 * A CVM publica ITR a cada trimestre, com defasagem mediana de **40 dias**
 * contra os 78 da DFP (conferido em 11/09/2026).
 *
 * **O que isto não faz, e por quê.** Não põe trimestres na série. O motor
 * presume **um exercício por ano** em quase toda guarda — retorno do capital
 * `lucro_t ÷ base_{t−1}`, crescimento por diferença anual, janela de ciclo,
 * oito exercícios na Porta 0 —, e um ponto a seis meses do anterior entraria
 * como se fosse um ano.
 *
 * **O que faz: ancora a série.** Se o documento mais recente publicado é o ITR
 * de 30/06, a série inteira vira doze meses terminados em 30/06 de cada ano —
 * todos a exatamente um ano de distância. Toda guarda anual continua valendo,
 * e o ponto mais recente carrega seis meses de informação que a DFP não tem.
 *
 * Ver a decisão 73.
 */

import { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DartEnum } from '../../lang/dart-enum';
import { DateTime, Duration } from '../../lang/date-time';

/** Tipo de documento entregue à CVM. */
export class CvmDocumentKind extends DartEnum {
  /** Demonstração anual — o exercício social completo. */
  static readonly dfp = new CvmDocumentKind('dfp', 0);

  /** Informação trimestral — acumulado do exercício até o trimestre. */
  static readonly itr = new CvmDocumentKind('itr', 1);

  static readonly values: readonly CvmDocumentKind[] = [CvmDocumentKind.dfp, CvmDocumentKind.itr];

  protected get typeName(): string {
    return 'CvmDocumentKind';
  }
}

/**
 * Um documento com o período das suas contas de fluxo.
 *
 * O snapshot sozinho não basta para somar períodos: ele não diz onde o
 * acumulado começa, e um exercício social de abril a março soma de outro
 * jeito que um de janeiro a dezembro.
 */
export class CvmPeriodDocument {
  /** DFP ou ITR. */
  readonly kind: CvmDocumentKind;

  /** Primeiro dia do período acumulado dos fluxos. */
  readonly periodStart: DateTime;

  /** Data de referência — último dia do período e data do balanço. */
  readonly periodEnd: DateTime;

  /** Fluxos **acumulados** do período, e balanço em [periodEnd]. */
  readonly current: FundamentalsSnapshot;

  /**
   * Fluxos do **mesmo período no exercício anterior**, que o ITR traz como
   * comparativo. `null` na DFP, que não precisa dele.
   */
  readonly prior: FundamentalsSnapshot | null;

  /** Primeiro dia do período de [prior]. */
  readonly priorStart: DateTime | null;

  /** Declara o documento. */
  constructor(args: {
    kind: CvmDocumentKind;
    periodStart: DateTime;
    periodEnd: DateTime;
    current: FundamentalsSnapshot;
    prior?: FundamentalsSnapshot | null;
    priorStart?: DateTime | null;
  }) {
    this.kind = args.kind;
    this.periodStart = args.periodStart;
    this.periodEnd = args.periodEnd;
    this.current = args.current;
    this.prior = args.prior ?? null;
    this.priorStart = args.priorStart ?? null;
  }
}

/** Duas datas no mesmo dia civil, dentro de [TrailingTwelveMonths.toleranceDays]. */
function close(a: DateTime, b: DateTime): boolean {
  const dayA = DateTime.utc(a.year, a.month, a.day);
  const dayB = DateTime.utc(b.year, b.month, b.day);
  return Math.abs(dayA.difference(dayB).inDays) <= TrailingTwelveMonths.toleranceDays;
}

/** Montagem dos últimos doze meses. */
export const TrailingTwelveMonths = {
  /**
   * Folga, em dias, para casar datas de período entre documentos.
   *
   * Fim de semana e encerramento em dia útil deslocam a data de referência
   * por poucos dias; mais que isso é período diferente, e a soma recusa.
   */
  toleranceDays: 4,

  /**
   * Doze meses terminados em `itr.periodEnd`: `anual + acumulado − anterior`.
   *
   * - [annual]: a DFP do exercício que terminou **imediatamente antes** do
   *   acumulado começar.
   * - [itr]: o documento trimestral, com o comparativo do ano anterior.
   *
   * **Recusa, com `null`, em vez de somar períodos que não fecham.** Três
   * conferências: o acumulado começa no dia seguinte ao fim do exercício
   * anual; o comparativo começa onde o exercício anual começou; e os dois
   * acumulados têm o mesmo comprimento. Qualquer uma falhando, a soma
   * produziria um número de outro intervalo — e sem aviso.
   *
   * **Campo de fluxo ausente em qualquer das três parcelas fica ausente.**
   * Somar dois termos e tratar o terceiro como zero seria a leitura que a
   * decisão 52 proíbe.
   *
   * A aritmética é em ponto flutuante e é **exata** aqui: os valores da CVM
   * são inteiros em milhares de reais, e a soma de três inteiros abaixo de
   * 2⁵³ não arredonda.
   */
  build(args: { annual: CvmPeriodDocument; itr: CvmPeriodDocument }): FundamentalsSnapshot | null {
    const { annual, itr } = args;
    if (annual.kind !== CvmDocumentKind.dfp) return null;
    if (itr.kind !== CvmDocumentKind.itr) return null;
    const prior = itr.prior;
    const priorStart = itr.priorStart;
    if (prior === null || priorStart === null) return null;

    // 1. O acumulado começa no dia seguinte ao fim do exercício anual.
    if (!close(itr.periodStart, annual.periodEnd.add(new Duration({ days: 1 })))) {
      return null;
    }
    // 2. O comparativo começa onde o exercício anual começou.
    if (!close(priorStart, annual.periodStart)) return null;
    // 3. Os dois acumulados têm o mesmo comprimento.
    const currentLength = itr.periodEnd.difference(itr.periodStart).inDays;
    const previousEnd = DateTime.utc(itr.periodEnd.year - 1, itr.periodEnd.month, itr.periodEnd.day);
    const previousLength = previousEnd.difference(
      DateTime.utc(priorStart.year, priorStart.month, priorStart.day),
    ).inDays;
    if (Math.abs(currentLength - previousLength) > TrailingTwelveMonths.toleranceDays) return null;

    const a = annual.current;
    const y = itr.current;
    const p = prior;

    const sum = (fa: number | null, fy: number | null, fp: number | null): number | null => {
      if (fa === null || fy === null || fp === null) return null;
      const v = fa + fy - fp;
      return Number.isFinite(v) ? v : null;
    };

    const ebitTtm = sum(a.ebit, y.ebit, p.ebit);
    const fromTtm = sum(a.depreciationAndAmortization, y.depreciationAndAmortization, p.depreciationAndAmortization);

    return new FundamentalsSnapshot({
      ticker: y.ticker,
      fiscalPeriodEnd: itr.periodEnd,
      receiptDate: y.receiptDate,
      // --- fluxo: doze meses ---
      totalRevenue: sum(a.totalRevenue, y.totalRevenue, p.totalRevenue),
      ebit: ebitTtm,
      ebitda: ebitTtm !== null && fromTtm !== null ? ebitTtm + fromTtm : null,
      netIncome: sum(a.netIncome, y.netIncome, p.netIncome),
      incomeBeforeTax: sum(a.incomeBeforeTax, y.incomeBeforeTax, p.incomeBeforeTax),
      incomeTaxExpense: sum(a.incomeTaxExpense, y.incomeTaxExpense, p.incomeTaxExpense),
      interestExpense: sum(a.interestExpense, y.interestExpense, p.interestExpense),
      nopat: sum(a.nopat, y.nopat, p.nopat),
      operatingCashFlow: sum(a.operatingCashFlow, y.operatingCashFlow, p.operatingCashFlow),
      investmentCashFlow: sum(a.investmentCashFlow, y.investmentCashFlow, p.investmentCashFlow),
      freeCashFlow: sum(a.freeCashFlow, y.freeCashFlow, p.freeCashFlow),
      equityIncomeResult: sum(a.equityIncomeResult, y.equityIncomeResult, p.equityIncomeResult),
      // LPA não se soma: é por ação, e a contagem muda entre os períodos.
      earningsPerShare: null,
      // --- estoque: na data do trimestre ---
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
   * A série anual ancorada no documento mais recente publicado em [asOf].
   *
   * - [documents]: DFPs e ITRs da companhia, em qualquer ordem.
   * - [published]: se o documento já era público na data da avaliação.
   *   Recebido pela própria cascata, para que a regra de publicidade seja uma
   *   só.
   *
   * **Ancorada em DFP, devolve as DFPs** — é a série que o motor já usava.
   * **Ancorada em ITR**, devolve os doze meses terminados na mesma data de
   * cada ano, para todo ano em que o ITR daquele trimestre e a DFP anterior
   * a ele existam e sejam públicos.
   *
   * O ponto que não fecha a soma é **omitido**, e não substituído pela DFP:
   * misturar âncoras na mesma série é exatamente o que ela existe para evitar.
   *
   * **E a série com buraco não é devolvida** (decisão 73). Se entre dois
   * pontos ancorados sobra mais de um ano, a série inteira recua para a âncora
   * de DFP. A razão está medida: em 14/09/2026 a CVM **não publica o ITR de
   * 2025** — o diretório pula de 2024 para 2026 —, e a primeira versão montou
   * séries com junho/24 seguido de junho/26. As guardas anuais leram os dois
   * anos como um: a QUAL3 foi de −22% a +908% de potencial, e a mediana do
   * movimento no universo foi de 25,3%. Uma série anual com um ano faltando
   * não é anual, e nenhum número que saia dela descreve a companhia.
   */
  anchoredSeries(
    documents: readonly CvmPeriodDocument[],
    options: { published: (s: FundamentalsSnapshot) => boolean },
  ): FundamentalsSnapshot[] {
    const visibleOnes = documents
      .filter((d) => options.published(d.current))
      .sort((x, y) => x.periodEnd.compareTo(y.periodEnd));
    if (visibleOnes.length === 0) return [];

    const anchor = visibleOnes[visibleOnes.length - 1]!;
    const dfps = visibleOnes.filter((d) => d.kind === CvmDocumentKind.dfp);
    if (anchor.kind === CvmDocumentKind.dfp) {
      return dfps.map((d) => d.current);
    }

    const out: FundamentalsSnapshot[] = [];
    for (const itr of visibleOnes) {
      if (itr.kind !== CvmDocumentKind.itr) continue;
      if (itr.periodEnd.month !== anchor.periodEnd.month) continue;
      if (Math.abs(itr.periodEnd.day - anchor.periodEnd.day) > TrailingTwelveMonths.toleranceDays) {
        continue;
      }
      let annual: CvmPeriodDocument | null = null;
      for (const dfp of dfps) {
        if (close(itr.periodStart, dfp.periodEnd.add(new Duration({ days: 1 })))) {
          annual = dfp;
        }
      }
      if (annual === null) continue;
      const ttm = TrailingTwelveMonths.build({ annual, itr });
      if (ttm !== null) out.push(ttm);
    }

    // A âncora tem de ser o último ponto: sem ele a série ancorada não
    // descreve o documento que a escolheu.
    if (out.length === 0 || out[out.length - 1]!.fiscalPeriodEnd.year !== anchor.periodEnd.year) {
      return dfps.map((d) => d.current);
    }
    for (let i = 1; i < out.length; i++) {
      const jump = out[i]!.fiscalPeriodEnd.year - out[i - 1]!.fiscalPeriodEnd.year;
      if (jump !== 1) return dfps.map((d) => d.current);
    }
    return out;
  },

  /**
   * `true` quando [series] é ancorada em trimestre — ao menos um ponto não
   * termina onde uma DFP terminaria.
   *
   * Serve para quem monta a série saber se a âncora de ITR vingou ou se
   * houve recuo para a DFP.
   */
  isAnchoredOnQuarter(series: readonly FundamentalsSnapshot[], documents: readonly CvmPeriodDocument[]): boolean {
    if (series.length === 0) return false;
    const dfpEnd = new Set<string>();
    for (const d of documents) {
      if (d.kind === CvmDocumentKind.dfp) {
        dfpEnd.add(DateTime.utc(d.periodEnd.year, d.periodEnd.month, d.periodEnd.day).key);
      }
    }
    const last = series[series.length - 1]!.fiscalPeriodEnd;
    return !dfpEnd.has(DateTime.utc(last.year, last.month, last.day).key);
  },
};
