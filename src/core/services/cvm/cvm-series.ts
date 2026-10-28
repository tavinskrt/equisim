/**
 * A série de exercícios que o motor consome, montada da CVM com o mercado.
 *
 * **Por que mora no núcleo.** Até o A1.8 esta montagem vivia dentro da
 * ferramenta de ligação, e levar a ligação ao aplicativo (A1.9) exigiria
 * copiá-la para a camada de dados. Duas cópias da mesma regra divergem na
 * primeira correção — e esta regra já teve três: exercício fora de dezembro,
 * série com buraco e mescla olhando para a frente. Uma só, testada aqui.
 */

import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DateTime, Duration } from '../../lang/date-time';
import { FieldSource, FundamentalsMerge } from './fundamentals-merge';
import { CvmDocumentKind, TrailingTwelveMonths, type CvmPeriodDocument } from './trailing-twelve-months';
import { YearToDate } from './year-to-date';

/** Resultado da montagem: a série e o que se sabe dela. */
export class CvmSeriesResult {
  /** Exercícios em ordem cronológica, prontos para a cascata. */
  readonly series: readonly FundamentalsSnapshot[];

  /** `true` quando a série terminou ancorada em trimestre. */
  readonly anchoredOnQuarter: boolean;

  /** `true` quando o último ponto é o ano corrente anualizado (decisão 153). */
  readonly endsAnnualized: boolean;

  /** Quantos campos vieram de cada fonte, somados sobre a série. */
  readonly provenance: ReadonlyMap<FieldSource, number>;

  /** Declara o resultado. */
  constructor(args: {
    series: readonly FundamentalsSnapshot[];
    anchoredOnQuarter: boolean;
    endsAnnualized?: boolean;
    provenance: ReadonlyMap<FieldSource, number>;
  }) {
    this.series = args.series;
    this.anchoredOnQuarter = args.anchoredOnQuarter;
    this.endsAnnualized = args.endsAnnualized ?? false;
    this.provenance = args.provenance;
  }
}

/** Montagem da série. */
export const CvmSeries = {
  /**
   * Folga, em dias, para casar o fim de um ponto da CVM com o exercício de
   * mercado que o completa.
   */
  marginDays: 4,

  /**
   * A série anual termina no ano corrente anualizado (decisão 153). O
   * aplicativo e o backtest leem daqui, para que a regra seja uma só.
   */
  yearToDateByDefault: true,

  /**
   * A versão vigente de cada documento: das já publicadas, a de recebimento
   * mais recente, por tipo e data de referência (item B8).
   *
   * A CVM republica o documento reapresentado com outra versão, e cada versão
   * tem a sua data de recebimento. Com todas elas na lista, a pergunta da
   * coorte deixa de ser «o documento era público?» e passa a ser «**qual**
   * versão era pública?» — a original até a reapresentação chegar, a
   * reapresentada depois. Sem isso o número corrigido em 2021 entra numa
   * avaliação de 2019, que é conhecimento futuro pela porta da frente.
   *
   * Com uma versão por documento — o pacote do aplicativo, que só traz a
   * última —, devolve os publicados, e nada muda. Em empate de data, fica a
   * que vem depois na lista. Documento sem data de recebimento conta como
   * recebido no fecho, que é o mais cedo que ele pode ter sido.
   */
  inForceAt(
    documents: readonly CvmPeriodDocument[],
    published: (s: FundamentalsSnapshot) => boolean,
  ): CvmPeriodDocument[] {
    const day = (d: DateTime): DateTime => DateTime.utc(d.year, d.month, d.day);
    const byKey = new Map<string, CvmPeriodDocument>();
    for (const d of documents) {
      if (!published(d.current)) continue;
      const k = `${d.kind.name}|${day(d.periodEnd).key}`;
      const current = byKey.get(k);
      if (
        current === undefined ||
        !day(d.current.receiptDate ?? d.periodEnd).isBefore(day(current.current.receiptDate ?? current.periodEnd))
      ) {
        byKey.set(k, d);
      }
    }
    return [...byKey.values()].sort((a, b) => a.periodEnd.compareTo(b.periodEnd));
  },

  /**
   * Monta a série de [documents] da CVM, mesclada com [market].
   *
   * - [anchored]: `true` para a série de doze meses no trimestre mais recente
   *   (A1.8); `false` para a série de DFPs (A1.7).
   * - [published]: a regra de publicidade da cascata — `PointInTimeView.
   *   isPublished` — para que ela seja uma só.
   * - [yearToDate]: na série anual, acrescenta o ano corrente anualizado do
   *   último ITR depois da última DFP (decisão 153). Sem efeito na ancorada,
   *   que já termina no trimestre.
   *
   * **A mescla nunca olha para a frente.** Um ponto terminado em junho é
   * completado com o último exercício de mercado encerrado **até** junho; o de
   * dezembro do mesmo ano ainda não existia.
   *
   * **Na série anual**, o exercício que só o mercado tem continua entrando.
   * **Na ancorada, não**: um dezembro no meio de junhos é a mistura de âncoras
   * que a série existe para evitar.
   *
   * Sem documento da CVM utilizável, devolve a série de mercado intacta.
   */
  build(args: {
    documents: readonly CvmPeriodDocument[];
    market: readonly FundamentalsSnapshot[];
    published: (s: FundamentalsSnapshot) => boolean;
    anchored: boolean;
    yearToDate?: boolean;
  }): CvmSeriesResult {
    const { documents, published, anchored } = args;
    const yearToDate = (args.yearToDate ?? false) && !anchored;
    const marketMedians = [...args.market].sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));

    // **Só documento publicado na data**, nas duas séries. A DFP recebida
    // depois da data ocupava o ano na mescla: o exercício de mercado daquele
    // ano, publicado de fato, era descartado, e a cascata depois removia o
    // ponto mesclado por ser do futuro — o ano sumia. USIM3 em 04/09/2024:
    // DFP de 2023 reapresentada, com a versão ingerida recebida em 16/01/2025,
    // e avaliação feita sobre 2022 (decisão 78).
    //
    // **E só a versão vigente de cada um** (item B8): com as versões antigas
    // na lista, a coorte lê o número que era público na data, e não o
    // reapresentado depois.
    const inForce = CvmSeries.inForceAt(documents, published);
    const fromCvm = anchored
      ? TrailingTwelveMonths.anchoredSeries(inForce, { published })
      : inForce.filter((d) => d.kind === CvmDocumentKind.dfp).map((d) => d.current);
    if (fromCvm.length === 0) {
      return new CvmSeriesResult({
        series: marketMedians,
        anchoredOnQuarter: false,
        provenance: new Map(),
      });
    }
    fromCvm.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));

    // **O ano corrente entra só se for o ano seguinte ao da última DFP.** O
    // exercício fora do calendário teria dois pontos no mesmo ano, e as
    // guardas, que contam por ano, não os separariam.
    let endsAnnualized = false;
    if (yearToDate) {
      const current = YearToDate.latest(inForce);
      const last = fromCvm[fromCvm.length - 1]!;
      if (current !== null && current.fiscalPeriodEnd.year === last.fiscalPeriodEnd.year + 1) {
        fromCvm.push(current);
        endsAnnualized = true;
      }
    }

    const marketUntil = (end: DateTime): FundamentalsSnapshot | null => {
      let m: FundamentalsSnapshot | null = null;
      const limit = end.add(new Duration({ days: CvmSeries.marginDays }));
      for (const s of marketMedians) {
        if (!s.fiscalPeriodEnd.isAfter(limit)) m = s;
      }
      return m;
    };

    const out: FundamentalsSnapshot[] = [];
    const years = new Set<number>();
    const origin = new Map<FieldSource, number>();
    for (const c of fromCvm) {
      const merged = FundamentalsMerge.merge({ cvm: c, market: marketUntil(c.fiscalPeriodEnd) });
      if (merged === null) continue;
      out.push(merged.snapshot);
      years.add(c.fiscalPeriodEnd.year);
      for (const [k, v] of merged.provenance.count) origin.set(k, (origin.get(k) ?? 0) + v);
    }

    const quarterAnchored = anchored && TrailingTwelveMonths.isAnchoredOnQuarter(fromCvm, documents);
    if (!quarterAnchored) {
      for (const s of marketMedians) {
        if (!years.has(s.fiscalPeriodEnd.year)) out.push(s);
      }
      out.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
    }

    return new CvmSeriesResult({
      series: Object.freeze([...out]),
      anchoredOnQuarter: quarterAnchored,
      endsAnnualized,
      provenance: new Map(origin),
    });
  },
};
