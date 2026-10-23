/// <reference lib="webworker" />
import { handleWorkerCall, type WorkerCall } from './valuation-worker-handler';

declare const self: DedicatedWorkerGlobalScope;

// Contexto próprio, com o seu núcleo e o seu coletor de auditoria: o que este
// Worker liga e desliga não alcança a aba.
self.onmessage = (message: MessageEvent<WorkerCall>) => {
  self.postMessage(handleWorkerCall(message.data));
};
