import { DateTime, type Ticker, type UnitComposition, UnitCompositionCodec } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Composição declarada das units, empacotada com o aplicativo (item B16).
 *
 * A razão de unidade era **inferida** do valor de mercado, e só acerta quando
 * ordinária e preferencial valem o mesmo: nas coortes ela erra 79 de 220
 * observações de unit. A composição que a companhia declara no quadro de
 * valores mobiliários da FCA é fonte primária e datada. Gerada por
 * `tool/unit-package.ts` e versionada, como o pacote da CVM.
 *
 * **Sem pacote, o repositório é transparente**: sem composição declarada, a
 * cascata volta a inferir a razão e passa a dizer que a inferiu.
 */
export class UnitCompositionRepository {
  /**
   * Data da avaliação. **Recebida por função**, e não lida do relógio no
   * ponto de uso: a composição vigente depende da data, e o núcleo recebe a
   * data pronta — é a mesma convenção de `CvmFundamentalsRepository`.
   */
  readonly today: () => DateTime;

  private readonly units: () => Promise<Map<string, UnitComposition[]>>;

  constructor(args: { loadPackage: PackageLoader; today?: () => DateTime }) {
    this.today = args.today ?? (() => DateTime.now());
    this.units = memoizedPackage(args.loadPackage, (json) => UnitCompositionCodec.decodePackage(json), new Map());
  }

  /**
   * Ações na unit de [ticker] declaradas até [asOf], ou `null`.
   *
   * Formulário posterior à data não entra: numa avaliação datada, a
   * composição de um ano futuro seria conhecimento futuro. Sem [asOf], vale a
   * data de [today].
   */
  async sharesPerUnitFor(ticker: Ticker, options: { asOf?: DateTime | null } = {}): Promise<number | null> {
    const declared = (await this.units()).get(ticker.value);
    if (declared === undefined) return null;
    return UnitCompositionCodec.at(declared, options.asOf ?? this.today())?.shares ?? null;
  }
}
