import { ArgumentError } from '../lang/num';
import { DateTime } from '../lang/date-time';

/**
 * Intervalo de datas fechado em ambas as pontas.
 *
 * Ambas as pontas são **truncadas para o dia** na construção: hora, minuto e
 * fuso são descartados. É o que torna a comparação com datas de pregão e de
 * divulgação estável, sem depender de o chamador ter normalizado.
 */
export class DateRange {
  /** Primeiro dia do intervalo, à meia-noite local. */
  readonly start: DateTime;

  /** Último dia do intervalo, à meia-noite local. Pertence ao intervalo. */
  readonly end: DateTime;

  /**
   * Constrói o intervalo truncando as duas datas para o dia.
   *
   * Lança [ArgumentError] se, **depois do truncamento**, `end` for anterior a
   * `start`. Um intervalo de um único dia (`start == end`) é válido e tem
   * [days] igual a zero.
   */
  constructor(start: DateTime, end: DateTime) {
    this.start = DateTime.local(start.year, start.month, start.day);
    this.end = DateTime.local(end.year, end.month, end.day);
    if (this.end.isBefore(this.start)) {
      throw new ArgumentError(`Data final (${end.toString()}) anterior à inicial (${start.toString()}).`);
    }
  }

  /**
   * Dias decorridos entre as pontas.
   *
   * É a **diferença**, não a contagem de dias contidos: um intervalo de um
   * único dia devolve `0`, e `01/01` a `02/01` devolve `1`.
   */
  get days(): number {
    return this.end.difference(this.start).inDays;
  }

  /**
   * Fração de anos, considerando anos bissextos.
   *
   * Usa 365,25 dias por ano — a média do ciclo de quatro anos. É a base de
   * contagem de toda anualização do pacote, e está declarada aqui de propósito
   * para que a escolha seja única e auditável em vez de repetida em cada
   * serviço.
   */
  get years(): number {
    return this.days / 365.25;
  }

  /**
   * `true` se [d] cai dentro do intervalo, com as duas pontas incluídas.
   * [d] é truncada para o dia antes da comparação.
   */
  contains(d: DateTime): boolean {
    const day = DateTime.local(d.year, d.month, d.day);
    return !day.isBefore(this.start) && !day.isAfter(this.end);
  }

  equals(other: unknown): boolean {
    return other instanceof DateRange && other.start.equals(this.start) && other.end.equals(this.end);
  }

  toString(): string {
    return `${DateRange.fmt(this.start)} a ${DateRange.fmt(this.end)}`;
  }

  private static fmt(d: DateTime): string {
    return `${String(d.day).padStart(2, '0')}/${String(d.month).padStart(2, '0')}/${d.year}`;
  }
}
