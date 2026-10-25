import { describe, expect, it } from 'vitest';

import { CorporateEvents, DateTime, RawQuote } from '../../src/core';
import { expectClose, expectDate } from './helpers';

const d = (m: number, dd: number): DateTime => DateTime.utc(2024, m, dd);
const q = (date: DateTime, close: number, distribution: number): RawQuote => new RawQuote(date, close, distribution);

describe('Detecção', () => {
  it('a bonificação do BBAS3 em 2024, com os números do COTAHIST', () => {
    const quotes = [
      q(d(4, 12), 56.1, 321),
      q(d(4, 15), 56.46, 321),
      q(d(4, 16), 27.91, 322), // bonificação de 100%
      q(d(4, 17), 28.05, 322),
    ];
    const e = CorporateEvents.detect(quotes);
    expect(e.length).toBe(1);
    expect(e[0]!.factor).toBe(2);
    expectDate(e[0]!.exDate, d(4, 16));
  });

  it('provento muda o DISMES e NÃO vira evento de ações', () => {
    // As oito outras trocas de DISMES do BBAS3 em 2024: quedas de 1% a 4%.
    const quotes = [q(d(2, 21), 59.44, 319), q(d(2, 22), 58.1, 320), q(d(6, 11), 27.51, 322), q(d(6, 12), 26.54, 323)];
    expect(CorporateEvents.detect(quotes), 'e o salto de fevereiro a junho não é pregão vizinho').toEqual([]);
  });

  it('salto entre pregões distantes não é atribuído a evento', () => {
    // Papel suspenso volta com DISMES novo e preço à metade: pode ser
    // evento, pode ser mercado. Sem pregões vizinhos, não se infere.
    expect(CorporateEvents.detect([q(d(2, 22), 58.1, 320), q(d(6, 11), 27.51, 322)])).toEqual([]);
  });

  it('grupamento de 2 para 1 tem a folga larga, e não a de bonificação', () => {
    // Razão 2,08: 4% longe de 2. Com "perto de 1" medido como |fator − 1|,
    // o fator 0,5 cairia na folga de 1,5% e seria recusado.
    const e = CorporateEvents.detect([q(d(5, 2), 10.0, 50), q(d(5, 3), 20.8, 51)]);
    expect(e).toHaveLength(1);
    expectClose(e[0]!.factor, 0.5, 1e-12);
  });

  it('grupamento de 10 para 1', () => {
    const e = CorporateEvents.detect([q(d(5, 2), 1.2, 50), q(d(5, 3), 12.3, 51)]);
    expect(e).toHaveLength(1);
    expectClose(e[0]!.factor, 0.1, 1e-12);
  });

  it('queda grande SEM troca de DISMES não é evento', () => {
    expect(
      CorporateEvents.detect([q(d(3, 1), 10.0, 7), q(d(3, 2), 5.0, 7)]),
      'sem distribuição registrada, é mercado',
    ).toEqual([]);
  });

  it('crise em data ex que não está perto de fração é recusada', () => {
    // -37%: nem 1/2 (fator 2 exigiria 0,5) nem 2/3 (não listado) — fica fora.
    expect(CorporateEvents.detect([q(d(3, 1), 10.0, 7), q(d(3, 2), 6.3, 8)])).toEqual([]);
  });

  it('bonificação pequena NÃO é detectada, e isso está declarado', () => {
    // 10% de bonificação (0,909) e 8,5% de queda em data ex (0,915) estão a
    // 0,6% uma da outra. Separá-las pelo preço é impossível; a régua recusa
    // as duas em vez de acertar uma por sorte.
    const bonusShares = [q(d(3, 1), 11.0, 7), q(d(3, 2), 10.0, 8)];
    const dividend = [q(d(3, 1), 10.0, 7), q(d(3, 2), 9.15, 8)];
    expect(CorporateEvents.detect(bonusShares)).toEqual([]);
    expect(CorporateEvents.detect(dividend)).toEqual([]);
  });

  it('bonificação de 50% é detectada com folga apertada', () => {
    const e = CorporateEvents.detect([
      q(d(3, 1), 15.0, 7),
      q(d(3, 2), 10.05, 8), // 0,67 ≈ 1/1,5
    ]);
    expect(e).toHaveLength(1);
    expect(e[0]!.factor).toBe(1.5);
  });
});

describe('Ajuste', () => {
  it('divide o passado pelo fator, e o presente fica intacto', () => {
    const quotes = [q(d(4, 15), 56.46, 321), q(d(4, 16), 27.91, 322), q(d(4, 17), 28.05, 322)];
    const adjusted = CorporateEvents.adjust(quotes, CorporateEvents.detect(quotes));
    expectClose(adjusted[0]!.close, 28.23, 1e-12);
    expect(adjusted[1]!.close).toBe(27.91);
    expect(adjusted[2]!.close).toBe(28.05);
  });

  it('dois eventos se compõem', () => {
    const quotes = [
      q(d(1, 2), 100, 1),
      q(d(1, 3), 50, 2), // 1 -> 2
      q(d(1, 4), 500, 3), // 10 -> 1
    ];
    const e = CorporateEvents.detect(quotes);
    expect(e.length).toBe(2);
    const a = CorporateEvents.adjust(quotes, e);
    // 100 / 2 * 10 = 500
    expectClose(a[0]!.close, 500, 1e-9);
  });
});
