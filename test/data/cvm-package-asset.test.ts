import { expect, it } from 'vitest';

import { CvmDocumentCodec, DateTime, interpolateJson } from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { asObject, isServed, readPublicJson, universeTickers } from './public-assets';

/**
 * O pacote da CVM versionado é o que o build leva (decisão 80).
 *
 * No aplicativo, pacote ausente ou ilegível vira ressalva — a avaliação segue.
 * Aqui, **reprova a suíte**: um build que sai sem a CVM por descuido não é
 * estado aceitável, é defeito, e o lugar de pegá-lo é antes do build.
 */

// O pacote tem 9 MB: lido uma vez para os três testes.
const json = isServed(AssetPaths.cvmPackage) ? readPublicJson(AssetPaths.cvmPackage) : null;

it('o pacote existe em public/, de onde o build o serve', () => {
  expect(isServed(AssetPaths.cvmPackage), 'gerar com `npm run tool -- cvm-package` e versionar').toBe(true);
});

it('o pacote é legível pelo codec deste build', () => {
  expect(json!['versao'], 'o codec mudou de versão e o pacote não foi regerado').toBe(CvmDocumentCodec.version);
  expect(DateTime.tryParse(interpolateJson(json!['geradoEm']))).not.toBeNull();

  const documents = CvmDocumentCodec.decodePackage(json!);
  const universe = new Set(universeTickers());
  const covered = [...universe].filter((t) => (documents.get(t)?.length ?? 0) > 0);
  // 371 de 375 em 14/09/2026: os quatro sem ponte ticker↔CNPJ (A1.1).
  expect(covered.length / universe.size, 'pacote truncado ou gerado sobre outro universo').toBeGreaterThanOrEqual(0.95);
});

it('todo documento do pacote tem período e demonstração', () => {
  const rawSessions = asObject(json!['tickers'], 'tickers');
  const documents = CvmDocumentCodec.decodePackage(json!);
  for (const [ticker, raw] of Object.entries(rawSessions)) {
    expect(documents.get(ticker)?.length, `${ticker}: documento que o codec não consegue ler`).toBe(
      (raw as unknown[]).length,
    );
    // **E o que foi lido tem conteúdo** (lente `risco`, 27/09/2026): um codec
    // que deixasse de mapear datas ou contas manteria a contagem e entregaria
    // documentos vazios.
    for (const d of documents.get(ticker) ?? []) {
      expect(d.periodEnd.isAfter(d.periodStart), `${ticker}: período de ${d.periodStart} a ${d.periodEnd}`).toBe(true);
      const c = d.current;
      expect(
        c.totalStockholderEquity !== null || c.totalRevenue !== null || c.netIncome !== null,
        `${ticker} ${d.periodEnd}: documento sem patrimônio, receita nem lucro`,
      ).toBe(true);
    }
  }
});
