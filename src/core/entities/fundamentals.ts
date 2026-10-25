import type { DateTime } from '../lang/date-time';
import { clamp } from '../lang/num';
import type { Ticker } from '../value-objects/ticker';

/** Campos opcionais de [FundamentalsSnapshot], na ordem do original. */
export interface FundamentalsFields {
  totalRevenue?: number | null;
  ebit?: number | null;
  ebitda?: number | null;
  netIncome?: number | null;
  incomeBeforeTax?: number | null;
  incomeTaxExpense?: number | null;
  interestExpense?: number | null;
  earningsPerShare?: number | null;
  nopat?: number | null;
  cash?: number | null;
  shortTermInvestments?: number | null;
  shortTermDebt?: number | null;
  longTermDebt?: number | null;
  totalStockholderEquity?: number | null;
  bookValuePerShare?: number | null;
  propertyPlantEquipment?: number | null;
  intangibleAssets?: number | null;
  totalCurrentAssets?: number | null;
  currentLiabilities?: number | null;
  realizedShareCapital?: number | null;
  profitReserves?: number | null;
  operatingCashFlow?: number | null;
  investmentCashFlow?: number | null;
  freeCashFlow?: number | null;
  sharesOutstanding?: number | null;
  sharesOutstandingAsOf?: number | null;
  marketCap?: number | null;
  enterpriseToEbitda?: number | null;
  minorityInterest?: number | null;
  equityIncomeResult?: number | null;
  receiptDate?: DateTime | null;
  treasuryShares?: number | null;
  treasuryFraction?: number | null;
  totalAssets?: number | null;
}

/** Argumentos completos do construtor. */
export interface FundamentalsArgs extends FundamentalsFields {
  ticker: Ticker;
  fiscalPeriodEnd: DateTime;
}

/** Magnitude abaixo da qual um valor publicado é resíduo, não número. */
const RESIDUAL = 1.0;

/** Magnitude abaixo da qual um valor **por papel** é resíduo: um centavo. */
const RESIDUAL_PER_SHARE = 0.01;

/**
 * Fotografia dos fundamentos de um exercício social.
 *
 * A fonte fornece **apenas granularidade anual** (16 exercícios, 2010–2025).
 * Não existe recorte trimestral — limitação a declarar na metodologia.
 *
 * Campos derivados relevantes que a fonte não entrega prontos:
 * - D&A       = `cleanEbitda − cleanEbit`
 * - alíquota  = `incomeTaxExpense / incomeBeforeTax`
 * - dív. líq. = `(curto + longo prazo) − (caixa + aplicações)`
 */
export class FundamentalsSnapshot {
  /** Ativo a que o exercício pertence. */
  readonly ticker: Ticker;

  /**
   * Encerramento do exercício a que os números se referem. É a data que
   * [PointInTimeView] compara com o corte de publicação.
   */
  readonly fiscalPeriodEnd: DateTime;

  // --- Demonstração de resultado ---
  // Todos os campos abaixo são `null` quando a fonte não os informa para o
  // exercício. Valores monetários vêm em reais, na escala publicada pela
  // fonte (unidades, não milhares), e por ação onde o nome indica.
  readonly totalRevenue: number | null;
  readonly ebit: number | null;
  readonly ebitda: number | null;
  readonly netIncome: number | null;
  readonly incomeBeforeTax: number | null;
  readonly incomeTaxExpense: number | null;
  readonly interestExpense: number | null;
  readonly earningsPerShare: number | null;

  // --- Balanço patrimonial ---
  readonly cash: number | null;
  readonly shortTermInvestments: number | null;
  readonly shortTermDebt: number | null;
  readonly longTermDebt: number | null;
  readonly totalStockholderEquity: number | null;
  readonly bookValuePerShare: number | null;

  /**
   * Lucro operacional líquido de imposto, como a fonte o publica.
   *
   * **Ele não é um dado independente do EBIT.** Conferido em 08/09/2026 sobre
   * o cache de produção: `nopat = EBIT × 0,66` em **4.572 de 4.572**
   * exercícios. A fonte aplica a alíquota estatutária brasileira de 34% e
   * publica o resultado. É por isso que o escudo fiscal do WACC usa a mesma
   * alíquota estatutária: ver `ValuationParameters.statutoryTaxRate`.
   *
   * Não existe para instituição financeira, que não tem EBIT publicado; é uma
   * das confirmações numéricas da Porta 1 (decisão 25).
   */
  readonly nopat: number | null;

  // --- Balanço, lado operacional ---
  readonly propertyPlantEquipment: number | null;
  readonly intangibleAssets: number | null;
  readonly totalCurrentAssets: number | null;
  readonly currentLiabilities: number | null;

  /**
   * Capital social realizado. Sobe por emissão **e** por incorporação de
   * reservas, então não serve sozinho para medir capital externo.
   */
  readonly realizedShareCapital: number | null;

  /** Reservas de lucro. Serve para distinguir emissão de incorporação. */
  readonly profitReserves: number | null;

  // --- Fluxo de caixa ---
  readonly operatingCashFlow: number | null;
  readonly investmentCashFlow: number | null;
  readonly freeCashFlow: number | null;

  // --- Mercado ---
  readonly sharesOutstanding: number | null;

  /**
   * Contagem de ações **do exercício**, preservada antes da sobrescrita pelo
   * valor corrente.
   *
   * **É contagem, e não data**, apesar do que o sufixo `AsOf` sugere — ele
   * significa "na data do exercício". [sharesOutstanding] descreve o hoje, e é
   * o que o preço por papel exige. Este descreve o ano, e é o que o
   * patrimônio exige.
   */
  readonly sharesOutstandingAsOf: number | null;

  readonly marketCap: number | null;
  readonly enterpriseToEbitda: number | null;

  /**
   * Participação dos **não controladores** no patrimônio consolidado.
   *
   * A demonstração consolida 100% das controladas, e o acionista da
   * controladora não é dono de tudo isso. O fluxo da firma carrega o
   * resultado inteiro; a ponte precisa devolver a parte que não é dele.
   */
  readonly minorityInterest: number | null;

  /**
   * Resultado de **equivalência patrimonial**, em reais do exercício.
   *
   * Na DRE brasileira ele já está dentro do EBIT publicado. Não se soma a
   * participação societária ao valor da firma, e não se tributa esse pedaço
   * de novo.
   */
  readonly equityIncomeResult: number | null;

  /**
   * Data em que o documento se tornou **público**, quando a fonte a informa.
   *
   * É o `DT_RECEB` da CVM. A conferência de 11/09/2026 mostrou que a
   * defasagem real tem mediana de **78 dias** no documento anual e de **40**
   * no trimestral. `null` para exercício vindo de fonte que não publica a
   * data — e aí `PointInTimeView` volta a presumir.
   */
  readonly receiptDate: DateTime | null;

  /**
   * Ações em tesouraria na data do exercício, em **contagem absoluta**.
   * **Prefira [treasuryFraction] quando a origem for a CVM.**
   */
  readonly treasuryShares: number | null;

  /**
   * Fração das ações integralizadas que está em tesouraria, em `[0, 1)`.
   *
   * **Existe porque a contagem absoluta da CVM não tem escala confiável.** A
   * razão `tesouraria ÷ integralizadas` **não depende da escala**: as duas
   * vêm do mesmo registro e erram juntas.
   */
  readonly treasuryFraction: number | null;

  /**
   * Ativo total publicado — a conta `1` do plano da CVM. **A identidade
   * `ativo = passivo` é conferida na ingestão**, e não aqui.
   */
  readonly totalAssets: number | null;

  constructor(args: FundamentalsArgs) {
    this.ticker = args.ticker;
    this.fiscalPeriodEnd = args.fiscalPeriodEnd;
    this.totalRevenue = args.totalRevenue ?? null;
    this.ebit = args.ebit ?? null;
    this.ebitda = args.ebitda ?? null;
    this.netIncome = args.netIncome ?? null;
    this.incomeBeforeTax = args.incomeBeforeTax ?? null;
    this.incomeTaxExpense = args.incomeTaxExpense ?? null;
    this.interestExpense = args.interestExpense ?? null;
    this.earningsPerShare = args.earningsPerShare ?? null;
    this.nopat = args.nopat ?? null;
    this.cash = args.cash ?? null;
    this.shortTermInvestments = args.shortTermInvestments ?? null;
    this.shortTermDebt = args.shortTermDebt ?? null;
    this.longTermDebt = args.longTermDebt ?? null;
    this.totalStockholderEquity = args.totalStockholderEquity ?? null;
    this.bookValuePerShare = args.bookValuePerShare ?? null;
    this.propertyPlantEquipment = args.propertyPlantEquipment ?? null;
    this.intangibleAssets = args.intangibleAssets ?? null;
    this.totalCurrentAssets = args.totalCurrentAssets ?? null;
    this.currentLiabilities = args.currentLiabilities ?? null;
    this.realizedShareCapital = args.realizedShareCapital ?? null;
    this.profitReserves = args.profitReserves ?? null;
    this.operatingCashFlow = args.operatingCashFlow ?? null;
    this.investmentCashFlow = args.investmentCashFlow ?? null;
    this.freeCashFlow = args.freeCashFlow ?? null;
    this.sharesOutstanding = args.sharesOutstanding ?? null;
    this.sharesOutstandingAsOf = args.sharesOutstandingAsOf ?? null;
    this.marketCap = args.marketCap ?? null;
    this.enterpriseToEbitda = args.enterpriseToEbitda ?? null;
    this.minorityInterest = args.minorityInterest ?? null;
    this.equityIncomeResult = args.equityIncomeResult ?? null;
    this.receiptDate = args.receiptDate ?? null;
    this.treasuryShares = args.treasuryShares ?? null;
    this.treasuryFraction = args.treasuryFraction ?? null;
    this.totalAssets = args.totalAssets ?? null;
  }

  /** Todos os campos, para reconstruir com alteração — a base dos `copyWith`. */
  toArgs(): FundamentalsArgs {
    return {
      ticker: this.ticker,
      fiscalPeriodEnd: this.fiscalPeriodEnd,
      totalRevenue: this.totalRevenue,
      ebit: this.ebit,
      ebitda: this.ebitda,
      netIncome: this.netIncome,
      incomeBeforeTax: this.incomeBeforeTax,
      incomeTaxExpense: this.incomeTaxExpense,
      interestExpense: this.interestExpense,
      earningsPerShare: this.earningsPerShare,
      nopat: this.nopat,
      cash: this.cash,
      shortTermInvestments: this.shortTermInvestments,
      shortTermDebt: this.shortTermDebt,
      longTermDebt: this.longTermDebt,
      totalStockholderEquity: this.totalStockholderEquity,
      bookValuePerShare: this.bookValuePerShare,
      propertyPlantEquipment: this.propertyPlantEquipment,
      intangibleAssets: this.intangibleAssets,
      totalCurrentAssets: this.totalCurrentAssets,
      currentLiabilities: this.currentLiabilities,
      realizedShareCapital: this.realizedShareCapital,
      profitReserves: this.profitReserves,
      operatingCashFlow: this.operatingCashFlow,
      investmentCashFlow: this.investmentCashFlow,
      freeCashFlow: this.freeCashFlow,
      sharesOutstanding: this.sharesOutstanding,
      sharesOutstandingAsOf: this.sharesOutstandingAsOf,
      marketCap: this.marketCap,
      enterpriseToEbitda: this.enterpriseToEbitda,
      minorityInterest: this.minorityInterest,
      equityIncomeResult: this.equityIncomeResult,
      receiptDate: this.receiptDate,
      treasuryShares: this.treasuryShares,
      treasuryFraction: this.treasuryFraction,
      totalAssets: this.totalAssets,
    };
  }

  /** Depreciação e amortização, derivada de EBITDA − EBIT. */
  get depreciationAndAmortization(): number | null {
    if (this.ebitda === null || this.ebit === null) return null;
    const dAndA = this.ebitda - this.ebit;
    return dAndA >= 0 ? dAndA : null;
  }

  /**
   * Alíquota efetiva de imposto, limitada a [0, 0.5] para conter distorções
   * de exercícios com prejuízo ou créditos fiscais extraordinários.
   *
   * **A fonte grava a despesa com sinal negativo**, e a conta respeita isso
   * desde 10/09/2026: negar o sinal em vez de tirar o módulo acerta o caso
   * comum e o crédito. **Com lucro antes do imposto nulo ou negativo não há
   * alíquota**, e a conta devolve `null`.
   */
  get effectiveTaxRate(): number | null {
    if (this.incomeBeforeTax === null || this.incomeTaxExpense === null) return null;
    if (this.incomeBeforeTax <= 0) return null;
    const rate = -this.incomeTaxExpense / this.incomeBeforeTax;
    if (Number.isNaN(rate) || !Number.isFinite(rate)) return null;
    return clamp(rate, 0.0, 0.5);
  }

  /**
   * `true` quando o exercício traz demonstração de resultado.
   *
   * **A fonte publica o exercício com o balanço preenchido e o resultado
   * inteiro zerado** (4 dos 376 ativos, 7 exercícios, medido em 10/09/2026).
   * **Zero é um número, e ausência não é zero.** O teste são **os quatro
   * juntos**: receita, resultado operacional, lucro líquido e lucro por ação,
   * por **magnitude**, e não por igualdade.
   */
  get hasIncomeStatement(): boolean {
    const isEmptyValue = (v: number | null, residual: number): boolean =>
      v === null || !Number.isFinite(v) || Math.abs(v) <= residual;
    return !(
      isEmptyValue(this.totalRevenue, RESIDUAL) &&
      isEmptyValue(this.ebit, RESIDUAL) &&
      isEmptyValue(this.netIncome, RESIDUAL) &&
      isEmptyValue(this.earningsPerShare, RESIDUAL_PER_SHARE)
    );
  }

  /**
   * Alavancagem observada: dívida **líquida** sobre o valor de mercado.
   *
   * **É a régua de desalavancar o beta, e existe para ser a mesma da
   * realavancagem** (decisão 54). Devolve `null` sem valor de mercado
   * utilizável. Pode ser **negativa** — caixa líquido —, e quem consome
   * confina: ver [BetaShrinkage.leverageFactor].
   */
  debtToMarketEquity(marketEquity: number | null): number | null {
    if (marketEquity === null || !Number.isFinite(marketEquity) || marketEquity <= 0) {
      return null;
    }
    const netDebtToEquity = this.netDebt / marketEquity;
    return Number.isFinite(netDebtToEquity) ? netDebtToEquity : null;
  }

  /**
   * Dívida bruta: curto mais longo prazo. **Trata ausência como zero.**
   * **Não é a dívida dos pesos do WACC**, que é a líquida (decisão 104).
   */
  get totalDebt(): number {
    return (this.shortTermDebt ?? 0) + (this.longTermDebt ?? 0);
  }

  /** Caixa e equivalentes: disponibilidades mais aplicações de curto prazo. */
  get totalCash(): number {
    return (this.cash ?? 0) + (this.shortTermInvestments ?? 0);
  }

  /**
   * Dívida líquida: [totalDebt] menos [totalCash]. **É a dívida do modelo
   * inteiro** (decisões 41, 54, 102 e 104).
   */
  get netDebt(): number {
    return this.totalDebt - this.totalCash;
  }

  /**
   * Cobertura de juros: `EBIT ÷ despesa financeira`.
   *
   * **Serve ao escudo fiscal**, e ao prêmio de crédito só quando a despesa é
   * juro de verdade (decisão 130). Devolve `null` sem EBIT ou sem despesa
   * financeira, e **zero** quando o EBIT é negativo.
   */
  get interestCoverage(): number | null {
    const op = this.ebit;
    const interest = this.interestExpense;
    if (op === null || interest === null) return null;
    const d = Math.abs(interest);
    if (d <= 0) return null;
    if (op <= 0) return 0.0;
    const c = op / d;
    return Number.isFinite(c) ? c : null;
  }

  /**
   * Alavancagem: dívida líquida sobre EBITDA — o direcionador da classificação
   * sintética de crédito. Devolve `null` sem EBITDA positivo.
   */
  get netDebtToEbitda(): number | null {
    const e = this.ebitda;
    if (e === null || e <= 0) return null;
    const r = this.netDebt / e;
    return Number.isFinite(r) ? r : null;
  }

  /** Custo da dívida implícito: despesa financeira sobre dívida bruta. */
  get costOfDebt(): number | null {
    if (this.interestExpense === null || this.totalDebt <= 0) return null;
    const kd = Math.abs(this.interestExpense) / this.totalDebt;
    if (Number.isNaN(kd) || !Number.isFinite(kd)) return null;
    return clamp(kd, 0.0, 1.0);
  }

  // --------------------------------------------------- Bases de capital --

  /**
   * Patrimônio líquido reconstituído: `VPA × ações do exercício`.
   *
   * **Sem o par, vale o patrimônio da demonstração** (item B47). **O VPA
   * negativo continua sendo insolvência**: o recuo só vale quando o par
   * falta.
   */
  get equityBookValue(): number | null {
    const bvps = this.bookValuePerShare;
    const n = this.sharesOutstandingAsOf;
    if (bvps !== null && bvps <= 0) return null;
    if (bvps !== null && n !== null && n > 0) {
      const pl = bvps * n;
      return Number.isFinite(pl) ? pl : null;
    }
    const pl = this.totalStockholderEquity;
    return pl !== null && Number.isFinite(pl) && pl > 0 ? pl : null;
  }

  /**
   * Capital investido pelo lado do financiamento: `PL + dívida bruta − caixa`.
   * Base da via A, e **a única das duas rotas que fecha com o que a fonte
   * publica**.
   */
  get investedCapital(): number | null {
    const pl = this.equityBookValue;
    if (pl === null) return null;
    const ic = pl + this.totalDebt - this.totalCash;
    return Number.isFinite(ic) && ic > 0 ? ic : null;
  }

  /**
   * Capital investido pelo lado operacional, **incompleto por falta de linha
   * na fonte**. **Não use como validador de [investedCapital]** — medição em
   * `docs/validacao/capital_investido.md`.
   */
  get investedCapitalOperating(): number | null {
    const fixedAssets = this.propertyPlantEquipment;
    const ca = this.totalCurrentAssets;
    const cl = this.currentLiabilities;
    if (fixedAssets === null || ca === null || cl === null) return null;
    const nwc = ca - this.totalCash - (cl - (this.shortTermDebt ?? 0));
    const ic = fixedAssets + (this.intangibleAssets ?? 0) + nwc;
    return Number.isFinite(ic) ? ic : null;
  }

  // ------------------------------------------------ Contagem de papéis --

  /**
   * Contagem de ações conciliada entre as duas que a fonte publica.
   *
   * **O árbitro é o próprio lucro por ação publicado.** `N = lucro ÷ LPA` é
   * identidade contábil. Sem árbitro, prefere-se a contagem do exercício.
   */
  get reconciledShares(): number | null {
    const fiscalYearValue = FundamentalsSnapshot.positive(this.sharesOutstandingAsOf);
    const current = FundamentalsSnapshot.positive(this.sharesOutstanding);
    if (fiscalYearValue === null) return current;
    if (current === null) return fiscalYearValue;

    const arbiter = this.sharesFromEarnings;
    if (arbiter !== null) {
      const byFiscalYear = FundamentalsSnapshot.logDistance(fiscalYearValue, arbiter);
      const byCurrent = FundamentalsSnapshot.logDistance(current, arbiter);
      const best = byFiscalYear <= byCurrent ? fiscalYearValue : current;
      const distance = byFiscalYear <= byCurrent ? byFiscalYear : byCurrent;
      if (distance <= FundamentalsSnapshot.reconciliationBand) return best;
    }
    return fiscalYearValue;
  }

  /**
   * Unidades negociadas implícitas no valor de mercado: `VM ÷ preço`.
   *
   * **É a contagem que forma o preço com que o preço justo é comparado**, e
   * por isso é a única defensável no divisor da ponte por papel. Devolve
   * `null` sem valor de mercado ou sem preço utilizável.
   */
  sharesFromMarketCap(marketPrice: number): number | null {
    const marketValue = this.marketCap;
    if (marketValue === null || !Number.isFinite(marketValue) || marketValue <= 0) return null;
    if (!Number.isFinite(marketPrice) || marketPrice <= 0) return null;
    const n = marketValue / marketPrice;
    return Number.isFinite(n) && n > 0 ? n : null;
  }

  /**
   * `true` quando as duas contagens discordam além de uma ação societária
   * plausível — o que a cascata registra como aviso.
   */
  get sharesDisagree(): boolean {
    const a = FundamentalsSnapshot.positive(this.sharesOutstandingAsOf);
    const b = FundamentalsSnapshot.positive(this.sharesOutstanding);
    if (a === null || b === null) return false;
    return FundamentalsSnapshot.logDistance(a, b) > FundamentalsSnapshot.reconciliationBand;
  }

  /** Contagem implícita no lucro por ação publicado: `N = lucro ÷ LPA`. */
  private get sharesFromEarnings(): number | null {
    const profit = this.netIncome;
    const eps = this.earningsPerShare;
    if (profit === null || eps === null) return null;
    if (Math.abs(eps) < 1e-9) return null;
    const n = profit / eps;
    return Number.isFinite(n) && n > 0 ? n : null;
  }

  /**
   * Tolerância da conciliação, em razão: aceita de 1/1,5 a 1,5. Pública porque
   * a ponte por papel usa a **mesma** banda.
   */
  static readonly reconciliationBand = 1.5;

  /** Distância multiplicativa entre duas contagens, sempre `>= 1`. */
  private static logDistance(a: number, b: number): number {
    return a >= b ? a / b : b / a;
  }

  /** O valor quando é positivo e finito; `null` caso contrário. */
  private static positive(v: number | null): number | null {
    return v !== null && Number.isFinite(v) && v > 0 ? v : null;
  }

  /**
   * NOPAT publicado, ou derivado por `EBIT × (1 − alíquota efetiva)`. O teste
   * é de **magnitude**, nunca de igualdade.
   */
  get nopatOrDerived(): number | null {
    const published = this.nopat;
    if (published !== null && Math.abs(published) > RESIDUAL) return published;
    const op = this.ebit;
    const t = this.effectiveTaxRate;
    if (op === null || t === null) return null;
    const v = op * (1 - t);
    return Number.isFinite(v) ? v : null;
  }

  /**
   * NOPAT recalculado a uma alíquota informada, no lugar da que a fonte usou.
   *
   * **A equivalência patrimonial atravessa sem ser tributada de novo**: o que
   * se tributa é `EBIT − equivalência`. Recua para [nopatOrDerived] sem EBIT
   * ou sem alíquota informada.
   */
  nopatAtRate(rate: number | null): number | null {
    const op = this.ebit;
    if (op === null || rate === null || !Number.isFinite(rate)) return this.nopatOrDerived;
    const v = op * (1 - rate) + this.taxableEquityIncome * rate;
    return Number.isFinite(v) ? v : this.nopatOrDerived;
  }

  /**
   * Equivalência patrimonial utilizável na conta do tributo, ou zero. **Só o
   * lado positivo**, e nunca acima do próprio EBIT.
   */
  get taxableEquityIncome(): number {
    const e = this.equityIncomeResult;
    if (e === null || !Number.isFinite(e) || e <= 0) return 0.0;
    const op = this.ebit;
    if (op === null || !Number.isFinite(op) || op <= 0) return 0.0;
    return e > op ? op : e;
  }
}
