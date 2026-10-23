// Os eventos de ações de uma companhia listada — desdobramento, grupamento e
// bonificação —, e o que eles fazem com a série da fonte e com a contagem por
// data das coortes (itens B29 e B30).
//
// **Quatro fontes, porque nenhuma basta.** O quadro de eventos do Formulário de
// Referência declara o fator pela contagem antes e depois, mas parou em 2022; o
// registro da B3 traz a data ex dos eventos recentes, e não de todos — a
// bonificação de 2024 da Klabin não está lá; o `DISMES` do COTAHIST marca todo
// evento, mas só se distingue de provento quando o fator é grande. A quarta é a
// contagem do próprio FRE: a mudança que nenhuma emissão por valor explica é
// candidata a evento, localizada no preço. Juntas, e sem repetir o mesmo
// evento, cobrem o que cada uma deixa de fora. **Candidato falso não custa
// nada**: evento só ajusta a série onde o salto dele está no preço.
//
// **O que a fonte de preços fez com cada um** se sabe pelo fator entre o
// fechamento bruto e o dela: no dia ex de um evento ajustado ele salta
// exatamente pelo fator, e no de um não ajustado fica parado. É uma conta sem
// ruído de mercado — os dois fechamentos andam juntos em todo pregão em que a
// fonte não mexeu —, e por isso quem tem o COTAHIST não precisa da regra do
// salto que o aplicativo usa (`CorporateEvents.completeAdjustment`).
import { existsSync } from 'node:fs';

import {
  type B3Issuer,
  B3RegistryCodec,
  CorporateEvents,
  DateTime,
  Duration,
  type JsonObject,
  type PriceSeries,
  ShareEvent,
  ShareIssue,
  str,
  tryParseDouble,
} from '../../src/core';
import type { TradingDay } from '../b3/dividends';
import { readCvmCsv } from '../cvm/csv';
import type { FreIssuances } from '../cvm/fre-issues';
import { filesIn, readJson } from '../lib/files';

interface DeclaredEvent {
  readonly approval: DateTime;
  readonly factor: number;
}

interface CountChange {
  readonly date: DateTime;
  readonly ratio: number;
  readonly before: number;
}

const isoDay = (d: DateTime) => d.toIso8601String().slice(0, 10);

/** Os eventos de ações declarados e registrados, prontos para localizar. */
export class ShareEvents {
  private constructor(
    /** Eventos do quadro do FRE, por CNPJ: aprovação e fator, distintos. */
    private readonly declared: Map<string, DeclaredEvent[]>,
    /** Registro da B3, por raiz do código. */
    private readonly registry: Map<string, B3Issuer>,
    /** Mudanças da contagem do FRE, por CNPJ: data e razão. */
    private readonly count: Map<string, CountChange[]>,
    /**
     * Emissões por valor do FRE, para separar a mudança de contagem que é
     * emissão da que é evento de ações.
     */
    private readonly issuances: FreIssuances | null,
  ) {}

  /**
   * Lê o quadro de eventos do FRE e o registro da B3.
   *
   * Sem o FRE em disco, segue só com o registro e o `DISMES`: um evento a
   * menos localizado é um ajuste a menos, e não um ajuste errado.
   */
  static read(
    options: { freDir?: string; registry?: string; listedCounts?: string; issuances?: FreIssuances | null } = {},
  ): ShareEvents {
    const freDir = options.freDir ?? 'data/cvm/fre';
    const registry = options.registry ?? 'public/assets/b3/emissores.json';
    const listedCounts = options.listedCounts ?? 'data/b3/listadas_contagem.json';
    const declared = new Map<string, DeclaredEvent[]>();
    const seen = new Set<string>();
    for (const f of filesIn(freDir, /^fre_cia_aberta_capital_social_desdobramento_\d{4}\.csv$/)) {
      for (const r of readCvmCsv(f)) {
        const cnpj = r['CNPJ_Companhia'];
        const approval = DateTime.tryParse(`${r['Data_Aprovacao']}T00:00:00Z`);
        const before = tryParseDouble(r['Quantidade_Total_Acoes_Antes_Aprovacao'] ?? '');
        const after = tryParseDouble(r['Quantidade_Total_Acoes_Depois_Aprovacao'] ?? '');
        if (cnpj === undefined || approval === null || before === null || after === null) continue;
        if (before <= 0 || after <= 0) continue;
        // Fator de 1 não é evento de ações: é o formulário repetindo a
        // contagem. E o mesmo evento se repete em toda versão do formulário.
        if (Math.abs(Math.log(after / before)) < 1e-6) continue;
        const key = `${cnpj}|${isoDay(approval)}|${str(before)}|${str(after)}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const list = declared.get(cnpj) ?? [];
        list.push({ approval, factor: after / before });
        declared.set(cnpj, list);
      }
    }
    const b3 = existsSync(registry) ? B3RegistryCodec.decodePackage(readJson<JsonObject>(registry)) : new Map<string, B3Issuer>();
    const count = new Map<string, CountChange[]>();
    if (existsSync(listedCounts)) {
      const json = readJson<Record<string, { contagem: { desde: string; acoes: number }[] }>>(listedCounts);
      for (const [cnpj, entry] of Object.entries(json)) {
        const points = entry.contagem
          .map((p) => ({ since: DateTime.parse(`${p.desde}T00:00:00Z`), shares: Number(p.acoes) }))
          .sort((a, b) => a.since.compareTo(b.since));
        const changes: CountChange[] = [];
        for (let i = 1; i < points.length; i++) {
          const a = points[i - 1]!.shares;
          const b = points[i]!.shares;
          if (a > 0 && b > 0 && Math.abs(Math.log(b / a)) > 1e-6) changes.push({ date: points[i]!.since, ratio: b / a, before: a });
        }
        if (changes.length > 0) count.set(cnpj, changes);
      }
    }
    return new ShareEvents(declared, b3, count, options.issuances ?? null);
  }

  /**
   * Os eventos de ações de [ticker], localizados no fechamento bruto dele.
   *
   * O mesmo evento vindo de duas fontes entra uma vez: dois eventos a até
   * quinze dias um do outro são o mesmo, e dois de mesmo fator a até 120 dias
   * também — a aprovação e a data ex de uma bonificação podem estar meses
   * separadas, e a contagem do FRE a localiza na primeira troca de `DISMES`.
   * Vale a fonte que chegou antes: o quadro do FRE e o registro da B3 dão a
   * data ex; a contagem, só uma aproximação.
   *
   * [withCount] falso deixa de fora a quarta fonte — a mudança de contagem
   * do FRE —, para quem quer explicar justamente a contagem.
   */
  ofSecurity(args: { cnpj: string | null; ticker: string; rawSessions: readonly TradingDay[]; withCount?: boolean }): ShareEvent[] {
    const { cnpj, ticker, rawSessions } = args;
    const raw = rawSessions.map((p) => p.raw);
    const out: ShareEvent[] = [];
    const merge = (e: ShareEvent) => {
      const repeatedEvent = out.some((x) => {
        const days = Math.abs(x.exDate.difference(e.exDate).inDays);
        return days <= 15 || (days <= 120 && Math.abs(Math.log(x.factor) - Math.log(e.factor)) < 0.02);
      });
      if (!repeatedEvent) out.push(e);
    };

    // **Cada fonte com a sua prova** (decisão 136). O quadro do FRE declara o
    // fator e a aprovação, não a data ex: ela é o pregão em que o preço
    // confirma — a primeira troca de `DISMES` depois da aprovação, que é o que
    // `CorporateEvents.locate` devolve para fator pequeno, é muitas vezes um
    // provento, e a ASAI3 ganhava um evento de 0,935 num dia qualquer.
    for (const d of (cnpj === null ? undefined : this.declared.get(cnpj)) ?? []) {
      const ev = locateInPrice(rawSessions, d.approval, d.factor);
      if (ev !== null) merge(ev);
    }
    // O registro repete o evento por classe e por consulta — a BBAS3 de 2018
    // tem fator 2 no preço e produto 8 no registro: um por data.
    const root = ticker.length >= 4 ? ticker.slice(0, 4) : ticker;
    const dates = new Set<string>();
    for (const e of this.registry.get(root)?.events ?? []) {
      if (!(e.factor > 0) || !Number.isFinite(e.factor)) continue;
      const key = isoDay(e.exDate);
      if (dates.has(key)) continue;
      dates.add(key);
      merge(
        new ShareEvent({
          exDate: DateTime.utc(e.exDate.year, e.exDate.month, e.exDate.day),
          factor: e.factor,
          observedRatio: 1 / e.factor,
        }),
      );
    }
    // O `DISMES` com salto grande só é evento de ações se a contagem mudou
    // junto: a SYNE3 caiu 47% em 09/12/2024, com troca de `DISMES`, numa
    // redução de capital com devolução em dinheiro — e a contagem do FRE não
    // se moveu. Tomada por desdobramento, ela dobrava o retorno de quem a
    // atravessava.
    const changes = (cnpj === null ? undefined : this.count.get(cnpj)) ?? [];
    for (const ev of CorporateEvents.detect(raw)) {
      const countChanged = changes.some(
        (m) => Math.abs(m.date.difference(ev.exDate).inDays) <= 400 && Math.abs(Math.log(m.ratio) - Math.log(ev.factor)) < 0.1,
      );
      if (countChanged) merge(ev);
    }
    // A mudança de contagem que nenhuma emissão por valor explica: aumento de
    // 3% ou mais — bonificação, desdobramento —, ou redução à metade ou menos
    // — grupamento. Redução pequena é cancelamento de tesouraria, e não
    // evento. **Só entra se o preço a confirma** — troca de `DISMES` com o
    // salto do fator —, e não pelo primeiro salto parecido: a AMER3 caiu 38%
    // em 16/01/2023, na semana da fraude, e isso casava com uma mudança de
    // contagem de 1,62.
    if (args.withCount === false) {
      out.sort((a, b) => a.exDate.compareTo(b.exDate));
      return out;
    }
    const issued = cnpj === null || this.issuances === null ? [] : this.issuances.known(cnpj, DateTime.utc(2100));
    for (const m of changes) {
      if (!(m.ratio >= 1.03 || m.ratio <= 0.5)) continue;
      const newShares = m.before * (m.ratio - 1);
      const isIssuance = issued.some((i) => Math.abs(i.date.difference(m.date).inDays) <= 60 && Math.abs(i.shares / newShares - 1) < 0.05);
      if (isIssuance) continue;
      const ev = locateInPrice(rawSessions, m.date, m.ratio);
      if (ev !== null) merge(ev);
    }
    out.sort((a, b) => a.exDate.compareTo(b.exDate));
    return out;
  }
}

/**
 * Os eventos que a fonte de preços **não** ajustou, com a data ex em que o
 * salto está (item B29).
 *
 * Para cada evento, procura a dez dias da data dada o pregão em que o bruto
 * salta pelo fator. Se nele o fator entre o bruto e a fonte também salta pelo
 * fator, a fonte ajustou; se fica parado, não ajustou, e o evento sai com esse
 * dia. Sem pregão que case — evento mal localizado, papel suspenso —, o evento
 * não sai: ajustar num dia errado inventaria o salto que se quer tirar.
 */
export function notAdjustedBySource(source: PriceSeries, rawSessions: readonly TradingDay[], events: readonly ShareEvent[]): ShareEvent[] {
  if (events.length === 0 || rawSessions.length < 2 || source.isEmpty) return [];
  const fromSource = new Map<string, number>();
  for (const p of source.points) if (p.close > 0) fromSource.set(isoDay(p.date), p.close);
  const out: ShareEvent[] = [];
  for (const e of events) {
    const q = e.factor;
    // Abaixo de 2% o salto do evento não se separa de um pregão comum, e o
    // efeito dele na série é desse tamanho.
    if (!(q > 0) || !Number.isFinite(q) || Math.abs(Math.log(q)) < 0.02) continue;
    const margin = Math.abs(Math.log(q)) < Math.log(1.6) ? 0.04 : 0.08;
    let adjusted = false;
    let unadjustedDay: DateTime | null = null;
    for (let i = 1; i < rawSessions.length; i++) {
      const b = rawSessions[i]!;
      const a = rawSessions[i - 1]!;
      const days = b.date.difference(e.exDate).inDays;
      if (days < -10) continue;
      if (days > 10) break;
      if (b.date.difference(a.date).inDays > 7) continue;
      const fa = fromSource.get(isoDay(a.date));
      const fb = fromSource.get(isoDay(b.date));
      if (fa === undefined || fb === undefined || !(a.close > 0) || !(b.close > 0)) continue;
      const rawJump = Math.log(b.close / a.close);
      const factorStep = Math.log(b.close / fb / (a.close / fa));
      if (Math.abs(factorStep + Math.log(q)) < 0.01) {
        adjusted = true;
        break;
      }
      // Sem ajuste: o fator parado, o bruto caindo pelo fator e o `DISMES`
      // trocando no dia — sem a troca, uma queda comum de mercado passaria.
      if (Math.abs(factorStep) < 0.005 && b.distribution !== a.distribution && Math.abs(rawJump + Math.log(q)) < margin) {
        unadjustedDay ??= b.date;
      }
    }
    if (!adjusted && unadjustedDay !== null) {
      out.push(
        new ShareEvent({
          exDate: DateTime.utc(unadjustedDay.year, unadjustedDay.month, unadjustedDay.day),
          factor: q,
          observedRatio: e.observedRatio,
        }),
      );
    }
  }
  return out;
}

/**
 * A contagem do FRE em [t] com os eventos que ele ainda não absorveu
 * (item B30).
 *
 * O quadro de eventos do FRE parou em 2022, e daí em diante a contagem só muda
 * quando a companhia corrige o formulário — o que pode levar mais de um ano.
 * Enquanto isso a coorte dividia pela contagem de antes do evento, com o preço
 * de depois: a BBAS3 de 30/06/2024 saía com metade do valor de mercado e o
 * dobro do potencial.
 *
 * **Só age quando a contagem está parada**: nenhuma mudança, por fator
 * nenhum, de 400 dias antes do evento até a data. Se ela mudou, o formulário
 * tratou o evento — a aprovação costuma vir antes da data ex, e às vezes
 * junto com outra operação —, e a contagem fica como veio.
 */
export function sharesWithEvents(
  count: readonly { since: DateTime; shares: number }[],
  t: DateTime,
  events: readonly ShareEvent[],
): { shares: number | null; applied: ShareEvent[] } {
  const day = DateTime.utc(t.year, t.month, t.day);
  if (count.length === 0) return { shares: null, applied: [] };
  // A contagem precisa cobrir a data do evento: um evento anterior ao primeiro
  // formulário — o registro da B3 guarda eventos de 1989 — já está nela.
  const start = count[0]!.since;
  let shares: number | null = null;
  let previous: number | null = null;
  const changes: { date: DateTime; ratio: number }[] = [];
  for (const p of count) {
    if (p.since.isAfter(day)) break;
    if (previous !== null && previous > 0 && p.shares > 0) {
      const r = p.shares / previous;
      if (Math.abs(Math.log(r)) > 1e-6) changes.push({ date: p.since, ratio: r });
    }
    previous = p.shares;
    shares = p.shares;
  }
  if (shares === null) return { shares: null, applied: [] };
  const applied: ShareEvent[] = [];
  let adjusted = shares;
  for (const e of events) {
    const ex = DateTime.utc(e.exDate.year, e.exDate.month, e.exDate.day);
    if (ex.isAfter(day)) continue;
    if (!(e.factor > 0) || Math.abs(Math.log(e.factor)) < 0.02) continue;
    // Só evento recente: a contagem do FRE começa em 2010, e o valor dela já
    // traz os eventos anteriores — uma data de aprovação antiga no primeiro
    // ponto não quer dizer contagem de antes do evento. Três anos cobrem com
    // folga o atraso de correção medido.
    if (ex.isBefore(DateTime.utc(2011)) || ex.isBefore(DateTime.utc(day.year - 3, day.month, day.day))) continue;
    if (!start.isBefore(ex)) continue;
    // **Parada de verdade**: nenhuma mudança da contagem, por fator nenhum, de
    // 400 dias antes do evento até a data. Se ela mudou, o formulário tratou o
    // evento, ainda que junto com outra coisa — a AERI3 registrou o grupamento
    // de 20 para 1 antes da data ex e junto com uma emissão, com razão 0,081,
    // e aplicar o evento de novo tirava 95% do valor de mercado.
    const moved = changes.some((m) => m.date.isAfter(ex.subtract(new Duration({ days: 400 }))));
    if (moved) continue;
    adjusted *= e.factor;
    applied.push(e);
  }
  return { shares: adjusted, applied };
}

/**
 * O pregão, de 30 dias antes de [d] a 150 depois, em que o `DISMES` troca e o
 * fechamento bruto se divide pelo fator [q]; `null` sem ele.
 */
function locateInPrice(rawSessions: readonly TradingDay[], d: DateTime, q: number): ShareEvent | null {
  const margin = Math.abs(Math.log(q)) < Math.log(1.6) ? 0.06 : 0.08;
  for (let i = 1; i < rawSessions.length; i++) {
    const b = rawSessions[i]!;
    const a = rawSessions[i - 1]!;
    const days = b.date.difference(d).inDays;
    if (days < -30) continue;
    if (days > 150) break;
    if (b.date.difference(a.date).inDays > 7) continue;
    if (b.distribution === a.distribution) continue;
    if (!(a.close > 0) || !(b.close > 0)) continue;
    const ratio = b.close / a.close;
    if (Math.abs(Math.log(ratio) + Math.log(q)) < margin) {
      return new ShareEvent({ exDate: DateTime.utc(b.date.year, b.date.month, b.date.day), factor: q, observedRatio: ratio });
    }
  }
  return null;
}

/**
 * As variações de capital do FRE que nenhum evento de ações explica, como
 * emissões **sem valor declarado** (item B28): a cascata não as soma, e diz
 * quanto o preço justo mudaria se fossem emissão por valor.
 *
 * A bonificação também aumenta o capital — capitaliza reserva —, e o que a
 * separa da emissão é o registro da B3, quando ele a tem, ou o preço: no dia
 * ex, o fechamento bruto se divide pela razão entre as contagens, e o `DISMES`
 * do COTAHIST troca. Uma queda comum de
 * mercado não troca o `DISMES`, e um provento troca mas não cai pela razão. A
 * busca vai de 30 dias antes da aprovação a 150 depois — a data ex costuma vir
 * depois dela, e a contagem do FRE às vezes é corrigida antes. A KLBN11 de
 * 2024 aparece no FRE como R$ 1,6 bilhão de capital com 10% de ações novas:
 * é a bonificação de 07/05/2024, com o bruto caindo 7,6% e o `DISMES` trocando
 * no dia, e fica de fora.
 *
 * - [events]: os eventos do quadro do FRE, do registro da B3 e do `DISMES` —
 *   **sem** a mudança de contagem, que se explicaria a si mesma.
 */
export function issuancesWithoutEvent(
  candidates: readonly { issuance: ShareIssue; ratio: number }[],
  rawSessions: readonly TradingDay[],
  events: readonly ShareEvent[],
): ShareIssue[] {
  return candidates
    .filter(
      (c) =>
        !eventJump(rawSessions, c.issuance.date, c.ratio) &&
        !events.some(
          (e) => Math.abs(e.exDate.difference(c.issuance.date).inDays) <= 150 && Math.abs(Math.log(e.factor) - Math.log(c.ratio)) < 0.03,
        ),
    )
    .map((c) => new ShareIssue({ date: c.issuance.date, amount: c.issuance.amount, shares: c.issuance.shares, declared: false }));
}

function eventJump(rawSessions: readonly TradingDay[], d: DateTime, q: number): boolean {
  // Com a troca de `DISMES` exigida, a folga pode ser a da detecção: a
  // bonificação de 20% da POMO4 caiu 20% no dia ex, e não 16,7%.
  const margin = Math.abs(Math.log(q)) < Math.log(1.6) ? 0.06 : 0.08;
  for (let i = 1; i < rawSessions.length; i++) {
    const b = rawSessions[i]!;
    const a = rawSessions[i - 1]!;
    const days = b.date.difference(d).inDays;
    if (days < -30) continue;
    if (days > 150) break;
    if (b.date.difference(a.date).inDays > 7) continue;
    if (b.distribution === a.distribution) continue;
    if (!(a.close > 0) || !(b.close > 0)) continue;
    if (Math.abs(Math.log(b.close / a.close) + Math.log(q)) < margin) return true;
  }
  return false;
}
