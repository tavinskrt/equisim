// B46 — o risco do controle estatal: o beta, o lambda e o efeito no preço.
//
// **A pergunta.** O motor dá às estatais potencial muito maior que às privadas.
// Parte disso pode ser risco que o CAPM do motor não cobra: o controlador
// público persegue objetivos além do lucro, e o minoritário paga. A medição
// confere três caminhos, sobre a entrada congelada de 14/09/2026:
//
// 1. **O beta.** O motor encolhe o beta medido em direção à mediana do setor,
//    e o setor é quase todo de privadas. Se o beta medido das estatais for
//    maior que o encolhido, a correção cabe no CAPM puro.
// 2. **O lambda de Damodaran** (2003): a exposição de cada companhia ao risco
//    do país, `Ke = Rf + β × prêmio + λ × prêmio-país`. Medido pela
//    sensibilidade do retorno semanal da ação à variação do risco soberano, por
//    duas séries independentes — o EMBI+ Risco-Brasil (até 30/07/2024, quando o
//    J.P. Morgan o descontinuou) e o prefixado de dez anos do Tesouro (até a
//    data congelada) —, sozinha e junto com o Ibovespa. O lambda de cada
//    companhia é a sensibilidade dela dividida pela mediana do universo.
// 3. **O efeito no preço de hoje** de cobrar das estatais um prêmio a mais no
//    custo do capital próprio, e o de tirar o encolhimento do beta delas.
//
// O controle é o do Formulário Cadastral da CVM (`public/assets/cvm/controle.json`,
// de `tool/control-package.ts`). Na medição do lambda, a companhia entra no
// grupo da espécie que teve a janela inteira; quem mudou de controle no meio
// fica de fora.
//
// Uso:
//   python tool/risco_pais_baixar.py
//   npm run tool -- control-package
//   npm run tool -- state-owned
//
// Grava docs/validacao/estatais.json.
import { existsSync } from 'node:fs';

import {
  compareNum,
  compareStr,
  DateRange,
  DateTime,
  intDiv,
  type JsonObject,
  type PricePoint,
  type ShareholderControl,
  ShareholderControlHistory,
  Ticker,
  TreasuryCurve,
  ValuationCascade,
  type YieldCurve,
} from '../src/core';
import { readTreasury } from './curve-link';
import { dartString, errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';

const output = 'docs/validacao/estatais.json';

/** Prêmios a mais no custo do capital próprio das estatais, em fração. */
const grid = [0.005, 0.01, 0.02, 0.03];

/** Mínimo de semanas com retorno para a regressão valer. */
const minWeeks = 150;

/** Quarta-feira no `weekday` do Dart, que começa na segunda em 1. */
const wednesday = 3;

type Point = [DateTime, number];

/** Uma regressão por mínimos quadrados, com intercepto. */
function ols(y: readonly number[], xs: readonly (readonly number[])[]): { coef: number[]; error: number[]; n: number } | null {
  const n = y.length;
  const k = xs.length + 1;
  if (n <= k + 2) return null;
  // X'X e X'y, com a coluna do intercepto.
  const xtx = Array.from({ length: k }, () => new Array<number>(k).fill(0.0));
  const xty = new Array<number>(k).fill(0.0);
  for (let i = 0; i < n; i++) {
    const row = [1.0, ...xs.map((x) => x[i]!)];
    for (let a = 0; a < k; a++) {
      xty[a]! += row[a]! * y[i]!;
      for (let b = 0; b < k; b++) xtx[a]![b]! += row[a]! * row[b]!;
    }
  }
  const inv = inverse(xtx);
  if (inv === null) return null;
  const coef = Array.from({ length: k }, (_, a) =>
    Array.from({ length: k }, (_, b) => inv[a]![b]! * xty[b]!).reduce((p, q) => p + q),
  );
  let sqr = 0.0;
  for (let i = 0; i < n; i++) {
    let predicted = coef[0]!;
    for (let j = 0; j < xs.length; j++) predicted += coef[j + 1]! * xs[j]![i]!;
    sqr += Math.pow(y[i]! - predicted, 2);
  }
  const s2 = sqr / (n - k);
  return {
    coef: coef.slice(1),
    error: Array.from({ length: k - 1 }, (_, a) => Math.sqrt(s2 * inv[a + 1]![a + 1]!)),
    n,
  };
}

function inverse(m: readonly (readonly number[])[]): number[][] | null {
  const k = m.length;
  const a = m.map((row, i) => [...row, ...Array.from({ length: k }, (_, j) => (i === j ? 1.0 : 0.0))]);
  for (let c = 0; c < k; c++) {
    let piv = c;
    for (let r = c + 1; r < k; r++) if (Math.abs(a[r]![c]!) > Math.abs(a[piv]![c]!)) piv = r;
    if (Math.abs(a[piv]![c]!) < 1e-14) return null;
    const t = a[c]!;
    a[c] = a[piv]!;
    a[piv] = t;
    const d = a[c]![c]!;
    for (let j = 0; j < 2 * k; j++) a[c]![j]! /= d;
    for (let r = 0; r < k; r++) {
      if (r === c) continue;
      const f = a[r]![c]!;
      for (let j = 0; j < 2 * k; j++) a[r]![j]! -= f * a[c]![j]!;
    }
  }
  return a.map((l) => l.slice(k));
}

function median(v: Iterable<number>): number {
  const s = [...v].sort(compareNum);
  if (s.length === 0) return Number.NaN;
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function mean(v: Iterable<number>): number {
  const l = [...v];
  return l.length === 0 ? Number.NaN : l.reduce((a, b) => a + b) / l.length;
}

/** `t` de Welch para a diferença de médias de dois grupos. */
function welch(a: readonly number[], b: readonly number[]): number {
  const variance = (x: readonly number[]): number => {
    const m = mean(x);
    return x.map((v) => Math.pow(v - m, 2)).reduce((p, q) => p + q) / (x.length - 1);
  };
  if (a.length < 2 || b.length < 2) return Number.NaN;
  return (mean(a) - mean(b)) / Math.sqrt(variance(a) / a.length + variance(b) / b.length);
}

/** O último valor da série em ou antes de [day]. */
function atDate(series: readonly Point[], day: DateTime): number | null {
  let lo = 0;
  let hi = series.length - 1;
  let foundValue: number | null = null;
  while (lo <= hi) {
    const m = intDiv(lo + hi, 2);
    if (series[m]![0].isAfter(day)) {
      hi = m - 1;
    } else {
      foundValue = series[m]![1];
      lo = m + 1;
    }
  }
  return foundValue;
}

/**
 * O prefixado de dez anos da curva: a média geométrica dos forwards anuais,
 * como em `tool/implied-premium.ts`.
 */
function fixedRate10(curve: YieldCurve | null): number | null {
  if (curve === null) return null;
  const fw = curve.annualForwards(10);
  if (fw.length === 0) return null;
  let factor = 1.0;
  for (const f of fw) factor *= 1 + f;
  return Math.pow(factor, 1 / fw.length) - 1;
}

const pct = (v: number, decimals = 2): string => `${(v * 100).toFixed(decimals).replaceAll('.', ',')}%`;

const num = (v: number, decimals = 2): string => v.toFixed(decimals).replaceAll('.', ',');

const day = (d: DateTime): string => d.toIso8601String().substring(0, 10);

interface WindowRegression {
  semanas: number;
  controleNoInicio: string | null;
  controleNoFim: string | null;
  sensibilidade: number | null;
  erro: number | null;
  alemDoMercado: number | null;
  erroAlemDoMercado: number | null;
  betaNaRegressao: number | null;
}

interface Row {
  ticker: string;
  raiz: string;
  controle: string | null;
  setor: string | null;
  betaMedido: number | null;
  betaEncolhido: number;
  origemBeta: string;
  avaliado: boolean;
  potencial: number | null;
  volumeMediano: number;
  [window: string]: unknown;
}

interface Window {
  from: DateTime;
  until: DateTime;
  risk: Point[];
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const controlFile = 'public/assets/cvm/controle.json';
    const control = existsSync(controlFile) ? ShareholderControlHistory.decode(readJson<JsonObject>(controlFile)) : null;
    if (control === null) {
      errln(`${controlFile} ilegível: rode npm run tool -- control-package`);
      process.exitCode = 2;
      return;
    }
    const rawEmbi = 'data/indices/embi_brasil.json';
    if (!existsSync(rawEmbi)) {
      errln('sem data/indices/embi_brasil.json: rode python tool/risco_pais_baixar.py');
      process.exitCode = 2;
      return;
    }
    const embi: Point[] = readJson<[string, number][]>(rawEmbi).map((p) => [DateTime.parse(p[0]), p[1] / 10000]);

    const today = frozenToday;
    const controlOf = (t: Ticker, d: DateTime): ShareholderControl | null => {
      const p = control.byIssuer.get(t.value.substring(0, 4));
      return p === undefined ? null : ShareholderControlHistory.at(p, d);
    };

    // -----------------------------------------------------------------------
    // As séries semanais: o Ibovespa gravado pelo gabarito, de dez anos, e as
    // duas medidas do risco soberano.
    // -----------------------------------------------------------------------
    const tenYears = new DateRange(DateTime.local(2016, 9, 14), today);
    const ibov = (await c.ctx.benchmark.ibovespa(tenYears)).unwrap();
    const ibovSeries: Point[] = ibov.points.map((p) => [p.date, p.close]);
    const wednesdays = ibov.points.filter((p) => p.date.weekday === wednesday).map((p) => p.date);
    const quotes = readTreasury('data/tesouro/precotaxatesourodireto.csv');

    // As duas janelas de cinco anos, cada uma com a sua medida do risco.
    const windows = new Map<string, Window>();
    {
      const embiEnd = embi[embi.length - 1]![0];
      windows.set('embi', {
        from: DateTime.local(embiEnd.year - 5, embiEnd.month, embiEnd.day),
        until: embiEnd,
        risk: embi,
      });
      const from = DateTime.local(today.year - 5, today.month, today.day);
      const pref: Point[] = [];
      for (const q of wednesdays) {
        if (q.isBefore(from)) continue;
        const y = fixedRate10(TreasuryCurve.at(quotes, q));
        if (y !== null) pref.push([q, y]);
      }
      windows.set('prefixado10', { from, until: today, risk: pref });
    }

    // -----------------------------------------------------------------------
    // O universo: beta medido e encolhido, avaliação e séries de preço.
    // -----------------------------------------------------------------------
    const rows: Row[] = [];
    const byRoot = new Map<string, Row>();
    const lastYear = DateTime.local(today.year - 1, today.month, today.day);
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const withPrior = await c.prepare(t);
      if (withPrior.isErr) continue;
      const withoutPrior = await c.prepare(t, { withPrior: false });
      const inputs = withPrior.unwrap();
      const r = ValuationCascade.evaluate(inputs);
      const series = (await c.ctx.prices.daily(t, tenYears)).valueOrNull;
      const points: readonly PricePoint[] = series?.points ?? [];
      const prices: Point[] = points.map((p) => [p.date, p.close]);
      const volumes = points.filter((p) => p.date.isAfter(lastYear)).map((p) => p.volume ?? 0);
      const row: Row = {
        ticker: t.value,
        raiz: t.value.substring(0, 4),
        controle: controlOf(t, today)?.name ?? null,
        setor: inputs.sectorKey,
        betaMedido: withoutPrior.valueOrNull?.capm.beta ?? null,
        betaEncolhido: inputs.capm.beta,
        origemBeta: inputs.capm.betaSource.name,
        avaliado: r.isOk,
        potencial: r.valueOrNull?.upside ?? null,
        volumeMediano: volumes.length === 0 ? 0.0 : median(volumes),
      };
      // Lambda nas duas janelas.
      for (const [key, w] of windows) {
        const ctl0 = controlOf(t, w.from);
        const ctl1 = controlOf(t, w.until);
        const ys: number[] = [];
        const xm: number[] = [];
        const xs: number[] = [];
        let before: DateTime | null = null;
        for (const q of wednesdays) {
          if (q.isBefore(w.from) || q.isAfter(w.until)) continue;
          if (before !== null) {
            const p0 = atDate(prices, before);
            const p1 = atDate(prices, q);
            const m0 = atDate(ibovSeries, before);
            const m1 = atDate(ibovSeries, q);
            const s0 = atDate(w.risk, before);
            const s1 = atDate(w.risk, q);
            // A semana sem negócio — preço igual ao da anterior — fica fora:
            // é falta de pregão, e não retorno zero.
            if (
              p0 !== null &&
              p1 !== null &&
              p0 > 0 &&
              m0 !== null &&
              m0 > 0 &&
              m1 !== null &&
              s0 !== null &&
              s1 !== null &&
              Math.abs(p1 - p0) > 1e-9 * p0
            ) {
              ys.push(p1 / p0 - 1);
              xm.push(m1 / m0 - 1);
              // Sinal trocado: risco que cai é retorno que sobe, e a
              // sensibilidade positiva é a exposição.
              xs.push(-(s1 - s0));
            }
          }
          before = q;
        }
        const oneFactor = ys.length >= minWeeks ? ols(ys, [xs]) : null;
        const twoFactor = ys.length >= minWeeks ? ols(ys, [xm, xs]) : null;
        const regression: WindowRegression = {
          semanas: ys.length,
          controleNoInicio: ctl0?.name ?? null,
          controleNoFim: ctl1?.name ?? null,
          sensibilidade: oneFactor?.coef[0] ?? null,
          erro: oneFactor?.error[0] ?? null,
          alemDoMercado: twoFactor?.coef[twoFactor.coef.length - 1] ?? null,
          erroAlemDoMercado: twoFactor?.error[twoFactor.error.length - 1] ?? null,
          betaNaRegressao: twoFactor?.coef[0] ?? null,
        };
        row[key] = regression;
      }
      rows.push(row);
      // Uma linha por companhia nas estatísticas de grupo: a classe mais
      // negociada no último ano.
      const current = byRoot.get(row.raiz);
      if (current === undefined || row.volumeMediano > current.volumeMediano) byRoot.set(row.raiz, row);
    }
    process.stderr.write('                                \r');

    const summary: Record<string, unknown> = {};
    outln('== 1. O beta: medido contra encolhido, uma linha por companhia');
    {
      const groups = new Map<string, Row[]>();
      for (const l of byRoot.values()) {
        if (l.betaMedido === null) continue;
        const g = l.controle === 'state' ? 'estatal' : 'privada';
        let list = groups.get(g);
        if (list === undefined) groups.set(g, (list = []));
        list.push(l);
      }
      for (const [g, list] of groups) {
        const measured = list.map((l) => l.betaMedido!);
        const shrunk = list.map((l) => l.betaEncolhido);
        const diff = list.map((l) => l.betaEncolhido - l.betaMedido!);
        outln(
          `  ${g}: ${list.length} companhias; beta medido mediano ${num(median(measured))}, encolhido ${num(median(shrunk))}; ` +
            `encolhido − medido: mediana ${num(median(diff), 3)}, média ${num(mean(diff), 3)}`,
        );
        summary[`beta_${g}`] = {
          companhias: list.length,
          medidoMediano: median(measured),
          encolhidoMediano: median(shrunk),
          difMediana: median(diff),
          difMedia: mean(diff),
        };
      }
      const est = [...byRoot.values()]
        .filter((l) => l.controle === 'state' && l.betaMedido !== null)
        .sort((a, b) => compareStr(a.ticker, b.ticker));
      outln(`  estatais: ${est.map((l) => `${l.ticker} ${num(l.betaMedido!)}→${num(l.betaEncolhido)}`).join('; ')}`);
      // Contra as privadas do mesmo setor.
      const bySector = new Map<string, number[]>();
      for (const l of byRoot.values()) {
        if (l.controle === 'state' || l.betaMedido === null) continue;
        const k = dartString(l.setor);
        let list = bySector.get(k);
        if (list === undefined) bySector.set(k, (list = []));
        list.push(l.betaMedido);
      }
      const againstSector: number[] = [];
      for (const l of est) {
        const pairs = bySector.get(dartString(l.setor));
        if (pairs === undefined || pairs.length < 3) continue;
        againstSector.push(l.betaMedido! - median(pairs));
      }
      outln(
        '  beta medido da estatal − mediana das privadas do mesmo setor (setores com 3+ privadas): ' +
          `mediana ${num(median(againstSector), 3)} em ${againstSector.length} estatais`,
      );
      summary['beta_contraSetor'] = { estatais: againstSector.length, difMediana: median(againstSector) };
    }

    outln('');
    outln('== 2. O lambda: sensibilidade à queda do risco soberano');
    const lambdaByWindow = new Map<string, number | null>();
    for (const [j, window] of windows) {
      const groups = new Map<string, WindowRegression[]>();
      for (const l of byRoot.values()) {
        const m = l[j] as WindowRegression;
        if (m.sensibilidade === null) continue;
        const ini = m.controleNoInicio;
        const end = m.controleNoFim;
        if (ini === null || ini !== end) continue;
        const g = ini === 'state' ? 'estatal' : 'privada';
        let list = groups.get(g);
        if (list === undefined) groups.set(g, (list = []));
        list.push(m);
      }
      const allRows = [...groups.values()].flatMap((g) => g.map((m) => m.sensibilidade!));
      const reference = median(allRows);
      const result: Record<string, unknown> = { medianaDoUniverso: reference };
      outln(
        `  ${j === 'embi' ? 'EMBI+ Risco-Brasil' : 'prefixado de dez anos'}, ${day(window.from)} a ${day(window.until)}, semanal; ` +
          `mediana do universo ${num(reference)}`,
      );
      const sens = new Map<string, number[]>();
      const beyond = new Map<string, number[]>();
      for (const [g, list] of groups) {
        const s = list.map((m) => m.sensibilidade!);
        const b = list.map((m) => m.alemDoMercado as number);
        sens.set(g, s);
        beyond.set(g, b);
        const lambda = median(s) / reference;
        if (g === 'estatal') lambdaByWindow.set(j, lambda);
        outln(
          `    ${g}: ${list.length} companhias; sensibilidade mediana ${num(median(s))} (lambda ${num(lambda)}); ` +
            `além do Ibovespa: mediana ${num(median(b))}, média ${num(mean(b))}`,
        );
        result[g] = {
          companhias: list.length,
          sensibilidadeMediana: median(s),
          lambda,
          alemDoMercadoMediana: median(b),
          alemDoMercadoMedia: mean(b),
        };
      }
      const tSens = welch(sens.get('estatal') ?? [], sens.get('privada') ?? []);
      const tBeyond = welch(beyond.get('estatal') ?? [], beyond.get('privada') ?? []);
      outln(`    diferença estatal − privada: t de Welch ${num(tSens)} na sensibilidade, ${num(tBeyond)} além do Ibovespa`);
      result['tWelchSensibilidade'] = tSens;
      result['tWelchAlemDoMercado'] = tBeyond;
      summary[`lambda_${j}`] = result;
    }
    const lastEmbi = embi[embi.length - 1]!;
    const countryPremium = lastEmbi[1];
    outln(`  prêmio-país no último EMBI+ (${day(lastEmbi[0])}): ${pct(countryPremium)}`);
    summary['premioPais'] = { data: day(lastEmbi[0]), valor: countryPremium };
    for (const j of windows.keys()) {
      const l = lambdaByWindow.get(j) ?? null;
      if (l === null) continue;
      outln(`  (λ − 1) × prêmio-país, pela janela ${j}: ${pct((l - 1) * countryPremium)}`);
    }

    outln('');
    outln('== 3. O efeito no preço de hoje, nas estatais avaliadas');
    const effects: Record<string, unknown>[] = [];
    const stateOwnedTickers = rows.filter((l) => l.controle === 'state' && l.avaliado);
    const base = c.premium.value;
    const variants: [string, number | null, boolean][] = [
      ['base', null, true],
      ...grid.map((x): [string, number | null, boolean] => [`+${pct(x, 1)} no Ke`, x, true]),
      ['beta sem encolhimento', null, false],
    ];
    for (const [label, extra, shrinkBeta] of variants) {
      const upsideByTicker: Record<string, number | null> = {};
      for (const l of stateOwnedTickers) {
        const t = Ticker.parse(l.ticker);
        let premium: number | null = null;
        if (extra !== null) {
          // O prêmio a mais entra somado ao do mercado na proporção do beta:
          // `β × (prêmio + x ÷ β) = β × prêmio + x`. Exato no Ke de hoje; no
          // caminho realavancado, o acréscimo anda com `β_t ÷ β`.
          const beta = l.betaEncolhido;
          if (Math.abs(beta) <= 0.01) {
            upsideByTicker[t.value] = null;
            continue;
          }
          premium = base + extra / beta;
        }
        const prep = await c.prepare(t, { premium, withPrior: shrinkBeta });
        const r = prep.isErr ? null : ValuationCascade.evaluate(prep.unwrap());
        upsideByTicker[t.value] = r?.valueOrNull?.upside ?? null;
      }
      const validValues = Object.values(upsideByTicker).filter((v): v is number => v !== null);
      outln(
        `  ${label}: ${validValues.length} de ${stateOwnedTickers.length} avaliadas, potencial mediano ` +
          `${validValues.length === 0 ? '—' : pct(median(validValues), 1)}`,
      );
      effects.push({
        variante: label,
        premioAMais: extra,
        comEncolhimento: shrinkBeta,
        avaliadas: validValues.length,
        potencialMediano: median(validValues),
        potenciais: upsideByTicker,
      });
    }
    const privateTickers = rows.filter((l) => l.controle !== 'state' && l.avaliado).map((l) => l.potencial as number);
    outln(`  (privadas: ${privateTickers.length} avaliadas, potencial mediano ${pct(median(privateTickers), 1)})`);
    summary['potencialPrivadas'] = { avaliadas: privateTickers.length, mediano: median(privateTickers) };

    writeText(
      output,
      jsonPretty(
        {
          geradoPor: 'tool/state-owned.ts',
          dataDaEntrada: day(today),
          premioDeMercado: base,
          resumo: summary,
          efeitos: effects,
          ativos: rows,
        },
        ' ',
      ),
    );
    outln(`\nescrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}
