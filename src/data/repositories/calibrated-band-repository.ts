import { CalibratedBandCodec, type CalibratedBandTable } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Faixa calibrada empacotada com o aplicativo (item C2, decisão 92).
 *
 * Gerada por `tool/cobertura_banda.py` a partir das coortes da validação.
 * **Sem pacote, o repositório é transparente**: a tela de avaliação não mostra
 * faixa calibrada, e a banda de cenários continua sendo o que ela é — a
 * sensibilidade às premissas.
 */
export class CalibratedBandRepository {
  private readonly bands: () => Promise<CalibratedBandTable[]>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.bands = memoizedPackage(args.loadPackage, (json) => CalibratedBandCodec.decode(json), []);
  }

  /** Todas as faixas do pacote, ou vazio. */
  tables(): Promise<CalibratedBandTable[]> {
    return this.bands();
  }
}
