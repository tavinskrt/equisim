import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  DateTime,
  ImpliedPremiumCodec,
  ImpliedPremiumPackage,
  ImpliedPremiumQuarter,
  MarketPremiumSource,
} from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { MarketPremiumRepository } from '../../src/data/repositories/market-premium-repository';
import { expectClose } from '../core/helpers';
import { isServed, readPublicJson } from './public-assets';

/**
 * A série do prêmio implícito versionada é o que o build leva (decisão 142).
 *
 * **Sem ela o prêmio é outro**: os 5,5% parametrizados, quatro pontos acima da
 * média de dez anos que o preço da bolsa embute. No aplicativo isso vira
 * ressalva; aqui **reprova a suíte**: um build que sai sem a série por
 * descuido não é estado aceitável.
 */

/** Trimestres de 2011 a meados de 2026, com `r − Rf` igual a [premium]. */
function premiumPackage(premium: number, generated?: DateTime): string {
  const quarters: ImpliedPremiumQuarter[] = [];
  for (let year = 2011; year <= 2026; year++) {
    for (const month of [3, 6, 9, 12]) {
      if (year === 2026 && month > 6) continue;
      // `DateTime.utc(year, month + 1, 0)`: o dia zero do mês seguinte é o
      // último deste, como no Dart.
      quarters.push(
        new ImpliedPremiumQuarter({ date: DateTime.utc(year, month + 1, 0), impliedReturn: 0.12 + premium, riskFree: 0.12 }),
      );
    }
  }
  return JSON.stringify(
    ImpliedPremiumCodec.encode(new ImpliedPremiumPackage({ generatedAt: generated ?? DateTime.utc(2026, 9, 14), quarters })),
  );
}

it('o pacote existe em public/, de onde o build o serve', () => {
  expect(isServed(AssetPaths.marketPremium), 'gerar com `npm run tool -- implied-premium --so-serie` e versionar').toBe(
    true,
  );
});

it('o pacote é legível pelo codec deste build, e a média é plausível', () => {
  const json = readPublicJson(AssetPaths.marketPremium);
  expect(json['versao'], 'o codec mudou de versão e o pacote não foi regerado').toBe(ImpliedPremiumCodec.version);
  const parsed = ImpliedPremiumCodec.decode(json);
  expect(parsed).not.toBeNull();
  const mean = parsed!.normalizedAt(parsed!.generatedAt);
  // A média de dez anos ficou entre 1% e 1,6% em todas as datas do backtest
  // (premio_implicito.md). A faixa é larga de propósito: o que ela barra é
  // pacote corrompido, com o prêmio em pontos em vez de fração, ou com o
  // sinal trocado.
  expect(mean).not.toBeNull();
  expect(mean!).toBeGreaterThanOrEqual(-0.02);
  expect(mean!).toBeLessThanOrEqual(0.06);
  expect(
    parsed!.window(parsed!.generatedAt),
    'a série tem de cobrir os dez anos até a data do pacote',
  ).toHaveLength(ImpliedPremiumPackage.windowYears * 4);
});

describe('O repositório', () => {
  it('sem pacote, devolve os 5,5% parametrizados e diz isso', async () => {
    const r = new MarketPremiumRepository({
      loadPackage: async () => {
        throw new Error('sem asset');
      },
    });
    const reading = await r.reading();
    expect(reading.premium).toBe(CapmInputs.defaultMarketPremium);
    expect(reading.source).toBe(MarketPremiumSource.parameterized);
    expect(reading.note).toContain('5,5%');
  });

  it('pacote recente: a média de dez anos, sem ressalva', async () => {
    const r = new MarketPremiumRepository({
      loadPackage: async () => premiumPackage(0.0124),
      today: () => DateTime.local(2026, 10, 1),
    });
    const reading = await r.reading();
    expectClose(reading.premium, 0.0124, 1e-12);
    expect(reading.source).toBe(MarketPremiumSource.impliedNormalized);
    expect(reading.note).toBeNull();
  });

  it('pacote velho continua valendo, e a ressalva diz de quando é', async () => {
    const r = new MarketPremiumRepository({
      loadPackage: async () => premiumPackage(0.0124),
      today: () => DateTime.local(2027, 9, 14),
    });
    const reading = await r.reading();
    // A média é a da data do pacote, e não a de uma janela que perdeu
    // trimestres sem ganhar nenhum.
    expectClose(reading.premium, 0.0124, 1e-12);
    expect(reading.source).toBe(MarketPremiumSource.impliedNormalized);
    expect(reading.note).toContain('2026-09-14');
  });

  it('pacote ilegível cai nos 5,5%', async () => {
    const r = new MarketPremiumRepository({ loadPackage: async () => '{"versao": 99}' });
    expect((await r.reading()).source).toBe(MarketPremiumSource.parameterized);
  });
});
