// B14 — o beta do papel pouco negociado, e o que ele faz com o nível.
//
// **A pergunta.** A [decisão 95](../docs/decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)
// deixou a recusa por liquidez de pé por **uma** razão: soltos do corte, os
// recusados ordenam o retorno, mas o preço justo deles sai 27 p.p. acima do das
// avaliadas. A explicação proposta foi o beta: papel com pouco negócio responde
// ao mercado com atraso, a covariância contemporânea perde a parte atrasada, o
// beta sai baixo, o custo de capital sai baixo e o preço justo sai alto.
//
// **Se for isso, um beta corrigido tira a razão da recusa.** É o que este
// programa mede, e é o item B14.
//
// [`beta_sincronia.md`](../docs/validacao/beta_sincronia.md) já mediu a
// correção de Dimson **nos avaliados**, e lá ela não existe: a Porta 0 removeu
// quem sofreria. Aquele documento fecha dizendo que, se o corte de liquidez for
// afrouxado, o item volta com o tamanho que o universo cru mostra. Aqui ele
// volta.
//
// **O que se mede, sobre a entrada congelada do gabarito:**
//
//   1. o beta de Dimson contra o diário, nos recusados **só por liquidez** e
//      nos avaliados, com os pregões por ano de cada grupo;
//   2. o preço justo dos soltos com o beta diário e com o de Dimson, os dois
//      sem o corte de liquidez;
//   3. o nível do potencial dos três conjuntos, que é a grandeza da decisão 95.
//
// Uso:
//   npm run tool -- cascade-golden      # congela a entrada
//   npm run tool -- beta-liquidity
import {
  BetaCalculator,
  BetaShrinkage,
  CapmInputs,
  compareNum,
  EligibilityGate,
  MarketLeverage,
  PointInTimeView,
  PrepareValuationInputs,
  round,
  type Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationParameters,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';
import { Regression } from './validation/regression';

const output = 'docs/validacao/beta_liquidez.json';

/** Mínimo de pares para a regressão de Dimson ter sentido. */
const minPeers = 40;

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function quantile(v: readonly number[], p: number): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  return s[round(p * (s.length - 1))]!;
}

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);

/** `toFixed` que escreve `null` para o ausente, como a interpolação do Dart. */
const fx = (v: number | null, digits: number): string => (v === null ? 'null' : v.toFixed(digits));

/**
 * `β = Σ_{k=−K}^{K} β_k`, das inclinações de uma regressão múltipla — a
 * correção de Dimson para negociação não síncrona, com [lags] defasagens e
 * outras tantas antecipações.
 *
 * **Uma defasagem é a forma clássica, e ela supõe que o atraso cabe num
 * pregão.** Papel que negocia sessenta vezes por ano não responde ao mercado
 * no dia seguinte: responde no próximo negócio, que pode estar a uma semana.
 * Por isso a medição do B14 roda também com cinco — se o beta corrigido subir
 * até o dos avaliados, o atraso era o problema; se não subir, o beta daquele
 * papel não é estimável com esta série, e isso é outra coisa.
 */
function dimson(ra: readonly number[], rm: readonly number[], lags = 1): { beta: number; error: number } | null {
  // Cada termo consome dois graus de liberdade de amostra nas pontas e um
  // coeficiente; sem folga, a regressão devolve ruído com cara de número.
  if (ra.length < minPeers + 4 * lags) return null;
  const y: number[] = [];
  const columns: number[][] = Array.from({ length: 2 * lags + 1 }, () => []);
  for (let t = lags; t < ra.length - lags; t++) {
    y.push(ra[t]!);
    for (let k = -lags; k <= lags; k++) columns[k + lags]!.push(rm[t + k]!);
  }
  const ols = Regression.ols(columns, y);
  if (ols === null) return null;
  let beta = 0.0;
  // Erro-padrão da soma **ignorando a covariância entre os coeficientes**: é
  // cota inferior, e serve para ordem de grandeza — que é o uso aqui.
  let v = 0.0;
  for (let k = 1; k <= columns.length; k++) {
    beta += ols.coefficients[k]!;
    v += ols.stdErrors[k]! * ols.stdErrors[k]!;
  }
  return { beta, error: v <= 0 ? 0.0 : root(v) };
}

/** Raiz quadrada por Newton, como a medição original fazia. */
function root(x: number): number {
  if (x <= 0) return 0;
  let r = x;
  for (let i = 0; i < 60; i++) r = 0.5 * (r + x / r);
  return r;
}

/**
 * Os mesmos insumos **sem a série de preços**, que é o que desliga o corte de
 * liquidez da Porta 0 — e só ele: o beta já foi estimado e viaja no CAPM.
 *
 * Com [beta] e [unleveredBeta], o CAPM é remontado sobre o beta informado.
 */
function unconstrained(b: ValuationInputs, options: { beta?: number; unleveredBeta?: number | null } = {}): ValuationInputs {
  const { beta } = options;
  return new ValuationInputs({
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm:
      beta === undefined
        ? b.capm
        : new CapmInputs({
            riskFreeRate: b.capm.riskFreeRate,
            beta,
            marketPremium: b.capm.marketPremium,
            betaSource: b.capm.betaSource,
            premiumSource: b.capm.premiumSource,
          }),
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
    riskFreeCurve: b.riskFreeCurve,
    officialShares: b.officialShares,
    isDistressed: b.isDistressed,
    unleveredBeta: options.unleveredBeta ?? b.unleveredBeta,
    concessionEnd: b.concessionEnd,
    dividendsInBeta: b.dividendsInBeta,
    creditReferenceRiskFree: b.creditReferenceRiskFree,
    declaredSharesPerUnit: b.declaredSharesPerUnit,
  });
}

interface Row {
  ticker: string;
  grupo: 'solto' | 'avaliado';
  pregoes: number;
  pregoesPorAno: number;
  liquidez: number | null;
  betaDiario: number;
  seDiario: number | null;
  betaDimson: number | null;
  seDimson: number | null;
  betaDimson5: number | null;
  seDimson5: number | null;
  betaDeProducao: number;
  betaDiarioEncolhido: number | null;
  betaDimsonEncolhido: number | null;
  betaDimson5Encolhido: number | null;
  potencial: number | null;
  potencialComDimson: number | null;
  potencialComDimson5: number | null;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const indexResult = await c.ctx.benchmark.ibovespa(c.betaWindow);
    if (indexResult.isErr) {
      errln(`sem índice: ${indexResult.failureOrNull?.message ?? null}`);
      process.exitCode = 2;
      return;
    }
    const index = indexResult.unwrap();
    const indexDates = index.dates;
    const indexCloses = index.points.map((p) => p.close);

    const rows: Row[] = [];
    const evaluated = new Map<Ticker, ValuationResult | null>();
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const inputs = prep.unwrap();
      const base = ValuationCascade.evaluate(inputs);
      evaluated.set(t, base.valueOrNull);

      const refusal = base.isErr ? base.failureOrNull!.message : null;
      const liquidityOnly = refusal !== null && refusal.includes('liquidez');
      if (!liquidityOnly && refusal !== null) continue;

      // --- O beta diário de produção e o de Dimson, na mesma janela --------
      const series = inputs.prices;
      if (series === null) continue;
      const points = series.points.filter((p) => c.betaWindow.contains(p.date));
      if (points.length < 60) continue;
      const pair = BetaCalculator.alignReturns({
        assetDates: points.map((p) => p.date),
        assetIndex: points.map((p) => p.close),
        marketDates: indexDates,
        marketIndex: indexCloses,
      });
      const daily = BetaCalculator.estimate({ returns: pair });
      if (daily.isErr) continue;
      const d = daily.unwrap();
      const dim = dimson(pair.asset, pair.market);
      const dim5 = dimson(pair.asset, pair.market, 5);

      // **O contrafactual tem de ser justo.** O beta de produção já é
      // encolhido em direção ao prior setorial (decisão 40), e Dimson tem
      // erro-padrão muito maior: comparar o encolhido com um Dimson cru
      // premiaria o ruído. Aqui o mesmo encolhimento é aplicado aos dois, com
      // o erro-padrão de cada um — que é o que a produção faria se adotasse a
      // correção.
      const published = new PointInTimeView(frozenToday).published(inputs.fundamentals);
      const last = published.length === 0 ? null : published[published.length - 1]!;
      const market = last?.marketCap ?? null;
      const debtToEquity =
        last === null || market === null || market <= 0
          ? null
          : (MarketLeverage.overWindow({ snapshots: published, prices: points, window: c.betaWindow }) ??
            last.debtToMarketEquity(market) ??
            0.0);
      const prior = c.prior;
      const shrink = (raw: number | null, error: number | null): number | null => {
        if (raw === null || prior === null || debtToEquity === null) return null;
        return BetaShrinkage.shrink({
          leveredBeta: raw,
          standardError: error,
          prior,
          sectorKey: inputs.sectorKey,
          debtToEquity,
          taxRate: ValuationParameters.statutoryTaxRate,
        }).beta;
      };

      const shrunkDaily = shrink(d.beta, d.standardError);
      const shrunkDimson = shrink(dim?.beta ?? null, dim?.error ?? null);
      const shrunkDimson5 = shrink(dim5?.beta ?? null, dim5?.error ?? null);

      // --- O preço justo solto do corte, com um beta e com o outro ---------
      const upside = (x: ValuationInputs): number | null => {
        const r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().upside : null;
      };

      const withDaily = liquidityOnly ? upside(unconstrained(inputs)) : null;
      // O beta desalavancado escala com o alavancado: Hamada é linear em `β_L`
      // e o fator de alavancagem não muda entre os dois estimadores.
      const withBeta = (shrunk: number | null): number | null => {
        if (!liquidityOnly || shrunk === null) return null;
        const reference = inputs.capm.beta;
        if (Math.abs(reference) < 1e-9) return null;
        const factor = shrunk / reference;
        return upside(
          unconstrained(inputs, {
            beta: shrunk,
            unleveredBeta: inputs.unleveredBeta === null ? null : inputs.unleveredBeta * factor,
          }),
        );
      };

      const withDimson = withBeta(shrunkDimson);
      const withDimson5 = withBeta(shrunkDimson5);

      rows.push({
        ticker: t.value,
        grupo: liquidityOnly ? 'solto' : 'avaliado',
        pregoes: points.length,
        pregoesPorAno: points.length / PrepareValuationInputs.betaWindowYears,
        liquidez: EligibilityGate.medianTradedValue(series),
        betaDiario: d.beta,
        seDiario: d.standardError ?? null,
        betaDimson: dim?.beta ?? null,
        seDimson: dim?.error ?? null,
        betaDimson5: dim5?.beta ?? null,
        seDimson5: dim5?.error ?? null,
        betaDeProducao: inputs.capm.beta,
        betaDiarioEncolhido: shrunkDaily,
        betaDimsonEncolhido: shrunkDimson,
        betaDimson5Encolhido: shrunkDimson5,
        potencial: liquidityOnly ? withDaily : (base.valueOrNull?.upside ?? null),
        potencialComDimson: withDimson,
        potencialComDimson5: withDimson5,
      });
    }
    errln('');

    const divergent = await c.checkAgainstAnswerKey(evaluated);
    writeText(
      output,
      jsonPretty(
        {
          medidoEm: frozenToday.toIso8601String().substring(0, 10),
          conferidoContraOGabarito: divergent?.length ?? null,
          ativos: rows,
        },
        ' ',
      ),
    );
    printReport(rows, divergent);
    errln(`\nescrito ${output} (${rows.length})`);
  } finally {
    await c.ctx.dispose();
  }
}

type NumericKey = {
  [K in keyof Row]: Row[K] extends number | null ? K : never;
}[keyof Row];

function printReport(l: readonly Row[], divergent: string[] | null): void {
  if (divergent === null) {
    outln('\n!! sem gabarito para conferir: a montagem não foi verificada contra a do aplicativo');
  } else if (divergent.length > 0) {
    outln(`\n!! a montagem DIVERGE do gabarito em ${divergent.length} ativo(s): ${divergent.slice(0, 8).join(', ')}`);
    outln('!! os números abaixo não valem');
  } else {
    outln('\nmontagem idêntica à do gabarito na montagem do aplicativo.');
  }

  const group = (g: Row['grupo']): Row[] => l.filter((e) => e.grupo === g);
  const col = (xs: readonly Row[], k: NumericKey): number[] =>
    xs.map((e) => e[k]).filter((v): v is number => v !== null && Number.isFinite(v));

  const unconstrainedOnes = group('solto');
  const evaluated = group('avaliado');
  const groups = [
    ['soltos', unconstrainedOnes],
    ['avaliados', evaluated],
  ] as const;
  outln('\n=== B14 — O BETA DO PAPEL POUCO NEGOCIADO ===');
  outln(`soltos do corte: ${unconstrainedOnes.length}   avaliados: ${evaluated.length}`);

  outln('\n-- quanto cada grupo negocia --');
  for (const [name, xs] of groups) {
    const sessionsPerYear = col(xs, 'pregoesPorAno');
    const liq = col(xs, 'liquidez');
    outln(
      `  ${name.padEnd(10)} pregões/ano mediana ${fx(median(sessionsPerYear), 0)}  p10 ` +
        `${fx(quantile(sessionsPerYear, 0.1), 0)}   giro diário mediano R$ ${((median(liq) ?? 0) / 1000).toFixed(0)} mil`,
    );
  }

  for (const k of ['betaDimson', 'betaDimson5'] as const) {
    outln(`\n-- ${k === 'betaDimson' ? 'Dimson, uma defasagem' : 'Dimson, cinco defasagens'} ÷ diário --`);
    for (const [name, xs] of groups) {
      const ratios: number[] = [];
      for (const e of xs) {
        const a = e.betaDiario;
        const b = e[k];
        if (b === null || Math.abs(a) < 1e-9) continue;
        ratios.push(b / a);
      }
      if (ratios.length === 0) continue;
      outln(
        `  ${name.padEnd(10)} p10 ${quantile(ratios, 0.1)!.toFixed(3)}  mediana ${median(ratios)!.toFixed(3)}  p90 ` +
          `${quantile(ratios, 0.9)!.toFixed(3)}   acima do diário em ${ratios.filter((x) => x > 1).length} de ${ratios.length}`,
      );
    }
  }

  outln('\n-- beta em nível, cru --');
  for (const [name, xs] of groups) {
    outln(
      `  ${name.padEnd(10)} diário ${fx(median(col(xs, 'betaDiario')), 3)}   ` +
        `Dimson(1) ${fx(median(col(xs, 'betaDimson')), 3)}   ` +
        `Dimson(5) ${fx(median(col(xs, 'betaDimson5')), 3)}   ` +
        `SE diário ${fx(median(col(xs, 'seDiario')), 4)}` +
        `  SE Dimson(1) ${fx(median(col(xs, 'seDimson')), 4)}` +
        `  SE Dimson(5) ${fx(median(col(xs, 'seDimson5')), 4)}`,
    );
  }

  // O que chega ao preço é o beta **encolhido** (decisão 40), e o erro-padrão
  // maior de Dimson desloca peso para o prior setorial. Sem esta linha, a
  // comparação premiaria o estimador mais ruidoso.
  outln('\n-- beta em nível, encolhido (é o que chega ao preço) --');
  for (const [name, xs] of groups) {
    outln(
      `  ${name.padEnd(10)} produção ${fx(median(col(xs, 'betaDeProducao')), 3)}   ` +
        `diário ${fx(median(col(xs, 'betaDiarioEncolhido')), 3)}` +
        `   Dimson(1) ${fx(median(col(xs, 'betaDimsonEncolhido')), 3)}` +
        `   Dimson(5) ${fx(median(col(xs, 'betaDimson5Encolhido')), 3)}`,
    );
  }

  // **Os soltos não são um grupo só.** Metade deles negocia todo pregão, e ali
  // a não sincronia não tem o que explicar; o beta baixo é outra coisa.
  outln('\n-- os soltos, por frequência de negócio --');
  const bands: [string, (x: number) => boolean][] = [
    ['negocia todo dia (>=240/ano)', (x) => x >= 240],
    ['intermitente (120 a 240)', (x) => x >= 120 && x < 240],
    ['raro (< 120/ano)', (x) => x < 120],
  ];
  for (const [name, test] of bands) {
    const xs = unconstrainedOnes.filter((e) => test(e.pregoesPorAno));
    if (xs.length === 0) continue;
    outln(
      `  ${name.padEnd(28)} n=${String(xs.length).padStart(3)}` +
        `  beta diário ${fx(median(col(xs, 'betaDiario')), 3)}` +
        `  Dimson(1) ${fx(median(col(xs, 'betaDimson')), 3)}` +
        `  Dimson(5) ${fx(median(col(xs, 'betaDimson5')), 3)}` +
        `  potencial ${pc(median(col(xs, 'potencial')))}`,
    );
  }

  outln('\n-- o nível do potencial, que é a razão da recusa --');
  outln(`  avaliados                   ${pc(median(col(evaluated, 'potencial')))}`);
  outln(`  soltos, beta diário         ${pc(median(col(unconstrainedOnes, 'potencial')))}`);
  outln(`  soltos, Dimson(1) encolhido ${pc(median(col(unconstrainedOnes, 'potencialComDimson')))}`);
  outln(`  soltos, Dimson(5) encolhido ${pc(median(col(unconstrainedOnes, 'potencialComDimson5')))}`);
  const withBoth: number[] = [];
  for (const e of unconstrainedOnes) {
    if (e.potencial !== null && e.potencialComDimson !== null) withBoth.push(e.potencialComDimson - e.potencial);
  }
  outln(`  nos ${withBoth.length} soltos com os dois: Dimson move o potencial em ${pc(median(withBoth))} na mediana`);
}
