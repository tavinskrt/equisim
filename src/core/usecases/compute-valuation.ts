/**
 * A cascata de avaliação: insumos já resolvidos entram, preço justo com
 * diagnósticos, avisos e rastro de auditoria sai.
 *
 * Porte isomórfico de `compute_valuation.dart`: mesmas portas, mesmas guardas,
 * mesmos textos e a mesma ordem de avaliação. **Síncrona e pura** — não toca
 * rede nem relógio, e a mesma entrada produz sempre a mesma saída.
 */

import type { AuditTransaction } from '../audit/audit-recorder';
import { AuditRecorder } from '../audit/audit-recorder';
import { TraceSample, TraceSamplePoint, type JsonMap } from '../audit/calculation-trace';
import { FundamentalsSnapshot } from '../entities/fundamentals';
import type { PriceSeries } from '../entities/price-series';
import type { ShareIssue } from '../entities/share-issue';
import {
  ScenarioBand,
  ScenarioMode,
  ValuationCaveat,
  ValuationDiagnostics,
  ValuationModel,
  ValuationResult,
} from '../entities/valuation';
import { ComputationFailure, InsufficientData, InvalidInput } from '../failures/failure';
import { err, ok, type Result } from '../failures/result';
import { DartEnum } from '../lang/dart-enum';
import { DateTime } from '../lang/date-time';
import { clamp, compareNum, round, roundToDouble, str, toStringAsFixed } from '../lang/num';
import { BaseNormalization, BaseNormalizationOutcome } from '../services/valuation/base-normalization';
import { CalibratedBand } from '../services/valuation/calibrated-band';
import { CapitalSeries, ValuationLane } from '../services/valuation/capital-base';
import { ConcessionSectors } from '../services/valuation/concession-sectors';
import { CapmInputs, CostOfCapital, MarketPremiumSource } from '../services/valuation/cost-of-capital';
import { CyclicalSectors } from '../services/valuation/cyclical-sectors';
import {
  CashTiming,
  DcfAssumptions,
  DcfCalculator,
  FirmDiscountRoute,
  ReinvestmentPolicy,
  DcfOutcome,
} from '../services/valuation/dcf';
import { EligibilityGate } from '../services/valuation/eligibility';
import { FinancialSectors } from '../services/valuation/financial-sectors';
import { GrowthEstimator } from '../services/valuation/growth-estimator';
import {
  GrowthGuards,
  GrowthOrigin,
  MoatBlock,
  ValuationParameters,
  type DispersionVerdict,
  type MoatVerdict,
  type TrendVerdict,
} from '../services/valuation/growth-guards';
import { LeveredCostOfCapital, type LeveredRates } from '../services/valuation/levered-rates';
import { ManualValuation } from '../services/valuation/manual-valuation';
import { MoatFixedPoint } from '../services/valuation/moat-fixed-point';
import { MultipleKind, PeerTriangulation, type PeerMultipleSet } from '../services/valuation/peer-multiples';
import { DiscreteScenarios, ScenarioEngine, type AssumptionSource } from '../services/valuation/scenario-engine';
import { CurveVertex, YieldCurve } from '../services/valuation/yield-curve';
import { PointInTimeView } from '../time/point-in-time-view';
import { Money } from '../value-objects/money';
import type { Ticker } from '../value-objects/ticker';
import type { WireKeyed } from '../audit/wire-keyed';

// ------------------------------------------------------------------ insumos --

/**
 * Como o deslocamento do cenário de desconto vira deslocamento do `Ke` na
 * rota derivada (item B20, decisão 121).
 *
 * O cenário perturba `DcfAssumptions.discountRate`. Na via do acionista esse
 * campo **é** o `Ke`, e o deslocamento é um a um por construção. Na via da
 * firma ele é o WACC, e a rota derivada desconta ao `Ke`: traduzir exige
 * escolher **o que o cenário está perturbando**, e ele não diz.
 */
export class ScenarioTranslation extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /**
   * `ΔK_e = ΔWACC`. O cenário perturba **a taxa aplicada ao fluxo**, que é a
   * que esta rota usa — e é o que faz as duas vias quererem dizer a mesma
   * coisa.
   */
  static readonly oneToOne = new ScenarioTranslation('oneToOne', 0, 'umPorUm');

  /** `ΔK_e = ΔWACC ÷ w_E`. O cenário perturba **o custo de capital da firma** com `K_d` e os pesos parados. */
  static readonly fixedStructure = new ScenarioTranslation('fixedStructure', 1, 'estruturaFixa');

  /** `ΔK_e = ΔWACC ÷ (1 − w_D·t)`. O cenário perturba **a taxa livre de risco**, que move `K_e` e `K_d` juntos. */
  static readonly riskFreeRate = new ScenarioTranslation('riskFreeRate', 2, 'taxaLivreDeRisco');

  static readonly values: readonly ScenarioTranslation[] = [
    ScenarioTranslation.oneToOne,
    ScenarioTranslation.fixedStructure,
    ScenarioTranslation.riskFreeRate,
  ];

  /**
   * Chave gravada nas saídas — pacote de dados, rastro de auditoria,
   * relatório. É dado, e não nome de código: renomear o valor não a muda.
   */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'ScenarioTranslation';
  }
}

/** De onde veio a contagem de papéis da ponte. */
export class QuotedSharesSource extends DartEnum {
  /**
   * Implícita no valor de mercado: `VM ÷ preço`. É a que forma a cotação, e é
   * a adotada sempre que as duas contagens publicadas concordam.
   */
  static readonly market = new QuotedSharesSource('market', 0);

  /**
   * Conciliada pelas demonstrações, adotada quando é a **maior** das duas e as
   * duas divergem além de uma ação societária plausível.
   */
  static readonly reconciled = new QuotedSharesSource('reconciled', 1);

  /** Única disponível: o valor de mercado não pôde ser usado. */
  static readonly onlyAvailable = new QuotedSharesSource('onlyAvailable', 2);

  /** Registro oficial da B3, líquida da fração em tesouraria (decisão 83). */
  static readonly official = new QuotedSharesSource('official', 3);

  static readonly values: readonly QuotedSharesSource[] = [
    QuotedSharesSource.market,
    QuotedSharesSource.reconciled,
    QuotedSharesSource.onlyAvailable,
    QuotedSharesSource.official,
  ];

  private constructor(name: string, index: number) {
    super(name, index);
  }

  protected get typeName(): string {
    return 'QuotedSharesSource';
  }
}

/** Contagem de ações de um emissor no registro oficial da B3. */
export class OfficialShareCount {
  /** Ações emitidas, **com as em tesouraria** — é como a B3 publica. */
  readonly total: number;

  /** Dia em que o registro foi consultado. */
  readonly asOf: DateTime;

  constructor(args: { total: number; asOf: DateTime }) {
    this.total = args.total;
    this.asOf = args.asOf;
  }
}

/** Campos de [ValuationInputs]. Ver a documentação de cada campo na classe. */
export interface ValuationInputsArgs {
  ticker: Ticker;
  asOf: DateTime;
  fundamentals: readonly FundamentalsSnapshot[];
  marketPrice: number;
  capm: CapmInputs;
  marginOfSafety?: number;
  projectionYears?: number;
  perpetualGrowthCap?: number;
  sectorKey?: string | null;
  industry?: string | null;
  inflation?: number;
  declaredTerminalRiskFreeRate?: number | null;
  riskFreeCurve?: YieldCurve | null;
  officialShares?: OfficialShareCount | null;
  prices?: PriceSeries | null;
  isDistressed?: boolean;
  stateControlled?: boolean;
  terminalReturnOverride?: number | null;
  laneOverride?: ValuationLane | null;
  growthOverride?: number | null;
  baseFactorOverride?: number | null;
  unleveredBeta?: number | null;
  reinvestmentOverride?: ReinvestmentPolicy | null;
  cashTimingOverride?: CashTiming | null;
  concessionEnd?: DateTime | null;
  dividendsInBeta?: number;
  creditReferenceRiskFree?: number | null;
  declaredSharesPerUnit?: number | null;
  terminalBetaWeightOverride?: number | null;
  terminalLeverageOverride?: number | null;
  betaWindowYears?: number | null;
  peerMultiples?: PeerMultipleSet | null;
  minorityEquityValue?: number | null;
  scenarioTranslation?: ScenarioTranslation;
  contextNotes?: readonly string[];
  shareIssues?: readonly ShareIssue[];
}

/** Campos que [ValuationInputs.copy] sabe trocar — inclusive por `null`. */
interface ValuationInputsChanges {
  fundamentals?: readonly FundamentalsSnapshot[];
  capm?: CapmInputs;
  projectionYears?: number;
  declaredTerminalRiskFreeRate?: number | null;
  riskFreeCurve?: YieldCurve | null;
  prices?: PriceSeries | null;
  creditReferenceRiskFree?: number | null;
  terminalReturnOverride?: number | null;
  laneOverride?: ValuationLane | null;
  growthOverride?: number | null;
  baseFactorOverride?: number | null;
  reinvestmentOverride?: ReinvestmentPolicy | null;
  cashTimingOverride?: CashTiming | null;
  peerMultiples?: PeerMultipleSet | null;
  contextNotes?: readonly string[];
}

/**
 * Insumos já resolvidos para uma avaliação.
 *
 * Reunir tudo aqui mantém a cascata **pura e síncrona**: ela decide qual
 * modelo aplicar sem tocar em rede, o que permite testá-la exaustivamente e
 * executá-la num *worker*.
 */
export class ValuationInputs {
  /** Ativo a avaliar. */
  readonly ticker: Ticker;

  /** Data de referência. Define o corte *point-in-time* dos fundamentos. */
  readonly asOf: DateTime;

  /** Série completa de exercícios, **sem** filtro de publicação — o filtro é de `PointInTimeView`. */
  readonly fundamentals: readonly FundamentalsSnapshot[];

  /** Cotação na data de referência, em reais **por unidade negociada**. */
  readonly marketPrice: number;

  /** Insumos do CAPM já resolvidos, incluindo a origem do beta. */
  readonly capm: CapmInputs;

  /** Margem de segurança aplicada ao preço justo, em fração. */
  readonly marginOfSafety: number;

  /** Anos de projeção explícita. **Dez, por medição** (decisão 115). */
  readonly projectionYears: number;

  /** Como o cenário de desconto vira deslocamento do `Ke` na rota derivada (item B20, decisão 121). */
  readonly scenarioTranslation: ScenarioTranslation;

  /** Valor a somar ao peso do capital próprio pelo minoritário — **imposição de diagnóstico do item B23**. */
  readonly minorityEquityValue: number | null;

  /** Medianas de múltiplos dos pares, para a segunda leitura (item B5). `null` desliga a triangulação. */
  readonly peerMultiples: PeerMultipleSet | null;

  /** Chave do setor, em minúsculas (decisão 87). Entra na Porta 1. */
  readonly sectorKey: string | null;

  /** Subsetor como publicado — com acento e pontuação. */
  readonly industry: string | null;

  /** Série de cotações da janela, para o corte de liquidez da Porta 0. */
  readonly prices: PriceSeries | null;

  /** `true` quando o ativo consta da lista externa de recuperação judicial. */
  readonly isDistressed: boolean;

  /** `true` quando a companhia é de controle estatal na data (item B46). **Não muda o preço justo.** */
  readonly stateControlled: boolean;

  /** Inflação anual observada, em fração — a âncora *top-down* da Saída 2. */
  readonly inflation: number;

  /** Taxa livre de risco **estrutural** — o destino do decaimento **quando não há curva**. */
  readonly declaredTerminalRiskFreeRate: number | null;

  /** Curva de juros observada, quando disponível (item A2, decisão 74). */
  readonly riskFreeCurve: YieldCurve | null;

  /** Contagem oficial de ações do registro da B3 (item A3.3, decisão 83). */
  readonly officialShares: OfficialShareCount | null;

  /** Retorno terminal imposto de fora — **existe para o DCF reverso**. */
  readonly terminalReturnOverride: number | null;

  /** Beta **desalavancado** do ativo, de `ShrunkBeta.unlevered` (decisão 41). */
  readonly unleveredBeta: number | null;

  /** Crescimento explícito imposto de fora — **existe para o teste A1**. */
  readonly growthOverride: number | null;

  /** Fator de normalização da base imposto de fora. */
  readonly baseFactorOverride: number | null;

  /** Via imposta de fora, no lugar do roteamento. **Também desliga a migração.** */
  readonly laneOverride: ValuationLane | null;

  /** Política do freio de reinvestimento imposta de fora — **existe para o D4**. */
  readonly reinvestmentOverride: ReinvestmentPolicy | null;

  /** Convenção de chegada do caixa imposta de fora. */
  readonly cashTimingOverride: CashTiming | null;

  /** Proventos reinvestidos no retorno que estimou o beta (decisão 89). */
  readonly dividendsInBeta: number;

  /** Fim do contrato de concessão (item A6, decisão 88). **Só age sobre concessão.** */
  readonly concessionEnd: DateTime | null;

  /** Taxa livre de risco **da data**, que arbitra o custo da dívida observado (item B10). */
  readonly creditReferenceRiskFree: number | null;

  /** Extensão, em anos, da série que estimou o beta (item B17). */
  readonly betaWindowYears: number | null;

  /** Peso do beta do ativo no beta de **equilíbrio** — imposição de diagnóstico do item B15. */
  readonly terminalBetaWeightOverride: number | null;

  /** `D/E` imposto na perpetuidade — imposição de diagnóstico do item B15. */
  readonly terminalLeverageOverride: number | null;

  /** Ações reunidas na unit, **como a companhia declara** (item B16). */
  readonly declaredSharesPerUnit: number | null;

  /** Teto **nominal** do crescimento na perpetuidade, em fração. */
  readonly perpetualGrowthCap: number;

  /** Ressalvas que a camada de dados conhece e a cascata não enxerga (item D4). */
  readonly contextNotes: readonly string[];

  /** Emissões de ações por valor conhecidas na data (item B28). */
  readonly shareIssues: readonly ShareIssue[];

  /** Agrupa os insumos. Não busca nada — quem busca é `PrepareValuationInputs`. */
  constructor(args: ValuationInputsArgs) {
    this.ticker = args.ticker;
    this.asOf = args.asOf;
    this.fundamentals = args.fundamentals;
    this.marketPrice = args.marketPrice;
    this.capm = args.capm;
    this.marginOfSafety = args.marginOfSafety ?? 0.0;
    this.projectionYears = args.projectionYears ?? 10;
    this.perpetualGrowthCap = args.perpetualGrowthCap ?? 0.0652;
    this.sectorKey = args.sectorKey ?? null;
    this.industry = args.industry ?? null;
    this.inflation = args.inflation ?? 0.05;
    this.declaredTerminalRiskFreeRate = args.declaredTerminalRiskFreeRate ?? null;
    this.riskFreeCurve = args.riskFreeCurve ?? null;
    this.officialShares = args.officialShares ?? null;
    this.prices = args.prices ?? null;
    this.isDistressed = args.isDistressed ?? false;
    this.stateControlled = args.stateControlled ?? false;
    this.terminalReturnOverride = args.terminalReturnOverride ?? null;
    this.laneOverride = args.laneOverride ?? null;
    this.growthOverride = args.growthOverride ?? null;
    this.baseFactorOverride = args.baseFactorOverride ?? null;
    this.unleveredBeta = args.unleveredBeta ?? null;
    this.reinvestmentOverride = args.reinvestmentOverride ?? null;
    this.cashTimingOverride = args.cashTimingOverride ?? null;
    this.concessionEnd = args.concessionEnd ?? null;
    this.dividendsInBeta = args.dividendsInBeta ?? 0;
    this.creditReferenceRiskFree = args.creditReferenceRiskFree ?? null;
    this.declaredSharesPerUnit = args.declaredSharesPerUnit ?? null;
    this.terminalBetaWeightOverride = args.terminalBetaWeightOverride ?? null;
    this.terminalLeverageOverride = args.terminalLeverageOverride ?? null;
    this.betaWindowYears = args.betaWindowYears ?? null;
    this.peerMultiples = args.peerMultiples ?? null;
    this.minorityEquityValue = args.minorityEquityValue ?? null;
    this.scenarioTranslation = args.scenarioTranslation ?? ScenarioTranslation.oneToOne;
    this.contextNotes = args.contextNotes ?? [];
    this.shareIssues = args.shareIssues ?? [];
  }

  /** Taxa livre de risco estrutural, com o padrão já resolvido. Com curva, é o forward depois do fim da projeção. */
  get terminalRiskFreeRate(): number {
    return (
      this.riskFreeCurve?.terminalRate(this.projectionYears) ??
      this.declaredTerminalRiskFreeRate ??
      this.capm.riskFreeRate
    );
  }

  /**
   * **A única cópia de [ValuationInputs]** (item B27). Campo mencionado em
   * [changes] é trocado — inclusive por `null`, que tira a série de preços,
   * por exemplo —, e o não mencionado é mantido. **Ao acrescentar um campo,
   * acrescente aqui e no teste «a cópia preserva todo campo».**
   */
  private copy(changes: ValuationInputsChanges): ValuationInputs {
    const pick = <K extends keyof ValuationInputsChanges>(key: K, current: ValuationInputsChanges[K]) =>
      key in changes ? changes[key] : current;
    return new ValuationInputs({
      ticker: this.ticker,
      asOf: this.asOf,
      fundamentals: changes.fundamentals ?? this.fundamentals,
      marketPrice: this.marketPrice,
      capm: changes.capm ?? this.capm,
      marginOfSafety: this.marginOfSafety,
      projectionYears: changes.projectionYears ?? this.projectionYears,
      perpetualGrowthCap: this.perpetualGrowthCap,
      sectorKey: this.sectorKey,
      industry: this.industry,
      inflation: this.inflation,
      declaredTerminalRiskFreeRate: pick('declaredTerminalRiskFreeRate', this.declaredTerminalRiskFreeRate),
      riskFreeCurve: pick('riskFreeCurve', this.riskFreeCurve),
      officialShares: this.officialShares,
      prices: pick('prices', this.prices),
      isDistressed: this.isDistressed,
      stateControlled: this.stateControlled,
      terminalReturnOverride: pick('terminalReturnOverride', this.terminalReturnOverride),
      laneOverride: pick('laneOverride', this.laneOverride),
      growthOverride: pick('growthOverride', this.growthOverride),
      baseFactorOverride: pick('baseFactorOverride', this.baseFactorOverride),
      unleveredBeta: this.unleveredBeta,
      reinvestmentOverride: pick('reinvestmentOverride', this.reinvestmentOverride),
      cashTimingOverride: pick('cashTimingOverride', this.cashTimingOverride),
      concessionEnd: this.concessionEnd,
      dividendsInBeta: this.dividendsInBeta,
      creditReferenceRiskFree: pick('creditReferenceRiskFree', this.creditReferenceRiskFree),
      declaredSharesPerUnit: this.declaredSharesPerUnit,
      terminalBetaWeightOverride: this.terminalBetaWeightOverride,
      terminalLeverageOverride: this.terminalLeverageOverride,
      betaWindowYears: this.betaWindowYears,
      peerMultiples: pick('peerMultiples', this.peerMultiples),
      minorityEquityValue: this.minorityEquityValue,
      scenarioTranslation: this.scenarioTranslation,
      contextNotes: changes.contextNotes ?? this.contextNotes,
      shareIssues: this.shareIssues,
    });
  }

  /** Os mesmos insumos, com [n] anos de projeção explícita. */
  withProjectionYears(n: number): ValuationInputs {
    return this.copy({ projectionYears: n });
  }

  /** Os mesmos insumos com outra série de exercícios — a ancorada no trimestre do backtest (item C1c). */
  withFundamentals(series: readonly FundamentalsSnapshot[]): ValuationInputs {
    return this.copy({ fundamentals: series });
  }

  /** Os mesmos insumos sem a série de cotações. Instrumento de diagnóstico. */
  withoutPrices(): ValuationInputs {
    return this.copy({ prices: null });
  }

  /** Os mesmos insumos com outras medianas de pares — ou sem elas. */
  withPeerMultiples(pairs: PeerMultipleSet | null): ValuationInputs {
    return this.copy({ peerMultiples: pairs });
  }

  /** Os mesmos insumos com as ressalvas de contexto (ver [contextNotes]). */
  withContextNotes(notes: readonly string[]): ValuationInputs {
    return this.copy({ contextNotes: Object.freeze([...notes]) });
  }

  /**
   * Os mesmos insumos com as **imposições de diagnóstico** trocadas pelas
   * informadas — `null` (ou ausência) desliga a imposição.
   */
  withOverrides(
    overrides: {
      lane?: ValuationLane | null;
      terminalReturn?: number | null;
      growth?: number | null;
      baseFactor?: number | null;
      reinvestment?: ReinvestmentPolicy | null;
      cashTiming?: CashTiming | null;
    } = {},
  ): ValuationInputs {
    return this.copy({
      laneOverride: overrides.lane ?? null,
      terminalReturnOverride: overrides.terminalReturn ?? null,
      growthOverride: overrides.growth ?? null,
      baseFactorOverride: overrides.baseFactor ?? null,
      reinvestmentOverride: overrides.reinvestment ?? null,
      cashTimingOverride: overrides.cashTiming ?? null,
    });
  }

  /**
   * Os mesmos insumos com o **nível** da taxa livre de risco deslocado em
   * [delta]: a corrente, a de equilíbrio declarada e cada vértice da curva. O
   * piso de 0,1% evita taxa negativa; a referência do crédito fica na data.
   */
  withRiskFreeShift(delta: number): ValuationInputs {
    const floorRate = (x: number) => (x < 0.001 ? 0.001 : x);
    const curve = this.riskFreeCurve;
    const declared = this.declaredTerminalRiskFreeRate;
    return this.copy({
      capm: this.capm.withRiskFree(floorRate(this.capm.riskFreeRate + delta)),
      declaredTerminalRiskFreeRate: declared === null ? null : floorRate(declared + delta),
      riskFreeCurve:
        curve === null
          ? null
          : YieldCurve.of(
              curve.referenceDate,
              curve.vertices.map((v) => new CurveVertex(v.years, floorRate(v.rate + delta))),
            ),
      creditReferenceRiskFree: this.creditReferenceRiskFree ?? this.capm.riskFreeRate,
    });
  }

  /**
   * O CAPM de **equilíbrio**: a taxa livre de risco estrutural e, quando a
   * varredura do B15 o impõe, o beta convergido em direção a 1 (Blume).
   */
  get terminalCapm(): CapmInputs {
    const w = this.terminalBetaWeightOverride;
    const base = this.capm.withRiskFree(this.terminalRiskFreeRate);
    if (w === null) return base;
    return new CapmInputs({
      riskFreeRate: base.riskFreeRate,
      beta: w * this.capm.beta + (1 - w) * 1.0,
      marketPremium: base.marketPremium,
      betaSource: base.betaSource,
      premiumSource: base.premiumSource,
    });
  }
}

/** Contagem de papéis da ponte, com a origem e as duas candidatas. */
export class QuotedShares {
  /** Papéis na unidade negociada. Sempre positiva. */
  readonly count: number;

  /** De onde ela veio. */
  readonly source: QuotedSharesSource;

  /** Contagem implícita no valor de mercado, na unidade negociada, ou `null`. */
  readonly fromMarketCap: number | null;

  /** Contagem conciliada pelas demonstrações, na unidade negociada, ou `null`. */
  readonly fromStatements: number | null;

  /** Razão de unidade medida, para o aviso de *unit*. */
  readonly sharesPerQuote: number;

  /** Contagem oficial da B3 na unidade negociada e líquida de tesouraria — adotada ou não. */
  readonly fromRegistry: number | null;

  /** Dia da consulta ao registro, quando [fromRegistry] existe. */
  readonly registryAsOf: DateTime | null;

  constructor(args: {
    count: number;
    source: QuotedSharesSource;
    fromMarketCap: number | null;
    fromStatements: number | null;
    sharesPerQuote: number;
    fromRegistry?: number | null;
    registryAsOf?: DateTime | null;
  }) {
    this.count = args.count;
    this.source = args.source;
    this.fromMarketCap = args.fromMarketCap;
    this.fromStatements = args.fromStatements;
    this.sharesPerQuote = args.sharesPerQuote;
    this.fromRegistry = args.fromRegistry ?? null;
    this.registryAsOf = args.registryAsOf ?? null;
  }

  /** Cópia adotando a contagem oficial. */
  withOfficial(official: number, queryDate: DateTime): QuotedShares {
    return new QuotedShares({
      count: official,
      source: QuotedSharesSource.official,
      fromMarketCap: this.fromMarketCap,
      fromStatements: this.fromStatements,
      sharesPerQuote: this.sharesPerQuote,
      fromRegistry: official,
      registryAsOf: queryDate,
    });
  }

  /** Cópia registrando a contagem oficial que **não** foi adotada. */
  withRefusedOfficial(official: number, queryDate: DateTime): QuotedShares {
    return new QuotedShares({
      count: this.count,
      source: this.source,
      fromMarketCap: this.fromMarketCap,
      fromStatements: this.fromStatements,
      sharesPerQuote: this.sharesPerQuote,
      fromRegistry: official,
      registryAsOf: queryDate,
    });
  }

  /** `true` quando as duas candidatas divergem além da banda de conciliação. */
  get diverge(): boolean {
    const a = this.fromMarketCap;
    const b = this.fromStatements;
    if (a === null || b === null) return false;
    const d = a >= b ? a / b : b / a;
    return d > FundamentalsSnapshot.reconciliationBand;
  }

  /** Razão entre a maior e a menor candidata, sempre `>= 1`. `null` quando só uma existe. */
  get divergence(): number | null {
    const a = this.fromMarketCap;
    const b = this.fromStatements;
    if (a === null || b === null) return null;
    return a >= b ? a / b : b / a;
  }
}

// --------------------------------------------------------- fraseado técnico --
//
// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a
// decisão 122 mantém no núcleo. O rótulo de tela mora na apresentação.

function quotedSharesSourceDiagnostic(s: QuotedSharesSource): string {
  if (s === QuotedSharesSource.market) return 'implícita no valor de mercado';
  if (s === QuotedSharesSource.reconciled) return 'conciliada pelas demonstrações';
  if (s === QuotedSharesSource.onlyAvailable) return 'única contagem disponível';
  return 'contagem oficial da B3, líquida de tesouraria';
}

function laneDiagnostic(lane: ValuationLane): string {
  return lane === ValuationLane.firm ? 'firma' : 'acionista';
}

function multipleKindDiagnostic(kind: MultipleKind): string {
  if (kind === MultipleKind.priceToEarnings) return 'P/L';
  if (kind === MultipleKind.priceToBook) return 'P/VP';
  return 'EV/EBITDA';
}

function modelDiagnostic(model: ValuationModel): string {
  return model === ValuationModel.dcfFcff ? 'DCF por fluxo da firma' : 'DCF sobre lucro distribuível';
}

function growthOriginDiagnostic(origin: GrowthOrigin): string {
  if (origin === GrowthOrigin.fundamental) return 'crescimento fundamental da base de capital';
  if (origin === GrowthOrigin.inflationAnchor) return 'âncora de inflação, financiável pela retenção observada';
  return 'valor da capacidade de gerar lucro, sem crescimento';
}

function moatBlockDiagnostic(block: MoatBlock): string {
  if (block === MoatBlock.noCycleReturn) return 'retorno do ciclo não medido';
  if (block === MoatBlock.noCostOfCapital) return 'custo de capital de equilíbrio não positivo';
  if (block === MoatBlock.shortHistory) return 'histórico curto';
  if (block === MoatBlock.externalCapitalUnmeasured) return 'capital externo não medido';
  if (block === MoatBlock.inorganicGrowth) return 'crescimento inorgânico';
  if (block === MoatBlock.persistenceNotEstimable) return 'persistência do excedente não estimável';
  if (block === MoatBlock.noExcess) return 'retorno do ciclo não supera o custo de capital';
  if (block === MoatBlock.degenerateExcess) return 'excedente não sobrevive ao decaimento medido';
  return 'o negócio opera sob contrato de prazo determinado';
}

// ------------------------------------------------------- estado interno (D1) --

/** O que uma via recebe e não muda ao longo dos estágios dela (D1). */
interface Lane {
  readonly inputs: ValuationInputs;
  /** Exercícios publicados na data, com demonstração de resultado. */
  readonly published: readonly FundamentalsSnapshot[];
  /** O mais recente deles. */
  readonly latest: FundamentalsSnapshot;
  readonly lane: ValuationLane;
  /** Contagem de papéis da ponte. */
  readonly divisor: QuotedShares;
  readonly audit: AuditTransaction | null;
  /** Capital das emissões por valor depois do balanço usado e até a data (item B28). Zero sem emissão. */
  readonly subsequentCapital: number;
}

/** A realavancagem recusou a estrutura de capital (decisão 45). */
interface RefusedStructure {
  readonly kind: 'refused';
  /** Frase da recusa, com o ativo e a via. */
  readonly reason: string;
}

/** A via descontada, com tudo o que a pós-condição da ponte e a conclusão leem. */
interface DiscountedLane {
  readonly kind: 'discounted';
  readonly output1: Base;
  readonly origin: GrowthOrigin;
  readonly assumptions: LaneAssumptions;
  /** Fluxo-base descontado. */
  readonly base: number;
  /** `true` quando o fluxo-base foi reconstruído do ciclo (decisão 53). */
  readonly rebuiltBase: boolean;
  readonly cost: Cost;
  /** O desconto sob as premissas finais. */
  readonly outcome: DcfOutcome;
  /** Avisos da via, na ordem em que os estágios os declararam. */
  readonly warnings: string[];
}

type Discounting = RefusedStructure | DiscountedLane;

/** A reconstrução do fluxo-base pelo ciclo (decisão 53). */
interface Reconstruction {
  readonly total: number;
  readonly fraction: number;
}

/** O que a Saída 1 da Porta 2 deixa para os estágios seguintes da via (D1). */
interface Base {
  /** Alíquota estrutural do ativo, ou `null` sem exercício que a meça. */
  readonly taxRate: number | null;
  /** Série de capital da via, na alíquota estrutural. */
  readonly series: CapitalSeries;
  /** Retorno sobre o capital do exercício mais recente. */
  readonly currentReturn: number | null;
  /** Retorno mediano na janela do ciclo. */
  readonly cycleReturn: number | null;
  /** Φ — capital externo em múltiplos da base inicial da janela. */
  readonly phi: number | null;
  /** Fator de normalização aplicado ao fluxo-base. */
  readonly factor: number;
  /** A reconstrução do fluxo-base pelo ciclo, ou `null` quando não se aplica. */
  readonly reconstruction: Reconstruction | null;
  /** A decisão da normalização, com o que a decidiu. */
  readonly normalization: BaseNormalization;
}

/** As premissas de uma via, antes do ponto fixo das taxas (D1). */
interface LaneAssumptions {
  /** Taxa de equilíbrio, sobre a taxa livre de risco estrutural. */
  readonly terminalDiscount: number;
  /** `true` quando o ativo é concessão. */
  readonly fixedTerm: boolean;
  /** Primeiro veredito da vantagem competitiva, contra [terminalDiscount]. */
  readonly verdict: MoatVerdict;
  /** Retorno terminal que o veredito concede, ou `null`. */
  readonly verifiedMoat: number | null;
  /** Retorno terminal aplicado: o imposto de fora, ou o do veredito. */
  readonly moat: number | null;
  /** Retorno implícito no fluxo-base, que converte crescimento em retenção. */
  readonly baseReturn: number;
  /** Premissas do DCF com a taxa interpolada. */
  readonly assumptions: DcfAssumptions;
  /** `Ke` do CAPM na taxa corrente e na de equilíbrio (decisão 102). */
  readonly currentKe: number;
  readonly keTerminal: number;
  /** Custo da dívida aplicado no WACC, ou `null` quando o WACC degenerou para o `Ke`. */
  readonly costOfDebt: number | null;
  /** Prêmio de crédito da classificação sintética, em fração. Zero sem dívida bruta. */
  readonly creditSpread: number;
}

/** O custo de capital resolvido de uma via, e o veredito que fechou com ele (D1). */
interface Cost {
  /** Premissas finais, com o caminho de taxas resolvido quando o ponto fixo fechou. */
  readonly assumptions: DcfAssumptions;
  /** Caminho de taxas resolvido, ou `null` quando vale a interpolação. */
  readonly rates: LeveredRates | null;
  /** Motivo da recusa **econômica** da estrutura de capital, ou `null` (decisão 45). */
  readonly rejectedStructure: string | null;
  /** Veredito final da vantagem competitiva. */
  readonly verdict: MoatVerdict;
  /** Retorno terminal que o veredito final concede, ou `null`. */
  readonly verifiedMoat: number | null;
  /** O caminho da taxa livre de risco contra o qual [rates] foram resolvidas (item B24). */
  readonly rfPath: readonly number[] | null;
}

/** A rota derivada da firma, e o `Ke` do centro que a desconta (decisão 147). */
interface FirmRoute {
  readonly route: FirmDiscountRoute;
  readonly ke: number;
  readonly keTerminal: number;
  readonly kePath: readonly number[] | null;
}

/** Custo de capital corrente de uma via. */
interface CurrentCost {
  readonly rate: number;
  readonly costOfDebtEstimated: boolean;
  readonly costOfDebt: number | null;
  readonly creditSpread: number;
}

// ---------------------------------------------------------------- constantes --

/** Fração do patrimônio consolidado a partir da qual o minoritário vira ressalva (item B23, decisão 120). */
const MINORITY_WEIGHT_MATERIALITY = 0.01;

/** Janela, em anos, que o beta pede — e contra a qual a efetiva é medida. */
const BETA_WINDOW_YEARS = 5;

/** Fração da janela do beta abaixo da qual a avaliação declara a janela curta (item B17). */
const MINIMUM_BETA_WINDOW_SHARE = 0.8;

/** Teto de ações por unit. As units da B3 vão até 5 (1 ON + 4 PN). */
const MAX_SHARES_PER_UNIT = 10;

/** Folga **relativa** entre a razão medida e o inteiro mais próximo (decisão 61). */
const UNIT_RATIO_TOLERANCE = 0.05;

/** Idade máxima, em dias, em que o registro oficial arbitra sozinho. */
const OFFICIAL_SHARES_MAX_AGE_DAYS = 31;

// ------------------------------------------------------------------ fraseado --

function fmtDate(date: DateTime): string {
  return `${String(date.day).padStart(2, '0')}/${String(date.month).padStart(2, '0')}/${date.year}`;
}

/** Fração como porcentagem de uma casa: `0.1234` → `12.3%`. */
function pct(fraction: number): string {
  return `${toStringAsFixed(fraction * 100, 1)}%`;
}

function millions(reais: number): string {
  return `${toStringAsFixed(reais / 1e6, 1)} milhões`;
}

/**
 * Arredonda para o JSON: o valor continua número no payload exportado. **O
 * que não é finito passa como é** (item D4) e sai como `"NaN"`/`"Infinity"`
 * pela serialização segura.
 */
function r(value: number, decimals = 2): number {
  if (!Number.isFinite(value)) return value;
  if (decimals <= 0) return round(value);
  const factor = Math.pow(10, decimals);
  return round(value * factor) / factor;
}

/** Razão entre o maior e o menor, sempre `>= 1`. */
function ratioOf(a: number, b: number): number {
  return a >= b ? a / b : b / a;
}

// ----------------------------------------------------------------- a cascata --

/**
 * Avalia usando o melhor modelo possível. A transação de auditoria abre
 * **antes** da primeira validação: um ativo recusado é tão auditável quanto
 * um avaliado. **Uma exceção também fecha a transação** (item D4), e continua
 * subindo: o rastro registra, não engole.
 */
function evaluate(
  receivedInputs: ValuationInputs,
  options: {
    scenarioBuilder?: ((base: DcfAssumptions) => AssumptionSource) | null;
    monteCarloSamples?: number;
    seed?: number;
  } = {},
): Result<ValuationResult> {
  const audit = AuditRecorder.begin(`/core/valuation/${receivedInputs.ticker.value}`, {
    inputPayload: inputPayload(receivedInputs),
  });
  try {
    return evaluateInner(receivedInputs, audit, {
      scenarioBuilder: options.scenarioBuilder ?? null,
      monteCarloSamples: options.monteCarloSamples ?? 10000,
      seed: options.seed ?? 42,
    });
  } catch (e) {
    // `name`, e não `constructor.name`: o build minificado renomeia classes,
    // e os erros do núcleo declaram o nome do tipo do Dart (lang/num).
    const name = e instanceof Error ? e.name : typeof e;
    const stack = e instanceof Error ? (e.stack ?? String(e)) : String(e);
    audit?.abort(`Exceção não tratada na cascata: ${String(e)}`, {
      extra: {
        excecao: name,
        pilha: stack.split('\n').slice(0, 12),
        notasDeContexto: receivedInputs.contextNotes,
      },
    });
    throw e;
  }
}

function evaluateInner(
  receivedInputs: ValuationInputs,
  audit: AuditTransaction | null,
  options: {
    scenarioBuilder: ((base: DcfAssumptions) => AssumptionSource) | null;
    monteCarloSamples: number;
    seed: number;
  },
): Result<ValuationResult> {
  // **Concessão que acaba dentro da projeção termina a projeção no contrato**
  // (item A6, decisão 88). Antes de tudo, porque o horizonte governa a curva,
  // o decaimento do crescimento, a convergência do retorno e o ponto fixo.
  const contractYearsCount = contractYears(receivedInputs);
  const inputs =
    contractYearsCount !== null && contractYearsCount < receivedInputs.projectionYears
      ? receivedInputs.withProjectionYears(contractYearsCount)
      : receivedInputs;

  if (inputs.marketPrice <= 0) {
    audit?.abort('Preço de mercado indisponível.');
    return err(new InvalidInput('Preço de mercado indisponível.'));
  }

  const view = new PointInTimeView(inputs.asOf);
  const disclosed = view.published(inputs.fundamentals);

  // **Exercício sem demonstração de resultado não é exercício de zero** (decisão 52).
  const published = disclosed.filter((s) => s.hasIncomeStatement);
  const emptyCount = disclosed.length - published.length;

  if (published.length === 0) {
    const message =
      disclosed.length === 0
        ? `Nenhum exercício de ${inputs.ticker.value} havia sido divulgado ` +
          `em ${fmtDate(inputs.asOf)} (defasagem de ` +
          `${view.publicationLag.inDays} dias).`
        : `Os ${disclosed.length} exercícios divulgados de ` +
          `${inputs.ticker.value} vêm sem demonstração de resultado: ` +
          'receita, resultado operacional, lucro e lucro por ação zerados. ' +
          'Não há o que descontar.';
    audit?.abort(message, {
      extra: {
        exerciciosRecebidos: inputs.fundamentals.length,
        exerciciosPublicados: disclosed.length,
        exerciciosSemResultado: emptyCount,
      },
    });
    return err(new InsufficientData(message, { subject: inputs.ticker.value }));
  }

  // Porta 0 — elegibilidade. Vem antes de qualquer decisão de modelo.
  const eligibility = EligibilityGate.assess({
    snapshots: published,
    prices: inputs.prices,
    isDistressed: inputs.isDistressed,
  });
  if (!eligibility.isEligible) {
    const message = eligibility.message!;
    const extra: JsonMap = {
      motivos: eligibility.reasons.map((reason) => reason.name),
      exerciciosPublicados: eligibility.publishedPeriods,
    };
    if (eligibility.averageDailyTradedValue !== null) {
      extra['volumeFinanceiroMediano'] = r(eligibility.averageDailyTradedValue, 0);
    }
    audit?.abort(message, { extra });
    return err(new InsufficientData(message, { subject: inputs.ticker.value }));
  }

  const latest = published[published.length - 1]!;
  const warnings: string[] = [];
  if (emptyCount > 0) {
    warnings.push(
      `${emptyCount} ${emptyCount === 1 ? 'exercício divulgado veio' : 'exercícios ' + 'divulgados vieram'} sem demonstração de resultado — receita, ` +
        'resultado operacional, lucro e lucro por ação zerados, com balanço ' +
        `preenchido. ${emptyCount === 1 ? 'Ele ficou' : 'Eles ficaram'} de fora da ` +
        'série: ausência não é zero, e lê-la como zero produziria base e ' +
        'retorno nulos.',
    );
  }

  if (latest.fiscalPeriodEnd.year < inputs.asOf.year - 2) {
    warnings.push(
      `O exercício mais recente já divulgado é de ${latest.fiscalPeriodEnd.year}; ` +
        'a avaliação pode estar desatualizada.',
    );
  }

  // **A composição declarada decide, e a medida confere** (item B16).
  const measured = quotedUnitRatio({
    sharesOutstanding: latest.sharesOutstanding,
    marketCap: latest.marketCap,
    marketPrice: inputs.marketPrice,
  });
  const declared = inputs.declaredSharesPerUnit;
  const declaredValid = declared !== null && declared >= 1 && declared <= MAX_SHARES_PER_UNIT;
  const sharesPerQuote = declaredValid ? declared : measured;
  auditUnitRatio(audit, inputs, latest, sharesPerQuote, {
    measured,
    declared: declaredValid ? declared : null,
  });
  auditCapm(audit, inputs.capm, inputs.dividendsInBeta, { withCurve: inputs.riskFreeCurve !== null });

  // **A janela do beta, quando ela é curta** (item B17, decisão 111).
  const betaWindow = inputs.betaWindowYears;
  if (betaWindow !== null && betaWindow > 0 && betaWindow < BETA_WINDOW_YEARS * MINIMUM_BETA_WINDOW_SHARE) {
    warnings.push(
      `O beta foi estimado sobre ${toStringAsFixed(betaWindow, 1)} ano(s) ` +
        `de cotação, e não sobre os ${BETA_WINDOW_YEARS} que a janela pede: a ` +
        'série do papel não cobre o período inteiro. O custo do capital próprio ' +
        'carrega esse ruído, e o preço justo com ele.',
    );
  }

  if (sharesPerQuote > 1) {
    warnings.push(
      `${inputs.ticker.value} é negociada em unit de ` +
        `${toStringAsFixed(sharesPerQuote, 0)} ações` +
        `${declaredValid ? ', pela composição que a companhia declara no formulário cadastral da CVM' : ', razão inferida do valor de mercado — a companhia não declara a composição'}` +
        '. Os demonstrativos vêm por ação e a cotação é por unit: o valor ' +
        'justo é convertido para a unit antes de ser comparado ao preço.',
    );
  }
  // A conferência: a razão medida discorda da declarada. Não muda número.
  if (declaredValid && Math.abs(measured - declared) > 1e-9) {
    warnings.push(
      'A razão de unidade medida no valor de mercado deu ' +
        `${toStringAsFixed(measured, 0)} e a composição declarada diz ` +
        `${toStringAsFixed(declared, 0)}: vale a declarada. A razão medida só ` +
        'devolve o número de ações da unit quando as espécies valem o mesmo, e ' +
        'esta divergência diz que não valem.',
    );
  }

  const divisor = quotedShares({
    latest,
    marketPrice: inputs.marketPrice,
    sharesPerQuote,
    published,
    official: inputs.officialShares,
    asOf: inputs.asOf,
  });
  if (divisor === null) {
    const message = 'Nenhuma contagem de papéis utilizável: a ponte por papel ' + 'não pode ser feita.';
    audit?.abort(message);
    return err(new InsufficientData(message));
  }
  auditQuotedShares(audit, latest, inputs.marketPrice, divisor);

  if (!shareBaseIsConsistent(published, latest)) {
    warnings.push(
      `A contagem de ações do exercício de ${latest.fiscalPeriodEnd.year} ` +
        `(${str(r(latest.sharesOutstandingAsOf ?? 0, 0))}) destoa por mais de ` +
        `${toStringAsFixed(CapitalSeries.neighbourFactor, 0)}x da dos exercícios ` +
        'vizinhos, o que é falha de escala da fonte e não ação societária. Ela ' +
        'foi descartada do divisor da ponte por papel, que passou a usar a ' +
        'contagem implícita no valor de mercado. As bases contábeis não são ' +
        'afetadas: nelas o erro se cancela contra o valor por ação publicado na ' +
        'mesma escala.',
    );
  }

  if (divisor.source === QuotedSharesSource.official) {
    const official = divisor.fromRegistry!;
    const discordant: string[] = [];
    if (divisor.fromMarketCap !== null && ratioOf(divisor.fromMarketCap, official) > FundamentalsSnapshot.reconciliationBand) {
      discordant.push(`${str(r(divisor.fromMarketCap, 0))} implícitas no valor de mercado`);
    }
    if (divisor.fromStatements !== null && ratioOf(divisor.fromStatements, official) > FundamentalsSnapshot.reconciliationBand) {
      discordant.push(`${str(r(divisor.fromStatements, 0))} conciliadas pelas demonstrações`);
    }
    if (discordant.length > 0) {
      warnings.push(
        `A contagem oficial da B3, de ${fmtDate(divisor.registryAsOf!)}, é de ` +
          `${str(r(official, 0))} papéis líquidos de tesouraria, e a fonte de ` +
          'preços diverge dela além da banda de conciliação: ' +
          `${discordant.join(' e ')}. Foi adotada a oficial.`,
      );
    }
  } else if (divisor.fromRegistry !== null) {
    warnings.push(
      `A contagem oficial da B3 é de ${fmtDate(divisor.registryAsOf!)}, mais ` +
        `antiga que ${OFFICIAL_SHARES_MAX_AGE_DAYS} dias, e diverge das duas ` +
        'contagens da fonte — o que um evento de ações depois da consulta ' +
        'explicaria. Ela não foi usada, e a ponte por papel seguiu a regra da ' +
        'fonte.',
    );
  }

  if (divisor.diverge && divisor.source !== QuotedSharesSource.official) {
    warnings.push(
      'As contagens de papéis da fonte divergem por ' +
        `${toStringAsFixed(divisor.divergence!, 2)}x: ` +
        `${str(r(divisor.fromMarketCap!, 0))} implícitas no valor de mercado ` +
        `contra ${str(r(divisor.fromStatements!, 0))} conciliadas pelas ` +
        'demonstrações. Nada no dado arbitra qual descreve a base societária ' +
        `de hoje, e foi adotada a **maior** — ${quotedSharesSourceDiagnostic(divisor.source)} —, ` +
        'porque divisor pequeno demais infla o preço justo e produz sinal ' +
        'falso de desconto. O preço justo é, nesta medida, conservador.',
    );
  } else if (latest.sharesDisagree) {
    // **A ponte por papel é a que o divisor adotou** (item B40).
    warnings.push(
      'As duas contagens de ações publicadas pela fonte discordam: ' +
        `${str(r(latest.sharesOutstanding ?? 0, 0))} correntes contra ` +
        `${str(r(latest.sharesOutstandingAsOf ?? 0, 0))} do exercício. As bases ` +
        'contábeis usam a do exercício, que reconstrói o patrimônio publicado; ' +
        `a ponte por papel usa a ${quotedSharesSourceDiagnostic(divisor.source)}, ` +
        `${str(r(divisor.count, 0))} papéis.`,
    );
  }

  const imposed = inputs.laneOverride;
  const lane = imposed ?? route(inputs, published, latest, warnings, audit);
  if (imposed !== null) {
    warnings.push(
      `Via imposta em "${laneDiagnostic(imposed)}" por varredura externa. Este ` +
        'resultado é instrumento de diagnóstico, não avaliação: o roteamento ' +
        'foi ignorado.',
    );
  }
  const refusals: string[] = [];
  const result = evaluateLane(
    inputs,
    published,
    latest,
    lane,
    warnings,
    options.scenarioBuilder,
    options.monteCarloSamples,
    options.seed,
    divisor,
    audit,
    refusals,
  );
  if (result !== null) {
    const withNotes = inputs.contextNotes.length === 0 ? result : result.withWarnings(inputs.contextNotes);
    auditVerdict(audit, withNotes);
    audit?.complete(outputPayload(withNotes));
    return ok(withNotes);
  }

  const message =
    refusals.length > 0
      ? refusals[0]!
      : `Os dados de ${inputs.ticker.value} não sustentam nenhuma das duas ` + 'vias de avaliação.';
  const extra: JsonMap = {
    viaTentada: laneDiagnostic(lane),
    exerciciosPublicados: published.length,
  };
  if (inputs.contextNotes.length > 0) extra['notasDeContexto'] = inputs.contextNotes;
  audit?.abort(message, { extra });
  return err(new InsufficientData(message, { subject: inputs.ticker.value }));
}

// ---------------------------------------------------- unidade de negociação --

/**
 * Quantas ações compõem a **unit** negociada, ou 1 para a ação comum. A
 * razão é **medida, não tabelada** (`ações × preço ÷ valor de mercado`), com
 * tolerância **relativa** ao inteiro mais próximo (decisão 61). Sempre em
 * `[1, MAX_SHARES_PER_UNIT]`; `1.0` para qualquer entrada ausente, não
 * positiva, não finita, fora da faixa ou longe de um inteiro.
 */
function quotedUnitRatio(args: {
  sharesOutstanding: number | null;
  marketCap: number | null;
  marketPrice: number;
}): number {
  const { sharesOutstanding, marketCap, marketPrice } = args;
  if (sharesOutstanding === null || sharesOutstanding <= 0) return 1.0;
  if (marketCap === null || marketCap <= 0) return 1.0;
  if (marketPrice <= 0) return 1.0;

  const raw = (sharesOutstanding * marketPrice) / marketCap;
  if (!Number.isFinite(raw)) return 1.0;

  const rounded = roundToDouble(raw);
  if (rounded < 1 || rounded > MAX_SHARES_PER_UNIT) return 1.0;
  // A tolerância absorve a diferença de data entre o preço e o valor de
  // mercado publicado, que é de fechamento — e essa diferença é relativa.
  if (Math.abs(raw / rounded - 1) > UNIT_RATIO_TOLERANCE) return 1.0;
  return rounded;
}

/**
 * A contagem de ações do exercício mais recente é coerente com a série? Teste
 * de vizinhança com o fator de [CapitalSeries]: falha de fonte é de ordem de
 * grandeza, salto societário real **precisa passar**. Lista vazia **aprova**.
 */
function shareBaseIsConsistent(published: readonly FundamentalsSnapshot[], latest: FundamentalsSnapshot): boolean {
  const target = latest.sharesOutstandingAsOf;
  if (target === null || target <= 0) return true;

  const neighbors: number[] = [];
  for (const s of published) {
    if (s === latest) continue;
    const n = s.sharesOutstandingAsOf;
    if (n !== null && n > 0) neighbors.push(n);
  }
  if (neighbors.length < 2) return true;

  const recent =
    neighbors.length <= CapitalSeries.neighbourRadius
      ? [...neighbors]
      : neighbors.slice(neighbors.length - CapitalSeries.neighbourRadius);
  recent.sort((a, b) => a - b);
  const m = Math.floor(recent.length / 2);
  const reference = recent.length % 2 === 1 ? recent[m]! : (recent[m - 1]! + recent[m]!) / 2;
  if (reference <= 0) return true;

  const ratio = target >= reference ? target / reference : reference / target;
  return ratio <= CapitalSeries.neighbourFactor;
}

/**
 * Papéis na **unidade negociada** para a ponte por papel. Na divergência entre
 * as duas contagens da fonte, **adota-se a maior** — divisor pequeno demais
 * infla o preço justo. O registro oficial recente arbitra sozinho; o antigo,
 * só quando concorda com alguma das contagens da fonte. `null` quando nenhuma
 * contagem é utilizável.
 */
function quotedShares(args: {
  latest: FundamentalsSnapshot;
  marketPrice: number;
  sharesPerQuote: number;
  published?: readonly FundamentalsSnapshot[];
  official?: OfficialShareCount | null;
  asOf?: DateTime | null;
}): QuotedShares | null {
  const { latest, marketPrice, sharesPerQuote } = args;
  const published = args.published ?? [];
  const official = args.official ?? null;
  const asOf = args.asOf ?? null;
  const fromSource = quotedSharesFromSource({ latest, marketPrice, sharesPerQuote, published });
  const officialPerUnit = officialInUnit(latest, official, sharesPerQuote, asOf);
  if (officialPerUnit === null) return fromSource;
  const queryDate = official!.asOf;
  if (fromSource === null) {
    return new QuotedShares({
      count: officialPerUnit,
      source: QuotedSharesSource.official,
      fromMarketCap: null,
      fromStatements: null,
      sharesPerQuote,
      fromRegistry: officialPerUnit,
      registryAsOf: queryDate,
    });
  }
  const age =
    asOf === null
      ? 0
      : DateTime.utc(asOf.year, asOf.month, asOf.day).difference(
          DateTime.utc(queryDate.year, queryDate.month, queryDate.day),
        ).inDays;
  const agrees = (c: number | null): boolean => {
    if (c === null || c <= 0) return false;
    const d = c >= officialPerUnit ? c / officialPerUnit : officialPerUnit / c;
    return d <= FundamentalsSnapshot.reconciliationBand;
  };

  if (age <= OFFICIAL_SHARES_MAX_AGE_DAYS || agrees(fromSource.fromMarketCap) || agrees(fromSource.fromStatements)) {
    return fromSource.withOfficial(officialPerUnit, queryDate);
  }
  return fromSource.withRefusedOfficial(officialPerUnit, queryDate);
}

/**
 * A contagem oficial na unidade negociada e líquida de tesouraria, ou `null`
 * sem registro utilizável **na data**. **Nunca olha para a frente.** A
 * tesouraria sai pela fração, e só por ela (decisão 70).
 */
function officialInUnit(
  latest: FundamentalsSnapshot,
  official: OfficialShareCount | null,
  sharesPerQuote: number,
  asOf: DateTime | null,
): number | null {
  if (official === null) return null;
  if (!Number.isFinite(official.total) || official.total <= 0) return null;
  if (asOf !== null) {
    const c = DateTime.utc(official.asOf.year, official.asOf.month, official.asOf.day);
    const a = DateTime.utc(asOf.year, asOf.month, asOf.day);
    if (c.isAfter(a)) return null;
  }
  const f = latest.treasuryFraction;
  const net =
    f !== null && Number.isFinite(f) && f > 0 && f < 1 ? roundToDouble(official.total * (1 - f)) : official.total;
  return net / sharesPerQuote;
}

function quotedSharesFromSource(args: {
  latest: FundamentalsSnapshot;
  marketPrice: number;
  sharesPerQuote: number;
  published: readonly FundamentalsSnapshot[];
}): QuotedShares | null {
  const { latest, marketPrice, sharesPerQuote, published } = args;
  const bySource = latest.sharesFromMarketCap(marketPrice);
  const reconciled = shareBaseIsConsistent(published, latest) ? latest.reconciledShares : null;
  const byBalanceSheet = reconciled !== null && reconciled > 0 ? reconciled / sharesPerQuote : null;

  if (bySource === null && byBalanceSheet === null) return null;
  if (bySource === null) {
    return new QuotedShares({
      count: byBalanceSheet!,
      source: QuotedSharesSource.onlyAvailable,
      fromMarketCap: null,
      fromStatements: byBalanceSheet,
      sharesPerQuote,
    });
  }
  if (byBalanceSheet === null) {
    return new QuotedShares({
      count: bySource,
      source: QuotedSharesSource.onlyAvailable,
      fromMarketCap: bySource,
      fromStatements: null,
      sharesPerQuote,
    });
  }

  const candidate = new QuotedShares({
    count: bySource,
    source: QuotedSharesSource.market,
    fromMarketCap: bySource,
    fromStatements: byBalanceSheet,
    sharesPerQuote,
  });
  if (!candidate.diverge || bySource >= byBalanceSheet) return candidate;

  return new QuotedShares({
    count: byBalanceSheet,
    source: QuotedSharesSource.reconciled,
    fromMarketCap: bySource,
    fromStatements: byBalanceSheet,
    sharesPerQuote,
  });
}

// ------------------------------------------------------ A6: prazo do contrato --

/**
 * Anos até o fim do contrato de concessão, ou `null` (não é concessão, fim
 * desconhecido ou já passado). **Arredondado ao ano, e nunca abaixo de um.**
 */
function contractYears(inputs: ValuationInputs): number | null {
  const end = inputs.concessionEnd;
  if (end === null) return null;
  if (!ConcessionSectors.hasFiniteTerm({ sectorKey: inputs.sectorKey, industry: inputs.industry })) {
    return null;
  }
  const today = DateTime.utc(inputs.asOf.year, inputs.asOf.month, inputs.asOf.day);
  const until = DateTime.utc(end.year, end.month, end.day);
  const days = until.difference(today).inDays;
  if (days <= 0) return null;
  const years = round(days / 365.25);
  return years < 1 ? 1 : years;
}

/** Anos de contrato depois do fim da projeção — já encurtada até ele —, ou `null` sem prazo. */
function contractYearsBeyondProjection(inputs: ValuationInputs): number | null {
  const t = contractYears(inputs);
  if (t === null) return null;
  const m = t - inputs.projectionYears;
  return m < 0 ? 0 : m;
}

// ------------------------------------------------- Porta 1 e Porta 3: a via --

/**
 * Decide de quem é o fluxo. **Porta 1** — instituição financeira sai da via
 * da firma, **pelo setor**. **Porta 3** — o fluxo da firma precisa se
 * sustentar, medido sobre NOPAT.
 */
function route(
  inputs: ValuationInputs,
  published: readonly FundamentalsSnapshot[],
  latest: FundamentalsSnapshot,
  warnings: string[],
  audit: AuditTransaction | null,
): ValuationLane {
  const gate1 = FinancialSectors.isFinancial({ sectorKey: inputs.sectorKey, industry: inputs.industry });

  const sustainedFlow = gate1 ? false : GrowthGuards.firmFlowIsSustained(published);
  const lane = gate1 || !sustainedFlow ? ValuationLane.shareholder : ValuationLane.firm;

  if (gate1) {
    warnings.push(
      'Instituição financeira: depósito, captação e passivo oneroso são ' +
        'insumo do negócio, não financiamento. A avaliação é do fluxo do ' +
        'acionista, descontada ao custo do capital próprio e sem ponte de ' +
        'dívida líquida — subtrair a captação do valor da firma trataria a ' +
        'matéria-prima do negócio como estrutura de capital.',
    );
  } else if (!sustainedFlow) {
    warnings.push(
      'O lucro operacional não se sustenta na maioria dos exercícios; a ' + 'avaliação passa para o fluxo do acionista.',
    );
  }

  const steps = [`Porta 1: setor financeiro → ${gate1 ? 'via do acionista' : 'segue para a Porta 3'}`];
  if (!gate1) {
    steps.push(
      'Porta 3: NOPAT positivo em ao menos ' +
        `${pct(ValuationParameters.minPositiveFlow)} dos exercícios → ` +
        `${sustainedFlow ? 'via da firma' : 'via do acionista'}`,
    );
  }
  audit?.step({
    formulaName: 'Roteamento por porta',
    latex: String.raw`\text{via} = f(\text{setor},\, D_{bruta},\, \Pr[NOPAT > 0])`,
    variables: {
      setor: inputs.sectorKey ?? 'não informado',
      'dívida bruta (R$)': r(latest.totalDebt),
      'Porta 1 (financeira)': gate1 ? 'sim' : 'não',
      'Porta 3 (fluxo sustentado)': sustainedFlow ? 'sim' : 'não',
    },
    steps,
    result: lane === ValuationLane.firm ? 1 : 2,
    unit: lane === ValuationLane.firm ? 'via da firma' : 'via do acionista',
  });
  return lane;
}

// -------------------------------------------------- Porta 2 e a avaliação --

/**
 * Aplica a Porta 2 e desconta, na via informada. **É o condutor, e os
 * estágios são funções** (item D1). **Nenhuma avaliação muda de via no meio
 * da conta** (decisão 102). Devolve `null` quando a via não se aplica; a
 * recusa com motivo vai para [refusals].
 */
function evaluateLane(
  inputs: ValuationInputs,
  published: readonly FundamentalsSnapshot[],
  latest: FundamentalsSnapshot,
  lane: ValuationLane,
  warnings: string[],
  scenarioBuilder: ((base: DcfAssumptions) => AssumptionSource) | null,
  samples: number,
  seed: number,
  divisor: QuotedShares,
  audit: AuditTransaction | null,
  refusals: string[] | null,
): ValuationResult | null {
  // **O capital que entrou depois do balanço** (item B28).
  const capital = subsequentCapital(inputs, latest);
  const withShares = divisor.count > 0;
  if (capital.value > 0 && withShares) {
    warnings.push(
      `O patrimônio é o do balanço de ${fmtDate(latest.fiscalPeriodEnd)}, e ` +
        'depois dele a companhia emitiu ações por R$ ' +
        `${millions(capital.value)} em ${capital.issuances} ` +
        `${capital.issuances === 1 ? 'emissão conhecida' : 'emissões conhecidas'} ` +
        `até ${fmtDate(inputs.asOf)}. As ações novas estão na contagem de hoje, e ` +
        'o capital delas não estava no balanço: ele entra no patrimônio da ' +
        'ponte pelo valor de emissão, somando ' +
        `${Money.fromReais(capital.value / divisor.count).toString()} ao preço justo de ` +
        'cada papel.',
    );
  }
  if (capital.withoutDeclaration > 0 && withShares) {
    warnings.push(
      `Depois do balanço de ${fmtDate(latest.fiscalPeriodEnd)}, o Formulário de ` +
        'Referência mostra o capital integralizado subindo R$ ' +
        `${millions(capital.withoutDeclaration)} com ` +
        `${toStringAsFixed(capital.sharesWithoutDeclaration / 1e6, 1)} milhões de ` +
        'ações novas, sem evento de ações no preço que o explique. ' +
        'O formulário não declara mais emissão por emissão, e a variação do ' +
        'capital não separa emissão por valor de bonificação ou de troca de ' +
        'ações numa reorganização: **ela não foi somada ao patrimônio**. Se foi ' +
        'emissão por valor, o preço justo está subavaliado em até ' +
        `${Money.fromReais(capital.withoutDeclaration / divisor.count).toString()} por papel.`,
    );
  }
  const laneContext: Lane = {
    inputs,
    published,
    latest,
    lane,
    divisor,
    audit,
    subsequentCapital: withShares ? capital.value : 0.0,
  };

  const discounted = discountLane(laneContext, warnings);
  if (discounted === null) return null;

  if (discounted.kind === 'refused') {
    // **Recusar** é a conta dizendo que a estrutura não fecha (decisão 45), e
    // desde a decisão 102 o ativo não muda de via por isso.
    refusals?.push(
      `${discounted.reason} A avaliação não muda de via: a do acionista é outro modelo, ` +
        'e trocar de modelo porque este recusou faria o preço justo depender ' +
        'de qual dos dois a conta alcançou.',
    );
    return null;
  }

  const d = discounted;
  if (lane === ValuationLane.firm && d.outcome.fairValuePerShare <= 0) {
    // **Recusa nomeada, e não número sem conteúdo.**
    const stake = d.outcome.equityShare;
    refusals?.push(
      `O fluxo do acionista de ${inputs.ticker.value}, derivado do da ` +
        'firma, não sustenta capital próprio positivo: a dívida líquida ' +
        'consome o valor que a operação gera' +
        `${stake > 0 ? `, e o capital próprio responderia por ${pct(stake)} do valor da firma` : ''}. ` +
        'O ativo não é avaliável por fluxo descontado nesta estrutura de ' +
        'capital.',
    );
    return null;
  }
  return conclude(laneContext, d, scenarioBuilder, samples, seed);
}

/**
 * **Os estágios da via, até o primeiro desconto.** `null` quando um estágio
 * não se aplica; [RefusedStructure] quando a realavancagem recusa a
 * estrutura de capital; [DiscountedLane] com tudo o que a conclusão lê.
 */
function discountLane(laneContext: Lane, warnings: readonly string[]): Discounting | null {
  const inputs = laneContext.inputs;
  const lane = laneContext.lane;
  const audit = laneContext.audit;
  const local = [...warnings];

  // --- Saída 1: a base ---------------------------------------------------
  const b = output1(laneContext, local);
  if (b === null) return null;

  // --- Saída 2: a taxa ---------------------------------------------------
  const rate = output2(laneContext, b, local);
  if (rate === null) return null;

  // --- Premissas ---------------------------------------------------------
  const p = laneAssumptions(laneContext, b, rate.g, local);

  // --- Fluxo-base --------------------------------------------------------
  const flow = baseFlow(laneContext, b, local);
  if (flow === null) return null;

  // --- Custo de capital realavancado e quem resolve o Ke ----------------
  const cost = resolveCost(laneContext, b, p, flow.base, local);

  // A auditoria e a narrativa do *moat* saem agora, com o veredito final.
  auditMoat(audit, cost.verdict);
  if (p.fixedTerm) {
    local.push(contractWarning(inputs, { capitalMeasured: p.baseReturn > 0 }));
  }
  const rInfFinal = cost.rates?.terminalWacc ?? p.terminalDiscount;
  if (cost.verifiedMoat !== null && inputs.terminalReturnOverride === null) {
    local.push(
      'Vantagem competitiva residual: retorno do ciclo de ' +
        `${pct(b.cycleReturn!)} contra custo de capital de equilíbrio de ` +
        `${pct(rInfFinal)}, com excedente decaindo ` +
        `${pct(1 - cost.verdict.persistence!)} ao ano — persistência medida ` +
        `na própria série do ativo, sobre ${cost.verdict.persistencePoints} ` +
        `pares. Em ${inputs.projectionYears} anos sobram ` +
        `${pct(cost.verdict.retainedFraction!)} do excedente, e o retorno ` +
        `terminal fica em ${pct(cost.verifiedMoat)} em vez do estado ` +
        'estacionário. O valor terminal volta a depender do crescimento ' +
        'perpétuo.',
    );
  }

  if (cost.rejectedStructure !== null) {
    return {
      kind: 'refused',
      reason:
        `A estrutura de capital de ${inputs.ticker.value} não sustenta a via ` +
        `${lane === ValuationLane.firm ? 'da firma' : 'do acionista'}: ` +
        `${cost.rejectedStructure}`,
    };
  }

  const first = discountFlow(laneContext, flow.base, cost, cost.assumptions, p);
  if (first.isErr) return null;

  return {
    kind: 'discounted',
    output1: b,
    origin: rate.origin,
    assumptions: p,
    base: flow.base,
    rebuiltBase: flow.rebuilt,
    cost,
    outcome: first.unwrap(),
    warnings: local,
  };
}

/**
 * **O desconto do fluxo da via**, sob as premissas [a]. Na via da firma, o
 * capital próprio vem sempre do fluxo do acionista derivado do da firma, e
 * nunca da subtração `EV − D` (decisão 102).
 */
function discountFlow(
  laneContext: Lane,
  base: number,
  cost: Cost,
  a: DcfAssumptions,
  assumptions: LaneAssumptions,
): Result<DcfOutcome> {
  return discountFromBalanceSheet(laneContext, base, cost, a, assumptions).map((o) =>
    withPosteriorCapital(laneContext, o),
  );
}

/** O desconto sobre o patrimônio do balanço, antes do capital posterior. */
function discountFromBalanceSheet(
  laneContext: Lane,
  base: number,
  cost: Cost,
  a: DcfAssumptions,
  assumptions: LaneAssumptions,
): Result<DcfOutcome> {
  if (laneContext.lane === ValuationLane.shareholder) {
    // **O deslocamento do cenário alcança o caminho de taxas** (itens B36 e B37).
    const path = a.discountRatePath;
    const deviation = a.discountRate - cost.assumptions.discountRate;
    const shifted =
      path === null || Math.abs(deviation) < 1e-12
        ? a
        : a.copyWith({ discountRatePath: path.map((rate) => rate + deviation) });
    return DcfCalculator.shareholder({ baseProfit: base, assumptions: shifted });
  }
  // **O centro é a premissa que produziu o preço justo** (item B11), e o
  // deslocamento vira deslocamento do `Ke` pelo fator da tradução (B20).
  const center = cost.assumptions;
  const factor = scenarioFactor(laneContext, cost);
  const dKe = (a.discountRate - center.discountRate) * factor;
  const dKeTerminal = (a.terminalDiscountRate - center.terminalDiscountRate) * factor;
  const fr = firmRoute(laneContext, cost, assumptions);
  const kePath = fr.kePath;
  return fr.route.discount({
    baseProfit: base,
    assumptions: a,
    equityDiscountRate: fr.ke + dKe,
    terminalEquityDiscountRate: fr.keTerminal + dKeTerminal,
    equityDiscountRatePath: kePath === null ? null : kePath.map((k) => k + dKe),
  });
}

/**
 * **A conta da via congelada, para o cálculo do usuário** (decisão 147). As
 * taxas saem do **desconto que produziu o preço justo**.
 */
function freeze(laneContext: Lane, d: DiscountedLane): ManualValuation | null {
  const rates = d.outcome.discountRates;
  const terminalRate = d.outcome.terminalDiscountRateUsed;
  if (rates === null || rates.length === 0 || terminalRate === null) return null;
  const firm = laneContext.lane === ValuationLane.firm ? firmRoute(laneContext, d.cost, d.assumptions) : null;
  const publishedBaseProfit = baseProfitFor(
    laneContext.lane,
    laneContext.latest,
    laneContext.divisor,
    1.0,
    d.output1.taxRate,
  );
  const scale = laneContext.lane === ValuationLane.shareholder ? laneContext.divisor.count : 1.0;
  return new ManualValuation({
    lane: laneContext.lane,
    shares: laneContext.divisor.count,
    marketPrice: laneContext.inputs.marketPrice,
    engineFairValue: d.outcome.fairValuePerShare,
    engineBase: d.base,
    publishedBase: publishedBaseProfit === null ? null : publishedBaseProfit * scale,
    baseFactor: d.output1.factor,
    rebuiltBase: d.rebuiltBase,
    engineAssumptions: d.cost.assumptions,
    engineRates: Object.freeze([...rates]),
    engineTerminalRate: terminalRate,
    firmRoute: firm?.route ?? null,
    engineEquityRate: firm?.ke ?? null,
    engineTerminalEquityRate: firm?.keTerminal ?? null,
    engineEquityRatePath: firm?.kePath ?? null,
    postStatementCapital: laneContext.subsequentCapital,
  });
}

/**
 * **A rota derivada da firma, e o `Ke` do centro que a desconta** (decisão
 * 147). O custo da dívida é **sempre o sintético que o WACC aplica** (item
 * B11), e o caixa rende a taxa livre de risco (decisão 119).
 */
function firmRoute(laneContext: Lane, cost: Cost, assumptions: LaneAssumptions): FirmRoute {
  const rates = cost.rates;
  const latest = laneContext.latest;
  const kd = assumptions.costOfDebt ?? laneContext.inputs.capm.riskFreeRate;
  const cashYield = laneContext.inputs.capm.riskFreeRate;
  const spread = assumptions.creditSpread;
  const terminalRf = laneContext.inputs.terminalRiskFreeRate;
  const makeRoute = (rfPath: readonly number[] | null): FirmDiscountRoute =>
    new FirmDiscountRoute({
      netDebt: latest.netDebt,
      sharesOutstanding: laneContext.divisor.count,
      costOfDebt: kd,
      taxRate: ValuationParameters.statutoryTaxRate,
      minorityInterest: latest.minorityInterest ?? 0,
      cash: latest.totalCash,
      cashYield,
      costOfDebtPath: rfPath === null ? null : rfPath.map((rf) => rf + spread),
      cashYieldPath: rfPath,
      terminalCostOfDebt: rfPath === null ? null : terminalRf + spread,
      terminalCashYield: rfPath === null ? null : terminalRf,
    });
  if (rates === null) {
    // Sem caminho resolvido, e com curva, o `Ke`, o juro e o rendimento do
    // caixa de cada ano seguem o forward daquele ano (item B37).
    const fw = laneContext.inputs.riskFreeCurve?.annualForwards(laneContext.inputs.projectionYears) ?? null;
    return {
      route: makeRoute(fw),
      ke: assumptions.currentKe,
      keTerminal: assumptions.keTerminal,
      kePath: fw === null ? null : fw.map((rf) => laneContext.inputs.capm.withRiskFree(rf).costOfEquity),
    };
  }
  // **Com o caminho de taxas resolvido, o juro e o rendimento seguem a
  // curva** (item B24, decisão 127).
  return {
    route: makeRoute(cost.rfPath),
    ke: rates.costOfEquity[0]!,
    keTerminal: rates.terminalCostOfEquity,
    kePath: rates.costOfEquity,
  };
}

/**
 * **A conclusão da via**: o rastro do desconto e da ponte, os cenários e os
 * diagnósticos. Devolve `null` com preço justo não positivo. Usa **as
 * premissas finais, e não as interpoladas** (item B11).
 */
function conclude(
  laneContext: Lane,
  d: DiscountedLane,
  scenarioBuilder: ((base: DcfAssumptions) => AssumptionSource) | null,
  samples: number,
  seed: number,
): ValuationResult | null {
  const inputs = laneContext.inputs;
  const lane = laneContext.lane;
  const audit = laneContext.audit;
  const outcome = d.outcome;
  const assumptions = d.cost.assumptions;
  if (outcome.fairValuePerShare <= 0) return null;

  // **O que a perpetuidade supõe sobre o capital que já existe** (item B12, decisão 107).
  const excess = outcome.discountedTerminalExcess;
  const excessFraction = excess === null || outcome.equityValue <= 0 ? null : excess / outcome.equityValue;
  const installedReturn = outcome.impliedTerminalReturn;
  if (
    excessFraction !== null &&
    installedReturn !== null &&
    Math.abs(excessFraction) > ValuationDiagnostics.terminalExcessLimit
  ) {
    const rInf = d.cost.rates?.terminalWacc ?? d.assumptions.terminalDiscount;
    const deficit = installedReturn < rInf;
    d.warnings.push(
      'A perpetuidade supõe que o capital já instalado continue rendendo ' +
        `${pct(installedReturn)} ao ano para sempre, contra um custo de ` +
        `capital de equilíbrio de ${pct(rInf)}: ` +
        `${pct(Math.abs(excessFraction))} do preço justo ` +
        `${deficit ? 'é subtraído por esse déficit' : 'vem desse excedente'}. ` +
        'O retorno terminal neutro recusa valor ao capital **novo**, e não ao ' +
        'que já existe — são duas afirmações, e só a primeira está no rótulo.',
    );
  }

  auditDcf(audit, {
    outcome,
    assumptions,
    baseFlow: d.base,
    flowSymbol: lane === ValuationLane.firm ? 'NOPAT' : 'LPA',
    perShareAlready: lane === ValuationLane.shareholder,
    capitalPerShare: laneContext.divisor.count > 0 ? laneContext.subsequentCapital / laneContext.divisor.count : 0.0,
  });
  if (lane === ValuationLane.firm) {
    auditEquityBridge(audit, {
      outcome,
      netDebt: laneContext.latest.netDebt,
      minorityInterest: laneContext.latest.minorityInterest ?? 0,
      shares: laneContext.divisor.count,
      resolved: d.cost.rates !== null,
      withCurve: inputs.riskFreeCurve !== null,
      subsequentCapital: laneContext.subsequentCapital,
    });
  }

  // **A segunda leitura** (item B5, decisão 118): mesmo exercício-base e
  // mesmo divisor do fluxo descontado.
  const triangulation = PeerTriangulation.build({
    latest: laneContext.latest,
    shares: laneContext.divisor.count,
    peers: inputs.peerMultiples,
    dcfFairValue: outcome.fairValuePerShare,
    sectorKey: inputs.sectorKey,
    industry: inputs.industry,
  });
  const warningsWithTriangulation = [...d.warnings];
  if (triangulation !== null && triangulation.diverges) {
    warningsWithTriangulation.push(triangulationWarning(triangulation, outcome.fairValuePerShare));
  }

  const retentionPath: number[] = [];
  const growthPath: number[] = [];
  for (let t = 1; t <= inputs.projectionYears; t++) retentionPath.push(assumptions.retentionAt(t));
  for (let t = 1; t <= inputs.projectionYears; t++) growthPath.push(assumptions.growthAt(t));

  return withScenarios({
    inputs,
    model: lane === ValuationLane.firm ? ValuationModel.dcfFcff : ValuationModel.dcfEarnings,
    assumptions,
    baseValue: outcome.fairValuePerShare,
    triangulation,
    manual: freeze(laneContext, d),
    valuate: (a) =>
      discountFlow(laneContext, d.base, d.cost, a, d.assumptions).map((o) => o.fairValuePerShare),
    scenarioBuilder,
    samples,
    seed,
    warnings: warningsWithTriangulation,
    diagnostics: diagnose({
      outcome,
      divisor: laneContext.divisor,
      baseFactor: d.output1.factor,
      growthOrigin: d.origin,
      // O veredito, e não o retorno imposto: `moatApplied` alimenta relatório
      // de cobertura, e uma varredura de diagnóstico não é vantagem reconhecida.
      moatApplied: d.cost.verifiedMoat !== null,
      finiteTerm: d.assumptions.fixedTerm,
      stateControlled: inputs.stateControlled,
      rebuiltBase: d.rebuiltBase,
      baseNormalization: d.output1.normalization,
      costOfEquity: inputs.capm.costOfEquity,
      terminalDiscountRate: d.cost.rates?.terminalWacc ?? d.assumptions.terminalDiscount,
      terminalRetainedSpread: d.cost.verdict.retainedFraction ?? 0.0,
      growthRate: assumptions.growthRate,
      returnOnCapital: assumptions.returnOnCapital,
      terminalReturnOnCapital: assumptions.terminalReturnOnCapital,
      firmTaxRate: lane === ValuationLane.firm ? d.output1.taxRate : null,
      terminalCostOfEquity: d.cost.rates?.terminalCostOfEquity ?? null,
      // A estrutura de capital da perpetuidade é a do ano N do modelo (item B15, decisão 105).
      terminalEquityShare: d.cost.rates?.equityShareAt(inputs.projectionYears) ?? null,
      postStatementCapital: laneContext.subsequentCapital > 0 ? laneContext.subsequentCapital : null,
      retentionPath,
      growthPath,
    }),
  });
}

/**
 * **O custo de capital realavancado ano a ano** (decisões 41, 44, 46 e 51),
 * com o veredito da vantagem competitiva refeito contra a taxa resolvida até
 * o par parar de mudar. Sem beta desalavancado — ou em instituição
 * financeira na via do acionista — vale a interpolação.
 */
function resolveCost(laneContext: Lane, b: Base, p: LaneAssumptions, base: number, local: string[]): Cost {
  const inputs = laneContext.inputs;
  const latest = laneContext.latest;
  const lane = laneContext.lane;
  const divisor = laneContext.divisor;
  const assumptions = p.assumptions;
  let moatVerdict = p.verdict;
  let verifiedMoat = p.verifiedMoat;
  let moat = p.moat;
  const assessMoat = (rInf: number): MoatVerdict => moatVerdictFor(inputs, b, p.fixedTerm, rInf);
  let assumptionsFinal = assumptions;
  let resolvedRates: LeveredRates | null = null;
  let resolvedRfPath: readonly number[] | null = null;
  let rejectedStructure: string | null = null;
  const betaU = inputs.unleveredBeta;

  // **A exceção é a instituição financeira, e é de direito** (decisão 46).
  const isFinancial = FinancialSectors.isFinancial({ sectorKey: inputs.sectorKey, industry: inputs.industry });
  const resolvesRates =
    betaU !== null && Number.isFinite(betaU) && (lane === ValuationLane.firm || !isFinancial);
  if (resolvesRates) {
    const n = inputs.projectionYears;
    // Com curva, o forward de um ano de cada ano (decisão 74); sem ela, o
    // decaimento linear de dois pontos da decisão 31.
    const curve = inputs.riskFreeCurve;
    let rfPath: number[];
    if (curve !== null) {
      rfPath = curve.annualForwards(n);
    } else {
      rfPath = [];
      for (let tYear = 1; tYear <= n; tYear++) {
        rfPath.push(
          inputs.capm.riskFreeRate -
            (inputs.capm.riskFreeRate - inputs.terminalRiskFreeRate) * (n <= 1 ? 1.0 : (tYear - 1) / (n - 1)),
        );
      }
    }
    // A dívida por papel usa a mesma contagem que forma a cotação.
    const debtPerShare = divisor.count > 0 ? latest.netDebt / divisor.count : Number.NaN;

    const resolveRates = (a: DcfAssumptions): Result<LeveredRates> =>
      lane === ValuationLane.firm
        ? LeveredCostOfCapital.solve({
            baseProfit: base,
            assumptions: a,
            netDebt: latest.netDebt,
            unleveredBeta: betaU,
            riskFreePath: rfPath,
            terminalRiskFree: inputs.terminalRiskFreeRate,
            marketPremium: inputs.capm.marketPremium,
            // O prêmio de crédito da classificação sintética (item B11).
            creditSpread: p.creditSpread,
            taxRate: ValuationParameters.statutoryTaxRate,
            // O caixa rende `R_f`, e não `R_f + spread`.
            cash: latest.totalCash,
            terminalBetaWeight: inputs.terminalBetaWeightOverride,
            terminalLeverage: inputs.terminalLeverageOverride,
            // O ponto fixo é tentado de dois lugares (item B18).
            warnings: local,
          })
        : LeveredCostOfCapital.solveEquity({
            baseProfit: base,
            assumptions: a,
            netDebtPerShare: debtPerShare,
            unleveredBeta: betaU,
            riskFreePath: rfPath,
            terminalRiskFree: inputs.terminalRiskFreeRate,
            marketPremium: inputs.capm.marketPremium,
            taxRate: ValuationParameters.statutoryTaxRate,
            terminalBetaWeight: inputs.terminalBetaWeightOverride,
            terminalLeverage: inputs.terminalLeverageOverride,
            warnings: local,
          });

    const resolved = resolveRates(assumptions);
    if (resolved.isOk) {
      let rates = resolved.unwrap();
      if (rates.converged) {
        // **Dois passes não fecham a volta** (decisão 51): a volta mora em
        // `MoatFixedPoint.iterate`, e o veredito só é adotado com a taxa dele.
        const roundTrip = MoatFixedPoint.iterate<MoatVerdict, LeveredRates>({
          verdict: moatVerdict,
          moat,
          rates,
          reassess: (rr) => assessMoat(rr.terminalWacc),
          moatOf: (v) => inputs.terminalReturnOverride ?? v.terminalReturn,
          solve: (newMoat) => {
            const next = resolveRates(
              assumptions.copyWith({
                terminalReturnOnCapital: newMoat,
                neutralTerminalReturn: newMoat === null,
              }),
            );
            return next.isOk && next.unwrap().converged ? next.unwrap() : null;
          },
        });
        const passes = roundTrip.passes;
        const stable = roundTrip.stable;
        const solverLocked = roundTrip.solverFailed;
        if (passes > 1) {
          moatVerdict = roundTrip.verdict;
          verifiedMoat = roundTrip.verdict.terminalReturn;
        }
        moat = roundTrip.moat;
        rates = roundTrip.rates;
        if (!stable) {
          const reason = solverLocked
            ? 'o veredito seguinte pedia uma taxa que o ponto fixo não ' + 'fechou'
            : `o teto de ${ValuationParameters.moatMaxPasses} passes foi ` + 'alcançado e o par ainda alternava';
          local.push(
            'O veredito de vantagem competitiva e a taxa de equilíbrio não ' +
              `se estabilizaram em ${passes} passes: ${reason}. A volta é ` +
              'circular — o retorno terminal muda a projeção, que muda a ' +
              'alavancagem, que muda a taxa contra a qual o excedente é ' +
              'medido —, e vale o último par consistente entre si.',
          );
        }
        resolvedRates = rates;
        resolvedRfPath = rfPath;
        assumptionsFinal = assumptions.copyWith({
          terminalReturnOnCapital: moat,
          neutralTerminalReturn: moat === null,
          discountRatePath: [...rates.wacc],
          terminalDiscountRate: rates.terminalWacc,
        });
        const symbol = lane === ValuationLane.firm ? 'WACC' : 'Ke';
        local.push(
          'O custo de capital é resolvido ano a ano contra a alavancagem que ' +
            `a própria avaliação produz: o ${symbol} vai de ` +
            `${pct(rates.wacc[0]!)} no primeiro ano a ${pct(rates.wacc[rates.wacc.length - 1]!)} no ` +
            `ano ${n}, e a perpetuidade é descontada a ` +
            `${pct(rates.terminalWacc)}. ${stakeExcerpt(rates, n)} ` +
            `Ponto fixo em ${rates.iterations} iterações, e o veredito ` +
            `da perpetuidade fechou em ${passes} ` +
            `${passes === 1 ? 'passe' : 'passes'}.`,
        );
      } else {
        local.push(
          'O ponto fixo do custo de capital não convergiu em ' +
            `${rates.iterations} iterações; vale o custo de capital com a ` +
            'estrutura de hoje, que supõe alavancagem constante.',
        );
      }
    } else {
      const failure = resolved.failureOrNull;
      if (failure instanceof ComputationFailure) {
        // Não é falha de método: é a estrutura de capital recusada pela conta.
        rejectedStructure = failure.message;
      } else {
        local.push(
          'O custo de capital não pôde ser resolvido contra a alavancagem ' +
            `(${failure?.message ?? 'null'}); vale o custo de capital com a estrutura de ` +
            'hoje.',
        );
      }
    }
  }

  // **A condição de exposição do minoritário** (item B23, decisão 120).
  if (lane === ValuationLane.firm && resolvedRates === null) {
    const minority = latest.minorityInterest ?? 0;
    const controllingEquity = latest.totalStockholderEquity ?? 0;
    const consolidated = minority + controllingEquity;
    if (minority > 0 && consolidated > 0 && minority / consolidated >= MINORITY_WEIGHT_MATERIALITY) {
      local.push(
        `A avaliação recuou para o WACC estático, e ${pct(minority / consolidated)} ` +
          'do patrimônio consolidado é de não controladores. **O peso do ' +
          'capital próprio na taxa é o valor de mercado da controladora**, e o ' +
          'fluxo descontado é o consolidado: a participação da dívida sai ' +
          'inflada e o desconto, achatado. O caminho resolvido não teria o ' +
          'problema, porque pondera pelo capital próprio que o próprio modelo ' +
          'produz (item B23).',
      );
    }
  }

  return {
    assumptions: assumptionsFinal,
    rates: resolvedRates,
    rfPath: resolvedRates === null ? null : resolvedRfPath,
    rejectedStructure,
    verdict: moatVerdict,
    verifiedMoat,
  };
}

/**
 * **As premissas da via**: a taxa corrente e a de equilíbrio, o crescimento
 * perpétuo, o primeiro veredito da vantagem competitiva e o retorno que
 * converte crescimento em retenção.
 */
function laneAssumptions(laneContext: Lane, b: Base, g: number, local: string[]): LaneAssumptions {
  const inputs = laneContext.inputs;
  const latest = laneContext.latest;
  const lane = laneContext.lane;
  const divisor = laneContext.divisor;
  const audit = laneContext.audit;
  const structuralTaxRate = b.taxRate;
  const currentReturn = b.currentReturn;
  const cycleReturn = b.cycleReturn;
  const baseFactor = b.factor;

  const currentCost: CurrentCost =
    lane === ValuationLane.firm
      ? wacc(inputs, latest, local, divisor, audit)
      : { rate: inputs.capm.costOfEquity, costOfDebtEstimated: false, costOfDebt: null, creditSpread: 0.0 };
  const discount = currentCost.rate;

  // Custo de capital de **equilíbrio** (item B15): avisos e auditoria saem só
  // da montagem corrente.
  const capmTerminal = inputs.terminalCapm;
  const terminalDiscount =
    lane === ValuationLane.firm
      ? wacc(inputs, latest, [], divisor, null, { capmOverride: capmTerminal, terminal: true }).rate
      : capmTerminal.costOfEquity;

  const perpetual = GrowthEstimator.perpetual({ explicitGrowth: g, economyGrowth: inputs.perpetualGrowthCap });
  auditPerpetualGrowth(audit, g, inputs.perpetualGrowthCap, perpetual);

  // **Com a curva, a taxa de cada ano é montada sobre o forward daquele ano**
  // (decisão 74; item B37).
  const curveAtDate = inputs.riskFreeCurve;
  const curvePath: number[] | null =
    curveAtDate === null
      ? null
      : curveAtDate
          .annualForwards(inputs.projectionYears)
          .map((rf) =>
            lane === ValuationLane.firm
              ? wacc(inputs, latest, [], divisor, null, { capmOverride: inputs.capm.withRiskFree(rf) }).rate
              : inputs.capm.withRiskFree(rf).costOfEquity,
          );

  // **Concessão não preserva excedente** (decisão 50).
  const fixedTerm = ConcessionSectors.hasFiniteTerm({ sectorKey: inputs.sectorKey, industry: inputs.industry });

  const moatVerdict = moatVerdictFor(inputs, b, fixedTerm, terminalDiscount);
  // O veredito e o retorno terminal aplicado são grandezas distintas.
  const verifiedMoat = moatVerdict.terminalReturn;
  const moat = inputs.terminalReturnOverride ?? verifiedMoat;

  auditDiscountTerm(audit, inputs, discount, terminalDiscount, curvePath);

  const yieldCurve = inputs.riskFreeCurve;
  if (yieldCurve !== null) {
    const ref = yieldCurve.referenceDate;
    const fw = yieldCurve.annualForwards(inputs.projectionYears);
    local.push(
      'A taxa livre de risco segue a curva dos títulos prefixados do Tesouro ' +
        `de ${String(ref.day).padStart(2, '0')}/` +
        `${String(ref.month).padStart(2, '0')}/${ref.year}: ` +
        `${pct(fw[0]!)} a.a. no primeiro ano, ${pct(fw[fw.length - 1]!)} a.a. no ano ` +
        `${inputs.projectionYears} e ${pct(inputs.terminalRiskFreeRate)} a.a. ` +
        'na perpetuidade. É a taxa que o mercado de títulos atribui a cada ' +
        'prazo, e não uma previsão do motor.',
    );
  } else if (Math.abs(discount - terminalDiscount) > 1e-7) {
    local.push(
      `O desconto parte de ${pct(discount)} a.a. no primeiro ano e converge ` +
        `linearmente para ${pct(terminalDiscount)} a.a. no ano ` +
        `${inputs.projectionYears}, que é a taxa da perpetuidade. A taxa livre ` +
        `de risco vai de ${pct(inputs.capm.riskFreeRate)} para ` +
        `${pct(inputs.terminalRiskFreeRate)}: sem curva de juros observada, ` +
        'descontar perpetuidade pelo CDI de um dia casaria durações ' +
        'incompatíveis.',
    );
  }

  // **O controle estatal é declarado, e não cobrado** (item B46).
  if (inputs.stateControlled) {
    local.push(
      'A companhia é de controle estatal, pelo Formulário Cadastral da CVM. ' +
        'O motor não cobra prêmio por esse controle: medido sobre as estatais ' +
        'do universo em 02/10/2026, o beta delas é menor que o das privadas e ' +
        'a exposição ao risco soberano, além do que o Ibovespa explica, não é ' +
        'maior. O risco do controlador público — preço, tarifa, crédito e ' +
        'indicação decididos por outros objetivos que o lucro — está no fluxo ' +
        'que o minoritário pode esperar receber, e o motor o projeta pelo ' +
        'histórico da companhia.',
    );
  }

  if (
    lane === ValuationLane.firm &&
    structuralTaxRate !== null &&
    Math.abs(structuralTaxRate - ValuationParameters.statutoryTaxRate) > 0.01
  ) {
    local.push(
      'O lucro operacional é tributado à alíquota estrutural do ativo, ' +
        `${pct(structuralTaxRate)}, e não aos ` +
        `${pct(ValuationParameters.statutoryTaxRate)} estatutários que a ` +
        'fonte embute em todo NOPAT publicado. É a mediana dos exercícios, ' +
        'não a do último: JCP, incentivo regional e lucro presumido são ' +
        'regime no Brasil, e regime é o que se projeta. O escudo fiscal do ' +
        'WACC continua na estatutária, que é a alíquota da margem.',
    );
  }

  if (inputs.terminalReturnOverride !== null) {
    local.push(
      'Retorno terminal imposto em ' +
        `${pct(inputs.terminalReturnOverride)} por varredura externa. ` +
        'Este resultado é instrumento de diagnóstico, não avaliação: o ' +
        'veredito de vantagem competitiva foi ignorado.',
    );
  }

  // O retorno que converte crescimento em retenção é o **do fluxo-base que
  // se está descontando**: `retorno_atual × fator`, ou o do ciclo sem retorno
  // corrente utilizável.
  const baseReturn = currentReturn !== null && currentReturn > 0 ? currentReturn * baseFactor : (cycleReturn ?? 0.0);

  const dcfAssumptions = new DcfAssumptions({
    projectionYears: inputs.projectionYears,
    growthRate: g,
    perpetualGrowth: perpetual,
    discountRate: discount,
    terminalDiscountRate: terminalDiscount,
    discountRatePath: curvePath,
    returnOnCapital: baseReturn,
    terminalReturnOnCapital: moat,
    marginOfSafety: inputs.marginOfSafety,
    reinvestmentPolicy: inputs.reinvestmentOverride ?? ReinvestmentPolicy.measured,
    inflation: inputs.inflation,
    cashTiming: inputs.cashTimingOverride ?? CashTiming.midYear,
    contractYearsAfterHorizon: contractYearsBeyondProjection(inputs),
  });
  if (inputs.cashTimingOverride !== null) {
    local.push(
      'Convenção de caixa imposta em ' +
        `"${inputs.cashTimingOverride.key}" por varredura externa, no lugar ` +
        'do meio de ano. Este resultado é instrumento de diagnóstico, não ' +
        'avaliação.',
    );
  }
  if (inputs.reinvestmentOverride !== null) {
    local.push(
      'Freio de reinvestimento imposto em ' +
        `"${inputs.reinvestmentOverride.key}" por varredura externa, no ` +
        'lugar do `b = g/ROIC` medido. Este resultado é instrumento de ' +
        'diagnóstico, não avaliação.',
    );
  }

  return {
    terminalDiscount,
    fixedTerm,
    verdict: moatVerdict,
    verifiedMoat,
    moat,
    baseReturn,
    assumptions: dcfAssumptions,
    currentKe: inputs.capm.costOfEquity,
    keTerminal: capmTerminal.costOfEquity,
    costOfDebt: currentCost.costOfDebt,
    creditSpread: currentCost.creditSpread,
  };
}

/** Veredito da vantagem competitiva residual contra a taxa de equilíbrio [rInf] (decisões 36, 44 e 50). */
function moatVerdictFor(inputs: ValuationInputs, b: Base, fixedTerm: boolean, rInf: number): MoatVerdict {
  const excessReturns: { year: number; excess: number }[] = [];
  for (const yv of b.series.returns) {
    if (Number.isFinite(yv.value)) excessReturns.push({ year: yv.year, excess: yv.value - rInf });
  }
  return GrowthGuards.residualMoat({
    cycleReturn: b.cycleReturn,
    terminalDiscountRate: rInf,
    externalCapitalRatio: b.phi,
    periods: b.series.length,
    excessReturns,
    projectionYears: inputs.projectionYears,
    finiteTerm: fixedTerm,
  });
}

/**
 * **Saída 1 da Porta 2 — a base.** Série de capital na alíquota estrutural,
 * convergência ao ciclo com a precedência do ciclo em commodity, a trava de
 * saúde operacional e a saturação do fator. `null` com série curta demais.
 */
function output1(laneContext: Lane, local: string[]): Base | null {
  const inputs = laneContext.inputs;
  const published = laneContext.published;
  const lane = laneContext.lane;
  const audit = laneContext.audit;
  // A alíquota estrutural entra **na série e no fluxo-base ao mesmo tempo**.
  const structuralTaxRate = CapitalSeries.structuralTaxRate(published, {
    statutoryRate: ValuationParameters.statutoryTaxRate,
  });
  const series = CapitalSeries.build(published, lane, { firmTaxRate: structuralTaxRate });
  if (series.isTooShort) return null;

  const currentReturn = series.latestReturn;
  const cycleReturn = series.cycleReturn({ window: ValuationParameters.cycleWindow });
  const trend = GrowthGuards.trend(series);
  const phi = GrowthGuards.externalCapitalRatio(series);
  const deviation = GrowthGuards.cycleDeviation(series);
  const deviates = deviation?.deviates ?? null;

  const comparable = phi === null || phi <= ValuationParameters.maxExternalCapital;

  // **Em commodity, a Guarda 3 tem precedência sobre a Guarda 1.**
  const cyclePrecedence = CyclicalSectors.hasCyclePrecedence({
    sectorKey: inputs.sectorKey,
    industry: inputs.industry,
  });
  const trendLocks = trend?.dominates === true && !cyclePrecedence;

  const normalizes =
    !trendLocks && deviates === true && currentReturn !== null && cycleReturn !== null && currentReturn > 0;

  // **Saúde operacional trava a normalização para cima.**
  const decline = GrowthGuards.recentOperationalDecline(published);
  const healthFailed = decline !== null && decline > ValuationParameters.maxOperationalDecline;

  // **Setor cíclico é isento da trava, aqui e só aqui.**
  const healthLock = healthFailed && !cyclePrecedence;
  const cap = healthLock ? 1.0 : ValuationParameters.baseFactorCeiling;

  // O fator é saturado em razão, `1/3` a `3`.
  const rawFactor = normalizes ? cycleReturn! / currentReturn! : 1.0;
  const decidedFactor = normalizes ? clamp(rawFactor, ValuationParameters.baseFactorFloor, cap) : 1.0;
  const baseFactor = inputs.baseFactorOverride ?? decidedFactor;
  if (inputs.baseFactorOverride !== null) {
    local.push(
      'Fator de normalização imposto em ' +
        `${toStringAsFixed(baseFactor, 3)}x por varredura externa, no lugar do ` +
        `${toStringAsFixed(decidedFactor, 3)}x apurado. Este resultado é ` +
        'instrumento de diagnóstico, não avaliação.',
    );
  }

  const healthLocked = normalizes && healthLock && rawFactor > 1.0;
  const saturated =
    normalizes &&
    (rawFactor > ValuationParameters.baseFactorCeiling || rawFactor < ValuationParameters.baseFactorFloor);

  const rebuilt = reconstructionOf(series, currentReturn, cycleReturn, healthLock);
  // O lucro publicado e o de partida, em reais nas duas vias.
  const scale = lane === ValuationLane.shareholder ? laneContext.divisor.count : 1.0;
  const publishedBaseProfit = baseProfitFor(lane, laneContext.latest, laneContext.divisor, 1.0, structuralTaxRate);
  const returns = series.returns;
  const start = returns.length - 1 - ValuationParameters.cycleWindow;
  const normalization = new BaseNormalization({
    lane,
    latestYear: returns.length === 0 ? null : returns[returns.length - 1]!.year,
    latestReturn: currentReturn,
    cycleWindow: returns.length < 2 ? [] : Object.freeze(returns.slice(start < 0 ? 0 : start, returns.length - 1)),
    cycleReturn,
    ratio: deviation?.ratio ?? null,
    robustZ: deviation?.z ?? null,
    deviates: deviates === true,
    trendSlope: trend?.slope ?? null,
    trendT: trend?.tStatistic ?? null,
    trendCriticalT: trend?.criticalT ?? null,
    trendDominates: trend?.dominates === true,
    cyclicalPrecedence: cyclePrecedence,
    operationalDecline: decline,
    healthCapped: healthLocked,
    healthExempt: healthFailed && cyclePrecedence,
    rawFactor,
    factor: baseFactor,
    saturated,
    rebuilt: rebuilt !== null,
    rebuiltPositiveShare: rebuilt?.fraction ?? null,
    imposed: inputs.baseFactorOverride !== null,
    publishedProfit: publishedBaseProfit === null ? null : publishedBaseProfit * scale,
    baseProfit:
      rebuilt !== null
        ? rebuilt.total
        : publishedBaseProfit === null
          ? null
          : publishedBaseProfit * scale * baseFactor,
  });

  auditBaseGuards(audit, currentReturn, cycleReturn, trend, phi, deviates === true, normalizes, baseFactor, series, {
    cyclePrecedence,
    rawFactor,
    saturated,
    operationalDecline: decline,
    healthCapped: healthLocked,
    healthExempt: healthFailed && cyclePrecedence,
    normalization,
  });

  if (normalizes) {
    local.push(
      'O retorno sobre o capital do exercício mais recente ' +
        `(${pct(currentReturn!)}) destoa do retorno típico da empresa, a mediana ` +
        `dos ${normalization.cycleWindow.length} exercícios anteriores ` +
        `(${pct(cycleReturn!)}): a base foi normalizada ` +
        `${baseFactor > 1 ? 'para cima' : baseFactor < 1 ? 'para baixo' : 'sem mudança'}, ` +
        'partindo do lucro que a empresa teria rendendo o típico — fator de ' +
        `${toStringAsFixed(baseFactor, 2)}x sobre o lucro publicado.`,
    );
    if (cyclePrecedence && trend?.dominates === true) {
      local.push(
        'A tendência do retorno é significante e domina a reversão à média, ' +
          'mas o ativo é de setor de commodity ou cíclico pesado: ali a perna ' +
          'de alta do ciclo tem a forma de uma tendência, e lê-la como patamar ' +
          'estrutural é o erro que se quer evitar. A reversão ao ciclo tem ' +
          'precedência, e a base foi normalizada.',
      );
    }
    if (healthFailed && cyclePrecedence && rawFactor > 1.0) {
      local.push(
        `O lucro ou o EBITDA recuou ${pct(decline!)} no triênio, acima do ` +
          `máximo de ${pct(ValuationParameters.maxOperationalDecline)}, mas o ` +
          'ativo é de setor de commodity: ali a queda entre pico e vale é ' +
          'oscilação do preço do insumo, não quebra de modelo de negócio. A ' +
          'trava de saúde não se aplica à base, e a convergência ao ciclo opera ' +
          'nos dois sentidos. A vantagem competitiva residual não tem trava de ' +
          'saúde desde a decisão 36: quem decide é a persistência medida do ' +
          'excedente.',
      );
    }
    if (healthLocked) {
      local.push(
        `O lucro ou o EBITDA recuou ${pct(decline!)} no triênio recente, acima ` +
          `do máximo de ${pct(ValuationParameters.maxOperationalDecline)}. A ` +
          'base **não foi normalizada para cima**: o fator seria de ' +
          `${toStringAsFixed(rawFactor, 2)}x e ficou em 1,00x. Uma empresa que ` +
          'perdeu mais da metade do resultado mudou de patamar, e trazer a base ' +
          `de volta à mediana de ${ValuationParameters.cycleWindow} exercícios ` +
          'atribuiria a ela um retorno que não vai se repetir.',
      );
    }
    if (saturated && !healthLocked) {
      local.push(
        'O fator bruto de normalização seria de ' +
          `${toStringAsFixed(rawFactor, 2)}x e foi saturado em ` +
          `${toStringAsFixed(baseFactor, 2)}x. O limite é de política, não de ` +
          'estatística: o preço justo é proporcional ao fluxo-base, e acima de ' +
          `${toStringAsFixed(ValuationParameters.baseFactorCeiling, 2)}x a ` +
          'normalização deixaria de corrigir um exercício para inventar uma ' +
          'empresa. O preço justo abaixo é, nesta medida, conservador.',
      );
    }
    if (!comparable) {
      local.push(
        `A base de capital cresceu ${str(r(phi!, 2))}x além do que o lucro ` +
          'retido financiaria, o que indica evento societário ou aquisição. ' +
          'A normalização foi aplicada mesmo assim: o retorno percentual é ' +
          'grandeza intensiva, e reverte à mediana do ciclo qualquer que tenha ' +
          'sido a mudança de tamanho. O que a série não sustenta é comparar ' +
          '**níveis absolutos** de lucro entre as pontas da janela.',
      );
    }
  }

  return {
    taxRate: structuralTaxRate,
    series,
    currentReturn,
    cycleReturn,
    phi,
    factor: baseFactor,
    reconstruction: rebuilt,
    normalization,
  };
}

/**
 * **A reconstrução do fluxo-base pelo ciclo** (decisão 53): o retorno do
 * ciclo sobre o capital de hoje, quando o último exercício veio no prejuízo,
 * o ciclo é positivo, a trava de saúde não reprova e ao menos
 * `minPositiveFlow` da janela é positiva.
 */
function reconstructionOf(
  series: CapitalSeries,
  currentReturn: number | null,
  cycleReturn: number | null,
  healthLock: boolean,
): Reconstruction | null {
  if (currentReturn === null || currentReturn > 0 || cycleReturn === null || cycleReturn <= 0 || healthLock) {
    return null;
  }
  const fraction = series.positiveShare({ window: ValuationParameters.cycleWindow });
  const capital = series.latestBase;
  if (fraction === null || fraction < ValuationParameters.minPositiveFlow || capital === null || capital <= 0) {
    return null;
  }
  return { total: cycleReturn * capital, fraction };
}

/**
 * **O fluxo-base da via**: o exercício mais recente vezes o fator do ciclo,
 * ou, com o exercício no prejuízo, o retorno do ciclo sobre o capital de hoje
 * (decisão 53). `null` sem base positiva.
 */
function baseFlow(laneContext: Lane, b: Base, local: string[]): { base: number; rebuilt: boolean } | null {
  const lane = laneContext.lane;
  const latest = laneContext.latest;
  const divisor = laneContext.divisor;
  const currentReturn = b.currentReturn;
  const cycleReturn = b.cycleReturn;
  const baseFactor = b.factor;
  let cycleBase: number | null = null;
  const reconstruction = b.reconstruction;
  if (reconstruction !== null && currentReturn !== null && cycleReturn !== null) {
    const total = reconstruction.total;
    const perUnit = lane === ValuationLane.firm ? total : divisor.count > 0 ? total / divisor.count : null;
    if (perUnit !== null && Number.isFinite(perUnit) && perUnit > 0) {
      cycleBase = perUnit;
      local.push(
        'O exercício-base veio no prejuízo — retorno de ' +
          `${pct(currentReturn)} sobre o capital —, e o fluxo-base foi ` +
          `reconstruído do ciclo: ${pct(cycleReturn)} de retorno mediano ` +
          `sobre o capital de hoje, com ${pct(reconstruction.fraction)} da janela ` +
          'positiva. **O preço justo não repousa em nenhum exercício recente ' +
          'observado**: repousa na afirmação de que a empresa volta ao que ' +
          'já foi.',
      );
    }
  }

  const base = cycleBase ?? baseProfitFor(lane, latest, divisor, baseFactor, b.taxRate);
  if (base === null || base <= 0) return null;
  return { base, rebuilt: cycleBase !== null };
}

/**
 * **Saída 2 da Porta 2 — de onde vem a taxa de crescimento.** Fundamental
 * quando a dispersão a identifica; a inflação quando a retenção observada a
 * financia; zero no resto. `null` quando a dispersão não é medível.
 */
function output2(laneContext: Lane, b: Base, local: string[]): { origin: GrowthOrigin; g: number } | null {
  const inputs = laneContext.inputs;
  const series = b.series;
  const cycleReturn = b.cycleReturn;
  const audit = laneContext.audit;
  const dispersion = GrowthGuards.dispersion(series);
  if (dispersion === null) return null;

  const retention = series.medianRetention;
  let origin: GrowthOrigin;
  let decidedG: number;
  if (dispersion.isIdentified) {
    origin = GrowthOrigin.fundamental;
    decidedG = dispersion.medianGrowth;
  } else if (
    GrowthGuards.anchorIsFundable({ inflation: inputs.inflation, cycleReturn, observedRetention: retention })
  ) {
    origin = GrowthOrigin.inflationAnchor;
    decidedG = inputs.inflation;
    local.push(
      `Crescimento fundamental não identificável: ${dispersion.failure ?? 'null'}. ` +
        `Adotada a inflação de ${pct(inputs.inflation)}, que a retenção ` +
        `observada de ${pct(retention ?? 0)} financia.`,
    );
  } else {
    origin = GrowthOrigin.earningsPower;
    decidedG = 0.0;
    local.push(
      'Crescimento não identificável nem financiável pela retenção observada; ' +
        'a avaliação é do valor da capacidade de gerar lucro, sem crescimento. ' +
        'É estimativa deliberadamente conservadora.',
    );
  }
  const g = inputs.growthOverride ?? decidedG;
  if (inputs.growthOverride !== null) {
    local.push(
      `Crescimento imposto em ${pct(g)} por varredura externa, no lugar ` +
        `dos ${pct(decidedG)} que as guardas apuraram. Este resultado é ` +
        'instrumento de diagnóstico, não avaliação.',
    );
  }
  auditGrowthOutcome(audit, dispersion, origin, g, retention, cycleReturn, inputs.inflation);
  return { origin, g };
}

/**
 * O que o prazo da concessão faz com a avaliação, em texto (decisão 88).
 * [capitalMeasured] é `false` sem retorno sobre o capital utilizável.
 */
function contractWarning(inputs: ValuationInputs, options: { capitalMeasured: boolean }): string {
  const n = inputs.projectionYears;
  const refusal = 'O excedente de retorno do capital novo é recusado, como em ' + 'toda concessão: a tarifa remunera o capital ao custo dele.';
  const devolve =
    'o que a amortização, a indenização do investimento não ' +
    'amortizado ou uma renovação que refaz a tarifa ao custo de capital ' +
    'devolvem';
  const end = inputs.concessionEnd;
  const years = contractYears(inputs);
  const yearsText = n === 1 ? '1 ano' : `${n} anos`;
  if (end !== null && years !== null && options.capitalMeasured) {
    if (years <= n) {
      return (
        'O negócio opera sob concessão, e a mediana das outorgas ' +
        `vigentes no Formulário de Referência termina em ${fmtDate(end)}: a ` +
        `projeção explícita vai até lá, ${yearsText}, e o valor terminal é o ` +
        `capital investido nessa data — ${devolve} —, sem excedente depois ` +
        `do contrato. ${refusal}`
      );
    }
    const beyond = years - n;
    return (
      'O negócio opera sob concessão, e a mediana das outorgas vigentes ' +
      `no Formulário de Referência termina em ${fmtDate(end)}, ${beyond} ` +
      `${beyond === 1 ? 'ano' : 'anos'} depois da projeção. O valor terminal é ` +
      'o capital investido no fim da projeção mais o excedente de retorno ' +
      'sobre ele até o fim do contrato, e não para sempre: no fim, o ' +
      `capital volta — ${devolve}. ${refusal}`
    );
  }
  const reason =
    end === null
      ? 'o prazo não foi lido do Formulário de Referência'
      : years === null
        ? 'a mediana das outorgas declaradas no Formulário de Referência, ' + `${fmtDate(end)}, já passou`
        : 'sem retorno sobre o capital utilizável, o capital investido não ' +
          'se apura e o terminal do contrato não pode ser montado';
  return (
    `O negócio opera sob concessão, e ${reason}. O valor terminal supõe o ` +
    'excedente de retorno sobre o capital existente para sempre; num ' +
    'contrato que acaba, ele acaba junto, e o preço justo fica abaixo do ' +
    `publicado — acima, se o capital rende menos que o custo dele. ${refusal}`
  );
}

/** A frase da participação do capital próprio, ou o motivo de não haver uma. */
function stakeExcerpt(rates: LeveredRates, n: number): string {
  const start = rates.equityShareAt(0);
  const end = rates.equityShareAt(n);
  if (start === null || end === null) {
    return (
      'A participação do capital próprio no valor da firma não tem ' +
      'sentido aqui — o caixa líquido supera o próprio negócio.'
    );
  }
  return (
    `A participação do capital próprio sai de ${pct(start)} para ` +
    `${pct(end)} no mesmo intervalo — e é justamente o que a taxa única ` +
    'não enxergava.'
  );
}

/**
 * Reúne os fatos que qualificam o preço justo. **Não julga nada de novo**:
 * cada ressalva corresponde a uma decisão que a cascata já tomou.
 */
function diagnose(args: {
  outcome: DcfOutcome;
  divisor: QuotedShares;
  baseFactor: number;
  growthOrigin: GrowthOrigin;
  moatApplied: boolean;
  finiteTerm: boolean;
  stateControlled: boolean;
  rebuiltBase: boolean;
  costOfEquity: number;
  terminalDiscountRate: number;
  terminalRetainedSpread: number;
  growthRate: number;
  returnOnCapital: number;
  terminalReturnOnCapital: number | null;
  firmTaxRate: number | null;
  terminalCostOfEquity: number | null;
  terminalEquityShare: number | null;
  postStatementCapital: number | null;
  retentionPath: readonly number[];
  growthPath: readonly number[];
  baseNormalization: BaseNormalization | null;
}): ValuationDiagnostics {
  const { outcome, divisor, baseFactor, growthOrigin } = args;
  const caveats: ValuationCaveat[] = [];
  if (outcome.terminalShare > ValuationDiagnostics.terminalShareLimit) caveats.push(ValuationCaveat.heavyTerminal);
  if (growthOrigin !== GrowthOrigin.fundamental) caveats.push(ValuationCaveat.unidentifiedGrowth);
  if (divisor.diverge && divisor.source !== QuotedSharesSource.official) caveats.push(ValuationCaveat.uncertainScale);
  if (baseFactor > ValuationDiagnostics.baseFactorLimit || baseFactor < 1 / ValuationDiagnostics.baseFactorLimit) {
    caveats.push(ValuationCaveat.strongNormalizedBase);
  }
  if (args.finiteTerm) caveats.push(ValuationCaveat.fixedTerm);
  if (args.rebuiltBase) caveats.push(ValuationCaveat.rebuiltBase);
  if (args.stateControlled) caveats.push(ValuationCaveat.stateControl);
  if (outcome.equityShare < ValuationDiagnostics.fragileEquityShare) caveats.push(ValuationCaveat.fragileBridge);
  // **O excedente perpétuo do capital instalado** (item B12), contra o valor
  // do capital próprio, o mesmo denominador de `terminalShare`.
  const excess = outcome.discountedTerminalExcess;
  const excessWeight = excess === null || outcome.equityValue <= 0 ? null : excess / outcome.equityValue;
  return new ValuationDiagnostics({
    terminalShare: outcome.terminalShare,
    terminalExcessShare: excessWeight,
    impliedTerminalReturn: outcome.impliedTerminalReturn,
    terminalEquityShare: args.terminalEquityShare,
    postStatementCapital: args.postStatementCapital,
    baseNormalization: args.baseNormalization,
    equityShare: outcome.equityShare,
    costOfEquity: args.costOfEquity,
    baseFactor,
    growthIdentified: growthOrigin === GrowthOrigin.fundamental,
    moatApplied: args.moatApplied,
    terminalDiscountRate: args.terminalDiscountRate,
    terminalRetainedSpread: args.terminalRetainedSpread,
    growthRate: args.growthRate,
    returnOnCapital: args.returnOnCapital,
    terminalReturnOnCapital: args.terminalReturnOnCapital,
    firmTaxRate: args.firmTaxRate,
    terminalCostOfEquity: args.terminalCostOfEquity,
    retentionPath: Object.freeze([...args.retentionPath]),
    growthPath: Object.freeze([...args.growthPath]),
    caveats: Object.freeze([...caveats]),
  });
}

/**
 * Lucro-base da via, já normalizado pelo fator do ciclo: NOPAT na via da
 * firma, lucro por papel na unidade negociada na do acionista.
 */
function baseProfitFor(
  lane: ValuationLane,
  latest: FundamentalsSnapshot,
  divisor: QuotedShares,
  baseFactor: number,
  firmTaxRate: number | null,
): number | null {
  if (lane === ValuationLane.firm) {
    const n = latest.nopatAtRate(firmTaxRate);
    return n === null ? null : n * baseFactor;
  }
  const eps = earningsPerQuotedUnit(latest, divisor);
  return eps === null ? null : eps * baseFactor;
}

/** Lucro por **unidade negociada**, na mesma escala do preço de tela. */
function earningsPerQuotedUnit(snapshot: FundamentalsSnapshot, divisor: QuotedShares): number | null {
  const netIncome = snapshot.netIncome;
  if (netIncome !== null && divisor.count > 0) return netIncome / divisor.count;
  const published = snapshot.earningsPerShare;
  return published === null ? null : published * divisor.sharesPerQuote;
}

/**
 * Monta o WACC, ou o Ke quando a estrutura de capital não é observável.
 * [capmOverride] monta o custo de capital **de equilíbrio** sem duplicar a
 * função; [terminal] liga o `D/E` imposto do B15.
 */
function wacc(
  inputs: ValuationInputs,
  latest: FundamentalsSnapshot,
  warnings: string[],
  divisor: QuotedShares,
  audit: AuditTransaction | null,
  options: { capmOverride?: CapmInputs | null; terminal?: boolean } = {},
): CurrentCost {
  const capm = options.capmOverride ?? inputs.capm;
  const terminal = options.terminal ?? false;
  // **A dívida dos pesos é a líquida** (decisão 104).
  const raw = latest.totalDebt;
  const imposedLeverage = terminal ? inputs.terminalLeverageOverride : null;
  const debt = imposedLeverage === null ? latest.netDebt : divisor.count * inputs.marketPrice * imposedLeverage;
  // O peso do capital próprio é o valor de mercado **pelo divisor da ponte**
  // (decisão 83); **o minoritário não entra neste peso** (item B23).
  const equity = divisor.count * inputs.marketPrice + (inputs.minorityEquityValue ?? 0);

  // O observado entra apenas como **conferência** (decisão 31).
  const kd = latest.costOfDebt;
  // O escudo fiscal usa a alíquota **marginal estatutária**.
  const tax = ValuationParameters.statutoryTaxRate;
  const effective = latest.effectiveTaxRate;

  // **Companhia sem dívida e com caixa não degenera para o Ke** (decisão 58).
  const noContractedDebt = raw <= 0;
  // A faixa da despesa financeira é medida na taxa da **data** (item B10).
  const reference = inputs.creditReferenceRiskFree ?? inputs.capm.riskFreeRate;
  // **O prêmio de crédito existe mesmo quando o WACC estático não** (item B26).
  const premium = noContractedDebt
    ? 0.0
    : CostOfCapital.syntheticSpread({
        leverage: latest.netDebtToEbitda,
        coverage: latest.interestCoverage,
        observedCostOfDebt: kd,
        riskFreeRate: reference,
      });

  // **Só a falta de valor de mercado impede o WACC estático** (item B26).
  if (equity <= 0) {
    warnings.push(
      'Estrutura de capital indisponível: sem valor de mercado utilizável o ' +
        'WACC estático não é montável, e quando o custo de capital não é ' +
        'resolvido ano a ano o desconto é o custo do capital próprio.',
    );
    audit?.step({
      formulaName: 'Taxa de desconto — degeneração para o Ke',
      latex: String.raw`r = K_e \quad (\text{sem estrutura de capital observável})`,
      variables: {
        'D bruta (R$)': r(raw),
        'D líquida (R$)': r(debt),
        'E (R$)': r(equity),
        'K_d (% a.a.)': kd === null ? null : r(kd * 100),
      },
      steps: [
        'Passo único: dívida, valor de mercado ou custo da dívida ausentes; ' +
          'o WACC não é montável e o desconto adota o custo do capital ' +
          'próprio.',
      ],
      result: capm.costOfEquity * 100,
      unit: '% a.a.',
    });
    return { rate: capm.costOfEquity, costOfDebtEstimated: false, costOfDebt: null, creditSpread: premium };
  }

  if (effective !== null && Math.abs(effective - tax) > 0.1) {
    warnings.push(
      `A alíquota efetiva do exercício foi de ${pct(effective)}, distante da ` +
        `alíquota marginal estatutária de ${pct(tax)} usada no escudo fiscal ` +
        'do WACC. O escudo desconta despesa financeira **futura**, que se ' +
        'realiza à alíquota legal; a efetiva de um exercício carrega ' +
        'incentivo, JCP, prejuízo compensado e diferimento.',
    );
  }

  const coc = new CostOfCapital({
    capm,
    costOfDebt: kd,
    taxRate: tax,
    equityValue: equity,
    debtValue: debt,
    interestCoverage: latest.interestCoverage,
    netDebtToEbitda: latest.netDebtToEbitda,
    creditReferenceRate: reference,
    hasContractedDebt: !noContractedDebt,
    // **O caixa entra separado, e rende a taxa livre de risco**; com `D/E`
    // imposto o corte não existe.
    cashValue: imposedLeverage === null ? latest.totalCash : null,
  });

  if (noContractedDebt) {
    warnings.push(
      `${inputs.ticker.value} não tem dívida contratada nos demonstrativos: ` +
        'o que sobra do lado do financiamento é caixa, e ele entra no desconto ' +
        'com peso negativo e rendimento igual à taxa livre de risco ' +
        `(${pct(capm.riskFreeRate)} a.a.). O caixa sai da taxa e volta na ` +
        'apuração do capital próprio — contá-lo só de um lado inflaria o preço ' +
        'justo.',
    );
  }
  if (!noContractedDebt && kd === null) {
    const leverage = latest.netDebtToEbitda;
    warnings.push(
      `A despesa financeira de ${inputs.ticker.value} não está publicada: a ` +
        'cobertura de juros não é medível, e o prêmio de crédito sai só da ' +
        'alavancagem' +
        `${leverage === null ? ', que também não é medível — prêmio máximo' : ` (${toStringAsFixed(leverage, 2)}x de dívida líquida sobre EBITDA)`}` +
        `. Custo da dívida adotado: ${pct(coc.effectiveCostOfDebt)} a.a.`,
    );
  }
  if (!noContractedDebt && coc.costOfDebtWasClamped) {
    warnings.push(
      costOfDebtWarning({
        observed: kd!,
        adopted: coc.effectiveCostOfDebt,
        reference,
        leverage: latest.netDebtToEbitda,
        coverage: latest.interestCoverage,
      }),
    );
  }
  if (coc.waccWasFloored) {
    warnings.push(
      `O WACC calculado (${pct(coc.rawWacc)} a.a.) ficou abaixo da taxa ` +
        'livre de risco; adotada a própria taxa livre de risco ' +
        `(${pct(capm.riskFreeRate)} a.a.) como piso do desconto.`,
    );
  }
  // **Caixa líquido**: o peso da dívida é negativo e o WACC fica acima do Ke (decisão 104).
  if (debt < 0 && coc.totalCapital > 0) {
    warnings.push(
      `${inputs.ticker.value} tem caixa líquido: o peso da dívida no WACC é ` +
        `negativo (${str(r(coc.debtShare, 4))}) e o desconto fica acima do custo ` +
        'do capital próprio. A conta é a mesma dos dois lados — o caixa sai da ' +
        'taxa e volta na apuração do capital próprio, que subtrai a dívida ' +
        'líquida.',
    );
  }

  auditWacc(audit, coc);
  return {
    rate: coc.wacc,
    costOfDebtEstimated: coc.costOfDebtWasClamped,
    costOfDebt: coc.effectiveCostOfDebt,
    creditSpread: premium,
  };
}

/**
 * O fator que traduz o deslocamento do cenário em deslocamento do `Ke` (item
 * B20, decisão 121). Participação fora de `(0, 1]` devolve 1.
 */
function scenarioFactor(laneContext: Lane, cost: Cost): number {
  const reading = laneContext.inputs.scenarioTranslation;
  if (reading === ScenarioTranslation.oneToOne) return 1.0;

  const rates = cost.rates;
  let equityWeight: number | null = null;
  if (rates !== null && rates.equity.length > 0 && rates.debt.length > 0) {
    const v = rates.equity[0]! + rates.debt[0]!;
    if (v > 0) equityWeight = rates.equity[0]! / v;
  } else {
    const e = laneContext.divisor.count * laneContext.inputs.marketPrice;
    const v = e + laneContext.latest.netDebt;
    if (v > 0) equityWeight = e / v;
  }
  if (equityWeight === null || !Number.isFinite(equityWeight) || equityWeight <= 0 || equityWeight > 1) {
    return 1.0;
  }

  if (reading === ScenarioTranslation.fixedStructure) return 1 / equityWeight;
  // `ΔWACC = ΔR_f·(w_E + w_D(1−t))` quando os dois custos sobem junto com a taxa livre de risco.
  return 1 / (1 - (1 - equityWeight) * ValuationParameters.statutoryTaxRate);
}

/**
 * O aviso de quando o custo da dívida adotado se afasta do observado.
 * **Descreve a regra que a conta aplica** (item B32).
 */
function costOfDebtWarning(args: {
  observed: number;
  adopted: number;
  reference: number;
  leverage: number | null;
  coverage: number | null;
}): string {
  const { observed, adopted, reference, leverage, coverage } = args;
  const cap = reference + CostOfCapital.maxCreditSpread;
  const within = observed >= reference && observed <= cap;
  const leverageSpreadValue = CostOfCapital.leverageSpread(leverage);
  const coverageSpreadValue = CostOfCapital.coverageSpread(coverage);
  const lev =
    leverage === null || !Number.isFinite(leverage)
      ? 'alavancagem, que não é medível'
      : `alavancagem de ${toStringAsFixed(leverage, 2)}x de dívida líquida ` + 'sobre EBITDA';
  const coverageRatio =
    coverage === null || !Number.isFinite(coverage)
      ? 'cobertura de juros, que não é medível'
      : `cobertura de juros de ${toStringAsFixed(coverage, 2)}x`;
  const coverageWins = within && coverageSpreadValue > leverageSpreadValue;
  const band = `da faixa defensável de ${pct(reference)} a ${pct(cap)}`;
  const origin = within
    ? `A razão observada caiu dentro ${band}, e por isso a despesa é juro e ` +
      `a cobertura também fala: vale o prêmio mais exigente entre a ${coverageRatio} ` +
      `e a ${lev} — o da ${coverageWins ? 'cobertura' : 'alavancagem'}, ` +
      `de ${pct(coverageWins ? coverageSpreadValue : leverageSpreadValue)}.`
    : `A razão observada caiu fora ${band}, e por isso mede outra coisa — ` +
      'arrendamento, variação cambial —: a cobertura sai da conta, e o ' +
      `prêmio é o da ${lev}, de ${pct(leverageSpreadValue)}.`;
  return (
    'O custo da dívida implícito nos demonstrativos deu ' +
    `${pct(observed)} a.a., e o adotado é ${pct(adopted)} a.a. O ` +
    'desconto usa sempre a taxa livre de risco mais o prêmio da ' +
    'classificação sintética: o custo de capital pede o de captar hoje, e ' +
    'a despesa publicada carrega dívida antiga, arrendamento e variação ' +
    `cambial. ${origin}`
  );
}

/**
 * As emissões por valor **depois** do balanço usado e até a data da
 * avaliação (item B28), somadas em centavos inteiros ([Money]). Só a emissão
 * **declarada** entra no valor; a sem declaração sai à parte, para o aviso.
 */
function subsequentCapital(
  inputs: ValuationInputs,
  latest: FundamentalsSnapshot,
): { value: number; issuances: number; withoutDeclaration: number; sharesWithoutDeclaration: number } {
  if (inputs.shareIssues.length === 0) {
    return { value: 0.0, issuances: 0, withoutDeclaration: 0.0, sharesWithoutDeclaration: 0 };
  }
  const fromDate = DateTime.utc(latest.fiscalPeriodEnd.year, latest.fiscalPeriodEnd.month, latest.fiscalPeriodEnd.day);
  const until = DateTime.utc(inputs.asOf.year, inputs.asOf.month, inputs.asOf.day);
  let value = Money.zero;
  let n = 0;
  let without = Money.zero;
  let sharesWithout = 0;
  for (const i of inputs.shareIssues) {
    if (!i.isUsable) continue;
    const d = DateTime.utc(i.date.year, i.date.month, i.date.day);
    if (!d.isAfter(fromDate) || d.isAfter(until)) continue;
    if (i.declared) {
      value = value.plus(i.amount);
      n++;
    } else {
      without = without.plus(i.amount);
      sharesWithout += i.shares;
    }
  }
  return {
    value: value.reais,
    issuances: n,
    withoutDeclaration: without.reais,
    sharesWithoutDeclaration: sharesWithout,
  };
}

/**
 * O desfecho do desconto **com o capital que entrou depois do balanço** (item
 * B28): somado ao capital próprio antes da divisão por papel, **pelo valor de
 * emissão, e fora do fluxo**.
 */
function withPosteriorCapital(laneContext: Lane, o: DcfOutcome): DcfOutcome {
  const c = laneContext.subsequentCapital;
  if (!(c > 0) || !(laneContext.divisor.count > 0)) return o;
  const perShare = c / laneContext.divisor.count;
  const e0 = o.equityValue;
  const e1 = e0 + (laneContext.lane === ValuationLane.shareholder ? perShare : c);
  return new DcfOutcome({
    projectedFlows: o.projectedFlows,
    discountedFlows: o.discountedFlows,
    terminalValue: o.terminalValue,
    discountedTerminalValue: o.discountedTerminalValue,
    enterpriseValue: o.enterpriseValue,
    equityValue: e1,
    fairValuePerShare: o.fairValuePerShare + perShare,
    // O capital novo não é terminal: a razão encolhe na mesma proporção (decisão 51).
    terminalShare: Math.abs(e0) > 0 && Math.abs(e1) > 0 ? (o.terminalShare * e0) / e1 : o.terminalShare,
    equityShare: o.equityShare,
    discountedTerminalExcess: o.discountedTerminalExcess,
    impliedTerminalReturn: o.impliedTerminalReturn,
    discountRates: o.discountRates,
    terminalDiscountRateUsed: o.terminalDiscountRateUsed,
    firmFlows: o.firmFlows,
    debtService: o.debtService,
    firmTerminalValue: o.firmTerminalValue,
    terminalFirmFlow: o.terminalFirmFlow,
    terminalDebtService: o.terminalDebtService,
    terminalEquityFlow: o.terminalEquityFlow,
  });
}

/**
 * O aviso da triangulação, quando as duas leituras discordam além do limite.
 * **Ele não escolhe**: o preço justo continua sendo o do fluxo descontado.
 */
function triangulationWarning(t: PeerTriangulation, dcf: number): string {
  const applied: string[] = [];
  for (const reading of t.readings) {
    if (reading.applied) {
      applied.push(
        `${multipleKindDiagnostic(reading.kind)} ${str(r(reading.peer!.median, 2))}× ` +
          `(${reading.peer!.peers} pares, ${reading.peer!.group})`,
      );
    }
  }
  return (
    'A leitura por múltiplos de pares diverge do fluxo descontado: ' +
    `R$ ${str(r(t.consolidated!, 2))} contra R$ ${str(r(dcf, 2))}, ` +
    `${pct(t.divergence!)} de diferença. ` +
    `Saiu de ${applied.join('; ')}. ` +
    '**O preço justo continua sendo o do fluxo descontado** — a segunda ' +
    'leitura é teste de sanidade sobre o nível, e a divergência fica ' +
    'declarada em vez de reconciliada.'
  );
}

function withScenarios(args: {
  inputs: ValuationInputs;
  model: ValuationModel;
  assumptions: DcfAssumptions;
  baseValue: number;
  valuate: (a: DcfAssumptions) => Result<number>;
  scenarioBuilder: ((base: DcfAssumptions) => AssumptionSource) | null;
  samples: number;
  seed: number;
  warnings: readonly string[];
  diagnostics: ValuationDiagnostics;
  triangulation: PeerTriangulation | null;
  manual: ManualValuation | null;
}): ValuationResult {
  const { inputs, model, assumptions, baseValue, samples } = args;
  const source = (args.scenarioBuilder ?? ((a: DcfAssumptions) => DiscreteScenarios.around(a)))(assumptions);
  const volatility = inputs.prices === null ? null : CalibratedBand.trailingVolatility(inputs.prices);
  const outcome = ScenarioEngine.run({ source, valuate: args.valuate, samples, seed: args.seed });

  if (outcome.isErr) {
    return new ValuationResult({
      ticker: inputs.ticker,
      asOf: inputs.asOf,
      model,
      fairValue: Money.fromReais(baseValue),
      marketPrice: Money.fromReais(inputs.marketPrice),
      // **A taxa do ano 1, e não o campo escalar** (item B11).
      discountRate: assumptions.discountRateAt(1),
      marginOfSafety: inputs.marginOfSafety,
      warnings: [...args.warnings, 'Cenários não puderam ser gerados; apresentado apenas o cenário base.'],
      diagnostics: args.diagnostics,
      priceVolatility: volatility,
      triangulation: args.triangulation,
      manual: args.manual,
    });
  }

  const scenarios = outcome.unwrap();
  const local = [...args.warnings];
  if (scenarios.discarded > 0 && scenarios.mode === ScenarioMode.monteCarlo) {
    const discardedPct = (scenarios.discarded / Math.max(1, samples)) * 100;
    if (discardedPct > 5) {
      local.push(
        `${toStringAsFixed(discardedPct, 0)}% dos sorteios foram descartados por ` +
          'produzirem valor inválido; estreite as faixas de premissas.',
      );
    }
  }

  let discreteScenarios: Map<ScenarioBand, Money> | null = null;
  if (scenarios.discrete !== null) {
    discreteScenarios = new Map<ScenarioBand, Money>();
    for (const [band, value] of scenarios.discrete) discreteScenarios.set(band, Money.fromReais(value));
  }

  return new ValuationResult({
    ticker: inputs.ticker,
    asOf: inputs.asOf,
    model,
    fairValue: Money.fromReais(baseValue),
    marketPrice: Money.fromReais(inputs.marketPrice),
    discountRate: assumptions.discountRateAt(1),
    marginOfSafety: inputs.marginOfSafety,
    mode: scenarios.mode,
    discreteScenarios,
    distribution: scenarios.distribution,
    warnings: local,
    diagnostics: args.diagnostics,
    priceVolatility: volatility,
    triangulation: args.triangulation,
    manual: args.manual,
  });
}

// ---------------------------------------------------------------- auditoria --
//
// Tudo daqui para baixo é rastro, não cálculo: cada função recebe valores
// **já computados** pelo caminho normal e apenas os descreve. Todas saem cedo
// quando não há transação aberta.

function inputPayload(inputs: ValuationInputs): JsonMap {
  // Os exercícios entram resumidos e limitados aos mais recentes.
  const recent = inputs.fundamentals.length <= 6 ? inputs.fundamentals : inputs.fundamentals.slice(inputs.fundamentals.length - 6);

  const payload: JsonMap = {
    ticker: inputs.ticker.value,
    asOf: inputs.asOf.toIso8601String(),
    marketPrice: r(inputs.marketPrice),
    capm: {
      riskFreeRate: r(inputs.capm.riskFreeRate, 6),
      beta: r(inputs.capm.beta, 4),
      marketPremium: r(inputs.capm.marketPremium, 6),
      betaSource: inputs.capm.betaSource.name,
      premiumSource: inputs.capm.premiumSource.name,
    },
    marginOfSafety: r(inputs.marginOfSafety, 4),
    projectionYears: inputs.projectionYears,
  };
  if (inputs.concessionEnd !== null) payload['concessionEnd'] = fmtDate(inputs.concessionEnd);
  payload['perpetualGrowthCap'] = r(inputs.perpetualGrowthCap, 6);
  payload['fundamentalsPeriods'] = inputs.fundamentals.length;
  // Quantos exercícios ficaram de fora do resumo abaixo.
  payload['fundamentalsOmitted'] = inputs.fundamentals.length - recent.length;
  payload['fundamentals'] = recent.map((f) => ({
    fiscalPeriodEnd: f.fiscalPeriodEnd.toIso8601String(),
    netIncome: f.netIncome === null ? null : r(f.netIncome),
    ebitda: f.ebitda === null ? null : r(f.ebitda),
    operatingCashFlow: f.operatingCashFlow === null ? null : r(f.operatingCashFlow),
    freeCashFlow: f.freeCashFlow === null ? null : r(f.freeCashFlow),
    sharesOutstanding: f.sharesOutstanding === null ? null : r(f.sharesOutstanding, 0),
    marketCap: f.marketCap === null ? null : r(f.marketCap),
    totalDebt: r(f.totalDebt),
    netDebt: r(f.netDebt),
    effectiveTaxRate: f.effectiveTaxRate === null ? null : r(f.effectiveTaxRate, 4),
    enterpriseToEbitda: f.enterpriseToEbitda === null ? null : r(f.enterpriseToEbitda, 4),
    bookValuePerShare: f.bookValuePerShare === null ? null : r(f.bookValuePerShare),
  }));
  // **O resto do que entra na conta** (item D4).
  payload['scenarioTranslation'] = inputs.scenarioTranslation.key;
  payload['sectorKey'] = inputs.sectorKey;
  payload['industry'] = inputs.industry;
  payload['isDistressed'] = inputs.isDistressed;
  payload['stateControlled'] = inputs.stateControlled;
  payload['inflation'] = r(inputs.inflation, 6);
  payload['terminalRiskFreeRate'] = r(inputs.terminalRiskFreeRate, 6);
  const curve = inputs.riskFreeCurve;
  if (curve !== null) {
    payload['riskFreeCurve'] = {
      referenceDate: fmtDate(curve.referenceDate),
      vertices: curve.vertices.map((v) => ({ years: r(v.years, 4), rate: r(v.rate, 6) })),
    };
  }
  const official = inputs.officialShares;
  if (official !== null) {
    payload['officialShares'] = { total: r(official.total, 0), asOf: fmtDate(official.asOf) };
  }
  payload['declaredSharesPerUnit'] = inputs.declaredSharesPerUnit;
  payload['unleveredBeta'] = inputs.unleveredBeta === null ? null : r(inputs.unleveredBeta, 4);
  payload['betaWindowYears'] = inputs.betaWindowYears === null ? null : r(inputs.betaWindowYears, 2);
  payload['dividendsInBeta'] = inputs.dividendsInBeta;
  payload['creditReferenceRiskFree'] =
    inputs.creditReferenceRiskFree === null ? null : r(inputs.creditReferenceRiskFree, 6);
  payload['minorityEquityValue'] = inputs.minorityEquityValue === null ? null : r(inputs.minorityEquityValue);
  const series = inputs.prices;
  if (series !== null) {
    const prices: JsonMap = { points: series.points.length };
    if (series.points.length > 0) {
      prices['first'] = fmtDate(series.points[0]!.date);
      prices['last'] = fmtDate(series.points[series.points.length - 1]!.date);
    }
    payload['prices'] = prices;
  }
  const pairs = inputs.peerMultiples;
  if (pairs !== null) {
    const peers: JsonMap = { asOf: fmtDate(pairs.asOf) };
    for (const [kind, peer] of pairs.byKind) {
      peers[kind.key] = { median: r(peer.median, 4), peers: peer.peers, group: peer.group };
    }
    payload['peerMultiples'] = peers;
  }
  // Só com emissão: o rastro de quem não tem fica como era (item B28).
  if (inputs.shareIssues.length > 0) {
    payload['shareIssues'] = inputs.shareIssues.map((i) => {
      const issue: JsonMap = { date: fmtDate(i.date), amount: r(i.amount.reais), shares: i.shares };
      if (!i.declared) issue['declared'] = false;
      return issue;
    });
  }
  const overrides: JsonMap = {};
  if (inputs.laneOverride !== null) overrides['lane'] = inputs.laneOverride.name;
  if (inputs.terminalReturnOverride !== null) overrides['terminalReturn'] = r(inputs.terminalReturnOverride, 6);
  if (inputs.growthOverride !== null) overrides['growth'] = r(inputs.growthOverride, 6);
  if (inputs.baseFactorOverride !== null) overrides['baseFactor'] = r(inputs.baseFactorOverride, 4);
  if (inputs.reinvestmentOverride !== null) overrides['reinvestment'] = inputs.reinvestmentOverride.key;
  if (inputs.cashTimingOverride !== null) overrides['cashTiming'] = inputs.cashTimingOverride.key;
  if (inputs.terminalBetaWeightOverride !== null) {
    overrides['terminalBetaWeight'] = r(inputs.terminalBetaWeightOverride, 4);
  }
  if (inputs.terminalLeverageOverride !== null) overrides['terminalLeverage'] = r(inputs.terminalLeverageOverride, 4);
  payload['overrides'] = overrides;
  if (inputs.contextNotes.length > 0) payload['contextNotes'] = inputs.contextNotes;
  return payload;
}

function outputPayload(result: ValuationResult): JsonMap {
  const payload: JsonMap = {
    status: 'ok',
    ticker: result.ticker.value,
    model: modelDiagnostic(result.model),
    fairValue: r(result.fairValue.reais),
    safetyPrice: r(result.safetyPrice.reais),
    marketPrice: r(result.marketPrice.reais),
    upside: r(result.upside, 6),
    discountRate: r(result.discountRate, 6),
    marginOfSafety: r(result.marginOfSafety, 4),
    isUndervalued: result.isUndervalued,
    scenarioMode: result.mode.name,
  };
  if (result.discreteScenarios !== null) {
    const discrete: JsonMap = {};
    for (const [band, value] of result.discreteScenarios) discrete[band.name] = r(value.reais);
    payload['discreteScenarios'] = discrete;
  }
  const dist = result.distribution;
  if (dist !== null && !dist.isEmpty) {
    payload['distribution'] = {
      samples: dist.sortedValues.length,
      p5: r(dist.p5),
      median: r(dist.median),
      p95: r(dist.p95),
      mean: r(dist.mean),
      probabilityAboveMarket: r(dist.probabilityAbove(result.marketPrice.reais), 4),
    };
  }
  // **O diagnóstico inteiro, e não cinco campos** (item D4).
  const d = result.diagnostics;
  if (d !== null) {
    const diagnostics: JsonMap = {
      terminalShare: r(d.terminalShare, 4),
      equityShare: r(d.equityShare, 4),
      baseFactor: r(d.baseFactor, 4),
      growthIdentified: d.growthIdentified,
      moatApplied: d.moatApplied,
      caveats: d.caveats.map((c) => c.key),
      terminalRetainedSpread: r(d.terminalRetainedSpread, 6),
      growthRate: r(d.growthRate, 6),
      terminalReturnOnCapital: d.terminalReturnOnCapital === null ? null : r(d.terminalReturnOnCapital, 6),
      firmTaxRate: d.firmTaxRate === null ? null : r(d.firmTaxRate, 6),
      returnOnCapital: r(d.returnOnCapital, 6),
      terminalDiscountRate: r(d.terminalDiscountRate, 6),
      terminalCostOfEquity: d.terminalCostOfEquity === null ? null : r(d.terminalCostOfEquity, 6),
      costOfEquity: r(d.costOfEquity, 6),
      terminalExcessShare: d.terminalExcessShare === null ? null : r(d.terminalExcessShare, 4),
      impliedTerminalReturn: d.impliedTerminalReturn === null ? null : r(d.impliedTerminalReturn, 6),
      terminalEquityShare: d.terminalEquityShare === null ? null : r(d.terminalEquityShare, 4),
    };
    if (d.postStatementCapital !== null) diagnostics['postStatementCapital'] = r(d.postStatementCapital);
    diagnostics['growthPath'] = d.growthPath.map((g) => r(g, 6));
    diagnostics['retentionPath'] = d.retentionPath.map((b) => r(b, 6));
    payload['diagnostics'] = diagnostics;
  }
  // O insumo da faixa calibrada, que a tela monta com ele (decisão 100).
  payload['priceVolatility'] = result.priceVolatility === null ? null : r(result.priceVolatility, 6);
  const t = result.triangulation;
  if (t !== null) {
    payload['triangulation'] = {
      asOf: fmtDate(t.asOf),
      consolidated: t.consolidated === null ? null : r(t.consolidated),
      divergence: t.divergence === null ? null : r(t.divergence, 4),
      readings: t.readings.map((reading) => {
        const row: JsonMap = {
          kind: reading.kind.key,
          fairValuePerShare: reading.fairValuePerShare === null ? null : r(reading.fairValuePerShare),
          refusal: reading.refusal?.key ?? null,
        };
        if (reading.peer !== null) {
          row['peer'] = { median: r(reading.peer.median, 4), peers: reading.peer.peers, group: reading.peer.group };
        }
        return row;
      }),
    };
  }
  payload['warnings'] = result.warnings;
  return payload;
}

function auditUnitRatio(
  audit: AuditTransaction | null,
  inputs: ValuationInputs,
  latest: FundamentalsSnapshot,
  sharesPerQuote: number,
  args: { measured: number; declared: number | null },
): void {
  if (audit === null) return;
  const { measured, declared } = args;
  const shares = latest.sharesOutstanding;
  const cap = latest.marketCap;
  const raw = shares !== null && cap !== null && cap > 0 ? (shares * inputs.marketPrice) / cap : null;

  const steps: string[] = [];
  if (raw === null) {
    steps.push(
      'Passo 1: quantidade de ações ou valor de mercado ausentes; a razão ' + 'medida cai na convenção de ação comum (u = 1).',
    );
  } else {
    steps.push(
      `Passo 1: razão medida → ${str(r(shares!, 0))} × ` +
        `${str(r(inputs.marketPrice))} ÷ ${str(r(cap!))} = ${str(r(raw, 4))}`,
    );
    steps.push(
      'Passo 2: arredondamento e teste de plausibilidade (1 ≤ u ≤ ' +
        `${str(r(MAX_SHARES_PER_UNIT, 0))}, desvio relativo ≤ ` +
        `${str(r(UNIT_RATIO_TOLERANCE * 100, 0))}%) → u medida = ` +
        `${str(r(measured, 0))}`,
    );
  }
  if (declared !== null) {
    steps.push(
      'Passo 3: a composição declarada no formulário cadastral da CVM diz ' +
        `${declared} ${declared === 1 ? 'ação' : 'ações'} por unit, e é ` +
        'ela que vale; a medida fica como conferência (item B16)',
    );
  } else {
    steps.push(
      'Passo 3: sem composição declarada para este papel; vale a razão ' + 'medida, e a avaliação declara que ela foi inferida',
    );
  }

  audit.step({
    formulaName: 'Razão da unidade negociada',
    latex:
      declared !== null
        ? String.raw`u = u_{declarada} \quad ; \quad ` +
          String.raw`u_{medida} = \mathrm{round}\!\left(` +
          String.raw`\frac{N_{ações} \cdot P_{mkt}}{VM}\right)`
        : String.raw`u = \mathrm{round}\!\left(\frac{N_{ações} \cdot P_{mkt}}{VM}\right)`,
    variables: {
      'N_ações': shares === null ? null : r(shares, 0),
      'P_mkt (R$)': r(inputs.marketPrice),
      'VM (R$)': cap === null ? null : r(cap),
      u_declarada: declared,
      u_medida: r(measured, 0),
    },
    steps,
    result: sharesPerQuote,
    unit: 'ações por papel negociado',
  });
}

function auditQuotedShares(
  audit: AuditTransaction | null,
  latest: FundamentalsSnapshot,
  marketPrice: number,
  divisor: QuotedShares,
): void {
  if (audit === null) return;
  const marketValue = latest.marketCap;
  const band = str(FundamentalsSnapshot.reconciliationBand);
  const steps = [
    'Passo 1: contagem implícita no valor de mercado → ' +
      `${marketValue === null ? 'valor de mercado ausente' : `${str(r(marketValue))} ÷ ${str(r(marketPrice))} = ${str(r(divisor.fromMarketCap ?? 0, 0))}`}`,
    'Passo 2: contagem conciliada pelas demonstrações, na unidade ' +
      `negociada → ${str(r(divisor.fromStatements ?? 0, 0))}`,
    `Passo 3: as duas ${divisor.diverge ? `divergem além da banda de ${band}x; adotada a maior, que é o sentido conservador do erro` : `concordam dentro da banda de ${band}x; adotada a do mercado`} → ` +
      `${quotedSharesSourceDiagnostic(divisor.source)}`,
  ];
  if (divisor.fromRegistry !== null) {
    steps.push(
      `Passo 4: registro oficial da B3 de ${fmtDate(divisor.registryAsOf!)} → ` +
        `${divisor.source === QuotedSharesSource.official ? 'adotado; ele arbitra a divergência da fonte' : 'recusado; antigo demais e sem concordar com a fonte'}`,
    );
  }
  audit.step({
    formulaName: 'Contagem de papéis da ponte',
    latex:
      String.raw`N_{ponte} = \max\!\left(\frac{VM}{P_{mkt}},\; ` +
      String.raw`\frac{N_{conciliado}}{u}\right)` +
      String.raw`\;\;\text{na divergência};\;\; \frac{VM}{P_{mkt}}\;\;\text{fora dela}`,
    variables: {
      'VM (R$)': marketValue === null ? null : r(marketValue),
      'P_mkt (R$)': r(marketPrice),
      'N pelo mercado': divisor.fromMarketCap === null ? null : r(divisor.fromMarketCap, 0),
      'N pelas demonstrações': divisor.fromStatements === null ? null : r(divisor.fromStatements, 0),
      'divergência (x)': divisor.divergence === null ? null : r(divisor.divergence, 3),
      'N oficial da B3, líquido de tesouraria': divisor.fromRegistry === null ? null : r(divisor.fromRegistry, 0),
    },
    steps,
    result: r(divisor.count, 0),
    unit: 'papéis na unidade negociada',
  });
}

/** De onde veio o prêmio de mercado, em texto (decisão 142). */
function premiumOrigin(capm: CapmInputs): string {
  if (capm.premiumSource === MarketPremiumSource.impliedNormalized) {
    return (
      `${pct(capm.marketPremium)}, a média de dez anos do prêmio implícito ` +
      'no preço da bolsa: o retorno que o valor de mercado das listadas ' +
      'embute, dado o dinheiro que elas distribuem, menos o prefixado de ' +
      'dez anos (decisão 142)'
    );
  }
  if (capm.premiumSource === MarketPremiumSource.parameterized) {
    return (
      `${pct(capm.marketPremium)}, o prêmio parametrizado: a série do ` +
      'prêmio implícito não chegou a esta avaliação, e o recuo é o ' +
      'parâmetro anterior à decisão 142'
    );
  }
  return `${pct(capm.marketPremium)}, a média histórica do índice na janela ` + 'declarada';
}

function auditCapm(
  audit: AuditTransaction | null,
  capm: CapmInputs,
  dividendsInBeta: number,
  options: { withCurve?: boolean } = {},
): void {
  if (audit === null) return;
  const withCurve = options.withCurve ?? false;
  const risk = capm.beta * capm.marketPremium;
  const steps = [
    `Passo 0: o prêmio de mercado → ${premiumOrigin(capm)}`,
    `Passo 1: prêmio ajustado ao risco sistemático → ${str(r(capm.beta, 4))} × ` +
      `${pct(capm.marketPremium)} = ${pct(risk)}`,
    `Passo 2: soma à taxa livre de risco → ${pct(capm.riskFreeRate)} + ` +
      `${pct(risk)} = ${pct(capm.costOfEquity)}`,
  ];
  if (withCurve) {
    steps.push(
      'Passo 3: este é o K_e sobre o CDI de hoje — o do WACC do dia e o do ' +
        'retorno esperado da tela de metas. O desconto de cada ano usa a ' +
        'taxa livre de risco daquele ano, da curva do Tesouro, e a ' +
        'alavancagem que a avaliação produz: ver a estrutura a termo e o ' +
        'desconto do período explícito.',
    );
  }
  audit.step({
    formulaName: 'Custo do capital próprio (CAPM)',
    latex: String.raw`K_e = R_f + \beta \cdot (R_m - R_f)`,
    variables: {
      'R_f (% a.a.)': r(capm.riskFreeRate * 100),
      beta: r(capm.beta, 4),
      'R_m - R_f (% a.a.)': r(capm.marketPremium * 100),
      'origem do prêmio': capm.premiumSource.name,
      'origem do beta': capm.betaSource.name,
      'retorno do beta': dividendsInBeta > 0 ? `total, ${dividendsInBeta} proventos reinvestidos` : 'de preço',
    },
    steps,
    result: r(capm.costOfEquity * 100),
    unit: '% a.a.',
  });
}

function auditWacc(audit: AuditTransaction | null, coc: CostOfCapital): void {
  if (audit === null) return;
  const kd = coc.effectiveCostOfDebt;
  const afterTax = kd * (1 - coc.effectiveTaxShield);
  const equityLeg = coc.equityShare * coc.costOfEquity;
  // **A perna do financiamento se abre em duas quando o caixa é conhecido.**
  const wGross = coc.grossDebtShare;
  const wCash = coc.cashShare;
  const separates = wGross !== null && wCash !== null;
  const income = coc.afterTaxCashYield;
  const debtLeg = separates ? wGross * afterTax - wCash * income : coc.debtShare * afterTax;
  // **O Passo 3 diz a regra que a conta usa** (item B25).
  const leverageSpreadValue = CostOfCapital.leverageSpread(coc.netDebtToEbitda);
  const reference = coc.creditReferenceRate ?? coc.capm.riskFreeRate;
  const observed = coc.costOfDebt;
  const expenseIsInformative =
    observed !== null && observed >= reference && observed <= reference + CostOfCapital.maxCreditSpread;
  const coverageSpreadValue = CostOfCapital.coverageSpread(coc.interestCoverage);
  const step3 = !coc.hasContractedDebt
    ? 'Passo 3: sem dívida contratada não há prêmio de crédito → K_d = R_f ' + `= ${pct(kd)}`
    : 'Passo 3: K_d = R_f + prêmio sintético → prêmio pela alavancagem ' +
      `(${coc.netDebtToEbitda === null ? '—' : str(r(coc.netDebtToEbitda, 2))}× ` +
      `dívida líquida ÷ EBITDA) = ${pct(leverageSpreadValue)}; ` +
      `${
        observed === null
          ? 'a despesa financeira não está publicada, e a ' + 'cobertura sai da conta'
          : expenseIsInformative
            ? 'a despesa observada ' +
              `(${pct(observed)} da dívida) está na banda, e a cobertura ` +
              `fala → prêmio pela cobertura = ${pct(coverageSpreadValue)}, vale o ` +
              'maior'
            : `a despesa observada (${pct(observed)} da dívida) ` +
              'está fora da banda e mede outra coisa, e a cobertura sai da ' +
              'conta'
      } → ` +
      `${pct(coc.capm.riskFreeRate)} + ` +
      `${pct(kd - coc.capm.riskFreeRate)} = ${pct(kd)}. O observado ` +
      'não entra na taxa';

  const variables: JsonMap = {
    'E (R$)': r(coc.equityValue),
    'D líquida (R$)': r(coc.debtValue),
  };
  if (separates) variables['D bruta (R$)'] = r(coc.debtValue + coc.cashValue!);
  if (separates) variables['C — caixa (R$)'] = r(coc.cashValue!);
  variables['K_e (% a.a.)'] = r(coc.costOfEquity * 100);
  variables['K_d (% a.a.)'] = r(kd * 100);
  if (separates) variables['R_f (% a.a.)'] = r(coc.capm.riskFreeRate * 100);
  variables['t (%)'] = r(coc.effectiveTaxShield * 100);

  const steps = [
    `Passo 1: participação do capital próprio → ${str(r(coc.equityValue))} ÷ ` +
      `${str(r(coc.totalCapital))} = ${str(r(coc.equityShare, 4))}`,
  ];
  if (separates) {
    steps.push(
      'Passo 2: participação da dívida bruta → ' +
        `${str(r(coc.debtValue + coc.cashValue!))} ÷ ` +
        `${str(r(coc.totalCapital))} = ${str(r(wGross, 4))}; e do caixa → ` +
        `${str(r(coc.cashValue!))} ÷ ${str(r(coc.totalCapital))} = ` +
        `${str(r(wCash, 4))}. A diferença das duas é a participação da ` +
        `dívida líquida, ${str(r(coc.debtShare, 4))} — o que a separação ` +
        'muda é a **taxa** de cada metade, e não o peso',
    );
  } else {
    steps.push(
      'Passo 2: participação do capital de terceiros → ' +
        `${str(r(coc.debtValue))} ÷ ${str(r(coc.totalCapital))} = ` +
        `${str(r(coc.debtShare, 4))}`,
    );
  }
  steps.push(step3);
  steps.push(
    `Passo 4: benefício fiscal da dívida → ${pct(kd)} × (1 − ` +
      `${str(r(coc.effectiveTaxShield, 4))}) = ${pct(afterTax)}`,
  );
  if (separates) {
    steps.push(
      'Passo 5: o caixa rende a taxa livre de risco, tributada → ' +
        `${pct(coc.capm.riskFreeRate)} × (1 − ${str(r(coc.taxRate, 4))}) = ` +
        `${pct(income)}. Soma ponderada → ` +
        `${str(r(coc.equityShare, 4))} × ${pct(coc.costOfEquity)} + ` +
        `${str(r(wGross, 4))} × ${pct(afterTax)} − ${str(r(wCash, 4))} × ` +
        `${pct(income)} = ${pct(equityLeg)} + ${pct(debtLeg)} = ` +
        `${pct(coc.rawWacc)}`,
    );
  } else {
    steps.push(
      `Passo 5: soma ponderada → ${str(r(coc.equityShare, 4))} × ` +
        `${pct(coc.costOfEquity)} + ${str(r(coc.debtShare, 4))} × ` +
        `${pct(afterTax)} = ${pct(equityLeg)} + ${pct(debtLeg)} = ` +
        `${pct(coc.rawWacc)}`,
    );
  }
  if (coc.waccWasFloored) {
    steps.push('Passo 6: WACC abaixo da taxa livre de risco; adotado o piso de ' + `${pct(coc.capm.riskFreeRate)}`);
  } else {
    steps.push('Passo 6: WACC acima da taxa livre de risco; nenhum piso aplicado');
  }

  audit.step({
    formulaName: 'Custo médio ponderado de capital (WACC)',
    latex: separates
      ? String.raw`WACC = \frac{E}{E+D_{liq}}\,K_e + ` +
        String.raw`\frac{D_{bruta}}{E+D_{liq}}\,K_d\,(1 - t) - ` +
        String.raw`\frac{C}{E+D_{liq}}\,R_f\,(1 - \tau)`
      : String.raw`WACC = \frac{E}{E+D_{liq}}\,K_e + ` + String.raw`\frac{D_{liq}}{E+D_{liq}}\,K_d\,(1 - t)`,
    variables,
    steps,
    result: r(coc.wacc * 100),
    unit: '% a.a.',
  });
}

/** Registra as três guardas da Saída 1 e o veredito sobre a base. */
function auditBaseGuards(
  audit: AuditTransaction | null,
  currentReturn: number | null,
  cycleReturn: number | null,
  trend: TrendVerdict | null,
  phi: number | null,
  deviates: boolean,
  normalizes: boolean,
  factor: number,
  series: CapitalSeries,
  args: {
    cyclePrecedence: boolean;
    rawFactor: number;
    saturated: boolean;
    operationalDecline: number | null;
    healthCapped: boolean;
    healthExempt: boolean;
    normalization: BaseNormalization;
  },
): void {
  if (audit === null) return;
  const { cyclePrecedence, rawFactor, saturated, operationalDecline, healthCapped, healthExempt, normalization } = args;
  const trendText =
    trend === null
      ? 'não avaliável'
      : trend.dominates
        ? cyclePrecedence
          ? 'domina a reversão, mas o setor é cíclico: a Guarda 3 tem precedência'
          : 'domina a reversão, base mantida'
        : trend.isSignificant
          ? 'significante, mas a reversão é maior'
          : 'sem tendência';
  const phiText =
    phi === null
      ? 'não avaliável'
      : phi <= ValuationParameters.maxExternalCapital
        ? 'expansão orgânica, base comparável'
        : `capital externo de ${str(r(phi, 2))}x a base inicial, base inorgânica`;
  const steps = [
    `Guarda 1 — tendência: ${trendText}`,
    `Guarda 2 — comparabilidade (declara, não barra): ${phiText}`,
    `Guarda 3 — desvio do ciclo: ${deviates ? 'o exercício destoa' : 'dentro da banda e do desvio robusto'}`,
    normalizes
      ? `Base normalizada por ${toStringAsFixed(factor, 2)}x ` +
        `(${factor > 1 ? 'para cima' : factor < 1 ? 'para baixo' : 'sem mudança'}): ` +
        'o lucro publicado vezes o fator, já no ano zero; o que converge ' +
        'ao longo da projeção é o retorno sobre o capital, até o custo ' +
        'do capital'
      : 'Base mantida como observada',
  ];
  if (healthCapped) {
    steps.push(
      'Saúde operacional: queda de ' +
        `${operationalDecline === null ? 'n/d' : pct(operationalDecline)} ` +
        'no triênio; o teto do fator cai para 1,00x e a base não é ' +
        'normalizada para cima',
    );
  }
  if (healthExempt) {
    steps.push(
      'Saúde operacional: queda de ' +
        `${operationalDecline === null ? 'n/d' : pct(operationalDecline)} ` +
        'no triênio, mas o setor é cíclico — isento da trava na Porta 2a. ' +
        'A vantagem residual não tem trava de saúde (decisão 36; item B39)',
    );
  }
  if (saturated) {
    steps.push(
      `Saturação: o fator bruto de ${toStringAsFixed(rawFactor, 2)}x saiu da ` +
        `banda de [${str(ValuationParameters.baseFactorFloor)}, ` +
        `${str(ValuationParameters.baseFactorCeiling)}] e foi confinado a ` +
        `${toStringAsFixed(factor, 2)}x`,
    );
  }
  audit.step({
    sample: returnSample(series, cycleReturn, currentReturn, normalizes),
    formulaName: 'Base do fluxo: normalização pelo ciclo',
    explanation: whyTheBase(normalization),
    latex: String.raw`fluxo_0 = NOPAT_{atual} \cdot \frac{r_{ciclo}}{r_{atual}}`,
    variables: {
      'retorno atual (% a.a.)': r((currentReturn ?? 0) * 100),
      'mediana do ciclo (% a.a.)': r((cycleReturn ?? 0) * 100),
      'inclinação da tendência (p.p./ano)': trend === null ? 'n/d' : r(trend.slope * 100, 2),
      't de Newey-West': trend === null ? 'n/d' : r(trend.tStatistic, 2),
      'capital externo / base (Φ)': phi === null ? 'n/d' : r(phi, 2),
      'guarda 1 — tendência': trend === null ? 'não avaliável' : trend.dominates ? 'domina' : 'não domina',
      'guarda 3 — desvio do ciclo': deviates ? 'destoa' : 'dentro da banda e do desvio robusto',
      'precedência do ciclo (setor cíclico)': cyclePrecedence,
      'fator bruto': r(rawFactor, 3),
      'fator saturado': saturated,
      'queda no triênio (%)': operationalDecline === null ? null : r(operationalDecline * 100),
      'teto travado pela saúde': healthCapped,
      'isento da trava por setor cíclico': healthExempt,
      'resultado da normalização': normalization.outcome.key,
      'razão último ÷ típico': normalization.ratio === null ? 'n/d' : r(normalization.ratio, 3),
      'desvios robustos': normalization.robustZ === null ? 'n/d' : r(normalization.robustZ, 2),
    },
    steps,
    result: r(factor, 3),
    unit: 'fator sobre o lucro observado',
  });
}

/**
 * **Por que a base foi normalizada, ou não, e em que direção**, em linguagem
 * corrente — a seção "por quê" do passo da base no rastro.
 */
function whyTheBase(n: BaseNormalization): string[] {
  const returnRate = n.lane === ValuationLane.firm ? 'retorno sobre o capital investido' : 'retorno sobre o patrimônio';
  const years = n.windowYears;
  const window = years === null ? '' : `, de ${years.first} a ${years.last}`;
  const current = n.latestReturn;
  const cycle = n.cycleReturn;
  const year = n.latestYear === null ? 'null' : String(n.latestYear);
  const f = toStringAsFixed(n.factor, 2);
  const pctOrNa = (v: number | null): string => (v === null ? 'n/d' : pct(v));
  const rows: string[] = [
    'Por que normalizar: um ano só pode ter sido um pico ou um vale, e o ' +
      'preço justo é proporcional ao lucro de partida. O motor compara o ' +
      `${returnRate} do último exercício com o retorno típico da empresa — a ` +
      `mediana dos ${n.cycleWindow.length} exercícios anteriores${window} — e ` +
      'só parte de outro lucro quando os dois destoam.',
  ];
  const outcome = n.outcome;
  if (outcome === BaseNormalizationOutcome.upward) {
    rows.push(
      `Para cima: em ${year} a empresa rendeu ${pctOrNa(current)}, abaixo do típico ` +
        `de ${pctOrNa(cycle)}. O motor lê o último ano como um vale e parte do ` +
        'lucro que a empresa de hoje teria rendendo o típico: fator de ' +
        `${f}x sobre o lucro publicado.`,
    );
  } else if (outcome === BaseNormalizationOutcome.downward) {
    rows.push(
      `Para baixo: em ${year} a empresa rendeu ${pctOrNa(current)}, acima do típico ` +
        `de ${pctOrNa(cycle)}. O motor lê o último ano como um pico e parte do ` +
        'lucro que a empresa de hoje teria rendendo o típico: fator de ' +
        `${f}x sobre o lucro publicado.`,
    );
  } else if (outcome === BaseNormalizationOutcome.withinNormal) {
    rows.push(
      `Sem normalização: em ${year} a empresa rendeu ${pctOrNa(current)}, contra o ` +
        `típico de ${pctOrNa(cycle)} — dentro do normal dela. A base é o lucro ` +
        'publicado.',
    );
  } else if (outcome === BaseNormalizationOutcome.trend) {
    rows.push(
      `Sem normalização: ${pctOrNa(current)} em ${year} destoa do típico de ` +
        `${pctOrNa(cycle)}, mas o retorno vem mudando de patamar — ` +
        `${n.trendSlope === null ? 'n/d' : toStringAsFixed(n.trendSlope * 100, 2)} ` +
        'ponto ao ano, com t de ' +
        `${n.trendT === null ? 'n/d' : toStringAsFixed(n.trendT, 2)} contra ` +
        'o crítico de ' +
        `${n.trendCriticalT === null ? 'n/d' : toStringAsFixed(n.trendCriticalT, 2)} ` +
        `—, e em ${ValuationParameters.trendDriftWindow} anos essa tendência ` +
        'anda mais do que a volta ao típico. O último ano é lido como o novo ' +
        'normal, e a base é o lucro publicado.',
    );
  } else if (outcome === BaseNormalizationOutcome.healthLocked) {
    rows.push(
      `Sem normalização para cima: ${pctOrNa(current)} em ${year} está abaixo do ` +
        `típico de ${pctOrNa(cycle)}, e o fator seria de ` +
        `${toStringAsFixed(n.rawFactor, 2)}x, mas o lucro ou o EBITDA caiu ` +
        `${pctOrNa(n.operationalDecline)} em ` +
        `${ValuationParameters.operationalHealthWindow} anos, acima do ` +
        `limite de ${pct(ValuationParameters.maxOperationalDecline)}. Uma ` +
        'empresa que perdeu mais da metade do resultado mudou de patamar, e ' +
        'trazê-la de volta ao típico lhe daria um retorno que ela não vai ' +
        'repetir. A base é o lucro publicado; para baixo a normalização ' +
        'continuaria valendo.',
    );
  } else if (outcome === BaseNormalizationOutcome.rebuilt) {
    rows.push(
      'Base reconstruída: o último exercício deu prejuízo ' +
        `(${pctOrNa(current)}), e não há fator que corrija um lucro negativo. Com o ` +
        `típico positivo (${pctOrNa(cycle)}) e ` +
        `${pctOrNa(n.rebuiltPositiveShare)} da janela no lucro, o motor parte do ` +
        'típico sobre o capital de hoje — a afirmação de que a empresa volta ' +
        'ao que já foi (decisão 53).',
    );
  } else if (outcome === BaseNormalizationOutcome.noCycle) {
    rows.push(
      'Sem normalização: a série não tem um retorno típico positivo para ' + 'comparar, e a base é o lucro publicado.',
    );
  } else {
    rows.push(`Fator imposto de fora, por varredura de diagnóstico: ${f}x.`);
  }
  const ratio = n.ratio;
  const z = n.robustZ;
  const compared =
    ratio !== null &&
    z !== null &&
    outcome !== BaseNormalizationOutcome.rebuilt &&
    outcome !== BaseNormalizationOutcome.noCycle &&
    outcome !== BaseNormalizationOutcome.imposed;
  if (compared) {
    const byRatio = ratio < ValuationParameters.bandLow || ratio > ValuationParameters.bandHigh;
    const byDistance = z > ValuationParameters.robustZ;
    const reason = byRatio && byDistance ? 'pelos dois critérios' : byRatio ? 'pela razão' : 'pela distância';
    rows.push(
      'O teste de destoar: o último ano sobre o típico dá ' +
        `${toStringAsFixed(ratio, 2)} (o normal vai de ` +
        `${toStringAsFixed(ValuationParameters.bandLow, 2)} a ` +
        `${toStringAsFixed(ValuationParameters.bandHigh, 2)}), e a distância ` +
        `entre os dois é de ${toStringAsFixed(z, 2)} desvios típicos da janela ` +
        `(o normal vai até ${toStringAsFixed(ValuationParameters.robustZ, 1)}). ` +
        `${n.deviates ? `Destoou ${reason}.` : 'Não destoou.'}`,
    );
  }
  const published = n.publishedProfit;
  const base = n.baseProfit;
  if (
    (outcome === BaseNormalizationOutcome.upward || outcome === BaseNormalizationOutcome.downward) &&
    published !== null &&
    base !== null
  ) {
    rows.push(
      `A conta: R$ ${millions(published)} × ${f} = R$ ${millions(base)}` +
        `${n.saturated ? '' : ` — o mesmo que o capital com que a empresa começou ${year} rendendo o típico de ${pctOrNa(cycle)}`}.`,
    );
  }
  if (n.saturated) {
    rows.push(
      `Limite: a razão pedia um fator de ${toStringAsFixed(n.rawFactor, 2)}x, ` +
        `e ele foi limitado a ${f}x. O fator fica entre ` +
        `${toStringAsFixed(ValuationParameters.baseFactorFloor, 2)} e ` +
        `${toStringAsFixed(ValuationParameters.baseFactorCeiling, 2)} porque a ` +
        'normalização corrige um ano, e não inventa uma empresa.',
    );
  }
  if (
    n.cyclicalPrecedence &&
    n.trendDominates &&
    (outcome === BaseNormalizationOutcome.upward || outcome === BaseNormalizationOutcome.downward)
  ) {
    rows.push(
      'O retorno tem tendência, mas o setor é de commodity ou cíclico ' +
        'pesado: ali a perna de alta do ciclo tem cara de tendência, e o ciclo ' +
        'tem precedência (decisão 28).',
    );
  }
  if (n.healthExempt && n.factor > 1) {
    rows.push(
      `O lucro ou o EBITDA caiu ${pctOrNa(n.operationalDecline)} em ` +
        `${ValuationParameters.operationalHealthWindow} anos, mas em ` +
        'commodity a queda entre pico e vale é do preço do insumo, e não ' +
        'mudança de patamar: a trava que impede subir não se aplica ' +
        '(decisão 30).',
    );
  }
  return rows;
}

/**
 * Amostra de retorno que sustenta a mediana do ciclo. Marcação por **posição
 * na ordenação**, não por valor: exatamente um ponto numa amostra ímpar,
 * exatamente dois numa par.
 */
function returnSample(
  series: CapitalSeries,
  cycle: number | null,
  current: number | null,
  normalizes: boolean,
): TraceSample | null {
  const returns = series.returns;
  if (returns.length < 3) return null;
  const ini = returns.length - 1 - ValuationParameters.cycleWindow;
  const window = returns.slice(ini < 0 ? 0 : ini);

  const order: number[] = [];
  for (let i = 0; i < window.length; i++) order.push(i);
  order.sort((a, b) => compareNum(window[a]!.value, window[b]!.value));
  const mid = Math.floor(order.length / 2);
  const centralValues = order.length % 2 === 1 ? new Set([order[mid]!]) : new Set([order[mid - 1]!, order[mid]!]);

  const points: TraceSamplePoint[] = [];
  for (let i = 0; i < window.length; i++) {
    points.push(
      new TraceSamplePoint({
        label: `${window[i]!.year}`,
        value: r(window[i]!.value * 100),
        definesResult: centralValues.has(i) && i !== window.length - 1,
        isObserved: i === window.length - 1,
      }),
    );
  }
  return new TraceSample({
    title:
      series.lane === ValuationLane.firm
        ? 'Retorno sobre o capital investido, por exercício'
        : 'Retorno sobre o patrimônio, por exercício',
    points,
    summary: cycle === null ? null : r(cycle * 100),
    summaryLabel: 'mediana do ciclo',
    selected: normalizes && cycle !== null ? r(cycle * 100) : current === null ? null : r(current * 100),
    unit: '%',
  });
}

/** Registra a Saída 2: qual estimador decidiu a taxa, e por quê. */
function auditGrowthOutcome(
  audit: AuditTransaction | null,
  d: DispersionVerdict,
  origin: GrowthOrigin,
  g: number,
  retention: number | null,
  cycleReturn: number | null,
  inflation: number,
): void {
  if (audit === null) return;
  const requiredValue = cycleReturn !== null && cycleReturn > 0 ? inflation / cycleReturn : null;
  const steps = [`Passo 1: precisão e concordância → ${d.isIdentified ? 'crescimento identificável' : (d.failure ?? 'null')}`];
  if (!d.isIdentified) {
    steps.push(
      `Passo 2: a inflação de ${pct(inflation)} exigiria reter ` +
        `${requiredValue === null ? 'n/d' : pct(requiredValue)} contra ` +
        `${retention === null ? 'n/d' : pct(retention)} observados → ` +
        `${origin === GrowthOrigin.inflationAnchor ? 'âncora aceita' : 'âncora recusada'}`,
    );
  }
  steps.push(`Origem adotada: ${growthOriginDiagnostic(origin)}`);
  audit.step({
    formulaName: 'Crescimento explícito',
    latex: String.raw`g = \mathrm{mediana}\left(\frac{\Delta \text{base}_t}{\text{base}_{t-1}}\right)`,
    variables: {
      'g pela mediana (% a.a.)': r(d.medianGrowth * 100),
      'g pela regressão (% a.a.)': r(d.regressionGrowth * 100),
      'erro-padrão de ĝ (p.p.)': r(d.stdError * 100, 2),
      'discordância D': r(d.d, 2),
      'D crítico': r(d.criticalD, 2),
      'retenção observada (%)': retention === null ? 'n/d' : r(retention * 100),
    },
    steps,
    result: r(g * 100),
    unit: '% a.a.',
  });
}

function auditPerpetualGrowth(
  audit: AuditTransaction | null,
  explicitGrowth: number,
  economyGrowth: number,
  perpetual: number,
): void {
  if (audit === null) return;
  audit.step({
    formulaName: 'Crescimento na perpetuidade',
    latex: String.raw`g_\infty = \mathrm{clamp}\big(\min(g,\, g_{eco}),\, -5\%,\, g_{eco}\big)`,
    variables: {
      'g (% a.a.)': r(explicitGrowth * 100),
      'g_eco nominal (% a.a.)': r(economyGrowth * 100),
    },
    steps: [
      'Passo 1: menor entre o crescimento explícito e o da economia → ' +
        `min(${pct(explicitGrowth)}, ${pct(economyGrowth)}) = ` +
        `${pct(explicitGrowth < economyGrowth ? explicitGrowth : economyGrowth)}`,
      `Passo 2: confinado a [${pct(GrowthEstimator.floorRate)}, ` +
        `${pct(economyGrowth)}] — uma empresa não cresce acima da economia ` +
        'para sempre, nem encolhe mais de 5% ao ano para sempre (decisão ' +
        `56) → ${pct(perpetual)}. ` +
        'O teto é **nominal**: composto do crescimento real da atividade com ' +
        'a inflação observada, porque a taxa de desconto também é nominal, ' +
        'por sair do CDI. Não é o PIB real.',
    ],
    result: r(perpetual * 100),
    unit: '% a.a.',
  });
}

function auditDiscountTerm(
  audit: AuditTransaction | null,
  inputs: ValuationInputs,
  spot: number,
  terminal: number,
  path: readonly number[] | null,
): void {
  if (audit === null) return;
  const curve = inputs.riskFreeCurve;
  if (curve !== null && path !== null) {
    const fw = curve.annualForwards(inputs.projectionYears);
    const date = fmtDate(curve.referenceDate);
    audit.step({
      formulaName: 'Estrutura a termo da taxa de desconto',
      latex:
        String.raw`R_{f,t} = f_{t-1,\,t} \quad;\quad r_t = C(R_{f,t})` + String.raw`\quad;\quad r_\infty = C(f_{N,\,N+1})`,
      variables: {
        curva: `prefixados do Tesouro de ${date}`,
        'R_f do ano 1 (% a.a.)': r(fw[0]! * 100),
        'R_f do ano N (% a.a.)': r(fw[fw.length - 1]! * 100),
        'R_f da perpetuidade (% a.a.)': r(inputs.terminalRiskFreeRate * 100),
        'r_1 (% a.a.)': r(path[0]! * 100),
        'r_N (% a.a.)': r(path[path.length - 1]! * 100),
        'r_inf (% a.a.)': r(terminal * 100),
        'N (anos)': inputs.projectionYears,
      },
      steps: [
        'Passo 1: a taxa livre de risco de cada ano é o forward de um ano da ' +
          `curva dos prefixados de ${date} → ` +
          `${fw.map((rate, t) => `ano ${t + 1}: ${pct(rate)}`).join('; ')}`,
        'Passo 2: o custo de capital de cada ano é remontado sobre ela, com ' +
          'o beta, o prêmio e a estrutura de capital de hoje → ' +
          `${path.map((rate, t) => `ano ${t + 1}: ${pct(rate)}`).join('; ')}`,
        'Passo 3: a perpetuidade usa o forward depois do ano ' +
          `${inputs.projectionYears}, ${pct(inputs.terminalRiskFreeRate)}, ` +
          `e é descontada a ${pct(terminal)}`,
        'Passo 4: quando o custo de capital é resolvido ano a ano contra a ' +
          'alavancagem que a própria avaliação produz, este caminho é o ' +
          'ponto de partida, e o resolvido o substitui — ver o desconto do ' +
          'período explícito',
      ],
      result: r(terminal * 100),
      unit: '% a.a.',
    });
    return;
  }
  audit.step({
    formulaName: 'Estrutura a termo da taxa de desconto',
    latex: String.raw`r_t = r_{spot} - (r_{spot} - r_\infty)\cdot\frac{t-1}{N-1}`,
    variables: {
      'R_f corrente (% a.a.)': r(inputs.capm.riskFreeRate * 100),
      'R_f estrutural (% a.a.)': r(inputs.terminalRiskFreeRate * 100),
      'r_spot (% a.a.)': r(spot * 100),
      'r_inf (% a.a.)': r(terminal * 100),
      'N (anos)': inputs.projectionYears,
    },
    steps: [
      'Passo 1: sem curva de juros, o custo de capital do ano 1 usa a taxa ' + `livre de risco corrente → ${pct(spot)}`,
      'Passo 2: o custo de capital de equilíbrio repete beta, prêmio e ' +
        `estrutura de capital sobre a taxa estrutural → ${pct(terminal)}. ` +
        'Como Ke e WACC são afins na taxa livre de risco, decair o custo de ' +
        'capital equivale a decair a taxa e remontar o custo a cada ano',
      `Passo 3: a perpetuidade é descontada a ${pct(terminal)}, e o fator de ` +
        'desconto acumula as taxas ano a ano em vez de elevar uma só a t',
    ],
    result: r(terminal * 100),
    unit: '% a.a.',
  });
}

function auditMoat(audit: AuditTransaction | null, v: MoatVerdict): void {
  if (audit === null) return;
  const cycle = v.cycleReturn;
  const excess = v.spread;
  const phiValue = v.externalCapitalRatio;
  audit.step({
    formulaName: 'Vantagem competitiva residual na perpetuidade',
    latex: String.raw`ROIC_\infty = WACC_\infty + \varphi^{N}(ROIC_{ciclo} - WACC_\infty)`,
    variables: {
      'ROIC do ciclo (% a.a.)': cycle === null ? null : r(cycle * 100),
      'WACC de equilíbrio (% a.a.)': r(v.terminalDiscountRate * 100),
      'excedente do ciclo (p.p.)': excess === null ? null : r(excess * 100),
      Phi: phiValue === null ? null : r(phiValue, 2),
      exercícios: v.periods,
      'phi cru (AR(1))': v.rawPersistence === null ? null : r(v.rawPersistence, 4),
      'phi aplicado': v.persistence === null ? null : r(v.persistence, 4),
      'pares na regressão': v.persistencePoints,
      lambda: v.retainedFraction === null ? null : r(v.retainedFraction, 4),
      'condição que barrou': v.primaryBlock?.key ?? 'nenhuma',
      'condições que barraram': v.blocks.map((b) => b.key),
    },
    steps: [
      'Passo 1: crescimento orgânico? Phi = ' +
        `${phiValue === null ? 'não medido' : str(r(phiValue, 2))} ` +
        `${phiValue !== null && phiValue <= ValuationParameters.moatMaxExternalCapital ? '<=' : '>'} ` +
        `${str(ValuationParameters.moatMaxExternalCapital)}`,
      `Passo 2: histórico longo? ${v.periods} exercícios contra ` + `${ValuationParameters.moatMinPeriods} exigidos`,
      'Passo 3: excedente positivo? ROIC do ciclo de ' +
        `${cycle === null ? 'não medido' : pct(cycle)} contra WACC de ` +
        `equilíbrio de ${pct(v.terminalDiscountRate)}`,
      'Passo 4: persistência do excedente por AR(1) sobre ' +
        `${v.persistencePoints} pares — phi cru ` +
        `${v.rawPersistence === null ? 'não estimável' : str(r(v.rawPersistence, 4))}, ` +
        'confinado em ' +
        `${v.persistence === null ? '—' : str(r(v.persistence, 4))}; ` +
        'lambda = phi^N = ' +
        `${v.retainedFraction === null ? '—' : str(r(v.retainedFraction, 4))}`,
      v.isProven
        ? 'Passo 5: há excedente e ele persiste — ROIC_inf = ' +
          `${pct(v.terminalReturn!)}, e o valor terminal volta a depender ` +
          'de g_inf, que é o preço declarado da exceção'
        : `Passo 5: barrado por ${v.blocks.map((b) => moatBlockDiagnostic(b)).join(', ')} — ` +
          'vale o estado estacionário, ROIC_inf = WACC_inf, e o valor ' +
          'terminal não depende de g_inf',
    ],
    // O resultado é o retorno terminal **efetivamente adotado**.
    result: r((v.terminalReturn ?? v.terminalDiscountRate) * 100),
    unit: '% a.a.',
  });
}

function auditDcf(
  audit: AuditTransaction | null,
  args: {
    outcome: DcfOutcome;
    assumptions: DcfAssumptions;
    baseFlow: number;
    flowSymbol: string;
    perShareAlready?: boolean;
    capitalPerShare?: number;
  },
): void {
  if (audit === null) return;
  const { outcome, assumptions, baseFlow, flowSymbol } = args;
  const perShareAlready = args.perShareAlready ?? false;
  const capitalPerShare = args.capitalPerShare ?? 0;
  const rInf = outcome.terminalDiscountRateUsed ?? assumptions.terminalDiscountRate;
  const gInf = assumptions.perpetualGrowth;
  const n = outcome.projectedFlows.length;
  let sumPv = 0;
  for (const v of outcome.discountedFlows) sumPv = sumPv + v;
  const unit = perShareAlready ? 'R$ por papel' : 'R$';

  // **O rastro descreve a conta que foi feita** (item B35).
  let rates: readonly number[];
  if (outcome.discountRates !== null) {
    rates = outcome.discountRates;
  } else {
    const fallback: number[] = [];
    for (let t = 1; t <= n; t++) fallback.push(assumptions.discountRateAt(t));
    rates = fallback;
  }
  let factor = 1.0;
  const factors: number[] = [];
  for (const rate of rates) {
    factor *= 1 + rate;
    factors.push(factor);
  }
  const finalFactor = n === 0 ? 1.0 : factors[n - 1]!;

  // **A convenção de caixa entra na fórmula, não só na conta** (decisão 48).
  const midYear = assumptions.cashTiming === CashTiming.midYear;
  const midYearLift = midYear ? String.raw`\,\sqrt{1 + k_t}` : '';
  const pathOrigin =
    assumptions.discountRatePath !== null
      ? 'sai do caminho ano a ano — o resolvido contra a alavancagem, ou o ' +
        'montado sobre a curva do Tesouro (ver a estrutura a termo)'
      : 'decai em linha reta da corrente à de equilíbrio';

  // O lucro de cada ano, pela mesma recorrência de `DcfCalculator`.
  const profits: number[] = [];
  let profit = baseFlow;
  for (let t = 1; t <= n; t++) {
    profit *= 1 + assumptions.growthAt(t);
    profits.push(profit);
  }

  const firm = outcome.firmFlows;
  const debtServices = outcome.debtService;
  if (firm !== null && debtServices !== null) {
    const projectionSteps = [
      'Passo 0: o crescimento decai em linha reta até o perpétuo, e o ' +
        'retorno sobre o capital converge do observado ao WACC do ano, ' +
        `que ${pathOrigin}. A retenção b = g ÷ ROIC é o que a firma ` +
        'reinveste para crescer g; o resto é o fluxo livre. O WACC aqui ' +
        'não desconta nada: ele é o destino do retorno, e o desconto é ' +
        'do fluxo do acionista, no passo seguinte (decisão 102).',
    ];
    for (let t = 1; t <= n; t++) {
      projectionSteps.push(
        `Passo ${t}: ano ${t} → g = ${pct(assumptions.growthAt(t))}, ` +
          `ROIC = ${pct(assumptions.returnOnCapitalAt(t))}, ` +
          `retenção = ${pct(assumptions.retentionAt(t))}; NOPAT ` +
          `${str(r(profits[t - 1]!))} × (1 − retenção) → fluxo da firma ` +
          `${str(r(firm[t - 1]!))}`,
      );
    }
    audit.step({
      formulaName: 'Projeção do fluxo da firma (NOPAT)',
      latex:
        String.raw`FCFF_t = NOPAT_t\,(1 - b_t)\quad;\quad ` +
        String.raw`NOPAT_t = NOPAT_{t-1}(1 + g_t)\quad;\quad b_t = g_t / ROIC_t` +
        String.raw`\quad;\quad ROIC_t \to WACC_t`,
      variables: {
        NOPAT_0: r(baseFlow),
        'g_1 (% a.a.)': r(assumptions.growthAt(1) * 100),
        'g_N (% a.a.)': r(assumptions.growthAt(n) * 100),
        'ROIC_1 (% a.a.)': r(assumptions.returnOnCapitalAt(1) * 100),
        'WACC_1 (% a.a.)': r(assumptions.discountRateAt(1) * 100),
        'WACC_N (% a.a.)': r(assumptions.discountRateAt(n) * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps: projectionSteps,
      result: n === 0 ? 0.0 : firm[n - 1]!,
      unit: 'R$',
    });

    const discountSteps = [
      'Passo 0: o acionista recebe o fluxo da firma menos o serviço da ' +
        'dívida — o juro da dívida bruta depois do imposto, menos o que ' +
        'o caixa rende depois do imposto, menos a dívida nova que ' +
        'mantém a alavancagem crescendo a g. O resultado é descontado ao ' +
        'custo do capital próprio de cada ano, e não ao WACC.',
    ];
    if (midYear) {
      discountSteps.push(
        'Passo 0b: o caixa do exercício chega ao longo do ano, e não no ' +
          'último dia dele. Cada fluxo é levantado por raiz de (1 + K_e ' +
          'do ano) — a convenção de meio de ano da decisão 48.',
      );
    }
    for (let t = 1; t <= n; t++) {
      discountSteps.push(
        `Passo ${t}: ano ${t} → fluxo da firma ${str(r(firm[t - 1]!))} − serviço ` +
          `da dívida ${str(r(debtServices[t - 1]!))} = fluxo do acionista ` +
          `${str(r(outcome.projectedFlows[t - 1]!))}; K_e = ` +
          `${pct(rates[t - 1]!)}, fator acumulado ` +
          `${str(r(factors[t - 1]!, 6))}` +
          `${midYear ? `, levantamento ${str(r(assumptions.lift(rates[t - 1]!), 6))}` : ''}` +
          ` → valor presente ${str(r(outcome.discountedFlows[t - 1]!))}`,
      );
    }
    discountSteps.push(`Passo ${n + 1}: soma dos valores presentes do período explícito → ` + `${str(r(sumPv))}`);
    audit.step({
      formulaName: 'Fluxo do acionista e desconto ao K_e (período explícito)',
      latex:
        String.raw`FCFE_t = FCFF_t - S_t\quad;\quad ` +
        String.raw`S_t = D^b_{t-1} K_{d,t}(1-\tau) - C_{t-1} R_{f,t}(1-\tau) ` +
        String.raw`- D_{t-1}\,g_t\quad;\quad ` +
        `VP = \\sum_{t=1}^{N} \\frac{FCFE_t${midYearLift}}` +
        String.raw`{\prod_{s=1}^{t}(1 + k_s)},\; k_t = K_{e,t}`,
      variables: {
        'K_e,1 (% a.a.)': n === 0 ? null : r(rates[0]! * 100),
        'K_e,N (% a.a.)': n === 0 ? null : r(rates[rates.length - 1]! * 100),
        'τ (escudo fiscal)': r(ValuationParameters.statutoryTaxRate, 4),
        'N (anos)': assumptions.projectionYears,
      },
      steps: discountSteps,
      result: sumPv,
      unit: 'R$',
    });
  } else {
    const steps = [
      `Passo 0: a taxa de cada ano ${pathOrigin}. O fator de desconto ` +
        '**acumula** a taxa de cada ano em vez de elevar uma só a t, e o ' +
        'fluxo do ano é o lucro menos a retenção que financia o ' +
        'crescimento daquele mesmo ano.',
    ];
    if (midYear) {
      steps.push(
        'Passo 0b: o caixa do exercício chega ao longo do ano, e não no ' +
          'último dia dele. Cada fluxo é levantado por raiz de (1 + K_e ' +
          'do ano) — a convenção de meio de ano da decisão 48.',
      );
    }
    for (let t = 1; t <= n; t++) {
      steps.push(
        `Passo ${t}: ano ${t} → g = ${pct(assumptions.growthAt(t))}, ` +
          `retenção = ${pct(assumptions.retentionAt(t))}, ` +
          `K_e = ${pct(rates[t - 1]!)}; lucro ${str(r(profits[t - 1]!))} × ` +
          `(1 − retenção) = ${str(r(outcome.projectedFlows[t - 1]!))} ÷ fator ` +
          `acumulado ${str(r(factors[t - 1]!, 6))}` +
          `${midYear ? ` × levantamento ${str(r(assumptions.lift(rates[t - 1]!), 6))}` : ''}` +
          ` → valor presente ${str(r(outcome.discountedFlows[t - 1]!))}`,
      );
    }
    steps.push(`Passo ${n + 1}: soma dos valores presentes do período explícito → ` + `${str(r(sumPv))}`);
    audit.step({
      formulaName: `Projeção e desconto do período explícito (${flowSymbol})`,
      latex:
        'VP_{explícito} = \\sum_{t=1}^{N} ' +
        `\\frac{L_t\\,(1 - b_t)${midYearLift}}{\\prod_{s=1}^{t}(1 + k_s)}` +
        String.raw`\quad;\quad L_t = L_{t-1}(1 + g_t),\; b_t = g_t / ROIC_t,\; ` +
        String.raw`k_t = K_{e,t}`,
      variables: {
        F_0: r(baseFlow),
        'g_1 (% a.a.)': r(assumptions.growthAt(1) * 100),
        'g_N (% a.a.)': r(assumptions.growthAt(n) * 100),
        'K_e,1 (% a.a.)': n === 0 ? null : r(rates[0]! * 100),
        'K_e,N (% a.a.)': n === 0 ? null : r(rates[rates.length - 1]! * 100),
        'ROIC_1 (% a.a.)': r(assumptions.returnOnCapitalAt(1) * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps,
      result: sumPv,
      unit,
    });
  }

  // Três formas de terminal, e o rastro precisa dizer qual foi aplicada.
  const moat = assumptions.terminalReturnOnCapital;
  const neutral = moat === null && assumptions.neutralTerminalReturn;
  // **A concessão tem terminal próprio, e o rastro tem de dizê-lo** (decisão 88).
  const contract = neutral ? assumptions.contractYearsAfterHorizon : null;
  const reinvestment =
    moat !== null ? clamp(gInf / moat, 0.0, 0.95) : assumptions.retentionAt(assumptions.projectionYears);
  const rFirm = assumptions.terminalDiscountRate;
  const tvForm =
    contract !== null
      ? String.raw`VT = K_N + EVA_{N+1}\,` + String.raw`\frac{1 - (1+r_\infty)^{-M}}{r_\infty}`
      : neutral
        ? String.raw`VT = \frac{L_{N+1}}{r_\infty}`
        : String.raw`VT = \frac{L_{N+1}\,(1 - b_\infty)}{r_\infty - g_\infty}`;
  const formStep =
    contract !== null
      ? `o contrato acaba ${contract} ano(s) depois do horizonte — o capital ` +
        'volta e o excedente sobre ele dura só até lá, de modo que a ' +
        'perpetuidade não se aplica (decisão 88)'
      : neutral
        ? 'com RONIC_inf = r_inf — o **capital novo** sem valor — a ' +
          'álgebra colapsa e o crescimento perpétuo sai da ' +
          'perpetuidade: VT = L_(N+1) ÷ r_inf, sem spread'
        : `spread da perpetuidade → ${pct(rFirm)} − ${pct(gInf)} = ` +
          `${pct(rFirm - gInf)}; retenção perpétua = ` +
          `${pct(reinvestment)}`;
  const formName =
    contract !== null
      ? 'contrato com prazo: capital devolvido e excedente até o fim'
      : neutral
        ? 'retorno neutro, RONIC_inf = r_inf'
        : 'Gordon com reinvestimento';
  // **O que o retorno neutro não diz** (item B12).
  const excessStep = (rate: number): string | null =>
    contract === null && neutral && outcome.impliedTerminalReturn !== null
      ? 'o retorno neutro vale para o capital **novo**; o instalado ' +
        `rende ${pct(outcome.impliedTerminalReturn)} na ` +
        `perpetuidade, contra ${pct(rate)} de custo de capital. ` +
        'Reagrupando, VT = capital_N + EVA_(N+1) ÷ r_inf, e a segunda ' +
        `parcela vale ${str(r(outcome.discountedTerminalExcess ?? 0))} a ` +
        'valor presente — ' +
        `${outcome.impliedTerminalReturn < rate ? 'déficit' : 'excedente'} ` +
        'mantido para sempre'
      : null;
  const terminalLift = midYear ? `, levantado por ${str(r(assumptions.lift(rInf), 6))} de meio de ano` : '';

  const firmTv = outcome.firmTerminalValue;
  const fcffTerminal = outcome.terminalFirmFlow;
  const terminalDebtService = outcome.terminalDebtService;
  const fcfeTerminal = outcome.terminalEquityFlow;
  if (firmTv !== null && fcffTerminal !== null && terminalDebtService !== null && fcfeTerminal !== null) {
    // Sem contrato, a perpetuidade do acionista **é** o terminal que a conta produziu.
    const shareholderSpread = rInf - gInf;
    const perpetual =
      contract === null
        ? outcome.terminalValue
        : shareholderSpread > 0 && Number.isFinite(shareholderSpread)
          ? fcfeTerminal / shareholderSpread
          : null;
    const excess = excessStep(rFirm);
    const presentValueForm = midYear
      ? String.raw`VP = \frac{VT_{acionista}\,\sqrt{1 + K_{e,\infty}}}` + String.raw`{\prod_{s=1}^{N}(1+K_{e,s})}`
      : String.raw`VP = \frac{VT_{acionista}}{\prod_{s=1}^{N}(1+K_{e,s})}`;
    const steps = [
      'Passo 1: valor terminal da firma no ano ' +
        `${assumptions.projectionYears}, ao WACC de equilíbrio — ` +
        `${formStep} → ${str(r(firmTv))}`,
      'Passo 2: o fluxo da firma do ano N+1 que essa perpetuidade supõe ' +
        `${contract !== null ? '(a perpetuidade sem prazo, NOPAT_(N+1) ' + '÷ r_inf, e não o terminal do contrato) ' : ''}` +
        `→ × (${pct(rFirm)} − ${pct(gInf)}) = ${str(r(fcffTerminal))}`,
      'Passo 3: menos o serviço da dívida do ano N+1 → ' +
        `${str(r(fcffTerminal))} − ${str(r(terminalDebtService))} = fluxo do ` +
        `acionista ${str(r(fcfeTerminal))}`,
      'Passo 4: capitalizado ao K_e de equilíbrio menos o crescimento ' +
        `perpétuo → ${str(r(fcfeTerminal))} ÷ (${pct(rInf)} − ` +
        `${pct(gInf)}) = ${perpetual === null ? '—' : str(r(perpetual))}` +
        `${contract !== null ? '; truncado no contrato, com o capital ' + 'devolvido menos a dívida no fim → ' + `${str(r(outcome.terminalValue))}` : ''}`,
      'Passo 5: trazido a presente pelo fator acumulado do K_e ' +
        `${str(r(finalFactor, 6))}${terminalLift} → ` +
        `${str(r(outcome.discountedTerminalValue))}`,
      'Passo 6: participação do valor terminal no capital próprio → ' + `${pct(outcome.terminalShare)}`,
    ];
    if (excess !== null) steps.push(`Passo 7: ${excess}`);
    audit.step({
      formulaName: `Valor terminal (${formName}), convertido para o acionista`,
      latex:
        `${tvForm}` +
        String.raw`\quad;\quad FCFF_{N+1} = VT^{\infty}_{firma}\,(r_\infty - g_\infty)` +
        String.raw`\quad;\quad FCFE_{N+1} = FCFF_{N+1} - S_{N+1}` +
        String.raw`\quad;\quad VT_{acionista} = \frac{FCFE_{N+1}}` +
        String.raw`{K_{e,\infty} - g_\infty}` +
        `${contract !== null ? String.raw`\,(1 - q^M) + (K_N - D_N)\,q^M` : ''}` +
        String.raw`\quad;\quad ` +
        `${presentValueForm}`,
      variables: {
        NOPAT_N: n === 0 ? null : r(profits[n - 1]!),
        'g_inf (% a.a.)': r(gInf * 100),
        'r_inf = WACC de equilíbrio (% a.a.)': r(rFirm * 100),
        'K_e,inf (% a.a.)': r(rInf * 100),
        'ROIC_inf (% a.a.)': moat === null ? null : r(moat * 100),
        'ROIC implícito do instalado (% a.a.)':
          outcome.impliedTerminalReturn === null ? null : r(outcome.impliedTerminalReturn * 100),
        'N (anos)': assumptions.projectionYears,
        'M (anos de contrato além de N)': contract,
      },
      steps,
      result: outcome.discountedTerminalValue,
      unit: 'R$',
    });
    return;
  }

  const presentValueForm = midYear
    ? String.raw`VP(VT) = \frac{VT\,\sqrt{1 + r_\infty}}{\prod_{s=1}^{N}(1+k_s)}`
    : String.raw`VP(VT) = \frac{VT}{\prod_{s=1}^{N}(1+k_s)}`;
  const excess = excessStep(rInf);
  const terminalSteps = [
    `Passo 1: ${formStep}`,
    `Passo 2: valor terminal no ano ${assumptions.projectionYears} → ` + `${str(r(outcome.terminalValue))}`,
    'Passo 3: trazido a presente pelo fator acumulado ' +
      `${str(r(finalFactor, 6))}${terminalLift} → ` +
      `${str(r(outcome.discountedTerminalValue))}`,
    'Passo 4: participação do valor terminal no total → ' + `${pct(outcome.terminalShare)}`,
  ];
  if (excess !== null) terminalSteps.push(`Passo 5: ${excess}`);
  audit.step({
    formulaName: `Valor terminal (${formName})`,
    latex: `${tvForm}` + String.raw`\quad;\quad ` + `${presentValueForm}`,
    variables: {
      L_N: n === 0 ? null : r(profits[n - 1]!),
      'g_inf (% a.a.)': r(gInf * 100),
      'r_inf (% a.a.)': r(rInf * 100),
      'ROIC_inf (% a.a.)': moat === null ? null : r(moat * 100),
      'ROIC implícito do instalado (% a.a.)':
        outcome.impliedTerminalReturn === null ? null : r(outcome.impliedTerminalReturn * 100),
      'N (anos)': assumptions.projectionYears,
      'M (anos de contrato além de N)': contract,
    },
    steps: terminalSteps,
    result: outcome.discountedTerminalValue,
    unit,
  });

  if (perShareAlready) {
    const variables: JsonMap = {
      'VP_explícito (R$)': r(sumPv),
      'VP(VT) (R$)': r(outcome.discountedTerminalValue),
    };
    if (capitalPerShare > 0) variables['capital emitido depois do balanço, por papel (R$)'] = r(capitalPerShare);
    audit.step({
      formulaName: 'Preço justo por papel (DCF sobre o lucro)',
      latex: String.raw`P_0 = VP_{explícito} + VP(VT)`,
      variables,
      steps: [
        capitalPerShare > 0
          ? 'Passo único: soma das duas parcelas e do capital emitido depois do ' +
            `balanço (item B28) → ${str(r(sumPv))} + ` +
            `${str(r(outcome.discountedTerminalValue))} + ` +
            `${str(r(capitalPerShare))} = ${str(r(outcome.fairValuePerShare))}`
          : `Passo único: soma das duas parcelas → ${str(r(sumPv))} + ` +
            `${str(r(outcome.discountedTerminalValue))} = ` +
            `${str(r(outcome.fairValuePerShare))}`,
      ],
      result: outcome.fairValuePerShare,
      unit: 'R$ por papel',
    });
  }
}

/**
 * O capital próprio da via da firma, **como ele é calculado**: pelo fluxo do
 * acionista derivado do da firma, e não pela subtração `EV − D` (decisão 102).
 */
function auditEquityBridge(
  audit: AuditTransaction | null,
  args: {
    outcome: DcfOutcome;
    netDebt: number;
    minorityInterest: number;
    shares: number;
    resolved: boolean;
    withCurve?: boolean;
    subsequentCapital?: number;
  },
): void {
  if (audit === null) return;
  const { outcome, netDebt, minorityInterest, shares, resolved } = args;
  const withCurve = args.withCurve ?? false;
  const subsequentCapitalValue = args.subsequentCapital ?? 0;
  let explicitValue = 0;
  for (const v of outcome.discountedFlows) explicitValue = explicitValue + v;
  const terminal = outcome.discountedTerminalValue;
  const minorityValue = minorityInterest < 0 ? 0.0 : minorityInterest;
  // O capital emitido depois do balanço entra depois do fluxo (item B28).
  const capital = subsequentCapitalValue > 0 ? subsequentCapitalValue : 0.0;
  const fromBalanceSheet = outcome.equityValue - capital;
  const variables: JsonMap = {
    'VP do fluxo explícito do acionista (R$)': r(explicitValue),
    'VP do terminal do acionista (R$)': r(terminal),
    'minoritários M (R$)': r(minorityValue),
    'dívida líquida inicial D_0 (R$)': r(netDebt),
  };
  if (capital > 0) variables['capital emitido depois do balanço C (R$)'] = r(capital);
  variables['N_papéis'] = r(shares, 0);
  variables['desconto'] = resolved
    ? 'caminho de K_e resolvido pela realavancagem'
    : withCurve
      ? 'K_e do CAPM sobre o forward de cada ano da curva, com a ' + 'estrutura de capital de hoje'
      : 'K_e do CAPM, da taxa corrente à de equilíbrio';
  const steps = [
    `Passo 1: a dívida líquida de ${str(r(netDebt))} não é subtraída aqui — ` +
      'ela já saiu do fluxo, ano a ano, no serviço da dívida dos dois ' +
      'passos anteriores',
    `Passo 2: valor presente do fluxo explícito → ${str(r(explicitValue))}`,
    `Passo 3: valor presente do terminal do acionista → ${str(r(terminal))}`,
    `Passo 4: menos a parte dos não controladores → ${str(r(explicitValue))} + ` +
      `${str(r(terminal))} − ${str(r(minorityValue))} = ${str(r(fromBalanceSheet))}`,
  ];
  if (capital > 0) {
    steps.push(
      'Passo 4b: mais o capital emitido depois do balanço, que está na ' +
        'contagem e não no patrimônio publicado (item B28) → ' +
        `${str(r(fromBalanceSheet))} + ${str(r(capital))} = ${str(r(outcome.equityValue))}`,
    );
  }
  steps.push(
    'Passo 5: divisão pelo número de papéis negociados → ' +
      `${str(r(outcome.equityValue))} ÷ ${str(r(shares, 0))} = ` +
      `${str(r(outcome.fairValuePerShare))}`,
  );
  audit.step({
    formulaName: 'Capital próprio pelo fluxo do acionista derivado',
    latex:
      capital > 0
        ? String.raw`P_0 = \frac{VP_{explícito} + VP(VT_{acionista}) - M + C}` + String.raw`{N_{papéis}}`
        : String.raw`P_0 = \frac{VP_{explícito} + VP(VT_{acionista}) - M}` + String.raw`{N_{papéis}}`,
    variables,
    steps,
    result: outcome.fairValuePerShare,
    unit: 'R$ por papel',
  });
}

function auditVerdict(audit: AuditTransaction | null, result: ValuationResult): void {
  if (audit === null) return;
  const fair = result.fairValue.reais;
  const market = result.marketPrice.reais;
  audit.step({
    formulaName: 'Margem de segurança e potencial de valorização',
    latex: String.raw`P_{seg} = P_0\,(1 - s) \quad;\quad ` + String.raw`upside = \frac{P_0 - P_{mkt}}{P_{mkt}}`,
    variables: {
      'P_0 (R$)': r(fair),
      's (%)': r(result.marginOfSafety * 100),
      'P_mkt (R$)': r(market),
    },
    steps: [
      `Passo 1: preço justo com margem de segurança → ${str(r(fair))} × (1 − ` +
        `${str(r(result.marginOfSafety, 4))}) = ${str(r(result.safetyPrice.reais))}`,
      `Passo 2: potencial de valorização total → (${str(r(fair))} − ` +
        `${str(r(market))}) ÷ ${str(r(market))} = ${pct(result.upside)}`,
      'Passo 3: veredito → o preço de mercado ' +
        `${result.isUndervalued ? 'está abaixo' : 'não está abaixo'} do ` +
        'preço com margem de segurança',
    ],
    result: r(result.upside * 100),
    unit: '% (total, sem prazo)',
  });
}

// --------------------------------------------------------------- API pública --

/**
 * Roteia o ativo por portas e aplica a via correspondente (decisão 25):
 * **Porta 0** elegibilidade; **Porta 1** instituição financeira fora da via da
 * firma; **Porta 3** sustentação do lucro operacional; **Porta 2** base e
 * taxa de crescimento. A via aplicada **vai no resultado**, junto dos avisos.
 */
export const ValuationCascade = {
  /** Avalia usando o melhor modelo possível. **Síncrono e puro.** */
  evaluate,
  /** Quantas ações compõem a unit negociada, ou 1 para a ação comum. */
  quotedUnitRatio,
  /** A contagem de ações do exercício mais recente é coerente com a série? */
  shareBaseIsConsistent,
  /** Papéis na unidade negociada para a ponte por papel. */
  quotedShares,
  /** Anos até o fim do contrato de concessão, ou `null`. */
  contractYears,
  minorityWeightMateriality: MINORITY_WEIGHT_MATERIALITY,
  betaWindowYears: BETA_WINDOW_YEARS,
  minimumBetaWindowShare: MINIMUM_BETA_WINDOW_SHARE,
  maxSharesPerUnit: MAX_SHARES_PER_UNIT,
  unitRatioTolerance: UNIT_RATIO_TOLERANCE,
  officialSharesMaxAgeDays: OFFICIAL_SHARES_MAX_AGE_DAYS,
} as const;
