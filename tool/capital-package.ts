// B28 e B29 — empacota os eventos de capital de cada ativo para o aplicativo.
//
// Duas listas por ativo do universo, no pacote `public/assets/cvm/capital.json`:
//
// - **as emissões por valor** do Formulário de Referência conhecidas na data de
//   referência, desde 2023 — a cascata soma ao patrimônio da ponte as que caem
//   depois do balanço usado (item B28);
// - **os eventos de ações** — desdobramento, grupamento e bonificação — desde
//   2019, que cobrem a janela de cinco anos do beta: do quadro do FRE,
//   localizados no preço bruto, do registro da B3 e do `DISMES` do COTAHIST. O
//   preparo completa com eles o ajuste que a fonte de preços deixou de fazer
//   (item B29), e só onde a série dela ainda mostra o salto.
//
// **A data do pacote é declarada, e não lida do relógio**, como nos outros
// pacotes versionados: o mesmo formulário tem de dar o mesmo arquivo.
// `--agora` usa o dia, para quando os dados forem atualizados.
//
// Uso:
//   python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
//   python tool/b3_baixar.py
//   npm run tool -- capital-package
import { CapitalEvents, CapitalEventsCodec, DateTime, type ShareIssue } from '../src/core';
import { readRawCotahist } from './b3/dividends';
import { chain, companyCodes } from './cohorts/as-of-base';
import { issuancesWithoutEvent, ShareEvents } from './cohorts/share-events';
import { FcaCodes } from './cvm/fca-codes';
import { FreIssuances } from './cvm/fre-issues';
import { errln, jsonPretty, outln, readJson, writeText } from './lib/files';

const output = 'public/assets/cvm/capital.json';

/**
 * A data de referência do pacote: o dia em que o FRE e o COTAHIST em disco
 * foram conferidos.
 */
const reference = DateTime.utc(2026, 9, 24);

/**
 * Desde quando entram as emissões: o balanço mais antigo que o aplicativo usa
 * é o do exercício anterior ao último, e o de 2023 cobre com folga.
 */
const issuancesSince = DateTime.utc(2023, 1, 1);

/** Desde quando entram os eventos: a janela do beta tem cinco anos. */
const eventsSince = DateTime.utc(2019, 1, 1);

export function main(args: string[]): void {
  const now = DateTime.now();
  const date = args.includes('--agora') ? DateTime.utc(now.year, now.month, now.day) : reference;
  const issuances = FreIssuances.read();
  if (issuances === null) {
    errln('sem data/cvm/fre. Rode antes:');
    errln('  python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre');
    process.exitCode = 2;
    return;
  }
  const universe = readJson<{ ticker: string }[]>('docs/validacao/universo.json').map((e) => e.ticker);
  const bridge = readJson<{ ponte: Record<string, string> }>('docs/validacao/ponte_cvm.json').ponte;
  const fca = FcaCodes.read();
  const codes = new Map<string, Set<string>>();
  for (const t of universe) {
    const cnpj = bridge[t];
    codes.set(t, companyCodes([t, ...((cnpj === undefined ? undefined : fca.byCnpj.get(cnpj)) ?? [])]));
  }
  const all = new Set<string>();
  for (const c of codes.values()) for (const code of c) all.add(code);
  const raw = readRawCotahist(all);
  const events = ShareEvents.read({ issuances });

  const pkg = new Map<string, CapitalEvents>();
  let withIssuance = 0;
  let withEvent = 0;
  let issuanceCount = 0;
  let eventCount = 0;
  for (const t of universe) {
    const cnpj = bridge[t] ?? null;
    const rawSessions = chain(t, codes.get(t) ?? [t], raw);
    const ofTicker = events.ofSecurity({ cnpj, ticker: t, rawSessions });
    // O quadro de aumentos do FRE, até 2023, e a variação do capital
    // integralizado que nenhum evento confirmado no preço explica, depois.
    const ofIssuance: ShareIssue[] =
      cnpj === null
        ? []
        : [
            ...issuances.known(cnpj, date),
            ...issuancesWithoutEvent(
              issuances.byCapitalChange(cnpj, date),
              rawSessions,
              events.ofSecurity({ cnpj, ticker: t, rawSessions, withCount: false }),
            ),
          ].filter((i) => !i.date.isBefore(issuancesSince));
    const ofSecurity = ofTicker.filter((e) => !e.exDate.isBefore(eventsSince));
    const c = new CapitalEvents({ issues: ofIssuance, shareEvents: ofSecurity });
    if (c.isEmpty) continue;
    pkg.set(t, c);
    if (ofIssuance.length > 0) withIssuance++;
    if (ofSecurity.length > 0) withEvent++;
    issuanceCount += ofIssuance.length;
    eventCount += ofSecurity.length;
  }
  writeText(output, `${jsonPretty(CapitalEventsCodec.encodePackage(pkg, { generatedAt: date }))}\n`);
  outln(
    `${universe.length} ativos: ${withIssuance} com emissão por valor (${issuanceCount}), ` +
      `${withEvent} com evento de ações (${eventCount})`,
  );
  outln(`escrito ${output}`);
}
