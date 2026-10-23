// O crescimento fundamental `g = ROE × (1 − payout)`, e o do PIB do setor para
// quem cresce sem reter — medição, sem ligar nada no motor.
//
// **A pergunta.** O motor tira o `g` da mediana das variações anuais da base
// de capital — o patrimônio na via do acionista, o capital investido na da
// firma (decisão 25). Pela identidade do lucro limpo, `Δpatrimônio = lucro ×
// retenção` quando não entra nem sai capital, e a variação da base **é** o
// `ROE × retenção` realizado ano a ano. A proposta do orientador é a versão
// que olha para a frente: o ROE normalizado vezes a retenção que o payout
// observado implica; e, para quem cresce sem precisar reter — as de pouco
// capital e as que distribuem quase tudo —, o crescimento nominal do setor.
//
// **As regras, fixadas antes de medir.**
//
//     ROE normalizado = mediana dos últimos 8 retornos sobre o patrimônio de
//                       abertura, com o do último exercício (≥ 4)
//     payout          = dividendos e JCP pagos ÷ lucro líquido, somados nos
//                       últimos 5 exercícios (≥ 3), do fluxo de caixa da DFP
//     g fundamental   = ROE normalizado × (1 − payout), retenção em [0; 1]
//
//     regra combinada:
//       commodity (a lista de precedência do ciclo do motor) → g = inflação
//       payout ≥ 75% ou receita ÷ capital investido ≥ 2      → g = PIB nominal
//                                                              do setor, 10 anos
//       o resto                                               → g fundamental
//
// Para commodity a proposta é crescimento real zero sobre a base normalizada
// pelo ciclo: preço real de commodity não tem tendência positiva de longo
// prazo, e o motor já põe a base no meio do ciclo. A variante que cresce pelo
// reinvestimento ao retorno do ciclo é a do `g` fundamental, medida ao lado.
//
// **Duas medições.**
//
// 1. Na entrada congelada, o universo reavaliado com cada `g`, imposto pelo
//    ponto de diagnóstico do motor (`withOverrides({ growth })`): o decaimento
//    até `g∞`, o teto da economia e o freio `g ≤ 0,95 × ROIC` continuam.
// 2. No histórico: em cada exercício de 2014 a 2022, o `g` que cada regra
//    daria com os dados até ele, contra o crescimento que aconteceu nos três
//    exercícios seguintes. É a régua de «projeção real».
//
//   python tool/cvm/dividendos_pagos.py              # data/cvm/dividendos_pagos.json
//   python tool/pib_setorial_baixar.py               # data/indices/pib_setorial.json
//   npm run tool -- fundamental-growth               # grava crescimento_fundamental.json
import { existsSync } from 'node:fs';

import {
  CapitalSeries,
  compareNum,
  compareStr,
  CyclicalSectors,
  DateRange,
  DateTime,
  Duration,
  type FundamentalsSnapshot,
  GrowthEstimator,
  GrowthGuards,
  Inference,
  ResolveMarketAnchors,
  type Result,
  round,
  type Ticker,
  ValuationCascade,
  ValuationLane,
  ValuationModel,
  ValuationParameters,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';
import { LongIbovespa } from './validation/long-ibovespa';
import { Regression } from './validation/regression';

const output = 'docs/validacao/crescimento_fundamental.json';

/** Payout a partir do qual a companhia é alta pagadora. */
const highPayout = 0.75;

/** Receita ÷ capital investido a partir da qual o negócio é de pouco capital. */
const salesToCapital = 2.0;

/** Exercícios somados no payout, e o mínimo presente. */
const payoutYears = 5;
const minPayoutYears = 3;

/** Retornos na mediana do ROE normalizado, e o mínimo. */
const roeWindow = 8;
const minRoeYears = 4;

/** Anos do crescimento do setor. */
const sectorYears = 10;

/** Dias entre o fim do trimestre e a publicação das Contas Nacionais. */
const gdpLag = 70;

/** Exercícios do crescimento realizado. */
const realizedYears = 3;

/** A atividade do IBGE de cada setor e subsetor da B3, fixada antes de medir. */
const activityBySector: ReadonlyMap<string, string> = new Map([
  ['Bens Industriais|Comércio', 'Comércio'],
  ['Bens Industriais|Construção e Engenharia', 'Construção'],
  ['Bens Industriais|Material de Transporte', 'Indústrias de transformação'],
  ['Bens Industriais|Máquinas e Equipamentos', 'Indústrias de transformação'],
  ['Bens Industriais|Serviços', 'Outras atividades de serviços'],
  ['Bens Industriais|Transporte', 'Transporte, armazenagem e correio'],
  ['Comunicações|Telecomunicações', 'Informação e comunicação'],
  ['Consumo Cíclico|Automóveis e Motocicletas', 'Indústrias de transformação'],
  ['Consumo Cíclico|Comércio', 'Comércio'],
  ['Consumo Cíclico|Construção Civil', 'Construção'],
  ['Consumo Cíclico|Diversos', 'Outras atividades de serviços'],
  ['Consumo Cíclico|Hoteis e Restaurantes', 'Outras atividades de serviços'],
  ['Consumo Cíclico|Tecidos. Vestuário e Calçados', 'Indústrias de transformação'],
  ['Consumo Cíclico|Utilidades Domésticas', 'Indústrias de transformação'],
  ['Consumo Cíclico|Viagens e Lazer', 'Outras atividades de serviços'],
  ['Consumo não Cíclico|Agropecuária', 'Agropecuária - total'],
  ['Consumo não Cíclico|Alimentos Processados', 'Indústrias de transformação'],
  ['Consumo não Cíclico|Bebidas', 'Indústrias de transformação'],
  ['Consumo não Cíclico|Comércio e Distribuição', 'Comércio'],
  ['Consumo não Cíclico|Produtos de Uso Pessoal e de Limpeza', 'Indústrias de transformação'],
  ['Financeiro|Exploração de Imóveis', 'Atividades imobiliárias'],
  ['Financeiro|Holdings Diversificadas', 'Atividades financeiras, de seguros e serviços relacionados'],
  ['Financeiro|Intermediários Financeiros', 'Atividades financeiras, de seguros e serviços relacionados'],
  ['Financeiro|Previdência e Seguros', 'Atividades financeiras, de seguros e serviços relacionados'],
  ['Financeiro|Serviços Diversos', 'Atividades financeiras, de seguros e serviços relacionados'],
  ['Financeiro|Serviços Financeiros Diversos', 'Atividades financeiras, de seguros e serviços relacionados'],
  ['Materiais Básicos|Embalagens', 'Indústrias de transformação'],
  ['Materiais Básicos|Madeira e Papel', 'Indústrias de transformação'],
  ['Materiais Básicos|Materiais Diversos', 'Indústrias de transformação'],
  ['Materiais Básicos|Mineração', 'Indústrias extrativas'],
  ['Materiais Básicos|Químicos', 'Indústrias de transformação'],
  ['Materiais Básicos|Siderurgia e Metalurgia', 'Indústrias de transformação'],
  ['Petróleo. Gás e Biocombustíveis|Petróleo. Gás e Biocombustíveis', 'Indústrias extrativas'],
  ['Saúde|Comércio e Distribuição', 'Comércio'],
  ['Saúde|Equipamentos', 'Indústrias de transformação'],
  ['Saúde|Medicamentos e Outros Produtos', 'Indústrias de transformação'],
  ['Saúde|Serv.Méd.Hospit..Análises e Diagnósticos', 'Outras atividades de serviços'],
  ['Tecnologia da Informação|Computadores e Equipamentos', 'Indústrias de transformação'],
  ['Tecnologia da Informação|Programas e Serviços', 'Informação e comunicação'],
  ['Utilidade Pública|Energia Elétrica', 'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos'],
  ['Utilidade Pública|Gás', 'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos'],
  ['Utilidade Pública|Água e Saneamento', 'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos'],
]);

/** Sem subsetor mapeado, o valor adicionado da economia inteira. */
const economy = 'Valor adicionado a preços básicos';

const pct = (v: number | null | undefined, decimals = 2): string =>
  v === null || v === undefined ? '—' : `${(v * 100).toFixed(decimals)}%`;

const median = (v: readonly number[]): number | null => (v.length === 0 ? null : Inference.median(v));

const present = (v: readonly (number | null | undefined)[]): number[] => v.filter((x): x is number => x !== null && x !== undefined);

// ---------------------------------------------------------------------------
// Fontes
// ---------------------------------------------------------------------------

/**
 * O valor adicionado por atividade, de `tool/pib_setorial_baixar.py`.
 *
 * Cada série é indexada pelo instante do fim do trimestre, em milissegundos:
 * a chave de mapa do JavaScript é por identidade, e duas datas iguais
 * construídas em lugares diferentes não se encontrariam.
 */
class SectorGdp {
  private constructor(private readonly series: Map<string, Map<number, number>>) {}

  static read(): SectorGdp {
    const f = 'data/indices/pib_setorial.json';
    if (!existsSync(f)) throw new Error(`Falta ${f}. Rode antes: python tool/pib_setorial_baixar.py`);
    const j = readJson<{ atividades: Record<string, [string, number][]> }>(f);
    const series = new Map<string, Map<number, number>>();
    for (const [activity, points] of Object.entries(j.atividades)) {
      series.set(activity, new Map(points.map((p) => [SectorGdp.endOfQuarter(p[0]).millisecondsSinceEpoch, p[1]])));
    }
    return new SectorGdp(series);
  }

  /** `201904` é o quarto trimestre de 2019; devolve o último dia dele, em UTC. */
  private static endOfQuarter(code: string): DateTime {
    const year = Number.parseInt(code.substring(0, 4), 10);
    const t = Number.parseInt(code.substring(4), 10);
    return DateTime.utc(year, t * 3 + 1, 0);
  }

  /**
   * Crescimento anual composto das quatro últimas leituras publicadas até
   * [date] contra as mesmas quatro, [years] antes.
   */
  growth(activity: string, date: DateTime, years = sectorYears): number | null {
    const s = this.series.get(activity);
    if (s === undefined) return null;
    const limit = DateTime.utc(date.year, date.month, date.day).subtract(new Duration({ days: gdpLag })).millisecondsSinceEpoch;
    const published = [...s.keys()].filter((d) => d <= limit).sort(compareNum);
    if (published.length < 4) return null;
    const lastOnes = published.slice(published.length - 4);
    let today = 0.0;
    let before = 0.0;
    for (const ms of lastOnes) {
      const d = DateTime.fromMillisecondsSinceEpoch(ms, { isUtc: true });
      const old = DateTime.utc(d.year - years, d.month + 1, 0).millisecondsSinceEpoch;
      const v = s.get(old);
      if (v === undefined) return null;
      today += s.get(ms)!;
      before += v;
    }
    if (!(before > 0) || !(today > 0)) return null;
    return Math.pow(today / before, 1 / years) - 1;
  }
}

/**
 * Dividendos e JCP pagos por CNPJ e exercício, em centavos, de
 * `tool/cvm/dividendos_pagos.py`.
 */
function readDividends(): Map<string, Map<number, number>> {
  const f = 'data/cvm/dividendos_pagos.json';
  if (!existsSync(f)) throw new Error(`Falta ${f}. Rode antes: python tool/cvm/dividendos_pagos.py`);
  const j = readJson<{ companhias: Record<string, Record<string, { pago: number }>> }>(f);
  const out = new Map<string, Map<number, number>>();
  for (const [cnpj, years] of Object.entries(j.companhias)) {
    out.set(cnpj, new Map(Object.entries(years).map(([y, v]) => [Number.parseInt(y, 10), round(v.pago * 100)])));
  }
  return out;
}

// ---------------------------------------------------------------------------
// As grandezas de cada regra, com os dados até o exercício [ano]
// ---------------------------------------------------------------------------

/** Os exercícios até [year], um por ano (o de fim mais tardio). */
function until(fs: readonly FundamentalsSnapshot[], year: number): FundamentalsSnapshot[] {
  const byYear = new Map<number, FundamentalsSnapshot>();
  for (const s of fs) {
    const y = s.fiscalPeriodEnd.year;
    if (y > year) continue;
    const current = byYear.get(y);
    if (current === undefined || s.fiscalPeriodEnd.isAfter(current.fiscalPeriodEnd)) byYear.set(y, s);
  }
  return [...byYear.keys()].sort(compareNum).map((y) => byYear.get(y)!);
}

/** Mediana dos últimos [roeWindow] retornos sobre o patrimônio de abertura. */
function normalizedRoe(upTo: readonly FundamentalsSnapshot[]): number | null {
  const r = CapitalSeries.build(upTo, ValuationLane.shareholder).returns;
  if (r.length < minRoeYears) return null;
  const window = r.slice(Math.max(0, r.length - roeWindow));
  return median(window.map((x) => x.value));
}

/** Dividendos pagos ÷ lucro, somados nos últimos [payoutYears] exercícios. */
function payoutOf(upTo: readonly FundamentalsSnapshot[], paidByYear: Map<number, number> | null, year: number): number | null {
  if (paidByYear === null) return null;
  let paid = 0;
  let profit = 0;
  let n = 0;
  for (const s of upTo) {
    const y = s.fiscalPeriodEnd.year;
    if (y <= year - payoutYears || y > year) continue;
    const d = paidByYear.get(y);
    const l = s.netIncome;
    if (d === undefined || l === null || !Number.isFinite(l)) continue;
    paid += d;
    profit += round(l * 100);
    n++;
  }
  if (n < minPayoutYears || profit <= 0) return null;
  return paid / profit;
}

/** Receita ÷ capital investido, mediana dos três últimos exercícios. */
function salesPerCapital(upTo: readonly FundamentalsSnapshot[]): number | null {
  const v: number[] = [];
  for (const s of upTo.slice(Math.max(0, upTo.length - 3))) {
    const revenue = s.totalRevenue;
    const capital = s.investedCapital;
    if ((revenue ?? 0) > 0 && (capital ?? 0) > 0) v.push(revenue! / capital!);
  }
  return v.length < 2 ? null : median(v);
}

const groups = ['commodity', 'highPayer', 'lowCapital', 'fundamental', 'noData'] as const;
type Group = (typeof groups)[number];

const groupName: Record<Group, string> = {
  commodity: 'commodity',
  highPayer: 'alta pagadora',
  lowCapital: 'pouco capital',
  fundamental: 'ROE × retenção',
  noData: 'sem dado',
};

/** O que as duas propostas dão para uma companhia num exercício. */
interface Reading {
  roe: number | null;
  payout: number | null;
  salesPerCapital: number | null;
  gFundamental: number | null;
  gSector: number | null;
  activity: string;
  group: Group;
  gRule: number | null;
}

function read(args: {
  fs: readonly FundamentalsSnapshot[];
  year: number;
  paidByYear: Map<number, number> | null;
  commodity: boolean;
  activity: string;
  gdp: SectorGdp;
  date: DateTime;
  inflation: number;
}): Reading {
  const upTo = until(args.fs, args.year);
  const roe = normalizedRoe(upTo);
  const payout = payoutOf(upTo, args.paidByYear, args.year);
  const salesPerCapitalValue = salesPerCapital(upTo);
  const gFund = roe === null || payout === null ? null : roe * Math.min(Math.max(1 - payout, 0.0), 1.0);
  const gSector = args.gdp.growth(args.activity, args.date);
  let group: Group;
  let gRule: number | null;
  if (args.commodity) {
    group = 'commodity';
    gRule = args.inflation;
  } else if ((payout ?? 0) >= highPayout) {
    group = 'highPayer';
    gRule = gSector;
  } else if ((salesPerCapitalValue ?? 0) >= salesToCapital) {
    group = 'lowCapital';
    gRule = gSector;
  } else if (gFund !== null) {
    group = 'fundamental';
    gRule = gFund;
  } else {
    group = 'noData';
    gRule = null;
  }
  return {
    roe,
    payout,
    salesPerCapital: salesPerCapitalValue,
    gFundamental: gFund,
    gSector,
    activity: args.activity,
    group,
    gRule,
  };
}

/**
 * O `g` que a regra do motor dá com os dados até [ano], na via [lane]: a
 * mediana das variações da base quando a dispersão a identifica; a inflação
 * quando não identifica e a retenção a financia; zero no resto (Saída 2).
 */
function engineG(upTo: readonly FundamentalsSnapshot[], lane: ValuationLane, inflation: number): number | null {
  const series = CapitalSeries.build(upTo, lane);
  const d = GrowthGuards.dispersion(series);
  if (d === null) return null;
  if (d.isIdentified) return d.medianGrowth;
  const cycle = series.cycleReturn({ window: ValuationParameters.cycleWindow });
  return GrowthGuards.anchorIsFundable({ inflation, cycleReturn: cycle, observedRetention: series.medianRetention }) ? inflation : 0.0;
}

/**
 * Crescimento anual composto dos três primeiros anos do caminho que o motor
 * projeta a partir de [g]: decai em linha reta até `g∞ = min(g, teto)`, em
 * [−5%; teto]. Composto, e não média das taxas, porque o realizado contra o
 * qual se compara também é composto.
 */
function pathMean(g: number, cap: number, years = 10): number | null {
  const gInf = GrowthEstimator.perpetual({ explicitGrowth: g, economyGrowth: cap });
  let factor = 1.0;
  for (let t = 1; t <= realizedYears; t++) factor *= 1 + g - (g - gInf) * ((t - 1) / (years - 1));
  // Taxa abaixo de −100% num ano não tem caminho composto: fica sem leitura.
  if (!(factor > 0)) return null;
  return Math.pow(factor, 1 / realizedYears) - 1;
}

/** Os exercícios até [year] + três, indexados pelo ano. */
const byFiscalYear = (fs: readonly FundamentalsSnapshot[], year: number): Map<number, FundamentalsSnapshot> =>
  new Map(until(fs, year + realizedYears).map((s) => [s.fiscalPeriodEnd.year, s]));

/**
 * Crescimento realizado do lucro: da média dos três exercícios até [year] à
 * dos três seguintes, anualizado em três anos. `null` se uma média não é
 * positiva ou falta exercício.
 */
function realizedProfit(fs: readonly FundamentalsSnapshot[], year: number): number | null {
  const byYear = byFiscalYear(fs, year);
  const mean = (from: number, to: number): number | null => {
    const v: number[] = [];
    for (let y = from; y <= to; y++) {
      const l = byYear.get(y)?.netIncome ?? null;
      if (l === null || !Number.isFinite(l)) return null;
      v.push(l);
    }
    const m = v.reduce((a, b) => a + b) / v.length;
    return m > 0 ? m : null;
  };

  const before = mean(year - 2, year);
  const after = mean(year + 1, year + realizedYears);
  if (before === null || after === null) return null;
  return Math.pow(after / before, 1 / realizedYears) - 1;
}

/** Crescimento realizado do patrimônio em três exercícios. */
function realizedEquity(fs: readonly FundamentalsSnapshot[], year: number): number | null {
  const byYear = byFiscalYear(fs, year);
  const a = byYear.get(year)?.equityBookValue ?? null;
  const b = byYear.get(year + realizedYears)?.equityBookValue ?? null;
  if (a === null || b === null || !(a > 0) || !(b > 0)) return null;
  return Math.pow(b / a, 1 / realizedYears) - 1;
}

// ---------------------------------------------------------------------------

const variants = ['motor', 'fundamental', 'combinada'] as const;
type Variant = (typeof variants)[number];

class AssetRow {
  g0: number | null = null;
  lane: ValuationLane | null = null;
  readonly fairValue: Partial<Record<Variant, number | null>> = {};
  readonly upside: Partial<Record<Variant, number | null>> = {};
  price: number | null = null;

  constructor(
    readonly ticker: string,
    readonly sector: string,
    readonly reading: Reading,
  ) {}
}

interface PanelRow {
  ticker: string;
  ano: number;
  grupo: string;
  gMotor: number | null;
  gFundamental: number | null;
  gCombinada: number | null;
  realizadoLucro: number | null;
  realizadoPatrimonio: number | null;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const bridge = (readJson<Record<string, unknown>>('docs/validacao/ponte_cvm.json')['ponte'] ?? {}) as Record<string, string>;
    const dividendTotals = readDividends();
    const gdp = SectorGdp.read();
    const today = frozenToday;
    const todayDate = DateTime.utc(today.year, today.month, today.day);
    const currentInflation = c.anchors.inflationCagr;
    const currentCap = c.anchors.nominalEconomyGrowth;

    // -----------------------------------------------------------------------
    // 1. A entrada congelada
    // -----------------------------------------------------------------------
    const assets: AssetRow[] = [];
    const histories = new Map<string, readonly FundamentalsSnapshot[]>();
    const cnpjOf = new Map<string, string | null>();
    const commodityOf = new Map<string, boolean>();
    const activityOf = new Map<string, string>();
    const baseEvaluated = new Map<Ticker, ValuationResult | null>();
    const withoutMap: string[] = [];
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const inputs = prep.unwrap();
      const r0 = ValuationCascade.evaluate(inputs);
      baseEvaluated.set(t, r0.valueOrNull);

      const classification = c.issuer(t)?.classification ?? null;
      const key =
        classification === null || classification.subsector === null ? '' : `${classification.sector}|${classification.subsector}`;
      const activity = activityBySector.get(key) ?? economy;
      if (!activityBySector.has(key)) withoutMap.push(`${t.value} «${key}»`);
      const commodity = CyclicalSectors.hasCyclePrecedence({ sectorKey: inputs.sectorKey, industry: inputs.industry });
      const cnpj = bridge[t.value] ?? null;
      const upTo = until(inputs.fundamentals, today.year);
      const lastYear = upTo.length === 0 ? null : upTo[upTo.length - 1]!.fiscalPeriodEnd.year;
      if (lastYear === null) continue;
      const reading = read({
        fs: inputs.fundamentals,
        year: lastYear,
        paidByYear: cnpj === null ? null : (dividendTotals.get(cnpj) ?? null),
        commodity,
        activity,
        gdp,
        date: todayDate,
        inflation: currentInflation,
      });
      const a = new AssetRow(t.value, key.replaceAll('|', ' / '), reading);
      histories.set(t.value, inputs.fundamentals);
      cnpjOf.set(t.value, cnpj);
      commodityOf.set(t.value, commodity);
      activityOf.set(t.value, activity);
      a.price = inputs.marketPrice;

      const store = (label: Variant, r: Result<ValuationResult>): void => {
        const v = r.valueOrNull;
        a.fairValue[label] = v?.fairValue.cents ?? null;
        a.upside[label] = v?.upside ?? null;
      };

      store('motor', r0);
      a.g0 = r0.valueOrNull?.diagnostics?.growthRate ?? null;
      const model = r0.valueOrNull?.model ?? null;
      a.lane = model === ValuationModel.dcfFcff ? ValuationLane.firm : model === ValuationModel.dcfEarnings ? ValuationLane.shareholder : null;
      const gF = reading.gFundamental;
      store('fundamental', gF === null ? r0 : ValuationCascade.evaluate(inputs.withOverrides({ growth: gF })));
      const gR = reading.gRule;
      store('combinada', gR === null ? r0 : ValuationCascade.evaluate(inputs.withOverrides({ growth: gR })));
      assets.push(a);
    }
    process.stderr.write('                    \r');
    if (withoutMap.length > 0) errln(`sem atividade mapeada (vai a economia inteira): ${withoutMap.join(', ')}`);

    const divergent = await c.checkAgainstAnswerKey(baseEvaluated);
    if (divergent !== null && divergent.length > 0) {
      errln(`ERRO: a montagem diverge do gabarito em ${divergent.length}: ${divergent.slice(0, 8).join(', ')}`);
      process.exitCode = 1;
      return;
    }

    const fair = (a: AssetRow, v: Variant): number | null => a.fairValue[v] ?? null;
    const up = (a: AssetRow, v: Variant): number | null => a.upside[v] ?? null;
    const evaluated = assets.filter((a) => variants.some((v) => fair(a, v) !== null)).sort((x, y) => compareStr(x.ticker, y.ticker));

    outln('-- a entrada congelada: o g de cada regra --');
    outln(
      '  ticker   grupo            payout   ROE norm  g motor  ' +
        'g fund   g setor  g regra   justo motor  justo fund  justo regra   preço',
    );
    const rs = (cents: number | null): string => (cents === null ? 'recusada' : (cents / 100).toFixed(2));
    for (const a of evaluated) {
      const l = a.reading;
      outln(
        `  ${a.ticker.padEnd(7)}  ` +
          `${groupName[l.group].padEnd(15)}  ${pct(l.payout, 0).padStart(6)}  ` +
          `${pct(l.roe, 1).padStart(8)}  ${pct(a.g0, 1).padStart(7)}  ` +
          `${pct(l.gFundamental, 1).padStart(6)}  ${pct(l.gSector, 1).padStart(7)}  ` +
          `${pct(l.gRule, 1).padStart(7)}   ${rs(fair(a, 'motor')).padStart(11)}  ` +
          `${rs(fair(a, 'fundamental')).padStart(10)}  ` +
          `${rs(fair(a, 'combinada')).padStart(11)}  ` +
          `${a.price === null ? 'null' : a.price.toFixed(2)}`,
      );
    }

    const summary: Record<string, unknown>[] = [];
    outln('');
    outln('-- o universo com cada regra --');
    outln('  regra         avaliados  potencial mediano  acima de zero  distância mediana ao preço  justo vs motor  postos');
    for (const v of variants) {
      const withInput = evaluated.filter((a) => fair(a, v) !== null);
      const upsideValues = present(withInput.map((a) => up(a, v)));
      // O logaritmo só existe com as duas pontas positivas.
      const dist: number[] = [];
      for (const a of withInput) {
        if ((a.price ?? 0) > 0 && fair(a, v)! > 0) dist.push(Math.abs(Math.log(fair(a, v)! / 100 / a.price!)));
      }
      const common = evaluated.filter(
        (a) => fair(a, v) !== null && fair(a, 'motor') !== null && up(a, v) !== null && up(a, 'motor') !== null,
      );
      const changeList: number[] = [];
      for (const a of common) if (fair(a, 'motor')! !== 0) changeList.push(fair(a, v)! / fair(a, 'motor')! - 1);
      const rho =
        common.length < 3
          ? null
          : Regression.spearman(
              common.map((a) => up(a, 'motor')!),
              common.map((a) => up(a, v)!),
            );
      const medianUpside = median(upsideValues);
      const medDist = median(dist);
      const medVar = median(changeList);
      const above = upsideValues.filter((p) => p > 0).length;
      outln(
        `  ${v.padEnd(12)}  ${String(withInput.length).padStart(9)}  ` +
          `${pct(medianUpside, 1).padStart(17)}  ${`${above} de ${withInput.length}`.padStart(13)}  ` +
          `${(medDist === null ? '—' : medDist.toFixed(3)).padStart(26)}  ` +
          `${pct(medVar, 1).padStart(14)}  ${rho === null ? '—' : rho.toFixed(3)}`,
      );
      summary.push({
        regra: v,
        avaliados: withInput.length,
        potencialMediano: medianUpside,
        acimaDeZero: above,
        distanciaMedianaAoPreco: medDist,
        justoMedianoContraMotor: medVar,
        spearmanContraMotor: rho,
      });
    }

    // Por grupo da regra combinada.
    const byGroup: Record<string, unknown>[] = [];
    outln('');
    outln('-- por grupo da regra combinada --');
    for (const g of groups) {
      const ofGroup = evaluated.filter((a) => a.reading.group === g);
      if (ofGroup.length === 0) continue;
      const med = (f: (a: AssetRow) => number | null): number | null => median(present(ofGroup.map(f)));
      const row = {
        grupo: groupName[g],
        ativos: ofGroup.length,
        gMotor: med((a) => a.g0),
        gFundamental: med((a) => a.reading.gFundamental),
        gRegra: med((a) => a.reading.gRule),
        potencialMotor: med((a) => up(a, 'motor')),
        potencialFundamental: med((a) => up(a, 'fundamental')),
        potencialCombinada: med((a) => up(a, 'combinada')),
      };
      byGroup.push(row);
      outln(
        `  ${groupName[g].padEnd(15)} ${String(ofGroup.length).padStart(3)}  ` +
          `g motor ${pct(row.gMotor, 1)}  ` +
          `g fund ${pct(row.gFundamental, 1)}  ` +
          `g regra ${pct(row.gRegra, 1)}  ` +
          `potencial ${pct(row.potencialMotor, 1)} → ` +
          `${pct(row.potencialFundamental, 1)} / ` +
          `${pct(row.potencialCombinada, 1)}`,
      );
    }

    // -----------------------------------------------------------------------
    // 2. O histórico: qual g acertou o crescimento seguinte
    // -----------------------------------------------------------------------
    const index = await LongIbovespa.build(c.ctx.benchmark, new DateRange(DateTime.local(today.year - 10, today.month, today.day), today));
    const panel: PanelRow[] = [];
    for (let year = 2014; year <= 2022; year++) {
      const anchors = (await ResolveMarketAnchors.call({ macro: c.ctx.macro, benchmark: index, asOf: DateTime.local(year, 12, 31) })).unwrap();
      const inflation = anchors.inflationCagr;
      const cap = anchors.nominalEconomyGrowth;
      const date = DateTime.utc(year + 1, 3, 31);
      for (const a of evaluated) {
        const fs = histories.get(a.ticker)!;
        const lane = a.lane ?? ValuationLane.shareholder;
        const upTo = until(fs, year);
        if (upTo.length === 0 || upTo[upTo.length - 1]!.fiscalPeriodEnd.year !== year) continue;
        const gEngine = engineG(upTo, lane, inflation);
        const cnpj = cnpjOf.get(a.ticker) ?? null;
        const l = read({
          fs,
          year,
          paidByYear: cnpj === null ? null : (dividendTotals.get(cnpj) ?? null),
          commodity: commodityOf.get(a.ticker)!,
          activity: activityOf.get(a.ticker)!,
          gdp,
          date,
          inflation,
        });
        panel.push({
          ticker: a.ticker,
          ano: year,
          grupo: groupName[l.group],
          gMotor: gEngine === null ? null : pathMean(gEngine, cap),
          gFundamental: l.gFundamental === null ? null : pathMean(l.gFundamental, cap),
          gCombinada: l.gRule === null ? null : pathMean(l.gRule, cap),
          realizadoLucro: realizedProfit(fs, year),
          realizadoPatrimonio: realizedEquity(fs, year),
        });
      }
    }

    const tests: Record<string, unknown>[] = [];
    outln('');
    outln('-- o histórico: o g de cada regra contra o crescimento dos três exercícios seguintes (2014 a 2022) --');
    outln('  alvo         regra         pares  erro absoluto mediano  viés mediano  postos');
    for (const target of ['realizadoLucro', 'realizadoPatrimonio'] as const) {
      // Só os pares em que as três regras existem: a comparação é no mesmo
      // conjunto.
      const pairs = panel.filter((p) => p[target] !== null && p.gMotor !== null && p.gFundamental !== null && p.gCombinada !== null);
      for (const rule of ['gMotor', 'gFundamental', 'gCombinada'] as const) {
        const errors = pairs.map((p) => p[rule]! - p[target]!);
        const abs = errors.map((e) => Math.abs(e));
        const rho =
          pairs.length < 3
            ? null
            : Regression.spearman(
                pairs.map((p) => p[rule]!),
                pairs.map((p) => p[target]!),
              );
        const row = {
          alvo: target,
          regra: rule,
          pares: pairs.length,
          erroAbsolutoMediano: median(abs),
          viesMediano: median(errors),
          spearman: rho,
        };
        tests.push(row);
        outln(
          `  ${target.padEnd(11)}  ${rule.padEnd(12)}  ` +
            `${String(pairs.length).padStart(5)}  ` +
            `${pct(row.erroAbsolutoMediano).padStart(21)}  ` +
            `${pct(row.viesMediano).padStart(12)}  ` +
            `${rho === null ? '—' : rho.toFixed(3)}`,
        );
      }
    }

    writeText(
      output,
      jsonPretty(
        {
          geradoPor: 'tool/fundamental-growth.ts',
          dataDaEntrada: today.toIso8601String().substring(0, 10),
          inflacao: currentInflation,
          teto: currentCap,
          regras: {
            payoutAlto: highPayout,
            vendasSobreCapital: salesToCapital,
            anosDoPayout: payoutYears,
            janelaDoRoe: roeWindow,
            anosDoSetor: sectorYears,
          },
          ativos: evaluated.map((a) => ({
            ticker: a.ticker,
            setor: a.sector,
            atividade: a.reading.activity,
            grupo: groupName[a.reading.group],
            payout: a.reading.payout,
            roeNormalizado: a.reading.roe,
            vendasPorCapital: a.reading.salesPerCapital,
            gMotor: a.g0,
            gFundamental: a.reading.gFundamental,
            gSetor: a.reading.gSector,
            gRegra: a.reading.gRule,
            preco: a.price,
            justoCentavos: a.fairValue,
            potencial: a.upside,
          })),
          resumo: summary,
          porGrupo: byGroup,
          historico: { testes: tests, painel: panel },
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
