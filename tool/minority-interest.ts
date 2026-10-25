// Item B23 — o minoritário nos pesos do custo médio de capital.
//
// **A acusação da lente `metodo`.** O fluxo que o WACC desconta é o
// **consolidado**, e o peso do capital próprio é `divisor × preço`, que é o
// valor de mercado da **controladora**. A fatia dos não controladores fica fora
// do denominador `E + D`, o que infla a participação da dívida e achata o WACC.
//
// **A primeira coisa que a medição precisa estabelecer é o escopo**, e ele é
// menor do que a acusação sugere: o caminho **resolvido** pondera pelo capital
// próprio que o modelo produz — `V − D` sobre um fluxo consolidado —, que já
// inclui o minoritário. Só o WACC **estático**, que é o recuo, fica de fora.
//
// **Duas formas de introduzi-lo, e a ferramenta mede as duas:**
//
//   (a) **contábil puro** — soma `minorityInterest` ao `E` de mercado, e o
//       denominador passa a ter duas unidades.
//   (b) **pelo `P/VP` do controlador** — supõe que o minoritário negocia à
//       mesma razão preço/patrimônio que o controlador, e soma
//       `PL_min × (E_mercado ÷ PL_contr)`. Não mistura unidades.
//
//   npm run tool -- cascade-golden      # congela a entrada
//   npm run tool -- minority-interest   # grava minoritario.json
import {
  compareNum,
  compareStr,
  type Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { truncatedMedian as median, truncatedQuantile as q } from './lib/stats';
import { Frozen } from './validation/frozen';
import { Regression } from './validation/regression';

const output = 'docs/validacao/minoritario.json';

/**
 * Fração do patrimônio consolidado a partir da qual o minoritário é
 * **material**. Abaixo de 1% qualquer tratamento dele muda o terceiro decimal
 * da taxa, e a pergunta não é sobre esses.
 */
const materiality = 0.01;

/**
 * As três formas medidas. A chave é a gravada nas saídas — é dado, e não nome
 * de código: renomear a forma não a muda.
 */
type Form = 'today' | 'book' | 'byRatio';
const forms: readonly Form[] = ['today', 'book', 'byRatio'];
const formKey: Record<Form, string> = { today: 'hoje', book: 'contabil', byRatio: 'pelaRazao' };

class Reading {
  readonly fairValueCents = new Map<string, number>();
  readonly upside = new Map<string, number>();
  readonly discount = new Map<string, number>();
}

const max = (v: readonly number[]): number => v.reduce((a, b) => (a > b ? a : b));

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const slice = new Map<string, number>();
    const staticSet = new Set<string>();
    const firmLane = new Set<string>();
    const readings = new Map<Form, Reading>(forms.map((f) => [f, new Reading()]));
    const evaluated = new Map<Ticker, ValuationResult | null>();

    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const b = prep.unwrap();
      if (b.fundamentals.length === 0) continue;
      const f = b.fundamentals[b.fundamentals.length - 1]!;

      const controllingEquity = f.totalStockholderEquity;
      const minority = f.minorityInterest;
      const consolidated = (controllingEquity ?? 0) + (minority ?? 0);
      const ratio =
        minority === null || minority <= 0 || controllingEquity === null || controllingEquity <= 0 || consolidated <= 0
          ? null
          : minority / consolidated;

      for (const form of forms) {
        const r = ValuationCascade.evaluate(withInput(b, form, minority, controllingEquity));
        if (form === 'today') evaluated.set(t, r.valueOrNull);
        if (r.isErr) continue;
        const v = r.unwrap();
        const reading = readings.get(form)!;
        reading.fairValueCents.set(t.value, v.fairValue.cents);
        reading.upside.set(t.value, v.upside);
        reading.discount.set(t.value, v.discountRate);
        // **Quem usa o WACC estático é quem não resolveu as taxas**, e é só
        // nele que o peso do minoritário falta. O aviso da avaliação é o que
        // separa os dois caminhos sem reimplementar a cascata.
        if (form === 'today') {
          if (!v.warnings.some((w) => w.includes('resolvido ano a ano'))) staticSet.add(t.value);
          // **E a via do acionista não tem WACC nenhum**: o fluxo dela é do
          // acionista da controladora, descontado ao `Ke`, e o minoritário não
          // entra em peso porque não há peso. Sem este corte, a contagem de
          // expostos junta banco com companhia operacional.
          if (v.model === ValuationModel.dcfFcff) firmLane.add(t.value);
        }
      }
      if (ratio !== null && readings.get('today')!.fairValueCents.has(t.value)) slice.set(t.value, ratio);
    }
    process.stderr.write('                              \r');

    const div = await c.checkAgainstAnswerKey(evaluated);
    if (div === null) {
      errln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.length > 0) {
      errln(`ERRO: a montagem de hoje diverge do gabarito em ${div.length}: ${div.slice(0, 8).join(', ')}`);
      process.exitCode = 1;
      return;
    } else {
      outln('montagem de hoje conferida contra o gabarito: zero divergências.');
    }

    const base = readings.get('today')!;
    const material = [...slice].filter(([, v]) => v >= materiality).map(([k]) => k);
    // **O conjunto exposto é a interseção das três condições**: via da firma
    // (tem WACC), recuo estático (o peso é de mercado da controladora) e
    // minoritário material.
    const exposed = new Set(material.filter((k) => staticSet.has(k)).filter((k) => firmLane.has(k)));

    outln('');
    outln('-- o escopo do defeito --');
    outln(`  avaliados                          ${base.fairValueCents.size}`);
    outln(`  pela via da firma (têm WACC)       ${firmLane.size}`);
    outln(`  usam o WACC estático               ${staticSet.size}`);
    outln(`  via da firma E estático            ${[...firmLane].filter((k) => staticSet.has(k)).length}`);
    outln(`  têm minoritário publicado          ${slice.size}`);
    outln(`  com fatia ≥ ${(materiality * 100).toFixed(0)}%                     ${material.length}`);
    outln(`  **firma, estático E material**     ${exposed.size}${exposed.size === 0 ? '' : `  (${[...exposed].slice(0, 10).join(', ')})`}`);
    const slices = [...slice.values()];
    if (slices.length > 0) {
      outln(`  fatia do minoritário: p50 ${pct(median(slices))}  p90 ${pct(q(slices, 0.9))}  máx ${pct(max(slices))}`);
    }

    const rows: Record<string, unknown>[] = [];
    outln('');
    outln('-- o efeito de pôr o minoritário no peso --');
    outln('  forma         avaliados   justo (todos)   justo (expostos)   Δ desconto (expostos)   postos');

    for (const form of forms) {
      if (form === 'today') continue;
      const l = readings.get(form)!;
      const common = [...l.fairValueCents.keys()].filter((k) => base.fairValueCents.has(k)).sort(compareStr);
      const varianceOf = (keys: Iterable<string>): number | null => {
        const v: number[] = [];
        for (const k of keys) {
          const b = base.fairValueCents.get(k);
          const x = l.fairValueCents.get(k);
          if (b !== undefined && b !== 0 && x !== undefined) v.push(x / b - 1);
        }
        return v.length === 0 ? null : median(v);
      };

      const discountDelta = common.filter((k) => exposed.has(k)).map((k) => l.discount.get(k)! - base.discount.get(k)!);
      const rho =
        common.length < 3
          ? null
          : Regression.spearman(
              common.map((k) => base.upside.get(k)!),
              common.map((k) => l.upside.get(k)!),
            );
      const leaving = [...base.fairValueCents.keys()].filter((k) => !l.fairValueCents.has(k)).sort(compareStr);

      outln(
        `  ${formKey[form].padEnd(12)}  ${String(l.fairValueCents.size).padStart(9)}   ` +
          `${pct(varianceOf(common) ?? Number.NaN).padStart(13)}   ` +
          `${pct(varianceOf(exposed) ?? Number.NaN).padStart(16)}   ` +
          `${discountDelta.length === 0 ? '         —      ' : `${(median(discountDelta) * 100).toFixed(2).padStart(13)} p.p.`}   ` +
          (rho === null ? '  —   ' : rho.toFixed(4)),
      );

      rows.push({
        forma: formKey[form],
        avaliados: l.fairValueCents.size,
        justoMedianoTodos: varianceOf(common),
        justoMedianoExpostos: varianceOf(exposed),
        deltaDescontoMedianoExpostos: discountDelta.length === 0 ? null : median(discountDelta),
        spearmanPotencial: rho,
        saem: leaving,
      });
    }

    writeText(
      output,
      jsonPretty(
        {
          materialidade: materiality,
          avaliados: base.fairValueCents.size,
          usamWaccEstatico: staticSet.size,
          viaDaFirma: firmLane.size,
          viaDaFirmaEEstatico: [...firmLane].filter((k) => staticSet.has(k)).sort(compareStr),
          comMinoritario: slice.size,
          comFatiaMaterial: material.length,
          estaticoEMaterial: [...exposed].sort(compareStr),
          fatia: {
            p50: slices.length === 0 ? null : median(slices),
            p90: slices.length === 0 ? null : q(slices, 0.9),
            maximo: slices.length === 0 ? null : max(slices),
          },
          maioresFatias: Object.fromEntries([...slice].sort((a, b) => compareNum(b[1], a[1])).slice(0, 15)),
          formas: rows,
        },
        '  ',
      ),
    );
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}

/** Os mesmos insumos, com o minoritário somado ao peso do capital próprio. */
function withInput(b: ValuationInputs, form: Form, minority: number | null, controllingEquity: number | null): ValuationInputs {
  if (form === 'today') return b;
  if (minority === null || minority <= 0) return b;
  if (controllingEquity === null || controllingEquity <= 0) return b;

  // O valor de mercado da controladora, pela mesma contagem que a ponte
  // arbitra — é o que está no denominador hoje.
  const divisor = ValuationCascade.quotedShares({
    latest: b.fundamentals[b.fundamentals.length - 1]!,
    marketPrice: b.marketPrice,
    sharesPerQuote: b.declaredSharesPerUnit ?? 1.0,
    published: b.fundamentals,
    official: b.officialShares,
    asOf: b.asOf,
  });
  if (divisor === null || divisor.count <= 0) return b;
  const market = divisor.count * b.marketPrice;

  // Contábil puro: o valor de livro entra num denominador de mercado.
  // Pelo `P/VP` do controlador: `PL_min × (E_mercado ÷ PL_contr)`. Coincide
  // com a contábil quando o `P/VP` é 1, e difere dela exatamente por ele.
  const value = form === 'book' ? minority : minority * (market / controllingEquity);

  return new ValuationInputs({
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: b.capm,
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
    riskFreeCurve: b.riskFreeCurve,
    officialShares: b.officialShares,
    prices: b.prices,
    isDistressed: b.isDistressed,
    unleveredBeta: b.unleveredBeta,
    concessionEnd: b.concessionEnd,
    dividendsInBeta: b.dividendsInBeta,
    creditReferenceRiskFree: b.creditReferenceRiskFree,
    declaredSharesPerUnit: b.declaredSharesPerUnit,
    betaWindowYears: b.betaWindowYears,
    minorityEquityValue: value,
  });
}

const pct = (v: number): string => (Number.isNaN(v) ? '   —  ' : `${(v * 100).toFixed(2)}%`);
