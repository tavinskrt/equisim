// @vitest-environment jsdom
import { cleanup, fireEvent, render } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { Ticker } from '../../src/core';
import { TickerLogo, tickerInitials, tickerLogoUrl } from '../../src/ui/ticker-logo';

afterEach(cleanup);

describe('TickerLogo (decisão 154)', () => {
  it('pede à brapi a logo no endereço que o perfil devolve em logoUrl', () => {
    // O mesmo endereço de test/fixtures/brapi_profile_petr4.json.
    expect(tickerLogoUrl(Ticker.parse('PETR4'))).toBe('https://icons.brapi.dev/icons/PETR4.svg');
  });

  it('as iniciais são da raiz, e as classes de uma empresa as dividem', () => {
    expect(tickerInitials(Ticker.parse('PETR4'))).toBe('PE');
    expect(tickerInitials(Ticker.parse('PETR3'))).toBe('PE');
    expect(tickerInitials(Ticker.parse('TAEE11'))).toBe('TA');
  });

  it('mostra as iniciais até a imagem carregar, e a imagem depois', () => {
    const { container } = render(<TickerLogo ticker={Ticker.parse('VALE3')} />);
    const mark = container.querySelector('[data-logo]')!;
    const img = container.querySelector('img')!;
    expect(mark.getAttribute('data-logo')).toBe('iniciais');
    expect(mark.textContent).toBe('VA');
    expect(img.getAttribute('src')).toBe('https://icons.brapi.dev/icons/VALE3.svg');

    fireEvent.load(img);
    expect(mark.getAttribute('data-logo')).toBe('imagem');
    expect(mark.textContent).toBe('');
  });

  it('é decorativa e não manda Referer para a brapi', () => {
    const { container } = render(<TickerLogo ticker={Ticker.parse('ITUB4')} />);
    expect(container.querySelector('[data-logo]')!.getAttribute('aria-hidden')).toBe('true');
    const img = container.querySelector('img')!;
    expect(img.getAttribute('alt')).toBe('');
    expect(img.getAttribute('referrerpolicy')).toBe('no-referrer');
    expect(img.getAttribute('loading')).toBe('lazy');
  });

  it('cai nas iniciais quando a imagem falha, e não tenta de novo na sessão', () => {
    const ticker = Ticker.parse('BBAS3');
    const first = render(<TickerLogo ticker={ticker} />);
    fireEvent.error(first.container.querySelector('img')!);
    expect(first.container.querySelector('img')).toBeNull();
    expect(first.container.textContent).toBe('BB');
    first.unmount();

    const again = render(<TickerLogo ticker={ticker} />);
    expect(again.container.querySelector('img')).toBeNull();
    expect(again.container.textContent).toBe('BB');
  });
});
