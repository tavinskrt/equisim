// Sensibilidade da distribuição de potencial ao prêmio de risco de mercado.
//
// O prêmio é o único insumo do CAPM que o motor **parametriza** em vez de
// medir, e as âncoras medem um valor bem diferente na mesma janela. Esta sonda
// mede quanto do nível da distribuição depende dessa escolha.
import {
  CapmInputs,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  ValuationCascade,
  ValuationInputs,
} from '../src/core';
import { errln, jsonPretty, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  const today = DateTime.local(2026, 9, 4);
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    const measured = anchors.marketCagr - anchors.riskFreeCagr;
    const premiums = new Map<string, number>([
      ['usado_5.50', CapmInputs.defaultMarketPremium],
      ['medido', measured],
      ['meio_4.00', 0.04],
      ['damodaran_7.00', 0.07],
    ]);
    errln(`prêmio medido na janela: ${(measured * 100).toFixed(2)} p.p.`);

    const universe = (await ctx.fundamentals.universe()).unwrap();
    const out: Record<string, unknown>[] = [];
    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}\r`);
      const prep = await PrepareValuationInputs.call({
        ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      });
      if (prep.isErr) continue;
      const base = prep.unwrap();
      const row: Record<string, unknown> = { ticker: ticker.value, beta: base.capm.beta };
      for (const [key, premium] of premiums) {
        const v = new ValuationInputs({
          ticker: base.ticker,
          asOf: base.asOf,
          fundamentals: base.fundamentals,
          marketPrice: base.marketPrice,
          capm: new CapmInputs({
            riskFreeRate: base.capm.riskFreeRate,
            beta: base.capm.beta,
            marketPremium: premium,
            betaSource: base.capm.betaSource,
          }),
          projectionYears: 10,
          perpetualGrowthCap: base.perpetualGrowthCap,
          sectorKey: base.sectorKey,
          industry: base.industry,
          inflation: base.inflation,
          declaredTerminalRiskFreeRate: base.declaredTerminalRiskFreeRate,
          prices: base.prices,
          isDistressed: base.isDistressed,
        });
        const r = ValuationCascade.evaluate(v);
        row[key] = r.isOk ? r.unwrap().upside : null;
      }
      out.push(row);
    }
    writeText('docs/validacao/sensibilidade_premio.json', jsonPretty(out));
    errln('\nescrito docs/validacao/sensibilidade_premio.json');
  } finally {
    await ctx.dispose();
  }
}
