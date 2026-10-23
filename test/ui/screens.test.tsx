// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  CapmInputs,
  FundamentalsSnapshot,
  Ticker,
  ValuationCascade,
  ValuationInputs,
} from '../../src/core';
import { emphasized } from '../../src/features/asset/caveats-card';
import { PriceRuler } from '../../src/features/asset/price-ruler';
import { PerAssetCard } from '../../src/features/backtest/per-asset-card';
import { SideBySidePortfolios } from '../../src/features/backtest/portfolio-metrics';
import { bridgeOf } from '../../src/features/backtest/wealth-bridge';
import { EventCard, katexSafe } from '../../src/features/logs/event-card';
import { formatAuditNumber } from '../../src/features/logs/format';
import { JsonPanel } from '../../src/features/logs/json-tree';
import { TooltipProvider } from '../../src/ui/tooltip';
import { day } from '../core/helpers';
import { curve, outcomeOf } from '../app/fixtures';
import { testRuntime } from '../app/harness';

afterEach(() => {
  cleanup();
  AuditRecorder.detach();
});

const wrap = (node: ReactNode) =>
  render(
    <MemoryRouter>
      <TooltipProvider>{node}</TooltipProvider>
    </MemoryRouter>,
  );

/** Uma avaliação real, pelo caminho de produção: a cascata emite, o coletor guarda. */
function valuationEvent(): AuditEvent {
  const events: AuditEvent[] = [];
  AuditRecorder.attach((e) => events.push(e));
  const ticker = Ticker.parse('PETR4');
  const fundamentals: FundamentalsSnapshot[] = [];
  for (let year = 2016; year <= 2025; year++) {
    const k = year - 2015;
    fundamentals.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(year, 12, 31),
        netIncome: 1000 * k,
        ebit: 1400 * k,
        ebitda: 1800 * k,
        incomeBeforeTax: 1300 * k,
        incomeTaxExpense: -300 * k,
        interestExpense: 120,
        operatingCashFlow: 1600 * k,
        freeCashFlow: 1200 * k,
        shortTermDebt: 400,
        longTermDebt: 1600,
        cash: 300,
        nopat: 1000 * k,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 20000,
        bookValuePerShare: 8 * k,
        enterpriseToEbitda: 6,
      }),
    );
  }
  ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 8, 20),
      fundamentals,
      marketPrice: 20,
      capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055 }),
    }),
  );
  const event = events.find((e) => e.endpoint === '/core/valuation/PETR4');
  expect(event, 'a cascata não emitiu a avaliação').toBeDefined();
  return event!;
}

describe('Painel de auditoria', () => {
  it('o número sai em pt-BR, sem a ambiguidade de dois pontos', () => {
    expect(formatAuditNumber(1234.5)).toBe('1.234,50');
    expect(formatAuditNumber(1_234_567)).toBe('1.234.567');
    expect(formatAuditNumber(0.1065)).toBe('0,106500');
    expect(formatAuditNumber(Number.NaN)).toBe('NaN');
  });

  it('palavra acentuada vai para \\text, e o resto do LaTeX fica intacto', () => {
    expect(katexSafe('N_{ações} \\cdot P_{mkt}')).toBe('N_{\\text{ações}} \\cdot P_{mkt}');
    expect(katexSafe('K_e = R_f + \\beta (R_m - R_f)')).toBe('K_e = R_f + \\beta (R_m - R_f)');
  });

  it('o evento recolhido não monta o conteúdo; aberto, traz as três seções', () => {
    const event = valuationEvent();
    const { container } = wrap(<EventCard event={event} ordinal={1} />);
    expect(screen.getByText('/core/valuation/PETR4')).toBeTruthy();
    expect(screen.queryByText('SEÇÃO A')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: /\/core\/valuation\/PETR4/ }));

    for (const letter of ['A', 'B', 'C']) expect(screen.getByText(`SEÇÃO ${letter}`)).toBeTruthy();
    // Uma fórmula desenhada pelo KaTeX por cálculo — nenhuma caiu no texto cru.
    expect(container.querySelectorAll('.katex-display')).toHaveLength(event.calculations.length);
    expect(container.querySelectorAll('pre')).toHaveLength(0);
  });

  it('o JSON mostra chave e valor, e o texto longo quebra em vez de vazar', () => {
    const { container } = wrap(<JsonPanel label="outputPayload" value={{ status: 'falha', motivo: 'x'.repeat(400) }} />);
    expect(screen.getByText('outputPayload')).toBeTruthy();
    expect(container.textContent).toContain('status');
    expect(container.querySelector('.whitespace-pre-wrap')).not.toBeNull();
  });
});

describe('Raio-X', () => {
  it('cada faixa da régua leva o horizonte escrito, e não só a cor', () => {
    wrap(
      <PriceRuler
        marks={[
          { key: 'mercado', short: 'Mercado', label: 'Preço de mercado', value: 30, color: 'var(--fg)' },
          { key: 'justo', short: 'Justo', label: 'Preço justo do motor', value: 36, color: 'var(--chart-1)' },
        ]}
        bands={[
          { key: '12', short: '12 m', label: 'Faixa de 12 meses', low: 25, high: 41 },
          { key: '36', short: '36 m', label: 'Faixa de 36 meses', low: 20, high: 52 },
        ]}
      />,
    );
    expect(screen.getByText('12 m')).toBeTruthy();
    expect(screen.getByText('36 m')).toBeTruthy();
    // A legenda é também a tabela dos valores.
    // O Intl separa "R$" do número com espaço inseparável.
    expect(screen.getByText('Faixa de 36 meses').closest('div')!.textContent!.replace(/\s/g, ' ')).toContain('R$ 20,00 a R$ 52,00');
  });

  it('o negrito do aviso do núcleo vira <strong>, sem os asteriscos', () => {
    const { container } = render(<p>{emphasized('desconta despesa **futura**, que se realiza')}</p>);
    expect(container.querySelector('strong')!.textContent).toBe('futura');
    expect(container.textContent).not.toContain('**');
  });
});

describe('Backtest', () => {
  testRuntime();
  const principal = outcomeOf('ITUB4', curve(10, 14, 250));
  const reserve = outcomeOf('BBAS3', curve(10, 11, 250));

  it('a ponte fecha em centavos: aportado − custos + ganho = final', () => {
    for (const o of [principal, reserve]) {
      const b = bridgeOf('x', 'red', o);
      expect(b.contributed - b.costs + b.marketGain).toBe(b.final);
    }
  });

  it('o Essencial mostra cinco métricas; o Completo, todas', () => {
    const essential = wrap(<SideBySidePortfolios principal={principal} reserve={reserve} essential />);
    const few = within(essential.container).getAllByRole('row').length;
    cleanup();
    const full = wrap(<SideBySidePortfolios principal={principal} reserve={reserve} />);
    const many = within(full.container).getAllByRole('row').length;
    // Cinco linhas de métrica mais a do cabeçalho.
    expect(few).toBe(6);
    expect(many).toBeGreaterThan(few);
  });

  it('a quantidade por ativo é de ações inteiras, e não de cotas', () => {
    const { container } = wrap(<PerAssetCard principal={principal} reserve={reserve} />);
    expect(container.textContent).toMatch(/\d ações ·/);
    expect(container.textContent).not.toContain('cotas');
  });
});
