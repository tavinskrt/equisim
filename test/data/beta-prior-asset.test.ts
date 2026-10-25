import { describe, expect, it } from 'vitest';

import { BetaPrior, BetaPriorCodec, DateTime } from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { BetaPriorRepository } from '../../src/data/repositories/beta-prior-repository';
import { expectClose } from '../core/helpers';
import { isServed, readPublicJson } from './public-assets';

/**
 * O prior transversal do beta versionado é o que o build leva (item B11).
 *
 * **Sem ele o motor é outro**: beta cru, WACC estático, e nenhum dos caminhos
 * que as decisões 40 a 46 descrevem. No aplicativo isso vira ressalva — a
 * avaliação segue e diz que seguiu sem o prior. Aqui **reprova a suíte**: um
 * build que sai sem o prior por descuido não é estado aceitável.
 */

it('o pacote existe em public/, de onde o build o serve', () => {
  expect(isServed(AssetPaths.betaPrior), 'gerar com `npm run tool -- beta-prior-package` e versionar').toBe(true);
});

it('o pacote é legível pelo codec deste build', () => {
  const json = readPublicJson(AssetPaths.betaPrior);
  expect(json['versao'], 'o codec mudou de versão e o pacote não foi regerado').toBe(BetaPriorCodec.version);
  const parsed = BetaPriorCodec.decode(json);
  expect(parsed).not.toBeNull();
  // Beta desalavancado do universo brasileiro: 0,64 em 14/09/2026. A faixa é
  // larga de propósito — o que ela barra é pacote corrompido ou gerado com
  // outra régua de alavancagem, não uma variação de mercado.
  expect(parsed!.prior.unleveredUniverse).toBeGreaterThanOrEqual(0.2);
  expect(parsed!.prior.unleveredUniverse).toBeLessThanOrEqual(1.5);
  expect(parsed!.prior.dispersion).toBeGreaterThan(0);
  expect(parsed!.prior.unleveredBySector.size).toBeGreaterThan(0);
  expect(parsed!.observations).toBeGreaterThan(100);
});

it('cada mediana setorial usa a chave da B3, e não a da fonte de preços', () => {
  const parsed = BetaPriorCodec.decode(readPublicJson(AssetPaths.betaPrior))!;
  // As chaves são as do setor econômico da B3 (decisão 87). Uma chave fora
  // dessa lista diz que o prior foi resolvido sobre outra camada de dados, e
  // aí ele agrupa outros pares.
  const fromB3 = new Set([
    'bens-industriais',
    'comunicacoes',
    'consumo-ciclico',
    'consumo-nao-ciclico',
    'financeiro',
    'materiais-basicos',
    'petroleo-gas-e-biocombustiveis',
    'saude',
    'tecnologia-da-informacao',
    'utilidade-publica',
    'outros',
  ]);
  for (const k of parsed.prior.unleveredBySector.keys()) {
    expect(fromB3.has(k), k).toBe(true);
  }
});

describe('O repositório', () => {
  it('sem pacote, devolve nulo e diz que o motor é o do beta cru', async () => {
    const r = new BetaPriorRepository({
      loadPackage: async () => {
        throw new Error('sem asset');
      },
    });
    const reading = await r.reading();
    expect(reading.prior).toBeNull();
    expect(reading.note).toContain('beta');
  });

  it('pacote velho demais não é usado, e a ressalva diz de quando é', async () => {
    const pkg = JSON.stringify(
      BetaPriorCodec.encode(new BetaPrior({ unleveredBySector: new Map(), unleveredUniverse: 0.64, dispersion: 0.5 }), {
        generatedAt: DateTime.local(2020, 1, 1),
        observations: 300,
      }),
    );
    const r = new BetaPriorRepository({ loadPackage: async () => pkg, today: () => DateTime.local(2026, 9, 14) });
    const reading = await r.reading();
    expect(reading.prior).toBeNull();
    expect(reading.note).toContain('2020-01-01');
  });

  it('pacote dentro da validade passa sem ressalva', async () => {
    const pkg = JSON.stringify(
      BetaPriorCodec.encode(
        new BetaPrior({ unleveredBySector: new Map([['saude', 0.78]]), unleveredUniverse: 0.64, dispersion: 0.5 }),
        { generatedAt: DateTime.local(2026, 6, 30), observations: 300 },
      ),
    );
    const r = new BetaPriorRepository({ loadPackage: async () => pkg, today: () => DateTime.local(2026, 9, 14) });
    const reading = await r.reading();
    expect(reading.note).toBeNull();
    expectClose(reading.prior!.unleveredFor('saude'), 0.78, 1e-9);
    expectClose(reading.prior!.unleveredFor('nao-existe'), 0.64, 1e-9);
  });

  it('versão desconhecida é recusada, e não lida pela metade', async () => {
    const r = new BetaPriorRepository({
      loadPackage: async () =>
        JSON.stringify({ versao: BetaPriorCodec.version + 1, universo: 0.64, dispersao: 0.5, geradoEm: '2026-09-14' }),
    });
    expect((await r.reading()).prior).toBeNull();
  });
});
