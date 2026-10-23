import { readFileSync, existsSync } from 'node:fs';

import { ApiConfig, BrapiMode } from '../../src/data/config/api-config';
import { ApiClient } from '../../src/data/network/api-client';
import { HttpError, type HttpErrorType, type HttpRequest, type HttpResponse } from '../../src/data/network/http';

/**
 * Transporte HTTP que responde a partir de arquivos gravados.
 *
 * As fixtures são **respostas reais** da brapi e do Banco Central, capturadas
 * uma vez e versionadas. Isso dá aos testes as duas propriedades que faltavam
 * na suíte antiga: rodam offline e são determinísticos — a suíte anterior
 * batia na API de produção e falhava conforme o mercado mudava.
 *
 * As regras são conferidas na ordem abaixo — erro de transporte, sequência de
 * status, corpo literal, falha, fixture —, e dentro de cada uma na ordem de
 * inserção, como o adaptador do aplicativo anterior.
 */
export class FixtureTransport {
  /** Trechos de URL mapeados para o nome da fixture. */
  readonly routes: Record<string, string>;
  /** URLs que devem falhar com o status dado. */
  readonly failures: Record<string, number>;
  /**
   * Corpo JSON **literal** por trecho de URL, respondido com status 200.
   *
   * Existe para o que fixture gravada não consegue exercitar: payload
   * deliberadamente corrompido — preço negativo, data fora de ordem, campo
   * ausente. Gravar isso como arquivo daria a impressão de ser resposta real
   * da fonte, que é o oposto do que o teste quer dizer.
   */
  readonly bodies: Record<string, string>;
  /**
   * Status por tentativa, na ordem, para um mesmo trecho de URL. A chamada
   * `n` recebe o `n`-ésimo status; esgotada a lista, repete o último. É o que
   * permite provar a **repetição de verdade**.
   */
  readonly statusSequence: Record<string, number[]>;
  /** Falha de transporte por trecho de URL — não há resposta nenhuma. */
  readonly transportErrors: Record<string, HttpErrorType>;
  /** Quantas vezes cada rota foi chamada. */
  readonly callCount: Record<string, number> = {};

  constructor(
    args: {
      routes?: Record<string, string>;
      failures?: Record<string, number>;
      bodies?: Record<string, string>;
      statusSequence?: Record<string, number[]>;
      transportErrors?: Record<string, HttpErrorType>;
    } = {},
  ) {
    this.routes = args.routes ?? {};
    this.failures = args.failures ?? {};
    this.bodies = args.bodies ?? {};
    this.statusSequence = args.statusSequence ?? {};
    this.transportErrors = args.transportErrors ?? {};
  }

  private count(key: string): number {
    const n = this.callCount[key] ?? 0;
    this.callCount[key] = n + 1;
    return n;
  }

  /** O transporte, para entregar ao [ApiClient]. */
  readonly transport = async (request: HttpRequest): Promise<HttpResponse> => {
    const url = request.url.toString();
    const respond = (status: number, text: string): HttpResponse =>
      request.responseType === 'stream'
        ? { status, text: null, stream: latin1Stream(text), request }
        : { status, text, stream: null, request };

    for (const [key, type] of Object.entries(this.transportErrors)) {
      if (!url.includes(key)) continue;
      this.count(key);
      throw new HttpError(type, request, { message: 'falha de transporte forçada' });
    }
    for (const [key, statuses] of Object.entries(this.statusSequence)) {
      if (!url.includes(key)) continue;
      const attempt = this.count(key);
      const status = statuses.length === 0 ? 200 : statuses[Math.min(attempt, statuses.length - 1)]!;
      if (status !== 200) return respond(status, `{"error":"status ${status} na tentativa ${attempt + 1}"}`);
      return respond(200, this.bodyFor(key));
    }
    for (const [key, body] of Object.entries(this.bodies)) {
      if (!url.includes(key)) continue;
      this.count(key);
      return respond(200, body);
    }
    for (const [key, status] of Object.entries(this.failures)) {
      if (!url.includes(key)) continue;
      this.count(key);
      return respond(status, '{"error":"forçado"}');
    }
    for (const [key, name] of Object.entries(this.routes)) {
      if (!url.includes(key)) continue;
      this.count(key);
      return respond(200, readFixture(name));
    }
    throw new Error(`Nenhuma fixture registrada para ${url}`);
  };

  private bodyFor(route: string): string {
    const literal = this.bodies[route];
    if (literal !== undefined) return literal;
    const name = this.routes[route];
    if (name === undefined) throw new Error(`Rota ${route} em sequência sem corpo nem fixture.`);
    return readFixture(name);
  }
}

/**
 * O corpo em fluxo, em pedaços pequenos e em Latin-1 — a codificação do
 * arquivo do Tesouro, que é o único lido assim. Pedaços de 7 bytes cortam
 * linhas no meio, que é o caso que a leitura em fluxo precisa aguentar.
 */
function latin1Stream(text: string): ReadableStream<Uint8Array> {
  const bytes = Uint8Array.from(text, (c) => c.charCodeAt(0) & 0xff);
  let offset = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      if (offset >= bytes.length) {
        controller.close();
        return;
      }
      controller.enqueue(bytes.slice(offset, offset + 7));
      offset += 7;
    },
  });
}

/**
 * Lê a fixture como o `fetch` lê o corpo: decodificação UTF-8 que **remove o
 * BOM**. Os arquivos gravados começam com ele, e o `Response.text()` do
 * navegador o descarta — ler com `readFileSync(…, 'utf8')` o manteria.
 */
export function readFixture(name: string): string {
  const path = `test/fixtures/${name}.json`;
  if (!existsSync(path)) throw new Error(`Fixture ausente: ${path}`);
  return new TextDecoder('utf-8').decode(readFileSync(path));
}

export const testConfig = new ApiConfig({
  mode: BrapiMode.direct,
  brapiBaseUrl: 'https://brapi.dev/api',
  brapiToken: 'token-de-teste',
  bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
});

/**
 * Cliente com a **mesma** cadeia e a mesma política de status de produção —
 * só o transporte e a espera da repetição são trocados, para o teste não
 * dormir de verdade.
 */
export function clientWith(fixture: FixtureTransport, config: ApiConfig = testConfig): ApiClient {
  return new ApiClient(config, { transport: fixture.transport, retrySleep: async () => {} });
}
