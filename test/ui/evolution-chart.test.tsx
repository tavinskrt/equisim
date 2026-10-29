// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { DateTime } from '../../src/core';
import { EvolutionChart, plotPoints, type Row } from '../../src/features/backtest/evolution-chart';
import { MotionProvider } from '../../src/ui/motion';
import { TooltipProvider } from '../../src/ui/tooltip';
import { comparisonOf, curve, outcomeOf } from '../app/fixtures';

afterEach(cleanup);

const day = (d: number) => DateTime.utc(2024, 1, d);
const row = (d: number, principal?: number, reserve?: number): Row => ({
  t: day(d).millisecondsSinceEpoch,
  date: day(d),
  ...(principal !== undefined ? { principal } : {}),
  ...(reserve !== undefined ? { reserve } : {}),
});

describe('Pontos da evolução no gráfico da Bklit (decisão 158)', () => {
  it('o pregão que falta no meio de uma curva é interpolado no tempo, e o tooltip continua vendo o ausente', () => {
    // Dia 3 falta à Reserva: entre 100 (dia 1) e 110 (dia 5), no dia 3, a reta passa em 105.
    const rows = [row(1, 100, 100), row(3, 102), row(5, 104, 110)];
    const { points, trimmed } = plotPoints(rows, ['principal', 'reserve']);
    expect(trimmed).toBe(false);
    expect(points.map((p) => p['reserve'])).toEqual([100, 105, 110]);
    expect(points[1]!.source.reserve).toBeUndefined();
    expect(points.map((p) => p.date.getTime())).toEqual(rows.map((r) => r.t));
  });

  it('nas pontas o gráfico fica no período comum, e avisa que cortou', () => {
    // A Reserva só começa no dia 2 e acaba no dia 4.
    const rows = [row(1, 100), row(2, 101, 100), row(3, 102, 103), row(4, 103, 104), row(5, 104)];
    const { points, trimmed } = plotPoints(rows, ['principal', 'reserve']);
    expect(trimmed).toBe(true);
    expect(points.map((p) => p.source.t)).toEqual([row(2).t, row(3).t, row(4).t]);
    expect(points.every((p) => typeof p['principal'] === 'number' && typeof p['reserve'] === 'number')).toBe(true);
  });

  it('uma carteira só não corta nada', () => {
    const rows = [row(1, 100), row(2, 101), row(3, 99)];
    const { points, trimmed } = plotPoints(rows, ['principal']);
    expect(trimmed).toBe(false);
    expect(points.map((p) => p['principal'])).toEqual([100, 101, 99]);
  });

  it('desenha nas duas grandezas, e a tabela segue com o valor exato de cada fim de mês', () => {
    const result = comparisonOf({ principal: outcomeOf('ITUB4', curve(10, 14, 250)), reserve: outcomeOf('BBAS3', curve(10, 11, 250)) });
    const { container } = render(
      <MotionProvider>
        <TooltipProvider>
          <EvolutionChart result={result} onExport={() => {}} />
        </TooltipProvider>
      </MotionProvider>,
    );
    expect(container.querySelector('.bklit-chart')).not.toBeNull();
    fireEvent.click(screen.getByRole('radio', { name: 'Patrimônio em reais' }));
    expect(container.querySelector('.bklit-chart')).not.toBeNull();
    expect(container.textContent).toContain('Patrimônio em reais');
    fireEvent.click(screen.getByRole('radio', { name: 'Tabela' }));
    const rows = within(screen.getByRole('table')).getAllByRole('row');
    expect(rows.length).toBeGreaterThan(2);
    expect(rows[1]!.textContent).toContain('R$');
  });
});
