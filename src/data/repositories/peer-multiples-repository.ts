import { PeerMultipleCodec, type PeerMultipleSet, type Ticker } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Medianas de múltiplos por grupo de pares, empacotadas com o aplicativo
 * (item B5, decisão 118).
 *
 * Dão à avaliação a **segunda leitura** — o preço justo que os pares do ativo
 * implicam, ao lado do fluxo descontado. Geradas por
 * `tool/multiples-package.ts` e versionadas, como o prior do beta e o
 * registro da B3.
 *
 * **Sem pacote, o repositório é transparente**: a avaliação sai como sempre
 * saiu, sem triangulação e sem ressalva inventada. Pacote ilegível tem o mesmo
 * efeito de pacote ausente — a segunda leitura é acréscimo, e a falta dela não
 * pode derrubar a primeira.
 */
export class PeerMultiplesRepository {
  private readonly medians: () => Promise<Map<string, PeerMultipleSet>>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.medians = memoizedPackage(args.loadPackage, (json) => PeerMultipleCodec.decode(json), new Map());
  }

  /**
   * As medianas que valem para [ticker], ou `null`.
   *
   * A chave é o **ticker inteiro**, e não a raiz do emissor: PETR3 e PETR4
   * negociam múltiplos diferentes, e é o múltiplo negociado que entra na
   * mediana do grupo.
   */
  async forTicker(ticker: Ticker): Promise<PeerMultipleSet | null> {
    return (await this.medians()).get(ticker.value) ?? null;
  }
}
