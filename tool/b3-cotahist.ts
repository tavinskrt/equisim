// A3 — COTAHIST da B3: eventos de ações e preço de quem deixou de existir.
//
// Lê os arquivos anuais do COTAHIST (fechamento bruto de todo papel negociado),
// infere os eventos de ações por `CorporateEvents`, ajusta a série, e confere
// contra o `close` da fonte de mercado — que já vem ajustado por desdobramento,
// grupamento e bonificação. **Depois do ajuste os dois têm de bater**; onde não
// batem, ou o evento não foi detectado, ou foi inventado.
//
// Uso:
//   curl -O https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A2024.ZIP
//   (descompactar em data/b3)
//   npm run tool -- b3-cotahist data/b3
import { readdirSync, statSync } from 'node:fs';

import { compareNum, compareStr, CorporateEvents, DateRange, DateTime, RawQuote, type ShareEvent, Ticker, tryParseInt } from '../src/core';
import { errln, fail, jsonPretty, outln, readJson, readLatin1, splitLines, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

/** Um papel no COTAHIST: ISIN, nome e fechamentos brutos. */
class Security {
  isin = '';
  name = '';
  readonly tradingDays: RawQuote[] = [];
  constructor(readonly ticker: string) {}
}

/**
 * Lê um arquivo anual, só mercado à vista e lote padrão.
 *
 * Layout do registro `01`, posições da B3 (base 1): data 3–10, BDI 11–12,
 * ticker 13–24, mercado 25–27, nome 28–39, fechamento 109–121 (duas casas
 * implícitas), ISIN 231–242, `DISMES` 243–245.
 */
function read(path: string, securities: Map<string, Security>): void {
  for (const l of splitLines(readLatin1(path))) {
    if (l.length < 245 || !l.startsWith('01')) continue;
    if (l.slice(24, 27) !== '010') continue; // à vista
    if (l.slice(10, 12) !== '02') continue; // lote padrão
    const tk = l.slice(12, 24).trim();
    // Em UTC: data em hora local cruza o horário de verão e perde uma hora.
    const date = DateTime.tryParse(`${l.slice(2, 6)}-${l.slice(6, 8)}-${l.slice(8, 10)}T00:00:00Z`);
    const cents = tryParseInt(l.slice(108, 121));
    const dismes = tryParseInt(l.slice(242, 245));
    if (date === null || cents === null || dismes === null) continue;
    let p = securities.get(tk);
    if (p === undefined) securities.set(tk, (p = new Security(tk)));
    p.isin = l.slice(230, 242).trim();
    p.name = l.slice(27, 39).trim();
    p.tradingDays.push(new RawQuote(date, cents / 100.0, dismes));
  }
}

const dayKey = (d: DateTime): string => DateTime.utc(d.year, d.month, d.day).key;

export async function main(args: string[]): Promise<void> {
  const dir = args.length === 0 ? 'data/b3' : args[0]!;
  let files: string[] = [];
  try {
    files = readdirSync(dir)
      .map((name) => `${dir}/${name}`)
      .filter((f) => f.toUpperCase().endsWith('.TXT') && statSync(f).isFile())
      .sort(compareStr);
  } catch {
    files = [];
  }
  if (files.length === 0) fail(`nenhum COTAHIST_A*.TXT em ${dir}`);

  const securities = new Map<string, Security>();
  for (const f of files) {
    errln(`  lendo ${f}`);
    read(f, securities);
  }

  const uni = new Set(readJson<{ ticker: string }[]>('docs/validacao/universo.json').map((e) => e.ticker));

  let events = 0;
  const perShare = new Map<string, ShareEvent[]>();
  for (const p of securities.values()) {
    const e = CorporateEvents.detect(p.tradingDays);
    if (e.length > 0) perShare.set(p.ticker, e);
    events += e.length;
  }

  outln(`== COTAHIST — ${files.length} arquivo(s) ==\n`);
  outln(`  papéis à vista, lote padrão: ${securities.size}`);
  outln(`  do universo de hoje presentes: ${[...uni].filter((t) => securities.has(t)).length} de ${uni.size}`);
  outln(`  fora do universo de hoje: ${[...securities.keys()].filter((t) => !uni.has(t)).length}`);
  outln(`  eventos de ações detectados: ${events} em ${perShare.size} papéis`);
  for (const [tk, list] of [...perShare].slice(0, 30)) {
    outln(`    ${tk.padEnd(7)} ${list.map((x) => `${x.exDate.toIso8601String().slice(0, 10)} ×${x.factor.toFixed(3)}`).join('  ')}`);
  }

  // --- Conferência contra o close ajustado da fonte de mercado -------------
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    let days = 0;
    let matching = 0;
    let checkedSecurities = 0;
    const badDays: string[] = [];
    const discordant = new Map<string, { days: number; bad: number; worst: number }>();
    for (const tk of uni) {
      const p = securities.get(tk);
      if (p === undefined || p.tradingDays.length === 0) continue;
      const dates = p.tradingDays.map((q) => q.date);
      const ini = dates.reduce((a, b) => (a.isBefore(b) ? a : b));
      const end = dates.reduce((a, b) => (a.isAfter(b) ? a : b));
      const r = await ctx.prices.daily(Ticker.parse(tk), new DateRange(ini, end));
      if (r.isErr) continue;
      const market = new Map<string, number>();
      for (const pt of r.unwrap().points) market.set(dayKey(pt.date), pt.close);
      const adjusted = CorporateEvents.adjust(p.tradingDays, perShare.get(tk) ?? []);
      // **Retorno diário, e não nível.** A fonte de mercado ajusta pelos
      // eventos até HOJE; com anos parciais do COTAHIST, um evento fora da
      // janela vira deslocamento constante em todo pregão — foi o que a
      // primeira conferência mediu (68%, com papéis discordando em 499 de 499
      // dias e zero eventos). No retorno o deslocamento some, e o que resta é
      // evento não detectado ou inventado.
      let d = 0;
      let bad = 0;
      let worst = 0.0;
      for (let k = 1; k < adjusted.length; k++) {
        const a0 = adjusted[k - 1]!;
        const a1 = adjusted[k]!;
        if (a1.date.difference(a0.date).inDays > 7) continue;
        const m0 = market.get(dayKey(a0.date));
        const m1 = market.get(dayKey(a1.date));
        if (m0 === undefined || m1 === undefined || m0 <= 0 || m1 <= 0 || a0.close <= 0) continue;
        d++;
        const deviation = Math.abs(a1.close / a0.close / (m1 / m0) - 1);
        if (deviation <= 0.01) {
          matching++;
        } else {
          bad++;
          if (deviation > worst) worst = deviation;
          badDays.push(
            `${tk} ${a1.date.toIso8601String().slice(0, 10)} cotahist ${(a1.close / a0.close).toFixed(4)} mercado ${(m1 / m0).toFixed(4)}`,
          );
        }
      }
      if (d === 0) continue;
      checkedSecurities++;
      days += d;
      if (bad > 0) discordant.set(tk, { days: d, bad, worst });
    }
    outln('\n== Conferência contra o close ajustado da fonte ==');
    outln(`  papéis conferidos: ${checkedSecurities}`);
    outln(`  pares de pregões conferidos (retorno diário): ${days}`);
    outln(`  retornos que batem a 1%: ${matching} (${days === 0 ? '—' : ((100 * matching) / days).toFixed(2)}%)`);
    outln(`  papéis com algum pregão discordante: ${discordant.size}`);
    const worst = [...discordant].sort((a, b) => compareNum(b[1].bad, a[1].bad));
    for (const [tk, v] of worst.slice(0, 15)) {
      outln(
        `    ${tk.padEnd(7)} ${v.bad}/${v.days} retornos fora de 1%, pior ${(100 * v.worst).toFixed(1)}%` +
          `   eventos: ${perShare.get(tk)?.length ?? 0}`,
      );
    }

    outln('');
    outln('  amostra de retornos discordantes:');
    for (const x of badDays.slice(0, 25)) outln(`    ${x}`);

    const out: Record<string, unknown> = {};
    for (const [tk, list] of perShare) {
      out[tk] = list.map((x) => ({ dataEx: x.exDate.toIso8601String().slice(0, 10), fator: x.factor, razaoObservada: x.observedRatio }));
    }
    writeText('docs/validacao/b3_eventos.json', jsonPretty(out));
    outln('\n  gravado docs/validacao/b3_eventos.json');
  } finally {
    await ctx.dispose();
  }
}
