import { useState } from 'react';

import type { Ticker } from '../core';
import { cn } from './cn';

/**
 * Onde a brapi publica as logos das empresas (decisão 154): o mesmo endereço
 * que `/v2/stocks/profile` devolve em `logoUrl`, montado direto pelo código
 * para não gastar uma requisição da cota por ativo só para descobri-lo.
 */
const LOGO_BASE_URL = 'https://icons.brapi.dev/icons/';

/** Endereço da logo de um ticker na brapi. */
export function tickerLogoUrl(ticker: Ticker): string {
  return `${LOGO_BASE_URL}${ticker.value}.svg`;
}

/**
 * As duas primeiras letras da raiz do ticker — `PE` para `PETR4` —, que
 * ocupam o lugar da logo quando ela não vem. A raiz é a mesma entre as
 * classes, então `PETR3` e `PETR4` ganham a mesma marca.
 */
export function tickerInitials(ticker: Ticker): string {
  return ticker.value.slice(0, 2);
}

/**
 * Tickers cuja logo já falhou nesta sessão. Sem a lembrança, cada lista que
 * remonta tentaria de novo e piscaria a imagem quebrada antes das iniciais.
 */
const failed = new Set<string>();

const sizes = {
  sm: 'size-5 text-caption',
  md: 'size-7 text-caption',
  lg: 'size-9 text-label',
} as const;

/**
 * A logo da empresa ao lado do ticker, com as iniciais no lugar quando a
 * imagem não carrega — sem rede, ativo sem logo na fonte ou endereço mudado.
 *
 * **É decorativa**: o ticker vem sempre escrito ao lado, então a marca sai da
 * árvore de acessibilidade e o leitor de tela não lê o nome duas vezes.
 *
 * A imagem vem de outro domínio, e sai sem `Referer`: a brapi recebe só o
 * ticker pedido, e não a página do Equisim em que ele apareceu.
 */
export function TickerLogo({ ticker, size = 'md', className }: { ticker: Ticker; size?: keyof typeof sizes; className?: string }) {
  const src = tickerLogoUrl(ticker);
  const [broken, setBroken] = useState<string | null>(null);
  const [loaded, setLoaded] = useState<string | null>(null);
  const showImage = broken !== src && !failed.has(ticker.value);
  const ready = showImage && loaded === src;

  return (
    <span
      aria-hidden
      data-logo={ready ? 'imagem' : 'iniciais'}
      className={cn(
        'relative inline-flex shrink-0 select-none items-center justify-center overflow-hidden rounded-full font-semibold leading-none ring-1 ring-line',
        ready ? 'bg-white' : 'bg-sunken text-fg-2',
        sizes[size],
        className,
      )}
    >
      {!ready && tickerInitials(ticker)}
      {showImage && (
        <img
          key={src}
          src={src}
          alt=""
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
          draggable={false}
          onLoad={() => setLoaded(src)}
          onError={() => {
            failed.add(ticker.value);
            setBroken(src);
          }}
          className={cn('absolute inset-0 size-full object-contain', !ready && 'opacity-0')}
        />
      )}
    </span>
  );
}
