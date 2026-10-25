// A4 — empacota os proventos da B3 para o aplicativo.
//
// O beta do aplicativo sai do retorno total do ativo (decisão 89), e o índice
// de retorno total precisa do provento **e** do preço com direito
// (`TotalReturnIndex`). Entra no pacote o provento com data ex a partir de
// 2015 — a janela do beta é de cinco anos, e a folga cobre a avaliação de
// qualquer data desde 2020 — e com preço com direito publicado pela B3: sem
// ele, o provento não entraria no índice e só ocuparia espaço.
//
// Uso:
//   python tool/b3_complemento_baixar.py
//   npm run tool -- b3-dividends-package
import { statSync } from 'node:fs';

import { type CashDividend, CashDividendsCodec, compareStr, DateTime } from '../src/core';
import { readDividends } from './b3/dividends';
import { filesIn, outln, readJson, writeText } from './lib/files';

const output = 'public/assets/b3/proventos.json';
const since = DateTime.utc(2015, 1, 1);

export function main(_args: string[]): void {
  const all = readDividends();
  const pkg = new Map<string, CashDividend[]>();
  let included = 0;
  let withoutPrice = 0;
  let old = 0;
  for (const [issuer, dividends] of all) {
    const list: CashDividend[] = [];
    for (const p of dividends) {
      if (p.exDate.isBefore(since)) {
        old++;
        continue;
      }
      if (p.closeWithRights === null) {
        withoutPrice++;
        continue;
      }
      list.push(p);
    }
    if (list.length > 0) {
      pkg.set(issuer, list);
      included += list.length;
    }
  }
  const queryDir = filesIn('data/b3/complemento', /.*/)
    .map((f) => readJson<{ consultadoEm: string }>(f).consultadoEm)
    .reduce((a, b) => (compareStr(b, a) < 0 ? b : a), '9999-12-31');
  writeText(output, JSON.stringify(CashDividendsCodec.encode(pkg, { generatedAt: DateTime.parse(`${queryDir}T00:00:00Z`) })));
  outln(`  emissores: ${pkg.size}  proventos: ${included}`);
  outln(`  fora: ${old} antes de 2015, ${withoutPrice} sem preço com direito`);
  outln(`  consulta mais antiga: ${queryDir}`);
  outln(`  tamanho: ${(statSync(output).size / 1024).toFixed(0)} KB`);
  outln(`  gravado ${output}`);
}
