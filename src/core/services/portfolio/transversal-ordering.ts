import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DartEnum } from '../../lang/dart-enum';
import { DateTime } from '../../lang/date-time';
import { clamp } from '../../lang/num';
import { reduce } from '../../lang/iter';
import { PointInTimeView } from '../../time/point-in-time-view';
import { Inference } from '../valuation/inference';

/**
 * A ordenação que decide o prêmio do retorno esperado (item B1).
 *
 * **O preço justo continua sendo a entrega da tela de avaliação, e o prêmio do
 * retorno esperado sai de uma ordenação medida** — ver
 * `docs/validacao/ordenacao_lado_a_lado.md`.
 */
export class TransversalOrdering extends DartEnum {
  /** Média dos escores robustos do potencial, do book-to-market e do lucro sobre o preço. */
  static readonly composite = new TransversalOrdering('composite', 0);

  /** O valor patrimonial sobre o valor de mercado. */
  static readonly bookToMarket = new TransversalOrdering('bookToMarket', 1);

  /** O potencial do valuation. */
  static readonly potential = new TransversalOrdering('potential', 2);

  static readonly values: readonly TransversalOrdering[] = [
    TransversalOrdering.composite,
    TransversalOrdering.bookToMarket,
    TransversalOrdering.potential,
  ];

  protected get typeName(): string {
    return 'TransversalOrdering';
  }
}

/** Os sinais de um ativo que a ordenação transversal lê. */
export class TransversalSignals {
  /** Potencial do valuation, `justo ÷ preço − 1`. */
  readonly potential: number | null;

  /** Patrimônio líquido do último exercício publicado sobre o valor de mercado. */
  readonly bookToMarket: number | null;

  /** Lucro líquido do último exercício publicado sobre o valor de mercado. */
  readonly earningsYield: number | null;

  constructor(args: { potential?: number | null; bookToMarket?: number | null; earningsYield?: number | null } = {}) {
    this.potential = args.potential ?? null;
    this.bookToMarket = args.bookToMarket ?? null;
    this.earningsYield = args.earningsYield ?? null;
  }

  /**
   * Os sinais do último exercício publicado até [asOf] em [history], e o
   * [potential] da avaliação. A data entra por parâmetro, e só na falta dela
   * vale a de hoje: o núcleo é determinístico.
   */
  static fromHistory(
    history: readonly FundamentalsSnapshot[],
    options: { asOf?: DateTime | null; potential?: number | null } = {},
  ): TransversalSignals {
    const today = options.asOf ?? DateTime.now();
    const published = new PointInTimeView(today).published(history);
    return TransversalSignals.of(published.length === 0 ? null : published[published.length - 1]!, {
      potential: options.potential ?? null,
    });
  }

  /**
   * Os sinais do último exercício publicado, e o [potential] da avaliação.
   * Sem valor de mercado positivo não há nenhum dos dois.
   */
  static of(latest: FundamentalsSnapshot | null, options: { potential?: number | null } = {}): TransversalSignals {
    const marketValue = latest?.marketCap ?? null;
    const hasMarketValue = marketValue !== null && Number.isFinite(marketValue) && marketValue > 0;
    const pl = latest?.equityBookValue ?? null;
    const profit = latest?.netIncome ?? null;
    return new TransversalSignals({
      potential: options.potential ?? null,
      bookToMarket: hasMarketValue && pl !== null && Number.isFinite(pl) ? pl / marketValue : null,
      earningsYield: hasMarketValue && profit !== null && Number.isFinite(profit) ? profit / marketValue : null,
    });
  }
}

/**
 * Escores da ordenação transversal, em desvios robustos confinados.
 *
 * **A escala é a do retorno esperado desde a decisão 58**: `(x − mediana) ÷
 * MAD`, confinado a ±[cap]. O composto é a média dos escores dos sinais que o
 * ativo tem, com pesos iguais.
 */
export const TransversalScore = {
  /** Teto do escore, em desvios robustos. */
  cap: 2.0,

  /**
   * Escore robusto de cada valor contra a seção formada pelos próprios
   * valores. Seção sem escala estimável dá zero a todos.
   */
  robustZ<K>(values: ReadonlyMap<K, number>): Map<K, number> {
    const finite = new Map<K, number>();
    for (const [k, v] of values) if (Number.isFinite(v)) finite.set(k, v);
    const crossSection = [...finite.values()];
    const center = Inference.median(crossSection);
    const scale = Inference.scaledMad(crossSection);
    const noScale = center === null || scale === null || scale <= 0;
    const out = new Map<K, number>();
    for (const [k, v] of finite) {
      out.set(
        k,
        noScale ? 0.0 : clamp((v - center!) / scale!, -TransversalScore.cap, TransversalScore.cap),
      );
    }
    return out;
  },

  /**
   * O escore de cada ativo pela [ordering], contra a seção dos próprios
   * [signals]. Ativo sem o sinal que a ordenação pede fica fora do mapa.
   */
  scores<K>(signals: ReadonlyMap<K, TransversalSignals>, ordering: TransversalOrdering): Map<K, number> {
    const byField = (field: (s: TransversalSignals) => number | null): Map<K, number> => {
      const m = new Map<K, number>();
      for (const [k, s] of signals) {
        const v = field(s);
        if (v !== null) m.set(k, v);
      }
      return m;
    };
    const upsideZ = TransversalScore.robustZ(byField((s) => s.potential));
    const zBm = TransversalScore.robustZ(byField((s) => s.bookToMarket));
    switch (ordering) {
      case TransversalOrdering.potential:
        return upsideZ;
      case TransversalOrdering.bookToMarket:
        return zBm;
      default: {
        const zEy = TransversalScore.robustZ(byField((s) => s.earningsYield));
        const out = new Map<K, number>();
        for (const k of signals.keys()) {
          const zs = [upsideZ.get(k), zBm.get(k), zEy.get(k)].filter((z): z is number => z !== undefined);
          if (zs.length === 0) continue;
          out.set(k, reduce(zs, (a, b) => a + b) / zs.length);
        }
        return out;
      }
    }
  },
};
