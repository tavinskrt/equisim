// A2.1 — empacota as cotações recentes do Tesouro para o aplicativo.
//
// **Na web o pacote é a única fonte** da curva (decisão 86): rode os dois
// comandos abaixo antes de cada `npm run build`. Com mais de
// `TreasuryCurve.fallbackDays` dias, o pacote não serve, e a avaliação recua
// para os dois pontos, declarando por quê.
//
// **A curva da entrada congelada é outro arquivo.** O gabarito e as medições
// sobre 14/09/2026 leem `tool/validation/curva_congelada.json`, gerado uma vez
// com `--ate 2026-09-14`, e não este pacote: regerá-lo para publicar tiraria a
// curva da entrada congelada (ver `frozenCurve`, em validation/frozen.ts).
//
// Uso:
//   python tool/tesouro_baixar.py
//   npm run tool -- curve-package
//   npm run tool -- curve-package --ate 2026-09-14 --saida tool/validation/curva_congelada.json

import { type DateTime, TreasuryQuotesCodec } from '../src/core';
import { readTreasury } from './curve-link';
import { fail, flagValue, outln, writeText } from './lib/files';

const appPackage = 'public/assets/tesouro/curva.json';

/** Datas-base guardadas: as dez mais recentes cobrem duas semanas de pregão. */
const baseDates = 10;

const isoDay = (d: DateTime): string => d.toIso8601String().slice(0, 10);

export function main(args: string[]): void {
  // `--ate`: só datas-base até o dia dado, inclusive. Sem ele, as mais recentes.
  const until = flagValue(args, '--ate');
  if (until !== null && !/^\d{4}-\d{2}-\d{2}$/.test(until)) fail(`--ate espera AAAA-MM-DD, e recebeu "${until}"`);
  const output = flagValue(args, '--saida') ?? appPackage;

  const allRows = readTreasury('data/tesouro/precotaxatesourodireto.csv');
  const byKey = new Map<string, DateTime>();
  for (const q of allRows) {
    if (until !== null && isoDay(q.baseDate) > until) continue;
    byKey.set(q.baseDate.key, q.baseDate);
  }
  const bases = [...byKey.values()].sort((a, b) => b.compareTo(a));
  if (bases.length === 0) fail(until === null ? 'a base do Tesouro não tem cotação' : `a base do Tesouro não tem cotação até ${until}`);
  const store = new Set(bases.slice(0, baseDates).map((d) => d.key));
  const quotes = allRows.filter((q) => store.has(q.baseDate.key));
  const pkg = TreasuryQuotesCodec.encode(quotes, { generatedAt: bases[0]! });
  writeText(output, JSON.stringify(pkg));
  const kept = bases.slice(0, baseDates);
  const oldest = kept.reduce((a, b) => (a.isBefore(b) ? a : b));
  outln(`  datas-base: ${store.size}, de ${isoDay(oldest)} a ${isoDay(bases[0]!)}`);
  outln(`  cotações: ${quotes.length}`);
  outln(`  gravado ${output}`);
}
