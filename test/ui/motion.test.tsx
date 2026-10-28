// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { createMemoryRouter, MemoryRouter, RouterProvider, useLocation } from 'react-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { SectionIndex } from '../../src/features/asset/section-index';
import { assetPath, useLegacyAssetRedirect } from '../../src/features/shell/use-open-asset';
import { Ticker } from '../../src/core';
import { EngineLoading } from '../../src/ui/engine-loading';
import { CountUp, MotionProvider } from '../../src/ui/motion';
import { Segmented } from '../../src/ui/segmented';

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe('Movimento (decisão 155)', () => {
  it('a contagem é só visual: o leitor de tela lê o valor final, uma vez', () => {
    const { container } = render(
      <MotionProvider>
        <CountUp value={36.12} format={(v) => `R$ ${v.toFixed(2)}`} />
      </MotionProvider>,
    );
    const live = container.querySelector('.sr-only');
    expect(live?.textContent).toBe('R$ 36.12');
    // O número que conta sai da árvore de acessibilidade.
    expect(container.querySelector('[aria-hidden]')).not.toBeNull();
  });

  it('o controle segmentado marca a escolha mesmo sem a placa medida', () => {
    // O jsdom não faz layout: a largura medida é 0, e a opção pinta o próprio fundo.
    const onChange = vi.fn();
    render(
      <Segmented
        label="Profundidade"
        value="guided"
        onChange={onChange}
        options={[
          { value: 'guided', label: 'Essencial' },
          { value: 'analyst', label: 'Completo' },
        ]}
      />,
    );
    const on = screen.getByRole('radio', { name: 'Essencial' });
    expect(on.getAttribute('data-state')).toBe('on');
    expect(on.className).toContain('data-[state=on]:bg-raised');
    fireEvent.click(screen.getByRole('radio', { name: 'Completo' }));
    expect(onChange).toHaveBeenCalledWith('analyst');
  });

  it('o carregamento do motor anuncia um rótulo fixo e reveza as etapas só na tela', () => {
    vi.useFakeTimers();
    const { container } = render(
      <MotionProvider>
        <EngineLoading texts={['Buscando…', 'Descontando…']} label="Avaliando o ativo" interval={1000} />
      </MotionProvider>,
    );
    const output = container.querySelector('output')!;
    expect(output.getAttribute('aria-live')).toBe('polite');
    expect(output.querySelector('.sr-only')!.textContent).toBe('Avaliando o ativo');
    expect(output.querySelector('[aria-hidden]')!.textContent).toContain('Buscando…');
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    expect(output.querySelector('[aria-hidden]')!.textContent).toContain('Descontando…');
    expect(output.querySelector('.sr-only')!.textContent).toBe('Avaliando o ativo');
  });
});

describe('Página do ativo (decisão 155)', () => {
  it('o endereço do ativo é /ativo/<TICKER>', () => {
    expect(assetPath(Ticker.parse('PETR4'))).toBe('/ativo/PETR4');
  });

  it('o link antigo ?ativo= redireciona para a página, sem ficar no histórico', async () => {
    function Probe() {
      useLegacyAssetRedirect();
      const l = useLocation();
      return <p data-testid="where">{`${l.pathname}${l.search}`}</p>;
    }
    const router = createMemoryRouter(
      [
        { path: '/estudo', element: <Probe /> },
        { path: '/ativo/:ticker', element: <Probe /> },
      ],
      { initialEntries: ['/estudo?ativo=vale3'] },
    );
    render(<RouterProvider router={router} />);
    expect(await screen.findByText('/ativo/VALE3')).toBeTruthy();
    // `replace`: o endereço velho não sobra para o Voltar.
    expect(router.state.historyAction).toBe('REPLACE');
  });

  it('o ?ativo= com código inválido é ignorado, e a área fica onde está', () => {
    function Probe() {
      useLegacyAssetRedirect();
      const l = useLocation();
      return <p>{l.pathname}</p>;
    }
    render(
      <MemoryRouter initialEntries={['/estudo?ativo=nada-disso']}>
        <Probe />
      </MemoryRouter>,
    );
    expect(screen.getByText('/estudo')).toBeTruthy();
  });

  it('o índice lista só as seções que a página mostra', () => {
    render(
      <div>
        <div id="secao-a">
          <p>Leitura</p>
        </div>
        <div id="secao-b" />
        <div id="secao-c">
          <p>Régua</p>
        </div>
        <SectionIndex
          sections={[
            { id: 'secao-a', label: 'Leitura do motor' },
            { id: 'secao-b', label: 'Seus valuations' },
            { id: 'secao-c', label: 'Régua de preço' },
          ]}
        />
      </div>,
    );
    const nav = screen.getByRole('navigation', { name: 'Seções do Raio-X' });
    expect(nav.textContent).toContain('Leitura do motor');
    expect(nav.textContent).toContain('Régua de preço');
    // A seção vazia — um cartão que não tinha o que mostrar — fica de fora.
    expect(nav.textContent).not.toContain('Seus valuations');
  });
});
