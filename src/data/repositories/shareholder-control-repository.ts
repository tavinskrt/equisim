import {
  DateTime,
  ShareholderControl,
  ShareholderControlHistory,
  type ShareholderControlPeriod,
  type Ticker,
} from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * A espécie do controle acionário, empacotada com o aplicativo (item B46).
 *
 * Vem do Formulário Cadastral da CVM, gerada por `tool/control-package.ts`
 * e versionada em `public/assets/cvm/controle.json`, pela raiz do código de
 * negociação — a mesma chave do registro da B3. A avaliação a usa só para a
 * ressalva de controle estatal: o preço justo não muda.
 *
 * **Sem pacote, o repositório é transparente**: sem a espécie, a avaliação
 * sai sem a ressalva, como antes dela.
 */
export class ShareholderControlRepository {
  /**
   * Data da avaliação. **Recebida por função**, e não lida do relógio no
   * ponto de uso — a mesma convenção de `UnitCompositionRepository`.
   */
  readonly today: () => DateTime;

  private readonly issuers: () => Promise<Map<string, ShareholderControlPeriod[]>>;

  constructor(args: { loadPackage: PackageLoader; today?: () => DateTime }) {
    this.today = args.today ?? (() => DateTime.now());
    this.issuers = memoizedPackage(
      args.loadPackage,
      (json) => ShareholderControlHistory.decode(json)?.byIssuer ?? new Map(),
      new Map(),
    );
  }

  /**
   * `true` quando o emissor de [ticker] é de controle estatal em [asOf] —
   * ou na data de [today], sem ela.
   */
  async isStateControlled(ticker: Ticker, options: { asOf?: DateTime | null } = {}): Promise<boolean> {
    const root = ticker.value.length >= 4 ? ticker.value.substring(0, 4) : ticker.value;
    const periods = (await this.issuers()).get(root);
    if (periods === undefined) return false;
    return ShareholderControlHistory.at(periods, options.asOf ?? this.today()) === ShareholderControl.state;
  }
}
