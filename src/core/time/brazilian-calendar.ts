/**
 * Calendário de dias úteis do mercado brasileiro, para taxas na base 252.
 *
 * **Por que existe.** A taxa dos títulos prefixados é efetiva anual na base de
 * 252 dias úteis: `PU = 1000 ÷ (1 + taxa)^(du ÷ 252)`. Medir o prazo em dias
 * corridos e dividir por 365,25 descasa prazo e taxa — pouco no prazo longo,
 * e bastante no curto, onde um Carnaval inteiro cabe no vértice.
 *
 * **Conferido contra o preço.** Em 14/09/2026, sobre as 19.171 cotações de LTN
 * desde 2010, o `du` deste calendário bateu **ao dia em 99,13%**.
 *
 * **Duas regras que a conferência ensinou**, e sem as quais a taxa de acerto
 * era de 83,9%:
 *
 * 1. **O calendário é o conhecido na data.** O Dia da Consciência Negra virou
 *    feriado nacional pela Lei 14.759, de 21/12/2023. [knownAt] reproduz isso.
 * 2. **O prazo conta da liquidação**, no dia útil seguinte à data-base, e a
 *    liquidação não acontece em 24/12 nem em 31/12.
 *
 * Só feriados **nacionais**, que são os que o calendário da ANBIMA usa para
 * título público.
 */

import { DateTime } from '../lang/date-time';
import { intDiv, mod } from '../lang/num';

const SATURDAY = 6;
const SUNDAY = 7;

const byYear = new Map<number, Set<number>>();
const byYearWithoutBlackConsciousness = new Map<number, Set<number>>();

function key(d: DateTime): number {
  return d.year * 10000 + d.month * 100 + d.day;
}

function day(d: DateTime): DateTime {
  return DateTime.utc(d.year, d.month, d.day);
}

function holidays(year: number, withBlackConsciousness: boolean): Set<number> {
  const cache = withBlackConsciousness ? byYear : byYearWithoutBlackConsciousness;
  const cached = cache.get(year);
  if (cached !== undefined) return cached;
  const p = BrazilianCalendar.easter(year);
  const rel = (days: number): DateTime => DateTime.utc(p.year, p.month, p.day + days);
  const set = new Set<number>([
    key(DateTime.utc(year, 1, 1)), // Confraternização Universal
    key(rel(-48)), // Carnaval, segunda
    key(rel(-47)), // Carnaval, terça
    key(rel(-2)), // Sexta-feira da Paixão
    key(DateTime.utc(year, 4, 21)), // Tiradentes
    key(DateTime.utc(year, 5, 1)), // Dia do Trabalho
    key(rel(60)), // Corpus Christi
    key(DateTime.utc(year, 9, 7)), // Independência
    key(DateTime.utc(year, 10, 12)), // Nossa Senhora Aparecida
    key(DateTime.utc(year, 11, 2)), // Finados
    key(DateTime.utc(year, 11, 15)), // Proclamação da República
  ]);
  if (withBlackConsciousness && year >= 2024) set.add(key(DateTime.utc(year, 11, 20))); // Consciência Negra
  set.add(key(DateTime.utc(year, 12, 25))); // Natal
  cache.set(year, set);
  return set;
}

/** Dias úteis no calendário nacional. */
export const BrazilianCalendar = {
  /**
   * A partir de quando o 20 de novembro é feriado conhecido. A lei é de
   * 21/12/2023; o preço do Tesouro de 22/12/2023 ainda não o descontava, e o
   * de 26/12/2023 já.
   */
  blackConsciousnessKnownSince: DateTime.utc(2023, 12, 26),

  /** Domingo de Páscoa, pelo algoritmo anônimo do calendário gregoriano. */
  easter(year: number): DateTime {
    const a = mod(year, 19);
    const b = intDiv(year, 100);
    const c = mod(year, 100);
    const d = intDiv(b, 4);
    const e = mod(b, 4);
    const f = intDiv(b + 8, 25);
    const g = intDiv(b - f + 1, 3);
    const h = mod(19 * a + b - d - g + 15, 30);
    const i = intDiv(c, 4);
    const k = mod(c, 4);
    const l = mod(32 + 2 * e + 2 * i - h - k, 7);
    const m = intDiv(a + 11 * h + 22 * l, 451);
    const month = intDiv(h + l - 7 * m + 114, 31);
    const dayOfMonth = mod(h + l - 7 * m + 114, 31) + 1;
    return DateTime.utc(year, month, dayOfMonth);
  },

  /** `true` quando [d] é dia útil no calendário conhecido em [knownAt]. Sem ele, vale o de hoje. */
  isBusinessDay(d0: DateTime, options: { knownAt?: DateTime | null } = {}): boolean {
    const d = day(d0);
    if (d.weekday === SATURDAY || d.weekday === SUNDAY) return false;
    const knownAt = options.knownAt ?? null;
    const withBlackConsciousness =
      knownAt === null || !day(knownAt).isBefore(BrazilianCalendar.blackConsciousnessKnownSince);
    return !holidays(d.year, withBlackConsciousness).has(key(d));
  },

  /** Dias úteis em `[from, to)` — o primeiro conta, o último não. */
  businessDaysBetween(from: DateTime, to: DateTime, options: { knownAt?: DateTime | null } = {}): number {
    const start = day(from);
    const end = day(to);
    let n = 0;
    for (let d = start; d.isBefore(end); d = DateTime.utc(d.year, d.month, d.day + 1)) {
      if (BrazilianCalendar.isBusinessDay(d, options)) n++;
    }
    return n;
  },

  /**
   * Liquidação de um título público negociado em [tradeDate]: o dia útil
   * seguinte, pulando 24/12 e 31/12, em que a B3 não liquida.
   */
  treasurySettlement(tradeDate: DateTime): DateTime {
    return BrazilianCalendar.nextTradingSession(tradeDate);
  },

  /** `true` quando a B3 abre em [d]: dia útil que não é 24/12 nem 31/12. */
  isTradingDay(d0: DateTime, options: { knownAt?: DateTime | null } = {}): boolean {
    const d = day(d0);
    if (d.month === 12 && (d.day === 24 || d.day === 31)) return false;
    return BrazilianCalendar.isBusinessDay(d, options);
  },

  /** Primeiro pregão depois de [d] — a data ex de quem tem data-com em [d]. */
  nextTradingSession(d0: DateTime): DateTime {
    let d = day(d0);
    do {
      d = DateTime.utc(d.year, d.month, d.day + 1);
    } while (!BrazilianCalendar.isTradingDay(d, { knownAt: d0 }));
    return d;
  },
};
