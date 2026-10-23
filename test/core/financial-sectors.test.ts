import { describe, expect, it } from 'vitest';

import { FinancialSectors } from '../../src/core';

const fin = (key: string | null, sub?: string): boolean =>
  FinancialSectors.isFinancial({ sectorKey: key, industry: sub ?? null });

describe('Porta 1 pela taxonomia oficial — item A5', () => {
  it('os três bancos que chegavam sem setor passam a ser financeiros', () => {
    // BRSR6, PINE4 e SANB4: a B3 os classifica pelo emissor.
    expect(fin('financeiro', 'Intermediários Financeiros / Bancos')).toBe(true);
  });

  it('seguradora, resseguradora e bolsa entram', () => {
    expect(fin('financeiro', 'Previdência e Seguros / Seguradoras')).toBe(true);
    expect(fin('financeiro', 'Previdência e Seguros / Resseguradoras')).toBe(true);
    expect(fin('financeiro', 'Serviços Financeiros Diversos / Serviços Financeiros Diversos')).toBe(true);
  });

  it('shopping e holding, que a B3 também põe em Financeiro, não entram', () => {
    expect(fin('financeiro', 'Exploração de Imóveis / Exploração de Imóveis')).toBe(false);
    expect(fin('financeiro', 'Holdings Diversificadas / Holdings Diversificadas')).toBe(false);
    expect(fin('financeiro'), 'setor sem subsetor não basta').toBe(false);
  });

  it('a chave da fonte de preços continua valendo no recuo', () => {
    expect(fin('servicos-financeiros')).toBe(true);
    expect(fin('Servicos-Financeiros')).toBe(true);
    expect(fin('Finance'), 'a taxonomia da listagem nunca foi a do perfil').toBe(false);
    expect(fin(null)).toBe(false);
    expect(fin('utilidade-publica', 'Energia Elétrica / Energia Elétrica')).toBe(false);
  });
});
