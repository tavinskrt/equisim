import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  CapmInputs,
  FundamentalsSnapshot,
  Ticker,
  ValuationInputs,
  type ValuationResult,
} from '../../src/core';
import { StructuredCodec } from '../../src/data/runner/structured-codec';
import { evaluateRequest } from '../../src/data/runner/valuation-request';
import type { WorkerCall, WorkerReply } from '../../src/data/runner/valuation-worker-handler';
import { ValuationRunner } from '../../src/data/runner/valuation-runner';
import { day } from '../core/helpers';

/**
 * O rastro atravessa o Worker (item D4).
 *
 * O coletor de auditoria é estático e local ao contexto: a avaliação que migra
 * para o Worker — Monte Carlo com 20 mil sorteios ou mais — sairia sem evento
 * no painel de logs. Aqui o "Worker" é o manipulador real carregado num grafo
 * de módulos **próprio** (`vi.resetModules`), com o seu núcleo, o seu coletor
 * e o seu cache de tickers, e as mensagens passam por `structuredClone`, que é
 * a cópia que o `postMessage` faz. É o isolamento que o navegador dá.
 */

const ticker = Ticker.parse('PETR4');
const inputs = new ValuationInputs({
  ticker,
  asOf: day(2026, 8, 20),
  fundamentals: Array.from({ length: 10 }, (_, i) => {
    const year = 2016 + i;
    const k = year - 2015;
    return new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      netIncome: 1000.0 * k,
      ebit: 1400.0 * k,
      ebitda: 1800.0 * k,
      incomeBeforeTax: 1300.0 * k,
      incomeTaxExpense: -300.0 * k,
      interestExpense: 120.0,
      operatingCashFlow: 1600.0 * k,
      freeCashFlow: 1200.0 * k,
      shortTermDebt: 400.0,
      longTermDebt: 1600.0,
      cash: 300.0,
      nopat: 1000.0 * k,
      sharesOutstanding: 1000.0,
      sharesOutstandingAsOf: 1000.0,
      marketCap: 20000.0,
      bookValuePerShare: 8.0 * k,
    });
  }),
  marketPrice: 20.0,
  capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055 }),
});

/** Um Worker de mentira que roda o manipulador real num grafo de módulos isolado. */
async function loopbackFactory(): Promise<{ factory: () => Worker; calls: () => number }> {
  vi.resetModules();
  const isolated = await import('../../src/data/runner/valuation-worker-handler');
  vi.resetModules();
  let count = 0;
  const factory = (): Worker => {
    const worker = {
      onmessage: null as ((m: MessageEvent<WorkerReply>) => void) | null,
      onerror: null,
      onmessageerror: null,
      postMessage(message: WorkerCall) {
        count++;
        const copy = structuredClone(message);
        setTimeout(() => {
          const reply = structuredClone(isolated.handleWorkerCall(copy));
          worker.onmessage?.({ data: reply } as MessageEvent<WorkerReply>);
        }, 0);
      },
      terminate() {},
    };
    return worker as unknown as Worker;
  };
  return { factory, calls: () => count };
}

afterEach(() => AuditRecorder.detach());

describe('ValuationRunner', () => {
  it('a avaliação que migra para o Worker chega ao painel com o rastro', async () => {
    const { factory, calls } = await loopbackFactory();
    const events: AuditEvent[] = [];
    AuditRecorder.attach((e) => events.push(e));

    const runner = new ValuationRunner(factory);
    const r = await runner.run({ inputs, monteCarlo: true, samples: ValuationRunner.workerThresholdSamples });

    expect(calls(), 'a conta foi de fato ao Worker').toBe(1);
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    expect(events).toHaveLength(1);
    expect(events[0]!.endpoint).toBe('/core/valuation/PETR4');
    expect(events[0]!.calculations.length).toBeGreaterThan(0);
    expect(events[0]!.outputPayload['fairValue']).toBe(r.unwrap().fairValue.reais);
    expect(AuditRecorder.isActive, 'o coletor deste contexto continua ligado').toBe(true);
  });

  it('o resultado do Worker é idêntico ao calculado em linha', async () => {
    const { factory } = await loopbackFactory();
    const request = { inputs, monteCarlo: true, samples: ValuationRunner.workerThresholdSamples };
    const viaWorker = (await new ValuationRunner(factory).run(request)).unwrap();
    const inline = evaluateRequest(request).unwrap();
    expect(viaWorker.fairValue).toEqual(inline.fairValue);
    expect(viaWorker.model).toBe(inline.model);
    expect(viaWorker.ticker, 'o ticker volta reinternado').toBe(ticker);
    expect(StructuredCodec.encode(viaWorker)).toEqual(StructuredCodec.encode(inline));
  });

  it('a recusa dentro do Worker volta como falha, com o evento, e sem travar', async () => {
    // Lente `risco`, 25/09/2026: o teste cobria só o caminho feliz. Sem
    // exercícios não há via, e a cascata recusa — dentro do Worker. A falha
    // tem de voltar como `Err`, com o evento de recusa no painel.
    const { factory } = await loopbackFactory();
    const events: AuditEvent[] = [];
    AuditRecorder.attach((e) => events.push(e));

    const r = await new ValuationRunner(factory).run({
      inputs: inputs.withFundamentals([]),
      monteCarlo: true,
      samples: ValuationRunner.workerThresholdSamples,
    });

    expect(r.isErr).toBe(true);
    expect(events).toHaveLength(1);
    expect(events[0]!.endpoint).toBe('/core/valuation/PETR4');
  });

  it('sem ninguém ouvindo, o Worker não monta rastro', async () => {
    const { factory } = await loopbackFactory();
    expect(AuditRecorder.isActive).toBe(false);
    const r = await new ValuationRunner(factory).run({
      inputs,
      monteCarlo: true,
      samples: ValuationRunner.workerThresholdSamples,
    });
    expect(r.isOk).toBe(true);
  });

  it('abaixo do limiar a conta roda em linha, sem Worker', async () => {
    const { factory, calls } = await loopbackFactory();
    const r = await new ValuationRunner(factory).run({ inputs, monteCarlo: true, samples: 10000 });
    expect(r.isOk).toBe(true);
    expect(calls()).toBe(0);
  });

  it('Worker quebrado recua para o cálculo em linha, com o mesmo número', async () => {
    const broken = (): Worker => {
      const worker = {
        onmessage: null,
        onerror: null as (() => void) | null,
        onmessageerror: null,
        postMessage() {
          setTimeout(() => worker.onerror?.(), 0);
        },
        terminate() {},
      };
      return worker as unknown as Worker;
    };
    const request = { inputs, monteCarlo: true, samples: ValuationRunner.workerThresholdSamples };
    const r = await new ValuationRunner(broken).run(request);
    const inline: ValuationResult = evaluateRequest(request).unwrap();
    expect(r.unwrap().fairValue).toEqual(inline.fairValue);
  });
});
