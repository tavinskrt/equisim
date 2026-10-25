import { DateTime } from '../lang/date-time';
import {
  AuditEvent,
  AuditIds,
  CalculationTrace,
  type JsonMap,
  type TraceSample,
} from './calculation-trace';

/** Destino dos eventos de auditoria. */
export type AuditEventSink = (event: AuditEvent) => void;

/** Relógio monotônico para medir a duração da transação. */
function monotonicMs(): number {
  const perf = (globalThis as { performance?: { now(): number } }).performance;
  return perf !== undefined ? perf.now() : Date.now();
}

/**
 * Ponto único de coleta dos rastros de cálculo.
 *
 * **Desligado por padrão.** Sem consumidor acoplado, [begin] devolve `null` e
 * todas as chamadas de instrumentação viram `trace?.step(...)` — nenhum objeto
 * criado, nenhuma string formatada, nenhum custo. Isso é o que permite deixar
 * a instrumentação permanentemente no caminho do cálculo em vez de mantê-la
 * atrás de uma bifurcação que só é exercitada na apresentação.
 *
 * O acoplamento é feito pela camada de aplicação ([attach]), que sabe para
 * onde mandar — a janela paralela de auditoria, em `/logs`.
 *
 * **Limite conhecido:** o coletor é estático e, portanto, local ao contexto de
 * execução. Uma avaliação executada num Web Worker roda com o coletor do
 * próprio worker; a camada de aplicação repassa os eventos dele ao barramento
 * da página (ver `src/data/valuation-runner.ts`).
 */
export class AuditRecorder {
  private static sink: AuditEventSink | null = null;

  private constructor() {}

  /** `true` quando há consumidor acoplado. */
  static get isActive(): boolean {
    return AuditRecorder.sink !== null;
  }

  /**
   * Acopla o consumidor e liga a instrumentação.
   *
   * **Substitui silenciosamente** qualquer coletor anterior: há um único slot.
   * Cada [AuditEvent] chega de forma síncrona, no fim da transação que o
   * produziu; um consumidor lento atrasa o cálculo.
   */
  static attach(sink: AuditEventSink): void {
    AuditRecorder.sink = sink;
  }

  /**
   * Desliga a instrumentação e devolve o custo a zero.
   *
   * Transações já abertas continuam válidas e ainda emitem para o coletor que
   * capturaram na abertura.
   */
  static detach(): void {
    AuditRecorder.sink = null;
  }

  /** Abre uma transação, ou devolve `null` se ninguém estiver ouvindo. */
  static begin(endpoint: string, options: { inputPayload?: JsonMap } = {}): AuditTransaction | null {
    const sink = AuditRecorder.sink;
    if (sink === null) return null;
    return new AuditTransaction(endpoint, options.inputPayload ?? {}, sink);
  }

  /**
   * Emite um evento já montado — usado pela camada de rede, que mede a
   * requisição inteira e não tem cálculo a decompor.
   */
  static emit(event: AuditEvent): void {
    AuditRecorder.sink?.(event);
  }
}

/** Argumentos de um passo registrado — os nomes do `step` do original. */
export interface TraceStep {
  formulaName: string;
  latex: string;
  variables?: JsonMap;
  steps?: readonly string[];
  result?: number | null;
  unit?: string;
  sample?: TraceSample | null;
  explanation?: readonly string[];
}

/** Transação aberta: acumula rastros e, ao ser concluída, emite o evento. */
export class AuditTransaction {
  /** UUID v4 sorteado na abertura. Correlaciona o evento com a linha da interface de logs. */
  readonly transactionId: string = AuditIds.uuidV4();

  /**
   * Instante da abertura. **Relógio do sistema** — é metadado de observação,
   * nunca entra em cálculo, e por isso não viola o determinismo do núcleo.
   */
  readonly startedAt: DateTime = DateTime.now();

  /** Origem da execução, no formato de caminho. Ver [AuditEvent.endpoint]. */
  readonly endpoint: string;

  /**
   * Payload de entrada, capturado na abertura. Não é copiado: alterar o mapa
   * depois de abrir a transação altera o que será emitido.
   */
  readonly inputPayload: JsonMap;

  private readonly calculations: CalculationTrace[] = [];
  private readonly sink: AuditEventSink;
  private readonly startedMs = monotonicMs();
  private closed = false;

  /** @internal Use [AuditRecorder.begin]. */
  constructor(endpoint: string, inputPayload: JsonMap, sink: AuditEventSink) {
    this.endpoint = endpoint;
    this.inputPayload = inputPayload;
    this.sink = sink;
  }

  /** Registra um cálculo. */
  step(args: TraceStep): void {
    this.calculations.push(
      new CalculationTrace({
        formulaName: args.formulaName,
        latexRepresentation: args.latex,
        mappedVariables: args.variables ?? {},
        intermediateSteps: args.steps ?? [],
        finalValue: args.result ?? null,
        unit: args.unit ?? '',
        sample: args.sample ?? null,
        explanation: args.explanation ?? [],
      }),
    );
  }

  /**
   * Encerra a transação com sucesso e emite o evento.
   *
   * **Idempotente**: chamadas após o primeiro encerramento não fazem nada e
   * não emitem evento duplicado.
   */
  complete(outputPayload: JsonMap): void {
    this.close(outputPayload);
  }

  /**
   * Encerra a transação sem resultado utilizável.
   *
   * O caminho de falha é tão auditável quanto o de sucesso: a banca pergunta
   * por que um ativo não foi avaliado, e a resposta precisa estar registrada
   * junto dos modelos que foram tentados antes de desistir.
   *
   * - [reason]: motivo da desistência, gravado em `motivo`.
   * - [extra]: campos adicionais mesclados no payload de saída. Chaves
   *   `status` e `motivo` são sobrescritas por [extra], não o contrário.
   */
  abort(reason: string, options: { extra?: JsonMap } = {}): void {
    this.close({ status: 'falha', motivo: reason, ...(options.extra ?? {}) });
  }

  private close(outputPayload: JsonMap): void {
    if (this.closed) return;
    this.closed = true;
    const elapsed = Math.trunc(monotonicMs() - this.startedMs);
    this.sink(
      new AuditEvent({
        transactionId: this.transactionId,
        timestamp: this.startedAt,
        endpoint: this.endpoint,
        inputPayload: this.inputPayload,
        outputPayload,
        executionTimeMs: elapsed,
        calculations: Object.freeze([...this.calculations]),
      }),
    );
  }
}
