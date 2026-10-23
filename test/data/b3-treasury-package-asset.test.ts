import { describe, expect, it } from 'vitest';

import {
  B3RegistryCodec,
  CashDividendsCodec,
  ConcessionTermsCodec,
  DateTime,
  FinancialSectors,
  TreasuryCurve,
  TreasuryQuotesCodec,
} from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { isServed, readPublicJson, universeTickers } from './public-assets';

/**
 * Os pacotes versionados da B3 e do Tesouro são o que o build leva.
 *
 * No aplicativo, ausência vira recuo — a ponte segue a regra da fonte, a
 * curva recua para os dois pontos. Aqui, reprova a suíte: build que sai sem
 * eles por descuido é defeito, e o lugar de pegá-lo é antes do build.
 */

const universeRoots = (): Set<string> => new Set(universeTickers().map((t) => t.substring(0, 4)));

describe('Registro de emissores da B3 — decisão 83', () => {
  it('existe em public/, de onde o build o serve', () => {
    expect(isServed(AssetPaths.b3Registry), 'gerar com `npm run tool -- b3-package` e versionar').toBe(true);
  });

  it('é legível e cobre o universo', () => {
    const issuers = B3RegistryCodec.decodePackage(readPublicJson(AssetPaths.b3Registry));
    expect(issuers.size, 'versão do codec mudou e o pacote não foi regerado').toBeGreaterThan(0);
    const universe = universeRoots();
    const covered = [...universe].filter((r) => issuers.get(r)?.totalShares != null);
    // 297 de 297 emissores em 14/09/2026.
    expect(covered.length / universe.size).toBeGreaterThanOrEqual(0.95);
  });

  it('classifica o setor de todo emissor do universo — item A5', () => {
    const issuers = B3RegistryCodec.decodePackage(readPublicJson(AssetPaths.b3Registry));
    const withoutSector = [...universeRoots()].filter((r) => {
      const issuer = issuers.get(r);
      return issuer !== undefined && issuer.classification === null;
    });
    expect(withoutSector, 'rodar `python tool/b3_complemento_baixar.py` antes de empacotar').toEqual([]);
    for (const bank of ['BRSR', 'PINE', 'SANB']) {
      const c = issuers.get(bank)!.classification!;
      expect(
        FinancialSectors.isFinancial({ sectorKey: c.sectorKey, industry: c.industry }),
        `${bank} escapava da Porta 1 sem setor`,
      ).toBe(true);
    }
  });
});

describe('Proventos da B3 — decisão 89', () => {
  it('existe, é legível e traz o preço com direito', () => {
    expect(isServed(AssetPaths.cashDividends), 'gerar com `npm run tool -- b3-dividends-package`').toBe(true);
    const dividends = CashDividendsCodec.decode(readPublicJson(AssetPaths.cashDividends));
    expect(dividends.size).toBeGreaterThan(200);
    expect(
      [...dividends.values()].every((l) => l.every((p) => p.closeWithRights !== null)),
      'provento sem preço com direito não entra no índice',
    ).toBe(true);
  });
});

describe('Prazo das outorgas — decisão 88', () => {
  it('existe e é legível', () => {
    expect(isServed(AssetPaths.concessionTerms), 'gerar com `npm run tool -- fre-grants`').toBe(true);
    const terms = ConcessionTermsCodec.decode(readPublicJson(AssetPaths.concessionTerms));
    expect(terms.size).toBeGreaterThan(0);
    expect(terms.get('TAEE11'), 'transmissora com 39 outorgas legíveis no FRE de 2022').toBeDefined();
  });
});

describe('Cotações do Tesouro — decisão 84', () => {
  it('existe em public/, de onde o build o serve', () => {
    expect(isServed(AssetPaths.treasuryQuotes), 'gerar com `npm run tool -- curve-package` e versionar').toBe(true);
  });

  it('é legível e monta uma curva na própria data', () => {
    const json = readPublicJson(AssetPaths.treasuryQuotes);
    const quotes = TreasuryQuotesCodec.decode(json);
    expect(quotes.length).toBeGreaterThan(0);
    const generated = DateTime.parse(`${String(json['geradoEm'])}T00:00:00Z`);
    expect(TreasuryCurve.at(quotes, generated), 'o pacote precisa sustentar uma curva, ao menos no dia dele').not.toBeNull();
  });
});
