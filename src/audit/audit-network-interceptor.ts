import { AuditEvent, AuditIds, AuditRecorder, DateTime, type JsonMap } from '../core';
import type { HttpError, HttpRequest, HttpResponse, Interceptor, ErrorOutcome } from '../data/network/http';
import { RETRY_ATTEMPT_KEY, SanitizedLogInterceptor } from '../data/network/interceptors';

const START_KEY = 'audit_started_at';
const START_MONOTONIC_KEY = 'audit_started_monotonic';
const ID_KEY = 'audit_transaction_id';

/**
 * Registra cada ida à API como um evento de auditoria.
 *
 * É a metade "payload bruto" do painel: o cálculo mostra a fórmula, e este
 * interceptador mostra de onde vieram os números que entraram nela. Sem ele, a
 * auditoria provaria que a conta está certa sem provar que os insumos são os
 * que a fonte devolveu.
 *
 * **Custo zero quando desligado**: tudo aqui é guardado por
 * [AuditRecorder.isActive], que é `false` enquanto ninguém estiver ouvindo.
 *
 * **Nada de credencial**: a URL passa pelo mesmo higienizador do log de
 * diagnóstico e os cabeçalhos de autorização não entram no payload. O painel é
 * feito para ser projetado numa tela durante a apresentação.
 */
export class AuditNetworkInterceptor implements Interceptor {
  /**
   * Teto do trecho de resposta guardado no evento.
   *
   * O histórico de dez anos de dez ativos passa de dois megabytes. Guardar
   * isso por requisição encheria o anel de memória e a mensagem entre abas
   * para mostrar algo que ninguém lê rolando. Respostas menores que o teto
   * entram desserializadas, e aí o visualizador mostra a árvore de verdade.
   */
  static readonly bodyPreviewLimit = 4000;

  constructor(private readonly monotonicNow: () => number = () => performance.now()) {}

  onRequest(request: HttpRequest): void {
    if (!AuditRecorder.isActive) return;
    request.extra[START_KEY] = DateTime.now();
    request.extra[START_MONOTONIC_KEY] = this.monotonicNow();
    request.extra[ID_KEY] = AuditIds.uuidV4();
  }

  onResponse(response: HttpResponse): void {
    this.emit(response.request, { status: response.status, body: describeResponse(response) });
  }

  onError(error: HttpError): ErrorOutcome {
    const response = error.response;
    this.emit(error.request, {
      status: response?.status ?? null,
      body: response === null ? { body: null } : describeResponse(response),
      error: error.message.length > 0 ? error.message : error.type,
    });
    return { kind: 'next', error };
  }

  private emit(request: HttpRequest, args: { status: number | null; body: JsonMap; error?: string }): void {
    if (!AuditRecorder.isActive) return;
    const startedAt = request.extra[START_KEY];
    if (!(startedAt instanceof DateTime)) return;
    const startedMonotonic = request.extra[START_MONOTONIC_KEY];
    const id = request.extra[ID_KEY];
    const elapsed = typeof startedMonotonic === 'number' ? this.monotonicNow() - startedMonotonic : 0;

    const queryParameters: JsonMap = {};
    for (const [key, value] of request.url.searchParams) {
      queryParameters[key] = key.toLowerCase() === 'token' ? '****' : value;
    }
    const output: JsonMap = { statusCode: args.status };
    if (args.error !== undefined) output['error'] = args.error;
    Object.assign(output, args.body);

    AuditRecorder.emit(
      new AuditEvent({
        transactionId: typeof id === 'string' ? id : AuditIds.uuidV4(),
        timestamp: startedAt,
        endpoint: request.url.pathname,
        inputPayload: {
          method: request.method,
          url: SanitizedLogInterceptor.sanitize(request.url.toString()),
          queryParameters,
          retryAttempt: request.extra[RETRY_ATTEMPT_KEY] ?? 0,
        },
        outputPayload: output,
        executionTimeMs: Math.max(0, Math.round(elapsed)),
      }),
    );
  }
}

function describeResponse(response: HttpResponse): JsonMap {
  // Fluxo lido aos pedaços (o CSV do Tesouro): o corpo não passa por aqui.
  if (response.text === null) return { body: null, fluxo: response.stream !== null };
  return describeBody(response.text);
}

/** O corpo como o painel o mostra: árvore até o teto, trecho acima dele. */
export function describeBody(body: string): JsonMap {
  const limit = AuditNetworkInterceptor.bodyPreviewLimit;
  if (body.length <= limit) {
    try {
      return { sizeBytes: body.length, body: JSON.parse(body) as unknown };
    } catch {
      return { sizeBytes: body.length, body };
    }
  }
  return {
    sizeBytes: body.length,
    truncated: true,
    bodyPreview: `${body.substring(0, limit)}… [truncado: a resposta completa tem ${body.length} caracteres]`,
  };
}
