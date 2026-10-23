import { StructuredCodec, type Encoded } from './structured-codec';
import { evaluateRequest, evaluateWithTrace, type ValuationRequest } from './valuation-request';

/** Mensagem que o executor manda ao Worker. */
export interface WorkerCall {
  readonly id: number;
  readonly request: Encoded;
  readonly trace: boolean;
}

/** Resposta do Worker: o resultado codificado, ou o motivo de não haver. */
export type WorkerReply =
  | { readonly id: number; readonly ok: true; readonly result: Encoded; readonly event: Encoded }
  | { readonly id: number; readonly ok: false; readonly error: string };

/**
 * O lado do Worker, sem o Worker: decodifica o pedido, avalia e codifica a
 * resposta. Separado do arquivo do Worker para ser exercitado em teste, num
 * grafo de módulos próprio — que é o isolamento que o Worker dá.
 */
export function handleWorkerCall(call: WorkerCall): WorkerReply {
  const { id, request, trace } = call;
  try {
    const decoded = StructuredCodec.decode<ValuationRequest>(request);
    if (trace) {
      const { result, event } = evaluateWithTrace(decoded);
      // O evento viaja pela mesma codificação do resultado, e não como JSON:
      // volta com o `DateTime`, os rastros e os payloads exatamente como a
      // cascata os registrou.
      return {
        id,
        ok: true,
        result: StructuredCodec.encode(result),
        event: event === null ? null : StructuredCodec.encode(event),
      };
    }
    return { id, ok: true, result: StructuredCodec.encode(evaluateRequest(decoded)), event: null };
  } catch (e) {
    return { id, ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}
