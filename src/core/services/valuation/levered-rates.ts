/** Custo de capital que acompanha a alavancagem ano a ano. */

import { ComputationFailure, InvalidInput } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import { toStringAsFixed } from '../../lang/num';
import { BetaShrinkage } from '../metrics/beta-shrinkage';
import { DcfCalculator, type DcfAssumptions } from './dcf';

/** Caminho de taxas e de valores resolvido pelo ponto fixo. */
export class LeveredRates {
  /** `Ke` do ano 1 ao ano N. */
  readonly costOfEquity: readonly number[];

  /** `WACC` do ano 1 ao ano N. */
  readonly wacc: readonly number[];

  /** Valor da firma do ano 0 ao ano N — `N + 1` posições. */
  readonly enterpriseValue: readonly number[];

  /** Capital próprio do ano 0 ao ano N. */
  readonly equity: readonly number[];

  /** Dívida líquida do ano 0 ao ano N. */
  readonly debt: readonly number[];

  /** `Ke` de equilíbrio, na alavancagem do ano N. */
  readonly terminalCostOfEquity: number;

  /** `WACC` de equilíbrio, na alavancagem do ano N. */
  readonly terminalWacc: number;

  /** Iterações consumidas pelo ponto fixo. */
  readonly iterations: number;

  /** `true` quando o critério de parada foi alcançado antes do teto. */
  readonly converged: boolean;

  constructor(args: {
    costOfEquity: readonly number[];
    wacc: readonly number[];
    enterpriseValue: readonly number[];
    equity: readonly number[];
    debt: readonly number[];
    terminalCostOfEquity: number;
    terminalWacc: number;
    iterations: number;
    converged: boolean;
  }) {
    this.costOfEquity = args.costOfEquity;
    this.wacc = args.wacc;
    this.enterpriseValue = args.enterpriseValue;
    this.equity = args.equity;
    this.debt = args.debt;
    this.terminalCostOfEquity = args.terminalCostOfEquity;
    this.terminalWacc = args.terminalWacc;
    this.iterations = args.iterations;
    this.converged = args.converged;
  }

  /**
   * Participação do capital próprio no ano [t], ou `null` quando ela não tem
   * sentido. **Nulo em vez de `NaN`**: com caixa líquido maior que o negócio,
   * a pergunta não se aplica.
   */
  equityShareAt(t: number): number | null {
    if (t < 0 || t >= this.enterpriseValue.length) return null;
    const v = this.enterpriseValue[t]!;
    if (!Number.isFinite(v) || v <= 0) return null;
    const s = this.equity[t]! / v;
    return Number.isFinite(s) ? s : null;
  }
}

/** Argumentos de [LeveredCostOfCapital.solve]. */
export interface LeveredSolveArgs {
  baseProfit: number;
  assumptions: DcfAssumptions;
  netDebt: number;
  unleveredBeta: number;
  riskFreePath: readonly number[];
  terminalRiskFree: number;
  marketPremium: number;
  /** **Prêmio de crédito** sobre a taxa livre de risco, e não o custo da dívida pronto. */
  creditSpread: number;
  taxRate: number;
  cash?: number | null;
  terminalBetaWeight?: number | null;
  terminalLeverage?: number | null;
  warnings?: string[] | null;
}

/** Argumentos de [LeveredCostOfCapital.solveEquity]. */
export interface LeveredSolveEquityArgs {
  baseProfit: number;
  assumptions: DcfAssumptions;
  netDebtPerShare: number;
  unleveredBeta: number;
  riskFreePath: readonly number[];
  terminalRiskFree: number;
  marketPremium: number;
  taxRate: number;
  terminalBetaWeight?: number | null;
  terminalLeverage?: number | null;
  warnings?: string[] | null;
}

/**
 * `β_∞ = w·β_L,N + (1 − w)·1` — o ajuste de Blume do item B15. Sem
 * imposição, o beta de equilíbrio é o realavancado do ano N.
 */
function equilibriumBeta(betaLevered: number, weight: number | null): number {
  return weight === null ? betaLevered : weight * betaLevered + (1 - weight) * 1.0;
}

/** A alavancagem imposta do B15 descreve uma estrutura possível? */
function impossibleLeverage(debtToEquity: number | null): boolean {
  return debtToEquity !== null && (!Number.isFinite(debtToEquity) || 1 + debtToEquity <= 0);
}

/**
 * Resolve `Ke` e `WACC` ano a ano contra a alavancagem que a própria avaliação
 * produz.
 *
 * ```
 * β_L,t  = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
 * Ke_t   = Rf_t + β_L,t · prêmio
 * WACC_t = Ke_t·(E/V)_{t−1} + Kd·(1 − τ)·(D/V)_{t−1}
 * ```
 *
 * **A circularidade é resolvida por ponto fixo**, e não por aproximação.
 */
export const LeveredCostOfCapital = {
  /** Teto de iterações do ponto fixo. */
  maxIterations: 100,

  /** Critério de parada: variação relativa do valor no ano zero. */
  tolerance: 1e-10,

  /** Amortecimento aplicado à atualização do caminho de capital próprio. Meio a meio. */
  damping: 0.5,

  /**
   * Distância relativa a partir da qual duas soluções do ponto fixo são
   * **respostas diferentes** (item B18). Um décimo de por cento no valor do
   * ano zero.
   */
  startIndependence: 0.001,

  /**
   * Resolve o caminho de taxas, **de dois pontos de partida** (item B18): o
   * caminho sem realavancagem e o custo de capital desalavancado. Quando só
   * uma converge, vale ela; quando as duas divergem, o aviso diz isso.
   */
  solve(args: LeveredSolveArgs): Result<LeveredRates> {
    const warnings = args.warnings ?? null;
    const attemptFrom = (initial: number[] | null, initialTerminal: number | null): Result<LeveredRates> =>
      attempt({
        initialWacc: initial,
        initialTerminalWacc: initialTerminal,
        baseProfit: args.baseProfit,
        assumptions: args.assumptions,
        netDebt: args.netDebt,
        unleveredBeta: args.unleveredBeta,
        riskFreePath: args.riskFreePath,
        terminalRiskFree: args.terminalRiskFree,
        marketPremium: args.marketPremium,
        creditSpread: args.creditSpread,
        taxRate: args.taxRate,
        cash: args.cash ?? null,
        terminalBetaWeight: args.terminalBetaWeight ?? null,
        terminalLeverage: args.terminalLeverage ?? null,
      });

    const byInterpolation = attemptFrom(null, null);
    // O desalavancado: o mesmo caminho de `Ke` com `D/E = 0`.
    const unlevered = args.riskFreePath.map((rf) => rf + args.unleveredBeta * args.marketPremium);
    const byUnlevered = attemptFrom(unlevered, args.terminalRiskFree + args.unleveredBeta * args.marketPremium);

    const a = byInterpolation.valueOrNull;
    const b = byUnlevered.valueOrNull;
    if (a === null && b === null) {
      // **A recusa é do ponto fixo, e o texto precisa dizer isso** (item B18).
      const reason = byInterpolation.failureOrNull?.message ?? '';
      return err(
        new ComputationFailure(
          `${reason} O ponto fixo foi tentado também a partir do custo de capital ` +
            'desalavancado, e não fecha de nenhuma das duas partidas: a recusa é ' +
            'do método, e não do chute.',
        ),
      );
    }
    if (a === null) {
      warnings?.push(
        'O ponto fixo do custo de capital não fecha a partir do caminho sem ' +
          'realavancagem, e fecha a partir do custo desalavancado. O resultado ' +
          'é o do ponto fixo, e não o do chute — recusar aqui seria recusar por ' +
          'causa de onde a conta começou (item B18).',
      );
      return byUnlevered;
    }
    if (b === null) return byInterpolation;

    const va = a.equity.length === 0 ? NaN : a.equity[0]!;
    const vb = b.equity.length === 0 ? NaN : b.equity[0]!;
    const distance = Math.abs(va) > 0 && Number.isFinite(va) && Number.isFinite(vb) ? Math.abs(vb / va - 1) : 0.0;
    if (distance > LeveredCostOfCapital.startIndependence) {
      warnings?.push(
        'O ponto fixo do custo de capital chega a dois resultados conforme o ' +
          `chute de partida — ${toStringAsFixed(distance * 100, 1)}% de ` +
          'diferença no capital próprio do ano zero. Vale o da interpolação, ' +
          'que é o caminho declarado, e esta divergência é ressalva do método ' +
          '(item B18).',
      );
    }
    return byInterpolation;
  },

  /**
   * Resolve o `Ke` ano a ano **pelo lado do capital próprio**, sem passar pelo
   * valor da firma. **Tudo por papel**, e **a dívida não cresce aqui** (item
   * B11). Também de duas partidas (item B18).
   */
  solveEquity(args: LeveredSolveEquityArgs): Result<LeveredRates> {
    const warnings = args.warnings ?? null;
    const attemptFrom = (initial: number[] | null, initialTerminal: number | null): Result<LeveredRates> =>
      attemptEquity({
        initialKe: initial,
        initialTerminalKe: initialTerminal,
        baseProfit: args.baseProfit,
        assumptions: args.assumptions,
        netDebtPerShare: args.netDebtPerShare,
        unleveredBeta: args.unleveredBeta,
        riskFreePath: args.riskFreePath,
        terminalRiskFree: args.terminalRiskFree,
        marketPremium: args.marketPremium,
        taxRate: args.taxRate,
        terminalBetaWeight: args.terminalBetaWeight ?? null,
        terminalLeverage: args.terminalLeverage ?? null,
      });

    const byInterpolation = attemptFrom(null, null);
    const unlevered = args.riskFreePath.map((rf) => rf + args.unleveredBeta * args.marketPremium);
    const byUnlevered = attemptFrom(unlevered, args.terminalRiskFree + args.unleveredBeta * args.marketPremium);

    const a = byInterpolation.valueOrNull;
    const b = byUnlevered.valueOrNull;
    if (a === null && b === null) {
      const reason = byInterpolation.failureOrNull?.message ?? '';
      return err(
        new ComputationFailure(
          `${reason} O ponto fixo foi tentado também a partir do custo de capital ` +
            'desalavancado, e não fecha de nenhuma das duas partidas: a recusa é ' +
            'do método, e não do chute.',
        ),
      );
    }
    if (a === null) {
      warnings?.push(
        'O ponto fixo do custo do capital próprio não fecha a partir do ' +
          'caminho sem realavancagem, e fecha a partir do custo desalavancado. ' +
          'O resultado é o do ponto fixo, e não o do chute (item B18).',
      );
      return byUnlevered;
    }
    if (b === null) return byInterpolation;

    const va = a.equity.length === 0 ? NaN : a.equity[0]!;
    const vb = b.equity.length === 0 ? NaN : b.equity[0]!;
    const distance = Math.abs(va) > 0 && Number.isFinite(va) && Number.isFinite(vb) ? Math.abs(vb / va - 1) : 0.0;
    if (distance > LeveredCostOfCapital.startIndependence) {
      warnings?.push(
        'O ponto fixo do custo do capital próprio chega a dois resultados ' +
          `conforme o chute de partida — ${toStringAsFixed(distance * 100, 1)}% ` +
          'de diferença no capital próprio do ano zero. Vale o da interpolação, ' +
          'e a divergência é ressalva do método (item B18).',
      );
    }
    return byInterpolation;
  },
};

/** Uma tentativa do ponto fixo da via da firma, a partir de um caminho de partida. */
function attempt(args: {
  initialWacc: readonly number[] | null;
  initialTerminalWacc: number | null;
  baseProfit: number;
  assumptions: DcfAssumptions;
  netDebt: number;
  unleveredBeta: number;
  riskFreePath: readonly number[];
  terminalRiskFree: number;
  marketPremium: number;
  creditSpread: number;
  taxRate: number;
  cash: number | null;
  terminalBetaWeight: number | null;
  terminalLeverage: number | null;
}): Result<LeveredRates> {
  const {
    initialWacc,
    initialTerminalWacc,
    baseProfit,
    assumptions,
    netDebt,
    unleveredBeta,
    riskFreePath,
    terminalRiskFree,
    marketPremium,
    creditSpread,
    taxRate,
    cash,
    terminalBetaWeight,
    terminalLeverage,
  } = args;
  const { damping, maxIterations, tolerance } = LeveredCostOfCapital;
  const n = assumptions.projectionYears;
  if (n < 1) {
    return err(new InvalidInput('Anos de projeção deve ser ao menos 1.'));
  }
  if (riskFreePath.length !== n) {
    return err(new InvalidInput('Caminho da taxa livre de risco precisa de uma taxa por ano ' + 'projetado.'));
  }
  if (impossibleLeverage(terminalLeverage)) {
    return err(
      new InvalidInput(
        'Alavancagem de equilíbrio imposta não descreve estrutura possível: ' +
          'com D/E de −1 ou menos o valor da firma não é positivo.',
      ),
    );
  }
  if (!Number.isFinite(unleveredBeta) || unleveredBeta < 0) {
    return err(new InvalidInput('Beta desalavancado indisponível: a realavancagem não é possível.'));
  }

  // A dívida segue a base de capital, que é o que a projeção faz crescer.
  const debt: number[] = [netDebt];
  for (let t = 1; t <= n; t++) {
    debt.push(debt[t - 1]! * (1 + assumptions.growthAt(t)));
  }
  // **O caixa acompanha a mesma base, e por isso a líquida não muda**: o que
  // a separação muda é só a composição da taxa — o caixa rende `R_f`.
  const cashPath: number[] | null = cash === null ? null : [cash];
  if (cashPath !== null) {
    for (let t = 1; t <= n; t++) {
      cashPath.push(cashPath[t - 1]! * (1 + assumptions.growthAt(t)));
    }
  }

  // `K_d` do ano, líquido do escudo.
  const netKdAt = (rf: number): number => (rf + creditSpread) * (1 - taxRate);
  const kdTerminal = netKdAt(terminalRiskFree);

  // Chute inicial: o informado, ou as taxas da interpolação de dois pontos.
  let ke: number[] =
    initialWacc !== null && initialWacc.length === n
      ? [...initialWacc]
      : Array.from({ length: n }, (_, i) => assumptions.discountRateAt(i + 1));
  let wacc = [...ke];
  let keTerminal = initialTerminalWacc ?? assumptions.terminalDiscountRate;
  let waccTerminal = keTerminal;
  let previousEquity: number[] | null = null;

  let iterations = 0;
  let converged = false;
  let previousValue = NaN;
  let ev: number[] = [];
  let equity: number[] = [];

  while (iterations < maxIterations) {
    iterations++;

    const valuation = DcfCalculator.firm({
      baseProfit,
      assumptions: assumptions.copyWith({ discountRatePath: wacc, terminalDiscountRate: waccTerminal }),
      netDebt: 0,
      sharesOutstanding: 1,
    });
    if (valuation.isErr) {
      return err(new ComputationFailure(`${valuation.failureOrNull!.message} (iteração ${iterations})`));
    }
    const o = valuation.unwrap();

    // Valor da firma ano a ano, por acumulação regressiva. O terminal entra
    // levantado por meio ano, pela mesma razão que os fluxos.
    const v = new Array<number>(n + 1).fill(0);
    v[n] = o.terminalValue * assumptions.lift(waccTerminal);
    for (let t = n; t >= 1; t--) {
      const r = wacc[t - 1]!;
      v[t - 1] = (o.projectedFlows[t - 1]! * assumptions.lift(r)) / (1 + r) + v[t]! / (1 + r);
    }
    ev = v;

    const e: number[] = [];
    for (let t = 0; t <= n; t++) e.push(v[t]! - debt[t]!);
    // Amortecimento contra oscilação em ativo muito alavancado.
    if (previousEquity !== null) {
      for (let t = 0; t <= n; t++) {
        e[t] = damping * e[t]! + (1 - damping) * previousEquity[t]!;
      }
    }
    equity = e;
    previousEquity = [...e];

    // Realavancagem: cada ano usa a estrutura do **início** do ano.
    const newKe: number[] = [];
    const newWacc: number[] = [];
    for (let t = 1; t <= n; t++) {
      const previousEquityValue = e[t - 1]!;
      const previousDebt = debt[t - 1]!;
      if (!Number.isFinite(previousEquityValue) || previousEquityValue <= 0) {
        return err(
          new ComputationFailure(
            `O capital próprio desaparece dentro da projeção (ano ${t - 1}, ` +
              `iteração ${iterations}): a realavancagem não tem sentido econômico, ` +
              'e o ativo não é avaliável por fluxo descontado nesta estrutura de ' +
              'capital.',
          ),
        );
      }
      const debtToEquity = previousDebt / previousEquityValue;
      const factor = BetaShrinkage.leverageFactor({ debtToEquity, taxRate });
      if (factor === null) {
        return err(new ComputationFailure('Fator de alavancagem não finito na realavancagem.'));
      }
      const keT = riskFreePath[t - 1]! + unleveredBeta * factor * marketPremium;
      // `D` é dívida **líquida** e pode ser negativa: sem esta guarda o peso do
      // capital próprio divide por zero.
      const vT = previousEquityValue + previousDebt;
      if (!Number.isFinite(vT) || vT <= 0) {
        return err(
          new ComputationFailure(
            'Valor da firma não positivo dentro da projeção: o caixa líquido ' +
              'supera o próprio valor, e o peso do capital no custo médio deixa ' +
              'de ter sentido.',
          ),
        );
      }
      // **O peso não é confinado em [0, 1]** (decisão 104).
      const equityWeight = previousEquityValue / vT;
      const interest = netKdAt(riskFreePath[t - 1]!);
      newKe.push(keT);
      if (cashPath === null) {
        newWacc.push(keT * equityWeight + interest * (1 - equityWeight));
      } else {
        // `w_bruta − w_caixa` é exatamente `1 − equityWeight`.
        const wGross = (previousDebt + cashPath[t - 1]!) / vT;
        const wCash = cashPath[t - 1]! / vT;
        const income = riskFreePath[t - 1]! * (1 - taxRate);
        newWacc.push(keT * equityWeight + interest * wGross - income * wCash);
      }
    }
    ke = newKe;
    wacc = newWacc;

    // Equilíbrio: a estrutura do ano N é a que vale na perpetuidade.
    const eN = e[n]!;
    const dN = debt[n]!;
    if (eN <= 0) {
      return err(new ComputationFailure('Capital próprio não positivo no fim da projeção (iteração ' + `${iterations}).`));
    }
    // **A alavancagem de equilíbrio é a do ano N**, e a imposição do B15 a
    // substitui quando a varredura quer testar outra.
    const terminalDebtToEquity = terminalLeverage ?? dN / eN;
    const factorN = BetaShrinkage.leverageFactor({ debtToEquity: terminalDebtToEquity, taxRate });
    if (factorN === null) {
      return err(new ComputationFailure('Fator de alavancagem terminal não finito.'));
    }
    keTerminal = terminalRiskFree + equilibriumBeta(unleveredBeta * factorN, terminalBetaWeight) * marketPremium;
    const vN = eN + dN;
    if (!Number.isFinite(vN) || vN <= 0) {
      return err(
        new ComputationFailure(
          'Valor da firma não positivo no fim da projeção: o peso do capital ' +
            'no custo médio de equilíbrio deixa de ter sentido.',
        ),
      );
    }
    const weightEN = terminalLeverage === null ? eN / vN : 1 / (1 + terminalLeverage);
    // Mesma separação do ano a ano, na estrutura do ano N. Com `D/E` imposto
    // não há separação.
    if (cashPath === null || terminalLeverage !== null) {
      waccTerminal = keTerminal * weightEN + kdTerminal * (1 - weightEN);
    } else {
      waccTerminal =
        keTerminal * weightEN +
        kdTerminal * ((dN + cashPath[n]!) / vN) -
        terminalRiskFree * (1 - taxRate) * (cashPath[n]! / vN);
    }

    const value = e[0]!;
    if (Number.isFinite(previousValue) && Math.abs(previousValue) > 0) {
      if (Math.abs(value - previousValue) / Math.abs(previousValue) < tolerance) {
        converged = true;
        previousValue = value;
        break;
      }
    }
    previousValue = value;
  }

  return ok(
    new LeveredRates({
      costOfEquity: Object.freeze([...ke]),
      wacc: Object.freeze([...wacc]),
      enterpriseValue: Object.freeze([...ev]),
      equity: Object.freeze([...equity]),
      debt: Object.freeze([...debt]),
      terminalCostOfEquity: keTerminal,
      terminalWacc: waccTerminal,
      iterations,
      converged,
    }),
  );
}

/** Uma tentativa do ponto fixo da via do acionista. */
function attemptEquity(args: {
  initialKe: readonly number[] | null;
  initialTerminalKe: number | null;
  baseProfit: number;
  assumptions: DcfAssumptions;
  netDebtPerShare: number;
  unleveredBeta: number;
  riskFreePath: readonly number[];
  terminalRiskFree: number;
  marketPremium: number;
  taxRate: number;
  terminalBetaWeight: number | null;
  terminalLeverage: number | null;
}): Result<LeveredRates> {
  const {
    initialKe,
    initialTerminalKe,
    baseProfit,
    assumptions,
    netDebtPerShare,
    unleveredBeta,
    riskFreePath,
    terminalRiskFree,
    marketPremium,
    taxRate,
    terminalBetaWeight,
    terminalLeverage,
  } = args;
  const { damping, maxIterations, tolerance } = LeveredCostOfCapital;
  const n = assumptions.projectionYears;
  if (n < 1) {
    return err(new InvalidInput('Anos de projeção deve ser ao menos 1.'));
  }
  if (riskFreePath.length !== n) {
    return err(new InvalidInput('Caminho da taxa livre de risco precisa de uma taxa por ano ' + 'projetado.'));
  }
  if (impossibleLeverage(terminalLeverage)) {
    return err(
      new InvalidInput(
        'Alavancagem de equilíbrio imposta não descreve estrutura possível: ' +
          'com D/E de −1 ou menos o valor da firma não é positivo.',
      ),
    );
  }
  if (!Number.isFinite(unleveredBeta) || unleveredBeta < 0) {
    return err(new InvalidInput('Beta desalavancado indisponível: a realavancagem não é possível.'));
  }

  // **A dívida fica constante em termos nominais, e a razão é o fluxo** (item
  // B11): o crescimento já é financiado por lucro retido, e fazer a dívida
  // crescer junto o financiaria duas vezes.
  const debt: number[] = [];
  for (let t = 0; t <= n; t++) debt.push(netDebtPerShare);

  let ke: number[] =
    initialKe !== null && initialKe.length === n
      ? [...initialKe]
      : Array.from({ length: n }, (_, i) => assumptions.discountRateAt(i + 1));
  let keTerminal = initialTerminalKe ?? assumptions.terminalDiscountRate;
  let previousEquity: number[] | null = null;

  let iterations = 0;
  let converged = false;
  let previousValue = NaN;
  let equity: number[] = [];

  while (iterations < maxIterations) {
    iterations++;

    const valuation = DcfCalculator.shareholder({
      baseProfit,
      assumptions: assumptions.copyWith({ discountRatePath: ke, terminalDiscountRate: keTerminal }),
    });
    if (valuation.isErr) {
      return err(new ComputationFailure(`${valuation.failureOrNull!.message} (iteração ${iterations})`));
    }
    const o = valuation.unwrap();

    // Capital próprio ano a ano, por acumulação regressiva.
    const e = new Array<number>(n + 1).fill(0);
    e[n] = o.terminalValue * assumptions.lift(keTerminal);
    for (let t = n; t >= 1; t--) {
      const r = ke[t - 1]!;
      e[t - 1] = (o.projectedFlows[t - 1]! * assumptions.lift(r)) / (1 + r) + e[t]! / (1 + r);
    }
    if (previousEquity !== null) {
      for (let t = 0; t <= n; t++) {
        e[t] = damping * e[t]! + (1 - damping) * previousEquity[t]!;
      }
    }
    equity = e;
    previousEquity = [...e];

    const newKe: number[] = [];
    for (let t = 1; t <= n; t++) {
      const previousEquityValue = e[t - 1]!;
      if (!Number.isFinite(previousEquityValue) || previousEquityValue <= 0) {
        return err(
          new ComputationFailure(
            `O capital próprio desaparece dentro da projeção (ano ${t - 1}, ` +
              `iteração ${iterations}): a realavancagem não tem sentido econômico.`,
          ),
        );
      }
      const factor = BetaShrinkage.leverageFactor({ debtToEquity: debt[t - 1]! / previousEquityValue, taxRate });
      if (factor === null) {
        return err(new ComputationFailure('Fator de alavancagem não finito na realavancagem.'));
      }
      newKe.push(riskFreePath[t - 1]! + unleveredBeta * factor * marketPremium);
    }
    ke = newKe;

    const eN = e[n]!;
    if (!Number.isFinite(eN) || eN <= 0) {
      return err(new ComputationFailure('Capital próprio não positivo no fim da projeção (iteração ' + `${iterations}).`));
    }
    const factorN = BetaShrinkage.leverageFactor({ debtToEquity: terminalLeverage ?? debt[n]! / eN, taxRate });
    if (factorN === null) {
      return err(new ComputationFailure('Fator de alavancagem terminal não finito.'));
    }
    keTerminal = terminalRiskFree + equilibriumBeta(unleveredBeta * factorN, terminalBetaWeight) * marketPremium;

    const value = e[0]!;
    if (Number.isFinite(previousValue) && Math.abs(previousValue) > 0) {
      if (Math.abs(value - previousValue) / Math.abs(previousValue) < tolerance) {
        converged = true;
        previousValue = value;
        break;
      }
    }
    previousValue = value;
  }

  const enterprise: number[] = [];
  for (let t = 0; t <= n; t++) enterprise.push(equity[t]! + debt[t]!);
  return ok(
    new LeveredRates({
      costOfEquity: Object.freeze([...ke]),
      wacc: Object.freeze([...ke]),
      enterpriseValue: Object.freeze(enterprise),
      equity: Object.freeze([...equity]),
      debt: Object.freeze([...debt]),
      terminalCostOfEquity: keTerminal,
      terminalWacc: keTerminal,
      iterations,
      converged,
    }),
  );
}
