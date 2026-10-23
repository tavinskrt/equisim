// Item B20 — a tradução do cenário de desconto para o `Ke` da rota derivada.
//
// **A pergunta.** O cenário perturba `DcfAssumptions.discountRate`. Na via do
// acionista esse campo **é** o `Ke`, e o deslocamento é um a um por construção.
// Na via da firma ele é o WACC, e a rota derivada desconta ao `Ke`: traduzir
// exige escolher o que o cenário está perturbando, e ele não diz.
//
// **As três leituras, e o fator de cada uma:**
//
//   um a um          `ΔK_e = ΔWACC`                 — a taxa aplicada ao fluxo
//   estrutura fixa   `ΔK_e = ΔWACC ÷ w_E`           — o custo de capital da firma
//   taxa livre       `ΔK_e = ΔWACC ÷ (1 − w_D·t)`   — o `R_f`, movendo os dois
//
// **O que esta ferramenta mede** é a largura da faixa de sensibilidade sob cada
// uma, no universo, e se o preço justo do cenário **base** volta ao preço justo
// — que é a pós-condição que a decisão 105 fixou e que nenhuma tradução pode
// quebrar.
//
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- scenario         # grava cenario.json
import {
  compareStr,
  ScenarioBand,
  ScenarioTranslation,
  type Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { pctColumn as pct, truncatedMedian as median, truncatedQuantile as q } from './lib/stats';
import { Frozen } from './validation/frozen';

const output = 'docs/validacao/cenario.json';

class Reading {
  readonly fairValueCents = new Map<string, number>();
  readonly width = new Map<string, number>();
  readonly asymmetry = new Map<string, number>();
  baseOutsideFair = 0;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const readings = new Map<ScenarioTranslation, Reading>(ScenarioTranslation.values.map((t) => [t, new Reading()]));
    const evaluated = new Map<Ticker, ValuationResult | null>();
    const onFirmLane = new Set<string>();

    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const b = prep.unwrap();

      for (const reading of ScenarioTranslation.values) {
        const r = ValuationCascade.evaluate(withInput(b, reading));
        if (reading === ScenarioTranslation.oneToOne) evaluated.set(t, r.valueOrNull);
        if (r.isErr) continue;
        const v = r.unwrap();
        const l = readings.get(reading)!;
        l.fairValueCents.set(t.value, v.fairValue.cents);
        if (reading === ScenarioTranslation.oneToOne && v.model === ValuationModel.dcfFcff) onFirmLane.add(t.value);

        const scenarios = v.discreteScenarios;
        const fairValue = v.fairValue.cents;
        if (scenarios === null || fairValue <= 0) continue;
        const bear = scenarios.get(ScenarioBand.bear)?.cents;
        const baseC = scenarios.get(ScenarioBand.base)?.cents;
        const bull = scenarios.get(ScenarioBand.bull)?.cents;
        if (bear === undefined || baseC === undefined || bull === undefined) continue;
        // **A pós-condição da decisão 105**: o cenário base é o preço justo.
        // Nenhuma tradução pode quebrá-la — se quebrar, a faixa cerca outro
        // número, e a medição de largura não quer dizer nada.
        if (baseC !== fairValue) l.baseOutsideFair++;
        l.width.set(t.value, (bull - bear) / fairValue);
        // Quanto da faixa fica de cada lado do preço justo. Tradução que só
        // multiplica o deslocamento não pode mover isto muito — se mover, o
        // efeito não é de escala.
        //
        // **Faixa de um lado só não tem assimetria a medir**: com o cenário
        // pessimista no próprio preço justo o denominador é zero, e a divisão
        // devolveria `Infinity`, que a mediana contamina. O ativo sai da conta
        // em vez de entrar com um número inventado.
        const below = fairValue - bear;
        if (below > 0) l.asymmetry.set(t.value, (bull - fairValue) / below);
      }
    }
    process.stderr.write('                              \r');

    const div = await c.checkAgainstAnswerKey(evaluated);
    if (div === null) {
      errln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.length > 0) {
      errln(`ERRO: a leitura de hoje diverge do gabarito em ${div.length}: ${div.slice(0, 8).join(', ')}`);
      process.exitCode = 1;
      return;
    } else {
      outln('leitura de hoje conferida contra o gabarito: zero divergências.');
    }

    const base = readings.get(ScenarioTranslation.oneToOne)!;
    const rows: Record<string, unknown>[] = [];

    outln('');
    outln('-- a largura da faixa sob cada leitura --');
    outln('  leitura             com faixa   largura (p25/med/p75)        vs um a um   base ≠ justo   preço justo muda');

    for (const reading of ScenarioTranslation.values) {
      const l = readings.get(reading)!;
      // **Só a via da firma importa**: na do acionista o campo perturbado já é
      // o `Ke`, e as três leituras devolvem o mesmo número.
      const keys = [...l.width.keys()].filter((k) => onFirmLane.has(k)).sort(compareStr);
      const widths = keys.map((k) => l.width.get(k)!);
      const ratio = keys
        .filter((k) => base.width.get(k) !== undefined && base.width.get(k)! > 0)
        .map((k) => l.width.get(k)! / base.width.get(k)!);
      const changing = keys.filter(
        (k) => base.fairValueCents.get(k) !== undefined && l.fairValueCents.get(k) !== base.fairValueCents.get(k),
      ).length;

      const vsOneToOne = ratio.length === 0 ? '   —  ' : `${median(ratio).toFixed(3)}×`;
      outln(
        `  ${reading.key.padEnd(18)}  ${String(keys.length).padStart(9)}   ` +
          `${pct(q(widths, 0.25))} / ${pct(median(widths))} / ${pct(q(widths, 0.75))}   ` +
          `${vsOneToOne.padStart(12)}   ${String(l.baseOutsideFair).padStart(12)}   ${String(changing).padStart(16)}`,
      );

      // `q` devolve `NaN` sobre lista vazia, e `NaN` não é JSON: onde não há
      // largura a declarar, o campo é `null`.
      const orNull = (v: number): number | null => (Number.isFinite(v) ? v : null);
      // Só quem tem assimetria medida entra na mediana dela — e o `null` diz
      // que nenhum tinha, em vez de um `NaN` que o JSON não carrega.
      const asymmetries = keys.filter((k) => l.asymmetry.has(k)).map((k) => l.asymmetry.get(k)!);

      rows.push({
        leitura: reading.key,
        comFaixa: keys.length,
        larguraP25: orNull(q(widths, 0.25)),
        larguraMediana: orNull(median(widths)),
        larguraP75: orNull(q(widths, 0.75)),
        razaoMedianaContraUmPorUm: ratio.length === 0 ? null : median(ratio),
        baseForaDoJusto: l.baseOutsideFair,
        precoJustoMuda: changing,
        assimetriaMediana: asymmetries.length === 0 ? null : median(asymmetries),
        // Quem tinha faixa no um a um e perde com esta leitura: amplificar o
        // deslocamento empurra o cenário otimista para uma perpetuidade que
        // diverge, e o ativo fica sem faixa.
        perdemAFaixa: [...onFirmLane].filter((k) => base.width.has(k) && !l.width.has(k)).sort(compareStr),
      });
    }

    writeText(output, jsonPretty({ naViaDaFirma: onFirmLane.size, leituras: rows }, '  '));
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}

/**
 * A mesma entrada com outra leitura do cenário. Reconstrói só os campos que a
 * medição original carregava, como ela fazia — os demais voltam ao padrão.
 */
const withInput = (b: ValuationInputs, reading: ScenarioTranslation): ValuationInputs =>
  new ValuationInputs({
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
    scenarioTranslation: reading,
  });
