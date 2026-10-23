import {
  ComputationFailure,
  DataQualityFailure,
  err,
  type Failure,
  InsufficientData,
  InvalidInput,
  ok,
  type Result,
} from '../../core';
import type { ApiConfig } from '../config/api-config';
import {
  fetchTransport,
  getRequest,
  HttpError,
  HttpPipeline,
  type HttpTransport,
  type Interceptor,
} from './http';
import { AuthInterceptor, type LogSink, RetryInterceptor, SanitizedLogInterceptor, ThrottleInterceptor } from './interceptors';

/**
 * Desserializador de respostas grandes.
 *
 * Injetável porque a estratégia certa depende do hospedeiro. O padrão é em
 * linha: no navegador, `JSON.parse` de dois megabytes custa poucos
 * milissegundos e o gargalo é a rede; o Flutter web já fazia o mesmo, porque
 * lá o `compute` também rodava em linha.
 */
export type HeavyJsonDecoder = (body: string) => Promise<unknown>;

const decodeInline: HeavyJsonDecoder = async (body) => JSON.parse(body) as unknown;

/**
 * Cliente HTTP das APIs externas.
 *
 * As respostas chegam como texto e são desserializadas pelo próprio cliente,
 * que converte toda falha de rede ou de protocolo em [Failure] tipada — quem
 * consome nunca precisa de `try`.
 */
export class ApiClient {
  /** Configuração de acesso — URLs base e credencial resolvida. */
  readonly config: ApiConfig;

  /** A cadeia de interceptadores, para quem precisa acrescentar um (a auditoria). */
  readonly pipeline: HttpPipeline;

  private readonly decodeHeavy: HeavyJsonDecoder;

  /**
   * Monta o cliente com a cadeia de interceptadores do projeto.
   *
   * A ordem dos interceptadores importa e é fixa: autenticação, limitação de
   * taxa, repetição e, por último, log — de modo que o log registre a
   * requisição como ela de fato saiu.
   *
   * A política de status ([acceptsStatus]) aceita tudo abaixo de 500 **menos
   * o 429**: erros de cliente viram [Failure] tipada em [getJson] em vez de
   * exceção, mas o limite de requisições precisa virar [HttpError] para que
   * [RetryInterceptor] o veja — o erro é o único gancho que ele tem.
   */
  constructor(
    config: ApiConfig,
    options: {
      transport?: HttpTransport;
      heavyDecoder?: HeavyJsonDecoder;
      logSink?: LogSink;
      logRequests?: boolean;
      /** Espera da repetição, injetável para o teste não dormir de verdade. */
      retrySleep?: (ms: number) => Promise<void>;
      retryRandom?: () => number;
    } = {},
  ) {
    this.config = config;
    this.pipeline = new HttpPipeline(options.transport ?? fetchTransport(), ApiClient.acceptsStatus);
    const interceptors: Interceptor[] = [
      new AuthInterceptor(config),
      new ThrottleInterceptor(),
      new RetryInterceptor({ pipeline: this.pipeline, sleep: options.retrySleep, random: options.retryRandom }),
      new SanitizedLogInterceptor({ enabled: options.logRequests ?? false, sink: options.logSink }),
    ];
    this.pipeline.interceptors.push(...interceptors);
    this.decodeHeavy = options.heavyDecoder ?? decodeInline;
  }

  /**
   * Política de aceitação de status do cliente.
   *
   * Pública e nomeada porque o teste precisa montar a cadeia com **a mesma**
   * política. Aceita `[200, 500)` **exceto 429**, que precisa virar erro para
   * chegar ao [RetryInterceptor].
   */
  static acceptsStatus(status: number): boolean {
    return status < 500 && status !== 429;
  }

  /**
   * GET que devolve JSON já desserializado.
   *
   * **Nunca lança** por falha de rede ou de protocolo: tudo vira [Failure].
   * `401`/`403` viram [InvalidInput]; `404`/`422` e resposta vazia viram
   * [InsufficientData]; `429` vira [DataQualityFailure] — a repetição
   * automática já se esgotou nesse ponto; JSON malformado e demais status
   * viram [ComputationFailure]. Tempo esgotado e ausência de conexão viram
   * [InsufficientData], porque são condições transitórias e não defeito do
   * dado.
   *
   * O `429` chega aqui por dois caminhos — como resposta, se alguém injetar
   * outra política, e como [HttpError], que é o caminho do cliente padrão. Os
   * dois desembocam em [failureFor], de modo que o status tem **um**
   * mapeamento só.
   */
  async getJson(url: string, options: { query?: Record<string, string>; heavy?: boolean } = {}): Promise<Result<unknown>> {
    try {
      const response = await this.pipeline.fetch(getRequest(url, { query: options.query ?? null }));
      const body = response.text ?? '';
      if (response.status !== 200) return err(ApiClient.failureFor(response.status, body));
      if (body.length === 0) return err(new InsufficientData('Resposta vazia da API.'));
      const decoded = options.heavy === true ? await this.decodeHeavy(body) : (JSON.parse(body) as unknown);
      return ok(decoded);
    } catch (e) {
      if (e instanceof HttpError) return err(ApiClient.failureForHttp(e));
      if (e instanceof SyntaxError) return err(new ComputationFailure(`Resposta não é JSON válido: ${e.message}`));
      return err(new ComputationFailure(`Falha de rede: ${e instanceof Error ? e.message : String(e)}`));
    }
  }

  /**
   * Lê um arquivo de texto **em fluxo**, linha a linha, e para quando [stop]
   * devolve `true` — sem baixar o resto.
   *
   * Existe para o arquivo de taxas do Tesouro, que tem 14,5 MB e traz o dia
   * mais recente nas primeiras linhas (item A2.1). A linha que dispara a
   * parada **não** entra no resultado. O arquivo vem em Latin-1.
   */
  async readLinesUntil(
    url: string,
    options: { stop: (line: string) => boolean; encoding?: string },
  ): Promise<Result<string[]>> {
    const controller = new AbortController();
    try {
      const response = await this.pipeline.fetch(getRequest(url, { responseType: 'stream', signal: controller.signal }));
      const stream = response.stream;
      if (response.status !== 200 || stream === null) return err(ApiClient.failureFor(response.status, ''));
      const decoder = new TextDecoder(options.encoding ?? 'latin1');
      const reader = stream.getReader();
      const rows: string[] = [];
      let pending = '';
      let stopped = false;
      const take = (line: string): boolean => {
        const clean = line.endsWith('\r') ? line.slice(0, -1) : line;
        if (options.stop(clean)) return true;
        rows.push(clean);
        return false;
      };
      while (!stopped) {
        const { value, done } = await reader.read();
        if (done) {
          pending += decoder.decode();
          if (pending.length > 0) take(pending);
          break;
        }
        pending += decoder.decode(value, { stream: true });
        let cut = pending.indexOf('\n');
        while (cut >= 0) {
          if (take(pending.slice(0, cut))) {
            stopped = true;
            break;
          }
          pending = pending.slice(cut + 1);
          cut = pending.indexOf('\n');
        }
      }
      if (stopped) {
        await reader.cancel('leitura encerrada').catch(() => undefined);
        controller.abort();
      }
      return ok(rows);
    } catch (e) {
      if (e instanceof HttpError) {
        if (e.type === 'cancel') return err(new ComputationFailure('Leitura cancelada.'));
        return err(ApiClient.failureForHttp(e));
      }
      return err(new ComputationFailure(`Falha de rede: ${e instanceof Error ? e.message : String(e)}`));
    }
  }

  static failureFor(status: number, body: string): Failure {
    switch (status) {
      case 401:
      case 403:
        return new InvalidInput('Credencial da brapi inválida, ausente ou sem permissão para este recurso.');
      case 404:
      case 422:
        return new InsufficientData('Ativo não encontrado na fonte.');
      case 429:
        return new DataQualityFailure(
          'Limite de requisições excedido. As tentativas automáticas se esgotaram; aguarde antes de repetir.',
        );
      case 400:
        return new InvalidInput(`Requisição rejeitada pela API: ${trim(body)}`);
      default:
        return new ComputationFailure(`HTTP ${status}: ${trim(body)}`);
    }
  }

  static failureForHttp(e: HttpError): Failure {
    // Erro que carrega resposta é status HTTP reprovado pela política — o 429,
    // no cliente padrão. Cai na mesma tabela dos status que chegam como
    // resposta, em vez de virar "falha de rede".
    const status = e.response?.status;
    if (status !== undefined) return ApiClient.failureFor(status, e.response?.text ?? '');
    switch (e.type) {
      case 'connectionTimeout':
      case 'sendTimeout':
      case 'receiveTimeout':
        return new InsufficientData('A fonte de dados demorou demais para responder.');
      case 'connectionError':
        return new InsufficientData('Sem conexão com a fonte de dados.');
      default:
        return new ComputationFailure(`Falha de rede: ${e.message.length > 0 ? e.message : e.type}`);
    }
  }
}

function trim(body: string): string {
  return body.length > 200 ? `${body.substring(0, 200)}…` : body;
}
