/**
 * Transporte HTTP do projeto: pedido, resposta, erro tipado e a cadeia de
 * interceptadores.
 *
 * É o equivalente do que o Dio fazia no aplicativo Flutter, sobre o `fetch`
 * da plataforma — o mesmo no navegador, no Web Worker e no Node 20 das
 * ferramentas de `tool/`. A cadeia preserva a semântica que os
 * interceptadores do projeto assumem: o pedido passa por todos na ordem, a
 * resposta volta por todos na mesma ordem, e um erro pode ser **resolvido**
 * por um deles (a repetição), o que pula os demais.
 */

/** Pedido em voo. Mutável de propósito: os interceptadores o enriquecem. */
export interface HttpRequest {
  method: 'GET';
  /** URL absoluta, já com os parâmetros de consulta. */
  url: URL;
  headers: Record<string, string>;
  /** Corpo do pedido. Os `GET` do projeto não têm. */
  data: string | null;
  /** Texto (desserializado pelo cliente) ou fluxo (lido aos pedaços). */
  responseType: 'text' | 'stream';
  /** Estado que os interceptadores compartilham entre ida e volta. */
  extra: Record<string, unknown>;
  /** Cancelamento externo — a leitura em fluxo encerra por ele. */
  signal: AbortSignal | null;
}

/** Resposta recebida. */
export interface HttpResponse {
  status: number;
  /** Corpo em texto, quando `responseType` é `text`. */
  text: string | null;
  /** Corpo em fluxo, quando `responseType` é `stream`. */
  stream: ReadableStream<Uint8Array> | null;
  request: HttpRequest;
}

/** Tipo do erro de transporte, com os nomes que o Dio usava. */
export type HttpErrorType =
  | 'connectionTimeout'
  | 'sendTimeout'
  | 'receiveTimeout'
  | 'badResponse'
  | 'cancel'
  | 'connectionError'
  | 'unknown';

/** Erro de transporte ou de status reprovado pela política do cliente. */
export class HttpError extends Error {
  readonly type: HttpErrorType;
  readonly request: HttpRequest;
  /** Resposta que carregou o status reprovado, ou `null` sem resposta. */
  readonly response: HttpResponse | null;

  constructor(type: HttpErrorType, request: HttpRequest, options: { response?: HttpResponse | null; message?: string } = {}) {
    super(options.message ?? type);
    this.name = 'HttpError';
    this.type = type;
    this.request = request;
    this.response = options.response ?? null;
  }
}

/** Executa o pedido de verdade. Injetável para teste com fixture. */
export type HttpTransport = (request: HttpRequest) => Promise<HttpResponse>;

/** O que um interceptador decide diante de um erro. */
export type ErrorOutcome = { kind: 'next'; error: HttpError } | { kind: 'resolve'; response: HttpResponse };

/** Gancho na cadeia, como o `Interceptor` do Dio. */
export interface Interceptor {
  onRequest?(request: HttpRequest): Promise<void> | void;
  onResponse?(response: HttpResponse): void;
  onError?(error: HttpError): Promise<ErrorOutcome> | ErrorOutcome;
}

/**
 * Cadeia de interceptadores sobre um transporte.
 *
 * [fetch] atravessa a cadeia inteira: é o que a repetição usa para reemitir
 * — e por isso a nova tentativa passa de novo pela autenticação e pelo
 * limitador de concorrência, como no Dio.
 */
export class HttpPipeline {
  readonly interceptors: Interceptor[] = [];

  constructor(
    private readonly transport: HttpTransport,
    private readonly acceptsStatus: (status: number) => boolean,
  ) {}

  async fetch(request: HttpRequest): Promise<HttpResponse> {
    for (const i of this.interceptors) await i.onRequest?.(request);
    let response: HttpResponse;
    try {
      response = await this.transport(request);
      if (!this.acceptsStatus(response.status)) {
        throw new HttpError('badResponse', request, {
          response,
          message: `status ${response.status} reprovado pela política do cliente`,
        });
      }
    } catch (raw) {
      let error = asHttpError(raw, request);
      for (const i of this.interceptors) {
        if (i.onError === undefined) continue;
        const outcome = await i.onError(error);
        if (outcome.kind === 'resolve') return outcome.response;
        error = outcome.error;
      }
      throw error;
    }
    for (const i of this.interceptors) i.onResponse?.(response);
    return response;
  }
}

/** Normaliza qualquer exceção do transporte para [HttpError]. */
export function asHttpError(raw: unknown, request: HttpRequest): HttpError {
  if (raw instanceof HttpError) return raw;
  if (raw instanceof Error && raw.name === 'AbortError') {
    return new HttpError('cancel', request, { message: 'pedido cancelado' });
  }
  // O `fetch` reprova CORS, DNS e conexão recusada com `TypeError`, sem
  // distinguir as causas — é o `connectionError` do Dio.
  if (raw instanceof TypeError) {
    return new HttpError('connectionError', request, { message: raw.message });
  }
  return new HttpError('unknown', request, { message: raw instanceof Error ? raw.message : String(raw) });
}

/** Monta um pedido `GET` com os parâmetros de consulta. */
export function getRequest(
  url: string,
  options: { query?: Record<string, string> | null; responseType?: 'text' | 'stream'; signal?: AbortSignal | null } = {},
): HttpRequest {
  const u = new URL(url);
  for (const [k, v] of Object.entries(options.query ?? {})) u.searchParams.set(k, v);
  return {
    method: 'GET',
    url: u,
    headers: {},
    data: null,
    responseType: options.responseType ?? 'text',
    extra: {},
    signal: options.signal ?? null,
  };
}

/**
 * Transporte sobre o `fetch` da plataforma.
 *
 * Os dois prazos são os do cliente anterior: 20 s até os cabeçalhos chegarem
 * (conexão) e 40 s para ler o corpo (recepção). O `fetch` não tem prazo
 * próprio; os dois saem de um `AbortController` por fase, e o tipo do erro
 * diz qual estourou.
 */
export function fetchTransport(
  options: { connectTimeoutMs?: number; receiveTimeoutMs?: number; fetchImpl?: typeof fetch } = {},
): HttpTransport {
  const connectTimeoutMs = options.connectTimeoutMs ?? 20_000;
  const receiveTimeoutMs = options.receiveTimeoutMs ?? 40_000;
  return async (request) => {
    const fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
    const controller = new AbortController();
    const external = request.signal;
    const onExternalAbort = (): void => controller.abort();
    if (external !== null) {
      if (external.aborted) controller.abort();
      else external.addEventListener('abort', onExternalAbort, { once: true });
    }
    let phase: 'connect' | 'receive' = 'connect';
    let timedOut = false;
    let timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, connectTimeoutMs);
    try {
      const response = await fetchImpl(request.url, {
        method: request.method,
        headers: request.headers,
        body: request.data,
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (request.responseType === 'stream') {
        return { status: response.status, text: null, stream: response.body, request };
      }
      phase = 'receive';
      timer = setTimeout(() => {
        timedOut = true;
        controller.abort();
      }, receiveTimeoutMs);
      const text = await response.text();
      return { status: response.status, text, stream: null, request };
    } catch (raw) {
      if (timedOut) {
        throw new HttpError(phase === 'connect' ? 'connectionTimeout' : 'receiveTimeout', request, {
          message: phase === 'connect' ? 'tempo de conexão esgotado' : 'tempo de recepção esgotado',
        });
      }
      throw asHttpError(raw, request);
    } finally {
      clearTimeout(timer);
      external?.removeEventListener('abort', onExternalAbort);
    }
  };
}
