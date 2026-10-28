// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { AccumulationChart } from '../../src/features/goal/accumulation-chart';
import { MotionProvider } from '../../src/ui/motion';
import { demoGoal } from '../app/fixtures';

afterEach(cleanup);

const rates = [
  { key: 'exigido', label: 'Exigido', annual: 0.2, color: 'var(--chart-1)' },
  { key: 'aportes', label: 'Só os aportes', annual: 0, color: 'var(--fg-3)', dashed: true },
];

describe('Curva de acumulação no gráfico da Bklit (decisão 156)', () => {
  it('desenha sem quebrar, com a legenda e a meta', () => {
    const { container } = render(
      <MotionProvider>
        <AccumulationChart goal={demoGoal} rates={rates} />
      </MotionProvider>,
    );
    expect(screen.getByText('Curva de acumulação')).toBeTruthy();
    expect(container.querySelector('.bklit-chart')).not.toBeNull();
    expect(container.textContent).toContain('Exigido (20,0% a.a.)');
    expect(container.textContent).toContain('Meta');
  });

  it('a tabela continua sendo a via do valor exato: um ano por linha, até o prazo', () => {
    render(
      <MotionProvider>
        <AccumulationChart goal={demoGoal} rates={rates} />
      </MotionProvider>,
    );
    fireEvent.click(screen.getByRole('radio', { name: 'Tabela' }));
    const table = screen.getByRole('table');
    const rows = within(table).getAllByRole('row');
    // Cabeçalho mais os anos 0 a 10.
    expect(rows).toHaveLength(12);
    expect(rows[rows.length - 1]!.textContent).toContain('10 anos e 0 meses');
    // Sem rendimento, o patrimônio final é o aportado: R$ 10 mil + 120 × R$ 1 mil.
    expect(rows[rows.length - 1]!.textContent).toContain('130');
  });
});
