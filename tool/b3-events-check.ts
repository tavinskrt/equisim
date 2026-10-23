// A3.1 — o registro oficial da B3 contra a inferência pelo preço.
//
// `CorporateEvents` infere desdobramento, grupamento e bonificação da razão
// entre pregões (decisão 75). O registro da B3 declara o fator (decisão 83).
// Aqui os dois se encontram, papel a papel, de 2010 em diante, para os
// emissores do universo:
//
//   cobertura  evento oficial que a inferência encontrou (mesma data ex, a três
//              dias, e fator a 6%)
//   precisão   evento inferido que o registro confirma
//
// Uso:
//   python tool/b3_baixar.py
//   python tool/b3_companhias_baixar.py
//   npm run tool -- b3-events-check
import { readFileSync } from 'node:fs';

import {
  B3Registry,
  CorporateEvents,
  DateTime,
  type JsonObject,
  type OfficialShareEvent,
  RawQuote,
  type ShareEvent,
  tryParseInt,
} from '../src/core';
import { filesIn, outln, readJson, splitLines } from './lib/files';

export function main(_args: string[]): void {
  const registryFiles = filesIn('data/b3/companhias', /.*/);
  // Emissores oficiais e seus eventos, por ISIN.
  const officialEvents = new Map<string, OfficialShareEvent[]>();
  for (const f of registryFiles) {
    const raw = readJson<JsonObject>(f);
    const queryDir = DateTime.parse(raw['consultadoEm'] as string);
    for (const c of raw['resposta'] as JsonObject[]) {
      const e = B3Registry.issuer(c, { consultedOn: queryDir });
      if (e === null) continue;
      for (const ev of e.events) {
        if (ev.exDate.year < 2010) continue;
        let list = officialEvents.get(ev.isin);
        if (list === undefined) officialEvents.set(ev.isin, (list = []));
        list.push(ev);
      }
    }
  }

  // Séries brutas do COTAHIST, só dos ISINs que o registro cobre.
  const series = new Map<string, RawQuote[]>();
  const files = filesIn('data/b3', /avista_\d{4}\.csv$/);
  const registryIsins = new Set<string>();
  for (const f of registryFiles) {
    for (const c of readJson<JsonObject>(f)['resposta'] as JsonObject[]) {
      for (const e of (c['stockDividends'] as JsonObject[] | null | undefined) ?? []) registryIsins.add(e['isinCode'] as string);
    }
  }
  for (const f of files) {
    for (const l of splitLines(readFileSync(f, 'utf8')).slice(1)) {
      const c = l.split(';');
      if (c.length < 9) continue;
      const isin = c[2]!;
      // Só papéis com algum evento declarado no registro. A precisão é medida
      // sobre eles: papel sem evento declarado nunca entra, e um falso
      // positivo nele não é contado.
      if (!registryIsins.has(isin)) continue;
      // Em UTC: data em hora local cruza o horário de verão e perde uma hora.
      const date = DateTime.tryParse(`${c[0]}T00:00:00Z`);
      const close = tryParseInt(c[5]!);
      const factor = tryParseInt(c[6]!);
      const distributionCode = tryParseInt(c[7]!);
      if (date === null || close === null || factor === null || distributionCode === null) continue;
      let list = series.get(isin);
      if (list === undefined) series.set(isin, (list = []));
      list.push(new RawQuote(date, close / 100 / (factor === 0 ? 1 : factor), distributionCode));
    }
  }

  const matchesEvent = (inferred: ShareEvent, official: OfficialShareEvent): boolean =>
    Math.abs(inferred.exDate.difference(official.exDate).inDays) <= 3 &&
    Math.abs(Math.log(inferred.factor / official.factor)) <= Math.log(1.06);

  let officialWithPrice = 0;
  let found = 0;
  let inferred = 0;
  let confirmed = 0;
  const missedBySize = new Map<string, number>();
  const foundBySize = new Map<string, number>();
  const falsePositives: string[] = [];
  const band = (f: number): string => {
    const a = f >= 1 ? f : 1 / f;
    if (a < 1.21) return 'até 20% (bonificação pequena)';
    if (a < 1.6) return '21% a 60%';
    if (a < 2.5) return '1,6x a 2,5x';
    return 'acima de 2,5x';
  };

  for (const [isin, quotes] of series) {
    quotes.sort((a, b) => a.date.compareTo(b.date));
    const first = quotes[0]!.date;
    const last = quotes[quotes.length - 1]!.date;
    const ofIsin = (officialEvents.get(isin) ?? []).filter((o) => !o.exDate.isBefore(first) && !o.exDate.isAfter(last));
    const detected = CorporateEvents.detect(quotes);
    inferred += detected.length;
    for (const d of detected) {
      if (ofIsin.some((o) => matchesEvent(d, o))) {
        confirmed++;
      } else if (falsePositives.length < 25) {
        falsePositives.push(
          `${isin} ${d.exDate.toIso8601String().slice(0, 10)} ×${d.factor.toFixed(3)} (razão ${d.observedRatio.toFixed(3)})`,
        );
      }
    }
    for (const o of ofIsin) {
      officialWithPrice++;
      const k = band(o.factor);
      if (detected.some((d) => matchesEvent(d, o))) {
        found++;
        foundBySize.set(k, (foundBySize.get(k) ?? 0) + 1);
      } else {
        missedBySize.set(k, (missedBySize.get(k) ?? 0) + 1);
      }
    }
  }

  const pc = (a: number, b: number): string => (b === 0 ? '—' : `${((100 * a) / b).toFixed(1)}%`);
  outln('== Registro da B3 × inferência pelo preço, 2010 em diante ==\n');
  outln(`  ISINs com evento declarado e pregão: ${series.size}`);
  outln(`  eventos oficiais dentro da série de preço: ${officialWithPrice}`);
  outln(`  cobertura — oficiais que a inferência encontrou: ${found} (${pc(found, officialWithPrice)})`);
  outln(`  precisão — inferidos que o registro confirma: ${confirmed} de ${inferred} (${pc(confirmed, inferred)})`);
  outln('\n  cobertura por tamanho do fator:');
  for (const k of ['até 20% (bonificação pequena)', '21% a 60%', '1,6x a 2,5x', 'acima de 2,5x']) {
    const a = foundBySize.get(k) ?? 0;
    const p = missedBySize.get(k) ?? 0;
    outln(`    ${k.padEnd(32)} ${pc(a, a + p).padStart(6)}  (${a} de ${a + p})`);
  }
  outln('\n  inferidos sem evento oficial (amostra):');
  for (const f of falsePositives) outln(`    ${f}`);
}
