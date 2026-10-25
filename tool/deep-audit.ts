// Diagnóstico profundo do motor de avaliação — instrumentação por ativo.
//
// Não altera o motor: lê os mesmos insumos que a cascata lê e expõe as
// grandezas intermediárias que o resultado não carrega, para que hipóteses de
// defeito sejam medidas em vez de supostas.
//
// Uso:
//   npm run tool -- deep-audit              # o universo inteiro
//   npm run tool -- deep-audit PETR4 VALE3  # só os ativos citados
import {
  CapitalSeries,
  compareNum,
  CostOfCapital,
  CyclicalSectors,
  DateTime,
  EligibilityGate,
  GrowthGuards,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  str,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  ValuationParameters,
} from '../src/core';
import { errln, jsonPretty, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

interface CompleteReturn {
  ano: number;
  retorno: number | null;
  descartado: boolean;
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function medianOf(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/**
 * A série de retornos com os exercícios de prejuízo.
 *
 * A série `returns` do núcleo descarta ano de lucro não positivo. Aqui a
 * mesma janela é reconstruída incluindo esses anos, para medir o viés.
 */
function completeReturns(s: CapitalSeries): CompleteReturn[] {
  const out: CompleteReturn[] = [];
  for (let i = 1; i < s.points.length; i++) {
    const a = s.points[i - 1]!;
    const b = s.points[i]!;
    if (b.year - a.year !== 1 || a.base <= 0) continue;
    const l = b.profit;
    out.push({ ano: b.year, retorno: l === null ? null : l / a.base, descartado: l === null || l <= 0 });
  }
  return out;
}

export function diagnose(inputs: ValuationInputs): Record<string, unknown> {
  const view = new PointInTimeView(inputs.asOf);
  const pub = view.published(inputs.fundamentals);
  if (pub.length === 0) return { erro: 'sem exercicio publicado' };
  const latest = pub[pub.length - 1]!;

  const firmSeries = CapitalSeries.build(pub, ValuationLane.firm);
  const shareholderSeries = CapitalSeries.build(pub, ValuationLane.shareholder);

  // --- Contagem de ações: todas as fontes lado a lado ---
  const nCurrent = latest.sharesOutstanding;
  const nFiscalYear = latest.sharesOutstandingAsOf;
  const profit = latest.netIncome;
  const eps = latest.earningsPerShare;
  const nByEps = profit !== null && eps !== null && Math.abs(eps) > 1e-9 ? profit / eps : null;
  const nByMarket = latest.marketCap !== null && inputs.marketPrice > 0 ? latest.marketCap / inputs.marketPrice : null;

  // --- Retornos: com e sem os exercícios de prejuízo ---
  const allFirmReturns = completeReturns(firmSeries);
  const usedFirmReturns = firmSeries.returns;

  // Ciclo incluindo os anos descartados (retorno negativo entra como é).
  const w = ValuationParameters.cycleWindow;
  const withLoss: number[] = [];
  const inWindow = allFirmReturns.filter((e) => e.retorno !== null);
  if (inWindow.length >= 2) {
    const start = inWindow.length - 1 - w;
    for (const e of inWindow.slice(start < 0 ? 0 : start, inWindow.length - 1)) withLoss.push(e.retorno!);
  }

  const lastReturnYear = usedFirmReturns.length === 0 ? null : usedFirmReturns[usedFirmReturns.length - 1]!.year;
  const lastFiscalYear = latest.fiscalPeriodEnd.year;

  const phi = GrowthGuards.externalCapitalRatio(firmSeries);
  const tend10 = GrowthGuards.trend(firmSeries, { driftWindow: 10 });
  const tend5 = GrowthGuards.trend(firmSeries, { driftWindow: 5 });
  const disp = GrowthGuards.dispersion(firmSeries);
  const decline = GrowthGuards.recentOperationalDecline(pub);

  const kd = latest.costOfDebt;
  const tax = latest.effectiveTaxRate;
  const capmT = inputs.capm.withRiskFree(inputs.terminalRiskFreeRate);
  const equityMkt = latest.marketCap;
  const coc =
    latest.totalDebt > 0 && equityMkt !== null && kd !== null
      ? new CostOfCapital({
          capm: inputs.capm,
          costOfDebt: kd,
          taxRate: ValuationParameters.statutoryTaxRate,
          equityValue: equityMkt,
          // A líquida, como o motor (decisão 104).
          debtValue: latest.netDebt,
          interestCoverage: latest.interestCoverage,
          netDebtToEbitda: latest.netDebtToEbitda,
        })
      : null;

  const adtv = inputs.prices === null ? null : EligibilityGate.medianTradedValue(inputs.prices);
  const divisor = ValuationCascade.quotedShares({
    latest,
    marketPrice: inputs.marketPrice,
    sharesPerQuote: ValuationCascade.quotedUnitRatio({
      sharesOutstanding: latest.sharesOutstanding,
      marketCap: latest.marketCap,
      marketPrice: inputs.marketPrice,
    }),
  });

  return {
    ticker: inputs.ticker.value,
    preco: inputs.marketPrice,
    setor: inputs.sectorKey,
    industria: inputs.industry,
    exerciciosPublicados: pub.length,
    anoUltimoExercicio: lastFiscalYear,
    // Ações
    nCorrente: nCurrent,
    nExercicio: nFiscalYear,
    nPorLpa: nByEps,
    nPorMercado: nByMarket,
    nConciliado: latest.reconciledShares,
    nPonte: divisor?.count ?? null,
    ponteOrigem: divisor?.source.name ?? null,
    divergenciaPonte: divisor?.divergence ?? null,
    adtv,
    coberturaJuros: latest.interestCoverage,
    alavancagem: latest.netDebtToEbitda,
    discordam: latest.sharesDisagree,
    marketCap: latest.marketCap,
    // Séries
    pontosFirma: firmSeries.length,
    pontosAcionista: shareholderSeries.length,
    anoUltimoRetornoFirma: lastReturnYear,
    defasagemRetorno: lastReturnYear === null ? null : lastFiscalYear - lastReturnYear,
    anosDescartadosPorPrejuizo: allFirmReturns.filter((e) => e.descartado).length,
    roicAtual: firmSeries.latestReturn,
    roicCiclo: firmSeries.cycleReturn({ window: w }),
    roicCicloComPrejuizo: medianOf(withLoss),
    retencaoMediana: firmSeries.medianRetention,
    // Guardas
    phi,
    destoa: GrowthGuards.deviatesFromCycle(firmSeries),
    tendencia10Domina: tend10?.dominates ?? null,
    tendencia5Domina: tend5?.dominates ?? null,
    tendenciaSignificante: tend10?.isSignificant ?? null,
    tendenciaSlope: tend10?.slope ?? null,
    tendenciaT: tend10?.tStatistic ?? null,
    dominancia10: tend10?.dominance ?? null,
    dominancia5: tend5?.dominance ?? null,
    quedaTrienio: decline,
    ciclicoPesado: CyclicalSectors.hasCyclePrecedence({ sectorKey: inputs.sectorKey, industry: inputs.industry }),
    crescIdentificado: disp?.isIdentified ?? null,
    crescMediana: disp?.medianGrowth ?? null,
    crescRegressao: disp?.regressionGrowth ?? null,
    crescErroPadrao: disp?.stdError ?? null,
    crescFalha: disp?.failure ?? null,
    // Custo de capital
    beta: inputs.capm.beta,
    betaOrigem: inputs.capm.betaSource.name,
    rfCorrente: inputs.capm.riskFreeRate,
    rfTerminal: inputs.terminalRiskFreeRate,
    ke: inputs.capm.costOfEquity,
    keTerminal: capmT.costOfEquity,
    kdBruto: kd,
    kdEfetivo: coc?.effectiveCostOfDebt ?? null,
    kdConfinado: coc?.costOfDebtWasClamped ?? null,
    aliquotaEfetiva: tax,
    pesoDivida: coc?.debtShare ?? null,
    wacc: coc?.wacc ?? null,
    waccPiso: coc?.waccWasFloored ?? null,
    dividaBruta: latest.totalDebt,
    caixa: latest.totalCash,
    dividaLiquida: latest.netDebt,
    nopat: latest.nopatOrDerived,
    nopatPublicado: latest.nopat,
    ebit: latest.ebit,
    ebitda: latest.ebitda,
    lucroLiquido: latest.netIncome,
    lpaPublicado: latest.earningsPerShare,
    capitalInvestido: latest.investedCapital,
    capitalInvestidoOper: latest.investedCapitalOperating,
    patrimonio: latest.equityBookValue,
    despesaFinanceira: latest.interestExpense,
  };
}

export async function main(args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  const today = DateTime.local(2026, 9, 4);
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    errln(
      `ancoras: rf=${str(anchors.currentRiskFreeRate)} rfTerm=${str(anchors.riskFreeCagr)} ` +
        `ipca=${str(anchors.inflationCagr)} gNom=${str(anchors.nominalEconomyGrowth)}`,
    );

    const universe = (await ctx.fundamentals.universe()).unwrap();
    const target = args.length === 0 ? universe : universe.filter((t) => args.includes(t.value));

    const out: Record<string, unknown>[] = [];
    let i = 0;
    for (const ticker of target) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${target.length}\r`);
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
      if (prep.isErr) {
        out.push({ ticker: ticker.value, erro: prep.failureOrNull?.message ?? null });
        continue;
      }
      const inputs = prep.unwrap();
      const d = diagnose(inputs);
      for (const n of [10, 5]) {
        const variant = new ValuationInputs({
          ticker: inputs.ticker,
          asOf: inputs.asOf,
          fundamentals: inputs.fundamentals,
          marketPrice: inputs.marketPrice,
          capm: inputs.capm,
          projectionYears: n,
          perpetualGrowthCap: inputs.perpetualGrowthCap,
          sectorKey: inputs.sectorKey,
          industry: inputs.industry,
          inflation: inputs.inflation,
          declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
          prices: inputs.prices,
          isDistressed: inputs.isDistressed,
        });
        const r = ValuationCascade.evaluate(variant);
        d[`ok${n}`] = r.isOk;
        d[`motivo${n}`] = r.isOk ? null : (r.failureOrNull?.message ?? null);
        if (r.isOk) {
          const v = r.unwrap();
          d[`fv${n}`] = v.fairValue.reais;
          d[`upside${n}`] = v.upside;
          d[`modelo${n}`] = v.model.name;
          d[`desconto${n}`] = v.discountRate;
          d[`avisos${n}`] = v.warnings;
          d[`ressalvas${n}`] = v.diagnostics!.caveats.map((c) => c.key);
          d[`pesoTerminal${n}`] = v.diagnostics!.terminalShare;
          d[`equityShare${n}`] = v.diagnostics!.equityShare;
          d[`moat${n}`] = v.diagnostics!.moatApplied;
        }
      }
      out.push(d);
    }
    writeText('docs/validacao/deep_audit.json', jsonPretty(out, ' '));
    errln(`\nescrito docs/validacao/deep_audit.json (${out.length})`);
  } finally {
    await ctx.dispose();
  }
}
