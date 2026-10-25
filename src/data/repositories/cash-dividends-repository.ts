import { type CashDividend, CashDividendsCodec, type Ticker } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Proventos da B3 empacotados com o aplicativo (item A4, decisão 89).
 *
 * Dão ao beta o **retorno total** do ativo. Gerado por
 * `tool/b3-dividends-package.ts`. **Sem pacote, o repositório é
 * transparente**: sem proventos, o beta sai do fechamento, que é o de antes.
 */
export class CashDividendsRepository {
  private readonly dividends: () => Promise<Map<string, readonly CashDividend[]>>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.dividends = memoizedPackage(args.loadPackage, (json) => CashDividendsCodec.decode(json), new Map());
  }

  /** Proventos da classe de [ticker], em ordem de data ex. */
  async dividendsFor(ticker: Ticker): Promise<CashDividend[]> {
    return CashDividendsCodec.forTicker(await this.dividends(), ticker.value);
  }
}
