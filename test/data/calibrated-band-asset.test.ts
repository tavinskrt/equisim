import { expect, it } from 'vitest';

import {
  CalibratedBand,
  CalibratedBandCodec,
  FairValueBandTable,
  Money,
  VolatilityBandTable,
} from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { CalibratedBandRepository } from '../../src/data/repositories/calibrated-band-repository';
import { expectClose } from '../core/helpers';
import { asObject, isServed, readPublicJson, readRepoJson } from './public-assets';

/**
 * A faixa calibrada é o que o aplicativo declara como incerteza (item C2,
 * decisão 92). Pacote ausente, ilegível ou fora do critério reprova a suíte:
 * no aplicativo, a ausência só esconde o cartão, e o lugar de pegar o descuido
 * é antes do build.
 */

const tables = () => CalibratedBandCodec.decode(readPublicJson(AssetPaths.calibratedBand));

it('existe em public/ e é legível', () => {
  expect(isServed(AssetPaths.calibratedBand), 'gerar com `python tool/cobertura_banda.py` e versionar').toBe(true);
  const decoded = tables();
  for (const months of [12, 36]) {
    for (const nominal of [0.5, 0.8, 0.9]) {
      expect(
        CalibratedBand.select(decoded, { months, nominal }),
        `faltou a faixa de ${months} meses a ${nominal * 100}%`,
      ).not.toBeNull();
    }
  }
});

// **A cobertura declarada é a medida.** O pacote não pode dizer ao aplicativo
// uma cobertura diferente da que a ferramenta mediu, e a forma do pacote é a
// que a regra da §9 de `cobertura_banda.md` escolheu — hoje a da volatilidade
// (decisão 100).
it('a cobertura fora da amostra do pacote é a que cobertura_banda mediu', () => {
  const decoded = tables();
  const measurement = asObject(readRepoJson('docs/validacao/cobertura_banda_trimestral.json'), 'medição');
  const field = (m: unknown, k: string) => asObject(asObject(m, k)[k], k);
  const form = String(field(measurement, 'regraDoPacote')['forma']);
  for (const t of decoded) {
    expect(t.outOfSampleCoverage).not.toBeNull();
    const horizon = field(field(measurement, 'horizontes'), String(t.months));
    const measurements =
      t instanceof VolatilityBandTable
        ? field(field(field(horizon, 'formaFixada'), 'formas'), form)
        : field(field(horizon, 'recalibrada'), 'justo');
    const measured = field(measurements, 'cobertura')[`${Math.round(t.nominal * 100)}%`] as number;
    expectClose(t.outOfSampleCoverage, measured / 100, 1e-9, `${t.months} meses a ${t.nominal}`);
    // A faixa central mais larga contém a mais estreita.
    const narrow = CalibratedBand.select(decoded, { months: t.months, nominal: t.nominal - 0.1 });
    if (narrow === null) continue;
    if (t instanceof FairValueBandTable && narrow instanceof FairValueBandTable) {
      expect(t.lowerFactor).toBeLessThanOrEqual(narrow.lowerFactor);
      expect(t.upperFactor).toBeGreaterThanOrEqual(narrow.upperFactor);
    } else if (t instanceof VolatilityBandTable && narrow instanceof VolatilityBandTable) {
      // O centro é o mesmo nas três frequências do horizonte; o que muda são
      // os quantis.
      expectClose(t.a, narrow.a, 1e-12);
      expectClose(t.b, narrow.b, 1e-12);
      expect(t.zLower).toBeLessThanOrEqual(narrow.zLower);
      expect(t.zUpper).toBeGreaterThanOrEqual(narrow.zUpper);
    } else {
      expect.fail(`o pacote mistura formas em ${t.months} meses`);
    }
  }
});

// A faixa da volatilidade precisa do preço e da volatilidade do papel; a do
// justo, não. O aplicativo lê a que estiver no pacote, e o cartão de
// avaliação passa os dois.
it('a faixa do pacote se forma com o que a avaliação tem', () => {
  for (const t of tables()) {
    const band = CalibratedBand.of(Money.fromReais(42.8), t, {
      marketPrice: Money.fromReais(33.15),
      volatility: 0.42,
    });
    expect(band, `${t.months} meses a ${t.nominal}`).not.toBeNull();
    expect(band!.low.cents).toBeLessThan(band!.high.cents);
  }
});

it('sem pacote utilizável o repositório devolve vazio, e não falha', async () => {
  const broken = new CalibratedBandRepository({ loadPackage: async () => 'não é json' });
  expect(await broken.tables()).toEqual([]);
  const missing = new CalibratedBandRepository({
    loadPackage: async () => {
      throw new Error('sem');
    },
  });
  expect(await missing.tables()).toEqual([]);
});
