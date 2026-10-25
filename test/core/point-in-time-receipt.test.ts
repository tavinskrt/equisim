import { describe, expect, it } from 'vitest';

import { Duration, FundamentalsSnapshot, PointInTimeView, Ticker, type DateTime } from '../../src/core';
import { day, expectDate } from './helpers';

function s(end: DateTime, received?: DateTime): FundamentalsSnapshot {
  return new FundamentalsSnapshot({
    ticker: Ticker.parse('TEST3'),
    fiscalPeriodEnd: end,
    receiptDate: received ?? null,
    netIncome: 100,
  });
}

describe('Publicidade pela data observada', () => {
  const end2024 = day(2024, 12, 31);
  // O Banco do Brasil entregou o DFP de 2024 em 19/02/2025.
  const received = day(2025, 2, 19);

  it('com DT_RECEB, o exercício é público no dia seguinte ao recebimento', () => {
    const x = s(end2024, received);
    expect(new PointInTimeView(day(2025, 2, 18)).isPublished(x)).toBe(false);
    expect(new PointInTimeView(day(2025, 2, 19)).isPublished(x)).toBe(true);
    expect(new PointInTimeView(day(2025, 3, 1)).isPublished(x)).toBe(true);
  });

  it('a presunção de 90 dias teria atrasado em 40 dias', () => {
    // Sem a data, o corte cai em 31/03/2025; com ela, 19/02/2025.
    const withoutDate = s(end2024);
    const withDate = s(end2024, received);
    const at = new PointInTimeView(day(2025, 3, 15));
    expect(at.isPublished(withoutDate)).toBe(false);
    expect(at.isPublished(withDate), 'o documento existia havia quase um mês').toBe(true);
  });

  it('a data observada também ATRASA quando a companhia demora', () => {
    // O máximo medido foi 472 dias. A presunção teria liberado cedo demais.
    const lateFiling = s(end2024, day(2026, 4, 17));
    const at = new PointInTimeView(day(2025, 6, 1));
    expect(at.isPublished(lateFiling)).toBe(false);
    expect(at.isPublished(s(end2024)), 'sem a data, a presunção o daria por público').toBe(true);
  });

  it('sem data, o comportamento antigo é preservado', () => {
    const x = s(end2024);
    expect(new PointInTimeView(day(2025, 3, 30)).isPublished(x)).toBe(false);
    expect(new PointInTimeView(day(2025, 4, 1)).isPublished(x)).toBe(true);
  });

  it('a defasagem presumida continua configurável', () => {
    const x = s(end2024);
    const short = new PointInTimeView(day(2025, 2, 1), { publicationLag: new Duration({ days: 30 }) });
    expect(short.isPublished(x)).toBe(true);
  });

  it('a série mistura os dois regimes sem se confundir', () => {
    const all = [
      s(day(2022, 12, 31)),
      s(day(2023, 12, 31), day(2024, 3, 20)),
      s(day(2024, 12, 31), day(2025, 2, 19)),
    ];
    const at = new PointInTimeView(day(2025, 3, 1));
    const visible = at.published(all);
    expect(visible.length).toBe(3);
    expectDate(visible[visible.length - 1]!.fiscalPeriodEnd, day(2024, 12, 31));

    const before = new PointInTimeView(day(2025, 1, 10)).published(all);
    expect(before.length, 'o de 2024 ainda não fora recebido').toBe(2);
  });
});
