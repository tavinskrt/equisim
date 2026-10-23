// B46 — empacota a espécie do controle acionário de cada emissor.
//
// Lê o Formulário Cadastral da CVM de todos os anos
// (`data/cvm/fca_cia_aberta_geral_<ano>.csv`), monta o histórico de cada
// companhia por `ShareholderControlHistory.fromFilings` — com a data da
// privatização tirada da coluna `Data_Especie_Controle_Acionario` quando ela é
// plausível — e grava o pacote pela raiz do código de negociação, a mesma chave
// do registro da B3. O aplicativo o lê para declarar o controle estatal na
// avaliação; as medições do item B46 o leem para separar estatais e privadas
// em cada data.
//
// **A data do pacote é declarada, e não lida do relógio**, como nos outros
// pacotes versionados. `--agora` usa o dia, para quando o conjunto for
// atualizado.
//
// Uso:
//   python tool/cvm_baixar.py --docs FCA
//   npm run tool -- control-package

import {
  DateTime,
  ShareholderControl,
  type ShareholderControlFiling,
  ShareholderControlHistory,
  type ShareholderControlPeriod,
} from '../src/core';
import { errln, filesIn, outln, readJson, readLatin1, writeText } from './lib/files';

const output = 'public/assets/cvm/controle.json';

/** A data de referência dos pacotes versionados. */
const reference = DateTime.local(2026, 9, 14);

export function main(args: string[]): void {
  const date = args.includes('--agora') ? DateTime.now() : reference;
  const files = filesIn('data/cvm', /fca_cia_aberta_geral_\d{4}\.csv$/);
  if (files.length === 0) {
    errln('sem FCA em data/cvm. Rode antes:');
    errln('  python tool/cvm_baixar.py --docs FCA');
    process.exitCode = 2;
    return;
  }

  const byCnpj = new Map<string, ShareholderControlFiling[]>();
  for (const f of files) {
    const rows = readLatin1(f).split('\n');
    const header = rows[0]!.trim().split(';');
    const cnpjIndex = header.indexOf('CNPJ_Companhia');
    const iRef = header.indexOf('Data_Referencia');
    const kindIndex = header.indexOf('Especie_Controle_Acionario');
    const iDate = header.indexOf('Data_Especie_Controle_Acionario');
    if ([cnpjIndex, iRef, kindIndex, iDate].includes(-1)) {
      errln(`${f}: colunas do FCA não encontradas`);
      process.exitCode = 1;
      return;
    }
    for (const row of rows.slice(1)) {
      const c = row.trim().split(';');
      if (c.length <= iDate) continue;
      const ref = DateTime.tryParse(c[iRef]!);
      if (ref === null || c[kindIndex]!.trim() === '') continue;
      let list = byCnpj.get(c[cnpjIndex]!);
      if (list === undefined) byCnpj.set(c[cnpjIndex]!, (list = []));
      list.push({ reference: ref, species: c[kindIndex]!, speciesDate: DateTime.tryParse(c[iDate]!) });
    }
  }

  const bridge = readJson<{ ponte: Record<string, string> }>('docs/validacao/ponte_cvm.json').ponte;
  const pkg = new Map<string, ShareholderControlPeriod[]>();
  const withoutFca: string[] = [];
  let changes = 0;
  for (const [ticker, cnpj] of Object.entries(bridge)) {
    const root = ticker.length >= 4 ? ticker.slice(0, 4) : ticker;
    if (pkg.has(root)) continue;
    const history = ShareholderControlHistory.fromFilings(byCnpj.get(cnpj) ?? []);
    if (history.length === 0) {
      withoutFca.push(root);
      continue;
    }
    pkg.set(root, history);
    changes += history.length - 1;
  }

  writeText(output, JSON.stringify(ShareholderControlHistory.encode(pkg, { generatedAt: date })));
  const today = new Map<ShareholderControl, number>();
  for (const c of ShareholderControl.values) {
    today.set(c, [...pkg.values()].filter((p) => ShareholderControlHistory.at(p, date) === c).length);
  }
  outln(`  emissores: ${pkg.size} (${withoutFca.length} sem FCA: ${withoutFca.join(' ')})`);
  outln(
    `  em ${date.toIso8601String().slice(0, 10)}: estatal ${today.get(ShareholderControl.state)}, ` +
      `privado ${today.get(ShareholderControl.private)}, estrangeiro ${today.get(ShareholderControl.foreign)}`,
  );
  outln(`  mudanças de espécie no histórico: ${changes}`);
  for (const [root, periods] of pkg) {
    if (periods.length < 2) continue;
    outln(`    ${root}: ${periods.map((p) => `${p.control.name} desde ${p.since.toIso8601String().slice(0, 10)}`).join(' → ')}`);
  }
  outln(`  gravado ${output}`);
}
