// Leitura da base ingerida (`data/cvm_exercicios.json`) para documentos do
// núcleo.
//
// Compartilhado por `cvm-link.ts` e `cvm-package.ts`: a conversão da linha da
// ingestão para `CvmPeriodDocument` já teve dois defeitos — a contagem absoluta
// de ações (decisão 70) e o "anual é dezembro" (decisão 72) —, e duas cópias
// dela voltariam a divergir.
import { existsSync, readFileSync } from 'node:fs';

import { CvmDocumentKind, CvmPeriodDocument, DateTime, FundamentalsSnapshot, type JsonObject, Ticker } from '../../src/core';

const toDate = (s: unknown): DateTime | null =>
  typeof s === 'string' && s.length >= 10 ? DateTime.tryParse(`${s.slice(0, 10)}T00:00:00Z`) : null;

const n = (e: JsonObject, k: string): number | null => (typeof e[k] === 'number' ? (e[k] as number) : null);

function snap(t: Ticker, end: DateTime, e: JsonObject, extra: { received?: DateTime | null; treasuryFraction?: number | null } = {}): FundamentalsSnapshot {
  const ebit = n(e, 'ebit');
  const dAndA = n(e, 'depreciacaoEAmortizacao');
  return new FundamentalsSnapshot({
    ticker: t,
    fiscalPeriodEnd: end,
    receiptDate: extra.received ?? null,
    totalRevenue: n(e, 'receita'),
    ebit,
    // EBITDA da própria CVM, para que o D&A dos doze meses se some junto.
    ebitda: ebit !== null && dAndA !== null ? ebit + dAndA : null,
    netIncome: n(e, 'lucroLiquido'),
    incomeBeforeTax: n(e, 'resultadoAntesDosTributos'),
    incomeTaxExpense: n(e, 'tributos'),
    operatingCashFlow: n(e, 'caixaOperacional'),
    investmentCashFlow: n(e, 'caixaDeInvestimento'),
    cash: n(e, 'caixa'),
    shortTermInvestments: n(e, 'aplicacoesFinanceiras'),
    shortTermDebt: n(e, 'dividaDeCurtoPrazo'),
    longTermDebt: n(e, 'dividaDeLongoPrazo'),
    totalStockholderEquity: n(e, 'patrimonioLiquido'),
    propertyPlantEquipment: n(e, 'imobilizado'),
    intangibleAssets: n(e, 'intangivel'),
    totalCurrentAssets: n(e, 'ativoCirculante'),
    currentLiabilities: n(e, 'passivoCirculante'),
    minorityInterest: n(e, 'naoControladores'),
    totalAssets: n(e, 'ativoTotal'),
    treasuryFraction: extra.treasuryFraction ?? null,
  });
}

/** As versões anteriores de cada documento, gravadas por `cvm-ingest.ts`. */
export const oldVersionsFile = 'data/cvm_versoes.json';

/**
 * Documentos por ticker, da base ingerida.
 *
 * - [tickersByCnpj]: tickers a mais para cada CNPJ. A ingestão só liga ticker
 *   à companhia do universo de hoje; as deslistadas (item C1b) chegam com a
 *   lista vazia, e o ticker delas vem da ponte do COTAHIST.
 * - [withOldVersions]: acrescenta as versões anteriores de cada documento, de
 *   `data/cvm_versoes.json` (item B8), cada uma com a data de recebimento dela.
 *   Quem lê a lista precisa escolher a vigente — `CvmSeries.build` o faz por
 *   `CvmSeries.inForceAt`. Sem o arquivo, avisa e segue com a última versão,
 *   que é o comportamento anterior ao B8.
 *
 * Encerra o processo com código 2 quando a base não existe, dizendo o que
 * rodar antes.
 */
export function loadDocuments(
  path: string,
  options: { onlyTickers?: Set<string> | null; tickersByCnpj?: Map<string, string[]> | null; withOldVersions?: boolean } = {},
): Map<string, CvmPeriodDocument[]> {
  if (!existsSync(path)) {
    process.stderr.write(`${path} não existe. Rode antes:\n`);
    process.stderr.write('  npm run tool -- cvm-ingest data/cvm\n');
    process.exit(2);
  }
  const rows = [...(JSON.parse(readFileSync(path, 'utf8')) as JsonObject[])];
  if (options.withOldVersions === true) {
    if (existsSync(oldVersionsFile)) {
      rows.push(...(JSON.parse(readFileSync(oldVersionsFile, 'utf8')) as JsonObject[]));
    } else {
      process.stderr.write(`AVISO: ${oldVersionsFile} não existe — as coortes leem a última versão de cada documento (item B8). Rode antes:\n`);
      process.stderr.write('  python tool/cvm_versoes_baixar.py\n');
      process.stderr.write('  npm run tool -- cvm-ingest data/cvm\n');
    }
  }
  const out = new Map<string, CvmPeriodDocument[]>();
  for (const e of rows) {
    const tickers = [...(e['tickers'] as string[]), ...(options.tickersByCnpj?.get(e['cnpj'] as string) ?? [])];
    if (tickers.length === 0) continue;
    const end = toDate(e['fimDoExercicio']);
    const ini = toDate(e['inicioDoPeriodo']);
    if (end === null || ini === null) continue;
    const kind = e['documento'] === 'DFP' ? CvmDocumentKind.dfp : CvmDocumentKind.itr;

    const paidIn = n(e, 'acoesIntegralizadas');
    const tes = n(e, 'acoesEmTesouraria');
    // Decisão 70: só a fração, porque a escala da contagem varia por declarante.
    const fraction = paidIn !== null && paidIn > 0 && tes !== null && tes >= 0 && tes < paidIn ? tes / paidIn : null;
    const previous = (e['anterior'] as JsonObject | null | undefined) ?? null;

    for (const t of tickers) {
      if (options.onlyTickers != null && !options.onlyTickers.has(t)) continue;
      const tk = Ticker.parse(t);
      let list = out.get(t);
      if (list === undefined) out.set(t, (list = []));
      list.push(
        new CvmPeriodDocument({
          kind,
          periodStart: ini,
          periodEnd: end,
          current: snap(tk, end, e, { received: toDate(e['recebidoEm']), treasuryFraction: fraction }),
          prior: previous === null ? null : snap(tk, DateTime.utc(end.year - 1, end.month, end.day), previous),
          priorStart: toDate(previous?.['inicioDoPeriodo']),
        }),
      );
    }
  }
  return out;
}
