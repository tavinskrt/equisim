import { expect, it } from 'vitest';

import { type JsonObject, SkillReadingCodec, TransversalOrdering } from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { SkillReadingRepository } from '../../src/data/repositories/skill-reading-repository';
import { expectClose } from '../core/helpers';
import { asObject, isServed, readPublicJson, readRepoJson } from './public-assets';

/**
 * A leitura da habilidade é o que a tela de metas cita na ressalva do prêmio
 * (item B1.0). Pacote ausente ou divergente da medição reprova a suíte: no
 * aplicativo a ausência vira a ressalva de "não medida", e o descuido que
 * importa pegar é o pacote dizer outra coisa que a medição.
 */

const m = (v: unknown): JsonObject => asObject(v, 'habilidade');

it('existe em public/ e é legível', () => {
  expect(
    isServed(AssetPaths.skillReading),
    'gerar com `npm run tool -- conditional-regression --pacote-habilidade` e versionar',
  ).toBe(true);
  expect(SkillReadingCodec.decode(readPublicJson(AssetPaths.skillReading))).not.toBeNull();
});

it('os números, o veredito e o prêmio são os da medição trimestral com deslistadas', () => {
  const reading = SkillReadingCodec.decode(readPublicJson(AssetPaths.skillReading))!;
  const measurement = m(readRepoJson('docs/validacao/habilidade_trimestral.json'));
  const fm = m(m(m(m(measurement['h36'])['trimestral'])['comDeslistadas'])['famaMacBeth']);
  const datum = m(fm['potencialDadoBm']);
  const num = (x: JsonObject, k: string): number => x[k] as number;

  expect(reading.months).toBe(36);
  expect(reading.cohorts).toBe(datum['coortes']);
  expectClose(reading.conditionalCoefficient, num(datum, 'media'), 1e-12);
  expectClose(reading.overlapT, num(datum, 'tSobreposicao'), 1e-12);
  expectClose(reading.overlapCritical, num(datum, 'criticoSobreposicao'), 1e-12);
  expectClose(reading.neweyWestT, num(datum, 'tNeweyWest'), 1e-12);
  // O critério mora no núcleo, e a ferramenta o aplica por conta própria: os
  // dois têm de concordar.
  expect(reading.demonstrated).toBe(datum['passaR3']);

  // As três ordenações lado a lado (item B1), cada uma contra a medição.
  const pairs: readonly (readonly [TransversalOrdering, string])[] = [
    [TransversalOrdering.composite, 'icComposto'],
    [TransversalOrdering.bookToMarket, 'icBookToMarket'],
    [TransversalOrdering.potential, 'icPotencial'],
  ];
  for (const [ordering, key] of pairs) {
    const measured = m(fm[key]);
    const readOrdering = reading.orderings.get(ordering)!;
    expectClose(readOrdering.ic, num(measured, 'media'), 1e-12, key);
    expectClose(readOrdering.overlapT, num(measured, 'tSobreposicao'), 1e-12, key);
    expect(readOrdering.demonstrated, key).toBe(measured['passaR3']);
  }
  // A regra do prêmio é a primeira que passa, na ordem fixada antes de medir.
  const first = pairs.find(([, key]) => m(fm[key])['passaR3'] === true)?.[0] ?? null;
  expect(reading.premiumOrdering).toBe(first);
});

it('sem pacote, ou com lixo, a leitura é nula', async () => {
  const without = new SkillReadingRepository({
    loadPackage: async () => {
      throw new Error('sem');
    },
  });
  expect(await without.reading()).toBeNull();
  const garbage = new SkillReadingRepository({ loadPackage: async () => '[1, 2]' });
  expect(await garbage.reading()).toBeNull();
});
