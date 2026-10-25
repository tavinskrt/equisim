/**
 * O valuation confirmado: as premissas do usuário e o que a conta deu com
 * elas, guardados juntos (decisão 150).
 */

import {
  AuditEvent,
  AuditJson,
  CalculationTrace,
  TraceSample,
  TraceSamplePoint,
  type JsonMap,
} from '../../audit/calculation-trace';
import { ComputationFailure, InvalidInput } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { DateTime } from '../../lang/date-time';
import { interpolateJson, isJsonObject } from '../../lang/json';
import { FormatException, round, str } from '../../lang/num';
import { Money } from '../../value-objects/money';
import { Ticker } from '../../value-objects/ticker';
import { ValuationLane } from './capital-base';
import {
  ManualField,
  ManualGroup,
  ManualGrowthPath,
  ManualNotice,
  ManualNoticeKind,
  ManualOutcome,
  ManualPremises,
  ManualRatePath,
  ManualReinvestment,
  ManualStep,
  ManualTerminal,
  ManualYear,
  type ManualValuation,
} from './manual-valuation';

/**
 * As chaves gravadas de cada enum do registro. **São dado, e não código**:
 * mudar uma delas torna ilegível o que já foi salvo com a antiga.
 */
const Wire = {
  lane: new Map<ValuationLane, string>([
    [ValuationLane.firm, 'firma'],
    [ValuationLane.shareholder, 'acionista'],
  ]),
  field: new Map<ManualField, string>([
    [ManualField.baseProfit, 'lucroDePartida'],
    [ManualField.growth, 'crescimento'],
    [ManualField.discountRate, 'taxaDeDesconto'],
    [ManualField.perpetualGrowth, 'crescimentoPerpetuo'],
    [ManualField.returnOnCapital, 'retornoSobreOCapital'],
    [ManualField.retention, 'parcelaReinvestida'],
    [ManualField.terminalReturn, 'retornoDoCapitalNovo'],
  ]),
  growthPath: new Map<ManualGrowthPath, string>([
    [ManualGrowthPath.decays, 'caiAtePerpetuidade'],
    [ManualGrowthPath.constant, 'constante'],
  ]),
  ratePath: new Map<ManualRatePath, string>([
    [ManualRatePath.engine, 'curvaDoMotor'],
    [ManualRatePath.constant, 'constante'],
  ]),
  reinvestment: new Map<ManualReinvestment, string>([
    [ManualReinvestment.byReturn, 'peloRetorno'],
    [ManualReinvestment.fixedFraction, 'parcelaFixa'],
  ]),
  terminal: new Map<ManualTerminal, string>([
    [ManualTerminal.neutral, 'neutra'],
    [ManualTerminal.advantage, 'vantagem'],
    [ManualTerminal.fixedFraction, 'parcelaFixa'],
    [ManualTerminal.contract, 'contrato'],
  ]),
  notice: new Map<ManualNoticeKind, string>([
    [ManualNoticeKind.confinedGrowth, 'crescimentoConfinado'],
    [ManualNoticeKind.negativeFlow, 'fluxoNegativo'],
    [ManualNoticeKind.perpetualConcession, 'concessaoPerpetua'],
    [ManualNoticeKind.neutralPerpetuity, 'perpetuidadeNeutra'],
  ]),
  group: new Map<ManualGroup, string>([
    [ManualGroup.profit, 'lucro'],
    [ManualGroup.growth, 'crescimento'],
    [ManualGroup.reinvestment, 'reinvestimento'],
    [ManualGroup.rate, 'taxa'],
    [ManualGroup.perpetuity, 'perpetuidade'],
    [ManualGroup.newCapital, 'capitalNovo'],
  ]),
};

/**
 * **Um valuation que o usuário confirmou** (decisão 150): as premissas
 * digitadas, as do motor de que elas partiram, e o resultado inteiro da
 * conta. **Nada aqui recalcula.**
 */
export class ManualValuationRecord {
  /** Versão do formato gravado por [toJson]. [fromJson] recusa outra. */
  static readonly format = 1;

  /** Prefixo do endereço do evento de auditoria. */
  static readonly endpointPrefix = '/core/valuation/manual/';

  /** Identificador: também o `transactionId` do evento e o nome do documento. */
  readonly id: string;
  readonly ticker: Ticker;

  /** Instante da confirmação. **Relógio do sistema**, recebido por parâmetro. */
  readonly savedAt: DateTime;

  /** Data de referência da avaliação do motor de que a conta partiu. */
  readonly engineAsOf: DateTime;
  readonly lane: ValuationLane;
  readonly marketPrice: number;
  readonly engineFairValue: number;
  readonly shares: number;
  readonly enginePremises: ManualPremises;
  readonly premises: ManualPremises;
  readonly outcome: ManualOutcome;

  /** Do preço do motor ao do usuário, um grupo de premissas de cada vez. */
  readonly attribution: readonly ManualStep[];

  constructor(args: {
    id: string;
    ticker: Ticker;
    savedAt: DateTime;
    engineAsOf: DateTime;
    lane: ValuationLane;
    marketPrice: number;
    engineFairValue: number;
    shares: number;
    enginePremises: ManualPremises;
    premises: ManualPremises;
    outcome: ManualOutcome;
    attribution?: readonly ManualStep[];
  }) {
    this.id = args.id;
    this.ticker = args.ticker;
    this.savedAt = args.savedAt;
    this.engineAsOf = args.engineAsOf;
    this.lane = args.lane;
    this.marketPrice = args.marketPrice;
    this.engineFairValue = args.engineFairValue;
    this.shares = args.shares;
    this.enginePremises = args.enginePremises;
    this.premises = args.premises;
    this.outcome = args.outcome;
    this.attribution = args.attribution ?? [];
  }

  /**
   * Retrata a conta de [valuation] com [premises] no instante [savedAt].
   * Recusa o que a tela também recusaria.
   */
  static capture(args: {
    id: string;
    ticker: Ticker;
    engineAsOf: DateTime;
    valuation: ManualValuation;
    premises: ManualPremises;
    savedAt: DateTime;
  }): Result<ManualValuationRecord> {
    const { id, valuation, premises } = args;
    if (id.trim().length === 0) {
      return err(new InvalidInput('Valuation sem identificador.'));
    }
    const evaluated = valuation.evaluate(premises);
    const outcome = evaluated.valueOrNull;
    if (outcome === null) return err(evaluated.failureOrNull!);
    if (!Number.isFinite(outcome.fairValuePerShare) || !Number.isFinite(outcome.equityValue)) {
      return err(new ComputationFailure('A conta não chegou a um preço justo finito: não há o que salvar.'));
    }
    return ok(
      new ManualValuationRecord({
        id,
        ticker: args.ticker,
        savedAt: args.savedAt,
        engineAsOf: args.engineAsOf,
        lane: valuation.lane,
        marketPrice: valuation.marketPrice,
        engineFairValue: valuation.engineFairValue,
        shares: valuation.shares,
        enginePremises: valuation.enginePremises,
        premises,
        outcome,
        attribution: valuation.attribution(premises),
      }),
    );
  }

  // ------------------------------------------------------------ Derivados --

  /** Preço justo do usuário por papel, sem arredondamento. */
  get fairValuePerShare(): number {
    return this.outcome.fairValuePerShare;
  }

  /** Preço justo do usuário **arredondado ao centavo**. */
  get fairValue(): Money {
    return Money.fromReais(this.outcome.fairValuePerShare);
  }

  /** Potencial total sobre o preço de mercado da avaliação, ou `null`. */
  get upside(): number | null {
    return this.marketPrice > 0 ? this.outcome.fairValuePerShare / this.marketPrice - 1 : null;
  }

  /** Quanto o preço do usuário se afasta do preço do motor, em reais por papel. */
  get engineDelta(): number {
    return this.outcome.fairValuePerShare - this.engineFairValue;
  }

  /** O endereço do evento de auditoria. */
  get endpoint(): string {
    return `${ManualValuationRecord.endpointPrefix}${this.ticker.value}`;
  }

  /** Os campos que o usuário trocou em relação ao motor, na ordem da tela. */
  get changedFields(): ManualField[] {
    const p = this.premises;
    const e = this.enginePremises;
    const byReturn = p.reinvestment === ManualReinvestment.byReturn;
    const changed = (f: ManualField): boolean => {
      switch (f) {
        case ManualField.baseProfit:
          return p.baseProfit !== e.baseProfit;
        case ManualField.growth:
          return p.growth !== e.growth || p.growthPath !== e.growthPath;
        case ManualField.discountRate:
          return p.discountRate !== e.discountRate || p.ratePath !== e.ratePath;
        case ManualField.perpetualGrowth:
          return p.perpetualGrowth !== e.perpetualGrowth;
        case ManualField.returnOnCapital:
          return byReturn && p.returnOnCapital !== e.returnOnCapital;
        case ManualField.retention:
          return !byReturn && (e.reinvestment !== p.reinvestment || p.retention !== e.retention);
        default:
          return p.terminalReturn !== e.terminalReturn;
      }
    };
    return ManualField.values.filter(changed);
  }

  // ---------------------------------------------------------- Persistência --

  /**
   * Serializa o registro inteiro. Os enums vão pela chave de `Wire`; valor não
   * finito vira o texto `NaN`, pela regra de [AuditJson.safe].
   */
  toJson(): JsonMap {
    return AuditJson.safeMap({
      formato: ManualValuationRecord.format,
      id: this.id,
      ticker: this.ticker.value,
      salvoEm: this.savedAt.toUtc().toIso8601String(),
      // Sem conversão a UTC: a data de referência é uma data de calendário.
      dataDaAvaliacao: this.engineAsOf.toIso8601String(),
      via: Wire.lane.get(this.lane),
      precoDeMercado: this.marketPrice,
      precoJustoDoMotor: this.engineFairValue,
      acoes: this.shares,
      premissasDoMotor: premisesJson(this.enginePremises),
      premissas: premisesJson(this.premises),
      resultado: outcomeJson(this.outcome),
      decomposicao: this.attribution.map((s) => ({
        grupos: s.groups.map((g) => Wire.group.get(g)),
        de: s.from,
        para: s.to,
      })),
    });
  }

  /**
   * Relê um registro gravado por [toJson], ou `null` quando ilegível. **Não
   * lança** por formato: um documento corrompido não derruba a lista inteira.
   */
  static fromJson(json: JsonMap): ManualValuationRecord | null {
    try {
      if (json['formato'] !== ManualValuationRecord.format) return null;
      const id = text(json, 'id');
      const ticker = Ticker.tryParse(text(json, 'ticker'));
      if (id.trim().length === 0 || ticker === null) return null;
      return new ManualValuationRecord({
        id,
        ticker,
        savedAt: date(json, 'salvoEm').toLocal(),
        engineAsOf: date(json, 'dataDaAvaliacao'),
        lane: decode(Wire.lane, json['via']),
        marketPrice: number(json, 'precoDeMercado'),
        engineFairValue: number(json, 'precoJustoDoMotor'),
        shares: number(json, 'acoes'),
        enginePremises: premisesFrom(map(json, 'premissasDoMotor')),
        premises: premisesFrom(map(json, 'premissas')),
        outcome: outcomeFrom(map(json, 'resultado')),
        attribution: list(json, 'decomposicao').map((raw) => stepFrom(asMap(raw))),
      });
    } catch (e) {
      if (e instanceof FormatException) return null;
      throw e;
    }
  }

  // ------------------------------------------------------------- Auditoria --

  /**
   * O registro como evento do painel de auditoria. O `transactionId` é [id] e
   * o instante é [savedAt]: o mesmo valuation emitido de novo é **um** evento
   * só no painel.
   */
  toAuditEvent(): AuditEvent {
    const changed = this.changedFields;
    return new AuditEvent({
      transactionId: this.id,
      timestamp: this.savedAt,
      endpoint: this.endpoint,
      inputPayload: {
        origem: 'valuation confirmado pelo usuário na edição (decisão 150)',
        ticker: this.ticker.value,
        via: Wire.lane.get(this.lane),
        dataDaAvaliacaoDoMotor: this.engineAsOf.toIso8601String(),
        precoDeMercado: this.marketPrice,
        precoJustoDoMotor: this.engineFairValue,
        acoes: this.shares,
        camposTrocados: changed.map((f) => Wire.field.get(f)),
        premissas: premisesJson(this.premises),
        premissasDoMotor: premisesJson(this.enginePremises),
      },
      outputPayload: {
        status: 'confirmado',
        salvoEm: this.savedAt.toUtc().toIso8601String(),
        precoJusto: this.outcome.fairValuePerShare,
        precoJustoCentavos: this.fairValue.cents,
        potencial: this.upside,
        diferencaContraOMotor: this.engineDelta,
        ...outcomeJson(this.outcome),
      },
      executionTimeMs: 0,
      calculations: Object.freeze(this.traces(changed)),
    });
  }

  private traces(changed: readonly ManualField[]): CalculationTrace[] {
    const o = this.outcome;
    const years = o.years;
    const upsideValue = this.upside;
    const terminalVariables: JsonMap = {
      'k_{\\infty} (% a.a.)': o.terminalRate * 100,
      'g (% a.a.)': this.premises.perpetualGrowth * 100,
    };
    if (o.terminalKind === ManualTerminal.advantage) {
      terminalVariables['r_{\\infty} (% a.a.)'] = (this.premises.terminalReturn ?? o.terminalRate) * 100;
    }
    if (o.terminalKind === ManualTerminal.fixedFraction) {
      terminalVariables['b (%)'] = this.premises.retention * 100;
    }
    terminalVariables['TV (R$)'] = o.terminalValue;
    terminalVariables['VP_{TV} (R$)'] = o.terminalPresentValue;

    const attributionSteps: string[] = [];
    if (this.attribution.length === 0) attributionSteps.push('Nenhum campo trocado: o preço é o do motor.');
    for (const s of this.attribution) {
      attributionSteps.push(
        `${s.groups.map(groupName).join(' + ')}: ` +
          `${price(s.from)} → ` +
          `${s.to === null ? 'sem valor finito' : price(s.to)}`,
      );
    }

    return [
      new CalculationTrace({
        formulaName: 'Valor presente dos anos explícitos — seus números',
        latexRepresentation: String.raw`VP_{anos} = \sum_{t=1}^{N} \frac{FC_t}{FD_t}`,
        mappedVariables: { N: years.length, 'VP_{anos} (R$)': o.explicitPresentValue },
        intermediateSteps: [
          ...years.map(
            (y) =>
              `Ano ${y.year}: FC ${millions(y.flow)} ÷ FD ` +
              `${decimal(y.discountFactor, 4)} = ${millions(y.presentValue)} ` +
              `(crescimento ${percent(y.growth)}, taxa ${percent(y.rate)})`,
          ),
          `Soma: ${millions(o.explicitPresentValue)}`,
        ],
        finalValue: o.explicitPresentValue,
        unit: 'R$',
        sample: new TraceSample({
          title: 'Valor presente de cada ano',
          points: years.map((y) => new TraceSamplePoint({ label: `ano ${y.year}`, value: y.presentValue })),
          unit: 'R$',
        }),
      }),
      new CalculationTrace({
        formulaName: `Valor terminal — ${terminalName(o.terminalKind)}`,
        latexRepresentation: terminalLatex(o.terminalKind),
        mappedVariables: terminalVariables,
        intermediateSteps: [
          `Valor terminal no ano ${years.length}: ${millions(o.terminalValue)}`,
          `Trazido a valor presente: ${millions(o.terminalPresentValue)}`,
        ],
        finalValue: o.terminalPresentValue,
        unit: 'R$',
      }),
      new CalculationTrace({
        formulaName: 'Valor do patrimônio — seus números',
        latexRepresentation: 'VPL = VP_{anos} + VP_{TV} - M + C_{pos}',
        mappedVariables: {
          'VP_{anos} (R$)': o.explicitPresentValue,
          'VP_{TV} (R$)': o.terminalPresentValue,
          'M (R$)': o.minorityInterest,
          'C_{pos} (R$)': o.postStatementCapital,
        },
        intermediateSteps: [
          `${millions(o.explicitPresentValue)} + ` +
            `${millions(o.terminalPresentValue)} − ` +
            `${millions(o.minorityInterest)} + ` +
            `${millions(o.postStatementCapital)} = ` +
            `${millions(o.equityValue)}`,
        ],
        finalValue: o.equityValue,
        unit: 'R$',
      }),
      new CalculationTrace({
        formulaName: 'Preço justo por ação — seus números',
        latexRepresentation: String.raw`P = \frac{VPL}{N_{acoes}}`,
        mappedVariables: { 'VPL (R$)': o.equityValue, 'N_{acoes}': this.shares },
        intermediateSteps: [
          `${millions(o.equityValue)} ÷ ${decimal(this.shares / 1e6, 1)} mi de ` +
            `ações = ${money(this.fairValue)} por ação`,
        ],
        finalValue: o.fairValuePerShare,
        unit: 'R$',
        explanation: [
          'É a conta do motor refeita com os números do usuário (decisão 147). ' +
            'A faixa calibrada e a habilidade medida continuam sendo do preço ' +
            'do motor: este preço é a opinião do usuário, sem validação ' +
            'própria.',
        ],
      }),
      new CalculationTrace({
        formulaName: 'Potencial sobre o preço de mercado',
        latexRepresentation: String.raw`u = \frac{P}{P_{mercado}} - 1`,
        mappedVariables: { 'P (R$)': o.fairValuePerShare, 'P_{mercado} (R$)': this.marketPrice },
        intermediateSteps: [
          upsideValue !== null
            ? `${money(this.fairValue)} ÷ ${price(this.marketPrice)} − 1 ` + `= ${percent(upsideValue)}`
            : 'Sem preço de mercado positivo, o potencial não é definido.',
        ],
        finalValue: upsideValue === null ? null : upsideValue * 100,
        unit: '%',
      }),
      new CalculationTrace({
        formulaName: 'Diferença contra o preço justo do motor',
        latexRepresentation: String.raw`\Delta = P - P_{motor}`,
        mappedVariables: {
          'P (R$)': o.fairValuePerShare,
          'P_{motor} (R$)': this.engineFairValue,
          'campos trocados': changed.length === 0 ? 'nenhum' : changed.map(fieldName).join(', '),
        },
        intermediateSteps: attributionSteps,
        finalValue: this.engineDelta,
        unit: 'R$',
      }),
    ];
  }
}

// -------------------------------------------------------------- Codecs --

function premisesJson(p: ManualPremises): JsonMap {
  return {
    lucroDePartida: p.baseProfit,
    crescimento: p.growth,
    caminhoDoCrescimento: Wire.growthPath.get(p.growthPath),
    taxaDeDesconto: p.discountRate,
    caminhoDaTaxa: Wire.ratePath.get(p.ratePath),
    crescimentoPerpetuo: p.perpetualGrowth,
    reinvestimento: Wire.reinvestment.get(p.reinvestment),
    retornoSobreOCapital: p.returnOnCapital,
    parcelaReinvestida: p.retention,
    // `null` é dado, e não ausência: é o estado estacionário.
    retornoDoCapitalNovo: p.terminalReturn,
  };
}

function premisesFrom(json: JsonMap): ManualPremises {
  return new ManualPremises({
    baseProfit: number(json, 'lucroDePartida'),
    growth: number(json, 'crescimento'),
    growthPath: decode(Wire.growthPath, json['caminhoDoCrescimento']),
    discountRate: number(json, 'taxaDeDesconto'),
    ratePath: decode(Wire.ratePath, json['caminhoDaTaxa']),
    perpetualGrowth: number(json, 'crescimentoPerpetuo'),
    reinvestment: decode(Wire.reinvestment, json['reinvestimento']),
    returnOnCapital: number(json, 'retornoSobreOCapital'),
    retention: number(json, 'parcelaReinvestida'),
    terminalReturn: json['retornoDoCapitalNovo'] == null ? null : number(json, 'retornoDoCapitalNovo'),
  });
}

function outcomeJson(o: ManualOutcome): JsonMap {
  return {
    precoJustoPorAcao: o.fairValuePerShare,
    valorDoPatrimonio: o.equityValue,
    valorPresenteDosAnos: o.explicitPresentValue,
    valorTerminal: o.terminalValue,
    valorPresenteDaPerpetuidade: o.terminalPresentValue,
    minoritarios: o.minorityInterest,
    capitalPosBalanco: o.postStatementCapital,
    taxaDaPerpetuidade: o.terminalRate,
    custoDoCapitalPorAno: o.capitalCostRates,
    custoDoCapitalNaPerpetuidade: o.terminalCapitalCost,
    perpetuidade: Wire.terminal.get(o.terminalKind),
    avisos: o.notices.map((n) => ({ tipo: Wire.notice.get(n.kind), anos: n.years })),
    anos: o.years.map((y) => ({
      ano: y.year,
      crescimento: y.growth,
      crescimentoPedido: y.plannedGrowth,
      lucro: y.profit,
      parcelaReinvestida: y.retention,
      fluxoDaFirma: y.firmFlow,
      servicoDaDivida: y.debtService,
      fluxo: y.flow,
      taxa: y.rate,
      fatorDeDesconto: y.discountFactor,
      valorPresente: y.presentValue,
    })),
  };
}

function outcomeFrom(json: JsonMap): ManualOutcome {
  const costs = json['custoDoCapitalPorAno'];
  return new ManualOutcome({
    fairValuePerShare: number(json, 'precoJustoPorAcao'),
    equityValue: number(json, 'valorDoPatrimonio'),
    explicitPresentValue: number(json, 'valorPresenteDosAnos'),
    terminalValue: number(json, 'valorTerminal'),
    terminalPresentValue: number(json, 'valorPresenteDaPerpetuidade'),
    minorityInterest: number(json, 'minoritarios'),
    postStatementCapital: number(json, 'capitalPosBalanco'),
    terminalRate: number(json, 'taxaDaPerpetuidade'),
    capitalCostRates: costs == null ? null : Object.freeze(list(json, 'custoDoCapitalPorAno').map(numberOf)),
    terminalCapitalCost:
      json['custoDoCapitalNaPerpetuidade'] == null ? null : number(json, 'custoDoCapitalNaPerpetuidade'),
    terminalKind: decode(Wire.terminal, json['perpetuidade']),
    notices: Object.freeze(list(json, 'avisos').map((raw) => noticeFrom(asMap(raw)))),
    years: Object.freeze(list(json, 'anos').map((raw) => yearFrom(asMap(raw)))),
  });
}

function noticeFrom(json: JsonMap): ManualNotice {
  return new ManualNotice(decode(Wire.notice, json['tipo']), {
    years: Object.freeze(list(json, 'anos').map((a) => round(numberOf(a)))),
  });
}

function yearFrom(json: JsonMap): ManualYear {
  return new ManualYear({
    year: round(number(json, 'ano')),
    growth: number(json, 'crescimento'),
    plannedGrowth: number(json, 'crescimentoPedido'),
    profit: number(json, 'lucro'),
    retention: number(json, 'parcelaReinvestida'),
    firmFlow: json['fluxoDaFirma'] == null ? null : number(json, 'fluxoDaFirma'),
    debtService: json['servicoDaDivida'] == null ? null : number(json, 'servicoDaDivida'),
    flow: number(json, 'fluxo'),
    rate: number(json, 'taxa'),
    discountFactor: number(json, 'fatorDeDesconto'),
    presentValue: number(json, 'valorPresente'),
  });
}

function stepFrom(json: JsonMap): ManualStep {
  return new ManualStep({
    groups: Object.freeze(list(json, 'grupos').map((g) => decode(Wire.group, g))),
    from: number(json, 'de'),
    to: json['para'] == null ? null : number(json, 'para'),
  });
}

// ---------------------------------------------- Leitura tolerante, local --

function field(json: JsonMap, key: string): unknown {
  if (!Object.prototype.hasOwnProperty.call(json, key)) throw new FormatException(`Campo ausente: ${key}`);
  return json[key];
}

function text(json: JsonMap, key: string): string {
  const v = field(json, key);
  if (typeof v !== 'string') throw new FormatException(`Campo não textual: ${key}`);
  return v;
}

function number(json: JsonMap, key: string): number {
  return numberOf(field(json, key));
}

/** Número gravado, aceitando os textos `NaN` e `Infinity` de [AuditJson]. */
function numberOf(raw: unknown): number {
  const n = AuditJson.number(raw);
  if (n === null) throw new FormatException(`Valor não numérico: ${interpolateJson(raw)}`);
  return n;
}

function date(json: JsonMap, key: string): DateTime {
  const d = DateTime.tryParse(text(json, key));
  if (d === null) throw new FormatException(`Data ilegível: ${key}`);
  return d;
}

function map(json: JsonMap, key: string): JsonMap {
  return asMap(field(json, key));
}

function asMap(raw: unknown): JsonMap {
  if (!isJsonObject(raw)) throw new FormatException('Esperado um mapa.');
  return { ...raw };
}

function list(json: JsonMap, key: string): unknown[] {
  const v = field(json, key);
  if (!Array.isArray(v)) throw new FormatException(`Campo não é lista: ${key}`);
  return v;
}

function decode<T>(keys: ReadonlyMap<T, string>, raw: unknown): T {
  for (const [k, v] of keys) {
    if (v === raw) return k;
  }
  throw new FormatException(`Chave desconhecida: ${interpolateJson(raw)}`);
}

// ------------------------------------------------------- Texto do rastro --

/** Reais em milhões, com uma casa, arredondados meio afastado de zero. */
function millions(v: number): string {
  if (!Number.isFinite(v)) return str(v);
  const tenths = round(Math.abs(v) / 1e5);
  return `${v < 0 ? '−' : ''}R$ ${Math.trunc(tenths / 10)},${tenths % 10} mi`;
}

/** Dinheiro já em centavos: o texto não arredonda de novo. */
function money(m: Money): string {
  const c = Math.abs(m.cents);
  return `${m.cents < 0 ? '−' : ''}R$ ${Math.trunc(c / 100)},` + `${String(c % 100).padStart(2, '0')}`;
}

/** Preço em reais, arredondado ao centavo. Valor não finito sai como está. */
function price(v: number): string {
  return Number.isFinite(v) ? money(Money.fromReais(v)) : str(v);
}

/** Fração como percentual com duas casas, arredondado meio afastado de zero. */
function percent(fraction: number): string {
  if (!Number.isFinite(fraction)) return str(fraction);
  const hundredths = round(fraction * 10000);
  const m = Math.abs(hundredths);
  return `${hundredths < 0 ? '−' : ''}${Math.trunc(m / 100)},` + `${String(m % 100).padStart(2, '0')}%`;
}

/** Número com [decimals] casas, arredondado meio afastado de zero. */
function decimal(v: number, decimals: number): string {
  if (!Number.isFinite(v)) return str(v);
  let scale = 1;
  for (let i = 0; i < decimals; i++) scale *= 10;
  const scaled = round(v * scale);
  const m = Math.abs(scaled);
  const fraction = String(m % scale).padStart(decimals, '0');
  return `${scaled < 0 ? '−' : ''}${Math.trunc(m / scale)}` + `${decimals > 0 ? `,${fraction}` : ''}`;
}

function terminalName(kind: ManualTerminal): string {
  switch (kind) {
    case ManualTerminal.neutral:
      return 'capital novo rendendo a própria taxa';
    case ManualTerminal.advantage:
      return 'Gordon com retorno próprio do capital novo';
    case ManualTerminal.fixedFraction:
      return 'Gordon com a parcela fixa';
    default:
      return 'concessão, até o fim do contrato';
  }
}

function terminalLatex(kind: ManualTerminal): string {
  switch (kind) {
    case ManualTerminal.neutral:
      return String.raw`TV = \frac{L_{N+1}}{k_{\infty}}`;
    case ManualTerminal.advantage:
      return String.raw`TV = \frac{L_{N+1}\,(1 - g/r_{\infty})}{k_{\infty} - g}`;
    case ManualTerminal.fixedFraction:
      return String.raw`TV = \frac{L_{N+1}\,(1 - b)}{k_{\infty} - g}`;
    default:
      return String.raw`TV = \text{excedente até o fim do contrato} + \text{capital}`;
  }
}

function fieldName(f: ManualField): string {
  switch (f) {
    case ManualField.baseProfit:
      return 'lucro de partida';
    case ManualField.growth:
      return 'crescimento nos primeiros anos';
    case ManualField.discountRate:
      return 'taxa de desconto';
    case ManualField.perpetualGrowth:
      return 'crescimento na perpetuidade';
    case ManualField.returnOnCapital:
      return 'retorno sobre o capital';
    case ManualField.retention:
      return 'parcela reinvestida';
    default:
      return 'retorno do capital novo';
  }
}

function groupName(g: ManualGroup): string {
  switch (g) {
    case ManualGroup.profit:
      return 'Lucro de partida';
    case ManualGroup.growth:
      return 'Crescimento';
    case ManualGroup.reinvestment:
      return 'Reinvestimento';
    case ManualGroup.rate:
      return 'Taxa de desconto';
    case ManualGroup.perpetuity:
      return 'Perpetuidade';
    default:
      return 'Capital novo';
  }
}
