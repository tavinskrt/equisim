import {
  type AuditEvent,
  AuditRecorder,
  type Result,
  StochasticScenarios,
  ValuationCascade,
  type ValuationInputs,
  type ValuationResult,
} from '../../core';

/**
 * Pedido de avaliação, serializável para atravessar a fronteira do Worker.
 *
 * Só carrega dados — nenhuma função. Funções não atravessam `postMessage`,
 * então a decisão de qual modelo aplicar acontece **dentro** do Worker, via
 * [ValuationCascade], em vez de ser injetada de fora.
 */
export interface ValuationRequest {
  /** Insumos já resolvidos. É o que domina o custo de cópia. */
  readonly inputs: ValuationInputs;
  /** `true` para sortear cenários; `false` para os três discretos. */
  readonly monteCarlo?: boolean;
  /**
   * Sorteios quando [monteCarlo] é `true`. Também decide se a execução vale
   * um Worker — ver `ValuationRunner.workerThresholdSamples`.
   */
  readonly samples?: number;
  /** Semente do gerador. Fixa por reprodutibilidade. */
  readonly seed?: number;
}

/** A avaliação propriamente dita, igual em linha e no Worker. */
export function evaluateRequest(request: ValuationRequest): Result<ValuationResult> {
  return ValuationCascade.evaluate(request.inputs, {
    scenarioBuilder: request.monteCarlo === true ? (base) => StochasticScenarios.around(base) : null,
    monteCarloSamples: request.samples ?? 10000,
    seed: request.seed ?? 42,
  });
}

/**
 * A avaliação com um coletor de auditoria próprio, e o evento que ele recebeu.
 *
 * É o ponto de entrada do Worker quando há alguém ouvindo do lado de cá: o
 * coletor é estático e local ao contexto, e a avaliação que migrava sairia sem
 * evento no painel de logs (item D4).
 */
export function evaluateWithTrace(request: ValuationRequest): { result: Result<ValuationResult>; event: AuditEvent | null } {
  let event: AuditEvent | null = null;
  AuditRecorder.attach((e) => {
    event = e;
  });
  try {
    return { result: evaluateRequest(request), event };
  } finally {
    AuditRecorder.detach();
  }
}
