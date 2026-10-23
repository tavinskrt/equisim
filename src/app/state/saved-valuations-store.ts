import { create } from 'zustand';

import {
  AuditEvent,
  AuditIds,
  AuditRecorder,
  err,
  type Failure,
  InvalidInput,
  type ManualValuationRecord,
  ok,
  type Result,
  type Ticker,
} from '../../core';
import { FailureCopy } from '../../copy';
import { activeStores, currentUserId } from './session-store';

export interface SavedValuationsState {
  readonly status: 'idle' | 'loading' | 'ready' | 'error';
  /** Do mais recente para o mais antigo. */
  readonly records: readonly ManualValuationRecord[];
  readonly error: string | null;
}

/**
 * Os valuations que o usuário confirmou (decisão 150).
 *
 * **É daqui que eles chegam ao painel de logs**, em dois momentos: na
 * confirmação, e ao carregar o histórico gravado — o que faz o painel
 * refletir o que está **persistido**, e não só o desta sessão. O evento leva
 * o identificador do registro, e o barramento descarta identificador repetido.
 */
export const useSavedValuations = create<SavedValuationsState>(() => ({ status: 'idle', records: [], error: null }));

/**
 * Sem nova tentativa automática: a falha comum aqui é de permissão, que
 * repetir não conserta, e cada repetição voltaria a emitir para o painel.
 */
export const SavedValuationsActions = {
  async load(): Promise<void> {
    const userId = currentUserId();
    const stores = activeStores();
    if (userId === null || stores === null) {
      useSavedValuations.setState({ status: 'ready', records: [], error: null });
      return;
    }
    useSavedValuations.setState({ status: 'loading', error: null });
    const result = await stores.valuations.listFor(userId);
    if (result.isErr) {
      useSavedValuations.setState({ status: 'error', error: FailureCopy.of(result.failureOrNull!) });
      return;
    }
    const records = result.unwrap();
    // Do mais antigo ao mais recente: o painel lista na ordem de chegada.
    for (const r of [...records].reverse()) AuditRecorder.emit(r.toAuditEvent());
    useSavedValuations.setState({ status: 'ready', records, error: null });
  },

  /**
   * Grava o valuation confirmado e o registra no painel. O evento só vai como
   * **confirmado** depois que o armazenamento aceitou; se a gravação falha,
   * vai uma tentativa recusada, com o motivo e outro identificador.
   */
  async confirm(record: ManualValuationRecord): Promise<Result<void>> {
    const userId = currentUserId();
    const stores = activeStores();
    if (userId === null || stores === null) {
      const failure = new InvalidInput(
        'Entre na sua conta para salvar o valuation: ele é guardado junto dos seus estudos.',
      );
      emitRefused(record, failure);
      return err(failure);
    }
    const saved = await stores.valuations.save(userId, record);
    const failure = saved.failureOrNull;
    if (failure !== null) {
      emitRefused(record, failure);
      return err(failure);
    }
    AuditRecorder.emit(record.toAuditEvent());
    const current = useSavedValuations.getState().records;
    useSavedValuations.setState({
      status: 'ready',
      records: [record, ...current.filter((r) => r.id !== record.id)],
      error: null,
    });
    return ok(undefined);
  },

  /**
   * Apaga um valuation salvo. **Irreversível.** O evento que ele deixou no
   * painel desta sessão fica: o painel é o registro do que aconteceu.
   */
  async remove(id: string): Promise<Result<void>> {
    const userId = currentUserId();
    const stores = activeStores();
    if (userId === null || stores === null) return err(new InvalidInput('Usuário não identificado.'));
    const removed = await stores.valuations.delete(userId, id);
    if (removed.isOk) {
      useSavedValuations.setState({ records: useSavedValuations.getState().records.filter((r) => r.id !== id) });
    }
    return removed;
  },
};

function emitRefused(record: ManualValuationRecord, failure: Failure): void {
  const event = record.toAuditEvent();
  AuditRecorder.emit(
    new AuditEvent({
      transactionId: AuditIds.uuidV4(),
      timestamp: event.timestamp,
      endpoint: event.endpoint,
      inputPayload: event.inputPayload,
      outputPayload: {
        status: 'falha',
        motivo: `O valuation não foi salvo: ${failure.message}`,
        registro: record.id,
      },
      executionTimeMs: 0,
      calculations: event.calculations,
    }),
  );
}

/**
 * **O valuation do usuário que vale para o ativo**, ou `null` quando vale o do
 * motor (decisão 151): o mais recente confirmado, **desde que discorde do
 * motor**. Confirmar os números do motor tal como estão é concordar com ele.
 */
export function userValuationOf(records: readonly ManualValuationRecord[], ticker: Ticker): ManualValuationRecord | null {
  for (const r of records) {
    if (r.ticker !== ticker) continue;
    return r.changedFields.length === 0 ? null : r;
  }
  return null;
}
