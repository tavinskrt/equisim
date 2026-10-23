// A1.9 — empacota os documentos da CVM do universo para o aplicativo.
//
// Lê a base ingerida, fica só com os tickers do universo e só com os campos que
// o motor lê, e grava no formato compacto de `CvmDocumentCodec`. O aplicativo
// carrega o pacote como asset e o mescla por `CvmFundamentalsRepository`.
//
// Uso:
//   npm run tool -- cvm-ingest data/cvm
//   npm run tool -- cvm-package
import { readFileSync, statSync } from 'node:fs';
import { gzipSync } from 'node:zlib';

import { CvmDocumentCodec, DateTime } from '../src/core';
import { loadDocuments } from './cvm/documents';
import { outln, readJson, writeText } from './lib/files';

const output = 'public/assets/cvm/documentos.json';

export function main(_args: string[]): void {
  const universe = new Set(readJson<{ ticker: string }[]>('docs/validacao/universo.json').map((e) => e.ticker));
  const docs = loadDocuments('data/cvm_exercicios.json', { onlyTickers: universe });

  const pkg = CvmDocumentCodec.encodePackage(docs, { generatedAt: DateTime.now() });
  writeText(output, JSON.stringify(pkg));

  const bytes = statSync(output).size;
  const gz = gzipSync(readFileSync(output)).length;
  let total = 0;
  for (const v of docs.values()) total += v.length;
  outln('== pacote da CVM para o aplicativo ==');
  outln(`  tickers: ${docs.size} de ${universe.size}`);
  outln(`  documentos: ${total}`);
  outln(`  tamanho: ${(bytes / 1e6).toFixed(2)} MB (${(gz / 1e6).toFixed(2)} MB comprimido)`);
  outln(`  gravado ${output}`);
}
