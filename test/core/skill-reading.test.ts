import { describe, expect, it } from 'vitest';

import { OrderingReading, SkillReadingCodec, TransversalOrdering, type JsonObject } from '../../src/core';

function reading(a: { ic?: number; t?: unknown; critical?: number; nw?: number } = {}): JsonObject {
  return { ic: a.ic ?? 0.1, tCorrigido: 't' in a ? a.t : 0.5, critico: a.critical ?? 2.7, tNeweyWest: a.nw ?? 1.0 };
}

function pkg(
  a: {
    version?: unknown;
    t?: unknown;
    critical?: unknown;
    nw?: unknown;
    composite?: JsonObject;
    bm?: JsonObject;
    upside?: JsonObject;
  } = {},
): JsonObject {
  return {
    versao: 'version' in a ? a.version : 2,
    horizonteMeses: 36,
    coortes: 22,
    potencialDadoBookToMarket: {
      coeficiente: 0.0297,
      tCorrigido: 't' in a ? a.t : 0.2431,
      critico: 'critical' in a ? a.critical : 2.705,
      tNeweyWest: 'nw' in a ? a.nw : 0.6894,
    },
    ordenacoes: {
      composto: a.composite ?? reading({ ic: 0.15 }),
      bookToMarket: a.bm ?? reading({ ic: 0.181, t: 2.92, nw: 7.03 }),
      potencial: a.upside ?? reading({ ic: 0.091, t: 0.74, nw: 1.89 }),
    },
  };
}

describe('Leitura da habilidade — itens B1.0 e B1', () => {
  it('lê o pacote, com as três ordenações', () => {
    const s = SkillReadingCodec.decode(pkg())!;
    expect(s.months).toBe(36);
    expect(s.cohorts).toBe(22);
    expect(s.conditionalCoefficient).toBe(0.0297);
    expect(s.overlapT).toBe(0.2431);
    expect(s.demonstrated).toBe(false);
    expect(s.potentialIc).toBe(0.091);
    expect(s.bookToMarketIc).toBe(0.181);
    expect(s.orderings.get(TransversalOrdering.composite)!.ic).toBe(0.15);
  });

  it('o critério da decisão 96 exige os dois t, e estritamente', () => {
    const withInput = (t: number, nw: number): OrderingReading =>
      new OrderingReading({ ic: 0.1, overlapT: t, overlapCritical: 2.7, neweyWestT: nw });
    expect(withInput(2.71, 2.01).demonstrated).toBe(true);
    expect(withInput(2.71, 2.0).demonstrated, 'o corrigido passa e o Newey-West não').toBe(false);
    expect(withInput(2.7, 3.5).demonstrated, 'o Newey-West passa e o corrigido fica no crítico').toBe(false);
  });

  describe('a regra do prêmio, fixada antes de medir', () => {
    const premium = (a: { composite: boolean; bm: boolean; upside: boolean }): TransversalOrdering | null => {
      const l = (passes: boolean): JsonObject => (passes ? reading({ t: 3.0, nw: 2.5 }) : reading({ t: 1.0, nw: 1.0 }));
      return SkillReadingCodec.decode(pkg({ composite: l(a.composite), bm: l(a.bm), upside: l(a.upside) }))!
        .premiumOrdering;
    };

    it('o composto vem primeiro, quando passa', () => {
      expect(premium({ composite: true, bm: true, upside: true })).toBe(TransversalOrdering.composite);
    });
    it('sem o composto, o book-to-market', () => {
      expect(premium({ composite: false, bm: true, upside: true })).toBe(TransversalOrdering.bookToMarket);
    });
    it('só o potencial passando, o potencial', () => {
      expect(premium({ composite: false, bm: false, upside: true })).toBe(TransversalOrdering.potential);
    });
    it('nenhuma passando, nenhum prêmio', () => {
      expect(premium({ composite: false, bm: false, upside: false })).toBeNull();
    });
  });

  it('pacote malformado não vira leitura: a ressalva não some por descuido', () => {
    expect(SkillReadingCodec.decode(pkg({ version: 1 }))).toBeNull();
    expect(SkillReadingCodec.decode(pkg({ t: '0,24' }))).toBeNull();
    expect(SkillReadingCodec.decode(pkg({ nw: null }))).toBeNull();
    expect(SkillReadingCodec.decode(pkg({ critical: Number.NaN }))).toBeNull();
    expect(SkillReadingCodec.decode(pkg({ bm: reading({ t: Number.POSITIVE_INFINITY }) }))).toBeNull();
    const withoutComposite = { ...pkg(), ordenacoes: { bookToMarket: reading() } };
    expect(SkillReadingCodec.decode(withoutComposite), 'as três ordenações precisam estar no pacote').toBeNull();
    expect(SkillReadingCodec.decode({ versao: 2 })).toBeNull();
  });
});
