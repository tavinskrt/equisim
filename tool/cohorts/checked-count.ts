// A contagem de ações por data conferida contra o salto do preço (item B43).
//
// **Por que conferir.** A contagem do Formulário de Referência erra de escala
// nos dois sentidos. A correção reenviada às vezes repete a contagem de antes
// de um grupamento: a Ampla agrupou 40.000 para 1 em dezembro de 2015, e a
// correção de maio de 2016 volta aos 3,9 trilhões de ações — vezes o preço de
// depois, R$ 142 trilhões de valor de mercado; a Hapvida (2025) e o IRB (2024)
// fazem o mesmo. E às vezes a correção é o **único** registro de um grupamento
// de verdade: a Magazine Luiza agrupou 10 para 1 em maio de 2024, e a contagem
// só cai de 7,39 bilhões para 739 milhões na correção de maio de 2025 — a coorte
// de 31/03/2025 foi avaliada com dez vezes as ações que a companhia tinha. A
// fonte da entrada não separa os dois casos; o preço separa: num grupamento de
// dez para um, o preço fica dez vezes maior de um pregão para o outro.
//
// **A regra.** Parte da contagem mais recente até a data de corte e anda para
// trás. Cada entrada é comparada com a última aceita depois dela: a diferença de
// até [largeCountChange] vezes vale como veio (emissão, recompra,
// conversão). Na maior, o preço decide:
//
// - com o salto correspondente no preço bruto de algum papel da companhia,
//   entre a data da entrada e [priceJumpWindow] dias depois da aceita, a
//   mudança é grupamento ou desdobramento, e a aceita passa a valer **no dia do
//   salto**, para que ação e preço mudem de base juntos;
// - sem o salto, a mudança não é evento de ações: é emissão ou incorporação
//   grande — a Dasa e a Light se capitalizaram, a Azul reestruturou — e vale
//   como veio, **a menos que a entrada seja uma correção de formulário**
//   (`filingCorrection`). A correção sem salto é a que repete a contagem de
//   antes do evento, e é descartada; o trecho dela fica com a contagem anterior
//   a ela. (Descartar toda mudança grande sem salto tirava das coortes, antes da
//   emissão, justamente as companhias que se capitalizaram em crise: viés de
//   seleção na validação.)
//
// A âncora é a contagem mais recente porque é a que o formulário de hoje
// confirma.
//
// **O que a regra não pega:** a entrada primária errada. A da TIM começa em
// julho de 2020 com 423 milhões — a contagem da TIM S.A. antes da incorporação
// da controladora —, contra os 2,42 bilhões que a ação tem desde então; é um
// evento de ações registrado, sem salto no preço, e fica como veio.
import { type DateTime, Duration } from '../../src/core';
import type { TradingDay } from '../b3/dividends';

/** Mudança, em vezes, a partir da qual o preço tem de confirmar a contagem. */
export const largeCountChange = 3.0;

/**
 * Dias depois da contagem nova em que o salto do preço ainda a confirma: a
 * aprovação do desdobramento vem meses antes da data ex (a da PRIO, de
 * 28/01/2021, para a data ex de 06/05/2021). É o prazo do item B30.
 */
export const priceJumpWindow = 400;

/** Folga, em vezes, entre o salto do preço e o inverso da mudança da contagem. */
export const priceJumpTolerance = 1.4;

/** Pregões consecutivos mais distantes que isto não formam um salto. */
const largestJumpGap = 30;

/** Uma entrada da contagem. [source] é a do arquivo, quando ele a traz. */
export interface CountEntry {
  readonly since: DateTime;
  readonly shares: number;
  readonly source: string | null;
}

/** Uma entrada que o preço não confirmou, e a contagem aceita depois dela. */
export interface DiscardedCount {
  readonly since: DateTime;
  readonly shares: number;
  readonly acceptedAfter: number;
  readonly source: string | null;
}

/** Uma contagem aceita: desde quando vale. */
export interface AcceptedCount {
  readonly since: DateTime;
  readonly shares: number;
}

/**
 * O primeiro pregão entre [from] e [until] em que o preço bruto de alguma das
 * [series] saltou [factor] vezes, com folga de [priceJumpTolerance].
 */
export function priceJump(series: Iterable<readonly TradingDay[]>, factor: number, from: DateTime, until: DateTime): DateTime | null {
  const target = Math.log(factor);
  const margin = Math.log(priceJumpTolerance);
  let first: DateTime | null = null;
  for (const s of series) {
    for (let i = 1; i < s.length; i++) {
      const a = s[i - 1]!;
      const b = s[i]!;
      if (b.date.isBefore(from) || b.date.isAfter(until)) continue;
      if (b.date.difference(a.date).inDays > largestJumpGap) continue;
      if (!(a.close > 0) || !(b.close > 0)) continue;
      if (Math.abs(Math.log(b.close / a.close) - target) >= margin) continue;
      if (first === null || b.date.isBefore(first)) first = b.date;
      break;
    }
  }
  return first;
}

/**
 * A contagem conferida contra o preço, em ordem de data, e as entradas
 * descartadas.
 *
 * - [count]: as entradas do formulário, em qualquer ordem;
 * - [series]: os pregões brutos de cada papel de espécie da companhia;
 * - [until]: a data de corte — entrada posterior a ela não entra, nem como
 *   âncora (o arquivo traz datas no futuro, de digitação).
 */
export function checkCount(
  count: readonly CountEntry[],
  series: Iterable<readonly TradingDay[]>,
  until: DateTime,
): { accepted: AcceptedCount[]; discarded: DiscardedCount[] } {
  const seriesList = [...series];
  const entries = count.filter((p) => p.shares > 0 && !p.since.isAfter(until)).sort((a, b) => a.since.compareTo(b.since));
  const discarded: DiscardedCount[] = [];
  // Da mais recente para a mais antiga; o `since` da aceita pode recuar ao dia
  // do salto do preço.
  const accepted: AcceptedCount[] = [];
  let acceptedDate: DateTime | null = null;
  for (let k = entries.length - 1; k >= 0; k--) {
    const p = entries[k]!;
    if (accepted.length === 0 || acceptedDate === null) {
      accepted.push({ since: p.since, shares: p.shares });
      acceptedDate = p.since;
      continue;
    }
    const acceptedAfter = accepted[accepted.length - 1]!;
    const change = acceptedAfter.shares / p.shares;
    if (change <= largeCountChange && change >= 1 / largeCountChange) {
      accepted.push({ since: p.since, shares: p.shares });
      acceptedDate = p.since;
      continue;
    }
    const jump = priceJump(seriesList, 1 / change, p.since, acceptedDate.add(new Duration({ days: priceJumpWindow })));
    if (jump === null && p.source !== 'filingCorrection') {
      accepted.push({ since: p.since, shares: p.shares });
      acceptedDate = p.since;
      continue;
    }
    if (jump === null) {
      discarded.push({ since: p.since, shares: p.shares, acceptedAfter: acceptedAfter.shares, source: p.source });
      continue;
    }
    // As entradas da contagem nova anteriores ao salto — a aprovação costuma
    // vir antes da data ex — passam a valer no dia dele.
    let fromNew = acceptedAfter.shares;
    while (accepted.length > 0 && accepted[accepted.length - 1]!.since.isBefore(jump)) {
      fromNew = accepted.pop()!.shares;
    }
    accepted.push({ since: jump, shares: fromNew }, { since: p.since, shares: p.shares });
    acceptedDate = p.since;
  }
  return { accepted: accepted.reverse(), discarded };
}
