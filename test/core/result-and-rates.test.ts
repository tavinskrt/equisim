import { describe, expect, it } from 'vitest';

import {
  DataQualityFailure,
  Duration,
  Err,
  InsufficientData,
  InvalidInput,
  Ok,
  PricePoint,
  PriceSeries,
  RatePoint,
  RateSeries,
  type Result,
  StateError,
  Ticker,
  TimeBasis,
} from '../../src/core';
import { day, expectClose, expectDate } from './helpers';

describe('Result', () => {
  it('Ok carrega valor e não carrega falha', () => {
    const result: Result<number> = new Ok(42);
    expect(result.isOk).toBe(true);
    expect(result.isErr).toBe(false);
    expect(result.valueOrNull).toBe(42);
    expect(result.failureOrNull).toBeNull();
    expect(result.unwrap()).toBe(42);
  });

  it('Err carrega falha e não carrega valor', () => {
    const result: Result<number> = new Err(new InvalidInput('erro'));
    expect(result.isErr).toBe(true);
    expect(result.valueOrNull).toBeNull();
    expect(result.failureOrNull).toBeInstanceOf(InvalidInput);
    expect(() => result.unwrap()).toThrow(StateError);
  });

  it('map transforma apenas o sucesso', () => {
    expect(new Ok(2).map((v) => v * 3).unwrap()).toBe(6);
    const failure: Result<number> = new Err(new InvalidInput('x'));
    expect(failure.map((v) => v * 3).isErr).toBe(true);
  });

  it('flatMap encadeia sem aninhar', () => {
    const chained = new Ok(2).flatMap((v) => new Ok(`valor ${v}`));
    expect(chained.unwrap()).toBe('valor 2');
    const shortCircuit = new Err<number>(new InvalidInput('x')).flatMap(() => new Ok('nunca'));
    expect(shortCircuit.isErr).toBe(true);
  });

  it('fold trata os dois lados', () => {
    expect(new Ok(5).fold((v) => `ok ${v}`, () => 'erro')).toBe('ok 5');
    expect(new Err<number>(new InvalidInput('x')).fold(() => 'ok', (f) => `erro: ${f.message}`)).toBe('erro: x');
  });

  it('getOrElse devolve o padrão em caso de falha', () => {
    expect(new Ok(1).getOrElse(99)).toBe(1);
    expect(new Err<number>(new InvalidInput('x')).getOrElse(99)).toBe(99);
  });

  it('falhas carregam contexto tipado', () => {
    expect(new DataQualityFailure('divergência', { observedDeviation: 0.38 }).observedDeviation).toBe(0.38);
    expect(new InsufficientData('faltou', { subject: 'PETR4' }).subject).toBe('PETR4');
  });
});

describe('RateSeries', () => {
  /**
   * Série de [n] pontos com a mesma taxa.
   *
   * **Não há como desalinhar** desde a decisão 59: o ponto carrega a data e a
   * taxa juntas, e o construtor por listas paralelas deixou de existir.
   */
  const seriesOf = (n: number, rate: number, basis: TimeBasis = TimeBasis.businessDaily): RateSeries => {
    const points: RatePoint[] = [];
    for (let i = 0; i < n; i++) points.push(new RatePoint({ date: day(2025, 1, 1).add(new Duration({ days: i })), rate }));
    return new RateSeries(points, { basis });
  };

  it('acumula fator composto de taxas diárias', () => {
    // 1,001³ − 1 = 0,003003001
    expectClose(seriesOf(3, 0.001).accumulated, 0.003003001, 1e-12);
  });

  it('anualiza pelo número de períodos por ano', () => {
    // 252 pregões a 0,0374% ao dia ≈ 9,9% ao ano.
    const series = seriesOf(252, 0.000374);
    expectClose(series.annualized(), series.accumulated, 1e-9);
    expectClose(series.annualized(), 0.0988, 1e-3);
  });

  it('não há como desalinhar data e taxa', () => {
    // O construtor por listas paralelas deixou de existir (decisão 59): a
    // série guarda um ponto por período, e o repositório de cache — que
    // iterava `rates` indexando `dates` — passou a iterar pontos.
    const s = seriesOf(3, 0.001);
    expect(s.points).toHaveLength(3);
    expect(s.dates).toHaveLength(3);
    expect(s.rates).toHaveLength(3);
    expect(s.dates.length).toBe(s.rates.length);
  });

  it('a cauda pega os últimos pontos, e nunca mais que existem', () => {
    const s = seriesOf(10, 0.001);
    expect(s.tail(3).points).toHaveLength(3);
    const tail = s.tail(3).points;
    expectDate(tail[tail.length - 1]!.date, s.points[s.points.length - 1]!.date);
    expect(s.tail(50).points).toHaveLength(10);
    expect(s.tail(0).points).toEqual([]);
  });

  it('a base vem da série, e não do chamador', () => {
    // Errar a base desloca o resultado em ordens de grandeza, e quem sabe a
    // frequência é quem construiu a série. Decisão 59.
    const daily = seriesOf(12, 0.01, TimeBasis.businessDaily);
    const monthly = seriesOf(12, 0.01, TimeBasis.monthly);
    expectClose(daily.accumulated, monthly.accumulated, 1e-12, 'o acumulado é o mesmo: o que muda é só a base');
    // Doze períodos a 1%: em base mensal é um ano inteiro; em base 252,
    // é um mês e pouco, e anualiza para muito mais.
    expectClose(monthly.annualized(), monthly.accumulated, 1e-9);
    expect(daily.annualized()).toBeGreaterThan(monthly.annualized() * 5);
  });

  it('série vazia não quebra', () => {
    const empty = new RateSeries([]);
    expect(empty.isEmpty).toBe(true);
    expect(empty.accumulated).toBe(0.0);
    expect(empty.annualized()).toBe(0.0);
  });

  it('meio ano de CDI anualiza para o dobro do acumulado, composto', () => {
    const series = seriesOf(126, 0.000374);
    const accumulated = series.accumulated;
    // Anualizar meio ano deve dar aproximadamente (1+acum)² − 1.
    expectClose(series.annualized(), (1 + accumulated) * (1 + accumulated) - 1, 1e-6);
  });
});

describe('PriceSeries', () => {
  const petr = Ticker.parse('PETR4');
  const pt = (d: number, close: number): PricePoint => new PricePoint({ date: day(2024, 1, d), close });

  it('ordena cronologicamente mesmo com entrada fora de ordem', () => {
    const series = new PriceSeries({ ticker: petr, points: [pt(3, 12), pt(1, 10), pt(2, 11)] });
    expectDate(series.firstDate, day(2024, 1, 1));
    expectDate(series.points[series.points.length - 1]!.date, day(2024, 1, 3));
    expect(series.points.map((p) => p.close)).toEqual([10, 11, 12]);
  });

  it('closeAsOf faz forward fill em dia sem pregão', () => {
    const series = new PriceSeries({ ticker: petr, points: [pt(2, 10), pt(5, 12)] });
    // Dias 3 e 4 sem pregão: mantém o último fechamento conhecido.
    expect(series.closeAsOf(day(2024, 1, 3))).toBe(10);
    expect(series.closeAsOf(day(2024, 1, 4))).toBe(10);
    expect(series.closeAsOf(day(2024, 1, 5))).toBe(12);
    expect(series.closeAsOf(day(2024, 1, 6))).toBe(12);
  });

  it('closeAsOf devolve nulo antes do primeiro pregão', () => {
    const series = new PriceSeries({ ticker: petr, points: [pt(2, 10)] });
    expect(series.closeAsOf(day(2023, 12, 31))).toBeNull();
  });

  it('closeOn exige a data exata', () => {
    const series = new PriceSeries({ ticker: petr, points: [pt(2, 10)] });
    expect(series.closeOn(day(2024, 1, 2))).toBe(10);
    expect(series.closeOn(day(2024, 1, 3))).toBeNull();
  });
});
