/** Contagem de ações por data, do Formulário de Referência (item A3.4). */

import { DartEnum } from '../../lang/dart-enum';
import { DateTime } from '../../lang/date-time';
import { reduce } from '../../lang/iter';
import { compareNum, tryParseDouble, tryParseInt } from '../../lang/num';

/** De onde veio um ponto da série. */
export class ShareCountSource extends DartEnum {
  /** Aprovação de capital, pela contagem da primeira declaração dela. */
  static readonly capitalApproval = new ShareCountSource('capitalApproval', 0);

  /** Desdobramento, grupamento ou bonificação declarado, pela contagem depois. */
  static readonly shareEvent = new ShareCountSource('shareEvent', 1);

  /**
   * Contagem de um formulário que a série não explicava, datada no
   * recebimento dele — evento de ações que o formulário não declarou.
   */
  static readonly filingCorrection = new ShareCountSource('filingCorrection', 2);

  static readonly values: readonly ShareCountSource[] = [
    ShareCountSource.capitalApproval,
    ShareCountSource.shareEvent,
    ShareCountSource.filingCorrection,
  ];

  protected get typeName(): string {
    return 'ShareCountSource';
  }
}

/** Uma contagem de ações que vale a partir de [date]. */
export class ShareCountPoint {
  /** A partir de quando a contagem vale. */
  readonly date: DateTime;

  /** Ações do capital, somadas as classes. */
  readonly total: number;

  /** De onde veio. */
  readonly source: ShareCountSource;

  /** Declara o ponto. */
  constructor(args: { date: DateTime; total: number; source: ShareCountSource }) {
    this.date = args.date;
    this.total = args.total;
    this.source = args.source;
  }
}

/** Um evento de ações declarado no FRE: a contagem depois dele. */
export interface DeclaredShareEvent {
  readonly date: DateTime;
  readonly totalAfter: number;
}

/** Linha do quadro de capital social, como o CSV a traz. */
export type FreRow = Readonly<Record<string, string | undefined>>;

type Capital = readonly [DateTime, number];

class FreDocument {
  readonly reference: DateTime;
  readonly version: number;
  readonly id: string;
  readonly capitals: Capital[];

  constructor(reference: DateTime, version: number, id: string, capitals: Capital[]) {
    this.reference = reference;
    this.version = version;
    this.id = id;
    this.capitals = capitals;
  }
}

function utc(d: DateTime): DateTime {
  return DateTime.utc(d.year, d.month, d.day);
}

function day(v: string | undefined): DateTime | null {
  if (v === undefined || v.length < 10) return null;
  return DateTime.tryParse(`${v.substring(0, 10)}T00:00:00Z`);
}

/** Por data; na mesma data, aprovação antes de evento antes de correção — quem vem depois vale. */
function sortPoints(points: ShareCountPoint[]): void {
  points.sort((a, b) => {
    const c = a.date.compareTo(b.date);
    return c !== 0 ? c : compareNum(a.source.index, b.source.index);
  });
}

/**
 * A contagem de ações de uma companhia ao longo do tempo.
 *
 * **De onde vem.** O quadro de capital social do FRE (item 17.1) declara, em
 * cada formulário, o capital **integralizado** com a data de aprovação e a
 * quantidade de ações. É a peça que falta para o backtest exercitar a ponte
 * por papel (limitações §3.5): a contagem oficial da B3 é de hoje e só de
 * emissor listado, e a coorte de 2015 com uma companhia que saiu da bolsa em
 * 2019 precisa da contagem de 2015.
 *
 * **Três camadas, porque a data de aprovação não conta tudo.** Um grupamento
 * muda a contagem **sem** aprovar capital novo: o formulário seguinte repete a
 * data de aprovação antiga com a contagem nova. Ler a declaração mais recente
 * levaria a contagem de depois do grupamento para antes dele — a CPFL
 * Transmissão, com grupamento de 40 para 1 em 2016, saía com P/VPA de 0,01 de
 * 2010 a 2015. Por isso:
 *
 * 1. cada aprovação de capital vale pela contagem da **primeira** declaração
 *    dela, que é a da época;
 * 2. cada evento de ações declarado entra na data dele, com a contagem de
 *    depois;
 * 3. um formulário cuja contagem a série não explica entra na data de
 *    recebimento — o evento não declarado aconteceu antes dela.
 */
export class ShareCountHistory {
  /** Pontos em ordem de data. */
  readonly points: readonly ShareCountPoint[];

  private constructor(points: readonly ShareCountPoint[]) {
    this.points = points;
  }

  /**
   * Tipo de capital lido, em ordem de preferência: o integralizado é o que
   * tem ação emitida e paga; o emitido é o recuo do formulário novo.
   */
  static readonly kinds: readonly string[] = ['Capital Integralizado', 'Capital Emitido'];

  /** Diferença a partir da qual a contagem de um formulário não é explicada pela série. */
  static readonly formMargin = 0.01;

  /**
   * Monta a série de **uma** companhia.
   *
   * - [rows]: quadro de capital social, de qualquer número de formulários.
   * - [events]: eventos de ações declarados, com a contagem depois.
   * - [receivedOn]: data de recebimento de cada formulário, por
   *   `ID_Documento`. Sem ela, o formulário não corrige a série.
   */
  static fromFre(
    rows: Iterable<FreRow>,
    options: { events?: Iterable<DeclaredShareEvent>; receivedOn?: ReadonlyMap<string, DateTime> } = {},
  ): ShareCountHistory {
    const list = [...rows];
    for (const kind of ShareCountHistory.kinds) {
      const documents = ShareCountHistory.documents(list, kind);
      if (documents.length === 0) continue;
      return ShareCountHistory.build(documents, [...(options.events ?? [])], options.receivedOn ?? new Map());
    }
    return new ShareCountHistory([]);
  }

  /** Formulários do [kind], cada referência na maior versão, em ordem. */
  private static documents(rows: readonly FreRow[], kind: string): FreDocument[] {
    const byReference = new Map<string, FreDocument>();
    for (const r of rows) {
      if (r['Tipo_Capital']?.trim() !== kind) continue;
      const approval = day(r['Data_Autorizacao_Aprovacao']);
      const reference = day(r['Data_Referencia']);
      const version = tryParseInt(r['Versao'] ?? '') ?? 0;
      const total = tryParseDouble(r['Quantidade_Total_Acoes'] ?? '');
      if (approval === null || reference === null) continue;
      if (total === null || !Number.isFinite(total) || total <= 0) continue;
      const current = byReference.get(reference.key);
      if (current === undefined || version > current.version) {
        byReference.set(reference.key, new FreDocument(reference, version, r['ID_Documento'] ?? '', [[approval, total]]));
      } else if (version === current.version) {
        current.capitals.push([approval, total]);
      }
    }
    return [...byReference.values()].sort((a, b) => a.reference.compareTo(b.reference));
  }

  private static build(
    documents: readonly FreDocument[],
    events: readonly DeclaredShareEvent[],
    receivedInputs: ReadonlyMap<string, DateTime>,
  ): ShareCountHistory {
    const points: ShareCountPoint[] = [];
    const approvals: DateTime[] = [];
    for (const d of documents) {
      for (const [approval, total] of d.capitals) {
        if (approvals.some((a) => a.isAtSameMomentAs(approval))) continue;
        approvals.push(approval);
        points.push(new ShareCountPoint({ date: approval, total, source: ShareCountSource.capitalApproval }));
      }
    }
    for (const e of events) {
      if (!(e.totalAfter > 0)) continue;
      points.push(new ShareCountPoint({ date: utc(e.date), total: e.totalAfter, source: ShareCountSource.shareEvent }));
    }
    sortPoints(points);

    for (const d of documents) {
      const received = receivedInputs.get(d.id);
      if (received === undefined) continue;
      // A contagem que o formulário diz vigente: a da aprovação mais recente.
      const last = reduce(d.capitals, (a, b) => (b[0].isAfter(a[0]) ? b : a));
      const today = new ShareCountHistory(points).at(received);
      if (today !== null && Math.abs(last[1] / today.total - 1) <= ShareCountHistory.formMargin) {
        continue;
      }
      points.push(new ShareCountPoint({ date: utc(received), total: last[1], source: ShareCountSource.filingCorrection }));
      sortPoints(points);
    }
    return new ShareCountHistory(Object.freeze([...points]));
  }

  /** Contagem em vigor em [date], ou `null` antes do primeiro ponto. */
  at(date: DateTime): ShareCountPoint | null {
    const d = utc(date);
    let current: ShareCountPoint | null = null;
    for (const p of this.points) {
      if (p.date.isAfter(d)) break;
      current = p;
    }
    return current;
  }
}
