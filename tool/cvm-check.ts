// Roda o leitor do plano de contas da CVM sobre os arquivos REAIS.
//
// O teste do núcleo prova a lógica sobre linhas sintéticas. Isto prova que ela
// sobrevive aos 286 CNPJs do universo — que é onde a conferência de campos
// achou os quatro layouts e a armadilha do `3.11`.
//
// Duas verificações que só o dado real permite:
//
// 1. **Identidade de balanço.** `Ativo Total = Passivo Total` tem de valer em
//    todo documento. É a conferência analítica que a §2.17 dizia não existir.
// 2. **Identidade da DRE.** `antes dos tributos + tributos = lucro`, dentro do
//    arredondamento da fonte.
//
// Uso:
//   npm run tool -- cvm-check <diretorio-com-os-csv-extraidos>
import { CvmAccountLine, CvmChart, type CvmLayout, str } from '../src/core';
import { readQuotedCsv } from './cvm/quoted-csv';
import { jsonPretty, outln, readJson, writeText } from './lib/files';

/** Uma linha crua do CSV, já como [CvmAccountLine]. */
interface Row {
  denom: string;
  account: CvmAccountLine;
}

/** Fator da coluna `ESCALA_MOEDA`. */
const scale = (e: string | undefined): number => ((e ?? '').toUpperCase() === 'MIL' ? 1000 : 1);

function byCnpj(path: string, desiredOrder: string | null = null): Map<string, Row[]> {
  const out = new Map<string, Row[]>();
  for (const r of readQuotedCsv(path)) {
    const order = r['ORDEM_EXERC'] ?? '';
    if (desiredOrder !== null && !order.startsWith(desiredOrder)) continue;
    const account = CvmAccountLine.fromText({
      code: r['CD_CONTA'] ?? '',
      label: r['DS_CONTA'] ?? '',
      value: r['VL_CONTA'] ?? '',
      scale: scale(r['ESCALA_MOEDA']),
    });
    if (account === null) continue;
    const key = r['CNPJ_CIA'] ?? '';
    let list = out.get(key);
    if (list === undefined) out.set(key, (list = []));
    list.push({ denom: r['DENOM_CIA'] ?? '', account });
  }
  return out;
}

const toChart = (l: readonly Row[]): CvmAccountLine[] => l.map((x) => x.account);

const pc = (n: number, d: number): string => (d === 0 ? '—' : `${((100 * n) / d).toFixed(1)}%`);

export function main(args: string[]): void {
  const dir = args.length === 0 ? '.' : args[0]!;
  const f = (n: string) => `${dir}/${n}`;

  // "ÚLTIMO" é o exercício de referência do documento; "PENÚLTIMO" é o
  // comparativo do ano anterior, que já virá no arquivo daquele ano.
  const last = 'Ú';

  const dre = byCnpj(f('dfp_cia_aberta_DRE_con_2024.csv'), last);
  const dreInd = byCnpj(f('dfp_cia_aberta_DRE_ind_2024.csv'), last);
  const bpa = byCnpj(f('dfp_cia_aberta_BPA_con_2024.csv'), last);
  const bpaInd = byCnpj(f('dfp_cia_aberta_BPA_ind_2024.csv'), last);
  const bpp = byCnpj(f('dfp_cia_aberta_BPP_con_2024.csv'), last);
  const bppInd = byCnpj(f('dfp_cia_aberta_BPP_ind_2024.csv'), last);

  const bridge = readJson<{ ponte: Record<string, string> }>('docs/validacao/ponte_cvm.json');
  const cnpjs = new Set(Object.values(bridge.ponte));

  outln('== Leitor do plano de contas sobre o DFP 2024 real ==');
  outln(`   ${cnpjs.size} CNPJs do universo\n`);

  const byLayout = new Map<CvmLayout, number>();
  let withProfit = 0;
  let withEbit = 0;
  let withEquity = 0;
  let withAsset = 0;
  let fellBackToInd = 0;
  let balanceOk = 0;
  let balanceTested = 0;
  let dreOk = 0;
  let dreTested = 0;
  const failures: string[] = [];
  const output: Record<string, unknown>[] = [];

  for (const cnpj of cnpjs) {
    // Consolidado, com recuo para individual — a conferência mostrou que
    // Sanepar, Comgás, Coelba e afins só arquivam individual.
    let dreRows = dre.get(cnpj);
    let bpaRows = bpa.get(cnpj);
    let bppRows = bpp.get(cnpj);
    let origin = 'consolidado';
    if (dreRows === undefined || dreRows.length === 0) {
      dreRows = dreInd.get(cnpj);
      bpaRows = bpaInd.get(cnpj);
      bppRows = bppInd.get(cnpj);
      origin = 'individual';
      if (dreRows !== undefined && dreRows.length > 0) fellBackToInd++;
    }
    if (dreRows === undefined || dreRows.length === 0) continue;

    const chartDre = CvmChart.of(toChart(dreRows));
    const chartBal = CvmChart.of([...toChart(bpaRows ?? []), ...toChart(bppRows ?? [])]);

    byLayout.set(chartDre.layout, (byLayout.get(chartDre.layout) ?? 0) + 1);
    const profit = chartDre.netIncome;
    const ebit = chartDre.ebit;
    const pl = chartBal.equity;
    const at = chartBal.totalAssets;
    const totalLiab = chartBal.totalLiabilities;
    if (profit !== null) withProfit++;
    if (ebit !== null) withEbit++;
    if (pl !== null) withEquity++;
    if (at !== null) withAsset++;

    // (1) Identidade de balanço.
    // `|at| > 1` e não `at !== 0`: um ativo total de 1e-14 — resíduo de
    // leitura, não companhia — faria a razão relativa estourar e inventar um
    // balanço que não fecha.
    if (at !== null && totalLiab !== null && Math.abs(at) > 1) {
      balanceTested++;
      if (Math.abs(at - totalLiab) / Math.abs(at) < 1e-6) {
        balanceOk++;
      } else {
        failures.push(`${dreRows[0]!.denom}: ativo ${str(at)} != passivo ${str(totalLiab)}`);
      }
    }

    // (2) Identidade da DRE.
    const before = chartDre.incomeBeforeTaxes;
    const taxes = chartDre.taxes;
    if (before !== null && taxes !== null && profit !== null && Math.abs(profit) > 1) {
      dreTested++;
      if (Math.abs(before + taxes - profit) / Math.abs(profit) < 0.02) dreOk++;
    }

    output.push({
      cnpj,
      nome: dreRows[0]!.denom,
      origem: origin,
      layout: chartDre.layout.key,
      receita: chartDre.revenue,
      ebit,
      lucro: profit,
      lpa: chartDre.earningsPerShare,
      ativoTotal: at,
      patrimonioLiquido: pl,
      naoControladores: chartBal.nonControllingInterests,
    });
  }

  const n = output.length;
  outln(`  companhias lidas: ${n}   (recuo para individual: ${fellBackToInd})`);
  outln('  layouts detectados:');
  for (const [layout, count] of byLayout) outln(`    ${String(count).padStart(4)}  ${layout.key}`);
  outln('');
  outln(`  lucro líquido resolvido : ${withProfit} / ${n}  ${pc(withProfit, n)}`);
  outln(`  patrimônio líquido      : ${withEquity} / ${n}  ${pc(withEquity, n)}`);
  outln(`  ativo total             : ${withAsset} / ${n}  ${pc(withAsset, n)}`);
  outln(`  EBIT (só não financeira): ${withEbit} / ${n}  ${pc(withEbit, n)}`);
  outln('');
  outln(`  IDENTIDADE ativo = passivo : ${balanceOk} / ${balanceTested}  ${pc(balanceOk, balanceTested)}`);
  outln(`  IDENTIDADE antes+trib=lucro: ${dreOk} / ${dreTested}  ${pc(dreOk, dreTested)}`);
  if (failures.length > 0) {
    outln('\n  balanços que não fecham:');
    for (const x of failures.slice(0, 10)) outln(`    ${x}`);
  }

  writeText('docs/validacao/cvm_leitura.json', jsonPretty(output));
  outln('\n  gravado docs/validacao/cvm_leitura.json');
}
