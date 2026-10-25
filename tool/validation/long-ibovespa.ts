// O Ibovespa diário longo: o SGS 7 do Banco Central antes da fonte de mercado,
// e a fonte de mercado dali em diante.
//
// **Por que existe.** A brapi entrega o índice dos últimos dez anos (desde
// 23/09/2016 na consulta de 28/09/2026). Um prêmio de risco histórico medido
// numa coorte de 2018 com janela de dez anos pede o índice desde 2008, e o
// SGS 7 tem o fechamento diário até 30/09/2019, quando foi descontinuado.
//
// **A emenda.** Vale a fonte de mercado a partir do primeiro pregão dela, e o
// SGS antes. Nos 744 pregões comuns de 2016 a 2019 a razão mediana entre as
// duas é 1,000000; três dias diferem mais de 0,2%, um deles um erro de dígito
// no SGS (61.108 contra 64.108 em 21/10/2016). A emenda confere a razão na
// sobreposição e recusa se ela se afastar de 1 — sinal de que uma das duas
// mudou de escala.
//
// Só serve a medições: o aplicativo não tem o SGS 7, e o beta das coortes
// continua lendo a série da fonte de mercado.
import { existsSync } from 'node:fs';

import {
  type BenchmarkRepository,
  DateRange,
  DateTime,
  Inference,
  type MarketAnchors,
  ok,
  PricePoint,
  PriceSeries,
  type Result,
  StateError,
  Ticker,
} from '../../src/core';
import { readJson } from '../lib/files';

/** O arquivo gravado por `tool/ibovespa_sgs_baixar.py`. */
export const sgs7File = 'data/indices/ibovespa_sgs7.json';

/** Distância máxima entre a razão mediana da sobreposição e 1. */
export const spliceTolerance = 0.002;

/** Série do Ibovespa que emenda o SGS 7 à fonte de mercado. */
export class LongIbovespa implements BenchmarkRepository {
  private constructor(
    private readonly points: readonly PricePoint[],
    /** Primeiro pregão da fonte de mercado: antes dele, os pontos são do SGS. */
    readonly sourceStart: DateTime,
    /** Razão mediana `fonte ÷ SGS` nos pregões comuns. */
    readonly overlapRatio: number,
  ) {}

  /**
   * Monta a série com a fonte de mercado [market].
   *
   * [sourceWindow] é a janela pedida a ela: por padrão tudo o que ela tiver;
   * a entrada congelada só serve as janelas que gravou, e aí vai a gravada.
   */
  static async build(market: BenchmarkRepository, sourceWindow?: DateRange): Promise<LongIbovespa> {
    if (!existsSync(sgs7File)) throw new StateError(`Falta ${sgs7File}. Rode antes: python tool/ibovespa_sgs_baixar.py`);
    const json = readJson<{ pontos: [string, number][] }>(sgs7File);
    const sgs = new Map<string, { date: DateTime; close: number }>();
    for (const [day, close] of json.pontos) {
      const date = DateTime.parse(day);
      sgs.set(date.key, { date, close: Number(close) });
    }
    const r = await market.ibovespa(sourceWindow ?? new DateRange(DateTime.local(2000, 1, 1), DateTime.local(2100, 1, 1)));
    if (r.isErr) throw new StateError(`Ibovespa da fonte de mercado: ${r.failureOrNull?.message}`);
    const source = r.unwrap().points;
    if (source.length === 0) throw new StateError('Ibovespa da fonte de mercado vazio.');
    const sourceStart = source[0]!.date;

    const ratios: number[] = [];
    for (const p of source) {
      const s = sgs.get(p.date.key);
      if (s !== undefined && s.close > 0 && p.close > 0) ratios.push(p.close / s.close);
    }
    if (ratios.length === 0) {
      throw new StateError('SGS 7 e fonte de mercado sem pregão em comum: a emenda não pode ser conferida.');
    }
    const ratio = Inference.median(ratios)!;
    if (Math.abs(ratio - 1) > spliceTolerance) {
      throw new StateError(`A razão mediana entre a fonte de mercado e o SGS 7 é ${ratio.toFixed(6)}: uma das duas mudou de escala.`);
    }

    const points = [
      ...[...sgs.values()].filter((e) => e.date.isBefore(sourceStart)).map((e) => new PricePoint({ date: e.date, close: e.close })),
      ...source,
    ].sort((a, b) => a.date.compareTo(b.date));
    return new LongIbovespa(points, sourceStart, ratio);
  }

  async ibovespa(range: DateRange): Promise<Result<PriceSeries>> {
    return ok(new PriceSeries({ ticker: Ticker.parse('IBOV11'), points: this.points.filter((p) => range.contains(p.date)) }));
  }
}

/**
 * O prêmio de risco histórico que as âncoras de mercado implicam.
 *
 * `(1 + CAGR do Ibovespa) ÷ (1 + CAGR do CDI) − 1`, os dois sobre a mesma
 * janela de `ResolveMarketAnchors` — o índice entre as médias de 63 pregões
 * das pontas, e o CDI composto. É Fisher, e não subtração: o prêmio é razão de
 * fatores brutos, como na medição da decisão 116.
 */
export function premiumOfAnchors(a: MarketAnchors): number {
  return (1 + a.marketCagr) / (1 + a.riskFreeCagr) - 1;
}
