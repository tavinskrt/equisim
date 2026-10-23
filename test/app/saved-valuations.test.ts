import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  ComputationFailure,
  DateTime,
  err,
  type ManualPremises,
  ManualValuationRecord,
  ok,
  Ticker,
} from '../../src/core';
import { SavedValuationsActions, useSavedValuations, userValuationOf } from '../../src/app/state/saved-valuations-store';
import type { ManualValuationStore } from '../../src/data/persistence/manual-valuation-store';
import { cascadeValuation } from './fixtures';
import { memoryStores, testRuntime } from './harness';

let events: AuditEvent[];
beforeEach(() => {
  events = [];
  AuditRecorder.attach((e) => events.push(e));
  useSavedValuations.setState({ status: 'idle', records: [], error: null });
});
afterEach(() => AuditRecorder.detach());

const engine = cascadeValuation();

function record(edit: (p: ManualPremises) => ManualPremises, id: string, minute: number): ManualValuationRecord {
  const m = engine.manual!;
  return ManualValuationRecord.capture({
    id,
    ticker: engine.ticker,
    engineAsOf: engine.asOf,
    valuation: m,
    premises: edit(m.enginePremises),
    savedAt: DateTime.utc(2026, 10, 22, 18, minute),
  }).unwrap();
}

const divergent = (id = '00000000-0000-4000-8000-000000000001', minute = 1) =>
  record((p) => p.copyWith({ growth: p.growth + 0.02 }), id, minute);
const agreeing = (id = '00000000-0000-4000-8000-000000000002', minute = 2) => record((p) => p, id, minute);

describe('Confirmar o valuation (decisão 150)', () => {
  it('grava, põe no topo da lista e registra no painel com o identificador do registro', async () => {
    testRuntime();
    const r = divergent();
    const result = await SavedValuationsActions.confirm(r);
    expect(result.isOk).toBe(true);
    expect(useSavedValuations.getState().records[0]).toBe(r);
    expect(events).toHaveLength(1);
    expect(events[0]!.transactionId).toBe(r.id);
    expect(events[0]!.endpoint).toBe(`${ManualValuationRecord.endpointPrefix}${r.ticker.value}`);
  });

  it('a gravação recusada vai ao painel como falha, com outro identificador', async () => {
    const failing: ManualValuationStore = {
      listFor: async () => ok([]),
      save: async () => err(new ComputationFailure('permissão negada')),
      delete: async () => ok(undefined),
    };
    testRuntime({ cloudStores: { portfolios: memoryStores().portfolios, valuations: failing } });
    const r = divergent();
    const result = await SavedValuationsActions.confirm(r);
    expect(result.isErr).toBe(true);
    expect(useSavedValuations.getState().records).toHaveLength(0);
    expect(events).toHaveLength(1);
    expect(events[0]!.transactionId).not.toBe(r.id);
    expect(events[0]!.outputPayload['status']).toBe('falha');
    expect(String(events[0]!.outputPayload['motivo'])).toContain('permissão negada');
    expect(events[0]!.outputPayload['registro']).toBe(r.id);
  });

  it('sem usuário, não grava e diz por quê', async () => {
    testRuntime({ user: null });
    const result = await SavedValuationsActions.confirm(divergent());
    expect(result.failureOrNull!.message).toContain('Entre na sua conta para salvar o valuation');
    expect(events[0]!.outputPayload['status']).toBe('falha');
  });

  it('carregar o histórico registra cada salvo no painel, do mais antigo ao mais recente', async () => {
    const runtime = testRuntime();
    await runtime.cloudStores!.valuations.save('usuario-1', divergent('00000000-0000-4000-8000-00000000000a', 1));
    await runtime.cloudStores!.valuations.save('usuario-1', divergent('00000000-0000-4000-8000-00000000000b', 5));
    await SavedValuationsActions.load();
    const s = useSavedValuations.getState();
    expect(s.status).toBe('ready');
    expect(s.records.map((r) => r.id)).toEqual([
      '00000000-0000-4000-8000-00000000000b',
      '00000000-0000-4000-8000-00000000000a',
    ]);
    expect(events.map((e) => e.transactionId)).toEqual([
      '00000000-0000-4000-8000-00000000000a',
      '00000000-0000-4000-8000-00000000000b',
    ]);
  });

  it('apagar tira o registro da lista', async () => {
    testRuntime();
    const r = divergent();
    await SavedValuationsActions.confirm(r);
    expect((await SavedValuationsActions.remove(r.id)).isOk).toBe(true);
    expect(useSavedValuations.getState().records).toHaveLength(0);
  });
});

describe('O valuation do usuário que vale para o ativo (decisão 151)', () => {
  it('sem salvo, vale o do motor', () => {
    expect(userValuationOf([], engine.ticker)).toBeNull();
  });

  it('o mais recente divergente vale', () => {
    const mine = divergent();
    expect(mine.changedFields.length).toBeGreaterThan(0);
    expect(userValuationOf([mine], engine.ticker)).toBe(mine);
    expect(userValuationOf([mine], Ticker.parse('PETR4'))).toBeNull();
  });

  it('confirmar depois os números do motor devolve o preço do motor', () => {
    // A lista vem do mais recente ao mais antigo: o primeiro do ativo decide.
    expect(userValuationOf([agreeing(), divergent()], engine.ticker)).toBeNull();
  });
});
