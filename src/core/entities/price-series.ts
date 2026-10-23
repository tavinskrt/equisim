import { DateTime } from '../lang/date-time';
import { intDiv } from '../lang/num';
import type { Ticker } from '../value-objects/ticker';

/**
 * Cotação de fechamento de um pregão.
 *
 * [close] vem ajustado por desdobramentos e grupamentos, mas **não** por
 * proventos (convenção Yahoo, verificada em BBAS3 15/04/2024 e WEGE3
 * 27/04/2021 — nenhuma descontinuidade nas datas-ex de split).
 *
 * **Nem por toda bonificação** (item B29, decisão 136): das mudanças de
 * contagem com salto no preço bruto, a fonte deixou 133 sem ajuste. Quem lê a
 * série para beta, volatilidade ou retorno a completa antes, com os eventos
 * declarados (`CorporateEvents.completeAdjustment` e `applyToSeries`).
 *
 * [adjustedClose] é série de retorno total, porém **subajusta proventos
 * brasileiros** — não deve ser usada em cálculo, apenas conferência.
 */
export class PricePoint {
  /** Dia do pregão, truncado para meia-noite local. */
  readonly date: DateTime;

  /** Fechamento ajustado por desdobramento e grupamento, em reais. */
  readonly close: number;

  /**
   * Volume negociado no pregão, em quantidade de papéis. `null` quando a fonte
   * não informa. Serve à Porta 0 (decisão 25). **Não entra em cálculo de retorno.**
   */
  readonly volume: number | null;

  /** Fechamento ajustado também por proventos. **Não use em cálculo.** */
  readonly adjustedClose: number | null;

  /** Constrói o ponto, truncando [date] para o dia. */
  constructor(args: { date: DateTime; close: number; adjustedClose?: number | null; volume?: number | null }) {
    this.date = DateTime.local(args.date.year, args.date.month, args.date.day);
    this.close = args.close;
    this.adjustedClose = args.adjustedClose ?? null;
    this.volume = args.volume ?? null;
  }
}

/** Série histórica de preços de um ativo, ordenada cronologicamente. */
export class PriceSeries {
  /** Ativo a que a série pertence. */
  readonly ticker: Ticker;

  /** Pontos em ordem cronológica crescente. **Imutável.** */
  readonly points: readonly PricePoint[];

  private byDateCache: Map<number, number> | null = null;

  /**
   * Constrói a série ordenando os pontos por data e congelando a lista.
   *
   * Ordenar na construção é o que autoriza a busca binária de [closeAsOf].
   * Datas repetidas não são removidas: sobrevivem as duas, e o índice de
   * [closeOn] fica com a última. Complexidade O(n log n).
   */
  constructor(args: { ticker: Ticker; points: readonly PricePoint[] }) {
    this.ticker = args.ticker;
    this.points = Object.freeze([...args.points].sort((a, b) => a.date.compareTo(b.date)));
  }

  /** `true` quando não há nenhum pregão na série. */
  get isEmpty(): boolean {
    return this.points.length === 0;
  }

  /** Data do primeiro pregão. Lança se a série estiver vazia. */
  get firstDate(): DateTime {
    const p = this.points[0];
    if (p === undefined) throw new Error('Bad state: No element');
    return p.date;
  }

  /** Índice por data, construído sob demanda. */
  private get byDate(): Map<number, number> {
    if (this.byDateCache === null) {
      const m = new Map<number, number>();
      for (const p of this.points) m.set(p.date.millisecondsSinceEpoch, p.close);
      this.byDateCache = m;
    }
    return this.byDateCache;
  }

  /**
   * Fechamento **exatamente** na data pedida. Devolve `null` quando não houve
   * pregão nesse dia. Para o último preço conhecido, use [closeAsOf].
   */
  closeOn(date: DateTime): number | null {
    return this.byDate.get(DateTime.local(date.year, date.month, date.day).millisecondsSinceEpoch) ?? null;
  }

  /**
   * Último fechamento conhecido em ou antes de [date] — *forward fill*.
   *
   * Devolve `null` apenas quando [date] é anterior ao primeiro pregão da
   * série. **Nunca olha para frente**, o que é o que impede a simulação de usar
   * preço futuro. Complexidade O(log n).
   */
  closeAsOf(date: DateTime): number | null {
    const target = DateTime.local(date.year, date.month, date.day);
    const direct = this.byDate.get(target.millisecondsSinceEpoch);
    if (direct !== undefined) return direct;

    let lo = 0;
    let hi = this.points.length - 1;
    let best: number | null = null;
    while (lo <= hi) {
      const mid = intDiv(lo + hi, 2);
      if (!this.points[mid]!.date.isAfter(target)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best === null ? null : this.points[best]!.close;
  }

  /** Datas dos pregões, em ordem cronológica. Constrói uma lista nova a cada chamada. */
  get dates(): DateTime[] {
    return this.points.map((p) => p.date);
  }
}
