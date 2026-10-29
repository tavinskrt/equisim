import { createRequire } from 'node:module';

import { describe, expect, it } from 'vitest';

// O proxy é CommonJS, como o Cloud Functions o carrega; a lista de caminhos
// fica num módulo sem dependências justamente para ser lida aqui.
const require = createRequire(import.meta.url);
const { ALLOWED_PATHS, resolveTarget } = require('../../functions/allowlist.js') as {
  ALLOWED_PATHS: string[];
  resolveTarget: (path: string, query: string) => string | null;
};

describe('resolveTarget', () => {
  it('repassa cada caminho permitido, com a consulta', () => {
    for (const path of ALLOWED_PATHS) {
      expect(resolveTarget(path, 'symbols=PETR4')).toBe(`https://brapi.dev/api${path}?symbols=PETR4`);
    }
  });

  it('não acrescenta "?" quando não há consulta', () => {
    expect(resolveTarget('/v2/tickers', '')).toBe('https://brapi.dev/api/v2/tickers');
  });

  it('aceita um segmento a mais, como uma lista de tickers', () => {
    expect(resolveTarget('/v2/stocks/quote/PETR4,VALE3', '')).toBe('https://brapi.dev/api/v2/stocks/quote/PETR4,VALE3');
  });

  it.each([
    // Subida de diretório, crua e codificada: o `fetch` a resolveria antes de sair.
    '/v2/stocks/quote/../dividends',
    '/v2/stocks/quote/%2e%2e/dividends',
    '/v2/stocks/quote/%2E%2E/%2E%2E/v1/crypto',
    '/v2/stocks/quote/..%2fdividends',
    '/v2/stocks/quote/%2Fdividends',
    '/v2/stocks/quote\\..\\dividends',
    '/v2/tickers/../../../',
    // Mesmo prefixo, outro endpoint.
    '/v2/tickersX',
    '/v2/stocks/quoteX',
    // Fora da lista.
    '/v2/stocks/dividends',
    '/v2/crypto',
    '/',
    '',
    // Mais de um segmento extra.
    '/v2/stocks/quote/PETR4/extra',
  ])('recusa %s', (path) => {
    expect(resolveTarget(path, '')).toBeNull();
  });

  it('nunca sai do host da brapi', () => {
    for (const path of ['//evil.example/v2/tickers', '/@evil.example/v2/tickers', '/v2/tickers/@evil.example']) {
      const target = resolveTarget(path, '');
      if (target !== null) expect(new URL(target).origin).toBe('https://brapi.dev');
    }
  });
});
