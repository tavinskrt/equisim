import { AuditEvent, AuditRecorder, type Result, type ValuationResult } from '../../core';
import { StructuredCodec } from './structured-codec';
import { evaluateRequest, type ValuationRequest } from './valuation-request';
import type { WorkerCall, WorkerReply } from './valuation-worker-handler';

/** Cria o Worker da avaliação. Injetável; `null` onde não há Worker (Node, teste). */
export type WorkerFactory = (() => Worker) | null;

const defaultFactory: WorkerFactory =
  typeof Worker === 'undefined'
    ? null
    : () => new Worker(new URL('./valuation.worker.ts', import.meta.url), { type: 'module', name: 'avaliacao' });

/**
 * Executa avaliações, decidindo por medição se vale pagar por um Worker.
 *
 * **A decisão é empírica, não dogmática.** O benchmark da Fase 0 mediu:
 * 10 mil cenários de Monte Carlo custam 2,6 ms — bem abaixo do orçamento de
 * 16,7 ms de um quadro a 60 fps —, enquanto 100 mil custam 17,8 ms e já
 * consomem um quadro inteiro. Abaixo do limiar, a troca de contexto custaria
 * mais (criação do Worker e cópia do payload) do que o próprio cálculo.
 *
 * **O rastro atravessa o Worker** (item D4). O coletor de auditoria é estático
 * e local a cada contexto: o Worker liga um coletor próprio, devolve o evento
 * junto com o resultado, e este contexto o reemite — o painel recebe o mesmo
 * rastro que receberia se a conta tivesse rodado aqui.
 *
 * **Falha do Worker não é falha da avaliação.** Worker que não sobe, objeto
 * que não atravessa a fronteira, erro inesperado do lado de lá: a conta é
 * refeita em linha, que é determinística e dá o mesmo número.
 */
export class ValuationRunner {
  /** Acima disto o cálculo passa a ameaçar o orçamento de um quadro. */
  static readonly workerThresholdSamples = 20000;

  private worker: Worker | null = null;
  private nextId = 0;
  private readonly pending = new Map<number, (reply: WorkerReply | null) => void>();

  constructor(private readonly workerFactory: WorkerFactory = defaultFactory) {}

  /**
   * Avalia um ativo, em Worker próprio só quando o volume justifica: modo
   * Monte Carlo **e** sorteios a partir de [workerThresholdSamples]. Abaixo
   * disso resolve em linha.
   *
   * Propaga a falha de `ValuationCascade.evaluate` sem traduzir.
   */
  async run(request: ValuationRequest): Promise<Result<ValuationResult>> {
    const needsWorker =
      request.monteCarlo === true && (request.samples ?? 10000) >= ValuationRunner.workerThresholdSamples;
    if (!needsWorker || this.workerFactory === null) return evaluateRequest(request);

    const trace = AuditRecorder.isActive;
    let encoded;
    try {
      encoded = StructuredCodec.encode(request);
    } catch {
      return evaluateRequest(request);
    }
    const reply = await this.call({ id: this.nextId++, request: encoded, trace });
    if (reply === null || !reply.ok) return evaluateRequest(request);
    let result: Result<ValuationResult>;
    let event: unknown;
    try {
      result = StructuredCodec.decode<Result<ValuationResult>>(reply.result);
      event = StructuredCodec.decode<unknown>(reply.event);
    } catch {
      return evaluateRequest(request);
    }
    if (trace && event instanceof AuditEvent) AuditRecorder.emit(event);
    return result;
  }

  private ensureWorker(): Worker | null {
    if (this.worker !== null) return this.worker;
    try {
      const worker = this.workerFactory!();
      worker.onmessage = (message: MessageEvent<WorkerReply>) => {
        const resolve = this.pending.get(message.data.id);
        this.pending.delete(message.data.id);
        resolve?.(message.data);
      };
      worker.onerror = () => this.fail();
      worker.onmessageerror = () => this.fail();
      this.worker = worker;
      return worker;
    } catch {
      return null;
    }
  }

  /** Worker quebrado: quem esperava recua para o cálculo em linha. */
  private fail(): void {
    for (const resolve of this.pending.values()) resolve(null);
    this.pending.clear();
    this.worker?.terminate();
    this.worker = null;
  }

  private call(message: WorkerCall): Promise<WorkerReply | null> {
    const worker = this.ensureWorker();
    if (worker === null) return Promise.resolve(null);
    return new Promise((resolve) => {
      this.pending.set(message.id, resolve);
      try {
        worker.postMessage(message);
      } catch {
        this.pending.delete(message.id);
        resolve(null);
      }
    });
  }

  /** Encerra o Worker, se houver. */
  dispose(): void {
    this.fail();
  }
}
