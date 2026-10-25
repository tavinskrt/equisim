import { DateTime, Duration } from '../lang/date-time';
import type { FundamentalsSnapshot } from '../entities/fundamentals';

/**
 * Recorte temporal que impede o uso de informação ainda não publicada.
 *
 * Um balanço encerrado em 31/12/2025 não estava disponível ao público em
 * 15/01/2026 — a divulgação à CVM leva meses. Consultar a série completa e
 * filtrar "na mão" funciona até alguém esquecer; por isso o filtro vive aqui,
 * e o motor recebe esta visão em vez da série bruta.
 */
export class PointInTimeView {
  /** Data de referência da análise. */
  readonly asOf: DateTime;

  /**
   * Defasagem **presumida** entre o encerramento do exercício e sua
   * divulgação, usada apenas quando o exercício não traz a data real.
   */
  readonly publicationLag: Duration;

  constructor(asOf: DateTime, options: { publicationLag?: Duration } = {}) {
    this.asOf = DateTime.local(asOf.year, asOf.month, asOf.day);
    this.publicationLag = options.publicationLag ?? PointInTimeView.defaultLag;
  }

  /**
   * 90 dias — parâmetro declarado da metodologia. **É conservador, e agora
   * se sabe quanto**: a defasagem real tem mediana de **78 dias** no
   * documento anual e de **40 dias** no trimestral.
   */
  static readonly defaultLag = new Duration({ days: 90 });

  /** Data-limite de encerramento de exercício **presumido** público em [asOf]. */
  get cutoff(): DateTime {
    return this.asOf.subtract(this.publicationLag);
  }

  /**
   * Verdadeiro se o exercício já era público na data de referência.
   * **Prefere a data observada**; sem ela, recua para [cutoff].
   */
  isPublished(snapshot: FundamentalsSnapshot): boolean {
    const received = snapshot.receiptDate;
    if (received !== null) return !PointInTimeView.isAfter(received, this.asOf);
    return !PointInTimeView.isAfter(snapshot.fiscalPeriodEnd, this.cutoff);
  }

  /**
   * `a` é um dia civil posterior a `b`? **Compara ano, mês e dia, e nunca
   * instantes** — local e UTC do mesmo dia civil são instantes distintos.
   */
  private static isAfter(a: DateTime, b: DateTime): boolean {
    if (a.year !== b.year) return a.year > b.year;
    if (a.month !== b.month) return a.month > b.month;
    return a.day > b.day;
  }

  /** Subconjunto já divulgado, em ordem cronológica. */
  published(all: readonly FundamentalsSnapshot[]): FundamentalsSnapshot[] {
    return all
      .filter((s) => this.isPublished(s))
      .sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
  }
}
