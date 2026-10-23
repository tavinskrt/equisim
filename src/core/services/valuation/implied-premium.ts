/**
 * O prêmio de risco de mercado implícito no preço da bolsa, e a média de dez
 * anos dele, que é o prêmio do CAPM do motor (decisão 142).
 *
 * **De onde vem.** Em cada fim de trimestre, o valor de mercado somado das
 * companhias listadas é igualado ao dinheiro que elas distribuem — dividendos e
 * juros sobre capital próprio dos doze meses —, crescendo com a economia
 * nominal: `r = rendimento × (1 + g) + g` (Gordon; o método de Damodaran, com
 * os dois estágios no mesmo `g` por falta de consenso de analistas). `r` é o
 * retorno que o preço embute. O prêmio do trimestre é `r` menos o prefixado de
 * dez anos da curva do Tesouro na mesma data. A série é medida fora do
 * aplicativo (`tool/implied-premium.ts`), que não tem como somar a bolsa
 * inteira para avaliar um ativo, e chega por pacote.
 *
 * **Por que a média de dez anos, e não o trimestre.** O implícito do
 * trimestre fica negativo quando o prefixado dispara — em 2015, em 2024 e em
 * 2026 —, e prêmio negativo faz o beta alto baratear o capital. A média de dez
 * anos fica positiva em todas as datas do backtest, entre 1% e 1,6%, e concorda
 * com o prêmio histórico de dez anos do Ibovespa contra o CDI
 * (`docs/validacao/premio_implicito.md`).
 *
 * **Por que `r − Rf`, e não Fisher.** O CAPM do motor soma:
 * `Ke = Rf + β × prêmio`. O prêmio que, somado à taxa livre de risco, devolve o
 * retorno que o preço embute para beta 1 é a diferença, e não a razão
 * `(1 + r) ÷ (1 + Rf) − 1`, que é a mesma grandeza dividida por `1 + Rf`.
 */

import { DateTime } from '../../lang/date-time';
import { asDouble, interpolateJson, isJsonObject, type JsonObject } from '../../lang/json';

/** Um trimestre da série do prêmio implícito. */
export class ImpliedPremiumQuarter {
  /** Último dia do trimestre, em UTC. */
  readonly date: DateTime;

  /** Retorno que o preço da bolsa embute, `r`, em fração ao ano. */
  readonly impliedReturn: number;

  /** Prefixado de dez anos da curva do Tesouro na data, em fração ao ano. */
  readonly riskFree: number;

  constructor(args: { date: DateTime; impliedReturn: number; riskFree: number }) {
    this.date = args.date;
    this.impliedReturn = args.impliedReturn;
    this.riskFree = args.riskFree;
  }

  /** O prêmio do trimestre na forma que o CAPM do motor soma, `r − Rf`. */
  get premium(): number {
    return this.impliedReturn - this.riskFree;
  }
}

/** A série trimestral do prêmio implícito, como o pacote a traz. */
export class ImpliedPremiumPackage {
  /** Data em que a série foi medida. */
  readonly generatedAt: DateTime;

  /** Os trimestres, em ordem de data. */
  readonly quarters: readonly ImpliedPremiumQuarter[];

  /** Anos da média. */
  static readonly windowYears = 10;

  /**
   * Trimestres mínimos dentro da janela para a média valer.
   *
   * **Vinte, metade da janela.** A série começa em 2011, e as coortes do
   * backtest de 2018 têm de 29 a 31 trimestres atrás de si: com o mínimo de
   * quarenta, elas não teriam prêmio. Com vinte, a média dessas datas é a dos
   * trimestres que havia, e a partir de 31/12/2020 a janela está cheia.
   */
  static readonly minQuarters = 20;

  constructor(args: { generatedAt: DateTime; quarters: readonly ImpliedPremiumQuarter[] }) {
    this.generatedAt = args.generatedAt;
    this.quarters = args.quarters;
  }

  /** Os trimestres que entram na média de [asOf]: fim em `(asOf − dez anos, asOf]`. */
  window(asOf: DateTime): ImpliedPremiumQuarter[] {
    const end = DateTime.utc(asOf.year, asOf.month, asOf.day);
    const start = DateTime.utc(asOf.year - ImpliedPremiumPackage.windowYears, asOf.month, asOf.day);
    return this.quarters.filter((q) => q.date.isAfter(start) && !q.date.isAfter(end));
  }

  /**
   * A média de dez anos do prêmio implícito até [asOf], ou `null` com menos
   * de [minQuarters] trimestres na janela.
   */
  normalizedAt(asOf: DateTime): number | null {
    const windowQuarters = this.window(asOf);
    if (windowQuarters.length < ImpliedPremiumPackage.minQuarters) return null;
    let sum = 0.0;
    for (const q of windowQuarters) {
      sum += q.premium;
    }
    return sum / windowQuarters.length;
  }
}

function day(d: DateTime): string {
  return d.toIso8601String().substring(0, 10);
}

/** Serialização da série do prêmio implícito. */
export const ImpliedPremiumCodec = {
  /** Versão do formato. */
  version: 1,

  /** Grava o pacote. */
  encode(pkg: ImpliedPremiumPackage): JsonObject {
    return {
      versao: ImpliedPremiumCodec.version,
      geradoEm: day(pkg.generatedAt),
      trimestres: pkg.quarters.map((q) => ({
        data: day(q.date),
        retornoImplicito: q.impliedReturn,
        prefixado10: q.riskFree,
      })),
    };
  },

  /**
   * Lê o pacote, ou devolve `null` quando ele não é utilizável.
   *
   * Recusa em vez de adivinhar: versão diferente, data ilegível, trimestre
   * com número não finito ou série vazia devolvem `null`, e quem chama segue
   * com o prêmio parametrizado — declarado.
   */
  decode(pkg: JsonObject): ImpliedPremiumPackage | null {
    if (pkg['versao'] !== ImpliedPremiumCodec.version) return null;
    const generated = DateTime.tryParse(interpolateJson(pkg['geradoEm']));
    const list = pkg['trimestres'];
    if (generated === null || !Array.isArray(list) || list.length === 0) return null;
    const quarters: ImpliedPremiumQuarter[] = [];
    for (const item of list) {
      if (!isJsonObject(item)) return null;
      const date = DateTime.tryParse(interpolateJson(item['data']));
      const r = asDouble(item['retornoImplicito']);
      const rf = asDouble(item['prefixado10']);
      if (date === null || r === null || rf === null) return null;
      if (!Number.isFinite(r) || !Number.isFinite(rf)) return null;
      quarters.push(
        new ImpliedPremiumQuarter({
          date: DateTime.utc(date.year, date.month, date.day),
          impliedReturn: r,
          riskFree: rf,
        }),
      );
    }
    quarters.sort((a, b) => a.date.compareTo(b.date));
    return new ImpliedPremiumPackage({
      generatedAt: DateTime.utc(generated.year, generated.month, generated.day),
      quarters: Object.freeze(quarters),
    });
  },
};
