import { type ConcessionTerm, ConcessionTermsCodec, type DateTime, type Ticker } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Prazo das outorgas empacotado com o aplicativo (item A6, decisão 88).
 *
 * Gerado por `tool/fre-grants.ts` a partir do Formulário de Referência da
 * CVM. **Sem pacote, o repositório é transparente**: sem prazo, a concessão
 * segue com a projeção inteira, e o aviso da avaliação diz o que isso supõe.
 */
export class ConcessionTermRepository {
  private readonly terms: () => Promise<Map<string, ConcessionTerm>>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.terms = memoizedPackage(args.loadPackage, (json) => ConcessionTermsCodec.decode(json), new Map());
  }

  /** Fim do contrato de [ticker], ou `null`. */
  async endFor(ticker: Ticker): Promise<DateTime | null> {
    return (await this.terms()).get(ticker.value)?.end ?? null;
  }
}
