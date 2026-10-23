// O prêmio de risco medido do Ibovespa, no lugar dos 5,5% fixos — medição, sem
// ligar nada no motor.
//
// **A pergunta.** O orientador perguntou se o prêmio de mercado pode ser
// capturado em vez de fixado. A forma mais direta é a histórica: o que o
// Ibovespa rendeu acima do CDI na mesma janela,
//
//     prêmio = (1 + CAGR do Ibovespa) ÷ (1 + CAGR do CDI) − 1
//
// com as duas pontas como as âncoras de mercado do aplicativo já as medem
// (`ResolveMarketAnchors`: o índice entre médias de 63 pregões nas pontas, o
// CDI composto). A decisão 116 mediu isso numa janela e o recusou por ruído;
// esta ferramenta mede o que faltava para decidir: quanto o prêmio muda com a
// janela, quanto ele muda de uma data para outra, e o que cada um faz ao preço
// justo, à cobertura e à ordenação.
//
// **Duas partes.**
//
//   1. Sobre a entrada congelada de 14/09/2026: o prêmio com janelas de 5, 10,
//      15 e 20 anos, e o universo reavaliado com cada um contra os 5,5%.
//   2. Nas datas das coortes trimestrais: o prêmio de cada data, só com dado
//      até ela, com janelas de 5 e 10 anos. O backtest com esse prêmio é
//      `npm run tool -- backtest-valuation --premio-historico 10 --saida <arq>`.
//
// O índice antes de 23/09/2016 vem do SGS 7 do Banco Central
// (`tool/ibovespa_sgs_baixar.py`), emendado à fonte de mercado — ver
// `tool/validation/long-ibovespa.ts`.
//
//   python tool/ibovespa_sgs_baixar.py
//   npm run tool -- historical-premium   # grava premio_historico.json
import {
  CapmInputs,
  compareStr,
  DateRange,
  DateTime,
  type MacroRepository,
  ResolveMarketAnchors,
  type Ticker,
  ValuationCascade,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';
import { LongIbovespa, premiumOfAnchors } from './validation/long-ibovespa';
import { Regression } from './validation/regression';

const output = 'docs/validacao/premio_historico.json';
const windows = [5, 10, 15, 20];
const cohortWindows = [5, 10];
const reference = CapmInputs.defaultMarketPremium;
const cases = ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3'];

const pct = (v: number, decimals = 2): string => `${(v * 100).toFixed(decimals)}%`;

function median(v: readonly number[]): number {
  const o = [...v].sort((a, b) => a - b);
  if (o.length === 0) return Number.NaN;
  const m = Math.floor(o.length / 2);
  return o.length % 2 === 1 ? o[m]! : (o[m - 1]! + o[m]!) / 2;
}

interface Measure {
  fim: string;
  anos: number;
  ibovespa: number;
  cdi: number;
  premio: number;
  erroPadrao: number | null;
  completa: boolean;
}

/** O prêmio de uma janela terminada em [end], com a barra de erro. */
async function measure(args: { macro: MacroRepository; index: LongIbovespa; end: DateTime; years: number }): Promise<Measure> {
  const { macro, index, end, years } = args;
  const window = new DateRange(DateTime.local(end.year - years, end.month, end.day), end);
  const anchors = (await ResolveMarketAnchors.call({ macro, benchmark: index, asOf: end, windowYears: years })).unwrap();
  // O CDI da janela precisa estar inteiro: sem ele, as âncoras recuam para o
  // valor de 2026 e o prêmio mediria outra coisa.
  const cdi = (await macro.riskFreeDaily(window)).unwrap();
  const cdiComplete = cdi.points.length > 0 && Math.abs(cdi.points[0]!.date.difference(window.start).inDays) <= 10;
  const points = (await index.ibovespa(window)).unwrap().points;
  const indexComplete = points.length > 0 && Math.abs(points[0]!.date.difference(window.start).inDays) <= 10;

  // Erro-padrão da média de um prêmio: `σ ÷ √T`, com a volatilidade anual dos
  // retornos diários do índice e `T` em anos. É a conta que diz quanto a
  // janela sabe.
  const returns: number[] = [];
  for (let i = 1; i < points.length; i++) {
    if (points[i - 1]!.close > 0) returns.push(points[i]!.close / points[i - 1]!.close - 1);
  }
  let error: number | null = null;
  if (returns.length > 1) {
    const mean = returns.reduce((a, b) => a + b) / returns.length;
    const variance = returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / (returns.length - 1);
    error = (Math.sqrt(variance) * Math.sqrt(252.0)) / Math.sqrt(years);
  }
  return {
    fim: end.toIso8601String().substring(0, 10),
    anos: years,
    ibovespa: anchors.marketCagr,
    cdi: anchors.riskFreeCagr,
    premio: premiumOfAnchors(anchors),
    erroPadrao: error,
    completa: cdiComplete && indexComplete,
  };
}

/**
 * As datas das coortes trimestrais do backtest: o último dia de cada
 * trimestre, de 31/03/2018 a 30/09/2025.
 */
function cohortDates(): DateTime[] {
  const out: DateTime[] = [];
  for (let year = 2018; year <= 2025; year++) {
    for (const month of [3, 6, 9, 12]) {
      if (!(year === 2025 && month === 12)) out.push(DateTime.local(year, month + 1, 0));
    }
  }
  return out;
}

class Reading {
  readonly fairValue = new Map<string, number>();
  readonly upside = new Map<string, number>();
  constructor(
    readonly label: string,
    readonly premium: number,
  ) {}
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const today = frozenToday;
    const index = await LongIbovespa.build(c.ctx.benchmark, new DateRange(DateTime.local(today.year - 10, today.month, today.day), today));
    outln(
      `-- Ibovespa emendado: SGS 7 até ${index.sourceStart.toIso8601String().substring(0, 10)}, fonte de ` +
        `mercado depois; razão mediana na sobreposição ${index.overlapRatio.toFixed(6)} --`,
    );

    // -------------------------------------------------------------------
    // 1) Sobre a entrada congelada
    // -------------------------------------------------------------------
    const fromApp = premiumOfAnchors(c.anchors);
    outln('');
    outln('-- o prêmio histórico em 14/09/2026, por janela --');
    outln(
      `  o do aplicativo (âncoras congeladas, dez anos): ${pct(fromApp)} = (1 + ${pct(c.anchors.marketCagr)}) ÷ ` +
        `(1 + ${pct(c.anchors.riskFreeCagr)}) − 1`,
    );
    const byWindow: Measure[] = [];
    for (const years of windows) {
      const m = await measure({ macro: c.ctx.macro, index, end: today, years });
      byWindow.push(m);
      const e = m.erroPadrao;
      const p = m.premio;
      outln(
        `  ${String(years).padStart(2)} anos   Ibovespa ${pct(m.ibovespa)}   CDI ${pct(m.cdi)}   ` +
          `prêmio ${pct(p)}   erro-padrão ${e === null ? '—' : pct(e)}   ` +
          `95%: ${e === null ? '—' : `${pct(p - 1.96 * e)} a ${pct(p + 1.96 * e)}`}` +
          (m.completa ? '' : '   (JANELA INCOMPLETA)'),
      );
    }

    // O universo reavaliado com cada prêmio.
    const candidates: [string, number][] = [['5,5% fixo', reference], ...byWindow.map((m): [string, number] => [`${m.anos} anos`, m.premio])];
    const readings: Reading[] = [];
    for (const [index_, [label, premium]] of candidates.entries()) {
      const l = new Reading(label, premium);
      const evaluated = new Map<Ticker, ValuationResult | null>();
      let i = 0;
      for (const t of c.universe) {
        i++;
        if (i % 50 === 0) process.stderr.write(`  ${label}: ${i}/${c.universe.length}   \r`);
        const prep = await c.prepare(t, { premium });
        if (prep.isErr) continue;
        const r = ValuationCascade.evaluate(prep.unwrap());
        if (index_ === 0) evaluated.set(t, r.valueOrNull);
        if (r.isErr) continue;
        l.fairValue.set(t.value, r.unwrap().fairValue.cents);
        l.upside.set(t.value, r.unwrap().upside);
      }
      if (index_ === 0) {
        const div = await c.checkAgainstAnswerKey(evaluated);
        if (div === null) {
          errln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (div.length > 0) {
          errln(`ERRO: a montagem de 5,5% diverge do gabarito em ${div.length}: ${div.slice(0, 8).join(', ')}`);
          process.exitCode = 1;
          return;
        }
      }
      readings.push(l);
    }
    process.stderr.write('                                        \r');

    const base = readings[0]!;
    const effects: Record<string, unknown>[] = [];
    outln('');
    outln('-- o universo reavaliado --');
    outln('  prêmio              avaliados   potencial mediano   acima de zero   preço justo vs 5,5%   postos');
    for (const l of readings) {
      const upsideValues = [...l.upside.values()];
      const common = [...l.fairValue.keys()].filter((k) => base.fairValue.has(k)).sort(compareStr);
      const changeList = common.filter((k) => base.fairValue.get(k)! !== 0).map((k) => l.fairValue.get(k)! / base.fairValue.get(k)! - 1);
      const rho =
        common.length < 3
          ? null
          : Regression.spearman(
              common.map((k) => base.upside.get(k)!),
              common.map((k) => l.upside.get(k)!),
            );
      const above = upsideValues.filter((p) => p > 0).length;
      const medianUpside = median(upsideValues);
      const medVar = changeList.length === 0 ? null : median(changeList);
      outln(
        `  ${`${l.label} (${pct(l.premium)})`.padEnd(20)}${String(l.fairValue.size).padStart(9)}   ` +
          `${pct(medianUpside).padStart(17)}   ${`${above} de ${upsideValues.length}`.padStart(13)}   ` +
          `${(medVar === null ? '—' : pct(medVar)).padStart(19)}   ${rho === null ? '—' : rho.toFixed(3)}`,
      );
      effects.push({
        rotulo: l.label,
        premio: l.premium,
        avaliados: l.fairValue.size,
        potencialMediano: medianUpside,
        acimaDeZero: above,
        precoJustoMedianoContraReferencia: medVar,
        spearmanContraReferencia: rho,
        casos: Object.fromEntries(
          cases.map((t) => [t, { justoCentavos: l.fairValue.get(t) ?? null, potencial: l.upside.get(t) ?? null }]),
        ),
      });
    }

    // -------------------------------------------------------------------
    // 2) O prêmio em cada data de coorte
    // -------------------------------------------------------------------
    outln('');
    outln('-- o prêmio histórico em cada data de coorte --');
    outln('  data          5 anos (erro)         10 anos (erro)');
    const byCohort: Record<string, unknown>[] = [];
    const p5: number[] = [];
    const p10: number[] = [];
    for (const t of cohortDates()) {
      const row: Record<string, unknown> = { data: t.toIso8601String().substring(0, 10) };
      const parts: string[] = [];
      for (const years of cohortWindows) {
        const m = await measure({ macro: c.ctx.macro, index, end: t, years });
        row[`janela${years}`] = m;
        if (years === 5) p5.push(m.premio);
        if (years === 10) p10.push(m.premio);
        const e = m.erroPadrao;
        parts.push(`${pct(m.premio).padStart(7)} (${e === null ? '—' : pct(e, 1)})${m.completa ? '' : '*'}`);
      }
      byCohort.push(row);
      outln(`  ${String(row['data'])}    ${parts.join('      ')}`);
    }
    outln(
      `  10 anos: de ${pct(Math.min(...p10))} a ${pct(Math.max(...p10))}, mediana ${pct(median(p10))}; ` +
        `negativos: ${p10.filter((p) => p <= 0).length} de ${p10.length}`,
    );
    outln(
      `   5 anos: de ${pct(Math.min(...p5))} a ${pct(Math.max(...p5))}, mediana ${pct(median(p5))}; ` +
        `negativos: ${p5.filter((p) => p <= 0).length} de ${p5.length}`,
    );

    writeText(
      output,
      jsonPretty(
        {
          geradoPor: 'tool/historical-premium.ts',
          dataDaEntrada: today.toIso8601String().substring(0, 10),
          emenda: {
            inicioDaFonteDeMercado: index.sourceStart.toIso8601String().substring(0, 10),
            razaoMedianaNaSobreposicao: index.overlapRatio,
          },
          premioDoAplicativoDezAnos: fromApp,
          porJanela: byWindow,
          efeitos: effects,
          porCoorte: byCohort,
        },
        ' ',
      ),
    );
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}
