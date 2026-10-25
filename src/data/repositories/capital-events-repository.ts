import { CapitalEvents, CapitalEventsCodec, type Ticker } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Eventos de capital empacotados com o aplicativo (itens B28 e B29).
 *
 * Gerado por `tool/capital-package.ts` a partir do Formulário de Referência
 * da CVM, do registro da B3 e do COTAHIST. Duas listas por ativo: as emissões
 * de ações, que a cascata soma ao patrimônio quando o valor é declarado e só
 * avisa quando não é, e os eventos de ações, com que o preparo completa o
 * ajuste que a fonte de preços deixou de fazer.
 *
 * **Sem pacote, o repositório é transparente**: sem emissão, o patrimônio é o
 * do balanço, e sem evento a série da fonte segue como veio — que é o
 * comportamento anterior.
 */
export class CapitalEventsRepository {
  private readonly pkg: () => Promise<Map<string, CapitalEvents>>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.pkg = memoizedPackage(args.loadPackage, (json) => CapitalEventsCodec.decodePackage(json), new Map());
  }

  /** Emissões e eventos de ações de [ticker]; vazio sem entrada no pacote. */
  async eventsFor(ticker: Ticker): Promise<CapitalEvents> {
    return (await this.pkg()).get(ticker.value) ?? new CapitalEvents();
  }
}
