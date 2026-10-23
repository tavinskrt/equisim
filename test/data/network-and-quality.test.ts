import { describe, expect, it } from 'vitest';

import { DataQualityFailure, InvalidInput, SeededRandom } from '../../src/core';
import { ApiConfig, BrapiMode } from '../../src/data/config/api-config';
import { getRequest, HttpPipeline, type HttpRequest } from '../../src/data/network/http';
import { AuthInterceptor, RetryInterceptor, SanitizedLogInterceptor } from '../../src/data/network/interceptors';
import { clientWith, FixtureTransport } from './fixture-transport';

function runWith(config: ApiConfig, url = 'https://brapi.dev/api/v2/stocks/quote'): HttpRequest {
  const request = getRequest(url);
  new AuthInterceptor(config).onRequest(request);
  return request;
}

describe('AuthInterceptor', () => {
  it('modo direto injeta o token', () => {
    const request = runWith(
      new ApiConfig({ mode: BrapiMode.direct, brapiBaseUrl: 'https://brapi.dev/api', brapiToken: 'segredo', bcbBaseUrl: '' }),
    );
    expect(request.headers['Authorization']).toBe('Bearer segredo');
  });

  it('modo proxy não envia credencial alguma', () => {
    const request = runWith(
      new ApiConfig({
        mode: BrapiMode.proxied,
        brapiBaseUrl: 'https://proxy.exemplo/api',
        brapiToken: 'nunca-usado',
        bcbBaseUrl: '',
      }),
      'https://proxy.exemplo/api/v2/stocks/quote',
    );
    expect('Authorization' in request.headers, 'com proxy o token vive só no servidor').toBe(false);
  });

  it('não manda a credencial para host de terceiro', () => {
    const request = runWith(
      new ApiConfig({
        mode: BrapiMode.direct,
        brapiBaseUrl: 'https://brapi.dev/api',
        brapiToken: 'segredo',
        bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
      }),
      'https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados',
    );
    expect(
      'Authorization' in request.headers,
      'o Banco Central não assina a brapi, e o cabeçalho extra reprova a verificação prévia do CORS no navegador',
    ).toBe(false);
  });

  it('GET sem corpo não declara Content-Type', () => {
    const request = runWith(
      new ApiConfig({ mode: BrapiMode.direct, brapiBaseUrl: 'https://brapi.dev/api', brapiToken: 'segredo', bcbBaseUrl: '' }),
    );
    expect(
      'Content-Type' in request.headers,
      'sem corpo o cabeçalho não descreve nada e ainda força o OPTIONS de verificação',
    ).toBe(false);
  });
});

describe('RetryInterceptor — espaçamento exponencial com ruído', () => {
  const pipeline = new HttpPipeline(async () => {
    throw new Error('não usado');
  }, () => true);

  it('o teto da espera dobra a cada tentativa', () => {
    const rng = new SeededRandom(1);
    const interceptor = new RetryInterceptor({ pipeline, baseDelayMs: 100, random: () => rng.nextDouble() });
    // Com jitter completo a espera é sorteada em [0, base·2ⁿ]; o que se
    // verifica é o teto, não o valor exato.
    for (let attempt = 0; attempt < 4; attempt++) {
      const ceiling = 100 * 2 ** attempt;
      for (let i = 0; i < 50; i++) {
        const delay = interceptor.delayFor(attempt);
        expect(delay).toBeLessThanOrEqual(ceiling);
        expect(delay).toBeGreaterThanOrEqual(0);
      }
    }
  });

  it('o ruído evita que chamadas simultâneas colidam de novo', () => {
    const rng = new SeededRandom(7);
    const interceptor = new RetryInterceptor({ pipeline, baseDelayMs: 500, random: () => rng.nextDouble() });
    const delays = Array.from({ length: 20 }, () => interceptor.delayFor(2));
    expect(new Set(delays).size, 'esperas idênticas recriariam a colisão que causou o 429').toBeGreaterThan(1);
  });
});

describe('RetryInterceptor — a repetição de verdade', () => {
  // O grupo acima prova a MATEMÁTICA da espera. Nada ali força uma requisição
  // bloqueada a ser reemitida — e falha de não reenviar derruba o usuário.
  // Estes testes exercitam o caminho inteiro: status 429, erro, `onError`,
  // nova busca.

  it('429 seguido de 200 é reemitido e devolve o corpo bom', async () => {
    const fixture = new FixtureTransport({
      statusSequence: { '/teste': [429, 200] },
      bodies: { '/teste': '{"results":[{"ok":true}]}' },
    });
    const result = await clientWith(fixture).getJson('https://brapi.dev/api/teste');
    expect(result.isOk, 'sem reemissão, o 429 viraria falha e o corpo bom se perderia').toBe(true);
    expect(fixture.callCount['/teste'], 'exatamente uma repetição: a primeira falhou, a segunda não').toBe(2);
  });

  it('429 insistente esgota as tentativas e vira falha de limite', async () => {
    const fixture = new FixtureTransport({ statusSequence: { '/teste': [429] }, bodies: { '/teste': '{"results":[]}' } });
    const result = await clientWith(fixture).getJson('https://brapi.dev/api/teste');
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull, 'esgotada a repetição, o 429 tem mapeamento próprio').toBeInstanceOf(DataQualityFailure);
    // `maxAttempts` é 3 no padrão do cliente: a original mais duas repetições.
    expect(fixture.callCount['/teste']).toBe(3);
  });

  it('erro de cliente NÃO é repetido — repetir credencial má multiplica a falha', async () => {
    const fixture = new FixtureTransport({ statusSequence: { '/teste': [401, 200] }, bodies: { '/teste': '{"results":[]}' } });
    const result = await clientWith(fixture).getJson('https://brapi.dev/api/teste');
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InvalidInput);
    expect(fixture.callCount['/teste']).toBe(1);
  });

  it('rajada acima do teto de concorrência, toda com 429, não trava', async () => {
    // A reemissão passa de novo pelo limitador de concorrência. Não trava
    // porque o `onError` dos interceptadores corre na ordem de inserção, e o
    // limitador libera a vaga ANTES de o repetidor reemitir. Oito requisições
    // contra um teto de quatro, todas bloqueadas uma vez: se a vaga não
    // voltasse, as quatro últimas esperariam para sempre.
    const paths = Array.from({ length: 8 }, (_, i) => `/rajada${i}`);
    const fixture = new FixtureTransport({
      statusSequence: Object.fromEntries(paths.map((c) => [c, [429, 200]])),
      bodies: Object.fromEntries(paths.map((c) => [c, '{"results":[{"ok":true}]}'])),
    });
    const client = clientWith(fixture);
    const results = await Promise.all(paths.map((c) => client.getJson(`https://brapi.dev/api${c}`)));
    expect(results.every((r) => r.isOk)).toBe(true);
    for (const c of paths) expect(fixture.callCount[c], `${c}: uma repetição`).toBe(2);
  }, 60_000);

  it('falha de transporte é repetida como o 429', async () => {
    // Sem status, mas transitória: é a outra metade de `isRetryable`.
    const fixture = new FixtureTransport({ transportErrors: { '/teste': 'connectionTimeout' } });
    const result = await clientWith(fixture).getJson('https://brapi.dev/api/teste');
    expect(result.isErr).toBe(true);
    expect(fixture.callCount['/teste']).toBe(3);
  });
});

describe('SanitizedLogInterceptor', () => {
  it('mascara token que apareça na query string', () => {
    const url = 'https://brapi.dev/api/v2/quote?token=abc123XYZ&range=1d';
    expect(SanitizedLogInterceptor.sanitize(url)).toContain('token=****');
    expect(SanitizedLogInterceptor.sanitize(url)).not.toContain('abc123XYZ');
    expect(SanitizedLogInterceptor.sanitize(url)).toContain('range=1d');
  });

  it('não altera URL sem credencial', () => {
    const url = 'https://brapi.dev/api/v2/stocks/historical?symbols=PETR4';
    expect(SanitizedLogInterceptor.sanitize(url)).toBe(url);
  });
});

describe('ApiConfig', () => {
  it('modo proxy é considerado credenciado sem token local', () => {
    const config = new ApiConfig({ mode: BrapiMode.proxied, brapiBaseUrl: 'https://proxy.exemplo', bcbBaseUrl: '' });
    expect(config.hasCredential).toBe(true);
    expect(config.brapiToken).toBeNull();
  });

  it('a resolução prefere o proxy, e marca o token do bundle como exposto', () => {
    const proxied = ApiConfig.resolve({ proxyUrl: 'https://proxy.exemplo/brapi', token: 'segredo' });
    expect(proxied.mode).toBe(BrapiMode.proxied);
    expect(proxied.brapiToken, 'com proxy o token não viaja').toBeNull();
    expect(proxied.credentialIsExposed).toBe(false);

    const direct = ApiConfig.resolve({ token: '  segredo  ' });
    expect(direct.mode).toBe(BrapiMode.direct);
    expect(direct.brapiToken).toBe('segredo');
    expect(direct.credentialIsExposed).toBe(true);

    const none = ApiConfig.resolve({});
    expect(none.hasCredential).toBe(false);
    expect(none.brapiBaseUrl).toBe(ApiConfig.brapiDefaultBaseUrl);
  });
});
