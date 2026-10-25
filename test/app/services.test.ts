import { afterEach, describe, expect, it } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  CapmInputs,
  MarketAnchors,
  MarketPremiumSource,
  Ticker,
} from '../../src/core';
import { goalFeasibility, valuate } from '../../src/app/valuation';
import { demoGoal } from './fixtures';
import { offlineServices } from './harness';

afterEach(() => AuditRecorder.detach());

describe('A raiz de dependências, sem rede', () => {
  it('as âncoras recuam para as medidas em 2026, e a meta continua avaliável', async () => {
    const services = offlineServices();
    expect(await services.marketAnchors()).toBe(MarketAnchors.fallback2026);
    const verdict = await goalFeasibility(services, demoGoal);
    expect(verdict).not.toBeNull();
    expect(verdict!.anchors).toBe(MarketAnchors.fallback2026);
  });

  it('os pacotes do build são lidos de public/, uma vez por sessão', async () => {
    let reads = 0;
    const services = offlineServices({
      loadText: async (path) => {
        reads++;
        const { readFileSync } = await import('node:fs');
        return readFileSync(`public/${path}`, 'utf8');
      },
    });
    const premium = await services.marketPremiumReading();
    expect(premium.source).not.toBe(MarketPremiumSource.parameterized);
    expect((await services.calibratedBands()).length).toBeGreaterThan(0);
    expect(await services.skillReading()).not.toBeNull();
    const before = reads;
    await services.marketPremiumReading();
    await services.calibratedBands();
    expect(reads, 'a segunda leitura é da memória').toBe(before);
  });

  it('sem pacote, o prêmio é o parametrizado e nada derruba a leitura', async () => {
    const services = offlineServices({
      loadText: async () => {
        throw new Error('sem asset');
      },
    });
    const premium = await services.marketPremiumReading();
    expect(premium.premium).toBe(CapmInputs.defaultMarketPremium);
    expect(await services.skillReading()).toBeNull();
    expect(await services.calibratedBands()).toEqual([]);
    expect((await services.distressedRegistry()).contains('OIBR3')).toBe(false);
  });

  it('a avaliação sem cotação devolve nulo, e a falha do preparo vai ao painel', async () => {
    const events: AuditEvent[] = [];
    AuditRecorder.attach((e) => events.push(e));
    const services = offlineServices();
    expect(await valuate(services, Ticker.parse('PETR4'))).toBeNull();
    const prep = events.find((e) => e.endpoint === '/core/valuation/PETR4');
    expect(prep, 'o preparo recusado aparece no painel').toBeDefined();
    expect(prep!.outputPayload['status']).toBe('falha');
    // E a ida à rede também, mesmo falhando.
    expect(events.some((e) => !e.endpoint.startsWith('/core/'))).toBe(true);
  });
});
