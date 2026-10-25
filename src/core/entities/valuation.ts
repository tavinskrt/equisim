import { DartEnum, type WireKeyed } from '../lang/dart-enum';
import type { DateTime } from '../lang/date-time';
import { clamp, floor, ceil, reduce } from '../lang';
import type { BaseNormalization } from '../services/valuation/base-normalization';
import type { ManualValuation } from '../services/valuation/manual-valuation';
import type { PeerTriangulation } from '../services/valuation/peer-multiples';
import type { Money } from '../value-objects/money';
import type { Ticker } from '../value-objects/ticker';

/**
 * Modelo efetivamente aplicado no cálculo.
 *
 * O modelo **faz parte do resultado**, não é detalhe interno: cair
 * silenciosamente para um modelo inferior e apresentar o número como "preço
 * justo" esconde do usuário a qualidade da estimativa.
 */
export class ValuationModel extends DartEnum {
  /**
   * Fluxo da firma, descontado ao WACC. `NOPAT × (1 − RI)`, com freio de
   * reinvestimento — a decisão 25 estendeu à firma a correção que a 24 fizera
   * só do lado do acionista.
   */
  static readonly dcfFcff = new ValuationModel('dcfFcff', 0);

  /**
   * DCF sobre lucro distribuível, descontado ao Ke. O fluxo é `LPA × (1 − b)`;
   * o dividendo vem da identidade da retenção, não de dado publicado de
   * provento — o que o mantém compatível com a decisão 23.
   */
  static readonly dcfEarnings = new ValuationModel('dcfEarnings', 1);

  static readonly values: readonly ValuationModel[] = [ValuationModel.dcfFcff, ValuationModel.dcfEarnings];

  protected get typeName(): string {
    return 'ValuationModel';
  }
}

/** Como os cenários foram gerados. */
export class ScenarioMode extends DartEnum {
  /** Três conjuntos fixos de premissas. Preenche `discreteScenarios`. */
  static readonly discrete = new ScenarioMode('discrete', 0);

  /** Premissas sorteadas de distribuições triangulares. Preenche `distribution`. */
  static readonly monteCarlo = new ScenarioMode('monteCarlo', 1);

  static readonly values: readonly ScenarioMode[] = [ScenarioMode.discrete, ScenarioMode.monteCarlo];

  protected get typeName(): string {
    return 'ScenarioMode';
  }
}

/** Faixas nomeadas apresentadas ao usuário. */
export class ScenarioBand extends DartEnum {
  /** Crescimento deslocado para baixo e desconto para cima. */
  static readonly bear = new ScenarioBand('bear', 0);

  /** Premissas centrais. É o cenário cujo valor vira o preço justo. */
  static readonly base = new ScenarioBand('base', 1);

  /** Crescimento para cima e desconto para baixo, respeitado o spread mínimo. */
  static readonly bull = new ScenarioBand('bull', 2);

  static readonly values: readonly ScenarioBand[] = [ScenarioBand.bear, ScenarioBand.base, ScenarioBand.bull];

  protected get typeName(): string {
    return 'ScenarioBand';
  }
}

/** Distribuição de valores justos produzida pelo motor de cenários. */
export class ValueDistribution {
  /** Valores por ação, ordenados crescentemente. */
  readonly sortedValues: readonly number[];

  /**
   * Envolve uma lista **já ordenada**. Não ordena nem copia — ordenar é
   * responsabilidade de quem constrói, e `ScenarioEngine.run` o faz.
   */
  constructor(sortedValues: readonly number[]) {
    this.sortedValues = sortedValues;
  }

  /** `true` quando nenhum cenário produziu valor válido. */
  get isEmpty(): boolean {
    return this.sortedValues.length === 0;
  }

  /**
   * Percentil por interpolação linear. [p] em [0, 1], travado nas pontas.
   * Devolve `0.0` para distribuição vazia, e o único elemento quando há
   * apenas um.
   */
  percentile(p: number): number {
    const v = this.sortedValues;
    if (v.length === 0) return 0.0;
    if (v.length === 1) return v[0]!;
    const position = clamp(p, 0.0, 1.0) * (v.length - 1);
    const lower = floor(position);
    const upper = ceil(position);
    if (lower === upper) return v[lower]!;
    const fraction = position - lower;
    return v[lower]! * (1 - fraction) + v[upper]! * fraction;
  }

  /** Percentil 5 — borda pessimista da banda apresentada. */
  get p5(): number {
    return this.percentile(0.05);
  }

  /** Mediana — preferida à [mean] por não ser arrastada pela cauda direita. */
  get median(): number {
    return this.percentile(0.5);
  }

  /** Percentil 95 — borda otimista da banda apresentada. */
  get p95(): number {
    return this.percentile(0.95);
  }

  /** Média aritmética. Devolve `0.0` para distribuição vazia. */
  get mean(): number {
    return this.sortedValues.length === 0
      ? 0.0
      : reduce(this.sortedValues, (a, b) => a + b) / this.sortedValues.length;
  }

  /**
   * Proporção de cenários em que o valor justo supera [price]. A comparação
   * é estrita.
   */
  probabilityAbove(price: number): number {
    if (this.sortedValues.length === 0) return 0.0;
    const count = this.sortedValues.filter((v) => v > price).length;
    return count / this.sortedValues.length;
  }
}

/**
 * Por que a estimativa perdeu confiança.
 *
 * Cada item é um **fato medido** no caminho do cálculo, não um julgamento.
 * Estruturá-los é o que permite ao consumidor ponderar o preço justo em vez de
 * tratar todos como igualmente firmes.
 */
export class ValuationCaveat extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /**
   * O valor terminal responde por mais que
   * [ValuationDiagnostics.terminalShareLimit] do total.
   */
  static readonly heavyTerminal = new ValuationCaveat('heavyTerminal', 0, 'terminalPesado');

  /** A taxa de crescimento não veio do próprio ativo. */
  static readonly unidentifiedGrowth = new ValuationCaveat('unidentifiedGrowth', 1, 'crescimentoNaoIdentificado');

  /** As duas contagens de papéis publicadas divergem além de uma ação societária plausível. */
  static readonly uncertainScale = new ValuationCaveat('uncertainScale', 2, 'escalaIncerta');

  /** Um único exercício foi multiplicado por mais de [ValuationDiagnostics.baseFactorLimit]. */
  static readonly strongNormalizedBase = new ValuationCaveat('strongNormalizedBase', 3, 'baseNormalizadaForte');

  /**
   * A avaliação começou na via da firma e migrou para a do acionista.
   * **Não é mais emitida desde a decisão 102.**
   */
  static readonly migratedLane = new ValuationCaveat('migratedLane', 4, 'viaMigrada');

  /** O capital próprio responde por pouco do valor da firma. */
  static readonly fragileBridge = new ValuationCaveat('fragileBridge', 5, 'ponteFragil');

  /**
   * O preço justo é combinação das duas vias. **Não é mais emitida desde a
   * decisão 102.**
   */
  static readonly mergedLanes = new ValuationCaveat('mergedLanes', 6, 'viasMescladas');

  /**
   * O fluxo-base foi reconstruído do retorno mediano do ciclo sobre o capital
   * de hoje. **É a ressalva mais forte da lista.**
   */
  static readonly rebuiltBase = new ValuationCaveat('rebuiltBase', 7, 'baseReconstruida');

  /** O negócio opera sob contrato de prazo determinado, e o terminal supõe perpetuidade. */
  static readonly fixedTerm = new ValuationCaveat('fixedTerm', 8, 'prazoDeterminado');

  /**
   * A companhia é de controle estatal, e o motor não cobra prêmio por isso
   * (item B46). **A ressalva informa, e não corrige.**
   */
  static readonly stateControl = new ValuationCaveat('stateControl', 9, 'controleEstatal');

  static readonly values: readonly ValuationCaveat[] = [
    ValuationCaveat.heavyTerminal,
    ValuationCaveat.unidentifiedGrowth,
    ValuationCaveat.uncertainScale,
    ValuationCaveat.strongNormalizedBase,
    ValuationCaveat.migratedLane,
    ValuationCaveat.fragileBridge,
    ValuationCaveat.mergedLanes,
    ValuationCaveat.rebuiltBase,
    ValuationCaveat.fixedTerm,
    ValuationCaveat.stateControl,
  ];

  /** Chave gravada nas saídas. É dado, e não nome de código. */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'ValuationCaveat';
  }
}

/**
 * Fatos medidos que qualificam o preço justo.
 *
 * **Por que existe.** Um preço justo cujo valor terminal responde por 85% do
 * total, cuja taxa veio da inflação e cujo divisor é ambíguo não é o mesmo
 * objeto que um apoiado em crescimento identificado e escala conciliada. Tudo
 * aqui já era apurado pela cascata; o que muda é que passa a sair com o
 * resultado, em forma que a máquina lê.
 *
 * **Não existe nota de confiança aqui, e a ausência é medida** (decisão 32): a
 * nota ordinal derivada da contagem de ressalvas ordenava ao contrário do que
 * prometia. O que fica são os **fatos**.
 */
export class ValuationDiagnostics {
  /**
   * Parcela do preço justo explicada pelo valor terminal, em fração. **É
   * contra o capital próprio, nas três rotas** (decisão 51). Pode passar de 1.
   */
  readonly terminalShare: number;

  /** Participação do capital próprio no valor da firma. `1.0` na via do acionista. */
  readonly equityShare: number;

  /** Fator de normalização aplicado ao exercício-base. */
  readonly baseFactor: number;

  /** `true` quando a taxa de crescimento saiu do próprio histórico. */
  readonly growthIdentified: boolean;

  /** `true` quando a perpetuidade preserva excedente de retorno (ver [terminalRetainedSpread]). */
  readonly moatApplied: boolean;

  /** Fração do excedente de retorno preservada na perpetuidade — o `λ = φ^N` da decisão 36. */
  readonly terminalRetainedSpread: number;

  /** Crescimento do primeiro ano da projeção explícita, antes do decaimento. */
  readonly growthRate: number;

  /**
   * Retorno terminal efetivamente aplicado, ou `null` no estado estacionário.
   * `r_∞ + λ·(ROIC_do_ciclo − r_∞)`.
   */
  readonly terminalReturnOnCapital: number | null;

  /** Alíquota estrutural aplicada ao NOPAT da via da firma; `null` na via do acionista. */
  readonly firmTaxRate: number | null;

  /** Retorno sobre o capital do fluxo-base, o denominador do freio. */
  readonly returnOnCapital: number;

  /**
   * Custo de capital de equilíbrio — a taxa que desconta a perpetuidade. A
   * taxa decai do CDI corrente até esta ao longo da projeção (decisão 31).
   */
  readonly terminalDiscountRate: number;

  /** Custo do capital próprio de **equilíbrio resolvido** (decisão 41), ou `null`. */
  readonly terminalCostOfEquity: number | null;

  /** Crescimento **aplicado** em cada ano explícito. */
  readonly growthPath: readonly number[];

  /** Retenção aplicada em cada ano explícito — o `b_t = g_t/ROIC_t` do freio. */
  readonly retentionPath: readonly number[];

  /**
   * Custo do capital próprio do ativo pelo CAPM, sobre a taxa livre de risco
   * **corrente** — o retorno esperado incondicional do papel (decisão 58).
   */
  readonly costOfEquity: number;

  /**
   * Parcela do preço justo que vem do **excedente perpétuo do capital
   * instalado**, em fração (item B12). Pode ser negativa.
   */
  readonly terminalExcessShare: number | null;

  /** Retorno que a perpetuidade supõe sobre o capital instalado: `lucro_{N+1} ÷ capital_N` (item B12). */
  readonly impliedTerminalReturn: number | null;

  /** Participação do capital próprio no valor da firma **no ano N** (item B15). */
  readonly terminalEquityShare: number | null;

  /** Capital das emissões de ações por valor **depois** do balanço usado, em reais (item B28). */
  readonly postStatementCapital: number | null;

  /** A decisão da normalização do lucro de partida, com o que a decidiu. **Explica, e não recalcula.** */
  readonly baseNormalization: BaseNormalization | null;

  /** Ressalvas medidas, na ordem em que a cascata as apura. */
  readonly caveats: readonly ValuationCaveat[];

  constructor(args: {
    terminalShare: number;
    equityShare: number;
    baseFactor: number;
    growthIdentified: boolean;
    moatApplied: boolean;
    terminalDiscountRate: number;
    terminalRetainedSpread: number;
    growthRate: number;
    returnOnCapital: number;
    terminalReturnOnCapital?: number | null;
    firmTaxRate?: number | null;
    terminalCostOfEquity?: number | null;
    costOfEquity: number;
    retentionPath?: readonly number[];
    growthPath?: readonly number[];
    terminalExcessShare?: number | null;
    impliedTerminalReturn?: number | null;
    terminalEquityShare?: number | null;
    postStatementCapital?: number | null;
    baseNormalization?: BaseNormalization | null;
    caveats?: readonly ValuationCaveat[];
  }) {
    this.terminalShare = args.terminalShare;
    this.equityShare = args.equityShare;
    this.baseFactor = args.baseFactor;
    this.growthIdentified = args.growthIdentified;
    this.moatApplied = args.moatApplied;
    this.terminalDiscountRate = args.terminalDiscountRate;
    this.terminalRetainedSpread = args.terminalRetainedSpread;
    this.growthRate = args.growthRate;
    this.returnOnCapital = args.returnOnCapital;
    this.terminalReturnOnCapital = args.terminalReturnOnCapital ?? null;
    this.firmTaxRate = args.firmTaxRate ?? null;
    this.terminalCostOfEquity = args.terminalCostOfEquity ?? null;
    this.costOfEquity = args.costOfEquity;
    this.retentionPath = args.retentionPath ?? [];
    this.growthPath = args.growthPath ?? [];
    this.terminalExcessShare = args.terminalExcessShare ?? null;
    this.impliedTerminalReturn = args.impliedTerminalReturn ?? null;
    this.terminalEquityShare = args.terminalEquityShare ?? null;
    this.postStatementCapital = args.postStatementCapital ?? null;
    this.baseNormalization = args.baseNormalization ?? null;
    this.caveats = args.caveats ?? [];
  }

  /**
   * Acima disto, o valor terminal domina e a estimativa é rebaixada. **80%**,
   * o topo da faixa que motivou a projeção de dez anos (decisão 25).
   */
  static readonly terminalShareLimit = 0.8;

  /**
   * Acima disto, um único exercício move demais a avaliação inteira. **2,0x**,
   * metade da autoridade que a saturação permite (decisão 28).
   */
  static readonly baseFactorLimit = 2.0;

  /**
   * Acima disto em módulo, o excedente perpétuo do capital instalado é
   * declarado na avaliação (item B12). Ver `docs/validacao/terminal_excedente.md`.
   */
  static readonly terminalExcessLimit = 0.2;

  /**
   * Abaixo disto a ponte é frágil, embora ainda acima do corte que faz
   * migrar. **35%, contra os 20% que reprovam.**
   */
  static readonly fragileEquityShare = 0.35;
}

/** Resultado de uma avaliação de valor intrínseco. */
export class ValuationResult {
  /** Ativo avaliado. */
  readonly ticker: Ticker;

  /** Data de referência da avaliação — define o recorte *point-in-time*. */
  readonly asOf: DateTime;

  /** Modelo que efetivamente produziu [fairValue]. **Faz parte do resultado.** */
  readonly model: ValuationModel;

  /** Preço justo por ação no cenário base. */
  readonly fairValue: Money;

  /** Preço de mercado na data de referência. */
  readonly marketPrice: Money;

  /** Margem de segurança aplicada sobre o preço justo, em fração. */
  readonly marginOfSafety: number;

  /** Como os cenários foram gerados. */
  readonly mode: ScenarioMode;

  /** Preenchido no modo discreto. */
  readonly discreteScenarios: ReadonlyMap<ScenarioBand, Money> | null;

  /** Preenchido no modo Monte Carlo. */
  readonly distribution: ValueDistribution | null;

  /** Custo de capital efetivamente usado no desconto, em fração. */
  readonly discountRate: number;

  /** Avisos acumulados (dados faltantes, aproximações, quedas de modelo). */
  readonly warnings: readonly string[];

  /** Fatos medidos que qualificam o preço justo. `null` só fora da cascata. */
  readonly diagnostics: ValuationDiagnostics | null;

  /**
   * Volatilidade anualizada do papel na janela da avaliação, ou `null` — a
   * escala da faixa calibrada (item C2b), da **mesma série** que a cascata usou.
   */
  readonly priceVolatility: number | null;

  /**
   * A segunda leitura, por múltiplos de pares (item B5, decisão 118). **Não é
   * preço, e não entra em [fairValue].**
   */
  readonly triangulation: PeerTriangulation | null;

  /**
   * A conta do motor congelada, para o usuário refazê-la com os números dele
   * (decisão 147). **Não muda [fairValue].**
   */
  readonly manual: ManualValuation | null;

  constructor(args: {
    ticker: Ticker;
    asOf: DateTime;
    model: ValuationModel;
    fairValue: Money;
    marketPrice: Money;
    discountRate: number;
    marginOfSafety?: number;
    mode?: ScenarioMode;
    discreteScenarios?: ReadonlyMap<ScenarioBand, Money> | null;
    distribution?: ValueDistribution | null;
    warnings?: readonly string[];
    diagnostics?: ValuationDiagnostics | null;
    priceVolatility?: number | null;
    triangulation?: PeerTriangulation | null;
    manual?: ManualValuation | null;
  }) {
    this.ticker = args.ticker;
    this.asOf = args.asOf;
    this.model = args.model;
    this.fairValue = args.fairValue;
    this.marketPrice = args.marketPrice;
    this.discountRate = args.discountRate;
    this.marginOfSafety = args.marginOfSafety ?? 0.0;
    this.mode = args.mode ?? ScenarioMode.discrete;
    this.discreteScenarios = args.discreteScenarios ?? null;
    this.distribution = args.distribution ?? null;
    this.warnings = args.warnings ?? [];
    this.diagnostics = args.diagnostics ?? null;
    this.priceVolatility = args.priceVolatility ?? null;
    this.triangulation = args.triangulation ?? null;
    this.manual = args.manual ?? null;
  }

  /** Ressalvas estruturadas do cálculo, vazias quando não há diagnóstico. */
  get caveats(): readonly ValuationCaveat[] {
    return this.diagnostics?.caveats ?? [];
  }

  /** O mesmo resultado, com [extra] ao fim dos avisos. Nenhum número muda. */
  withWarnings(extra: readonly string[]): ValuationResult {
    if (extra.length === 0) return this;
    return new ValuationResult({
      ticker: this.ticker,
      asOf: this.asOf,
      model: this.model,
      fairValue: this.fairValue,
      marketPrice: this.marketPrice,
      discountRate: this.discountRate,
      marginOfSafety: this.marginOfSafety,
      mode: this.mode,
      discreteScenarios: this.discreteScenarios,
      distribution: this.distribution,
      warnings: Object.freeze([...this.warnings, ...extra]),
      diagnostics: this.diagnostics,
      priceVolatility: this.priceVolatility,
      triangulation: this.triangulation,
      manual: this.manual,
    });
  }

  /** Preço justo já descontado da margem de segurança — o limiar de compra. */
  get safetyPrice(): Money {
    return this.fairValue.times(1.0 - this.marginOfSafety);
  }

  /**
   * Valorização total esperada até o preço justo, em fração. Número
   * **total**, sem prazo — ver `ExpectedReturn.annualizedFromUpside`.
   */
  get upside(): number {
    if (this.marketPrice.cents <= 0) return 0.0;
    return (this.fairValue.reais - this.marketPrice.reais) / this.marketPrice.reais;
  }

  /** `true` quando o preço de mercado está em ou abaixo de [safetyPrice], inclusive. */
  get isUndervalued(): boolean {
    return this.marketPrice.lte(this.safetyPrice);
  }
}
