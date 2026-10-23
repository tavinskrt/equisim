import { FinancialGoal, RequiredReturn } from '../../entities/financial-goal';
import { ComputationFailure } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';

const TOLERANCE = 1e-12;
const MAX_ITERATIONS = 200;

/** Limite inferior de busca: −99,99% ao mês. */
const LOWER_BOUND = -0.9999;

/** Limite superior: 100% ao mês. Acima disso a meta é absurda por qualquer critério. */
const UPPER_BOUND = 1.0;

/**
 * Resolve a rentabilidade necessária para um plano com aportes mensais.
 *
 * **Não existe forma fechada.** A fórmula `(V_f/V₀)^(1/t) − 1` só vale quando
 * não há aportes; com PMT ≠ 0 ela ignora todo o capital adicionado ao longo do
 * caminho e superestima grosseiramente a taxa exigida.
 *
 * A equação correta é o valor futuro de uma série uniforme:
 *
 *     V_f = V₀(1+i)ⁿ + PMT · [((1+i)ⁿ − 1) / i]
 *
 * `i` não pode ser isolado algebricamente, então é resolvido numericamente.
 */
export const RequiredReturnSolver = {
  /**
   * Valor futuro do plano a uma taxa mensal [rate]. Trata o limite `i → 0`
   * explicitamente: o fator de anuidade tende a `n`.
   */
  futureValue(args: { rate: number; initial: number; monthly: number; months: number }): number {
    const { rate, initial, monthly, months } = args;
    if (Math.abs(rate) < 1e-12) {
      return initial + monthly * months;
    }
    const growth = Math.pow(1 + rate, months);
    return initial * growth + (monthly * (growth - 1)) / rate;
  },

  /**
   * Resolve a taxa mensal requerida.
   *
   * Newton-Raphson com bisseção de resguardo: Newton converge em 4–6
   * iterações no caso típico, mas pode divergir com aportes grandes em
   * relação ao inicial; a bisseção garante a resposta porque a função é
   * monotônica crescente em `i`.
   *
   * **As guardas de entrada continuam aqui de propósito**: `FinancialGoal.
   * unvalidated` é o caminho da desserialização, e uma meta gravada antes da
   * fábrica pode chegar aqui inconsistente.
   */
  solve(goal: FinancialGoal): Result<RequiredReturn> {
    const valid = FinancialGoal.create({
      initialContribution: goal.initialContribution,
      monthlyContribution: goal.monthlyContribution,
      months: goal.months,
      targetWealth: goal.targetWealth,
    });
    if (valid.isErr) return err(valid.failureOrNull!);

    const v0 = goal.initialContribution.reais;
    const pmt = goal.monthlyContribution.reais;
    const n = goal.months;
    const target = goal.targetWealth.reais;

    const f = (rate: number): number =>
      RequiredReturnSolver.futureValue({ rate, initial: v0, monthly: pmt, months: n }) - target;

    // Newton-Raphson com derivada numérica central: a derivada analítica do
    // fator de anuidade é instável perto de i = 0.
    let rate = 0.01;
    for (let i = 0; i < MAX_ITERATIONS; i++) {
      const value = f(rate);
      if (Math.abs(value) < TOLERANCE) {
        return ok(new RequiredReturn({ monthly: rate }));
      }
      const h = 1e-7;
      const derivative = (f(rate + h) - f(rate - h)) / (2 * h);
      if (Math.abs(derivative) < 1e-14 || !Number.isFinite(derivative)) break;
      const next = rate - value / derivative;
      if (!Number.isFinite(next) || next <= LOWER_BOUND || next > UPPER_BOUND) break;
      if (Math.abs(next - rate) < TOLERANCE) {
        return ok(new RequiredReturn({ monthly: next }));
      }
      rate = next;
    }

    // Bisseção: a função é monotônica crescente.
    let low = LOWER_BOUND;
    let high = UPPER_BOUND;
    const fLow = f(low);
    const fHigh = f(high);

    if (fLow > 0) {
      // Mesmo com perda quase total o patrimônio supera a meta.
      return ok(new RequiredReturn({ monthly: 0.0 }));
    }
    if (fHigh < 0) {
      return err(
        new ComputationFailure(
          `Meta inatingível: nem 100% ao mês durante ${goal.months} meses ` +
            `alcança ${goal.targetWealth.toString()}.`,
        ),
      );
    }

    for (let i = 0; i < MAX_ITERATIONS; i++) {
      const mid = (low + high) / 2;
      const fMid = f(mid);
      if (Math.abs(fMid) < TOLERANCE || (high - low) / 2 < TOLERANCE) {
        return ok(new RequiredReturn({ monthly: mid }));
      }
      if (fMid < 0) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return ok(new RequiredReturn({ monthly: (low + high) / 2 }));
  },
};
