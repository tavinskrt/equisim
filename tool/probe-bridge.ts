// D7 — o que a fonte publica entre o valor da firma e o do acionista.
//
// A ponte do motor é `E = EV − dívida líquida`. A contabilidade tem mais
// termos: participação de não controladores, investimento em coligada avaliado
// por equivalência patrimonial, arrendamento reconhecido como passivo pelo
// IFRS 16. Antes de decidir o que fazer com cada um, é preciso saber **quais
// existem na fonte** — e o cache guarda só os campos já tipados, de modo que
// esta sonda vai à API buscar o mapa cru.
//
// Uso:
//   npm run tool -- probe-bridge PETR4 VALE3 ITUB4
import { compareStr, str, Ticker } from '../src/core';
import { outln } from './lib/files';
import { ValidationContext } from './validation/context';

/** Palavras que denunciam um termo de ponte no nome do campo. */
const clues = [
  'minor',
  'noncontrol',
  'controlling',
  'participa',
  'equity',
  'affiliate',
  'associate',
  'investment',
  'lease',
  'arrend',
  'pension',
  'provision',
  'goodwill',
  'treasury',
];

/** Um valor cru como o Dart o interpolava: ausente é `null`. */
const show = (v: unknown): string =>
  v === undefined || v === null ? 'null' : typeof v === 'number' ? str(v) : typeof v === 'object' ? JSON.stringify(v) : String(v);

export async function main(args: string[]): Promise<void> {
  const targets = args.length === 0 ? ['PETR4', 'VALE3', 'ITUB4', 'MGLU3', 'RENT3', 'CSNA3'] : args;
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    for (const t of targets) {
      const r = await ctx.brapi.rawFundamentals(Ticker.parse(t));
      if (r.isErr) {
        outln(`${t}: ${r.failureOrNull?.message}`);
        continue;
      }
      const rows = r.unwrap();
      if (rows.length === 0) {
        outln(`${t}: sem exercícios`);
        continue;
      }
      outln('  --- série de equivalência ÷ EBIT ---');
      for (const l of rows) {
        const e = l['equityIncomeResult'];
        const b = l['ebit'];
        if (typeof e === 'number' && typeof b === 'number' && b > 0 && Math.abs(e) > 0) {
          outln(
            `    ${show(l['endDate'])}  equiv=${(e / 1e6).toFixed(1)} mi  ebit=${(b / 1e6).toFixed(1)} mi  ` +
              `${((e / b) * 100).toFixed(1)}%`,
          );
        }
      }
      const last = rows[rows.length - 1]!;
      outln(`\n=== ${t} — ${rows.length} exercícios, ${Object.keys(last).length} campos no último ===`);
      const keys = Object.keys(last).sort(compareStr);
      const suspicious = keys.filter((k) => clues.some((p) => k.toLowerCase().includes(p)));
      for (const k of suspicious) outln(`  ${k.padEnd(38)} ${show(last[k])}`);
      if (suspicious.length === 0) outln('  (nenhum campo de ponte)');

      const n = (k: string): number | null => {
        const v = last[k];
        return typeof v === 'number' ? v : null;
      };

      const marketValue = n('marketCap');
      const debt = (n('shortLongTermDebt') ?? n('loansAndFinancing') ?? 0) + (n('longTermDebt') ?? n('longTermLoansAndFinancing') ?? 0);
      const leases = (n('leaseFinancing') ?? 0) + (n('longTermLeaseFinancing') ?? 0);
      const minor = n('minorityInterest') ?? 0;
      const affiliates = n('longTermInvestments') ?? 0;
      const pct = (x: number): string => (marketValue === null || marketValue <= 0 ? '—' : `${((x / marketValue) * 100).toFixed(1)}%`);
      outln('  --- tamanho contra o valor de mercado ---');
      outln(`  valor de mercado      ${marketValue === null ? 'null' : marketValue.toFixed(0)}`);
      outln(`  dívida (empréstimos)  ${debt.toFixed(0)}  ${pct(debt)}`);
      outln(`  arrendamento          ${leases.toFixed(0)}  ${pct(leases)}`);
      outln(`  não controladores     ${minor.toFixed(0)}  ${pct(minor)}`);
      outln(`  coligadas             ${affiliates.toFixed(0)}  ${pct(affiliates)}`);
      outln('  --- o arrendamento já está na dívida? ---');
      for (const k of [
        'shortLongTermDebt',
        'loansAndFinancing',
        'longTermDebt',
        'longTermLoansAndFinancing',
        'debentures',
        'longTermDebentures',
        'leaseFinancing',
        'longTermLeaseFinancing',
        'loansAndFinancingInNationalCurrency',
        'loansAndFinancingInForeignCurrency',
        'longTermLoansAndFinancingInNationalCurrency',
        'longTermLoansAndFinancingInForeignCurrency',
        'totalLiab',
        'nonCurrentLiabilities',
        '--- ativo ---',
        'nonCurrentAssets',
        'longTermAssets',
        'longTermInvestments',
        'investments',
        'investmentProperties',
        'shareholdings',
        'propertyPlantEquipment',
        'intangibleAsset',
        '--- patrimonio ---',
        'shareholdersEquity',
        'minorityInterest',
        'controllerShareholdersEquity',
        'equityIncomeResult',
        'netIncome',
        'cleanNetIncome',
        'ebit',
        'cleanEbit',
        'cleanNopat',
        'operatingIncome',
        'incomeFromOperations',
      ]) {
        outln(`  ${k.padEnd(30)} ${show(last[k])}`);
      }
    }
  } finally {
    await ctx.dispose();
  }
}
