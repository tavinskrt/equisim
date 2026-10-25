// Ingestão da CVM: dos CSVs anuais para a série de documentos do motor.
//
// Junta as peças dos itens A1.1 a A1.8:
//
//   A1.1  a ponte ticker -> CNPJ, por `CvmBridge`
//   A1.2  o layout do plano de contas, por `CvmChart`
//   A1.3  consolidado com recuo para individual
//   A1.4  publicidade pela `DT_RECEB`, e a versão mais recente de cada
//   A1.5  fração de tesouraria
//   A1.6  todos os anos, inclusive companhias que já não existem
//   A1.8  o acumulado do ano anterior, para os últimos doze meses
//
// **Dois defeitos da primeira versão, corrigidos aqui** (decisão 72):
//
// 1. **A DRE do ITR traz duas linhas por conta** no 2º e no 3º trimestre: o
//    trimestre isolado (`DT_INI_EXERC` no início do trimestre) e o acumulado
//    do exercício (`DT_INI_EXERC` no início do exercício). A versão anterior
//    filtrava só por `ÚLTIMO`, e o leitor recebia as duas com o mesmo código —
//    a receita do 2T23 da WEG chegava como R$ 15,87 bi **e** R$ 8,17 bi. A
//    seleção agora fica com a de **menor `DT_INI_EXERC`**, que é o acumulado, e
//    que funciona também em exercício que não começa em janeiro.
// 2. **O tipo de documento entra na chave e na saída.** A série anual é a DFP,
//    não "o que termina em dezembro": cinco companhias do universo têm
//    exercício social fora do calendário, e para elas o ITR de dezembro é um
//    acumulado de nove meses.
//
// **A regra de versão é decisão, e está aqui** (item B8). A CVM republica
// documento reapresentado com `VERSAO` maior, e os CSVs anuais trazem só a
// última — o número correto conhecido hoje, que numa avaliação datada é
// conhecimento futuro. Por isso a ingestão grava **dois arquivos**:
//
//   data/cvm_exercicios.json  a última versão de cada documento, como sempre;
//                             é o que o pacote do aplicativo e as ferramentas
//                             de conferência leem
//   data/cvm_versoes.json     as versões anteriores que estavam vigentes em
//                             alguma coorte, baixadas do RAD por
//                             `tool/cvm_versoes_baixar.py`, cada uma com a data
//                             de recebimento **dela**
//
// O backtest lê os dois, e `CvmSeries.inForceAt` escolhe, em cada coorte, a
// versão que era pública naquela data.
//
// Uso:
//   python tool/cvm_baixar.py --de 2010 --ate 2026 --docs DFP,ITR,FCA
//   python tool/cvm_versoes_baixar.py            # as versões antigas
//   npm run tool -- cvm-ingest data/cvm
import { existsSync, readdirSync, statSync, unlinkSync } from 'node:fs';

import { compareNum, compareStr, CvmAccountLine, CvmChart, tryParseDouble, tryParseInt } from '../src/core';
import { dartString, errln, outln, readJson, readLatin1, splitLines, writeText } from './lib/files';

// ------------------------------------------------------------------ leitura

type CsvRow = Record<string, string>;

/**
 * Lê um CSV da CVM: `latin-1`, separador `;`, aspas respeitadas.
 *
 * É o leitor de linha a linha desta ingestão, e não o de `cvm/csv.ts`: linha
 * com número de campos diferente do cabeçalho é descartada, como sempre foi.
 */
function readCsv(path: string): CsvRow[] {
  const rows = splitLines(readLatin1(path));
  if (rows.length === 0) return [];
  const headerRow = fields(rows[0]!);
  const out: CsvRow[] = [];
  for (let i = 1; i < rows.length; i++) {
    if (rows[i]!.trim().length === 0) continue;
    const c = fields(rows[i]!);
    if (c.length !== headerRow.length) continue;
    const row: CsvRow = {};
    for (let j = 0; j < headerRow.length; j++) row[headerRow[j]!] = c[j]!;
    out.push(row);
  }
  return out;
}

function fields(l: string): string[] {
  const out: string[] = [];
  let current = '';
  let quoted = false;
  for (const ch of l) {
    if (ch === '"') {
      quoted = !quoted;
    } else if (ch === ';' && !quoted) {
      out.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  out.push(current);
  return out;
}

const scaleOf = (e: string | undefined): number => ((e ?? '').toUpperCase() === 'MIL' ? 1000 : 1);

const dayOf = (s: string | undefined): string => (s === undefined || s.length < 10 ? '' : s.substring(0, 10));

/** Chave de um documento: companhia, data de referência e tipo. */
interface DocKey {
  cnpj: string;
  refer: string;
  doc: string;
}

/** Chave de uma versão de documento. */
interface VersionKey extends DocKey {
  version: number;
}

const docId = (k: DocKey): string => `${k.cnpj}|${k.refer}|${k.doc}`;
const versionId = (k: VersionKey): string => `${docId(k)}|${k.version}`;

/** Metadados de um documento entregue à CVM. */
class Meta {
  constructor(
    readonly denom: string,
    readonly version: number,
    readonly received: string | null,
  ) {}
}

/** Linhas de uma demonstração, com o início do período das contas de fluxo. */
class Statement {
  readonly byAccount = new Map<string, { ini: string; row: CvmAccountLine }>();

  /**
   * Quantas contas chegaram com mais de uma linha — o trimestre e o
   * acumulado, na DRE do ITR.
   */
  duplicates = 0;

  /**
   * Fica com a linha de **menor** início de período para cada conta — o
   * acumulado do exercício. Balanço não tem início, e passa direto.
   */
  append(ini: string, row: CvmAccountLine): void {
    const current = this.byAccount.get(row.code);
    if (current !== undefined) this.duplicates++;
    if (current === undefined || (ini.length > 0 && compareStr(ini, current.ini) < 0)) {
      this.byAccount.set(row.code, { ini, row });
    }
  }

  get rows(): CvmAccountLine[] {
    return [...this.byAccount.values()].map((v) => v.row);
  }

  /** Início do período acumulado, pela receita ou pelo lucro. */
  get start(): string | null {
    for (const c of ['3.01', '3.11', '3.09', '3.13', '6.01']) {
      const v = this.byAccount.get(c);
      if (v !== undefined && v.ini.length > 0) return v.ini;
    }
    return null;
  }
}

/** Valores de um mapa por chave composta, guardando a chave original. */
class KeyedMap<K, V> {
  private readonly entries = new Map<string, { key: K; value: V }>();

  constructor(private readonly id: (k: K) => string) {}

  get(k: K): V | undefined {
    return this.entries.get(this.id(k))?.value;
  }

  set(k: K, v: V): void {
    const id = this.id(k);
    const current = this.entries.get(id);
    if (current === undefined) this.entries.set(id, { key: k, value: v });
    else current.value = v;
  }

  has(k: K): boolean {
    return this.entries.has(this.id(k));
  }

  get size(): number {
    return this.entries.size;
  }

  keys(): K[] {
    return [...this.entries.values()].map((e) => e.key);
  }

  values(): V[] {
    return [...this.entries.values()].map((e) => e.value);
  }
}

type FiscalYear = Record<string, unknown>;

const filesByName = (dir: string): Map<string, string> => {
  const out = new Map<string, string>();
  if (!existsSync(dir)) return out;
  for (const name of [...readdirSync(dir)].sort(compareStr)) {
    const path = `${dir}/${name}`;
    if (statSync(path).isFile()) out.set(name, path);
  }
  return out;
};

export function main(args: string[]): void {
  const dir = args.length === 0 ? 'data/cvm' : args[0]!;
  if (!existsSync(dir)) {
    errln(`${dir} não existe. Rode antes:`);
    errln('  python tool/cvm_baixar.py --de 2010 --ate 2026');
    process.exitCode = 2;
    return;
  }
  const byName = filesByName(dir);

  const years = new Set<number>();
  for (const n of byName.keys()) {
    const m = /_(\d{4})\.csv$/.exec(n);
    if (m !== null) years.add(Number.parseInt(m[1]!, 10));
  }
  const sortedYears = [...years].sort(compareNum);
  if (sortedYears.length === 0) throw new Error(`nenhum CSV anual em ${dir}`);
  outln('== Ingestão da CVM ==');
  outln(`  anos encontrados: ${sortedYears[0]}–${sortedYears[sortedYears.length - 1]}\n`);

  // --- Metadados: recebimento de cada versão, e a vigente -----------------
  const meta = new KeyedMap<DocKey, Meta>(docId);
  const byVersion = new KeyedMap<VersionKey, Meta>(versionId);
  for (const year of sortedYears) {
    for (const doc of ['dfp', 'itr']) {
      const f = byName.get(`${doc}_cia_aberta_${year}.csv`);
      if (f === undefined) continue;
      for (const r of readCsv(f)) {
        const k: DocKey = { cnpj: r['CNPJ_CIA'] ?? '', refer: dayOf(r['DT_REFER']), doc: doc.toUpperCase() };
        const v = tryParseInt(r['VERSAO'] ?? '') ?? 1;
        const m = new Meta(r['DENOM_CIA'] ?? '', v, dayOf(r['DT_RECEB']));
        // A mesma versão aparece, às vezes, no índice de dois anos com datas
        // diferentes; vale a primeira lida, que é a regra de antes do B8.
        const vk: VersionKey = { ...k, version: v };
        if (!byVersion.has(vk)) byVersion.set(vk, m);
        const current = meta.get(k);
        if (current === undefined || v > current.version) meta.set(k, m);
      }
    }
  }
  const byKind = new Map<string, number>();
  for (const k of meta.keys()) byKind.set(k.doc, (byKind.get(k.doc) ?? 0) + 1);
  outln(`  documentos: ${meta.size} ${dartString(byKind)}`);
  const restated = meta.values().filter((m) => m.version > 1).length;
  outln(`  reapresentados (VERSAO > 1): ${restated} (${((100 * restated) / meta.size).toFixed(1)}%)`);

  // As versões antigas, no layout dos anuais, quando foram baixadas.
  const versionsByName = filesByName(`${dir}/versoes`);

  /** Arquivos de um demonstrativo: os anuais, ou o das versões antigas. */
  function* files(suffix: string, oldVersions: boolean): Generator<[string, string]> {
    for (const doc of ['dfp', 'itr']) {
      if (oldVersions) {
        const f = versionsByName.get(`${doc}_cia_aberta_${suffix}_versoes.csv`);
        if (f !== undefined) yield [doc, f];
      } else {
        for (const year of sortedYears) {
          const f = byName.get(`${doc}_cia_aberta_${suffix}_${year}.csv`);
          if (f !== undefined) yield [doc, f];
        }
      }
    }
  }

  const key = (r: CsvRow, doc: string): VersionKey => ({
    cnpj: r['CNPJ_CIA'] ?? '',
    refer: dayOf(r['DT_REFER']),
    doc: doc.toUpperCase(),
    version: tryParseInt(r['VERSAO'] ?? '') ?? 1,
  });

  // --- Composição de capital -----------------------------------------------
  const loadCapital = (oldVersions: boolean): KeyedMap<VersionKey, { paidInShares: number; treasury: number }> => {
    const out = new KeyedMap<VersionKey, { paidInShares: number; treasury: number }>(versionId);
    for (const [doc, f] of files('composicao_capital', oldVersions)) {
      for (const r of readCsv(f)) {
        const tot = tryParseDouble(r['QT_ACAO_TOTAL_CAP_INTEGR'] ?? '');
        const treasuryShares = tryParseDouble(r['QT_ACAO_TOTAL_TESOURO'] ?? '') ?? 0;
        if (tot === null || tot <= 0) continue;
        out.set(key(r, doc), { paidInShares: tot, treasury: treasuryShares });
      }
    }
    return out;
  };

  // --- Demonstrações --------------------------------------------------------
  /**
   * Lê uma demonstração de todos os anos. [order] é `Ú` (exercício do
   * documento) ou `P` (o comparativo que o acompanha).
   */
  const load = (suffix: string, order: string, oldVersions: boolean): KeyedMap<VersionKey, Statement> => {
    const out = new KeyedMap<VersionKey, Statement>(versionId);
    for (const [doc, f] of files(suffix, oldVersions)) {
      for (const r of readCsv(f)) {
        if (!(r['ORDEM_EXERC'] ?? '').startsWith(order)) continue;
        const row = CvmAccountLine.fromText({
          code: r['CD_CONTA'] ?? '',
          label: r['DS_CONTA'] ?? '',
          value: r['VL_CONTA'] ?? '',
          scale: scaleOf(r['ESCALA_MOEDA']),
        });
        if (row === null) continue;
        const k = key(r, doc);
        let statement = out.get(k);
        if (statement === undefined) out.set(k, (statement = new Statement()));
        statement.append(dayOf(r['DT_INI_EXERC']), row);
      }
    }
    return out;
  };

  // --- Ponte ---------------------------------------------------------------
  const bridgePath = 'docs/validacao/ponte_cvm.json';
  if (!existsSync(bridgePath)) {
    errln(`Rode antes: npm run tool -- cvm-bridge ${dir}`);
    process.exitCode = 2;
    return;
  }
  const bridge = (readJson<Record<string, unknown>>(bridgePath)['ponte'] ?? {}) as Record<string, string>;
  const byCnpj = new Map<string, string[]>();
  for (const [ticker, cnpj] of Object.entries(bridge)) {
    let list = byCnpj.get(cnpj);
    if (list === undefined) byCnpj.set(cnpj, (list = []));
    list.push(ticker);
  }

  const flows = (dreChart: CvmChart, dfcC: CvmChart): Record<string, number | null> => ({
    receita: dreChart.revenue,
    ebit: dreChart.ebit,
    resultadoAntesDosTributos: dreChart.incomeBeforeTaxes,
    tributos: dreChart.taxes,
    lucroLiquido: dreChart.netIncome,
    caixaOperacional: dfcC.operatingCashFlow,
    caixaDeInvestimento: dfcC.investingCashFlow,
    capex: dfcC.capex,
    depreciacaoEAmortizacao: dfcC.depreciationAndAmortization,
  });

  // --- Montagem ------------------------------------------------------------
  let withFallback = 0;
  let withoutDre = 0;
  let balanceOk = 0;
  let balanceN = 0;
  let resolvedDuplicates = 0;
  let withoutReceipt = 0;
  const layouts = new Map<string, number>();

  /**
   * Monta os exercícios de um conjunto de CSVs — os anuais ou os das versões
   * antigas. A data de recebimento é a **da versão** que as contas trazem.
   */
  const build = (oldVersions: boolean): FiscalYear[] => {
    const pair = (suffix: string, order: string) => ({
      con: load(`${suffix}_con`, order, oldVersions),
      ind: load(`${suffix}_ind`, order, oldVersions),
    });
    const dre = pair('DRE', 'Ú');
    const previousDre = pair('DRE', 'P');
    const dfc = pair('DFC_MI', 'Ú');
    const dfcPrev = pair('DFC_MI', 'P');
    const bpa = pair('BPA', 'Ú');
    const bpp = pair('BPP', 'Ú');
    const capital = loadCapital(oldVersions);

    const fiscalYears: FiscalYear[] = [];
    const keys = new KeyedMap<VersionKey, VersionKey>(versionId);
    for (const k of [...dre.con.keys(), ...dre.ind.keys()]) if (!keys.has(k)) keys.set(k, k);
    if (!oldVersions) {
      const withDre = new Set(keys.keys().map((k) => docId(k)));
      withoutDre = meta.keys().filter((k) => !withDre.has(docId(k))).length;
    }
    for (const k of keys.keys()) {
      // A versão das contas dá a data de recebimento. Nos anuais, a versão que
      // o CSV traz é a última, e o índice a confirma; sem ela no índice, fica a
      // vigente, como antes.
      const m = byVersion.get(k) ?? (oldVersions ? undefined : meta.get(k));
      if (m === undefined) {
        withoutReceipt++;
        continue;
      }
      let origin: 'con' | 'ind' = 'con';
      if (dre.con.get(k) === undefined) {
        origin = 'ind';
        if (dre.ind.get(k) !== undefined) withFallback++;
      }
      const dreStatement = dre[origin].get(k);
      if (dreStatement === undefined) continue;

      const chartDre = CvmChart.of(dreStatement.rows);
      const chartDfc = CvmChart.of(dfc[origin].get(k)?.rows ?? []);
      const chartBal = CvmChart.of([...(bpa[origin].get(k)?.rows ?? []), ...(bpp[origin].get(k)?.rows ?? [])]);
      layouts.set(chartDre.layout.key, (layouts.get(chartDre.layout.key) ?? 0) + 1);

      const at = chartBal.totalAssets;
      const pt = chartBal.totalLiabilities;
      if (at !== null && pt !== null && Math.abs(at) > 1) {
        balanceN++;
        if (Math.abs(at - pt) / Math.abs(at) < 1e-6) balanceOk++;
      }

      // Acumulado do mesmo período no exercício anterior — só o ITR precisa,
      // para os últimos doze meses. A DFP é o ano cheio por si.
      let previous: Record<string, unknown> | null = null;
      if (k.doc === 'ITR') {
        const dPrev = previousDre[origin].get(k);
        if (dPrev !== undefined) {
          const fPrev = flows(CvmChart.of(dPrev.rows), CvmChart.of(dfcPrev[origin].get(k)?.rows ?? []));
          previous = { inicioDoPeriodo: dPrev.start, ...fPrev };
        }
        if (dreStatement.duplicates > 0) resolvedDuplicates++;
      }

      const cap = capital.get(k);
      fiscalYears.push({
        cnpj: k.cnpj,
        nome: m.denom,
        tickers: byCnpj.get(k.cnpj) ?? [],
        documento: k.doc,
        inicioDoPeriodo: dreStatement.start,
        fimDoExercicio: k.refer,
        recebidoEm: m.received,
        versao: m.version,
        origem: origin === 'con' ? 'consolidado' : 'individual',
        layout: chartDre.layout.key,
        ...flows(chartDre, chartDfc),
        lucroPorAcao: chartDre.earningsPerShare,
        ativoTotal: at,
        ativoCirculante: chartBal.currentAssets,
        passivoCirculante: chartBal.currentLiabilities,
        patrimonioLiquido: chartBal.equity,
        naoControladores: chartBal.nonControllingInterests,
        caixa: chartBal.cash,
        aplicacoesFinanceiras: chartBal.financialInvestments,
        imobilizado: chartBal.propertyPlantEquipment,
        intangivel: chartBal.intangibleAssets,
        dividaDeCurtoPrazo: chartBal.shortTermDebt,
        dividaDeLongoPrazo: chartBal.longTermDebt,
        acoesIntegralizadas: cap?.paidInShares ?? null,
        acoesEmTesouraria: cap?.treasury ?? null,
        anterior: previous,
      });
    }

    fiscalYears.sort((a, b) => {
      const c = compareStr(a['cnpj'] as string, b['cnpj'] as string);
      if (c !== 0) return c;
      const f = compareStr(a['fimDoExercicio'] as string, b['fimDoExercicio'] as string);
      return f !== 0 ? f : compareNum(a['versao'] as number, b['versao'] as number);
    });
    return fiscalYears;
  };

  // Nos anuais, **uma entrada por documento, a de maior versão**: um
  // documento raro vem com duas versões em arquivos de anos diferentes (a DFP
  // de 2021 da INTER & CO), e a versão menor não é a vigente de hoje.
  const fiscalYears = ((): FiscalYear[] => {
    const byDoc = new Map<string, FiscalYear>();
    for (const e of build(false)) {
      const k = `${dartString(e['cnpj'])}|${dartString(e['fimDoExercicio'])}|${dartString(e['documento'])}`;
      const current = byDoc.get(k);
      if (current === undefined || (e['versao'] as number) > (current['versao'] as number)) byDoc.set(k, e);
    }
    return [...byDoc.values()];
  })();
  // O recuo, as duplicadas e a identidade descrevem a base vigente; as
  // versões antigas são contadas à parte.
  const [fallback0, dup0, balanceOk0, balanceN0] = [withFallback, resolvedDuplicates, balanceOk, balanceN];
  const oldVersions = versionsByName.size === 0 ? [] : build(true);
  const oldBalanceOk = balanceOk - balanceOk0;
  const oldBalanceN = balanceN - balanceN0;
  withFallback = fallback0;
  resolvedDuplicates = dup0;
  balanceOk = balanceOk0;
  balanceN = balanceN0;

  const withTicker = fiscalYears.filter((e) => (e['tickers'] as string[]).length > 0).length;
  outln('');
  outln(`  documentos montados : ${fiscalYears.length}`);
  outln(
    `    DFP: ${fiscalYears.filter((e) => e['documento'] === 'DFP').length}` +
      `   ITR: ${fiscalYears.filter((e) => e['documento'] === 'ITR').length}`,
  );
  outln(`  companhias distintas: ${new Set(fiscalYears.map((e) => e['cnpj'])).size}`);
  outln(`  com ticker no universo de hoje: ${withTicker}`);
  outln(`  fora do universo de hoje: ${fiscalYears.length - withTicker}`);
  outln(`  recuo para individual: ${withFallback}`);
  outln(`  sem DRE: ${withoutDre}`);
  outln(`  ITR em que a DRE trazia trimestre E acumulado: ${resolvedDuplicates}`);
  outln(`  layouts: ${dartString(layouts)}`);
  outln(`  IDENTIDADE ativo = passivo: ${balanceOk} / ${balanceN}`);

  const output = 'data/cvm_exercicios.json';
  writeText(output, JSON.stringify(fiscalYears));
  outln(`\n  gravado ${output} (${(statSync(output).size / 1e6).toFixed(1)} MB)`);

  // --- Versões antigas (item B8) --------------------------------------------
  const versionsOutput = 'data/cvm_versoes.json';
  if (oldVersions.length === 0) {
    if (existsSync(versionsOutput)) unlinkSync(versionsOutput);
    outln(`  sem versões antigas em ${dir}/versoes — rode tool/cvm_versoes_baixar.py para o point-in-time por versão`);
  } else {
    writeText(versionsOutput, JSON.stringify(oldVersions));
    outln(`  versões antigas montadas: ${oldVersions.length}   IDENTIDADE ativo = passivo: ${oldBalanceOk} / ${oldBalanceN}`);
    outln(`  gravado ${versionsOutput} (${(statSync(versionsOutput).size / 1e6).toFixed(1)} MB)`);
  }
  if (withoutReceipt > 0) outln(`  versões sem data de recebimento no índice, descartadas: ${withoutReceipt}`);
}
