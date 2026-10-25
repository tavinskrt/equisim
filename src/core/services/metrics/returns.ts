import { DateTime } from '../../lang/date-time';
import { ComputationFailure, InsufficientData, InvalidInput } from '../../failures/failure';
import { err, ok, type Result } from '../../failures/result';
import type { Money } from '../../value-objects/money';
import type { WealthPath } from '../../value-objects/paired-series';

/**
 * Movimentação externa de capital, datada.
 *
 * Convenção de sinal: aporte é **negativo** (saída do bolso do investidor),
 * resgate e valor final são **positivos**. É a convenção da TIR.
 */
export class CashFlow {
  /** Dia da movimentação, truncado para meia-noite local. */
  readonly date: DateTime;

  /** Valor movimentado. Negativo para aporte, positivo para resgate e valor final. */
  readonly amount: Money;

  constructor(args: { date: DateTime; amount: Money }) {
    this.date = DateTime.local(args.date.year, args.date.month, args.date.day);
    this.amount = args.amount;
  }

  toString(): string {
    return `${this.date.toIso8601String().substring(0, 10)}: ${this.amount.toString()}`;
  }
}

/**
 * Pregões por ano, base de anualização.
 *
 * 252 é a base de dias úteis da B3 e do Banco Central — a mesma em que Selic e
 * CDI são publicados. Conversão entre bases é sempre por composição
 * (`(1+i)^(1/252) − 1`), nunca por divisão.
 */
export const tradingDaysPerYear = 252;

/** Bisseção sobre [f] no intervalo `[lo, hi]`; ver a ressalva em [Returns.extendedIrr]. */
function bisect(
  f: (x: number) => number,
  lo: number,
  hi: number,
  tolerance: number,
  maxIterations: number,
): Result<number> {
  let low = lo;
  let high = hi;
  let fLow = f(low);
  const fHigh = f(high);
  if (Number.isNaN(fLow) || Number.isNaN(fHigh) || fLow * fHigh > 0) {
    return err(
      new ComputationFailure('Não foi possível isolar a raiz: a função não muda de sinal no intervalo.'),
    );
  }
  for (let i = 0; i < maxIterations; i++) {
    const mid = (low + high) / 2.0;
    const fMid = f(mid);
    if (Math.abs(fMid) < tolerance || (high - low) / 2.0 < tolerance) {
      return ok(mid);
    }
    if (fLow * fMid < 0) {
      high = mid;
    } else {
      low = mid;
      fLow = fMid;
    }
  }
  return ok((low + high) / 2.0);
}

/** Métricas de retorno de uma carteira. */
export const Returns = {
  /**
   * **Retorno ponderado pelo tempo (TWR)**.
   *
   * Neutraliza o efeito do cronograma de aportes: é a métrica correta para
   * comparar a qualidade de duas composições de carteira. Para cada período,
   * `r = (V_t − F_t) / V_{t−1} − 1`.
   *
   * Devolve `0.0` para menos de dois períodos. Períodos abertos com patrimônio
   * não positivo são **pulados**, não zerados.
   */
  timeWeighted(path: WealthPath): number {
    const values = path.values;
    const externalFlows = path.externalFlows;
    if (values.length < 2) return 0.0;

    let compounded = 1.0;
    for (let i = 1; i < values.length; i++) {
      const previous = values[i - 1]!;
      if (previous <= 0) continue;
      const periodReturn = (values[i]! - externalFlows[i]!) / previous - 1.0;
      compounded *= 1.0 + periodReturn;
    }
    return compounded - 1.0;
  },

  /**
   * Índice de retorno total normalizado em base 100. É a curva que deve
   * alimentar volatilidade e drawdown — a curva bruta de patrimônio salta no
   * dia do aporte e contaminaria as duas métricas.
   */
  timeWeightedIndex(path: WealthPath, options: { base?: number } = {}): number[] {
    const base = options.base ?? 100.0;
    const values = path.values;
    const externalFlows = path.externalFlows;
    if (values.length === 0) return [];
    const out: number[] = [base];
    let level = base;
    for (let i = 1; i < values.length; i++) {
      const previous = values[i - 1]!;
      if (previous > 0) {
        const periodReturn = (values[i]! - externalFlows[i]!) / previous - 1.0;
        level *= 1.0 + periodReturn;
      }
      out.push(level);
    }
    return out;
  },

  /**
   * Converte um retorno acumulado em taxa anual composta.
   *
   * Devolve `0.0` para [years] não positivo, e `-1.0` (perda total) quando o
   * fator de crescimento `1 + totalReturn` é não positivo.
   */
  annualize(totalReturn: number, years: number): number {
    if (years <= 0) return 0.0;
    const growth = 1.0 + totalReturn;
    if (growth <= 0) return -1.0;
    return Math.pow(growth, 1.0 / years) - 1.0;
  },

  /**
   * **Taxa interna de retorno de fluxos datados (XIRR)**.
   *
   * Resolve `Σ CF_i / (1+r)^(d_i/365) = 0` por Newton-Raphson com bisseção de
   * resguardo em `[-99,99%, 10000%]`. A base de contagem é **365 dias
   * corridos**. Retorna a taxa **anual** em fração.
   *
   * Devolve [InsufficientData] com menos de dois fluxos; [InvalidInput] se
   * faltar fluxo positivo ou negativo; [ComputationFailure] quando a bisseção
   * não consegue isolar a raiz.
   */
  extendedIrr(
    flows: readonly CashFlow[],
    options: { guess?: number; tolerance?: number; maxIterations?: number } = {},
  ): Result<number> {
    const guess = options.guess ?? 0.1;
    const tolerance = options.tolerance ?? 1e-9;
    const maxIterations = options.maxIterations ?? 200;
    if (flows.length < 2) {
      return err(new InsufficientData('XIRR exige ao menos dois fluxos.'));
    }

    const hasPositive = flows.some((f) => f.amount.cents > 0);
    const hasNegative = flows.some((f) => f.amount.cents < 0);
    if (!hasPositive || !hasNegative) {
      return err(new InvalidInput('XIRR exige ao menos um fluxo positivo e um negativo.'));
    }

    const sorted = [...flows].sort((a, b) => a.date.compareTo(b.date));
    const origin = sorted[0]!.date;
    const years = sorted.map((f) => f.date.difference(origin).inDays / 365.0);
    const amounts = sorted.map((f) => f.amount.reais);

    const npv = (rate: number): number => {
      let total = 0.0;
      for (let i = 0; i < amounts.length; i++) {
        total += amounts[i]! / Math.pow(1.0 + rate, years[i]!);
      }
      return total;
    };

    // Newton-Raphson.
    let rate = guess;
    for (let iteration = 0; iteration < maxIterations; iteration++) {
      if (rate <= -1.0) break;
      let value = 0.0;
      let derivative = 0.0;
      for (let i = 0; i < amounts.length; i++) {
        const discount = Math.pow(1.0 + rate, years[i]!);
        value += amounts[i]! / discount;
        derivative -= (years[i]! * amounts[i]!) / (discount * (1.0 + rate));
      }
      if (Math.abs(value) < tolerance) return ok(rate);
      if (Math.abs(derivative) < 1e-14) break;
      const next = rate - value / derivative;
      if (!Number.isFinite(next)) break;
      if (Math.abs(next - rate) < tolerance) return ok(next);
      rate = next;
    }

    // Bisseção de resguardo quando Newton diverge.
    return bisect(npv, -0.9999, 100.0, tolerance, maxIterations);
  },
};
