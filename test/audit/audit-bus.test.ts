import { afterEach, describe, expect, it } from 'vitest';

import {
  AuditEvent,
  AuditIds,
  AuditRecorder,
  CapmInputs,
  DateTime,
  FundamentalsSnapshot,
  Ticker,
  ValuationCascade,
  ValuationInputs,
} from '../../src/core';
import { AuditBus } from '../../src/audit/audit-bus';
import type { AuditChannel } from '../../src/audit/audit-channel';
import { auditFileName, buildAuditDocument, matchesFilter, matchesQuery } from '../../src/audit/audit-export';
import { day } from '../core/helpers';

/**
 * O barramento de auditoria, pelo caminho de produção inteiro: o cálculo chama
 * [AuditRecorder], o barramento recebe, e a outra janela recebe pelo canal.
 * Montar eventos direto no barramento testaria contra uma fixture escrita à
 * mão, que é o tipo de segunda verdade que o painel existe para eliminar.
 */

/** Um `BroadcastChannel` em memória: entrega a todos do mesmo nome, menos ao remetente. */
class Hub {
  private readonly members = new Set<HubChannel>();
  open = (_name: string): AuditChannel => {
    const c = new HubChannel(this);
    this.members.add(c);
    return c;
  };
  deliver(from: HubChannel, json: string): void {
    for (const m of this.members) if (m !== from) m.receive(json);
  }
  leave(c: HubChannel): void {
    this.members.delete(c);
  }
}

class HubChannel implements AuditChannel {
  readonly supportsCrossWindow = true;
  private readonly listeners = new Set<(json: string) => void>();
  readonly sent: string[] = [];
  constructor(private readonly hub: Hub) {}
  post(json: string): void {
    this.sent.push(json);
    this.hub.deliver(this, json);
  }
  listen(onMessage: (json: string) => void): () => void {
    this.listeners.add(onMessage);
    return () => this.listeners.delete(onMessage);
  }
  receive(json: string): void {
    for (const l of this.listeners) l(json);
  }
  close(): void {
    this.hub.leave(this);
  }
}

const buses: AuditBus[] = [];
function bus(hub: Hub = new Hub()): AuditBus {
  const b = new AuditBus(hub.open);
  buses.push(b);
  return b;
}

afterEach(() => {
  for (const b of buses.splice(0)) b.dispose();
  AuditRecorder.detach();
});

function emitValuation(tickerCode = 'PETR4'): void {
  const ticker = Ticker.parse(tickerCode);
  const fundamentals: FundamentalsSnapshot[] = [];
  for (let year = 2016; year <= 2025; year++) {
    const k = year - 2015;
    fundamentals.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(year, 12, 31),
        netIncome: 1000 * k,
        ebit: 1400 * k,
        ebitda: 1800 * k,
        incomeBeforeTax: 1300 * k,
        // Negativo, na convenção da fonte: 1300 − 300 = 1000 de líquido.
        incomeTaxExpense: -300 * k,
        interestExpense: 120,
        operatingCashFlow: 1600 * k,
        freeCashFlow: 1200 * k,
        shortTermDebt: 400,
        longTermDebt: 1600,
        cash: 300,
        nopat: 1000 * k,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 20000,
        bookValuePerShare: 8 * k,
        enterpriseToEbitda: 6,
      }),
    );
  }
  ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 8, 20),
      fundamentals,
      marketPrice: 20,
      capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055 }),
    }),
  );
}

const network = (i: number): AuditEvent =>
  new AuditEvent({
    transactionId: `rede-${i}`,
    timestamp: DateTime.now(),
    endpoint: '/v2/stocks/quote',
    inputPayload: { method: 'GET' },
    outputPayload: { statusCode: 200 },
    executionTimeMs: 1,
  });

describe('Na janela que calcula', () => {
  it('um cálculo real entra no histórico no instante em que acontece', () => {
    const b = bus();
    b.start('emitter');
    emitValuation();
    expect(b.history).toHaveLength(1);
    expect(b.history[0]!.endpoint).toBe('/core/valuation/PETR4');
    expect(b.history[0]!.calculations.length).toBeGreaterThan(0);
  });

  it('o snapshot muda de referência a cada evento, e só então', () => {
    const b = bus();
    b.start('emitter');
    const before = b.getSnapshot();
    expect(b.getSnapshot()).toBe(before);
    AuditRecorder.emit(network(1));
    expect(b.getSnapshot()).not.toBe(before);
  });

  it('o mesmo evento não entra duas vezes', () => {
    const b = bus();
    b.start('emitter');
    AuditRecorder.emit(network(1));
    AuditRecorder.emit(network(1));
    expect(b.history).toHaveLength(1);
  });

  it('recusa antes do primeiro passo é cálculo, e não rede (D4)', () => {
    const b = bus();
    b.start('emitter');
    // Sem preço de mercado a cascata recusa antes de qualquer passo, e o
    // evento sai sem fórmula decomposta — a regra antiga o filtrava como rede.
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker: Ticker.parse('VALE3'),
        asOf: day(2026, 8, 20),
        fundamentals: [],
        marketPrice: 0,
        capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
      }),
    );
    const event = b.history.find((e) => e.endpoint === '/core/valuation/VALE3')!;
    expect(matchesFilter(event, 'calculos')).toBe(true);
    expect(matchesFilter(event, 'rede')).toBe(false);
  });

  it('o ruído de rede não empurra a avaliação para fora (D4)', () => {
    const b = bus();
    b.start('emitter');
    emitValuation();
    for (let i = 0; i < AuditBus.networkLimit + 50; i++) AuditRecorder.emit(network(i));
    expect(b.history.filter((e) => AuditBus.isCalculation(e)), 'a avaliação continua no histórico').toHaveLength(1);
    expect(b.discardedNetwork).toBe(50);
    expect(b.discardedCalculations).toBe(0);
  });

  it('o descarte de cálculos é contado, e limpar zera (D4)', () => {
    const b = bus();
    b.start('emitter');
    for (let i = 0; i < AuditBus.calculationLimit + 3; i++) {
      AuditRecorder.emit(
        new AuditEvent({
          transactionId: `calc-${i}`,
          timestamp: DateTime.now(),
          endpoint: `/core/valuation/X${i}`,
          inputPayload: {},
          outputPayload: { status: 'ok' },
          executionTimeMs: 1,
        }),
      );
    }
    expect(b.discardedCalculations).toBe(3);
    expect(b.history[0]!.transactionId, 'sai o mais antigo').toBe('calc-3');
    b.clear();
    expect(b.discardedCalculations).toBe(0);
    expect(b.history).toHaveLength(0);
  });
});

describe('Entre janelas — equisim_audit_channel_v1', () => {
  it('o nome do canal é o combinado', () => {
    expect(AuditBus.channelName).toBe('equisim_audit_channel_v1');
  });

  it('o painel aberto depois recebe o histórico por replay', () => {
    const hub = new Hub();
    const main = bus(hub);
    main.start('emitter');
    emitValuation();
    AuditRecorder.emit(network(7));

    const logs = bus(hub);
    logs.start('inspector');
    expect(logs.history.map((e) => e.endpoint)).toEqual(['/core/valuation/PETR4', '/v2/stocks/quote']);
    expect(logs.getSnapshot().peerConnected).toBe(true);
    expect(logs.getSnapshot().role).toBe('inspector');
  });

  it('o painel aberto antes fica sabendo quando a janela principal sobe', () => {
    const hub = new Hub();
    const logs = bus(hub);
    logs.start('inspector');
    expect(logs.getSnapshot().peerConnected).toBe(false);

    const main = bus(hub);
    main.start('emitter');
    expect(logs.getSnapshot().peerConnected, 'o aperto de mão marca a conexão').toBe(true);
    emitValuation();
    expect(logs.history).toHaveLength(1);
  });

  it('o evento atravessa inteiro: o JSON do lado de lá é o do lado de cá', () => {
    const hub = new Hub();
    const main = bus(hub);
    main.start('emitter');
    const logs = bus(hub);
    logs.start('inspector');
    emitValuation();
    expect(JSON.stringify(logs.history[0]!.toJson())).toBe(JSON.stringify(main.history[0]!.toJson()));
  });

  it('o painel mostra os descartes da origem, que ele não viu acontecer', () => {
    const hub = new Hub();
    const main = bus(hub);
    main.start('emitter');
    for (let i = 0; i < AuditBus.networkLimit + 5; i++) AuditRecorder.emit(network(i));
    const logs = bus(hub);
    logs.start('inspector');
    expect(logs.history).toHaveLength(AuditBus.networkLimit);
    expect(logs.discardedNetwork).toBe(5);
  });

  it('limpar no painel limpa a janela que calcula, e o replay seguinte vem vazio', () => {
    const hub = new Hub();
    const main = bus(hub);
    main.start('emitter');
    emitValuation();
    const logs = bus(hub);
    logs.start('inspector');
    logs.clear();
    expect(main.history).toHaveLength(0);
    logs.requestReplay();
    expect(logs.history).toHaveLength(0);
  });

  it('mensagem ilegível é ignorada, sem derrubar o barramento', () => {
    const hub = new Hub();
    const logs = bus(hub);
    logs.start('inspector');
    const intruder = hub.open('x') as HubChannel;
    intruder.post('{isto não é json');
    intruder.post(JSON.stringify({ kind: 'event', event: 'não é objeto' }));
    expect(logs.history).toHaveLength(0);
  });

  it('o inspetor não responde a pedidos de replay: só quem calcula tem histórico', () => {
    const hub = new Hub();
    const a = bus(hub);
    a.start('inspector');
    const b = bus(hub);
    b.start('inspector');
    expect(a.history).toHaveLength(0);
    expect(b.history).toHaveLength(0);
  });
});

describe('A exportação — formato 2', () => {
  it('é íntegra: completa, declarada e serializável (D4)', () => {
    const b = bus();
    b.start('emitter');
    emitValuation();
    // Um passo degenerado: `NaN` no rastro derrubava o `JSON.stringify` do Dart.
    const tx = AuditRecorder.begin('/core/valuation/NAN3', { inputPayload: { x: Number.NaN } })!;
    tx.step({ formulaName: 'conta degenerada', latex: 'x', variables: { a: Number.POSITIVE_INFINITY }, result: Number.NaN });
    tx.complete({ status: 'ok' });

    const doc = JSON.parse(
      JSON.stringify(
        buildAuditDocument({
          events: b.history,
          historySize: b.history.length,
          filter: 'todos',
          query: '',
          discardedCalculations: b.discardedCalculations,
          discardedNetwork: b.discardedNetwork,
        }),
      ),
    ) as Record<string, unknown>;
    expect(doc['formato']).toBe(2);
    expect(doc['aplicacao']).toBe('Equisim');
    expect(doc['totalDeAvaliacoes']).toBe(2);
    expect(doc['buscaAplicada']).toBeNull();
    expect(doc['descartados']).toEqual({ calculos: 0, rede: 0 });
    expect(doc['aviso']).toBeUndefined();
    const events = doc['eventos'] as Record<string, unknown>[];
    const petr = events.find((e) => e['endpoint'] === '/core/valuation/PETR4')!;
    const original = b.history.find((e) => e.endpoint === '/core/valuation/PETR4')!;
    expect(JSON.stringify(petr), 'o arquivo leva o evento inteiro, sem corte').toBe(JSON.stringify(original.toJson()));
    const nan = events.find((e) => e['endpoint'] === '/core/valuation/NAN3')!;
    const step = (nan['calculations'] as Record<string, unknown>[])[0]!;
    expect(step['finalValue']).toBe('NaN');
  });

  it('declara a busca, o filtro e o descarte', () => {
    const events = [network(1)];
    const doc = buildAuditDocument({
      events,
      historySize: 40,
      filter: 'rede',
      query: '  quote ',
      discardedCalculations: 0,
      discardedNetwork: 2,
    });
    expect(doc['filtroAplicado']).toBe('rede');
    expect(doc['buscaAplicada']).toBe('quote');
    expect(doc['totalNoHistorico']).toBe(40);
    expect(doc['aviso']).toContain('não tem a sessão inteira');
  });

  it('a busca casa endereço, transação e nome de fórmula', () => {
    const b = bus();
    b.start('emitter');
    emitValuation();
    const event = b.history[0]!;
    expect(matchesQuery(event, 'petr4')).toBe(true);
    expect(matchesQuery(event, event.transactionId.substring(0, 8).toUpperCase())).toBe(true);
    expect(matchesQuery(event, event.calculations[0]!.formulaName.substring(0, 6))).toBe(true);
    expect(matchesQuery(event, 'nada-a-ver')).toBe(false);
    expect(matchesQuery(event, '   ')).toBe(true);
  });

  it('o nome do arquivo não tem dois-pontos nem fração de segundo', () => {
    expect(auditFileName(DateTime.local(2026, 10, 23, 9, 5, 7, 123))).toBe('equisim-auditoria-2026-10-23T09-05-07.json');
  });

  it('o identificador da transação é um UUID v4', () => {
    expect(AuditIds.uuidV4()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});
