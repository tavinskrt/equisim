/**
 * O cálculo do usuário: a conta do motor refeita com os números de quem
 * discorda dele (decisão 147).
 */

import { ComputationFailure, InvalidInput, QuantityUnit, type Failure } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { DartEnum } from '../../lang/dart-enum';
import { ValuationLane } from './capital-base';
import { DcfCalculator, ReinvestmentPolicy, type DcfAssumptions, type DcfOutcome, type FirmDiscountRoute } from './dcf';

/**
 * Uma premissa que o usuário pode digitar. O nome de cada valor é o que vai
 * em [InvalidInput.field] quando a conta recusa a premissa.
 */
export class ManualField extends DartEnum {
  /** Lucro do ano de partida, em reais: `NOPAT` na firma, lucro líquido no acionista. */
  static readonly baseProfit = new ManualField('baseProfit', 0);

  /** Crescimento do lucro no primeiro ano projetado. */
  static readonly growth = new ManualField('growth', 1);

  /** Taxa que desconta o fluxo do acionista no primeiro ano — o `Ke`, nas duas vias. */
  static readonly discountRate = new ManualField('discountRate', 2);

  /** Crescimento na perpetuidade. */
  static readonly perpetualGrowth = new ManualField('perpetualGrowth', 3);

  /** Retorno sobre o capital no primeiro ano: `ROIC` na firma, `ROE` no acionista. */
  static readonly returnOnCapital = new ManualField('returnOnCapital', 4);

  /** Parcela do lucro reinvestida, quando ela é fixa. */
  static readonly retention = new ManualField('retention', 5);

  /** Retorno do capital novo na perpetuidade. */
  static readonly terminalReturn = new ManualField('terminalReturn', 6);

  static readonly values: readonly ManualField[] = [
    ManualField.baseProfit,
    ManualField.growth,
    ManualField.discountRate,
    ManualField.perpetualGrowth,
    ManualField.returnOnCapital,
    ManualField.retention,
    ManualField.terminalReturn,
  ];

  protected get typeName(): string {
    return 'ManualField';
  }
}

/** Como a taxa de desconto se espalha pelos anos. */
export class ManualRatePath extends DartEnum {
  /** O caminho do motor, deslocado em paralelo pela diferença do primeiro ano. */
  static readonly engine = new ManualRatePath('engine', 0);

  /** Uma taxa só, do primeiro ano à perpetuidade. */
  static readonly constant = new ManualRatePath('constant', 1);

  static readonly values: readonly ManualRatePath[] = [ManualRatePath.engine, ManualRatePath.constant];

  protected get typeName(): string {
    return 'ManualRatePath';
  }
}

/** Como o crescimento evolui nos anos explícitos. */
export class ManualGrowthPath extends DartEnum {
  /** Do crescimento digitado ao da perpetuidade, em linha reta. É o que o motor faz. */
  static readonly decays = new ManualGrowthPath('decays', 0);

  /** O mesmo crescimento em todos os anos explícitos. */
  static readonly constant = new ManualGrowthPath('constant', 1);

  static readonly values: readonly ManualGrowthPath[] = [ManualGrowthPath.decays, ManualGrowthPath.constant];

  protected get typeName(): string {
    return 'ManualGrowthPath';
  }
}

/** De onde sai a parcela do lucro reinvestida. */
export class ManualReinvestment extends DartEnum {
  /** `b_t = g_t ÷ retorno_t`, com o retorno convergindo à taxa. É o que o motor faz. */
  static readonly byReturn = new ManualReinvestment('byReturn', 0);

  /** Uma parcela fixa do lucro, em todos os anos e na perpetuidade. */
  static readonly fixedFraction = new ManualReinvestment('fixedFraction', 1);

  static readonly values: readonly ManualReinvestment[] = [ManualReinvestment.byReturn, ManualReinvestment.fixedFraction];

  protected get typeName(): string {
    return 'ManualReinvestment';
  }
}

/** Campos das premissas do usuário. */
export interface ManualPremisesArgs {
  baseProfit: number;
  growth: number;
  growthPath?: ManualGrowthPath;
  discountRate: number;
  ratePath?: ManualRatePath;
  perpetualGrowth: number;
  reinvestment?: ManualReinvestment;
  returnOnCapital: number;
  retention: number;
  terminalReturn?: number | null;
}

/**
 * As premissas de um cálculo do usuário (decisão 147). Taxas em fração ao
 * ano. **O lucro de partida é em reais nas duas vias.**
 */
export class ManualPremises {
  readonly baseProfit: number;
  readonly growth: number;
  readonly growthPath: ManualGrowthPath;
  readonly discountRate: number;
  readonly ratePath: ManualRatePath;
  readonly perpetualGrowth: number;
  readonly reinvestment: ManualReinvestment;

  /** Retorno sobre o capital do primeiro ano, usado sob [ManualReinvestment.byReturn]. */
  readonly returnOnCapital: number;

  /** Parcela reinvestida, usada sob [ManualReinvestment.fixedFraction]. */
  readonly retention: number;

  /** Retorno do capital novo na perpetuidade, ou `null` para igual à taxa — o estado estacionário. */
  readonly terminalReturn: number | null;

  /** Declara as premissas. Não valida: quem recusa é [ManualValuation.evaluate]. */
  constructor(args: ManualPremisesArgs) {
    this.baseProfit = args.baseProfit;
    this.growth = args.growth;
    this.growthPath = args.growthPath ?? ManualGrowthPath.decays;
    this.discountRate = args.discountRate;
    this.ratePath = args.ratePath ?? ManualRatePath.engine;
    this.perpetualGrowth = args.perpetualGrowth;
    this.reinvestment = args.reinvestment ?? ManualReinvestment.byReturn;
    this.returnOnCapital = args.returnOnCapital;
    this.retention = args.retention;
    this.terminalReturn = args.terminalReturn ?? null;
  }

  /**
   * Cópia com os campos informados trocados. [terminalReturn] aceita `null`
   * explícito — é como se volta ao estado estacionário; ausente mantém.
   */
  copyWith(changes: Partial<Omit<ManualPremisesArgs, 'terminalReturn'>> & { terminalReturn?: number | null } = {}): ManualPremises {
    return new ManualPremises({
      baseProfit: changes.baseProfit ?? this.baseProfit,
      growth: changes.growth ?? this.growth,
      growthPath: changes.growthPath ?? this.growthPath,
      discountRate: changes.discountRate ?? this.discountRate,
      ratePath: changes.ratePath ?? this.ratePath,
      perpetualGrowth: changes.perpetualGrowth ?? this.perpetualGrowth,
      reinvestment: changes.reinvestment ?? this.reinvestment,
      returnOnCapital: changes.returnOnCapital ?? this.returnOnCapital,
      retention: changes.retention ?? this.retention,
      terminalReturn: 'terminalReturn' in changes ? (changes.terminalReturn ?? null) : this.terminalReturn,
    });
  }

  /** O valor de um campo, ou `null` para o retorno terminal no estado estacionário. */
  valueOf(field: ManualField): number | null {
    switch (field) {
      case ManualField.baseProfit:
        return this.baseProfit;
      case ManualField.growth:
        return this.growth;
      case ManualField.discountRate:
        return this.discountRate;
      case ManualField.perpetualGrowth:
        return this.perpetualGrowth;
      case ManualField.returnOnCapital:
        return this.returnOnCapital;
      case ManualField.retention:
        return this.retention;
      default:
        return this.terminalReturn;
    }
  }

  /** Cópia com um campo trocado. */
  withValue(field: ManualField, value: number): ManualPremises {
    switch (field) {
      case ManualField.baseProfit:
        return this.copyWith({ baseProfit: value });
      case ManualField.growth:
        return this.copyWith({ growth: value });
      case ManualField.discountRate:
        return this.copyWith({ discountRate: value });
      case ManualField.perpetualGrowth:
        return this.copyWith({ perpetualGrowth: value });
      case ManualField.returnOnCapital:
        return this.copyWith({ returnOnCapital: value });
      case ManualField.retention:
        return this.copyWith({ retention: value });
      default:
        return this.copyWith({ terminalReturn: value });
    }
  }
}

/** Os grupos de premissas, na ordem em que [ManualValuation.attribution] os aplica. */
export class ManualGroup extends DartEnum {
  /** O lucro de partida. */
  static readonly profit = new ManualGroup('profit', 0);

  /** O crescimento e o caminho dele. */
  static readonly growth = new ManualGroup('growth', 1);

  /** O modo de reinvestir, o retorno e a parcela. */
  static readonly reinvestment = new ManualGroup('reinvestment', 2);

  /** A taxa de desconto e o caminho dela. */
  static readonly rate = new ManualGroup('rate', 3);

  /** O crescimento na perpetuidade. */
  static readonly perpetuity = new ManualGroup('perpetuity', 4);

  /** O retorno do capital novo na perpetuidade. */
  static readonly newCapital = new ManualGroup('newCapital', 5);

  static readonly values: readonly ManualGroup[] = [
    ManualGroup.profit,
    ManualGroup.growth,
    ManualGroup.reinvestment,
    ManualGroup.rate,
    ManualGroup.perpetuity,
    ManualGroup.newCapital,
  ];

  protected get typeName(): string {
    return 'ManualGroup';
  }
}

/** Como o valor terminal foi formado. */
export class ManualTerminal extends DartEnum {
  /** Capital novo rendendo a própria taxa: `lucro_{N+1} ÷ taxa`. */
  static readonly neutral = new ManualTerminal('neutral', 0);

  /** Gordon com reinvestimento: `lucro_{N+1}·(1 − g/retorno) ÷ (taxa − g)`. */
  static readonly advantage = new ManualTerminal('advantage', 1);

  /** Gordon com a parcela fixa: `lucro_{N+1}·(1 − b) ÷ (taxa − g)`. */
  static readonly fixedFraction = new ManualTerminal('fixedFraction', 2);

  /** Concessão: o capital volta no fim do contrato (decisão 88). */
  static readonly contract = new ManualTerminal('contract', 3);

  static readonly values: readonly ManualTerminal[] = [
    ManualTerminal.neutral,
    ManualTerminal.advantage,
    ManualTerminal.fixedFraction,
    ManualTerminal.contract,
  ];

  protected get typeName(): string {
    return 'ManualTerminal';
  }
}

/** Algo que a conta fez e que o usuário precisa saber para ler o número. */
export class ManualNoticeKind extends DartEnum {
  /** O crescimento digitado não coube no que o retorno financia. */
  static readonly confinedGrowth = new ManualNoticeKind('confinedGrowth', 0);

  /** O fluxo de algum ano ficou negativo. */
  static readonly negativeFlow = new ManualNoticeKind('negativeFlow', 1);

  /** A empresa é concessão, e a perpetuidade deixou de acabar no contrato. */
  static readonly perpetualConcession = new ManualNoticeKind('perpetualConcession', 2);

  /** Crescimento perpétuo trocado com o capital novo rendendo a própria taxa. */
  static readonly neutralPerpetuity = new ManualNoticeKind('neutralPerpetuity', 3);

  static readonly values: readonly ManualNoticeKind[] = [
    ManualNoticeKind.confinedGrowth,
    ManualNoticeKind.negativeFlow,
    ManualNoticeKind.perpetualConcession,
    ManualNoticeKind.neutralPerpetuity,
  ];

  protected get typeName(): string {
    return 'ManualNoticeKind';
  }
}

/** Um aviso do cálculo do usuário, com os anos a que se refere. */
export class ManualNotice {
  readonly kind: ManualNoticeKind;

  /** Anos explícitos afetados, contados a partir de 1. Vazio quando o aviso não é de ano. */
  readonly years: readonly number[];

  constructor(kind: ManualNoticeKind, options: { years?: readonly number[] } = {}) {
    this.kind = kind;
    this.years = options.years ?? [];
  }
}

/** Um ano do cálculo do usuário, em reais. */
export class ManualYear {
  readonly year: number;
  /** Crescimento aplicado, já confinado. */
  readonly growth: number;
  /** Crescimento pedido, antes do confinamento. */
  readonly plannedGrowth: number;
  /** Lucro do ano antes do reinvestimento. */
  readonly profit: number;
  readonly retention: number;
  /** Fluxo da firma, antes da dívida — só na via da firma. */
  readonly firmFlow: number | null;
  /** Serviço líquido da dívida — só na via da firma. */
  readonly debtService: number | null;
  /** Fluxo do acionista do ano, o que se desconta. */
  readonly flow: number;
  readonly rate: number;
  /** `fluxo ÷ fator = valor presente`. */
  readonly discountFactor: number;
  readonly presentValue: number;

  constructor(args: {
    year: number;
    growth: number;
    plannedGrowth: number;
    profit: number;
    retention: number;
    firmFlow?: number | null;
    debtService?: number | null;
    flow: number;
    rate: number;
    discountFactor: number;
    presentValue: number;
  }) {
    this.year = args.year;
    this.growth = args.growth;
    this.plannedGrowth = args.plannedGrowth;
    this.profit = args.profit;
    this.retention = args.retention;
    this.firmFlow = args.firmFlow ?? null;
    this.debtService = args.debtService ?? null;
    this.flow = args.flow;
    this.rate = args.rate;
    this.discountFactor = args.discountFactor;
    this.presentValue = args.presentValue;
  }
}

/** O resultado de um cálculo do usuário. Valores agregados em reais. */
export class ManualOutcome {
  readonly fairValuePerShare: number;
  readonly equityValue: number;
  readonly explicitPresentValue: number;
  readonly terminalValue: number;
  readonly terminalPresentValue: number;
  readonly minorityInterest: number;
  readonly postStatementCapital: number;
  readonly terminalRate: number;
  /** Custo médio do capital de cada ano — só na via da firma. */
  readonly capitalCostRates: readonly number[] | null;
  readonly terminalCapitalCost: number | null;
  readonly terminalKind: ManualTerminal;
  readonly years: readonly ManualYear[];
  readonly notices: readonly ManualNotice[];

  constructor(args: {
    fairValuePerShare: number;
    equityValue: number;
    explicitPresentValue: number;
    terminalValue: number;
    terminalPresentValue: number;
    minorityInterest: number;
    postStatementCapital: number;
    terminalRate: number;
    capitalCostRates?: readonly number[] | null;
    terminalCapitalCost?: number | null;
    terminalKind: ManualTerminal;
    years: readonly ManualYear[];
    notices: readonly ManualNotice[];
  }) {
    this.fairValuePerShare = args.fairValuePerShare;
    this.equityValue = args.equityValue;
    this.explicitPresentValue = args.explicitPresentValue;
    this.terminalValue = args.terminalValue;
    this.terminalPresentValue = args.terminalPresentValue;
    this.minorityInterest = args.minorityInterest;
    this.postStatementCapital = args.postStatementCapital;
    this.terminalRate = args.terminalRate;
    this.capitalCostRates = args.capitalCostRates ?? null;
    this.terminalCapitalCost = args.terminalCapitalCost ?? null;
    this.terminalKind = args.terminalKind;
    this.years = args.years;
    this.notices = args.notices;
  }
}

/** Um degrau de "onde você discorda do motor". */
export class ManualStep {
  /** Os grupos aplicados neste degrau. */
  readonly groups: readonly ManualGroup[];
  /** Preço justo antes do degrau. */
  readonly from: number;
  /** Preço justo depois do degrau, ou `null` quando a conta não fecha. */
  readonly to: number | null;

  constructor(args: { groups: readonly ManualGroup[]; from: number; to?: number | null }) {
    this.groups = args.groups;
    this.from = args.from;
    this.to = args.to ?? null;
  }

  /** Quanto o degrau moveu o preço, ou `null` quando a conta não fecha. */
  get delta(): number | null {
    return this.to === null ? null : this.to - this.from;
  }
}

/** A resposta de "o que o preço de hoje supõe". */
export class ManualSolution {
  readonly field: ManualField;
  readonly target: number;
  /** O valor do campo que leva o preço justo a [target], ou `null`. */
  readonly value: number | null;
  /** Sem solução: o valor que chega mais perto, e o preço que ele dá. */
  readonly closestValue: number | null;
  readonly closestPrice: number | null;

  constructor(args: {
    field: ManualField;
    target: number;
    value?: number | null;
    closestValue?: number | null;
    closestPrice?: number | null;
  }) {
    this.field = args.field;
    this.target = args.target;
    this.value = args.value ?? null;
    this.closestValue = args.closestValue ?? null;
    this.closestPrice = args.closestPrice ?? null;
  }
}

interface RateSet {
  readonly years: readonly number[];
  readonly terminal: number;
}

/** O mesmo tratamento que a rota derivada dá aos minoritários. */
function nonNegative(v: number): number {
  return Number.isFinite(v) && v > 0 ? v : 0.0;
}

/** `true` quando o grupo [g] difere entre [a] e [b]. */
function differs(g: ManualGroup, a: ManualPremises, b: ManualPremises): boolean {
  switch (g) {
    case ManualGroup.profit:
      return a.baseProfit !== b.baseProfit;
    case ManualGroup.growth:
      return a.growth !== b.growth || a.growthPath !== b.growthPath;
    case ManualGroup.reinvestment:
      return (
        a.reinvestment !== b.reinvestment ||
        a.returnOnCapital !== b.returnOnCapital ||
        (b.reinvestment === ManualReinvestment.fixedFraction && a.retention !== b.retention)
      );
    case ManualGroup.rate:
      return a.discountRate !== b.discountRate || a.ratePath !== b.ratePath;
    case ManualGroup.perpetuity:
      return a.perpetualGrowth !== b.perpetualGrowth;
    default:
      return a.terminalReturn !== b.terminalReturn;
  }
}

/** [current] com os campos do grupo [g] trocados pelos de [target]. */
function apply(g: ManualGroup, current: ManualPremises, target: ManualPremises): ManualPremises {
  switch (g) {
    case ManualGroup.profit:
      return current.copyWith({ baseProfit: target.baseProfit });
    case ManualGroup.growth:
      return current.copyWith({ growth: target.growth, growthPath: target.growthPath });
    case ManualGroup.reinvestment:
      return current.copyWith({
        reinvestment: target.reinvestment,
        returnOnCapital: target.returnOnCapital,
        retention: target.retention,
      });
    case ManualGroup.rate:
      return current.copyWith({ discountRate: target.discountRate, ratePath: target.ratePath });
    case ManualGroup.perpetuity:
      return current.copyWith({ perpetualGrowth: target.perpetualGrowth });
    default:
      return current.copyWith({ terminalReturn: target.terminalReturn });
  }
}

/** Menor de uma lista, como o `reduce((x, y) => x < y ? x : y)` do original. */
function smallest(values: readonly number[]): number {
  let acc = values[0]!;
  for (let i = 1; i < values.length; i++) {
    const y = values[i]!;
    acc = acc < y ? acc : y;
  }
  return acc;
}

/**
 * **A conta do motor congelada**, para o usuário refazê-la com os números
 * dele (decisão 147). Sem nenhuma troca, o resultado é o preço justo do
 * motor; cada troca muda só a premissa trocada. **O que ele não faz é
 * revalidar.**
 */
export class ManualValuation {
  /** Via da avaliação do motor. */
  readonly lane: ValuationLane;
  /** Papéis da ponte — a contagem que forma a cotação. */
  readonly shares: number;
  readonly marketPrice: number;
  /** Preço justo do motor por papel, antes do arredondamento ao centavo. */
  readonly engineFairValue: number;
  /** Fluxo-base do motor, na unidade da via. */
  readonly engineBase: number;
  /** Lucro do último exercício publicado, em reais e sem normalização. */
  readonly publishedBase: number | null;
  /** Fator de normalização que o motor aplicou ao último exercício. */
  readonly baseFactor: number;
  /** `true` quando o fluxo-base foi reconstruído do ciclo (decisão 53). */
  readonly rebuiltBase: boolean;
  /** Premissas finais do motor. */
  readonly engineAssumptions: DcfAssumptions;
  /** Taxa que descontou o fluxo do acionista em cada ano, e a da perpetuidade. */
  readonly engineRates: readonly number[];
  readonly engineTerminalRate: number;
  /** A rota derivada da firma e o `Ke` do centro — só na via da firma. */
  readonly firmRoute: FirmDiscountRoute | null;
  readonly engineEquityRate: number | null;
  readonly engineTerminalEquityRate: number | null;
  readonly engineEquityRatePath: readonly number[] | null;
  /** Capital das emissões depois do balanço, em reais (item B28). */
  readonly postStatementCapital: number;

  constructor(args: {
    lane: ValuationLane;
    shares: number;
    marketPrice: number;
    engineFairValue: number;
    engineBase: number;
    publishedBase?: number | null;
    baseFactor?: number;
    rebuiltBase?: boolean;
    engineAssumptions: DcfAssumptions;
    engineRates: readonly number[];
    engineTerminalRate: number;
    firmRoute?: FirmDiscountRoute | null;
    engineEquityRate?: number | null;
    engineTerminalEquityRate?: number | null;
    engineEquityRatePath?: readonly number[] | null;
    postStatementCapital?: number;
  }) {
    this.lane = args.lane;
    this.shares = args.shares;
    this.marketPrice = args.marketPrice;
    this.engineFairValue = args.engineFairValue;
    this.engineBase = args.engineBase;
    this.publishedBase = args.publishedBase ?? null;
    this.baseFactor = args.baseFactor ?? 1.0;
    this.rebuiltBase = args.rebuiltBase ?? false;
    this.engineAssumptions = args.engineAssumptions;
    this.engineRates = args.engineRates;
    this.engineTerminalRate = args.engineTerminalRate;
    this.firmRoute = args.firmRoute ?? null;
    this.engineEquityRate = args.engineEquityRate ?? null;
    this.engineTerminalEquityRate = args.engineTerminalEquityRate ?? null;
    this.engineEquityRatePath = args.engineEquityRatePath ?? null;
    this.postStatementCapital = args.postStatementCapital ?? 0.0;
  }

  /** Anos de projeção explícita. */
  get projectionYears(): number {
    return this.engineAssumptions.projectionYears;
  }

  /** `true` quando a empresa é concessão com prazo. */
  get isConcession(): boolean {
    return this.engineAssumptions.contractYearsAfterHorizon !== null;
  }

  /** Quanto um real de lucro por papel vale em reais agregados. */
  private get scale(): number {
    return this.lane === ValuationLane.shareholder ? this.shares : 1.0;
  }

  /** As premissas do motor, no vocabulário do usuário. */
  get enginePremises(): ManualPremises {
    return new ManualPremises({
      baseProfit: this.engineBase * this.scale,
      growth: this.engineAssumptions.growthRate,
      discountRate: this.engineRates[0]!,
      perpetualGrowth: this.engineAssumptions.perpetualGrowth,
      returnOnCapital: this.engineAssumptions.returnOnCapital,
      // A parcela do primeiro ano do motor é o ponto de partida de quem troca
      // o reinvestimento pelo retorno pela parcela fixa.
      retention: this.engineAssumptions.retentionAt(1),
      terminalReturn: this.engineAssumptions.terminalReturnOnCapital,
    });
  }

  /** `true` quando a taxa das premissas é exatamente a do motor. */
  private isEngineRate(p: ManualPremises): boolean {
    return p.ratePath === ManualRatePath.engine && p.discountRate === this.engineRates[0];
  }

  /** A taxa de cada ano e a da perpetuidade, sob as premissas. */
  private rates(p: ManualPremises): RateSet {
    if (p.ratePath === ManualRatePath.engine) {
      const d = p.discountRate - this.engineRates[0]!;
      return { years: this.engineRates.map((r) => r + d), terminal: this.engineTerminalRate + d };
    }
    return { years: new Array<number>(this.projectionYears).fill(p.discountRate), terminal: p.discountRate };
  }

  /**
   * As premissas do motor com as do usuário no lugar. Cada troca só acontece
   * quando o campo difere do motor.
   */
  private assumptions(p: ManualPremises, rates: RateSet): DcfAssumptions {
    const m = this.enginePremises;
    let a = this.engineAssumptions;
    // **Na via do acionista a taxa das premissas é o `Ke`**, e a do usuário
    // entra nela. **Na da firma, não**: a taxa do usuário entra só no `Ke` que
    // desconta o fluxo do acionista (medido e decidido em 11/10/2026).
    if (!this.isEngineRate(p) && this.lane === ValuationLane.shareholder) {
      a = a.copyWith({
        discountRatePath: rates.years,
        discountRate: rates.years[0]!,
        terminalDiscountRate: rates.terminal,
      });
    }
    if (p.growth !== m.growth) a = a.copyWith({ growthRate: p.growth });
    if (p.growthPath === ManualGrowthPath.constant) {
      a = a.copyWith({ growthPath: new Array<number>(this.projectionYears).fill(p.growth) });
    }
    if (p.perpetualGrowth !== m.perpetualGrowth) {
      a = a.copyWith({ perpetualGrowth: p.perpetualGrowth });
    }
    if (p.returnOnCapital !== m.returnOnCapital) {
      a = a.copyWith({ returnOnCapital: p.returnOnCapital });
    }
    if (p.reinvestment === ManualReinvestment.fixedFraction) {
      // O terminal neutro sai: com a parcela fixa, é Gordon com ela.
      a = a.copyWith({
        reinvestmentPolicy: ReinvestmentPolicy.fixedFraction,
        fixedRetention: p.retention,
        neutralTerminalReturn: false,
      });
    }
    if (p.terminalReturn !== m.terminalReturn) {
      a = a.withTerminalReturnOnCapital(p.terminalReturn);
    }
    return a;
  }

  /**
   * Refaz a conta do motor com as premissas [p]. Recusa com [InvalidInput] e
   * o campo nomeado quando a premissa não tem conta.
   */
  evaluate(p: ManualPremises): Result<ManualOutcome> {
    if (!Number.isFinite(p.baseProfit) || p.baseProfit <= 0) {
      return err(
        new InvalidInput('Lucro de partida não positivo: o fluxo descontado parte dele.', {
          field: ManualField.baseProfit.name,
          actual: p.baseProfit,
          limit: 0,
          unit: QuantityUnit.currency,
        }),
      );
    }
    if (
      p.reinvestment === ManualReinvestment.fixedFraction &&
      (!Number.isFinite(p.retention) || p.retention < 0 || p.retention >= 1)
    ) {
      return err(
        new InvalidInput(
          'Parcela reinvestida fora de [0, 100%): reinvestir tudo para sempre ' + 'não deixa nada ao acionista.',
          { field: ManualField.retention.name, actual: p.retention, limit: 1, unit: QuantityUnit.fraction },
        ),
      );
    }
    const tr = p.terminalReturn;
    if (tr !== null && (!Number.isFinite(tr) || tr <= 0)) {
      return err(
        new InvalidInput('Retorno do capital novo na perpetuidade não positivo.', {
          field: ManualField.terminalReturn.name,
          actual: tr,
          limit: 0,
          unit: QuantityUnit.fraction,
        }),
      );
    }
    if (!Number.isFinite(p.growth) || p.growth <= -1) {
      return err(
        new InvalidInput('Crescimento que zera o lucro.', {
          field: ManualField.growth.name,
          actual: p.growth,
          limit: -1,
          unit: QuantityUnit.fraction,
        }),
      );
    }
    if (!Number.isFinite(p.perpetualGrowth) || p.perpetualGrowth <= -1) {
      return err(
        new InvalidInput('Crescimento perpétuo que zera o lucro.', {
          field: ManualField.perpetualGrowth.name,
          actual: p.perpetualGrowth,
          limit: -1,
          unit: QuantityUnit.fraction,
        }),
      );
    }
    if (!Number.isFinite(p.returnOnCapital)) {
      return err(
        new InvalidInput('Retorno sobre o capital não finito.', { field: ManualField.returnOnCapital.name }),
      );
    }
    const rates = this.rates(p);
    const lowestRate = smallest([...rates.years, rates.terminal]);
    if (!Number.isFinite(lowestRate) || lowestRate <= 0) {
      return err(
        new InvalidInput('Taxa de desconto não positiva em algum ano.', {
          field: ManualField.discountRate.name,
          actual: lowestRate,
          limit: 0,
          unit: QuantityUnit.fraction,
        }),
      );
    }

    const a = this.assumptions(p, rates);
    const base = p.baseProfit === this.enginePremises.baseProfit ? this.engineBase : p.baseProfit / this.scale;
    let discountedOutcome: Result<DcfOutcome>;
    if (this.lane === ValuationLane.shareholder) {
      discountedOutcome = DcfCalculator.shareholder({ baseProfit: base, assumptions: a });
    } else {
      const route = this.firmRoute;
      if (route === null) {
        return err(new ComputationFailure('Avaliação da via da firma sem a rota da dívida congelada.'));
      }
      const fromEngine = this.isEngineRate(p);
      discountedOutcome = route.discount({
        baseProfit: base,
        assumptions: a,
        equityDiscountRate: fromEngine ? (this.engineEquityRate ?? rates.years[0]!) : rates.years[0]!,
        terminalEquityDiscountRate: fromEngine ? (this.engineTerminalEquityRate ?? rates.terminal) : rates.terminal,
        equityDiscountRatePath: fromEngine ? this.engineEquityRatePath : rates.years,
      });
    }

    return discountedOutcome.fold<Result<ManualOutcome>>(
      (o) => ok(this.result(p, a, o, rates)),
      (failure) => err(this.translate(failure, p, a, rates)),
    );
  }

  /** A recusa da calculadora, nomeando o campo quando é a margem da perpetuidade. */
  private translate(failure: Failure, p: ManualPremises, a: DcfAssumptions, rates: RateSet): Failure {
    const margins = [rates.terminal - p.perpetualGrowth];
    if (this.lane === ValuationLane.firm) margins.push(a.terminalDiscountRate - p.perpetualGrowth);
    const smaller = smallest(margins);
    if (smaller < DcfCalculator.minimumSpread) {
      return new InvalidInput(
        'A taxa de desconto da perpetuidade não supera o crescimento perpétuo ' +
          'pela margem mínima: a perpetuidade não tem valor finito.',
        {
          field: ManualField.perpetualGrowth.name,
          actual: smaller,
          limit: DcfCalculator.minimumSpread,
          unit: QuantityUnit.fraction,
        },
      );
    }
    return failure;
  }

  private result(p: ManualPremises, a: DcfAssumptions, o: DcfOutcome, rates: RateSet): ManualOutcome {
    const e = this.scale;
    const n = o.projectedFlows.length;
    const profits = o.projectedProfits;
    const retentions = o.retentions;
    const growthRates = o.growthRates;
    const factors = o.discountFactors;
    const years: ManualYear[] = [];
    for (let i = 0; i < n; i++) {
      years.push(
        new ManualYear({
          year: i + 1,
          growth: growthRates?.[i] ?? a.growthAt(i + 1),
          plannedGrowth: a.plannedGrowthAt(i + 1),
          profit: (profits?.[i] ?? NaN) * e,
          retention: retentions?.[i] ?? a.retentionAt(i + 1),
          firmFlow: o.firmFlows?.[i] ?? null,
          debtService: o.debtService?.[i] ?? null,
          flow: o.projectedFlows[i]! * e,
          rate: o.discountRates?.[i] ?? rates.years[i]!,
          discountFactor: factors?.[i] ?? NaN,
          presentValue: o.discountedFlows[i]! * e,
        }),
      );
    }
    let discountedSum = 0.0;
    for (const v of o.discountedFlows) discountedSum = discountedSum + v;
    const explicitValue = discountedSum * e;
    const terminalPv = o.discountedTerminalValue * e;
    const route = this.firmRoute;
    const minorityValue = this.lane === ValuationLane.firm && route !== null ? nonNegative(route.minorityInterest) : 0.0;
    const capital = this.postStatementCapital > 0 && this.shares > 0 ? this.postStatementCapital : 0.0;
    const perShare = o.fairValuePerShare + (this.shares > 0 ? capital / this.shares : 0);

    let kind: ManualTerminal;
    if (a.reinvestmentPolicy === ReinvestmentPolicy.fixedFraction) {
      kind = ManualTerminal.fixedFraction;
    } else if (a.terminalReturnOnCapital !== null) {
      kind = ManualTerminal.advantage;
    } else if (a.contractYearsAfterHorizon !== null && a.returnOnCapital > 0) {
      kind = ManualTerminal.contract;
    } else {
      kind = ManualTerminal.neutral;
    }

    const warnings: ManualNotice[] = [];
    const confinedValues = years.filter((y) => y.plannedGrowth - y.growth > 1e-9).map((y) => y.year);
    if (confinedValues.length > 0) {
      warnings.push(new ManualNotice(ManualNoticeKind.confinedGrowth, { years: confinedValues }));
    }
    const negatives = years.filter((y) => y.flow < 0).map((y) => y.year);
    if (negatives.length > 0) {
      warnings.push(new ManualNotice(ManualNoticeKind.negativeFlow, { years: negatives }));
    }
    if (this.isConcession && kind !== ManualTerminal.contract) {
      warnings.push(new ManualNotice(ManualNoticeKind.perpetualConcession));
    }
    if (kind === ManualTerminal.neutral && p.perpetualGrowth !== this.enginePremises.perpetualGrowth) {
      warnings.push(new ManualNotice(ManualNoticeKind.neutralPerpetuity));
    }

    const capitalCostRates: number[] = [];
    for (let t = 1; t <= n; t++) capitalCostRates.push(a.discountRateAt(t));
    return new ManualOutcome({
      fairValuePerShare: perShare,
      equityValue: explicitValue + terminalPv - minorityValue + capital,
      explicitPresentValue: explicitValue,
      terminalValue: o.terminalValue * e,
      terminalPresentValue: terminalPv,
      minorityInterest: minorityValue,
      postStatementCapital: capital,
      terminalRate: o.terminalDiscountRateUsed ?? rates.terminal,
      capitalCostRates: this.lane === ValuationLane.firm ? Object.freeze(capitalCostRates) : null,
      terminalCapitalCost: this.lane === ValuationLane.firm ? a.terminalDiscountRate : null,
      terminalKind: kind,
      years: Object.freeze(years),
      notices: Object.freeze(warnings),
    });
  }

  /**
   * **Onde o usuário discorda do motor**: do preço do motor ao dele, um grupo
   * de premissas de cada vez, na ordem de [ManualGroup]. Um grupo que,
   * sozinho, deixa a conta sem valor finito é somado ao seguinte.
   */
  attribution(p: ManualPremises): readonly ManualStep[] {
    const m = this.enginePremises;
    const start = this.evaluate(m).valueOrNull?.fairValuePerShare ?? this.engineFairValue;
    let current = m;
    let previous = start;
    const pending: ManualGroup[] = [];
    const steps: ManualStep[] = [];
    for (const g of ManualGroup.values) {
      if (!differs(g, m, p)) continue;
      current = apply(g, current, p);
      pending.push(g);
      const r = this.evaluate(current).valueOrNull;
      if (r === null) continue;
      steps.push(new ManualStep({ groups: Object.freeze([...pending]), from: previous, to: r.fairValuePerShare }));
      previous = r.fairValuePerShare;
      pending.length = 0;
    }
    if (pending.length > 0) {
      steps.push(new ManualStep({ groups: Object.freeze([...pending]), from: previous }));
    }
    return Object.freeze(steps);
  }

  /** Faixa examinada por [solve] para cada campo. */
  private band(f: ManualField): [number, number] {
    switch (f) {
      case ManualField.baseProfit:
        return [this.enginePremises.baseProfit * 0.001, this.enginePremises.baseProfit * 50];
      case ManualField.growth:
        return [-0.5, 1.0];
      case ManualField.discountRate:
        return [0.001, 0.6];
      case ManualField.perpetualGrowth:
        return [-0.2, 0.3];
      case ManualField.returnOnCapital:
        return [0.001, 1.5];
      case ManualField.retention:
        return [0.0, 0.999];
      default:
        return [0.001, 1.0];
    }
  }

  /**
   * **O que o preço de hoje supõe**: o valor de [field] que leva o preço justo
   * a [target] — o de mercado, quando omitido. Grade de 400 pontos, primeira
   * troca de sinal refinada por bisseção; sem troca, o mais próximo.
   */
  solve(field: ManualField, from: ManualPremises, options: { target?: number | null } = {}): ManualSolution {
    const targetValue = options.target ?? this.marketPrice;
    const deviation = (v: number): number | null => {
      const r = this.evaluate(from.withValue(field, v)).valueOrNull;
      if (r === null || !Number.isFinite(r.fairValuePerShare)) return null;
      return r.fairValuePerShare - targetValue;
    };

    const [lo, hi] = this.band(field);
    const points = 400;
    let a: number | null = null;
    let fa: number | null = null;
    let b: number | null = null;
    let best: number | null = null;
    let bestDeviation: number | null = null;
    for (let i = 0; i <= points; i++) {
      const v = lo + ((hi - lo) * i) / points;
      const fv = deviation(v);
      if (fv === null) continue;
      if (bestDeviation === null || Math.abs(fv) < Math.abs(bestDeviation)) {
        best = v;
        bestDeviation = fv;
      }
      if (fa !== null && fa <= 0 !== fv <= 0) {
        b = v;
        break;
      }
      a = v;
      fa = fv;
    }
    if (a === null || fa === null || b === null) {
      return new ManualSolution({
        field,
        target: targetValue,
        closestValue: best,
        closestPrice: bestDeviation === null ? null : bestDeviation + targetValue,
      });
    }
    let left = a;
    let dir = b;
    let fLeft = fa;
    for (let i = 0; i < 80; i++) {
      const mid = (left + dir) / 2;
      const fm = deviation(mid);
      if (fm === null) break;
      if (fLeft <= 0 === fm <= 0) {
        left = mid;
        fLeft = fm;
      } else {
        dir = mid;
      }
    }
    return new ManualSolution({ field, target: targetValue, value: (left + dir) / 2 });
  }
}
