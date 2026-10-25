// D4 — de onde vem o resíduo entre o preço justo e o de mercado.
//
// **A pergunta.** O preço justo mediano fica 36% abaixo do de mercado. Isso não
// é defeito por si: o motor não existe para reproduzir o mercado, e a
// [decisão 35](../docs/decisoes/035-dcf-reverso-e-regressao-condicional.md)
// veda ajustá-lo até que reproduza. O que é defeito é a parte do resíduo que
// vem de o motor usar um número que não é o da empresa, ou uma convenção que
// não é a correta.
//
// **O desenho.** Para cada ativo mede-se quanto o preço justo teria de subir
// para bater no de mercado — `m_necessário = preço ÷ justo` —, e quanto cada
// contrafactual entrega:
//
//   fração fechada = (justo_contrafactual ÷ justo − 1) / (m_necessário − 1)
//
// **Os contrafactuais rodam PELA CASCATA**, por `ValuationInputs.reinvestmentOverride`,
// e não por uma reimplementação da projeção. A versão anterior deste utilitário
// reimplementava, e media outro motor: usava o teto da economia como
// crescimento perpétuo em 78 dos 120 ativos e reinterpolava a taxa de desconto
// em vez de usar o caminho resolvido pelo ponto fixo. A conferência não pegava
// porque comparava o laço contra si mesmo.
//
// Uso:
//   npm run tool -- explicit-flow
//   npm run tool -- explicit-flow --limit 30
import {
  CashTiming,
  compareNum,
  DateTime,
  MarketAnchors,
  PrepareValuationInputs,
  ReinvestmentPolicy,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  tryParseInt,
  ValuationCascade,
  ValuationInputs,
  ValuationParameters,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const today = DateTime.local(2026, 9, 4);

/** Quantos passes o veredito da perpetuidade consumiu, lido do aviso. */
function passesOf(warnings: readonly string[]): number | null {
  for (const a of warnings) {
    const m = /fechou em (\d+) passe/.exec(a);
    if (m !== null) return tryParseInt(m[1]!);
    const i = /estabilizaram em (\d+) passes/.exec(a);
    if (i !== null) return tryParseInt(i[1]!);
  }
  return null;
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

const pc = (v: number): string => `${(v * 100).toFixed(1)}%`;
const mx = (v: number): string => `${v.toFixed(2)}x`;

interface Row {
  ticker: string;
  setor: string | null;
  via: string;
  preco: number;
  justo: number;
  potencial: number;
  participacaoEquity: number;
  pesoTerminal: number;
  crescimento: number;
  retornoDaBase: number;
  desconto: number;
  descontoTerminal: number;
  aliquotaEstrutural: number | null;
  passesDoVeredito: number | null;
  vereditoInstavel: boolean;
  retencaoAno1: number | null;
  retencaoAnoN: number | null;
  noTetoAno1: boolean;
  mNecessario: number;
  mSemFreio: number | null;
  mCrescimentoReal: number | null;
  mSemConvergencia: number | null;
  mSemTeto: number | null;
  mFimDeAno: number | null;
  fechaSemFreio: number | null;
  fechaCrescimentoReal: number | null;
  fechaSemConvergencia: number | null;
  fechaSemTeto: number | null;
}

type NumericKey = { [K in keyof Row]: Row[K] extends number | null ? K : never }[keyof Row];

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

    const prior = await ResolveBetaPrior.call({
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: today,
    });

    const output: Row[] = [];
    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);

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
        betaPrior: prior,
      });
      if (prep.isErr) continue;
      const inputs = prep.unwrap();

      const res = ValuationCascade.evaluate(inputs);
      if (res.isErr) continue;
      const v = res.unwrap();
      const d = v.diagnostics!;
      const fairValue = v.fairValue.reais;
      const price = inputs.marketPrice;
      if (fairValue <= 0 || price <= 0) continue;

      /** O mesmo ativo, pela mesma cascata, com o freio ou a convenção trocados. */
      const relative = (overrides: { policy?: ReinvestmentPolicy; timing?: CashTiming }): number | null => {
        const r = ValuationCascade.evaluate(
          new ValuationInputs({
            ticker: inputs.ticker,
            asOf: inputs.asOf,
            fundamentals: inputs.fundamentals,
            marketPrice: inputs.marketPrice,
            capm: inputs.capm,
            marginOfSafety: inputs.marginOfSafety,
            projectionYears: inputs.projectionYears,
            perpetualGrowthCap: inputs.perpetualGrowthCap,
            sectorKey: inputs.sectorKey,
            industry: inputs.industry,
            inflation: inputs.inflation,
            declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
            prices: inputs.prices,
            isDistressed: inputs.isDistressed,
            unleveredBeta: inputs.unleveredBeta,
            reinvestmentOverride: overrides.policy ?? null,
            cashTimingOverride: overrides.timing ?? null,
          }),
        );
        if (r.isErr) return null;
        const x = r.unwrap().fairValue.reais;
        return x > 0 ? x / fairValue : null;
      };

      const mRequired = price / fairValue;
      const closedFraction = (m: number | null): number | null => {
        if (m === null || !Number.isFinite(m)) return null;
        if (Math.abs(mRequired - 1) < 1e-9) return null;
        return (m - 1) / (mRequired - 1);
      };

      // O mesmo ativo com a convenção de caixa de antes da decisão 48.
      const mEndOfYear = relative({ timing: CashTiming.endOfYear });
      const mNoBrake = relative({ policy: ReinvestmentPolicy.none });
      const mReal = relative({ policy: ReinvestmentPolicy.realGrowth });
      const mNoConvergence = relative({ policy: ReinvestmentPolicy.noConvergence });
      const mUncapped = relative({ policy: ReinvestmentPolicy.uncapped });

      const retention = d.retentionPath;

      output.push({
        ticker: ticker.value,
        setor: inputs.sectorKey,
        via: v.model.name,
        preco: price,
        justo: fairValue,
        potencial: v.upside,
        participacaoEquity: d.equityShare,
        pesoTerminal: d.terminalShare,
        crescimento: d.growthRate,
        retornoDaBase: d.returnOnCapital,
        desconto: v.discountRate,
        descontoTerminal: d.terminalDiscountRate,
        aliquotaEstrutural: d.firmTaxRate,
        // Quantos passes o veredito da perpetuidade consumiu até parar de
        // mudar (decisão 51). Sai do aviso porque é propriedade da conta, e
        // não do resultado.
        passesDoVeredito: passesOf(v.warnings),
        vereditoInstavel: v.warnings.some((w) => w.includes('não se estabilizaram em')),
        // O freio, ano a ano, como a cascata o aplicou — inclusive com o
        // caminho de taxas resolvido dentro do `ROIC_t`.
        retencaoAno1: retention.length > 0 ? retention[0]! : null,
        retencaoAnoN: retention.length > 0 ? retention[retention.length - 1]! : null,
        noTetoAno1: retention.length > 0 && retention[0]! >= 0.9499,
        mNecessario: mRequired,
        mSemFreio: mNoBrake,
        mCrescimentoReal: mReal,
        mSemConvergencia: mNoConvergence,
        mSemTeto: mUncapped,
        mFimDeAno: mEndOfYear,
        fechaSemFreio: closedFraction(mNoBrake),
        fechaCrescimentoReal: closedFraction(mReal),
        fechaSemConvergencia: closedFraction(mNoConvergence),
        fechaSemTeto: closedFraction(mUncapped),
      });
    }
    errln('');

    writeText('docs/validacao/fluxo_explicito.json', jsonPretty(output, ' '));
    printReport(output);
    errln(`\nescrito docs/validacao/fluxo_explicito.json (${output.length} ativos)`);
  } finally {
    await ctx.dispose();
  }
}

function printReport(l: readonly Row[]): void {
  const finite = (rows: readonly Row[], k: NumericKey): number[] =>
    rows.map((e) => e[k]).filter((v): v is number => v !== null && Number.isFinite(v));
  const col = (k: NumericKey): number[] => finite(l, k);

  outln(`\n=== D4 — O RESÍDUO DO FLUXO EXPLÍCITO — ${l.length} avaliados ===\n`);

  const r1 = col('retencaoAno1');
  const rn = col('retencaoAnoN');
  outln('-- retenção imposta pelo freio --');
  outln(`  ano 1: mediana=${pc(median(r1)!)}   ano N: mediana=${pc(median(rn)!)}`);
  outln(`  no teto de 95% no ano 1: ${l.filter((e) => e.noTetoAno1).length} de ${l.length}`);

  const need = col('mNecessario').sort(compareNum);
  outln('\n-- quanto o preço justo teria de subir --');
  outln(
    `  p25=${mx(need[Math.floor(need.length / 4)]!)}  mediana=${mx(median(need)!)}  ` +
      `p75=${mx(need[Math.floor((3 * need.length) / 4)]!)}`,
  );
  outln(`  já acima do preço: ${need.filter((x) => x <= 1).length} de ${need.length}`);
  const stillBelow = need.filter((x) => x > 1);
  outln(`  entre os que têm vão a fechar: mediana=${mx(median(stillBelow)!)}  (n=${stillBelow.length})`);

  // **Só quem tem vão a fechar.** Trinta dos 120 já saem acima do preço de
  // mercado, e para eles todo contrafactual "fecha tudo" por vacuidade — a
  // mediana com eles dentro elogia qualquer coisa.
  const withGap = l.filter((e) => e.mNecessario > 1.0);
  outln(`\n-- contrafactuais, rodados pela cascata (${withGap.length} com vão a fechar) --`);
  const row = (name: string, engineKey: NumericKey, firmKey: NumericKey): void => {
    const ms = finite(withGap, engineKey);
    const fs = finite(withGap, firmKey);
    if (ms.length === 0) {
      outln(`  ${name.padEnd(28)} — sem medida`);
      return;
    }
    const closes = withGap.filter((e) => e[engineKey] !== null && e[engineKey]! >= e.mNecessario).length;
    outln(`  ${name.padEnd(28)} m=${mx(median(ms)!)}  fecha ${pc(median(fs) ?? 0).padStart(7)} do vão  (fecha tudo em ${closes} de ${ms.length})`);
  };

  row('freio desligado', 'mSemFreio', 'fechaSemFreio');
  row('freio só no crescimento real', 'mCrescimentoReal', 'fechaCrescimentoReal');
  row('sem convergência do ROIC', 'mSemConvergencia', 'fechaSemConvergencia');
  row('freio sem o teto de 95%', 'mSemTeto', 'fechaSemTeto');

  // Quantos passes a volta veredito-taxa consumiu (decisão 51).
  const passes = new Map<number, number>();
  let unstable = 0;
  for (const e of l) {
    const p = e.passesDoVeredito;
    if (p !== null) passes.set(p, (passes.get(p) ?? 0) + 1);
    if (e.vereditoInstavel) unstable++;
  }
  if (passes.size > 0) {
    const keys = [...passes.keys()].sort(compareNum);
    outln('\n-- passes do veredito da perpetuidade --');
    for (const k of keys) outln(`  ${k} ${k === 1 ? 'passe' : 'passes'}: ${passes.get(k)}`);
    outln(`  não estabilizaram no teto: ${unstable}`);
  }

  // A convenção de caixa não é contrafactual de freio: é a de **antes** da
  // decisão 48, e mede o que o meio de ano vale no universo. Vai como razão
  // pura, sem "fração fechada", porque ela já entrou em produção.
  const end = col('mFimDeAno');
  if (end.length > 0) {
    const sortedEntries = [...end].sort(compareNum);
    outln('\n-- o que a convenção de meio de ano vale --');
    outln(
      `  justo(fim de ano) ÷ justo(produção): p10=${mx(sortedEntries[Math.floor(sortedEntries.length * 0.1)]!)}  ` +
        `mediana=${mx(median(end)!)}  p90=${mx(sortedEntries[Math.floor(sortedEntries.length * 0.9)]!)}  (n=${end.length})`,
    );
    outln(`  ou seja, o meio de ano levanta o preço justo em ${pc(1 / median(end)! - 1)} na mediana`);
  }

  // O teto de retenção é o único contrafactual que pode DERRUBAR o valor: sem
  // ele a retenção passa de 100% e o fluxo do ano fica negativo.
  const uncapped = l.filter((e) => e.mSemTeto !== null && e.mSemTeto < 0.995).sort((a, b) => compareNum(a.mSemTeto!, b.mSemTeto!));
  outln('\n-- quem o teto de 95% está segurando --');
  outln(`  ativos que perdem valor sem o teto: ${uncapped.length}`);
  for (const e of uncapped.slice(0, 10)) {
    outln(
      `    ${e.ticker.padEnd(7)} m=${mx(e.mSemTeto!).padStart(7)}  retenção ano 1=${pc(e.retencaoAno1 ?? Number.NaN)}  ` +
        `ROIC=${pc(e.retornoDaBase)}  g=${pc(e.crescimento)}`,
    );
  }

  const taxRateColumn = col('aliquotaEstrutural');
  if (taxRateColumn.length > 0) {
    outln('\n-- alíquota estrutural aplicada (via da firma) --');
    outln(`  mediana=${pc(median(taxRateColumn)!)} contra ${pc(ValuationParameters.statutoryTaxRate)} estatutários  (n=${taxRateColumn.length})`);
  }
}
