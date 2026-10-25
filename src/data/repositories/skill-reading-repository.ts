import { type SkillReading, SkillReadingCodec } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Leitura da habilidade do potencial empacotada com o aplicativo (item B1.0).
 *
 * Gerada por `tool/conditional-regression.ts --trimestral` a partir das
 * coortes da validação. **Sem pacote, a leitura é `null`**, e a tela de metas
 * diz que a habilidade não foi medida: a ausência não pode esconder a
 * ressalva.
 */
export class SkillReadingRepository {
  private readonly cached: () => Promise<SkillReading | null>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.cached = memoizedPackage<SkillReading | null>(args.loadPackage, (json) => SkillReadingCodec.decode(json), null);
  }

  /** A leitura do pacote, ou `null`. */
  reading(): Promise<SkillReading | null> {
    return this.cached();
  }
}
