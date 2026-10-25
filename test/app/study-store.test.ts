import { beforeEach, describe, expect, it } from 'vitest';

import {
  ComputationFailure,
  err,
  FinancialGoal,
  Money,
  ok,
  Portfolio,
  PortfolioEntry,
  Ticker,
  Weight,
  Weights,
} from '../../src/core';
import { concentrationOf, emptyStudy, readDraft, StudyActions, useStudy } from '../../src/app/state/study-store';
import type { PortfolioStore } from '../../src/data/persistence/portfolio-store';
import type { PortfolioStudy } from '../../src/data/persistence/portfolio-study';
import { assetOf } from './fixtures';
import { memoryStores, testRuntime } from './harness';

/** Gravação de mentira: registra o que foi salvo, e pode falhar. */
class FakePortfolioStore implements PortfolioStore {
  saved: PortfolioStudy | null = null;
  shouldFail = false;
  async listFor() {
    return ok([]);
  }
  async save(_userId: string, study: PortfolioStudy) {
    if (this.shouldFail) return err(new ComputationFailure('rede indisponível'));
    this.saved = study;
    return ok('estudo-1');
  }
  async delete() {
    return ok(undefined);
  }
}

const state = () => useStudy.getState();

beforeEach(() => {
  testRuntime();
  StudyActions.load(emptyStudy());
});

describe('O estudo — edição síncrona', () => {
  it('começa vazio e sem erro', () => {
    expect(state().study.principal.isEmpty).toBe(true);
    expect(state().study.reserve.isEmpty).toBe(true);
    expect(state().lastError).toBeNull();
  });

  it('adicionar ativo reequipondera a carteira', () => {
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    StudyActions.addAsset(assetOf('VALE3', 'materiais'), true);
    const principal = state().study.principal;
    expect(principal.length).toBe(2);
    expect(Weights.sumsToOne(principal.weights)).toBe(true);
    for (const w of principal.weights) expect(w.value).toBeCloseTo(0.5, 9);
  });

  it('promover ativo move entre as carteiras e reequipondera as duas', () => {
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    StudyActions.addAsset(assetOf('VALE3', 'materiais'), true);
    StudyActions.addAsset(assetOf('ITUB4'), false);
    StudyActions.swap(Ticker.parse('ITUB4'), true);
    expect(state().study.principal.length).toBe(3);
    expect(state().study.reserve.length).toBe(0);
    expect(Weights.sumsToOne(state().study.principal.weights)).toBe(true);
  });

  it('erro de operação vira mensagem, não exceção', () => {
    StudyActions.swap(Ticker.parse('PETR4'), true);
    expect(state().lastError).toContain('PETR4');
  });

  it('teto de 15 ativos é recusado com mensagem clara', () => {
    for (let i = 0; i < 15; i++) StudyActions.addAsset(assetOf(`AAAA${i}`), true);
    expect(state().study.principal.length).toBe(15);
    StudyActions.addAsset(assetOf('BBBB1'), true);
    expect(state().study.principal.length).toBe(15);
    expect(state().lastError).toContain('15');
  });

  it('equalizar restaura pesos iguais num estudo salvo desigual', () => {
    const current = state().study;
    StudyActions.load(
      current.copyWith({
        principal: new Portfolio({
          id: current.principal.id,
          name: current.principal.name,
          kind: current.principal.kind,
          entries: new Map([
            [Ticker.parse('PETR4'), new PortfolioEntry({ asset: assetOf('PETR4', 'energia'), weight: Weight.fraction(0.9) })],
            [Ticker.parse('VALE3'), new PortfolioEntry({ asset: assetOf('VALE3', 'materiais'), weight: Weight.fraction(0.1) })],
          ]),
        }),
      }),
    );
    StudyActions.equalize(true);
    for (const w of state().study.principal.weights) expect(w.value).toBeCloseTo(0.5, 9);
  });

  it('o rascunho acompanha cada mudança, e relê igual', () => {
    StudyActions.rename('Dividendos');
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    StudyActions.addAsset(assetOf('ITUB4'), false);
    const draft = readDraft()!;
    expect(draft.name).toBe('Dividendos');
    expect(draft.principal.tickers.map((t) => t.value)).toEqual(['PETR4']);
    expect(draft.reserve.tickers.map((t) => t.value)).toEqual(['ITUB4']);
  });

  it('estudo novo preserva a meta', () => {
    const goal = FinancialGoal.unvalidated({
      initialContribution: Money.fromReais(10000),
      monthlyContribution: Money.fromReais(1000),
      months: 120,
      targetWealth: Money.fromReais(500000),
    });
    StudyActions.setGoal(goal);
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    StudyActions.startNew();
    expect(state().study.principal.isEmpty).toBe(true);
    expect(state().study.goal).toBe(goal);
  });
});

describe('Concentração setorial reativa', () => {
  it('acompanha cada alteração da carteira', () => {
    expect(concentrationOf(state().study.principal).hasAlert).toBe(false);
    StudyActions.addAsset(assetOf('ITUB4', 'financeiro'), true);
    expect(concentrationOf(state().study.principal).hasAlert).toBe(false);
    StudyActions.addAsset(assetOf('BBAS3', 'financeiro'), true);
    const report = concentrationOf(state().study.principal);
    expect(report.hasAlert).toBe(true);
    expect(report.concentrated[0]!.sector.key).toBe('financeiro');
    expect(report.concentrated[0]!.count).toBe(2);
  });

  it('o alerta some quando o ativo é rebaixado para a reserva', () => {
    StudyActions.addAsset(assetOf('ITUB4', 'financeiro'), true);
    StudyActions.addAsset(assetOf('BBAS3', 'financeiro'), true);
    StudyActions.swap(Ticker.parse('BBAS3'), false);
    expect(concentrationOf(state().study.principal).hasAlert).toBe(false);
  });

  it('não bloqueia a operação, apenas sinaliza', () => {
    StudyActions.addAsset(assetOf('ITUB4', 'financeiro'), true);
    StudyActions.addAsset(assetOf('BBAS3', 'financeiro'), true);
    StudyActions.addAsset(assetOf('SANB11', 'financeiro'), true);
    expect(state().study.principal.length).toBe(3);
    expect(state().lastError, 'concentrar é decisão do investidor, não erro').toBeNull();
    expect(concentrationOf(state().study.principal).hasAlert).toBe(true);
  });
});

describe('O estudo — persistência', () => {
  it('sem sessão identificada, salvar recusa e explica', async () => {
    testRuntime({ user: null });
    expect(await StudyActions.save()).toBe(false);
    expect(state().lastError).toContain('Sessão não identificada');
  });

  it('salvar guarda o identificador devolvido', async () => {
    const store = new FakePortfolioStore();
    testRuntime({ cloudStores: { portfolios: store, valuations: memoryStores().valuations } });
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    expect(await StudyActions.save()).toBe(true);
    expect(state().study.id).toBe('estudo-1');
    expect(store.saved!.principal.length).toBe(1);
  });

  it('falha ao salvar não perde o estado editado', async () => {
    const store = new FakePortfolioStore();
    store.shouldFail = true;
    testRuntime({ cloudStores: { portfolios: store, valuations: memoryStores().valuations } });
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    expect(await StudyActions.save()).toBe(false);
    expect(state().study.principal.length).toBe(1);
    expect(state().isSaving).toBe(false);
    expect(state().lastError).not.toBeNull();
  });

  it('em modo local, grava no navegador e a lista mostra o estudo', async () => {
    const runtime = testRuntime({ local: true, cloudStores: null });
    StudyActions.rename('Local');
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    expect(await StudyActions.save()).toBe(true);
    await StudyActions.refreshSaved();
    expect(state().saved.status).toBe('ready');
    expect(state().saved.studies.map((s) => s.name)).toEqual(['Local']);
    const listed = await runtime.localStores.portfolios.listFor('usuario-1');
    expect(listed.unwrap()).toHaveLength(1);
  });

  it('apagar o estudo aberto desfaz o vínculo e mantém a tela', async () => {
    testRuntime();
    StudyActions.addAsset(assetOf('PETR4', 'energia'), true);
    await StudyActions.save();
    const id = state().study.id!;
    expect(await StudyActions.deleteSaved(id)).toBe(true);
    expect(state().study.id).toBeNull();
    expect(state().study.principal.length).toBe(1);
  });
});
