import {
  CalibratedBand,
  type CalibratedBandTable,
  type Money,
  type ValuationResult,
  VolatilityBandTable,
} from '../core';
import { Fmt } from './fmt';

/** Uma faixa calibrada pronta para a tela: o horizonte, os dois extremos e a tabela que a gerou. */
export interface BandReading {
  readonly table: CalibratedBandTable;
  readonly low: Money;
  readonly high: Money;
}

/**
 * A faixa calibrada da tela de avaliação (decisões 92 e 100).
 *
 * **É a incerteza medida, e não a sensibilidade**: vem do que aconteceu nas
 * coortes, com a cobertura fora da amostra declarada.
 */
export const BandCopy = {
  /** Frequência apresentada: oito em cada dez. */
  nominal: 0.8,
  /** Distância da nominal até onde a faixa se diz calibrada — o critério do R2. */
  criterionMargin: 0.05,
  horizons: [12, 36] as const,

  readings(result: ValuationResult, tables: readonly CalibratedBandTable[]): BandReading[] {
    const out: BandReading[] = [];
    for (const months of BandCopy.horizons) {
      const table = CalibratedBand.select(tables, { months, nominal: BandCopy.nominal });
      if (table === null) continue;
      const band = CalibratedBand.of(result.fairValue, table, {
        marketPrice: result.marketPrice,
        volatility: result.priceVolatility,
      });
      if (band !== null) out.push({ table, low: band.low, high: band.high });
    }
    return out;
  },

  /** A frase que diz o que a faixa é, de onde sai e se está calibrada. */
  reading(bands: readonly BandReading[]): string {
    const coverages = bands
      .filter((b) => b.table.outOfSampleCoverage !== null)
      .map((b) => `${Fmt.percent(b.table.outOfSampleCoverage!, { decimals: 1 })} em ${b.table.months} meses`);
    const calibrated = bands.every(
      (b) => b.table.outOfSampleCoverage !== null && Math.abs(b.table.outOfSampleCoverage - BandCopy.nominal) <= BandCopy.criterionMargin,
    );
    const fromVolatility = bands.some((b) => b.table instanceof VolatilityBandTable);
    const origin = fromVolatility
      ? 'Ela sai do preço de hoje, da volatilidade do papel e do preço justo, que entra com o peso que a ' +
        'validação mediu — pequeno, porque o preço converge pouco ao justo.'
      : 'Ela é a razão entre o realizado e o preço justo nas coortes.';
    const reading = calibrated
      ? 'Em 8 de cada 10 avaliações passadas, o preço mais os proventos terminaram nesta faixa' +
        `${coverages.length === 0 ? '' : ` — ${coverages.join(' e ')}, medidos fora da amostra`}. ${origin}`
      : 'Faixa central de 80% das avaliações passadas. Medida fora da amostra, ela conteve o preço mais os ' +
        `proventos em ${coverages.length === 0 ? 'uma fração não medida' : coverages.join(' e ')} dos casos — a mais ` +
        `de 5 pontos dos 80% que a nomeiam, e por isso não está calibrada. ${origin}`;
    return `${reading} A largura é o tamanho do erro medido contra o que aconteceu: não é previsão.`;
  },
};
