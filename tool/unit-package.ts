// B16 — empacota a composição declarada das units para o aplicativo.
//
// A razão de unidade era inferida do valor de mercado, e só acerta quando
// ordinária e preferencial valem o mesmo (item B16,
// `docs/validacao/ponte_por_papel.md` §3). A composição que a companhia declara
// no quadro de valores mobiliários da FCA é fonte primária e datada; este
// programa a lê, ano a ano, e grava o pacote que o aplicativo carrega como
// asset.
//
// **O código de negociação da FCA não serve de chave**, e a medição do A1 já
// dizia por quê: a coluna é texto livre, vem em branco em 44% das linhas e
// traz zeros no BTG — a BPAC11 declara a composição sob `000000`. A chave é o
// **CNPJ**, pela ponte do registro da B3 (decisão 82).
//
// **A data do pacote é declarada, e não lida do relógio.** Rodar o programa
// hoje e amanhã sobre a mesma FCA tem de produzir o mesmo arquivo: a
// composição não muda, e um `geradoEm` do relógio geraria diff espúrio no
// repositório. O padrão é a data de referência dos pacotes versionados, e
// `--agora` usa o dia, para quando o conjunto for atualizado — o mesmo arranjo
// de `beta-prior-package`.
//
// Uso:
//   python tool/cvm_baixar.py --docs FCA
//   npm run tool -- unit-package
import { compareNum, compareStr, DateTime, type UnitComposition, UnitCompositionCodec } from '../src/core';
import { FcaCodes } from './cvm/fca-codes';
import { errln, outln, readJson, writeText } from './lib/files';

const output = 'public/assets/cvm/units.json';

/** A data de referência dos pacotes versionados. */
const reference = DateTime.local(2026, 9, 14);

export function main(args: string[]): void {
  const date = args.includes('--agora') ? DateTime.now() : reference;
  const universe = readJson<{ ticker: string }[]>('docs/validacao/universo.json').map((e) => e.ticker);
  const bridge = readJson<{ ponte: Record<string, string> }>('docs/validacao/ponte_cvm.json').ponte;

  const fca = FcaCodes.read();
  if (fca.unitsByCnpj.size === 0) {
    errln('sem FCA em data/cvm. Rode antes:');
    errln('  python tool/cvm_baixar.py --docs FCA');
    process.exitCode = 2;
    return;
  }

  // Unit é a classe 11 da B3. A regra é do formato do código, e não de uma
  // lista: um papel novo não pode depender de alguém lembrar de cadastrá-lo.
  const units = universe.filter((t) => t.endsWith('11'));
  const pkg = new Map<string, UnitComposition[]>();
  const without: string[] = [];
  for (const t of units) {
    const cnpj = bridge[t];
    const declared = cnpj === undefined ? undefined : fca.unitsByCnpj.get(cnpj);
    if (declared === undefined || declared.length === 0) {
      without.push(t);
      continue;
    }
    pkg.set(t, declared);
  }

  writeText(output, JSON.stringify(UnitCompositionCodec.encodePackage(pkg, { generatedAt: date })));

  outln('== composição declarada das units ==');
  for (const t of [...pkg.keys()].sort(compareStr)) {
    const c = pkg.get(t)!.sort((a, b) => compareNum(a.year, b.year));
    const years = `${c[0]!.year}–${c[c.length - 1]!.year}`;
    const shares = [...new Set(c.map((x) => x.shares))].sort(compareNum);
    outln(`  ${t}  ${years}  ${shares.join('/')} ações  "${c[c.length - 1]!.declared}"`);
  }
  outln(`  ${pkg.size} de ${units.length} units do universo`);
  if (without.length > 0) {
    // Sem declaração o motor recua para a razão medida — e passa a dizer que
    // ela foi inferida, que é o que o item B16 pede.
    outln(`  sem composição declarada: ${without.join(', ')}`);
  }
  outln(`  gravado ${output}`);
}
