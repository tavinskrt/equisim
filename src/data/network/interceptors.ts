import { BrapiMode, type ApiConfig } from '../config/api-config';
import type { ErrorOutcome, HttpError, HttpPipeline, HttpRequest, HttpResponse, Interceptor } from './http';

/**
 * Injeta a credencial quando o cliente fala direto com a brapi.
 *
 * Em modo proxy nada é injetado: o token vive apenas no servidor.
 *
 * A credencial vai **apenas para o host da brapi**. Mandá-la em toda
 * requisição entregaria o token da assinatura ao Banco Central — que não
 * pediu nada — e, no navegador, quebraria a chamada: `Authorization` e
 * `Content-Type: application/json` não estão na lista segura do CORS, então
 * o navegador antecipa um `OPTIONS` de verificação. Verificado por `curl`:
 * o `GET` do SGS responde `access-control-allow-origin: *`, mas o `OPTIONS`
 * responde 200 **sem cabeçalho algum de CORS** — verificação reprovada, e o
 * `GET` real nunca sai.
 */
export class AuthInterceptor implements Interceptor {
  private readonly brapiHost: string;

  constructor(readonly config: ApiConfig) {
    this.brapiHost = new URL(config.brapiBaseUrl).host;
  }

  /** `true` quando a requisição vai para a brapi (ou para o proxy que a substitui). */
  private isOwnBackend(url: URL): boolean {
    return url.host.length === 0 || url.host === this.brapiHost;
  }

  onRequest(request: HttpRequest): void {
    const token = this.config.brapiToken;
    if (this.config.mode === BrapiMode.direct && token !== null && this.isOwnBackend(request.url)) {
      request.headers['Authorization'] = `Bearer ${token}`;
    }
    // Só faz sentido declarar o tipo do corpo quando existe corpo. Num GET o
    // cabeçalho não descreve nada e ainda força a verificação prévia do CORS.
    if (request.data !== null) request.headers['Content-Type'] = 'application/json';
  }
}

/**
 * Limita o número de requisições simultâneas.
 *
 * A brapi **não expõe nenhum cabeçalho de rate limit** — verificado: nenhum
 * `X-RateLimit-*` nem `Retry-After`. Como o limite é inobservável, a
 * estratégia é conter a concorrência na origem em vez de reagir ao 429.
 *
 * **A fila não tem teto nem tempo limite**: requisições esperam
 * indefinidamente por uma vaga. Aceitável porque o número de chamadas por
 * interação é limitado pelo teto de 15 ativos da carteira.
 */
export class ThrottleInterceptor implements Interceptor {
  private inFlight = 0;
  private readonly queue: Array<() => void> = [];

  /** Teto de requisições em voo. Padrão `4`: contém a rajada sem serializar tudo. */
  constructor(readonly maxConcurrent = 4) {}

  async onRequest(): Promise<void> {
    if (this.inFlight >= this.maxConcurrent) {
      await new Promise<void>((resolve) => this.queue.push(resolve));
    }
    this.inFlight++;
  }

  private release(): void {
    this.inFlight = Math.max(0, this.inFlight - 1);
    this.queue.shift()?.();
  }

  onResponse(): void {
    this.release();
  }

  onError(error: HttpError): ErrorOutcome {
    this.release();
    return { kind: 'next', error };
  }
}

/** Chave da tentativa em `extra`, lida também pelo interceptador de auditoria. */
export const RETRY_ATTEMPT_KEY = 'retry_attempt';

/**
 * Repete requisições falhas com espaçamento exponencial e ruído aleatório.
 *
 * O ruído (*jitter*) evita que várias chamadas disparadas juntas — o caso
 * normal ao montar uma carteira — voltem a colidir todas no mesmo instante
 * após a espera.
 *
 * Repete apenas o que pode melhorar sozinho: `429`, `5xx` e falhas de conexão
 * ou tempo esgotado. `4xx` de cliente não é repetido — repetir uma credencial
 * inválida só multiplica a falha.
 */
export class RetryInterceptor implements Interceptor {
  /** Cadeia que reemite: a nova tentativa atravessa todos os interceptadores de novo. */
  readonly pipeline: HttpPipeline;
  /** Total de tentativas, contando a original. `3` significa duas repetições. */
  readonly maxAttempts: number;
  /** Base da espera exponencial, em milissegundos. */
  readonly baseDelayMs: number;
  private readonly random: () => number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(args: {
    pipeline: HttpPipeline;
    maxAttempts?: number;
    baseDelayMs?: number;
    /** Gerador em `[0, 1)`, injetável para tornar o teste determinístico. */
    random?: () => number;
    /** Espera, injetável para o teste não dormir de verdade. */
    sleep?: (ms: number) => Promise<void>;
  }) {
    this.pipeline = args.pipeline;
    this.maxAttempts = args.maxAttempts ?? 3;
    this.baseDelayMs = args.baseDelayMs ?? 500;
    this.random = args.random ?? Math.random;
    this.sleep = args.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  private isRetryable(error: HttpError): boolean {
    const status = error.response?.status;
    if (status === 429) return true;
    if (status !== undefined && status >= 500 && status < 600) return true;
    return (
      error.type === 'connectionTimeout' ||
      error.type === 'receiveTimeout' ||
      error.type === 'sendTimeout' ||
      error.type === 'connectionError'
    );
  }

  /**
   * Espera exponencial com jitter completo: `random(0, base · 2^n)`.
   *
   * O jitter é **completo**, não parcial: o sorteio vai de zero ao teto, e não
   * de metade do teto ao teto. É o que descorrelaciona por inteiro rajadas que
   * falharam juntas.
   */
  delayFor(attempt: number): number {
    const ceiling = this.baseDelayMs * 2 ** attempt;
    return Math.floor(this.random() * (ceiling + 1));
  }

  async onError(error: HttpError): Promise<ErrorOutcome> {
    const raw = error.request.extra[RETRY_ATTEMPT_KEY];
    const attempt = typeof raw === 'number' ? raw : 0;
    if (!this.isRetryable(error) || attempt >= this.maxAttempts - 1) return { kind: 'next', error };

    await this.sleep(this.delayFor(attempt));
    const request = error.request;
    request.extra[RETRY_ATTEMPT_KEY] = attempt + 1;
    try {
      return { kind: 'resolve', response: await this.pipeline.fetch(request) };
    } catch (retryError) {
      return { kind: 'next', error: retryError as HttpError };
    }
  }
}

/** Destino das mensagens de diagnóstico. */
export type LogSink = (message: string) => void;

const TOKEN_PATTERN = /([?&]token=)[^&]+/gi;

/**
 * Log de diagnóstico com credenciais mascaradas.
 *
 * Nenhum cabeçalho de autorização e nenhum parâmetro de token chega ao
 * console: logs vazam para relatórios de erro e capturas de tela.
 */
export class SanitizedLogInterceptor implements Interceptor {
  readonly enabled: boolean;
  readonly sink: LogSink;

  constructor(options: { enabled?: boolean; sink?: LogSink } = {}) {
    this.enabled = options.enabled ?? false;
    this.sink = options.sink ?? ((m) => console.debug(m));
  }

  /**
   * Mascara o valor de um parâmetro `token=` na URL.
   *
   * **Cobre apenas o token em parâmetro de consulta.** O cabeçalho
   * `Authorization` nunca é registrado porque este interceptador não imprime
   * cabeçalhos — não porque esta função o remova. Ao acrescentar registro de
   * cabeçalhos, mascare-os aqui antes.
   */
  static sanitize(input: string): string {
    return input.replace(TOKEN_PATTERN, (_m, prefix: string) => `${prefix}****`);
  }

  onRequest(request: HttpRequest): void {
    if (this.enabled) this.sink(`→ ${request.method} ${SanitizedLogInterceptor.sanitize(request.url.toString())}`);
  }

  onResponse(response: HttpResponse): void {
    if (this.enabled) {
      this.sink(`← ${response.status} ${SanitizedLogInterceptor.sanitize(response.request.url.toString())}`);
    }
  }

  onError(error: HttpError): ErrorOutcome {
    if (this.enabled) {
      this.sink(
        `✖ ${error.response?.status ?? error.type} ${SanitizedLogInterceptor.sanitize(error.request.url.toString())}`,
      );
    }
    return { kind: 'next', error };
  }
}
