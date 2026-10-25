import type { Sector } from '../../entities/asset';
import type { Portfolio } from '../../entities/portfolio';
import { compareNum } from '../../lang/num';

/** Concentração observada em um setor. */
export class SectorExposure {
  /** Setor observado. Nunca é [Sector.unknown]. */
  readonly sector: Sector;

  /** Quantidade de ativos da carteira no setor. */
  readonly count: number;

  /** Soma dos pesos dos ativos do setor, em fração. */
  readonly weight: number;

  constructor(args: { sector: Sector; count: number; weight: number }) {
    this.sector = args.sector;
    this.count = args.count;
    this.weight = args.weight;
  }
}

/** Resultado da análise de concentração setorial. */
export class ConcentrationReport {
  /** Setores que atingiram ou superaram o limiar de alerta. */
  readonly concentrated: readonly SectorExposure[];

  constructor(args: { concentrated: readonly SectorExposure[] }) {
    this.concentrated = args.concentrated;
  }

  /** `true` quando ao menos um setor atingiu o limiar. **Informativo.** */
  get hasAlert(): boolean {
    return this.concentrated.length > 0;
  }
}

/** Analisa a distribuição setorial de uma carteira. */
export const SectorConcentration = {
  /** A partir de dois ativos no mesmo setor, dispara alerta. */
  defaultThreshold: 2,

  /**
   * Analisa a concentração setorial da carteira.
   *
   * O alerta é **informativo e não bloqueia a operação**: concentrar em um
   * setor pode ser uma decisão deliberada do investidor. O critério é
   * **contagem de ativos, não soma de pesos** — a concentração que interessa
   * é a de exposição a um mesmo choque setorial. Complexidade O(n log n).
   */
  analyze(portfolio: Portfolio, options: { threshold?: number } = {}): ConcentrationReport {
    const threshold = options.threshold ?? SectorConcentration.defaultThreshold;
    // O setor se compara pela chave; a primeira instância vista fica no mapa.
    const bySector = new Map<string, { sector: Sector; count: number; weight: number }>();

    for (const entry of portfolio.entries.values()) {
      const sector = entry.sector;
      if (sector.isUnknown) continue;
      const current = bySector.get(sector.key);
      if (current === undefined) {
        bySector.set(sector.key, { sector, count: 1, weight: 0.0 + entry.weight.value });
      } else {
        current.count = current.count + 1;
        current.weight = current.weight + entry.weight.value;
      }
    }

    const exposures = [...bySector.values()]
      .map((e) => new SectorExposure({ sector: e.sector, count: e.count, weight: e.weight }))
      .sort((a, b) => {
        const byCount = compareNum(b.count, a.count);
        return byCount !== 0 ? byCount : compareNum(b.weight, a.weight);
      });

    return new ConcentrationReport({ concentrated: exposures.filter((e) => e.count >= threshold) });
  },
};
