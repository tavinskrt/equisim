import { create } from 'zustand';

import {
  AuditIds,
  type DateTime,
  err,
  type FinancialGoal,
  InvalidInput,
  isoDay,
  ok,
  type Result,
  type Ticker,
  type TrackingOrder,
  TrackingPlan,
  TrackingRecord,
} from '../../core';
import { FailureCopy } from '../../copy';
import type { StoredTracking } from '../../data/persistence/tracking-store';
import { activeStores, currentUserId } from './session-store';

export interface TrackingsState {
  readonly status: 'idle' | 'loading' | 'ready' | 'error';
  /** Do mais recente para o mais antigo. */
  readonly items: readonly StoredTracking[];
  readonly error: string | null;
  /** `true` enquanto uma gravação está em curso. */
  readonly busy: boolean;
  /** Falha da última gravação de compras, para a tela dizer que o resultado não ficou guardado. */
  readonly syncError: string | null;
}

/**
 * Os acompanhamentos da carteira. A falha de leitura é
 * **propagada**, e não convertida em lista vazia: "nenhum acompanhamento" e
 * "não consegui ler" são situações diferentes.
 */
export const useTrackings = create<TrackingsState>(() => ({
  status: 'idle',
  items: [],
  error: null,
  busy: false,
  syncError: null,
}));

function session(): { userId: string; stores: NonNullable<ReturnType<typeof activeStores>> } | null {
  const userId = currentUserId();
  const stores = activeStores();
  return userId === null || stores === null ? null : { userId, stores };
}

export const TrackingActions = {
  async load(): Promise<void> {
    const s = session();
    if (s === null) {
      useTrackings.setState({ status: 'ready', items: [], error: null });
      return;
    }
    useTrackings.setState({ status: 'loading', error: null });
    const result = await s.stores.trackings.listFor(s.userId);
    if (result.isErr) {
      useTrackings.setState({ status: 'error', error: FailureCopy.of(result.failureOrNull!) });
      return;
    }
    useTrackings.setState({ status: 'ready', items: result.unwrap(), error: null });
  },

  /**
   * Começa um acompanhamento com a meta e a carteira Principal de agora,
   * congeladas. As compras não vão aqui: a tela as decide ao montar o
   * acompanhamento e as grava por [appendOrders].
   */
  async start(args: {
    goal: FinancialGoal;
    tickers: readonly Ticker[];
    start: DateTime;
    today: DateTime;
    createdAt: DateTime;
    contributionDay: number;
    expectedReturn: number | null;
    cohortsGeneratedAt: DateTime | null;
  }): Promise<Result<StoredTracking>> {
    const s = session();
    if (s === null) return err(new InvalidInput('Entre na sua conta para acompanhar a carteira: as compras são guardadas nela.'));
    const record = new TrackingRecord({
      id: AuditIds.uuidV4(),
      name: `Principal desde ${isoDay(args.start)}`,
      createdAt: args.createdAt,
      plan: new TrackingPlan({
        start: args.start,
        createdOn: args.today,
        initial: args.goal.initialContribution,
        monthly: args.goal.monthlyContribution,
        contributionDay: args.contributionDay,
        tickers: args.tickers,
      }),
      targetWealth: args.goal.targetWealth,
      months: args.goal.months,
      expectedReturn: args.expectedReturn,
      expectedSource: args.expectedReturn === null ? null : `motor ${isoDay(args.today)}`,
      cohortsGeneratedAt: args.cohortsGeneratedAt === null ? null : isoDay(args.cohortsGeneratedAt),
    });
    useTrackings.setState({ busy: true });
    const saved = await s.stores.trackings.create(s.userId, record);
    if (saved.isErr) {
      useTrackings.setState({ busy: false });
      return err(saved.failureOrNull!);
    }
    const stored: StoredTracking = { record, orders: [] };
    useTrackings.setState({ busy: false, status: 'ready', items: [stored, ...useTrackings.getState().items], syncError: null });
    return ok(stored);
  },

  /**
   * Grava as compras recém-decididas. Só depois que o armazenamento aceita é
   * que elas passam a valer como registro; se a gravação falha, a tela segue
   * mostrando o resultado, e diz que ele não ficou guardado.
   */
  async appendOrders(trackingId: string, orders: readonly TrackingOrder[]): Promise<void> {
    const s = session();
    if (s === null || orders.length === 0) return;
    const saved = await s.stores.trackings.appendOrders(s.userId, trackingId, orders);
    if (saved.isErr) {
      useTrackings.setState({ syncError: FailureCopy.of(saved.failureOrNull!) });
      return;
    }
    useTrackings.setState({
      syncError: null,
      items: useTrackings.getState().items.map((t) => {
        if (t.record.id !== trackingId) return t;
        const known = new Set(t.orders.map((o) => o.seq));
        const merged = [...t.orders, ...orders.filter((o) => !known.has(o.seq))].sort((a, b) => a.seq - b.seq);
        return { record: t.record, orders: merged };
      }),
    });
  },

  /** Apaga o acompanhamento e as compras dele. **Irreversível.** */
  async remove(trackingId: string): Promise<Result<void>> {
    const s = session();
    if (s === null) return err(new InvalidInput('Usuário não identificado.'));
    useTrackings.setState({ busy: true });
    const removed = await s.stores.trackings.delete(s.userId, trackingId);
    useTrackings.setState({ busy: false });
    if (removed.isOk) {
      useTrackings.setState({ items: useTrackings.getState().items.filter((t) => t.record.id !== trackingId), syncError: null });
    }
    return removed;
  },
};
