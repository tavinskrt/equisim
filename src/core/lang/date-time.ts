/**
 * Data e duração com a interface do `DateTime` e do `Duration` do Dart.
 *
 * **O fuso "local" é fixado em UTC para a aritmética.** No Dart, `DateTime(y,
 * m, d)` é meia-noite no fuso do aparelho, e a diferença entre duas datas
 * locais atravessa o horário de verão: no Brasil antes de 2019, a meia-noite do
 * dia da mudança nem existia, e `difference().inDays` podia dar um dia a menos.
 * Era a única dependência do motor em relação ao relógio do aparelho. Aqui a
 * data local é guardada como *relógio de parede* — os campos ano, mês, dia,
 * hora lidos como se fossem UTC — e toda conta (diferença, soma, comparação,
 * dia da semana) é feita sobre esse relógio, sem fuso nem horário de verão. É o
 * comportamento que o motor original tinha num ambiente em UTC, e é o que o
 * torna reprodutível em qualquer fuso (CLAUDE.md, §3.2).
 *
 * O fuso real do aparelho só entra em duas fronteiras de apresentação:
 * [DateTime.now], que lê o relógio de parede do usuário, e [DateTime.toUtc] /
 * [DateTime.toLocal], que convertem para o instante real ao serializar o
 * carimbo de um evento de auditoria.
 */

import { FormatException, intDiv, parseInt_, remainder } from './num';

const MS_PER_SECOND = 1000;
const MS_PER_MINUTE = 60 * MS_PER_SECOND;
const MS_PER_HOUR = 60 * MS_PER_MINUTE;
const MS_PER_DAY = 24 * MS_PER_HOUR;

/** Intervalo de tempo — o `Duration` do Dart, com resolução de milissegundo. */
export class Duration {
  readonly inMilliseconds: number;

  constructor(parts: {
    days?: number;
    hours?: number;
    minutes?: number;
    seconds?: number;
    milliseconds?: number;
  } = {}) {
    this.inMilliseconds =
      (parts.days ?? 0) * MS_PER_DAY +
      (parts.hours ?? 0) * MS_PER_HOUR +
      (parts.minutes ?? 0) * MS_PER_MINUTE +
      (parts.seconds ?? 0) * MS_PER_SECOND +
      (parts.milliseconds ?? 0);
  }

  static readonly zero = new Duration();

  get inDays(): number {
    return intDiv(this.inMilliseconds, MS_PER_DAY);
  }

  get inHours(): number {
    return intDiv(this.inMilliseconds, MS_PER_HOUR);
  }

  get inMinutes(): number {
    return intDiv(this.inMilliseconds, MS_PER_MINUTE);
  }

  get inSeconds(): number {
    return intDiv(this.inMilliseconds, MS_PER_SECOND);
  }

  get inMicroseconds(): number {
    return this.inMilliseconds * 1000;
  }

  get isNegative(): boolean {
    return this.inMilliseconds < 0;
  }

  plus(other: Duration): Duration {
    return new Duration({ milliseconds: this.inMilliseconds + other.inMilliseconds });
  }

  minus(other: Duration): Duration {
    return new Duration({ milliseconds: this.inMilliseconds - other.inMilliseconds });
  }

  times(factor: number): Duration {
    return new Duration({ milliseconds: Math.round(this.inMilliseconds * factor) });
  }

  abs(): Duration {
    return new Duration({ milliseconds: Math.abs(this.inMilliseconds) });
  }

  compareTo(other: Duration): number {
    return this.inMilliseconds < other.inMilliseconds
      ? -1
      : this.inMilliseconds > other.inMilliseconds
        ? 1
        : 0;
  }

  equals(other: unknown): boolean {
    return other instanceof Duration && other.inMilliseconds === this.inMilliseconds;
  }
}

/** Instante de relógio de parede, a partir dos campos, com ano de 0 a 99 respeitado. */
function wallFromFields(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  millisecond: number,
): number {
  const d = new Date(0);
  d.setUTCFullYear(year, month - 1, day);
  d.setUTCHours(hour, minute, second, millisecond);
  return d.getTime();
}

function fourDigits(n: number): string {
  const absN = Math.abs(n);
  const sign = n < 0 ? '-' : '';
  if (absN >= 1000) return `${n}`;
  if (absN >= 100) return `${sign}0${absN}`;
  if (absN >= 10) return `${sign}00${absN}`;
  return `${sign}000${absN}`;
}

function sixDigits(n: number): string {
  const absN = Math.abs(n);
  const sign = n < 0 ? '-' : '+';
  if (absN >= 100000) return `${sign}${absN}`;
  return `${sign}0${absN}`;
}

function threeDigits(n: number): string {
  if (n >= 100) return `${n}`;
  if (n >= 10) return `0${n}`;
  return `00${n}`;
}

function twoDigits(n: number): string {
  if (n >= 10) return `${n}`;
  return `0${n}`;
}

const PARSE_FORMAT =
  /^([+-]?\d{4,6})-?(\d\d)-?(\d\d)(?:[ T](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?( ?[zZ]| ?([-+])(\d\d)(?::?(\d\d))?)?)?$/;

/** Data e hora — o `DateTime` do Dart, ver o cabeçalho do arquivo. */
export class DateTime {
  /** Relógio de parede no fuso da instância, em milissegundos desde 1970 lidos como UTC. */
  private readonly wall: number;

  /** `true` para instância em UTC; `false` para data local (relógio de parede). */
  readonly isUtc: boolean;

  private constructor(wall: number, isUtc: boolean) {
    this.wall = wall;
    this.isUtc = isUtc;
  }

  /** `DateTime(y, m, d, ...)` do Dart: data local, com estouro de campo normalizado. */
  static local(
    year: number,
    month = 1,
    day = 1,
    hour = 0,
    minute = 0,
    second = 0,
    millisecond = 0,
  ): DateTime {
    return new DateTime(wallFromFields(year, month, day, hour, minute, second, millisecond), false);
  }

  /** `DateTime.utc(y, m, d, ...)` do Dart. */
  static utc(
    year: number,
    month = 1,
    day = 1,
    hour = 0,
    minute = 0,
    second = 0,
    millisecond = 0,
  ): DateTime {
    return new DateTime(wallFromFields(year, month, day, hour, minute, second, millisecond), true);
  }

  /**
   * `DateTime.now()` do Dart: o relógio de parede do aparelho.
   *
   * **Metadado de observação ou padrão injetável**, nunca caminho de cálculo
   * direto — o núcleo recebe a data por parâmetro (`asOf ?? DateTime.now()`).
   */
  static now(): DateTime {
    const real = new Date();
    return new DateTime(
      wallFromFields(
        real.getFullYear(),
        real.getMonth() + 1,
        real.getDate(),
        real.getHours(),
        real.getMinutes(),
        real.getSeconds(),
        real.getMilliseconds(),
      ),
      false,
    );
  }

  /** `DateTime.fromMillisecondsSinceEpoch` do Dart, no relógio de parede do fuso fixo. */
  static fromMillisecondsSinceEpoch(ms: number, options: { isUtc?: boolean } = {}): DateTime {
    return new DateTime(ms, options.isUtc ?? false);
  }

  /** `DateTime.parse` do Dart: ISO-8601 e variantes; com fuso explícito vira UTC. */
  static parse(formattedString: string): DateTime {
    const match = PARSE_FORMAT.exec(formattedString);
    if (match === null) {
      throw new FormatException(`Invalid date format: ${formattedString}`);
    }
    const parseIntOrZero = (matched: string | undefined): number =>
      matched === undefined ? 0 : parseInt_(matched);
    const parseMilliAndMicroseconds = (matched: string | undefined): number => {
      if (matched === undefined) return 0;
      let result = 0;
      for (let i = 0; i < 6; i++) {
        result *= 10;
        if (i < matched.length) result += matched.charCodeAt(i) ^ 0x30;
      }
      return result;
    };
    const years = parseInt_(match[1]!);
    const month = parseInt_(match[2]!);
    const day = parseInt_(match[3]!);
    const hour = parseIntOrZero(match[4]);
    let minute = parseIntOrZero(match[5]);
    const second = parseIntOrZero(match[6]);
    const milliAndMicroseconds = parseMilliAndMicroseconds(match[7]);
    const millisecond = intDiv(milliAndMicroseconds, 1000);
    // Microssegundo descartado: a resolução aqui é de milissegundo.
    void remainder(milliAndMicroseconds, 1000);
    let isUtc = false;
    if (match[8] !== undefined) {
      isUtc = true;
      const tzSign = match[9];
      if (tzSign !== undefined) {
        const sign = tzSign === '-' ? -1 : 1;
        const hourDifference = parseInt_(match[10]!);
        let minuteDifference = parseIntOrZero(match[11]);
        minuteDifference += 60 * hourDifference;
        minute -= sign * minuteDifference;
      }
    }
    const wall = wallFromFields(years, month, day, hour, minute, second, millisecond);
    if (!Number.isFinite(wall)) {
      throw new FormatException(`Time out of range: ${formattedString}`);
    }
    return new DateTime(wall, isUtc);
  }

  /** `DateTime.tryParse` do Dart. */
  static tryParse(formattedString: string): DateTime | null {
    try {
      return DateTime.parse(formattedString);
    } catch (e) {
      if (e instanceof FormatException) return null;
      throw e;
    }
  }

  private get fields(): Date {
    return new Date(this.wall);
  }

  get year(): number {
    return this.fields.getUTCFullYear();
  }

  get month(): number {
    return this.fields.getUTCMonth() + 1;
  }

  get day(): number {
    return this.fields.getUTCDate();
  }

  get hour(): number {
    return this.fields.getUTCHours();
  }

  get minute(): number {
    return this.fields.getUTCMinutes();
  }

  get second(): number {
    return this.fields.getUTCSeconds();
  }

  get millisecond(): number {
    return this.fields.getUTCMilliseconds();
  }

  get microsecond(): number {
    return 0;
  }

  /** Dia da semana do Dart: segunda é 1, domingo é 7. */
  get weekday(): number {
    const d = this.fields.getUTCDay();
    return d === 0 ? 7 : d;
  }

  get millisecondsSinceEpoch(): number {
    return this.wall;
  }

  get microsecondsSinceEpoch(): number {
    return this.wall * 1000;
  }

  isBefore(other: DateTime): boolean {
    return this.wall < other.wall;
  }

  isAfter(other: DateTime): boolean {
    return this.wall > other.wall;
  }

  isAtSameMomentAs(other: DateTime): boolean {
    return this.wall === other.wall;
  }

  compareTo(other: DateTime): number {
    return this.wall < other.wall ? -1 : this.wall > other.wall ? 1 : 0;
  }

  /** `==` do Dart: mesmo instante **e** mesma marcação de UTC. */
  equals(other: unknown): boolean {
    return other instanceof DateTime && other.wall === this.wall && other.isUtc === this.isUtc;
  }

  /** Chave de mapa equivalente ao `hashCode`/`==` do Dart. */
  get key(): string {
    return `${this.wall}${this.isUtc ? 'Z' : ''}`;
  }

  difference(other: DateTime): Duration {
    return new Duration({ milliseconds: this.wall - other.wall });
  }

  add(duration: Duration): DateTime {
    return new DateTime(this.wall + duration.inMilliseconds, this.isUtc);
  }

  subtract(duration: Duration): DateTime {
    return new DateTime(this.wall - duration.inMilliseconds, this.isUtc);
  }

  /**
   * O mesmo instante em UTC. Para a data local, a conversão usa o fuso real do
   * aparelho — é fronteira de serialização, nunca de cálculo.
   */
  toUtc(): DateTime {
    if (this.isUtc) return this;
    const real = new Date(
      this.year,
      this.month - 1,
      this.day,
      this.hour,
      this.minute,
      this.second,
      this.millisecond,
    );
    if (this.year >= 0 && this.year < 100) real.setFullYear(this.year);
    return new DateTime(real.getTime(), true);
  }

  /** O mesmo instante no relógio de parede do aparelho. */
  toLocal(): DateTime {
    if (!this.isUtc) return this;
    const real = new Date(this.wall);
    return DateTime.local(
      real.getFullYear(),
      real.getMonth() + 1,
      real.getDate(),
      real.getHours(),
      real.getMinutes(),
      real.getSeconds(),
      real.getMilliseconds(),
    );
  }

  /** `toIso8601String` do Dart: sem `Z` para data local. */
  toIso8601String(): string {
    const year = this.year;
    const y = year >= -9999 && year <= 9999 ? fourDigits(year) : sixDigits(year);
    const m = twoDigits(this.month);
    const d = twoDigits(this.day);
    const h = twoDigits(this.hour);
    const min = twoDigits(this.minute);
    const sec = twoDigits(this.second);
    const ms = threeDigits(this.millisecond);
    return this.isUtc ? `${y}-${m}-${d}T${h}:${min}:${sec}.${ms}Z` : `${y}-${m}-${d}T${h}:${min}:${sec}.${ms}`;
  }

  /** `toString` do Dart: `2024-01-02 00:00:00.000`. */
  toString(): string {
    const y = fourDigits(this.year);
    const m = twoDigits(this.month);
    const d = twoDigits(this.day);
    const h = twoDigits(this.hour);
    const min = twoDigits(this.minute);
    const sec = twoDigits(this.second);
    const ms = threeDigits(this.millisecond);
    return this.isUtc ? `${y}-${m}-${d} ${h}:${min}:${sec}.${ms}Z` : `${y}-${m}-${d} ${h}:${min}:${sec}.${ms}`;
  }

  /** `copyWith` do Dart. */
  copyWith(parts: {
    year?: number;
    month?: number;
    day?: number;
    hour?: number;
    minute?: number;
    second?: number;
    millisecond?: number;
  }): DateTime {
    const make = this.isUtc ? DateTime.utc : DateTime.local;
    return make(
      parts.year ?? this.year,
      parts.month ?? this.month,
      parts.day ?? this.day,
      parts.hour ?? this.hour,
      parts.minute ?? this.minute,
      parts.second ?? this.second,
      parts.millisecond ?? this.millisecond,
    );
  }
}

/** Atalho para `DateTime(y, m, d)` do Dart: data local à meia-noite. */
export function date(year: number, month = 1, day = 1): DateTime {
  return DateTime.local(year, month, day);
}

/** Atalho para `Duration(days: n)`. */
export function days(n: number): Duration {
  return new Duration({ days: n });
}
