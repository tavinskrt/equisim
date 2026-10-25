// A2.1 — empacota as cotações recentes do Tesouro para o aplicativo.
//
// **Na web o pacote é a única fonte** da curva (decisão 86): rode os dois
// comandos abaixo antes de cada `npm run build`. Com mais de
// `TreasuryCurve.fallbackDays` dias, o pacote não serve, e a avaliação recua
// para os dois pontos, declarando por quê.
//
// Uso:
//   python tool/tesouro_baixar.py
//   npm run tool -- curve-package

import { type DateTime, TreasuryQuotesCodec } from '../src/core';
import { readTreasury } from './curve-link';
import { outln, writeText } from './lib/files';

const output = 'public/assets/tesouro/curva.json';

/** Datas-base guardadas: as dez mais recentes cobrem duas semanas de pregão. */
const baseDates = 10;

export function main(_args: string[]): void {
  const allRows = readTreasury('data/tesouro/precotaxatesourodireto.csv');
  const byKey = new Map<string, DateTime>();
  for (const q of allRows) byKey.set(q.baseDate.key, q.baseDate);
  const bases = [...byKey.values()].sort((a, b) => b.compareTo(a));
  const store = new Set(bases.slice(0, baseDates).map((d) => d.key));
  const quotes = allRows.filter((q) => store.has(q.baseDate.key));
  const pkg = TreasuryQuotesCodec.encode(quotes, { generatedAt: bases[0]! });
  writeText(output, JSON.stringify(pkg));
  const kept = bases.slice(0, baseDates);
  const oldest = kept.reduce((a, b) => (a.isBefore(b) ? a : b));
  outln(`  datas-base: ${store.size}, de ${oldest.toIso8601String().slice(0, 10)} a ${bases[0]!.toIso8601String().slice(0, 10)}`);
  outln(`  cotações: ${quotes.length}`);
  outln(`  gravado ${output}`);
}
