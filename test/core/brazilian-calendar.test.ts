import { describe, expect, it } from 'vitest';

import { BrazilianCalendar, DateTime } from '../../src/core';
import { expectDate } from './helpers';

const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

/** Dias úteis da liquidação ao vencimento, como o Tesouro conta. */
const treasuryBusinessDays = (base: DateTime, maturity: DateTime): number =>
  BrazilianCalendar.businessDaysBetween(BrazilianCalendar.treasurySettlement(base), maturity, { knownAt: base });

describe('Feriados', () => {
  it('Páscoa pelo algoritmo gregoriano', () => {
    expectDate(BrazilianCalendar.easter(2024), d(2024, 3, 31));
    expectDate(BrazilianCalendar.easter(2025), d(2025, 4, 20));
    expectDate(BrazilianCalendar.easter(2026), d(2026, 4, 5));
  });

  it('Carnaval, Paixão e Corpus Christi andam com a Páscoa', () => {
    expect(BrazilianCalendar.isBusinessDay(d(2024, 2, 12))).toBe(false);
    expect(BrazilianCalendar.isBusinessDay(d(2024, 2, 13))).toBe(false);
    expect(BrazilianCalendar.isBusinessDay(d(2024, 2, 14)), 'quarta de cinzas é útil no calendário nacional').toBe(true);
    expect(BrazilianCalendar.isBusinessDay(d(2024, 3, 29))).toBe(false);
    expect(BrazilianCalendar.isBusinessDay(d(2024, 5, 30))).toBe(false);
  });

  it('fim de semana não é útil', () => {
    expect(BrazilianCalendar.isBusinessDay(d(2026, 9, 12))).toBe(false);
    expect(BrazilianCalendar.isBusinessDay(d(2026, 9, 13))).toBe(false);
    expect(BrazilianCalendar.isBusinessDay(d(2026, 9, 14))).toBe(true);
  });

  it('o 20 de novembro só é feriado para quem já conhecia a lei', () => {
    // Quinta-feira, 20/11/2025.
    expect(BrazilianCalendar.isBusinessDay(d(2025, 11, 20))).toBe(false);
    expect(BrazilianCalendar.isBusinessDay(d(2025, 11, 20), { knownAt: d(2022, 6, 9) }), 'Lei 14.759 é de 21/12/2023').toBe(
      true,
    );
    expect(BrazilianCalendar.isBusinessDay(d(2023, 11, 20)), 'antes de 2024 não era feriado nacional').toBe(true);
  });
});

describe('Contagem', () => {
  it('[início, fim): o primeiro dia conta, o último não', () => {
    // Segunda 14/09/2026 a segunda 21/09/2026: cinco dias úteis.
    expect(BrazilianCalendar.businessDaysBetween(d(2026, 9, 14), d(2026, 9, 21))).toBe(5);
    expect(BrazilianCalendar.businessDaysBetween(d(2026, 9, 21), d(2026, 9, 14))).toBe(0);
  });

  it('a liquidação pula 24/12 e 31/12', () => {
    expectDate(BrazilianCalendar.treasurySettlement(d(2025, 12, 23)), d(2025, 12, 26));
    expectDate(BrazilianCalendar.treasurySettlement(d(2025, 12, 30)), d(2026, 1, 2));
    expectDate(BrazilianCalendar.treasurySettlement(d(2026, 9, 11)), d(2026, 9, 14), 'sexta liquida na segunda');
  });
});

describe('Conferido contra o PU do Tesouro', () => {
  // `du` implícito = 252 · ln(1000 ÷ PU) ÷ ln(1 + taxa), das LTN do arquivo
  // de preços do Tesouro Direto. Arredondado ao dia.
  it('data-base de hoje', () => {
    expect(treasuryBusinessDays(d(2026, 9, 10), d(2027, 1, 1))).toBe(76);
    expect(treasuryBusinessDays(d(2026, 9, 10), d(2029, 1, 1))).toBe(575);
    expect(treasuryBusinessDays(d(2026, 9, 10), d(2032, 1, 1))).toBe(1328);
  });

  it('virada de ano, onde a liquidação importa', () => {
    expect(treasuryBusinessDays(d(2025, 12, 23), d(2026, 1, 1))).toBe(4);
    expect(treasuryBusinessDays(d(2025, 12, 30), d(2027, 1, 1))).toBe(249);
  });

  it('antes da lei, o 20 de novembro dos anos futuros ainda era útil', () => {
    expect(treasuryBusinessDays(d(2022, 6, 9), d(2025, 1, 1))).toBe(644);
    expect(treasuryBusinessDays(d(2022, 6, 9), d(2029, 1, 1))).toBe(1647);
    expect(treasuryBusinessDays(d(2019, 3, 15), d(2025, 1, 1))).toBe(1458);
  });
});

describe('Pregão da B3 — data ex', () => {
  it('24/12 e 31/12 são dias úteis e não têm pregão', () => {
    expect(BrazilianCalendar.isBusinessDay(d(2014, 12, 31))).toBe(true);
    expect(BrazilianCalendar.isTradingDay(d(2014, 12, 31))).toBe(false);
    expect(BrazilianCalendar.isTradingDay(d(2025, 12, 24))).toBe(false);
    expect(BrazilianCalendar.isTradingDay(d(2025, 12, 23))).toBe(true);
  });

  it('data-com em 30/12 tem data ex no primeiro pregão de janeiro', () => {
    expectDate(BrazilianCalendar.nextTradingSession(d(2014, 12, 30)), d(2015, 1, 2));
    expectDate(BrazilianCalendar.nextTradingSession(d(2025, 9, 12)), d(2025, 9, 15));
  });
});
