import { describe, expect, it } from 'vitest';

import { DateTime, Ticker, UnitCompositionCodec } from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { UnitCompositionRepository } from '../../src/data/repositories/unit-composition-repository';
import { isServed, readPublic, readPublicJson } from './public-assets';

/**
 * A composição declarada das units versionada com o build (item B16).
 *
 * **Sem ela a razão volta a ser inferida do valor de mercado**, que só acerta
 * quando ordinária e preferencial valem o mesmo. No aplicativo isso vira
 * ressalva; aqui reprova a suíte, porque um build sem o pacote avalia nove
 * papéis por uma convenção de fonte que ninguém declarou.
 */

const loadPackage = async (): Promise<string> => readPublic(AssetPaths.unitComposition);

it('o pacote existe em public/, de onde o build o serve', () => {
  expect(isServed(AssetPaths.unitComposition), 'gerar com `npm run tool -- unit-package` e versionar').toBe(true);
});

it('as nove units do universo saem com a composição da FCA', () => {
  const parsed = UnitCompositionCodec.decodePackage(readPublicJson(AssetPaths.unitComposition));
  // Conferido contra o quadro de valores mobiliários da FCA de 2026. A BPAC11
  // só aparece porque a chave é o CNPJ: o código de negociação dela no
  // formulário é `000000`.
  const expected: Record<string, number> = {
    ALUP11: 3,
    BPAC11: 3,
    BRBI11: 3,
    ENGI11: 5,
    IGTI11: 3,
    KLBN11: 5,
    SANB11: 2,
    SAPR11: 5,
    TAEE11: 3,
  };
  for (const [ticker, shares] of Object.entries(expected)) {
    const c = UnitCompositionCodec.at(parsed.get(ticker) ?? [], DateTime.local(2026, 9, 14));
    expect(c?.shares, ticker).toBe(shares);
    expect(c?.declared.length ?? 0, `${ticker} sem o texto declarado`).toBeGreaterThan(0);
  }
});

it('a série é por ano, e a ENGI11 de 2018 já sai com cinco', () => {
  const parsed = UnitCompositionCodec.decodePackage(readPublicJson(AssetPaths.unitComposition));
  // Em 2018 a companhia declarou "1 ENG3 e 4 ENGI4": código de três letras,
  // que o leitor antigo não somava.
  expect(UnitCompositionCodec.at(parsed.get('ENGI11')!, DateTime.local(2018, 12, 31))?.shares).toBe(5);
  expect(parsed.get('ENGI11')!.length, 'um formulário por ano, e não só o último').toBeGreaterThan(1);
});

describe('O repositório', () => {
  it('devolve a composição vigente na data', async () => {
    const r = new UnitCompositionRepository({ loadPackage });
    expect(await r.sharesPerUnitFor(Ticker.parse('SAPR11'), { asOf: DateTime.local(2026, 9, 14) })).toBe(5);
    expect(
      await r.sharesPerUnitFor(Ticker.parse('BRBI11'), { asOf: DateTime.local(2019, 1, 1) }),
      'a BRBI11 só declara de 2022 em diante',
    ).toBeNull();
  });

  it('papel que não é unit não tem composição', async () => {
    const r = new UnitCompositionRepository({ loadPackage });
    expect(await r.sharesPerUnitFor(Ticker.parse('PETR4'), { asOf: DateTime.local(2026, 9, 14) })).toBeNull();
  });

  it('sem data, vale o relógio injetado — e ele é injetado', async () => {
    // A raiz de dependências não lê o relógio no ponto de uso: ela o entrega
    // ao repositório, que é o que torna a composição vigente testável.
    const r = new UnitCompositionRepository({ loadPackage, today: () => DateTime.local(2019, 1, 1) });
    expect(await r.sharesPerUnitFor(Ticker.parse('BRBI11')), 'em 2019 a BRBI11 ainda não declarava').toBeNull();
    expect(await r.sharesPerUnitFor(Ticker.parse('SAPR11'))).toBe(5);
  });

  it('sem pacote, é transparente', async () => {
    const r = new UnitCompositionRepository({
      loadPackage: async () => {
        throw new Error('sem asset');
      },
    });
    expect(await r.sharesPerUnitFor(Ticker.parse('SAPR11'), { asOf: DateTime.local(2026, 9, 14) })).toBeNull();
  });
});
