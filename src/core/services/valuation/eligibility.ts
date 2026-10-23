/** Porta 0 — elegibilidade e integridade contábil. */

import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import type { PriceSeries } from '../../entities/price-series';
import { DartEnum } from '../../lang/dart-enum';
import { Inference } from './inference';

/** Por que um ativo não é avaliável. */
export class IneligibilityReason extends DartEnum {
  /** Volume financeiro médio abaixo do corte. */
  static readonly illiquid = new IneligibilityReason('illiquid', 0);

  /** Exercícios publicados de menos para qualquer inferência. */
  static readonly shortHistory = new IneligibilityReason('shortHistory', 1);

  /** Patrimônio líquido não positivo de forma persistente. */
  static readonly insolvent = new IneligibilityReason('insolvent', 2);

  /** Continuidade formalmente suspensa. */
  static readonly distressed = new IneligibilityReason('distressed', 3);

  static readonly values: readonly IneligibilityReason[] = [
    IneligibilityReason.illiquid,
    IneligibilityReason.shortHistory,
    IneligibilityReason.insolvent,
    IneligibilityReason.distressed,
  ];

  protected get typeName(): string {
    return 'IneligibilityReason';
  }

  /**
   * Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a
   * decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na
   * apresentação (decisão 125).
   */
  get diagnostic(): string {
    switch (this) {
      case IneligibilityReason.illiquid:
        return 'liquidez insuficiente para formar preço confiável';
      case IneligibilityReason.shortHistory:
        return 'histórico curto demais para os testes das guardas';
      case IneligibilityReason.insolvent:
        return 'patrimônio líquido não positivo em exercícios consecutivos';
      default:
        return 'em recuperação judicial ou extrajudicial';
    }
  }
}

/** Veredito da Porta 0. */
export class EligibilityVerdict {
  /** `true` quando o ativo pode ser avaliado. */
  readonly isEligible: boolean;

  /** Motivos de recusa, em ordem de verificação. Vazio quando elegível. */
  readonly reasons: readonly IneligibilityReason[];

  /** Volume financeiro diário mediano medido, em reais. `null` sem série. */
  readonly averageDailyTradedValue: number | null;

  /** Exercícios publicados considerados. */
  readonly publishedPeriods: number;

  constructor(args: {
    isEligible: boolean;
    reasons: readonly IneligibilityReason[];
    publishedPeriods: number;
    averageDailyTradedValue?: number | null;
  }) {
    this.isEligible = args.isEligible;
    this.reasons = args.reasons;
    this.publishedPeriods = args.publishedPeriods;
    this.averageDailyTradedValue = args.averageDailyTradedValue ?? null;
  }

  /**
   * Diagnóstico técnico da recusa, ou `null` quando elegível — é o que vai
   * para a falha e para o rastro. A tela lê [reasons].
   */
  get message(): string | null {
    if (this.isEligible) return null;
    return `Ativo fora do universo analisável: ${this.reasons.map((r) => r.diagnostic).join('; ')}.`;
  }
}

/**
 * Patrimônio não positivo no exercício mais recente **e** no anterior.
 *
 * Dois consecutivos, e não um: um exercício isolado de patrimônio negativo é
 * evento a normalizar, e a Porta 2 tem mecanismo para isso. Persistente é
 * outra coisa — sem base de capital não há ROE, ROIC, retenção nem
 * crescimento fundamental, e as duas vias perdem o denominador.
 */
function insolvent(s: readonly FundamentalsSnapshot[]): boolean {
  if (s.length < 2) return false;
  const lastValue = s[s.length - 1]!.equityBookValue;
  const penultimate = s[s.length - 2]!.equityBookValue;
  const bad = (v: number | null): boolean => v === null || v <= 0;
  return bad(lastValue) && bad(penultimate);
}

/**
 * Filtra o universo antes de qualquer decisão de modelo.
 *
 * **Por que existe.** Os parâmetros das guardas foram calibrados sobre dezoito
 * ativos cujo volume financeiro diário mediano vai de R$ 36,6 mi a
 * R$ 1.541,9 mi. A mediana do universo negociável da B3 é de R$ 9,2 mi e o
 * primeiro quartil, R$ 1,9 mi — a amostra está inteira no decil superior de
 * liquidez. A Porta 0 torna essa fronteira explícita em vez de extrapolá-la em
 * silêncio (decisão 25).
 */
export const EligibilityGate = {
  /**
   * P1 — volume financeiro diário mediano mínimo, em reais.
   *
   * Com este corte, 161 dos 382 papéis-base da B3 permanecem analisáveis.
   *
   * **O que ele protege.** Pregão sem formação de preço gera retorno zero
   * espúrio, que enviesa o beta para baixo por negociação não sincronizada —
   * `β̂ → β(1 − θ)` com fração `θ` de pregões vazios. Beta menor reduz Ke e
   * WACC e **infla** o preço justo: é o pior sentido possível de erro.
   */
  minAverageDailyTradedValue: 2000000.0,

  /** Pregões da janela de liquidez. */
  liquidityWindowDays: 90,

  /**
   * P2 — exercícios publicados mínimos.
   *
   * Oito dá seis graus de liberdade, e é o menor `n` em que a janela de ciclo
   * de oito anos ainda existe. Abaixo disso o teste de tendência não tem poder:
   * com `n = 6`, só uma tendência que explique 53% da variância é detectável.
   */
  minPublishedPeriods: 8,

  /**
   * Avalia a elegibilidade de um ativo.
   *
   * - [snapshots]: exercícios **já filtrados por publicação**.
   * - [prices]: série de cotações; sem volume, o teste de liquidez é omitido
   *   em vez de reprovar — cache antigo não tem a coluna, e recusar por dado
   *   ausente confundiria falta de informação com falta de liquidez.
   * - [isDistressed]: veio de lista externa. A fonte não publica situação de
   *   recuperação judicial, e `isActive` marca negociabilidade, não
   *   continuidade — os 786 tickers vêm todos com `isActive = true`.
   */
  assess(args: {
    snapshots: readonly FundamentalsSnapshot[];
    prices?: PriceSeries | null;
    isDistressed?: boolean;
    minTradedValue?: number;
    minPeriods?: number;
  }): EligibilityVerdict {
    const { snapshots } = args;
    const prices = args.prices ?? null;
    const minTradedValue = args.minTradedValue ?? EligibilityGate.minAverageDailyTradedValue;
    const minPeriods = args.minPeriods ?? EligibilityGate.minPublishedPeriods;
    const reasons: IneligibilityReason[] = [];

    const adtv = prices === null ? null : EligibilityGate.medianTradedValue(prices);
    if (adtv !== null && adtv < minTradedValue) {
      reasons.push(IneligibilityReason.illiquid);
    }

    if (snapshots.length < minPeriods) {
      reasons.push(IneligibilityReason.shortHistory);
    }

    if (insolvent(snapshots)) {
      reasons.push(IneligibilityReason.insolvent);
    }

    if (args.isDistressed ?? false) {
      reasons.push(IneligibilityReason.distressed);
    }

    return new EligibilityVerdict({
      isEligible: reasons.length === 0,
      reasons,
      publishedPeriods: snapshots.length,
      averageDailyTradedValue: adtv,
    });
  },

  /**
   * Volume financeiro diário **mediano** dos últimos pregões.
   *
   * Mediana e não média: um leilão de bloco isolado distorce a média, e é
   * exatamente o caso que o corte quer excluir.
   *
   * Devolve `null` quando a série não traz volume ou é curta demais para a
   * janela — ausência de dado, que o chamador trata como omissão do teste, não
   * como reprovação.
   */
  medianTradedValue(series: PriceSeries, options: { window?: number } = {}): number | null {
    const window = options.window ?? EligibilityGate.liquidityWindowDays;
    const points = series.points;
    if (points.length < 20) return null;

    const ini = points.length > window ? points.length - window : 0;
    const tradedValue: number[] = [];
    for (let i = ini; i < points.length; i++) {
      const v = points[i]!.volume;
      if (v === null || v < 0) continue;
      tradedValue.push(points[i]!.close * v);
    }
    if (tradedValue.length < 20) return null;
    return Inference.median(tradedValue);
  },
};
