import { afterEach, describe, expect, it } from 'vitest';

import { type AuditEvent, AuditRecorder } from '../../src/core';
import { AuditNetworkInterceptor, describeBody } from '../../src/audit/audit-network-interceptor';
import { clientWith, FixtureTransport } from '../data/fixture-transport';

/** Cliente de produção com o interceptador de auditoria no fim da cadeia, como a raiz de dependências monta. */
function auditedClient(fixture: FixtureTransport) {
  const client = clientWith(fixture);
  client.pipeline.interceptors.push(new AuditNetworkInterceptor());
  return client;
}

function listen(): AuditEvent[] {
  const events: AuditEvent[] = [];
  AuditRecorder.attach((e) => events.push(e));
  return events;
}

afterEach(() => AuditRecorder.detach());

describe('AuditNetworkInterceptor', () => {
  it('sem ninguém ouvindo, não monta evento nenhum', async () => {
    const fixture = new FixtureTransport({ bodies: { '/v2/stocks/quote': '{"ok":true}' } });
    const events: AuditEvent[] = [];
    await auditedClient(fixture).getJson('https://brapi.dev/api/v2/stocks/quote');
    expect(events).toHaveLength(0);
  });

  it('a resposta pequena entra desserializada, com o status e o tamanho', async () => {
    const events = listen();
    const fixture = new FixtureTransport({ bodies: { '/v2/stocks/quote': '{"results":[1,2]}' } });
    await auditedClient(fixture).getJson('https://brapi.dev/api/v2/stocks/quote', { query: { symbols: 'PETR4' } });
    expect(events).toHaveLength(1);
    const e = events[0]!;
    expect(e.endpoint).toBe('/api/v2/stocks/quote');
    expect(e.inputPayload['method']).toBe('GET');
    expect(e.inputPayload['queryParameters']).toEqual({ symbols: 'PETR4' });
    expect(e.inputPayload['retryAttempt']).toBe(0);
    expect(e.outputPayload['statusCode']).toBe(200);
    expect(e.outputPayload['sizeBytes']).toBe(17);
    expect(e.outputPayload['body']).toEqual({ results: [1, 2] });
    expect(e.calculations, 'ida à rede não tem conta a decompor').toHaveLength(0);
  });

  it('o token não chega ao painel, nem na URL nem nos parâmetros', async () => {
    const events = listen();
    const fixture = new FixtureTransport({ bodies: { '/v2/stocks/quote': '{}' } });
    await auditedClient(fixture).getJson('https://brapi.dev/api/v2/stocks/quote', { query: { token: 'segredo-123' } });
    const e = events[0]!;
    expect(JSON.stringify(e.toJson())).not.toContain('segredo-123');
    expect((e.inputPayload['queryParameters'] as Record<string, string>)['token']).toBe('****');
    expect(e.inputPayload['url']).toContain('token=****');
  });

  it('a resposta grande é cortada no teto, e o corte se declara', () => {
    const big = `"${'x'.repeat(AuditNetworkInterceptor.bodyPreviewLimit + 10)}"`;
    const d = describeBody(big);
    expect(d['truncated']).toBe(true);
    expect(d['sizeBytes']).toBe(big.length);
    expect(String(d['bodyPreview'])).toContain(`a resposta completa tem ${big.length} caracteres`);
    expect(d['body']).toBeUndefined();
  });

  it('corpo que não é JSON entra como texto', () => {
    expect(describeBody('<html>erro</html>')).toEqual({ sizeBytes: 17, body: '<html>erro</html>' });
  });

  it('a repetição aparece como a tentativa que valeu', async () => {
    const events = listen();
    const fixture = new FixtureTransport({
      statusSequence: { '/v2/stocks/quote': [429, 200] },
      bodies: { '/v2/stocks/quote': '{"ok":1}' },
    });
    const r = await auditedClient(fixture).getJson('https://brapi.dev/api/v2/stocks/quote');
    expect(r.isOk).toBe(true);
    // O 429 é resolvido pela repetição antes de chegar ao fim da cadeia: o
    // painel mostra a tentativa que trouxe o dado, e ela diz que é a segunda.
    expect(events).toHaveLength(1);
    expect(events[0]!.inputPayload['retryAttempt']).toBe(1);
    expect(events[0]!.outputPayload['statusCode']).toBe(200);
  });

  it('a falha que sobra também é registrada, com o motivo', async () => {
    const events = listen();
    const fixture = new FixtureTransport({ transportErrors: { '/v2/stocks/quote': 'connectionError' } });
    const r = await auditedClient(fixture).getJson('https://brapi.dev/api/v2/stocks/quote');
    expect(r.isErr).toBe(true);
    const last = events.at(-1)!;
    expect(last.outputPayload['statusCode']).toBeNull();
    expect(last.outputPayload['error']).toBe('falha de transporte forçada');
  });
});
