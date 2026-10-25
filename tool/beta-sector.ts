// Beta desalavancado, e quanto o setor explica.
//
// **Por que agora.** O teste A1 ([decisão 39](../docs/decisoes/039-as-duas-vias-sao-modelos-independentes.md))
// mostrou que as duas vias são modelos independentes, e que uma das duas
// razões é que `Ke` e `WACC` não estão ligados pela alavancagem: o beta é
// regressão crua contra o Ibovespa, sem versão desalavancada. Sem essa ligação
// a identidade `FCFF/WACC ≡ FCFE/Ke` não fecha por construção, e a conciliação
// das vias não tem como acontecer.
//
// **O que se mede aqui, antes de trocar nada:**
//
//   1. **O ruído do beta atual.** `SE(β) = |β|·√((1−ρ²)/(ρ²·(n−2)))` — a
//      identidade que liga erro-padrão a correlação e tamanho de amostra. Um
//      beta cujo intervalo cobre 1,0 não distingue o ativo do mercado, e
//      alimenta um `Ke` com precisão fingida.
//   2. **Se o setor explica.** Desalavancando por Hamada,
//      `β_U = β_L / (1 + (1−t)·D/E)`, o que sobra é risco do **negócio**. Se a
//      dispersão dentro do setor for muito menor que a do universo, a mediana
//      setorial é estimador melhor que a regressão individual. Se não for, o
//      agrupamento não compra nada.
//   3. **Quanto muda.** Realavancando a mediana setorial para a estrutura de
//      capital do próprio ativo, quanto o beta e o `Ke` se movem.
//
// **D/E é a preço de mercado e sobre dívida bruta**, para ficar consistente
// com o que `CostOfCapital` já usa no peso da dívida — misturar dívida líquida
// aqui e bruta lá produziria duas alavancagens no mesmo cálculo.
//
// Uso:
//   npm run tool -- beta-sector
//   npm run tool -- beta-sector --limit 40
import {
  BetaCalculator,
  BetaObservation,
  type BetaPrior,
  CapitalSeries,
  CapmInputs,
  compareNum,
  DateRange,
  DateTime,
  Inference,
  intDiv,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  Ticker,
  tryParseInt,
  ValuationCascade,
  ValuationParameters,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/**
 * Erro-padrão da inclinação, pela identidade com a correlação.
 *
 * `SE(β) = |β| · √((1 − ρ²) / (ρ² · (n − 2)))`. Devolve `null` sem correlação
 * utilizável ou com amostra curta demais.
 */
function standardError(beta: number, rho: number, n: number): number | null {
  if (n <= 2) return null;
  const r2 = rho * rho;
  if (r2 <= 0 || r2 >= 1) return null;
  const v = Math.abs(beta) * Math.sqrt((1 - r2) / (r2 * (n - 2)));
  return Number.isFinite(v) ? v : null;
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/** Desvio absoluto mediano escalado — dispersão robusta. */
const mad = (v: readonly number[]): number | null => Inference.scaledMad(v);

/**
 * Uma linha do relatório. Os campos depois de `rfCorrente` entram na ordem em
 * que cada etapa os calcula, e só quando a etapa tem o que dizer — como no
 * relatório original.
 */
interface Row {
  ticker: string;
  setor: string | null;
  betaRegressao: number;
  correlacao: number;
  observacoes: number;
  erroPadrao: number | null;
  dividaSobreEquity: number;
  aliquotaEstrutural: number;
  fatorHamada: number;
  betaDesalavancado: number | null;
  rfCorrente: number;
  betaUSetor?: number | null;
  pesoVasicek?: number;
  betaEncolhido?: number;
  variacaoVasicek?: number;
  variacaoKeVasicek?: number;
  ativosNoSetor?: number;
  betaRealavancado?: number;
  variacaoBeta?: number;
  variacaoKe?: number;
  justoSemPrior?: number | null;
  justoComPrior?: number | null;
  variacaoJusto?: number;
}

export async function main(args: string[]): Promise<void> {
  const limitIndex = args.indexOf('--limit');
  const limit = limitIndex >= 0 ? (tryParseInt(args[limitIndex + 1] ?? '') ?? 0) : 0;

  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    let universe = (await ctx.fundamentals.universe()).unwrap();
    if (limit > 0 && universe.length > limit) universe = universe.slice(0, limit);

    const window = new DateRange(DateTime.local(today.year - PrepareValuationInputs.betaWindowYears, today.month, today.day), today);
    const ibov = await ctx.benchmark.ibovespa(window);
    if (ibov.isErr) {
      errln(`sem Ibovespa: ${ibov.failureOrNull?.message ?? null}`);
      process.exitCode = 2;
      return;
    }
    const index = ibov.unwrap();

    const output: Row[] = [];
    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);

      const prices = await ctx.prices.daily(ticker, window);
      if (prices.isErr) continue;

      const points = prices.unwrap().points;
      const aligned = BetaCalculator.alignReturns({
        assetDates: points.map((p) => p.date),
        assetIndex: points.map((p) => p.close),
        marketDates: index.dates,
        marketIndex: index.points.map((p) => p.close),
      });
      const estimateResult = BetaCalculator.estimate({ returns: aligned });
      if (estimateResult.isErr) continue;
      const est = estimateResult.unwrap();

      const historyResult = await ctx.fundamentals.history(ticker);
      if (historyResult.isErr) continue;
      const pub = new PointInTimeView(today).published(historyResult.unwrap());
      if (pub.length === 0) continue;
      const latest = pub[pub.length - 1]!;

      const profile = await ctx.fundamentals.profile(ticker);
      // A chave, não o rótulo: é ela que agrupa de forma estável. Chave vazia
      // é ausência de setor, não um setor chamado "".
      const key = profile.isOk ? profile.unwrap().sector.key.trim() : '';
      const sector = key.length === 0 ? null : key;

      const grossDebt = latest.totalDebt;
      const marketEquity = latest.marketCap;
      if (marketEquity === null || marketEquity <= 0) continue;
      const debtToEquity = grossDebt / marketEquity;

      const taxRate =
        CapitalSeries.structuralTaxRate(pub, { statutoryRate: ValuationParameters.statutoryTaxRate }) ??
        ValuationParameters.statutoryTaxRate;

      // Hamada: β_L = β_U · (1 + (1 − t)·D/E)
      const hamadaFactor = 1 + (1 - taxRate) * debtToEquity;
      const betaU = hamadaFactor > 0 ? est.beta / hamadaFactor : null;

      output.push({
        ticker: ticker.value,
        setor: sector,
        betaRegressao: est.beta,
        correlacao: est.correlation,
        observacoes: est.observations,
        erroPadrao: standardError(est.beta, est.correlation, est.observations),
        dividaSobreEquity: debtToEquity,
        aliquotaEstrutural: taxRate,
        fatorHamada: hamadaFactor,
        betaDesalavancado: betaU,
        rfCorrente: anchors.currentRiskFreeRate,
      });
    }
    errln('');

    // --- Medianas setoriais do beta desalavancado ---
    const bySector = new Map<string, number[]>();
    for (const e of output) {
      const s = e.setor;
      const b = e.betaDesalavancado;
      if (s === null || b === null || !Number.isFinite(b)) continue;
      let list = bySector.get(s);
      if (list === undefined) bySector.set(s, (list = []));
      list.push(b);
    }
    const sectorMedian = new Map<string, number>();
    for (const [k, v] of bySector) if (v.length >= 3) sectorMedian.set(k, median(v)!);

    // Dispersão transversal dos betas de regressão — é a variância do
    // **prior** no encolhimento de Vasicek. Sem ela não há como pesar o
    // estimador individual contra o do grupo.
    const priorDispersion = mad(output.map((e) => e.betaRegressao).filter((b) => Number.isFinite(b))) ?? 0.5;
    const universeMedian =
      median(output.map((e) => e.betaDesalavancado).filter((b): b is number => b !== null && Number.isFinite(b))) ?? 0.5;

    for (const e of output) {
      const s = e.setor;
      const mu = s === null ? null : (sectorMedian.get(s) ?? null);
      e.betaUSetor = mu;

      // --- Encolhimento de Vasicek ---
      //
      // `w = (1/SE²) / (1/SE² + 1/σ_prior²)`. O peso do estimador individual é
      // a **precisão** dele contra a do prior: um beta com erro-padrão de 0,07
      // fica com 98% de si mesmo, e um com 83.228 fica com nada. Nenhum limiar
      // decide — a precisão decide, e é contínua.
      const se = e.erroPadrao;
      const factor = e.fatorHamada;
      const priorU = mu ?? universeMedian;
      const priorL = priorU * factor;
      const individual = e.betaRegressao;
      if (se !== null && se > 0 && priorDispersion > 0) {
        const individualPrecision = 1 / (se * se);
        const priorPrecision = 1 / (priorDispersion * priorDispersion);
        const w = individualPrecision / (individualPrecision + priorPrecision);
        const shrunk = w * individual + (1 - w) * priorL;
        e.pesoVasicek = w;
        e.betaEncolhido = shrunk;
        e.variacaoVasicek = shrunk - individual;
        e.variacaoKeVasicek = (shrunk - individual) * CapmInputs.defaultMarketPremium;
      }
      e.ativosNoSetor = s === null ? 0 : (bySector.get(s)?.length ?? 0);
      if (mu !== null) {
        const newPackage = mu * e.fatorHamada;
        e.betaRealavancado = newPackage;
        e.variacaoBeta = newPackage - e.betaRegressao;
        // Efeito direto no Ke, ao prêmio parametrizado.
        e.variacaoKe = (newPackage - e.betaRegressao) * CapmInputs.defaultMarketPremium;
      }
    }

    // --- Efeito em produção: avaliar com e sem o prior ---
    //
    // O prior sai das mesmas observações que este utilitário já coletou, pelo
    // agregador do núcleo — não por uma segunda implementação aqui.
    const prior = ResolveBetaPrior.fromObservations(
      output.map(
        (e) =>
          new BetaObservation({
            leveredBeta: e.betaRegressao,
            sectorKey: e.setor,
            debtToEquity: e.dividaSobreEquity,
            taxRate: e.aliquotaEstrutural,
          }),
      ),
    );
    if (prior !== null) {
      errln(
        `prior: ${prior.unleveredBySector.size} setores, universo=${prior.unleveredUniverse.toFixed(3)}, ` +
          `dispersão=${prior.dispersion.toFixed(3)}`,
      );
      let j = 0;
      for (const e of output) {
        j++;
        if (j % 25 === 0) process.stderr.write(`  produção ${j}/${output.length}   \r`);
        const t = Ticker.parse(e.ticker);

        const fairValue = async (p: BetaPrior | null = null): Promise<number | null> => {
          const prep = await PrepareValuationInputs.call({
            ticker: t,
            prices: ctx.prices,
            fundamentals: ctx.fundamentals,
            benchmark: ctx.benchmark,
            riskFreeRate: anchors.currentRiskFreeRate,
            asOf: today,
            perpetualGrowthCap: anchors.nominalEconomyGrowth,
            inflation: anchors.inflationCagr,
            terminalRiskFreeRate: anchors.riskFreeCagr,
            projectionYears: 10,
            betaPrior: p,
          });
          if (prep.isErr) return null;
          const r = ValuationCascade.evaluate(prep.unwrap());
          return r.isOk ? r.unwrap().fairValue.reais : null;
        };

        const without = await fairValue();
        const withInput = await fairValue(prior);
        e.justoSemPrior = without;
        e.justoComPrior = withInput;
        if (without !== null && withInput !== null && without > 0) e.variacaoJusto = withInput / without - 1;
      }
      errln('');
    }

    writeText('docs/validacao/beta_setorial.json', jsonPretty(output, ' '));
    printReport(output, bySector, sectorMedian);
    errln(`\nescrito docs/validacao/beta_setorial.json (${output.length})`);
  } finally {
    await ctx.dispose();
  }
}

type NumericKey = {
  [K in keyof Row]-?: NonNullable<Row[K]> extends number ? K : never;
}[keyof Row];

function printReport(l: readonly Row[], bySector: Map<string, number[]>, sectorMedian: Map<string, number>): void {
  const col = (k: NumericKey): number[] =>
    l.map((e) => e[k]).filter((v): v is number => v !== null && v !== undefined && Number.isFinite(v));
  const n2 = (x: number | null | undefined): string => (x === null || x === undefined ? '—' : x.toFixed(2));
  const pc = (x: number | null | undefined): string => (x === null || x === undefined ? '—' : `${(x * 100).toFixed(2)} p.p.`);
  const sortedAsc = (v: readonly number[]): number[] => [...v].sort(compareNum);

  outln(`\n=== BETA DESALAVANCADO — ${l.length} ativos ===\n`);

  // --- 1. O ruído do beta atual ---
  const se = col('erroPadrao');
  const betas = col('betaRegressao');
  outln('-- ruído do beta de regressão --');
  outln(`  β: mediana=${n2(median(betas))}  dispersão robusta=${n2(mad(betas))}`);
  if (se.length > 0) {
    const s = sortedAsc(se);
    outln(`  erro-padrão: mediana=${n2(median(s))}  p75=${n2(s[intDiv(3 * s.length, 4)])}  p90=${n2(s[intDiv(9 * s.length, 10)])}`);
    let coversOne = 0;
    let seAbove03 = 0;
    for (const e of l) {
      const b = e.betaRegressao;
      const err = e.erroPadrao;
      if (err === null) continue;
      if (Math.abs(b - 1) < 1.96 * err) coversOne++;
      if (err > 0.3) seAbove03++;
    }
    outln(`  intervalo de 95% cobre 1,0 em ${coversOne} de ${se.length}  (o beta não distingue o ativo do mercado)`);
    outln(`  erro-padrão acima de 0,30: ${seAbove03} de ${se.length}`);
  }

  // --- 2. O setor explica? ---
  const bu = col('betaDesalavancado');
  const universeDispersion = mad(bu);
  const within: number[] = [];
  for (const v of bySector.values()) {
    if (v.length < 3) continue;
    const m = mad(v);
    if (m !== null && Number.isFinite(m)) within.push(m);
  }
  outln('\n-- o setor explica risco de negócio? --');
  outln(`  β desalavancado: mediana=${n2(median(bu))}  dispersão robusta do universo=${n2(universeDispersion)}`);
  outln(`  dispersão robusta MEDIANA dentro do setor=${n2(median(within))}  (${within.length} setores com 3+ ativos)`);
  const withinMedian = median(within);
  if (universeDispersion !== null && withinMedian !== null) {
    const reduction = 1 - withinMedian / universeDispersion;
    outln(`  redução de dispersão ao agrupar: ${(reduction * 100).toFixed(1)}%`);
  }
  outln(`  ativos sem setor com 3+ pares: ${l.filter((e) => e.betaUSetor === null || e.betaUSetor === undefined).length} de ${l.length}`);

  // --- 3. Quanto muda ---
  const dBeta = col('variacaoBeta');
  const dKe = col('variacaoKe');
  outln('\n-- efeito de trocar regressão por setorial realavancado --');
  if (dBeta.length > 0) {
    const s = sortedAsc(dBeta.map((x) => Math.abs(x)));
    outln(`  |Δβ|: mediana=${n2(median(s))}  p90=${n2(s[intDiv(9 * s.length, 10)])}  máx=${n2(s[s.length - 1])}`);
    outln(`  Δβ mediano com sinal: ${n2(median(dBeta))}`);
  }
  if (dKe.length > 0) {
    const s = sortedAsc(dKe.map((x) => Math.abs(x)));
    outln(`  |ΔKe|: mediana=${pc(median(s))}  p90=${pc(s[intDiv(9 * s.length, 10)])}`);
    outln(`  ΔKe mediano com sinal: ${pc(median(dKe))}`);
  }

  // --- 3b. Encolhimento de Vasicek ---
  const w = col('pesoVasicek');
  const dv = col('variacaoVasicek');
  const dkv = col('variacaoKeVasicek');
  outln('\n-- encolhimento por precisão (Vasicek) --');
  if (w.length > 0) {
    const s = sortedAsc(w);
    outln(`  peso do estimador individual: mediana=${n2(median(s))}  p10=${n2(s[intDiv(s.length, 10)])}  mín=${n2(s[0])}`);
    outln(`  abaixo de 0,90 (o prior pesa): ${w.filter((x) => x < 0.9).length} de ${w.length}`);
  }
  if (dv.length > 0) {
    const s = sortedAsc(dv.map((x) => Math.abs(x)));
    outln(`  |Δβ|: mediana=${n2(median(s))}  p90=${n2(s[intDiv(9 * s.length, 10)])}  máx=${n2(s[s.length - 1])}`);
    outln(`  |ΔKe|: mediana=${pc(median(dkv.map((x) => Math.abs(x))))}`);
  }

  // --- 3c. Efeito em produção ---
  const dj = col('variacaoJusto');
  outln('\n-- efeito no preço justo, em produção --');
  if (dj.length === 0) {
    outln('  sem comparação disponível');
  } else {
    const s = sortedAsc(dj.map((x) => Math.abs(x)));
    outln(`  avaliados nos dois modos: ${dj.length}`);
    outln(`  |Δ preço justo|: mediana=${pc(median(s))}  p90=${pc(s[intDiv(9 * s.length, 10)])}  máx=${pc(s[s.length - 1])}`);
    outln(`  alterados além de 0,5%: ${dj.filter((x) => Math.abs(x) > 0.005).length} de ${dj.length}`);
  }

  // --- 4. Os setores ---
  outln('\n-- mediana desalavancada por setor (3+ ativos) --');
  const sortedEntries = [...sectorMedian.entries()].sort((a, b) => compareNum(a[1], b[1]));
  for (const [k, v] of sortedEntries) {
    outln(`  ${k.padEnd(34)} β_U=${n2(v)}  n=${bySector.get(k)!.length}  dispersão=${n2(mad(bySector.get(k)!))}`);
  }
}
