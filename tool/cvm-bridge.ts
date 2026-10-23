// Constrói a ponte ticker -> CNPJ com as regras do núcleo, sobre o FCA real.
//
// A lógica mora em `CvmBridge`, no núcleo, e é testada lá. Isto aqui só a
// alimenta com os arquivos e mede a cobertura contra o universo.
//
// Uso:
//   npm run tool -- cvm-bridge <diretorio-com-os-csv-extraidos>
import { existsSync } from 'node:fs';

import { compareStr, CvmBridge, type JsonObject, tryParseInt } from '../src/core';
import { readQuotedCsv as readCsv } from './cvm/quoted-csv';
import { filesIn, jsonPretty, outln, readJson, writeText } from './lib/files';

export function main(args: string[]): void {
  const dir = args.length === 0 ? '.' : args[0]!;

  // --- Regra 1: Codigo_Negociacao com formato de ticker, em todos os FCA ---
  const byCode = new Map<string, Set<string>>();
  let fcaRows = 0;
  let blank = 0;
  let discarded = 0;
  for (const f of filesIn(dir, /fca_cia_aberta_valor_mobiliario_/)) {
    for (const r of readCsv(f)) {
      fcaRows++;
      const code = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
      if (code === '') {
        blank++;
        continue;
      }
      if (!CvmBridge.looksLikeTicker(code)) {
        discarded++;
        continue;
      }
      let set = byCode.get(code);
      if (set === undefined) byCode.set(code, (set = new Set()));
      set.add(r['CNPJ_Companhia'] ?? '');
    }
  }
  const ambiguous = new Map([...byCode].filter(([, v]) => v.size > 1));
  const uniqueCode = new Map([...byCode].filter(([, v]) => v.size === 1).map(([k, v]) => [k, [...v][0]!] as const));

  // --- Regra 3: nome exato contra o DENOM_CIA ---
  const byName = new Map<string, string>();
  for (const n of ['dfp_cia_aberta_2024.csv', 'itr_cia_aberta_2024.csv']) {
    const f = `${dir}/${n}`;
    if (!existsSync(f)) continue;
    for (const r of readCsv(f)) {
      const name = r['DENOM_CIA'];
      const cnpj = r['CNPJ_CIA'];
      if (name === undefined || cnpj === undefined) continue;
      const key = CvmBridge.normalizeName(name);
      if (!byName.has(key)) byName.set(key, cnpj);
    }
  }

  // --- Regra 0: registro oficial da B3 (decisão 82) ---
  // Emissor → código CVM, de data/b3/companhias; código CVM → CNPJ, dos
  // metadados de DFP e ITR de todos os anos. Ausente o registro, a regra só
  // não responde. Os arquivos são lidos em ordem de nome, para que "o último
  // vence" seja sempre o mesmo.
  const cvmToCnpj = new Map<string, string>();
  for (const f of filesIn(dir, /^(dfp|itr)_cia_aberta_\d{4}\.csv$/)) {
    for (const r of readCsv(f)) {
      const cd = tryParseInt(r['CD_CVM'] ?? '');
      const cnpj = r['CNPJ_CIA'];
      if (cd !== null && cnpj !== undefined) cvmToCnpj.set(String(cd), cnpj);
    }
  }
  const byOfficialRegistry = new Map<string, string>();
  for (const f of filesIn('data/b3/companhias', /.*/)) {
    const raw = readJson<JsonObject>(f);
    for (const c of raw['resposta'] as JsonObject[]) {
      const cd = tryParseInt(String(c['codeCVM']));
      const cnpj = cd === null ? undefined : cvmToCnpj.get(String(cd));
      const code = c['code'];
      if (typeof code === 'string' && cnpj !== undefined) byOfficialRegistry.set(code, cnpj);
    }
  }

  // --- Universo ---
  const uni = readJson<{ ticker: string; nome: string | null }[]>('docs/validacao/universo.json');
  const tickers = uni.map((u) => u.ticker);
  const names = new Map(uni.filter((u) => u.nome !== null).map((u) => [u.ticker, u.nome!] as const));

  const withoutOfficial = CvmBridge.resolveUniverse(tickers, { byCode: uniqueCode, byName, names });
  const bridge = CvmBridge.resolveUniverse(tickers, { byCode: uniqueCode, byName, names, byOfficialRegistry });
  const missingTickers = tickers.filter((t) => !bridge.has(t));
  const companies = new Set(bridge.values()).size;

  outln('== Ponte ticker -> CNPJ, pelas regras do núcleo ==\n');
  outln(`  linhas de FCA lidas        : ${fcaRows}`);
  outln(`    em branco                : ${blank} (${((100 * blank) / fcaRows).toFixed(1)}%)`);
  outln(`    descartadas pelo formato : ${discarded}`);
  outln(`    códigos com CNPJ único   : ${uniqueCode.size}`);
  outln(`    AMBÍGUOS                 : ${ambiguous.size} ${[...ambiguous.keys()].slice(0, 6).join(', ')}`);
  outln('');
  outln(`  universo: ${tickers.length}`);
  outln(`  resolvidos: ${bridge.size} (${((100 * bridge.size) / tickers.length).toFixed(1)}%)`);
  outln(`  companhias distintas: ${companies}`);
  outln(`  sem ponte: ${missingTickers.length}  ${missingTickers.join(' ')}`);
  outln(`  emissores no registro oficial da B3: ${byOfficialRegistry.size}`);
  const corrected: string[] = [];
  for (const [t, cnpj] of bridge) {
    const before = withoutOfficial.get(t);
    if (before !== undefined && before !== cnpj) corrected.push(`${t} ${before} → ${cnpj}`);
  }
  outln(`  corrigidos pelo registro oficial: ${corrected.length}`);
  for (const c of corrected) outln(`    ${c}`);
  const unexpected = missingTickers.filter((t) => !CvmBridge.withoutBridge.has(t));
  outln(`  fora do que o núcleo declara em semPonte: ${unexpected.length === 0 ? 'nenhum' : unexpected.join(' ')}`);

  // A regra geral: uma companhia alcançada por duas raízes tem uma ponte
  // errada, e nenhuma medição interna diz qual.
  const conflicts = CvmBridge.rootConflicts(bridge);
  outln('');
  outln(`  companhias alcançadas por mais de uma raiz: ${conflicts.size}`);
  for (const [cnpj, roots] of conflicts) {
    const reached = [...bridge].filter(([, v]) => v === cnpj).map(([k]) => k).sort(compareStr);
    outln(`    ${cnpj}  raízes ${[...roots].join('/')}  -> ${reached.join(' ')}`);
  }

  writeText(
    'docs/validacao/ponte_cvm.json',
    jsonPretty({
      medidoEm: '2026-09-14',
      universo: tickers.length,
      resolvidos: bridge.size,
      companhias: companies,
      semPonte: missingTickers,
      ponte: Object.fromEntries(bridge),
    }),
  );
  outln('\n  gravado docs/validacao/ponte_cvm.json');
}
