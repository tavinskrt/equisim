/**
 * Os dois modelos de fluxo descontado do pacote, e as premissas de uma rodada.
 *
 * A simetria entre eles é deliberada e é o que a decisão 25 introduziu: nas
 * duas vias o fluxo é `lucro × (1 − retenção)`, o crescimento decai até a
 * perpetuidade, e o terminal supõe retorno igual ao custo de capital.
 */

import { ComputationFailure, InsufficientData, InvalidInput } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { DartEnum, type WireKeyed } from '../../lang/dart-enum';
import { clamp } from '../../lang/num';

/**
 * Como o freio de reinvestimento é formado, em cada rodada.
 *
 * **Existe para medir, não para escolher.** A política de produção é
 * [measured], e as outras são costuras de diagnóstico que rodam os
 * contrafactuais **pela cascata real**.
 */
export class ReinvestmentPolicy extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** `b_t = g_t / ROIC_t`, confinado em `[0; 0,95]`. O que a produção faz. */
  static readonly measured = new ReinvestmentPolicy('measured', 0, 'medido');

  /** Sem freio: todo o lucro é distribuível. */
  static readonly none = new ReinvestmentPolicy('none', 1, 'nenhum');

  /** `b_t = g_real,t / ROIC_t` — só o crescimento **real** exige capital novo. */
  static readonly realGrowth = new ReinvestmentPolicy('realGrowth', 2, 'crescimentoReal');

  /** `b_t = g_t / ROIC_base`, sem a convergência do retorno ao custo de capital. */
  static readonly noConvergence = new ReinvestmentPolicy('noConvergence', 3, 'semConvergencia');

  /** `b_t = g_t / ROIC_t` **sem o teto de 0,95**. */
  static readonly uncapped = new ReinvestmentPolicy('uncapped', 4, 'semTeto');

  /**
   * `b_t = b` para todo `t`, inclusive na perpetuidade. **É a forma do cálculo
   * do usuário, e não da produção** (decisão 147).
   */
  static readonly fixedFraction = new ReinvestmentPolicy('fixedFraction', 5, 'parcelaFixa');

  static readonly values: readonly ReinvestmentPolicy[] = [
    ReinvestmentPolicy.measured,
    ReinvestmentPolicy.none,
    ReinvestmentPolicy.realGrowth,
    ReinvestmentPolicy.noConvergence,
    ReinvestmentPolicy.uncapped,
    ReinvestmentPolicy.fixedFraction,
  ];

  /** Chave gravada nas saídas. É dado, e não nome de código. */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'ReinvestmentPolicy';
  }
}

/** Quando o caixa do exercício chega, para efeito de desconto. */
export class CashTiming extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** Tudo no último dia do ano: `FCFF/WACC ≡ FCFE/Ke` é identidade exata. */
  static readonly endOfYear = new CashTiming('endOfYear', 0, 'fimDeAno');

  /** Distribuído ao longo do ano, representado pelo meio dele. Produção. */
  static readonly midYear = new CashTiming('midYear', 1, 'meioDeAno');

  static readonly values: readonly CashTiming[] = [CashTiming.endOfYear, CashTiming.midYear];

  /** Chave gravada nas saídas. É dado, e não nome de código. */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'CashTiming';
  }
}

/** Campos das premissas, para construção e cópia. */
export interface DcfAssumptionsArgs {
  projectionYears?: number;
  growthRate: number;
  perpetualGrowth: number;
  discountRate: number;
  terminalDiscountRate?: number | null;
  returnOnCapital?: number;
  neutralTerminalReturn?: boolean;
  terminalReturnOnCapital?: number | null;
  marginOfSafety?: number;
  discountRatePath?: readonly number[] | null;
  reinvestmentPolicy?: ReinvestmentPolicy;
  inflation?: number | null;
  cashTiming?: CashTiming;
  contractYearsAfterHorizon?: number | null;
  fixedRetention?: number | null;
  growthPath?: readonly number[] | null;
}

/** Premissas de uma rodada de DCF. */
export class DcfAssumptions {
  /** Teto da retenção, e por consequência do crescimento financiável. */
  static readonly maxRetention = 0.95;

  /** Anos de projeção explícita. Dez por decisão 25. */
  readonly projectionYears: number;

  /** Crescimento do **primeiro** ano projetado; decai até [perpetualGrowth]. */
  readonly growthRate: number;

  /**
   * Crescimento na perpetuidade. **Com [neutralTerminalReturn] ligado, ele não
   * afeta o valor terminal** — continua governando o decaimento do período
   * explícito.
   */
  readonly perpetualGrowth: number;

  /** Taxa de desconto do **primeiro** ano — WACC na firma, Ke no acionista. */
  readonly discountRate: number;

  /**
   * Taxa de desconto de **equilíbrio**, usada na perpetuidade e como destino
   * do decaimento: o custo de capital sobre a taxa livre de risco estrutural.
   */
  readonly terminalDiscountRate: number;

  /** Retorno sobre a base de capital: ROIC na firma, ROE no acionista. Zero desliga o freio. */
  readonly returnOnCapital: number;

  /**
   * Retorno terminal igual ao custo de capital (decisão 25): o valor terminal
   * vira `lucro_{N+1} / desconto` e deixa de depender do crescimento perpétuo.
   */
  readonly neutralTerminalReturn: boolean;

  /** Retorno preservado na perpetuidade, quando a vantagem competitiva é comprovada. */
  readonly terminalReturnOnCapital: number | null;

  /** Margem de segurança sobre o preço justo, em fração. */
  readonly marginOfSafety: number;

  /**
   * Caminho explícito da taxa de desconto, do ano 1 ao ano N. Nulo mantém a
   * interpolação de dois pontos. Preenchido, precisa ter [projectionYears]
   * posições.
   */
  readonly discountRatePath: readonly number[] | null;

  /** Política do freio de reinvestimento. */
  readonly reinvestmentPolicy: ReinvestmentPolicy;

  /** Inflação do ano, usada **apenas** por [ReinvestmentPolicy.realGrowth]. */
  readonly inflation: number | null;

  /** Convenção de chegada do caixa. [CashTiming.midYear] em produção. */
  readonly cashTiming: CashTiming;

  /**
   * Anos de contrato que restam depois do fim da projeção, ou `null` sem prazo
   * (item A6, decisão 88). Com prazo, o excedente sobre o capital existente
   * acaba no contrato.
   */
  readonly contractYearsAfterHorizon: number | null;

  /** Parcela do lucro reinvestida em todo ano, sob [ReinvestmentPolicy.fixedFraction]. */
  readonly fixedRetention: number | null;

  /** Crescimento explícito de cada ano, no lugar do decaimento linear (decisão 147). */
  readonly growthPath: readonly number[] | null;

  /** Declara as premissas. **Não valida** — quem confere é [DcfCalculator]. */
  constructor(args: DcfAssumptionsArgs) {
    this.projectionYears = args.projectionYears ?? 10;
    this.growthRate = args.growthRate;
    this.perpetualGrowth = args.perpetualGrowth;
    this.discountRate = args.discountRate;
    this.terminalDiscountRate = args.terminalDiscountRate ?? args.discountRate;
    this.returnOnCapital = args.returnOnCapital ?? 0.0;
    this.neutralTerminalReturn = args.neutralTerminalReturn ?? true;
    this.terminalReturnOnCapital = args.terminalReturnOnCapital ?? null;
    this.marginOfSafety = args.marginOfSafety ?? 0.0;
    this.discountRatePath = args.discountRatePath ?? null;
    this.reinvestmentPolicy = args.reinvestmentPolicy ?? ReinvestmentPolicy.measured;
    this.inflation = args.inflation ?? null;
    this.cashTiming = args.cashTiming ?? CashTiming.midYear;
    this.contractYearsAfterHorizon = args.contractYearsAfterHorizon ?? null;
    this.fixedRetention = args.fixedRetention ?? null;
    this.growthPath = args.growthPath ?? null;
  }

  /** Fração percorrida da janela explícita no ano [t]: 0 no ano 1, 1 no ano N. */
  private step(t: number): number {
    return this.projectionYears <= 1 ? 1.0 : (t - 1) / (this.projectionYears - 1);
  }

  /**
   * Taxa de desconto do ano [t]: `r_t = r_spot − (r_spot − r_∞)·(t − 1)/(N − 1)`.
   * `r_t` é taxa **do período**, não taxa à vista de vértice.
   */
  discountRateAt(t: number): number {
    const path = this.discountRatePath;
    if (path !== null && t >= 1 && t <= path.length) {
      return path[t - 1]!;
    }
    return this.discountRate - (this.discountRate - this.terminalDiscountRate) * this.step(t);
  }

  /**
   * Retorno sobre o capital no ano [t], convergindo do observado ao custo de
   * capital do próprio ano. Zero sem retorno utilizável.
   */
  returnOnCapitalAt(t: number): number {
    if (this.returnOnCapital <= 0) return 0.0;
    const destination = this.discountRateAt(t);
    return this.returnOnCapital - (this.returnOnCapital - destination) * this.step(t);
  }

  /** Retenção aplicada ao ano [t], `b_t = g_t / ROIC_t`, confinada a `[0, 0,95]`. */
  retentionAt(t: number): number {
    if (this.reinvestmentPolicy === ReinvestmentPolicy.none) return 0.0;
    // A parcela é a do usuário, sem o confinamento: dizer quanto se reinveste
    // é exatamente a premissa que ele quis fixar.
    if (this.reinvestmentPolicy === ReinvestmentPolicy.fixedFraction) {
      return this.fixedRetention ?? 0.0;
    }
    const roic =
      this.reinvestmentPolicy === ReinvestmentPolicy.noConvergence ? this.returnOnCapital : this.returnOnCapitalAt(t);
    if (roic <= 0) return 0.0;
    let g = this.growthAt(t);
    if (this.reinvestmentPolicy === ReinvestmentPolicy.realGrowth) {
      const pi = this.inflation;
      // Sem inflação declarada não há crescimento real a apurar: vale o nominal.
      if (pi !== null && Number.isFinite(pi) && pi > -1) g = (1 + g) / (1 + pi) - 1;
    }
    if (g <= 0) return 0.0;
    const b = g / roic;
    if (this.reinvestmentPolicy === ReinvestmentPolicy.uncapped) return b;
    return clamp(b, 0.0, DcfAssumptions.maxRetention);
  }

  /** Crescimento aplicado ao ano [t], já confinado ao que o retorno financia. */
  growthAt(t: number): number {
    const g = this.plannedGrowthAt(t);
    // Com a parcela fixa, o crescimento não sai do retorno (decisão 147).
    if (this.reinvestmentPolicy === ReinvestmentPolicy.fixedFraction) return g;
    return DcfAssumptions.sustainable(g, this.returnOnCapitalAt(t));
  }

  /**
   * Crescimento do ano [t] **antes** do confinamento: o de [growthPath] quando
   * há, e o decaimento linear `g_t = g − (g − g_∞)·(t − 1)/(N − 1)` quando não.
   */
  plannedGrowthAt(t: number): number {
    const path = this.growthPath;
    if (path !== null && t >= 1 && t <= path.length) {
      return path[t - 1]!;
    }
    return this.projectionYears <= 1
      ? this.perpetualGrowth
      : this.growthRate - (this.growthRate - this.perpetualGrowth) * ((t - 1) / (this.projectionYears - 1));
  }

  /** Levantamento de meio de ano do ano com taxa [rate], ou 1 no fim de ano. */
  lift(rate: number): number {
    return this.cashTiming === CashTiming.midYear ? DcfAssumptions.midYearLift(rate) : 1.0;
  }

  /** Fator de **meio de ano**: `√(1 + r)`. */
  static midYearLift(rate: number): number {
    return rate > -1 ? Math.sqrt(1 + rate) : 1.0;
  }

  /**
   * Confina [growth] ao que [returnOnCapital] financia: `g ≤ b_max · ROIC`.
   * Sem retorno utilizável o crescimento passa inteiro.
   */
  static sustainable(growth: number, returnOnCapital: number): number {
    if (returnOnCapital <= 0 || !Number.isFinite(returnOnCapital)) return growth;
    const cap = DcfAssumptions.maxRetention * returnOnCapital;
    return growth > cap ? cap : growth;
  }

  /** Os campos atuais, para cópia. */
  private get fields(): Required<DcfAssumptionsArgs> {
    return {
      projectionYears: this.projectionYears,
      growthRate: this.growthRate,
      perpetualGrowth: this.perpetualGrowth,
      discountRate: this.discountRate,
      terminalDiscountRate: this.terminalDiscountRate,
      returnOnCapital: this.returnOnCapital,
      neutralTerminalReturn: this.neutralTerminalReturn,
      terminalReturnOnCapital: this.terminalReturnOnCapital,
      marginOfSafety: this.marginOfSafety,
      discountRatePath: this.discountRatePath,
      reinvestmentPolicy: this.reinvestmentPolicy,
      inflation: this.inflation,
      cashTiming: this.cashTiming,
      contractYearsAfterHorizon: this.contractYearsAfterHorizon,
      fixedRetention: this.fixedRetention,
      growthPath: this.growthPath,
    };
  }

  /** Cópia com os campos informados substituídos. Nulo ou ausente lê-se "manter". */
  copyWith(changes: Partial<DcfAssumptionsArgs> = {}): DcfAssumptions {
    const f = this.fields;
    return new DcfAssumptions({
      projectionYears: changes.projectionYears ?? f.projectionYears,
      growthRate: changes.growthRate ?? f.growthRate,
      perpetualGrowth: changes.perpetualGrowth ?? f.perpetualGrowth,
      discountRate: changes.discountRate ?? f.discountRate,
      terminalDiscountRate: changes.terminalDiscountRate ?? f.terminalDiscountRate,
      returnOnCapital: changes.returnOnCapital ?? f.returnOnCapital,
      neutralTerminalReturn: changes.neutralTerminalReturn ?? f.neutralTerminalReturn,
      terminalReturnOnCapital: changes.terminalReturnOnCapital ?? f.terminalReturnOnCapital,
      marginOfSafety: changes.marginOfSafety ?? f.marginOfSafety,
      discountRatePath: changes.discountRatePath ?? f.discountRatePath,
      reinvestmentPolicy: changes.reinvestmentPolicy ?? f.reinvestmentPolicy,
      inflation: changes.inflation ?? f.inflation,
      cashTiming: changes.cashTiming ?? f.cashTiming,
      contractYearsAfterHorizon: changes.contractYearsAfterHorizon ?? f.contractYearsAfterHorizon,
      fixedRetention: changes.fixedRetention ?? f.fixedRetention,
      growthPath: changes.growthPath ?? f.growthPath,
    });
  }

  /**
   * Cópia com o retorno terminal trocado — **inclusive por nulo**, que
   * [copyWith] não alcança porque lê nulo como "manter".
   */
  withTerminalReturnOnCapital(value: number | null): DcfAssumptions {
    return new DcfAssumptions({ ...this.fields, terminalReturnOnCapital: value });
  }
}

/** Campos da saída bruta de um DCF. */
export interface DcfOutcomeArgs {
  projectedFlows: readonly number[];
  discountedFlows: readonly number[];
  terminalValue: number;
  discountedTerminalValue: number;
  enterpriseValue: number;
  equityValue: number;
  fairValuePerShare: number;
  terminalShare: number;
  equityShare?: number;
  discountedTerminalExcess?: number | null;
  impliedTerminalReturn?: number | null;
  discountRates?: readonly number[] | null;
  terminalDiscountRateUsed?: number | null;
  firmFlows?: readonly number[] | null;
  debtService?: readonly number[] | null;
  firmTerminalValue?: number | null;
  terminalFirmFlow?: number | null;
  terminalDebtService?: number | null;
  terminalEquityFlow?: number | null;
  projectedProfits?: readonly number[] | null;
  retentions?: readonly number[] | null;
  growthRates?: readonly number[] | null;
  discountFactors?: readonly number[] | null;
}

/** Saída bruta de um DCF, antes de virar `ValuationResult`. */
export class DcfOutcome {
  /** Fluxos distribuíveis do ano 1 ao ano N, **antes** de descontar. */
  readonly projectedFlows: readonly number[];

  /** Os mesmos fluxos a valor presente, alinhados posição a posição. */
  readonly discountedFlows: readonly number[];

  /** Valor terminal no ano N, em valor futuro. */
  readonly terminalValue: number;

  /** Valor terminal trazido a presente. */
  readonly discountedTerminalValue: number;

  /** Valor da firma, ou o valor por papel quando o fluxo já é do acionista. */
  readonly enterpriseValue: number;

  /** Valor do capital próprio da controladora, **na escala do fluxo**. */
  readonly equityValue: number;

  /** Preço justo por papel. */
  readonly fairValuePerShare: number;

  /** Parcela do **valor do capital próprio** explicada pelo terminal. **Pode passar de 100%.** */
  readonly terminalShare: number;

  /** Participação do equity no valor da firma. `1.0` na via do acionista. */
  readonly equityShare: number;

  /** Excedente perpétuo do capital instalado, a valor presente (item B12). Pode ser negativo. */
  readonly discountedTerminalExcess: number | null;

  /** `lucro_{N+1} ÷ capital_N`, implícito na projeção (item B12). */
  readonly impliedTerminalReturn: number | null;

  /** Taxa que descontou o fluxo de cada ano (item B35). */
  readonly discountRates: readonly number[] | null;

  /** Taxa que capitalizou o valor terminal descontado aqui. */
  readonly terminalDiscountRateUsed: number | null;

  /** Fluxo da firma de cada ano, antes do serviço da dívida — só no acionista derivado. */
  readonly firmFlows: readonly number[] | null;

  /** Serviço líquido da dívida de cada ano: `D_bruta·K_d(1−τ) − C·R_f(1−τ) − D_líquida·g`. */
  readonly debtService: readonly number[] | null;

  /** Valor terminal **da firma** no ano N — só no acionista derivado. */
  readonly firmTerminalValue: number | null;

  /** Fluxo da firma do ano N+1. */
  readonly terminalFirmFlow: number | null;

  /** Serviço líquido da dívida do ano N+1. */
  readonly terminalDebtService: number | null;

  /** Fluxo do acionista do ano N+1, que o terminal capitaliza. */
  readonly terminalEquityFlow: number | null;

  /** Lucro de cada ano, **antes** do reinvestimento (decisão 147). */
  readonly projectedProfits: readonly number[] | null;

  /** Parcela do lucro reinvestida em cada ano. */
  readonly retentions: readonly number[] | null;

  /** Crescimento aplicado a cada ano, já confinado. */
  readonly growthRates: readonly number[] | null;

  /** Desconto acumulado de cada ano, com o levantamento: `fluxo ÷ fator = valor presente`. */
  readonly discountFactors: readonly number[] | null;

  constructor(args: DcfOutcomeArgs) {
    this.projectedFlows = args.projectedFlows;
    this.discountedFlows = args.discountedFlows;
    this.terminalValue = args.terminalValue;
    this.discountedTerminalValue = args.discountedTerminalValue;
    this.enterpriseValue = args.enterpriseValue;
    this.equityValue = args.equityValue;
    this.fairValuePerShare = args.fairValuePerShare;
    this.terminalShare = args.terminalShare;
    this.equityShare = args.equityShare ?? 1.0;
    this.discountedTerminalExcess = args.discountedTerminalExcess ?? null;
    this.impliedTerminalReturn = args.impliedTerminalReturn ?? null;
    this.discountRates = args.discountRates ?? null;
    this.terminalDiscountRateUsed = args.terminalDiscountRateUsed ?? null;
    this.firmFlows = args.firmFlows ?? null;
    this.debtService = args.debtService ?? null;
    this.firmTerminalValue = args.firmTerminalValue ?? null;
    this.terminalFirmFlow = args.terminalFirmFlow ?? null;
    this.terminalDebtService = args.terminalDebtService ?? null;
    this.terminalEquityFlow = args.terminalEquityFlow ?? null;
    this.projectedProfits = args.projectedProfits ?? null;
    this.retentions = args.retentions ?? null;
    this.growthRates = args.growthRates ?? null;
    this.discountFactors = args.discountFactors ?? null;
  }
}

/** Argumentos do fluxo do acionista derivado do da firma. */
export interface EquityFromFirmArgs {
  baseProfit: number;
  assumptions: DcfAssumptions;
  netDebt: number;
  sharesOutstanding: number;
  costOfDebt: number;
  taxRate: number;
  equityDiscountRate: number;
  terminalEquityDiscountRate: number;
  equityDiscountRatePath?: readonly number[] | null;
  minorityInterest?: number;
  cash?: number;
  cashYield?: number | null;
  costOfDebtPath?: readonly number[] | null;
  cashYieldPath?: readonly number[] | null;
  terminalCostOfDebt?: number | null;
  terminalCashYield?: number | null;
}

/**
 * Os insumos do fluxo do acionista derivado do da firma que **não** são
 * premissa de projeção (decisão 147). Existe para que a cascata e o cálculo
 * do usuário descontem pela mesma chamada.
 */
export class FirmDiscountRoute {
  readonly netDebt: number;
  readonly sharesOutstanding: number;
  readonly costOfDebt: number;
  readonly taxRate: number;
  readonly minorityInterest: number;
  readonly cash: number;
  readonly cashYield: number | null;
  readonly costOfDebtPath: readonly number[] | null;
  readonly cashYieldPath: readonly number[] | null;
  readonly terminalCostOfDebt: number | null;
  readonly terminalCashYield: number | null;

  constructor(args: {
    netDebt: number;
    sharesOutstanding: number;
    costOfDebt: number;
    taxRate: number;
    minorityInterest?: number;
    cash?: number;
    cashYield?: number | null;
    costOfDebtPath?: readonly number[] | null;
    cashYieldPath?: readonly number[] | null;
    terminalCostOfDebt?: number | null;
    terminalCashYield?: number | null;
  }) {
    this.netDebt = args.netDebt;
    this.sharesOutstanding = args.sharesOutstanding;
    this.costOfDebt = args.costOfDebt;
    this.taxRate = args.taxRate;
    this.minorityInterest = args.minorityInterest ?? 0;
    this.cash = args.cash ?? 0;
    this.cashYield = args.cashYield ?? null;
    this.costOfDebtPath = args.costOfDebtPath ?? null;
    this.cashYieldPath = args.cashYieldPath ?? null;
    this.terminalCostOfDebt = args.terminalCostOfDebt ?? null;
    this.terminalCashYield = args.terminalCashYield ?? null;
  }

  /** O fluxo do acionista derivado do da firma, sob [assumptions] e o `Ke` dado. */
  discount(args: {
    baseProfit: number;
    assumptions: DcfAssumptions;
    equityDiscountRate: number;
    terminalEquityDiscountRate: number;
    equityDiscountRatePath?: readonly number[] | null;
  }): Result<DcfOutcome> {
    return DcfCalculator.equityFromFirm({
      baseProfit: args.baseProfit,
      assumptions: args.assumptions,
      netDebt: this.netDebt,
      sharesOutstanding: this.sharesOutstanding,
      costOfDebt: this.costOfDebt,
      taxRate: this.taxRate,
      equityDiscountRate: args.equityDiscountRate,
      terminalEquityDiscountRate: args.terminalEquityDiscountRate,
      equityDiscountRatePath: args.equityDiscountRatePath ?? null,
      minorityInterest: this.minorityInterest,
      cash: this.cash,
      cashYield: this.cashYield,
      costOfDebtPath: this.costOfDebtPath,
      cashYieldPath: this.cashYieldPath,
      terminalCostOfDebt: this.terminalCostOfDebt,
      terminalCashYield: this.terminalCashYield,
    });
  }
}

/** Projeção interna, antes da ponte. */
interface Projection {
  readonly flows: number[];
  readonly discounted: number[];
  /** A taxa de cada ano, como `discountRateAt` a deu. */
  readonly rates: readonly number[];
  readonly profits: readonly number[];
  readonly retentions: readonly number[];
  readonly growthRates: readonly number[];
  readonly factors: readonly number[];
  readonly discountedSum: number;
  readonly terminal: number;
  readonly discountedTerminal: number;
  readonly capitalFinal: number | null;
  /** Lucro do ano N, antes da retenção — o que o terminal capitaliza. */
  readonly finalProfit: number;
  /** O excedente perpétuo do capital instalado dentro de [terminal], em valor futuro. */
  readonly terminalExcess: number | null;
  /** `lucro_{N+1} ÷ capital_N`. `null` sem capital medível. */
  readonly impliedTerminalReturn: number | null;
}

/**
 * Abaixo disto, em módulo, o valor terminal é resíduo de ponto flutuante e
 * não denominador.
 */
const terminalResidual = 1e-9;

/** O valor, ou zero quando ele é negativo ou não finito. */
function nonNegative(v: number): number {
  return Number.isFinite(v) && v > 0 ? v : 0.0;
}

/** O excedente perpétuo trazido a presente **pelo mesmo fator do terminal**. */
function discountedAsTerminal(p: Projection): number | null {
  const e = p.terminalExcess;
  if (e === null || Math.abs(p.terminal) < terminalResidual || !Number.isFinite(p.terminal)) {
    return null;
  }
  const v = e * (p.discountedTerminal / p.terminal);
  return Number.isFinite(v) ? v : null;
}

function project(baseProfit: number, a: DcfAssumptions): Result<Projection> {
  if (a.projectionYears < 1) {
    return err(new InvalidInput('Anos de projeção deve ser ao menos 1.'));
  }
  if (a.discountRate <= 0 || a.terminalDiscountRate <= 0) {
    return err(new InvalidInput('Taxa de desconto deve ser positiva.'));
  }
  const path = a.discountRatePath;
  if (path !== null) {
    if (path.length !== a.projectionYears) {
      return err(
        new InvalidInput(
          'Caminho de desconto com tamanho diferente do horizonte: cada ano ' + 'projetado precisa da sua taxa.',
        ),
      );
    }
    for (const r of path) {
      if (!Number.isFinite(r) || r <= 0) {
        return err(new InvalidInput('Caminho de desconto com taxa não positiva.'));
      }
    }
  }
  const givenGrowth = a.growthPath;
  if (givenGrowth !== null) {
    if (givenGrowth.length !== a.projectionYears) {
      return err(
        new InvalidInput(
          'Caminho de crescimento com tamanho diferente do horizonte: cada ano ' +
            'projetado precisa do seu crescimento.',
        ),
      );
    }
    for (const g of givenGrowth) {
      if (!Number.isFinite(g) || g <= -1) {
        return err(new InvalidInput('Caminho de crescimento com taxa que zera o lucro.'));
      }
    }
  }

  const flows: number[] = [];
  const discounted: number[] = [];
  const rates: number[] = [];
  const profits: number[] = [];
  const retentions: number[] = [];
  const growthRates: number[] = [];
  const factors: number[] = [];
  let profit = baseProfit;
  let sum = 0.0;
  // Capital investido implícito, **o que gera o lucro do ano seguinte**: o do
  // primeiro ano é o lucro dele sobre o retorno, e cada ano soma o
  // reinvestimento. Só existe com retorno utilizável.
  let capital = NaN;

  // O fator de desconto **acumula** as taxas de cada ano, porque `r_t` é taxa
  // do período e não taxa à vista de vértice.
  let factor = 1.0;

  for (let t = 1; t <= a.projectionYears; t++) {
    const r = a.discountRateAt(t);
    rates.push(r);
    factor *= 1 + r;
    const g = a.growthAt(t);
    profit *= 1 + g;
    if (t === 1 && a.returnOnCapital > 0) capital = profit / a.returnOnCapital;
    const retention = a.retentionAt(t);
    capital += retention * profit;
    const distributable = profit * (1 - retention);
    // Meio de ano: o fluxo do ano chega, em média, no meio dele.
    const vp = (distributable * a.lift(r)) / factor;
    flows.push(distributable);
    discounted.push(vp);
    profits.push(profit);
    retentions.push(retention);
    growthRates.push(g);
    factors.push(factor / a.lift(r));
    sum += vp;
  }

  const finalCapital = Number.isFinite(capital) ? capital : null;
  const terminal = DcfCalculator.terminalValue({ finalProfit: profit, assumptions: a, finalCapital });
  if (terminal.isErr) return err(terminal.failureOrNull!);
  const vt = terminal.unwrap();

  return ok({
    flows,
    discounted,
    rates: Object.freeze(rates),
    profits: Object.freeze(profits),
    retentions: Object.freeze(retentions),
    growthRates: Object.freeze(growthRates),
    factors: Object.freeze(factors),
    discountedSum: sum,
    terminal: vt,
    capitalFinal: finalCapital,
    finalProfit: profit,
    terminalExcess: DcfCalculator.neutralTerminalExcess({ finalProfit: profit, finalCapital, assumptions: a }),
    impliedTerminalReturn:
      Number.isFinite(capital) && capital > 0 ? (profit * (1 + a.perpetualGrowth)) / capital : null,
    // A perpetuidade também é feita de fluxos distribuídos no ano, e recebe
    // o mesmo levantamento — sob a taxa de equilíbrio.
    discountedTerminal: (vt * a.lift(a.terminalDiscountRate)) / factor,
  });
}

/** Os dois modelos de fluxo descontado do pacote. */
export const DcfCalculator = {
  /**
   * Distância mínima entre taxa de desconto e crescimento perpétuo. Só age
   * quando o retorno terminal neutro está desligado.
   */
  minimumSpread: 0.005,

  /**
   * O **excedente perpétuo do capital instalado**, embutido no terminal neutro
   * (item B12): `VT = lucro_{N+1}/r = capital_N + EVA_{N+1}/r`. **É premissa, e
   * não identidade.** `null` quando a decomposição não se aplica; pode ser
   * negativo.
   */
  neutralTerminalExcess(args: {
    finalProfit: number;
    finalCapital: number | null;
    assumptions: DcfAssumptions;
  }): number | null {
    const { assumptions } = args;
    if (!assumptions.neutralTerminalReturn) return null;
    if (assumptions.terminalReturnOnCapital !== null) return null;
    if (assumptions.contractYearsAfterHorizon !== null) return null;
    const k = args.finalCapital;
    if (k === null || !Number.isFinite(k) || k <= 0) return null;
    const r = assumptions.terminalDiscountRate;
    if (r <= 0) return null;
    const next = args.finalProfit * (1 + assumptions.perpetualGrowth);
    const eva = next - r * k;
    return Number.isFinite(eva) ? eva / r : null;
  },

  /**
   * Valor terminal no ano N. **Com retorno terminal neutro** a álgebra colapsa
   * e o crescimento desaparece: `VT = lucro_{N+1} / r`.
   */
  terminalValue(args: {
    finalProfit: number;
    assumptions: DcfAssumptions;
    finalCapital?: number | null;
  }): Result<number> {
    const { finalProfit, assumptions } = args;
    const finalCapital = args.finalCapital ?? null;
    const r = assumptions.terminalDiscountRate;
    const g = assumptions.perpetualGrowth;
    const next = finalProfit * (1 + g);

    if (r <= 0) {
      return err(new InvalidInput('Taxa de desconto deve ser positiva.'));
    }

    // Parcela fixa: Gordon com a mesma parcela (decisão 147). Vem antes do
    // contrato e da vantagem competitiva.
    if (assumptions.reinvestmentPolicy === ReinvestmentPolicy.fixedFraction) {
      const spread = r - g;
      if (spread < DcfCalculator.minimumSpread) {
        return err(
          new ComputationFailure(
            'Taxa de desconto de equilíbrio não supera o crescimento perpétuo ' +
              'por margem suficiente: o valor terminal diverge.',
          ),
        );
      }
      const b = assumptions.retentionAt(assumptions.projectionYears);
      return ok((next * (1 - b)) / spread);
    }

    // Contrato que acaba: o capital volta, e o excedente sobre ele só dura os
    // anos que faltam (decisão 88).
    const years = assumptions.contractYearsAfterHorizon;
    if (
      years !== null &&
      years >= 0 &&
      assumptions.terminalReturnOnCapital === null &&
      assumptions.neutralTerminalReturn &&
      finalCapital !== null &&
      Number.isFinite(finalCapital) &&
      finalCapital > 0
    ) {
      const eva = next - r * finalCapital;
      const annuity = (1 - Math.pow(1 + r, -years)) / r;
      return ok(finalCapital + eva * annuity);
    }

    // Vantagem competitiva residual: o terminal volta à forma de Gordon com
    // reinvestimento.
    const moat = assumptions.terminalReturnOnCapital;
    if (moat !== null) {
      if (moat <= 0) {
        return err(new InvalidInput('Retorno terminal deve ser positivo quando declarado.'));
      }
      // O mesmo confinamento da projeção explícita. Vem **antes** da guarda do
      // spread: confinar o crescimento só o afasta da taxa.
      const gInf = DcfAssumptions.sustainable(g, moat);
      const spread = r - gInf;
      if (spread < DcfCalculator.minimumSpread) {
        return err(
          new ComputationFailure(
            'Taxa de desconto de equilíbrio não supera o crescimento perpétuo ' +
              'por margem suficiente: o valor terminal diverge.',
          ),
        );
      }
      const reinvestment = clamp(gInf / moat, 0.0, DcfAssumptions.maxRetention);
      return ok((finalProfit * (1 + gInf) * (1 - reinvestment)) / spread);
    }

    if (assumptions.neutralTerminalReturn) return ok(next / r);

    const spread = r - g;
    if (spread < DcfCalculator.minimumSpread) {
      return err(
        new ComputationFailure(
          'Taxa de desconto não supera o crescimento perpétuo por margem ' +
            'suficiente: o valor terminal diverge. Reduza o crescimento perpétuo ' +
            'ou adote retorno terminal neutro.',
        ),
      );
    }
    const perpetualRetention = assumptions.retentionAt(assumptions.projectionYears);
    return ok((next * (1 - perpetualRetention)) / spread);
  },

  /**
   * DCF sobre o fluxo da firma, descontado ao WACC: `FCFF_t = NOPAT_t × (1 − RI)`.
   * A parte dos não controladores sai antes da divisão por papel.
   */
  firm(args: {
    baseProfit: number;
    assumptions: DcfAssumptions;
    netDebt: number;
    sharesOutstanding: number;
    minorityInterest?: number;
  }): Result<DcfOutcome> {
    const { baseProfit, assumptions, netDebt, sharesOutstanding } = args;
    const minorityInterest = args.minorityInterest ?? 0;
    if (sharesOutstanding <= 0) {
      return err(new InsufficientData('Quantidade de papéis em circulação indisponível ou inválida.'));
    }
    if (baseProfit <= 0) {
      return err(new InsufficientData('Lucro operacional base não positivo: a via da firma não é aplicável.'));
    }

    const projected = project(baseProfit, assumptions);
    if (projected.isErr) return err(projected.failureOrNull!);
    const p = projected.unwrap();

    const ev = p.discountedSum + p.discountedTerminal;
    const equity = ev - netDebt;
    // A demonstração consolida 100% das controladas: a parte dos não
    // controladores sai antes da divisão por papel, e **não** entra em
    // [equityShare].
    const controllingEquity = equity - nonNegative(minorityInterest);
    const perShare = controllingEquity / sharesOutstanding;

    if (!Number.isFinite(perShare)) {
      return err(new ComputationFailure('Valor por papel não finito: verifique as premissas.'));
    }

    const discountedExcess = discountedAsTerminal(p);

    return ok(
      new DcfOutcome({
        projectedFlows: p.flows,
        discountedFlows: p.discounted,
        terminalValue: p.terminal,
        discountedTerminalValue: p.discountedTerminal,
        enterpriseValue: ev,
        equityValue: controllingEquity,
        fairValuePerShare: perShare,
        discountedTerminalExcess: discountedExcess,
        impliedTerminalReturn: p.impliedTerminalReturn,
        discountRates: p.rates,
        terminalDiscountRateUsed: assumptions.terminalDiscountRate,
        // **Contra o capital próprio, e não contra o valor da firma** (decisão 51).
        terminalShare: controllingEquity > 0 ? p.discountedTerminal / controllingEquity : 0.0,
        equityShare: ev > 0 ? equity / ev : 0.0,
        projectedProfits: p.profits,
        retentions: p.retentions,
        growthRates: p.growthRates,
        discountFactors: p.factors,
      }),
    );
  },

  /**
   * DCF sobre o fluxo do acionista **derivado do da firma**, descontado ao Ke:
   * `FCFE_t = FCFF_t − [D^b_{t−1}·Kd_t·(1−τ) − C_{t−1}·Rc_t·(1−τ) − D_{t−1}·g_t]`.
   *
   * Não é uma segunda opinião: é a mesma avaliação por uma rota que não passa
   * pela subtração `EV − D`.
   */
  equityFromFirm(args: EquityFromFirmArgs): Result<DcfOutcome> {
    const {
      baseProfit,
      assumptions,
      netDebt,
      sharesOutstanding,
      costOfDebt,
      taxRate,
      equityDiscountRate,
      terminalEquityDiscountRate,
    } = args;
    const equityDiscountRatePath = args.equityDiscountRatePath ?? null;
    const minorityInterest = args.minorityInterest ?? 0;
    const cash = args.cash ?? 0;
    const cashYield = args.cashYield ?? null;
    const costOfDebtPath = args.costOfDebtPath ?? null;
    const cashYieldPath = args.cashYieldPath ?? null;
    const terminalCostOfDebt = args.terminalCostOfDebt ?? null;
    const terminalCashYield = args.terminalCashYield ?? null;

    for (const c of [costOfDebtPath, cashYieldPath]) {
      if (c !== null && c.length !== assumptions.projectionYears) {
        return err(
          new InvalidInput(
            'Caminho de custo da dívida ou de rendimento do caixa com tamanho ' + 'diferente do horizonte.',
          ),
        );
      }
    }
    if (sharesOutstanding <= 0) {
      return err(new InsufficientData('Quantidade de papéis em circulação indisponível ou inválida.'));
    }
    if (baseProfit <= 0) {
      return err(new InsufficientData('Lucro operacional base não positivo: a via da firma não é aplicável.'));
    }
    if (equityDiscountRate <= 0 || terminalEquityDiscountRate <= 0) {
      return err(new InvalidInput('Custo do capital próprio deve ser positivo.'));
    }
    const kePath = equityDiscountRatePath;
    if (kePath !== null) {
      if (kePath.length !== assumptions.projectionYears) {
        return err(
          new InvalidInput(
            'Caminho de custo do capital próprio com tamanho diferente do ' +
              'horizonte: cada ano projetado precisa da sua taxa.',
          ),
        );
      }
      for (const k of kePath) {
        if (!Number.isFinite(k) || k <= 0) {
          return err(new InvalidInput('Caminho de custo do capital próprio com taxa não positiva.'));
        }
      }
    }

    // O fluxo da firma vem da mesma projeção que a via A usa.
    const projected = project(baseProfit, assumptions);
    if (projected.isErr) return err(projected.failureOrNull!);
    const p = projected.unwrap();

    const netKd = costOfDebt * (1 - taxRate);
    // **O caixa rende a taxa livre de risco, e não o custo de empréstimo**
    // (decisão 119). Sem [cashYield], vale `K_d` nos dois lados.
    const netCashYield = (cashYield ?? costOfDebt) * (1 - taxRate);
    const n = assumptions.projectionYears;

    // **Com caminho, o juro e o rendimento do ano t são os do ano t** (item B24).
    const kdAt = (t: number): number => (costOfDebtPath === null ? netKd : costOfDebtPath[t - 1]! * (1 - taxRate));
    const cashAt = (t: number): number =>
      cashYieldPath === null ? netCashYield : cashYieldPath[t - 1]! * (1 - taxRate);
    const kdTerminal = terminalCostOfDebt === null ? netKd : terminalCostOfDebt * (1 - taxRate);
    const terminalCash = terminalCashYield === null ? netCashYield : terminalCashYield * (1 - taxRate);

    /** `Ke` do ano [t]: o do caminho, ou o decaimento linear de dois pontos. */
    const keAt = (t: number): number => {
      const path = equityDiscountRatePath;
      if (path !== null && t >= 1 && t <= path.length) {
        return path[t - 1]!;
      }
      const step = n <= 1 ? 1.0 : (t - 1) / (n - 1);
      return equityDiscountRate - (equityDiscountRate - terminalEquityDiscountRate) * step;
    };

    const flows: number[] = [];
    const discounted: number[] = [];
    const usedRates: number[] = [];
    const debtServices: number[] = [];
    const factors: number[] = [];
    let sum = 0.0;
    let factor = 1.0;
    let debt = netDebt;
    // As duas metades crescem com o mesmo fator, e a diferença delas é a
    // líquida.
    let raw = netDebt + cash;
    let cashBalance = cash;

    /** `D_bruta·K_d(1−τ) − C·R_f(1−τ) − D_líquida·g`. */
    const debtService = (g: number, rates: { kd: number; rc: number }): number =>
      raw * rates.kd - cashBalance * rates.rc - debt * g;

    for (let t = 1; t <= n; t++) {
      const ke = keAt(t);
      factor *= 1 + ke;
      const g = assumptions.growthAt(t);
      // `D_{t−1}` é a dívida no **início** do ano.
      const yearDebtService = debtService(g, { kd: kdAt(t), rc: cashAt(t) });
      const fcfe = p.flows[t - 1]! - yearDebtService;
      usedRates.push(ke);
      debtServices.push(yearDebtService);
      flows.push(fcfe);
      const vp = (fcfe * assumptions.lift(ke)) / factor;
      factors.push(factor / assumptions.lift(ke));
      discounted.push(vp);
      sum += vp;
      debt = debt * (1 + g);
      raw = raw * (1 + g);
      cashBalance = cashBalance * (1 + g);
    }

    // Terminal do acionista, pela mesma identidade.
    const gInf = assumptions.perpetualGrowth;
    const spread = terminalEquityDiscountRate - gInf;
    if (spread < DcfCalculator.minimumSpread) {
      return err(
        new ComputationFailure(
          'Custo do capital próprio de equilíbrio não supera o crescimento ' +
            'perpétuo por margem suficiente: o valor terminal do acionista ' +
            'diverge.',
        ),
      );
    }
    const contract =
      assumptions.contractYearsAfterHorizon !== null &&
      assumptions.terminalReturnOnCapital === null &&
      assumptions.neutralTerminalReturn &&
      p.capitalFinal !== null;
    // O fluxo da firma do ano N+1 é o da **perpetuidade**.
    const firmPerpetual = contract
      ? (p.finalProfit * (1 + gInf)) / assumptions.terminalDiscountRate
      : p.terminal;
    const fcffTerminal = firmPerpetual * (assumptions.terminalDiscountRate - gInf);
    const terminalDebtService = debtService(gInf, { kd: kdTerminal, rc: terminalCash });
    const fcfeTerminal = fcffTerminal - terminalDebtService;
    const perpetual = fcfeTerminal / spread;
    // **Com contrato que acaba, o terminal do acionista é o perpétuo truncado**
    // (decisões 88 e 102): `VT = VT_∞·(1 − qᴹ) + (K − D)·qᴹ`.
    let vt: number;
    if (contract) {
      const q = (1 + gInf) / (1 + terminalEquityDiscountRate);
      const qM = Math.pow(q, assumptions.contractYearsAfterHorizon!);
      vt = perpetual * (1 - qM) + (p.capitalFinal! - debt) * qM;
    } else {
      vt = perpetual;
    }
    const discountedTv = (vt * assumptions.lift(terminalEquityDiscountRate)) / factor;

    // **O excedente perpétuo do capital instalado, pela mesma rota** (item B12).
    const firmExcess = DcfCalculator.neutralTerminalExcess({
      finalProfit: p.finalProfit,
      finalCapital: p.capitalFinal,
      assumptions,
    });
    let discountedExcess: number | null;
    // Comparação por tolerância, e não igualdade.
    if (firmExcess === null || Math.abs(vt) < terminalResidual || !Number.isFinite(vt)) {
      discountedExcess = null;
    } else {
      const delta = (firmExcess * (assumptions.terminalDiscountRate - gInf)) / spread;
      const v = delta * (discountedTv / vt);
      discountedExcess = Number.isFinite(v) ? v : null;
    }

    const equity = sum + discountedTv;
    const controllingEquity = equity - nonNegative(minorityInterest);
    const perShare = controllingEquity / sharesOutstanding;
    if (!Number.isFinite(perShare)) {
      return err(new ComputationFailure('Valor por papel não finito: verifique as premissas.'));
    }

    const ev = equity + netDebt;
    return ok(
      new DcfOutcome({
        projectedFlows: flows,
        discountedFlows: discounted,
        terminalValue: vt,
        discountedTerminalValue: discountedTv,
        enterpriseValue: ev,
        equityValue: controllingEquity,
        fairValuePerShare: perShare,
        terminalShare: controllingEquity > 0 ? discountedTv / controllingEquity : 0.0,
        equityShare: ev > 0 ? equity / ev : 0.0,
        discountedTerminalExcess: discountedExcess,
        impliedTerminalReturn: p.impliedTerminalReturn,
        discountRates: Object.freeze([...usedRates]),
        terminalDiscountRateUsed: terminalEquityDiscountRate,
        firmFlows: Object.freeze([...p.flows]),
        debtService: Object.freeze([...debtServices]),
        firmTerminalValue: p.terminal,
        terminalFirmFlow: fcffTerminal,
        terminalDebtService,
        terminalEquityFlow: fcfeTerminal,
        projectedProfits: p.profits,
        retentions: p.retentions,
        growthRates: p.growthRates,
        discountFactors: Object.freeze([...factors]),
      }),
    );
  },

  /**
   * DCF sobre o fluxo do acionista, descontado ao Ke: `Dividendo_t = LPA_t × (1 − b)`,
   * com o dividendo obtido pela identidade da retenção, e não por dado
   * publicado de provento (decisão 23). Sem ponte de dívida.
   */
  shareholder(args: { baseProfit: number; assumptions: DcfAssumptions }): Result<DcfOutcome> {
    const { baseProfit, assumptions } = args;
    if (baseProfit <= 0) {
      return err(new InsufficientData('Lucro base não positivo: a via do acionista não é aplicável.'));
    }

    const projected = project(baseProfit, assumptions);
    if (projected.isErr) return err(projected.failureOrNull!);
    const p = projected.unwrap();

    const perShare = p.discountedSum + p.discountedTerminal;
    if (!Number.isFinite(perShare)) {
      return err(new ComputationFailure('Valor por papel não finito: verifique as premissas.'));
    }

    return ok(
      new DcfOutcome({
        projectedFlows: p.flows,
        discountedFlows: p.discounted,
        terminalValue: p.terminal,
        discountedTerminalValue: p.discountedTerminal,
        enterpriseValue: perShare,
        equityValue: perShare,
        fairValuePerShare: perShare,
        terminalShare: perShare > 0 ? p.discountedTerminal / perShare : 0.0,
        discountedTerminalExcess: discountedAsTerminal(p),
        impliedTerminalReturn: p.impliedTerminalReturn,
        discountRates: p.rates,
        terminalDiscountRateUsed: assumptions.terminalDiscountRate,
        projectedProfits: p.profits,
        retentions: p.retentions,
        growthRates: p.growthRates,
        discountFactors: p.factors,
      }),
    );
  },
};
