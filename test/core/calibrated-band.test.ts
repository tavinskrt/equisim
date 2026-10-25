import { describe, expect, it } from 'vitest';

import {
  CalibratedBand,
  CalibratedBandCodec,
  Duration,
  FairValueBandTable,
  type JsonObject,
  Money,
  PricePoint,
  PriceSeries,
  Ticker,
  VolatilityBandTable,
} from '../../src/core';
import { day, expectClose } from './helpers';

const band = (
  options: { months?: number; nominal?: number; lower?: number; upper?: number; outside?: unknown } = {},
): JsonObject => ({
  meses: options.months ?? 12,
  nominal: options.nominal ?? 0.8,
  fatorInferior: options.lower ?? 0.6248,
  fatorSuperior: options.upper ?? 9.2125,
  observacoes: 730,
  primeiraCoorte: 2018,
  ultimaCoorte: 2024,
  coberturaForaDaAmostra: ('outside' in options ? options.outside : 0.803) as JsonObject[string],
  observacoesForaDaAmostra: 651,
});

describe('Faixa calibrada — item C2', () => {
  it('as bordas são o preço justo vezes os fatores, em centavos', () => {
    const [t] = CalibratedBandCodec.decode({ versao: 1, faixas: [band()] });
    const b = CalibratedBand.of(new Money(1000), t!)!;
    // R$ 10,00 × 0,6248 = R$ 6,248 → 625 centavos; × 9,2125 → 9.212,5 →
    // 9.213, com o meio afastado de zero de `Money`.
    expect(b.low.cents).toBe(625);
    expect(b.high.cents).toBe(9213);
  });

  it('preço justo não positivo não tem faixa: a razão não foi medida ali', () => {
    const [t] = CalibratedBandCodec.decode({ versao: 1, faixas: [band()] });
    expect(CalibratedBand.of(Money.zero, t!)).toBeNull();
    expect(CalibratedBand.of(new Money(-500), t!)).toBeNull();
  });

  it('a seleção compara a frequência com folga, não por igualdade', () => {
    const tables = CalibratedBandCodec.decode({
      versao: 1,
      faixas: [
        band({ nominal: 0.9, lower: 0.43, upper: 17 }),
        band({ nominal: 0.8 }),
        band({ months: 36, nominal: 0.8, lower: 0.5, upper: 9.5 }),
      ],
    });
    // 0,7 + 0,1 não é exatamente 0,8 em ponto flutuante.
    const t = CalibratedBand.select(tables, { months: 36, nominal: 0.7 + 0.1 });
    expect(t).not.toBeNull();
    expect(t!.months).toBe(36);
    expect((t as FairValueBandTable).lowerFactor).toBe(0.5);
    expect(CalibratedBand.select(tables, { months: 24, nominal: 0.8 })).toBeNull();
  });

  it('faixa malformada ou fora de ordem é descartada, e não inventada', () => {
    const tables = CalibratedBandCodec.decode({
      versao: 1,
      faixas: [
        band({ lower: 2, upper: 1 }),
        band({ lower: 0, upper: 1 }),
        { meses: '12' },
        'lixo',
        band({ outside: 'alto' }),
        band({ outside: null }),
      ],
    });
    expect(tables).toHaveLength(1);
    expect(tables[0]!.outOfSampleCoverage).toBeNull();
  });

  it('versão desconhecida não é lida', () => {
    expect(CalibratedBandCodec.decode({ versao: 2, faixas: [band()] })).toEqual([]);
  });
});

describe('Volatilidade do papel — a escala da forma do C2b', () => {
  /** Fechamentos que sobem e descem pelo mesmo logaritmo, [stepCount] vezes. */
  const alternating = (start: number, step: number, stepCount: number): number[] => {
    const v = [start];
    for (let i = 0; i < stepCount; i++) v.push(v[v.length - 1]! * Math.exp(i % 2 === 0 ? step : -step));
    return v;
  };

  const series = (closes: readonly number[]): PriceSeries =>
    new PriceSeries({
      ticker: Ticker.parse('PETR4'),
      points: closes.map((c, i) => new PricePoint({ date: day(2024, 1, 1).add(new Duration({ days: i })), close: c })),
    });

  it('lê só os últimos 252 pregões, pelo desvio amostral anualizado', () => {
    // 47 retornos de ±5% e depois 252 de ±1%: a janela vê só os de ±1%.
    // Média zero, variância amostral 252·0,01²/251, anualizada por √252.
    const old = alternating(100, 0.05, 47);
    const recent = alternating(old[old.length - 1]!, 0.01, 252).slice(1);
    const v = CalibratedBand.trailingVolatility(series([...old, ...recent]))!;
    expectClose(v, 0.01 * Math.sqrt(252 / 251) * Math.sqrt(252), 1e-12);
  });

  it('com menos de 120 retornos o papel fica sem volatilidade', () => {
    expect(CalibratedBand.trailingVolatility(series(alternating(10, 0.02, 119)))).toBeNull();
    expect(CalibratedBand.trailingVolatility(series(alternating(10, 0.02, 120)))).not.toBeNull();
  });

  it('fechamento não positivo não forma retorno', () => {
    // 130 retornos de ±2% e um zero no meio: os dois pares que tocam o zero
    // saem, e sobram 128 — com média e variância recalculadas sobre eles.
    const f = alternating(10, 0.02, 130);
    f[60] = 0;
    const v = CalibratedBand.trailingVolatility(series(f))!;
    const r: number[] = [];
    for (let i = 1; i < f.length; i++) if (f[i - 1]! > 0 && f[i]! > 0) r.push(Math.log(f[i]! / f[i - 1]!));
    expect(r).toHaveLength(128);
    const m = r.reduce((a, b) => a + b) / r.length;
    const s2 = r.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (r.length - 1);
    expectClose(v, Math.sqrt(s2 * 252), 1e-12);
  });
});

describe('Faixa na escala da volatilidade — item C2b', () => {
  const pkg = (
    options: { a?: unknown; b?: unknown; zLower?: unknown; zUpper?: unknown; version?: number } = {},
  ): JsonObject => ({
    versao: options.version ?? 2,
    forma: 'convergenciaNaVolatilidade',
    faixas: [
      {
        meses: 12,
        nominal: 0.9,
        a: ('a' in options ? options.a : 0.079914) as JsonObject[string],
        b: ('b' in options ? options.b : 0.027969) as JsonObject[string],
        zInferior: ('zLower' in options ? options.zLower : -1.595952) as JsonObject[string],
        zSuperior: ('zUpper' in options ? options.zUpper : 1.640003) as JsonObject[string],
        observacoes: 3517,
        primeiraCoorte: 2018,
        ultimaCoorte: 2025,
        coberturaForaDaAmostra: 0.879,
        observacoesForaDaAmostra: 3136,
      },
    ],
  });

  it('a faixa é o preço de hoje pelo centro medido e pela volatilidade', () => {
    const t = CalibratedBandCodec.decode(pkg())[0] as VolatilityBandTable;
    expect(t).toBeInstanceOf(VolatilityBandTable);
    expectClose(t.b, 0.027969, 1e-9);
    const b = CalibratedBand.of(Money.fromReais(20), t, { marketPrice: Money.fromReais(10), volatility: 0.4 })!;
    // Conta à mão: centro = 0,079914 + 0,027969·ln(2) = 0,099299;
    // borda = 10·exp(centro ± 0,40·z).
    const center = 0.079914 + 0.027969 * Math.log(2);
    expectClose(b.low.reais, 10 * Math.exp(center + 0.4 * -1.595952), 0.005);
    expectClose(b.high.reais, 10 * Math.exp(center + 0.4 * 1.640003), 0.005);
  });

  it('sem volatilidade, ou sem preço de mercado, não há faixa', () => {
    const t = CalibratedBandCodec.decode(pkg())[0]!;
    const fairValue = Money.fromReais(20);
    const price = Money.fromReais(10);
    expect(CalibratedBand.of(fairValue, t, { marketPrice: price })).toBeNull();
    expect(CalibratedBand.of(fairValue, t, { volatility: 0.4 })).toBeNull();
    expect(CalibratedBand.of(fairValue, t, { marketPrice: Money.zero, volatility: 0.4 })).toBeNull();
    expect(CalibratedBand.of(fairValue, t, { marketPrice: price, volatility: 0 })).toBeNull();
    expect(CalibratedBand.of(fairValue, t, { marketPrice: price, volatility: Number.NaN })).toBeNull();
    expect(CalibratedBand.of(Money.zero, t, { marketPrice: price, volatility: 0.4 })).toBeNull();
  });

  it('faixa malformada ou versão desconhecida não vira faixa', () => {
    expect(CalibratedBandCodec.decode(pkg({ a: '0,08' }))).toEqual([]);
    expect(CalibratedBandCodec.decode(pkg({ zLower: null }))).toEqual([]);
    // Bordas fora de ordem.
    expect(CalibratedBandCodec.decode(pkg({ zLower: 2.0, zUpper: -2.0 }))).toEqual([]);
    expect(CalibratedBandCodec.decode(pkg({ version: 3 }))).toEqual([]);
    // O pacote da volatilidade não é lido como o do justo: sem `fatorInferior`
    // a faixa da versão 1 é descartada.
    expect(CalibratedBandCodec.decode(pkg({ version: 1 }))).toEqual([]);
  });
});
