// A3.4 — contagem de ações e eventos por data, para as companhias deslistadas.
//
// Para cada companhia da ponte de `b3_ponte.py` (A3.2), e para cada papel dela:
//
//   contagem   série do capital integralizado do Formulário de Referência:
//              aprovação a aprovação, evento a evento, e o formulário que a
//              série não explica na data de recebimento (`ShareCountHistory`)
//   eventos    desdobramento, grupamento e bonificação declarados no FRE, com
//              a data ex localizada no preço (`CorporateEvents.locate`); e,
//              onde o FRE não declara, os inferidos pelo preço (decisão 75)
//   série      fechamento do COTAHIST ajustado pelos dois
//
// **A escala é conferida de três jeitos**, porque companhia deslistada não tem
// valor de mercado publicado em data conhecida:
//
//   1. nas listadas, a contagem do FRE em 14/09/2026 contra a oficial da B3 —
//      é onde a verdade existe, e é o que valida o método;
//   2. nas deslistadas, a contagem do FRE contra a composição do capital do
//      DFP e do ITR da mesma data — dois formulários da CVM, preenchidos em
//      quadros diferentes;
//   3. e o preço sobre valor patrimonial por ação no fim de cada exercício,
//      que um erro de mil vezes na contagem tira de qualquer faixa plausível.
//
// Grava `data/b3/deslistadas_contagem.json`, para as coortes da Fase 2, e o
// resumo em `docs/validacao/b3_contagem_por_data.json`.
//
// **E as listadas, desde o item C3.** A coorte da listada também precisa da
// contagem da data — o valor de mercado dela era `contagem do exercício ×
// preço`, e a razão de unidade colapsava. A mesma série sai para cada companhia
// do universo em `data/b3/listadas_contagem.json`, com os eventos declarados
// localizados no preço dos códigos que a FCA declara. Nas duas, a série leva
// também a divisão entre ordinárias e preferenciais (`CapitalClasses`), para
// o valor de mercado espécie a espécie.
//
// Uso:
//   python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
//   npm run tool -- b3-delisted-count
import { existsSync, readFileSync } from 'node:fs';

import {
  B3CashDividends,
  B3RegistryCodec,
  type CashDividend,
  compareNum,
  compareStr,
  CorporateEvents,
  DateTime,
  type ShareEvent,
  ShareCountHistory,
  tryParseDouble,
} from '../src/core';
import { readRawCotahist, tradingDayUntil } from './b3/dividends';
import { CapitalClasses, companyCodes } from './cohorts/as-of-base';
import { FcaCodes } from './cvm/fca-codes';
import { readCvmCsv } from './cvm/csv';
import { dartString, errln, filesIn, jsonPretty, outln, readJson, writeText } from './lib/files';

/** Contagens que batem: a 2% entre formulários, a 1% contra a B3. */
const formsMargin = 0.02;
const b3Margin = 0.01;

/** P/VPA plausível para uma companhia com pregão: fora disto, a escala errou. */
const minPriceToBook = 0.02;
const maxPriceToBook = 50.0;

type CsvRow = Record<string, string>;

function byCnpj(pattern: RegExp): Map<string, CsvRow[]> {
  const out = new Map<string, CsvRow[]>();
  for (const f of filesIn('data/cvm/fre', pattern)) {
    for (const r of readCvmCsv(f)) {
      const cnpj = r['CNPJ_Companhia'];
      if (cnpj === undefined) continue;
      let list = out.get(cnpj);
      if (list === undefined) out.set(cnpj, (list = []));
      list.push(r);
    }
  }
  return out;
}

interface Declared {
  approval: DateTime;
  factor: number;
  after: number;
  kind: string;
}

/** Eventos de ações declarados no FRE de uma companhia, distintos. */
function declaredEvents(rows: readonly CsvRow[]): Declared[] {
  const out: Declared[] = [];
  const seen = new Set<string>();
  for (const r of rows) {
    const approval = DateTime.tryParse(`${r['Data_Aprovacao'] ?? 'null'}T00:00:00Z`);
    const before = tryParseDouble(r['Quantidade_Total_Acoes_Antes_Aprovacao'] ?? '');
    const after = tryParseDouble(r['Quantidade_Total_Acoes_Depois_Aprovacao'] ?? '');
    if (approval === null || before === null || after === null) continue;
    if (before <= 0 || after <= 0) continue;
    const key = `${day(approval)}|${r['Quantidade_Total_Acoes_Antes_Aprovacao']}|${r['Quantidade_Total_Acoes_Depois_Aprovacao']}`;
    if (seen.has(key)) continue;
    seen.add(key);
    // Fator de 1 não é evento de ações: é o formulário repetindo a contagem.
    if (Math.abs(Math.log(after / before)) < 1e-6) continue;
    out.push({ approval, factor: after / before, after, kind: r['Tipo_Evento'] ?? '' });
  }
  return out;
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const day = (d: DateTime): string => d.toIso8601String().substring(0, 10);

interface BridgeCompany {
  nome?: string | null;
  papeis: Record<string, unknown>;
  anosDfp?: number[] | null;
}

interface FiscalYearRow {
  cnpj: string;
  fimDoExercicio?: string | null;
  acoesIntegralizadas?: number | null;
  patrimonioLiquido?: number | null;
  documento?: string | null;
}

export function main(_args: string[]): void {
  if (!existsSync('data/cvm/fre')) {
    errln('sem data/cvm/fre — rode: python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre');
    process.exitCode = 2;
    return;
  }
  const bridge = readJson<Record<string, BridgeCompany>>('data/b3/ponte_deslistadas.json');
  const capital = byCnpj(/^fre_cia_aberta_capital_social_\d{4}\.csv$/);
  const splits = byCnpj(/^fre_cia_aberta_capital_social_desdobramento_\d{4}\.csv$/);
  // Recebimento de cada formulário, para datar a contagem que a série não
  // explica (`ShareCountSource.filingCorrection`).
  const receivedInputs = new Map<string, DateTime>();
  for (const f of filesIn('data/cvm/fre', /^fre_cia_aberta_\d{4}\.csv$/)) {
    for (const r of readCvmCsv(f)) {
      const id = r['ID_DOC'];
      const received = DateTime.tryParse(`${r['DT_RECEB'] ?? 'null'}T00:00:00Z`);
      if (id !== undefined && received !== null) receivedInputs.set(id, received);
    }
  }
  errln(`FRE: capital de ${capital.size} companhias, eventos de ${splits.size}`);

  // Composição do capital do DFP e do ITR, e patrimônio do DFP, por CNPJ.
  const composition = new Map<string, { date: DateTime; shares: number }[]>();
  const equity = new Map<string, Map<number, number>>();
  for (const d of readJson<FiscalYearRow[]>('data/cvm_exercicios.json')) {
    const cnpj = d.cnpj;
    const end = DateTime.tryParse(`${d.fimDoExercicio ?? 'null'}T00:00:00Z`);
    if (end === null) continue;
    const shares = d.acoesIntegralizadas ?? null;
    if (shares !== null && shares > 0) {
      let list = composition.get(cnpj);
      if (list === undefined) composition.set(cnpj, (list = []));
      list.push({ date: end, shares });
    }
    const pl = d.patrimonioLiquido ?? null;
    if (d.documento === 'DFP' && pl !== null && pl > 0) {
      let byYear = equity.get(cnpj);
      if (byYear === undefined) equity.set(cnpj, (byYear = new Map()));
      byYear.set(end.year, pl);
    }
  }

  const tickers = new Set<string>();
  for (const c of Object.values(bridge)) for (const t of Object.keys(c.papeis)) tickers.add(t);
  // Os códigos das listadas: os da ponte do universo e os que a FCA declara.
  const listedBridge = (readJson<Record<string, unknown>>('docs/validacao/ponte_cvm.json')['ponte'] ?? {}) as Record<string, string>;
  const fca = FcaCodes.read();
  const listedCodes = new Map<string, Set<string>>();
  for (const [ticker, cnpj] of Object.entries(listedBridge)) {
    let codes = listedCodes.get(cnpj);
    if (codes === undefined) listedCodes.set(cnpj, (codes = new Set()));
    codes.add(ticker);
    for (const code of fca.byCnpj.get(cnpj) ?? []) codes.add(code);
  }
  for (const [cnpj, codes] of listedCodes) listedCodes.set(cnpj, companyCodes(codes));

  // Proventos das deslistadas, pelo nome de pregão (item A4): a consulta da B3
  // responde para companhia que saiu da bolsa. Um nome de pregão pode ser de
  // outra companhia; o preço com direito contra o COTAHIST do papel é o que
  // confere que é a mesma.
  const delistedDividends = new Map<string, CashDividend[]>();
  for (const f of filesIn('data/b3/complemento_deslistadas', /./)) {
    const raw = JSON.parse(readFileSync(f, 'utf8')) as { cnpj: string; consultas: { proventos: unknown[] }[] };
    delistedDividends.set(
      raw.cnpj,
      raw.consultas.flatMap((q) => B3CashDividends.parse(q.proventos)),
    );
  }
  const allCodes = new Set<string>(tickers);
  for (const codes of listedCodes.values()) for (const code of codes) allCodes.add(code);
  const cotahist = readRawCotahist(allCodes);

  // ---- 1. O método nas listadas: FRE contra a contagem oficial da B3 ----
  const registry = B3RegistryCodec.decodePackage(readJson('public/assets/b3/emissores.json'));
  const queryDay = DateTime.utc(2026, 9, 14);
  let listed = 0;
  let listedMatching = 0;
  const seenIssuers = new Set<string>();
  const divergentListed: string[] = [];
  for (const [ticker, cnpj] of Object.entries(listedBridge)) {
    const root = ticker.length >= 4 ? ticker.substring(0, 4) : '';
    if (seenIssuers.has(root)) continue;
    const official = registry.get(root)?.totalShares ?? null;
    const fre = capital.get(cnpj);
    if (official === null || fre === undefined) continue;
    const point = ShareCountHistory.fromFre(fre, {
      events: declaredEvents(splits.get(cnpj) ?? []).map((d) => ({ date: d.approval, totalAfter: d.after })),
      receivedOn: receivedInputs,
    }).at(queryDay);
    if (point === null) continue;
    seenIssuers.add(root);
    listed++;
    const ratio = point.total / official;
    if (Math.abs(ratio - 1) <= b3Margin) {
      listedMatching++;
    } else {
      divergentListed.push(`${root} ${ratio.toFixed(4)}`);
    }
  }

  // ---- 1b. A contagem por data das listadas, para as coortes (item C3) ----
  const listedOutput: Record<string, unknown> = {};
  let listedWithCount = 0;
  let listedEvents = 0;
  let listedLocatedEvents = 0;
  for (const [cnpj, codes] of listedCodes) {
    const declared = declaredEvents(splits.get(cnpj) ?? []);
    // A data ex de cada evento, no primeiro código que o localiza.
    const firstExDate = new Map<number, DateTime>();
    for (const code of codes) {
      const series = cotahist.get(code);
      if (series === undefined || series.length === 0) continue;
      const rawSessions = series.map((p) => p.raw);
      for (let k = 0; k < declared.length; k++) {
        const ev = CorporateEvents.locate(rawSessions, { factor: declared[k]!.factor, approvedOn: declared[k]!.approval });
        if (ev === null) continue;
        const existing = firstExDate.get(k);
        if (existing === undefined || ev.exDate.isBefore(existing)) firstExDate.set(k, ev.exDate);
      }
    }
    listedEvents += declared.length;
    listedLocatedEvents += firstExDate.size;
    const history = ShareCountHistory.fromFre(capital.get(cnpj) ?? [], {
      events: declared.map((d, k) => ({ date: firstExDate.get(k) ?? d.approval, totalAfter: d.after })),
      receivedOn: receivedInputs,
    });
    if (history.points.length === 0) continue;
    listedWithCount++;
    listedOutput[cnpj] = {
      codigos: [...codes].sort(compareStr),
      contagem: history.points.map((p) => ({ desde: day(p.date), acoes: p.total, fonte: p.source.name })),
      classes: CapitalClasses.fromFre(capital.get(cnpj) ?? []).toJson(),
    };
  }
  writeText('data/b3/listadas_contagem.json', JSON.stringify(listedOutput));

  // ---- 2 e 3: as deslistadas ---------------------------------------------
  const output: Record<string, unknown> = {};
  let withCount = 0;
  let withFreEvents = 0;
  let freEvents = 0;
  let located = 0;
  let eventsWithTradingDay = 0;
  let locatedEvents = 0;
  const notLocated: string[] = [];
  let inferred = 0;
  let formMatches = 0;
  let formChecks = 0;
  let priceToBookWithin = 0;
  let priceToBookChecks = 0;
  let usableFiscalYears = 0;
  let companiesWithDividends = 0;
  let securityDividends = 0;
  let checkedDividends = 0;
  let dividendsMatching = 0;
  const priceToBooks: number[] = [];
  const outOfRange: string[] = [];
  for (const [cnpj, c] of Object.entries(bridge)) {
    const papers = Object.keys(c.papeis);
    const declared = declaredEvents(splits.get(cnpj) ?? []);
    // Data ex de cada evento declarado, quando algum papel a localizou: é nela
    // que a contagem muda; sem ela, vale a aprovação.
    const firstExDate = new Map<number, DateTime>();
    if (declared.length > 0) withFreEvents++;
    freEvents += declared.length;

    // Papel com pregão na data: antes de 2010 não há COTAHIST, e fora da vida
    // do papel não há preço a ajustar.
    const tradedOn = (when: DateTime): boolean =>
      papers.some((t) => {
        const s = cotahist.get(t);
        return s !== undefined && s.length > 0 && !s[0]!.date.isAfter(when) && !s[s.length - 1]!.date.isBefore(when);
      });

    // Evento com pregão do papel na data de aprovação é o que se pode
    // localizar.
    const findings = new Set<number>();
    for (const d of declared) if (tradedOn(d.approval)) eventsWithTradingDay++;

    const securities: Record<string, unknown> = {};
    for (const t of papers) {
      const series = cotahist.get(t);
      if (series === undefined || series.length === 0) continue;
      const first = series[0]!;
      const last = series[series.length - 1]!;
      const rawSessions = series.map((p) => p.raw);
      const events: ShareEvent[] = [];
      const origin: string[] = [];
      const securityFindings = new Set<number>();
      for (let k = 0; k < declared.length; k++) {
        const d = declared[k]!;
        const ev = CorporateEvents.locate(rawSessions, { factor: d.factor, approvedOn: d.approval });
        if (ev === null) continue;
        events.push(ev);
        origin.push('fre');
        located++;
        securityFindings.add(k);
        findings.add(k);
        const existing = firstExDate.get(k);
        if (existing === undefined || ev.exDate.isBefore(existing)) firstExDate.set(k, ev.exDate);
      }
      for (const ev of CorporateEvents.detect(rawSessions)) {
        const near = events.some((e) => Math.abs(e.exDate.difference(ev.exDate).inDays) <= 15);
        if (near) continue;
        events.push(ev);
        origin.push('inferido');
        inferred++;
      }
      // Proventos da classe do papel, com data ex na vida dele.
      const shareClass = B3CashDividends.shareClassOf(t);
      const ofSecurity = (delistedDividends.get(cnpj) ?? []).filter(
        (p) => p.shareClass === shareClass && !p.exDate.isBefore(first.date) && !p.exDate.isAfter(last.date),
      );
      securityDividends += ofSecurity.length;
      for (const p of ofSecurity) {
        const withInput = tradingDayUntil(series, p.lastDateWithRights, 0);
        if (p.closeWithRights === null || withInput === null) continue;
        checkedDividends++;
        if (Math.abs(p.closeWithRights / withInput.close - 1) <= 0.01) dividendsMatching++;
      }

      securities[t] = {
        primeiro: day(first.date),
        ultimo: day(last.date),
        proventos: ofSecurity.map((p) => ({
          dataEx: day(p.exDate),
          valor: p.amount,
          tipo: p.kind.key,
          ...(p.closeWithRights !== null ? { precoComDireito: p.closeWithRights } : {}),
        })),
        // Evento declarado com pregão e sem data ex no preço: a série não está
        // ajustada por ele, e a coorte cuja janela o atravessa tem de sair.
        eventosNaoLocalizados: declared
          .filter((d, k) => !securityFindings.has(k) && !first.date.isAfter(d.approval) && !last.date.isBefore(d.approval))
          .map((d) => day(d.approval)),
        eventos: events.map((e, k) => ({ dataEx: day(e.exDate), fator: e.factor, origem: origin[k]! })),
      };
    }

    if ((delistedDividends.get(cnpj) ?? []).length > 0) companiesWithDividends++;
    locatedEvents += findings.size;
    const history = ShareCountHistory.fromFre(capital.get(cnpj) ?? [], {
      events: declared.map((d, k) => ({ date: firstExDate.get(k) ?? d.approval, totalAfter: d.after })),
      receivedOn: receivedInputs,
    });
    if (history.points.length > 0) withCount++;
    for (let k = 0; k < declared.length; k++) {
      const d = declared[k]!;
      if (tradedOn(d.approval) && !findings.has(k)) {
        notLocated.push(`${dartString(c.nome)} ${day(d.approval)} ${d.kind} fator ${d.factor.toFixed(4)}`);
      }
    }

    // 2. Formulário contra formulário.
    const checks: { data: string; razao: number; bate: boolean }[] = [];
    for (const x of composition.get(cnpj) ?? []) {
      const point = history.at(x.date);
      if (point === null) continue;
      formChecks++;
      const ratio = point.total / x.shares;
      // A composição do capital vem na escala do declarante — mil ações, em
      // quem publica em milhares (decisão 70). Mil exatas é a mesma contagem.
      const matches = Math.abs(ratio - 1) <= formsMargin || Math.abs(ratio / 1000 - 1) <= formsMargin;
      if (matches) formMatches++;
      checks.push({ data: day(x.date), razao: ratio, bate: matches });
    }

    // 3. P/VPA no fim de cada exercício, e o exercício utilizável: contagem na
    //    data e pregão no ano seguinte.
    for (const year of c.anosDfp ?? []) {
      const end = DateTime.utc(year, 12, 31);
      const point = history.at(end);
      const pl = equity.get(cnpj)?.get(year) ?? null;
      const withTradingDayAfter = papers.some((t) => cotahist.get(t)?.some((p) => p.date.year === year + 1) ?? false);
      if (point !== null && withTradingDayAfter) usableFiscalYears++;
      if (point === null || pl === null) continue;
      for (const t of papers) {
        const s = cotahist.get(t);
        if (s === undefined) continue;
        const p = tradingDayUntil(s, end, 10);
        if (p === null) continue;
        const priceToBook = (point.total * p.close) / pl;
        priceToBookChecks++;
        priceToBooks.push(priceToBook);
        if (priceToBook >= minPriceToBook && priceToBook <= maxPriceToBook) {
          priceToBookWithin++;
        } else {
          outOfRange.push(`${dartString(c.nome)} ${t} ${year}: ${priceToBook.toFixed(3)}`);
        }
        break;
      }
    }

    output[cnpj] = {
      nome: c.nome ?? null,
      contagem: history.points.map((p) => ({ desde: day(p.date), acoes: p.total, fonte: p.source.name })),
      papeis: securities,
      classes: CapitalClasses.fromFre(capital.get(cnpj) ?? []).toJson(),
      conferenciaComComposicao: checks,
    };
  }

  writeText('data/b3/deslistadas_contagem.json', JSON.stringify(output));
  const summary = {
    medidoEm: '2026-09-15',
    listadas: {
      emissores: listed,
      batemA1pct: listedMatching,
      divergentes: divergentListed,
      companhiasComContagemPorData: listedWithCount,
      eventosDeclarados: listedEvents,
      eventosLocalizados: listedLocatedEvents,
    },
    deslistadas: {
      companhias: Object.keys(bridge).length,
      comContagem: withCount,
      comEventosDeclarados: withFreEvents,
      eventosDeclarados: freEvents,
      eventosComPregaoNaAprovacao: eventsWithTradingDay,
      eventosLocalizados: locatedEvents,
      eventosNaoLocalizados: notLocated,
      papelEventoLocalizado: located,
      papelEventoInferido: inferred,
      composicaoConferida: formChecks,
      composicaoBateA2pct: formMatches,
      pvpaConferido: priceToBookChecks,
      pvpaNaFaixa: priceToBookWithin,
      pvpaMediano: median(priceToBooks),
      pvpaForaDaFaixa: outOfRange,
      exerciciosUtilizaveis: usableFiscalYears,
      companhiasComProventos: companiesWithDividends,
      proventosNaVidaDoPapel: securityDividends,
      proventosComPrecoConferido: checkedDividends,
      proventosQueBatemA1pct: dividendsMatching,
    },
  };
  writeText('docs/validacao/b3_contagem_por_data.json', jsonPretty(summary, ' '));

  const companies = Object.keys(bridge).length;
  outln('== 1. Listadas: FRE em 14/09/2026 contra a contagem oficial ==');
  outln(`  ${listedMatching} de ${listed} a 1%`);
  for (const d of divergentListed.slice(0, 15)) outln(`    ${d}`);
  outln(
    `  contagem por data para as coortes: ${listedWithCount} companhias; ${listedLocatedEvents} de ${listedEvents} eventos ` +
      'declarados localizados no preço',
  );
  outln(`\n== Deslistadas (${companies} companhias da ponte) ==`);
  outln(`  com contagem por data: ${withCount}`);
  outln(
    `  com evento declarado no FRE: ${withFreEvents} (${freEvents} eventos); com pregão na aprovação: ${eventsWithTradingDay}; ` +
      `localizados no preço: ${locatedEvents}; inferidos onde o FRE não declara: ${inferred}`,
  );
  for (const n of notLocated) outln(`    não localizado: ${n}`);
  outln(`  2. FRE × composição do DFP/ITR: ${formMatches} de ${formChecks} a 2%, contando a escala de mil (decisão 70)`);
  const pbMedian = median(priceToBooks);
  outln(
    `  3. P/VPA no fim do exercício: ${priceToBookWithin} de ${priceToBookChecks} entre ${minPriceToBook} e ${maxPriceToBook}; ` +
      `mediana ${pbMedian === null ? 'null' : pbMedian.toFixed(2)}`,
  );
  for (const f of outOfRange.slice(0, 12)) outln(`    ${f}`);
  outln(`  exercícios com contagem na data e pregão no ano seguinte: ${usableFiscalYears}`);
  outln(
    `  4. proventos: ${companiesWithDividends} companhias; ${securityDividends} na vida dos papéis; preço com direito contra o ` +
      `COTAHIST: ${dividendsMatching} de ${checkedDividends} a 1%`,
  );
  outln('\n  gravado data/b3/deslistadas_contagem.json, data/b3/listadas_contagem.json e docs/validacao/b3_contagem_por_data.json');
}
