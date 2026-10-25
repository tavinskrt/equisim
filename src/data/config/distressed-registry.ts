import { isJsonObject } from '../../core';
import { AssetPaths } from './asset-paths';

/**
 * Registro externo de ativos sem continuidade operacional.
 *
 * **Existe por necessidade, não por escolha.** A Porta 0 recusa empresa em
 * recuperação judicial ou extrajudicial, porque o fluxo descontado e o valor da
 * capacidade de gerar lucro pressupõem continuidade. Mas a fonte de dados não
 * publica essa situação: o campo `isActive` marca **negociabilidade**, não
 * continuidade, e os 786 tickers do universo vêm todos com ele verdadeiro.
 *
 * É a única exclusão da Porta 0 que não se automatiza com o que a fonte
 * oferece, e a decisão 25 a registra como dependência assumida.
 *
 * O arquivo é `public/config/distressed_tickers.json`, servido com o build.
 */
export class DistressedRegistry {
  /** Tickers em recuperação, em maiúsculas e sem sufixo fracionário. */
  readonly tickers: ReadonlySet<string>;

  constructor(tickers: Iterable<string>) {
    this.tickers = new Set(tickers);
  }

  /**
   * Registro vazio — nenhum ativo excluído.
   *
   * É o estado degradado quando o arquivo não carrega. **Degradar para vazio é
   * deliberado**: um registro que falha em carregar não pode barrar o universo
   * inteiro, e um falso negativo aqui produz uma avaliação a mais, não uma
   * avaliação errada em silêncio — o ativo em recuperação apareceria com os
   * avisos que a própria cascata emite.
   */
  static readonly empty = new DistressedRegistry([]);

  /** Caminho do arquivo, relativo à raiz servida. */
  static readonly assetPath = AssetPaths.distressedTickers;

  /** Carrega o registro, tolerando ausência e JSON malformado. */
  static async load(loadText: () => Promise<string>): Promise<DistressedRegistry> {
    try {
      return DistressedRegistry.parse(await loadText());
    } catch {
      return DistressedRegistry.empty;
    }
  }

  /** Interpreta o conteúdo do arquivo. Separado de [load] para ser testável sem rede. */
  static parse(raw: string): DistressedRegistry {
    try {
      const json: unknown = JSON.parse(raw);
      if (!isJsonObject(json)) return DistressedRegistry.empty;
      const list = json['emRecuperacao'];
      if (!Array.isArray(list)) return DistressedRegistry.empty;
      const out: string[] = [];
      for (const item of list) {
        if (typeof item === 'string' && item.trim().length > 0) out.push(item.trim().toUpperCase());
        else if (isJsonObject(item) && typeof item['ticker'] === 'string') out.push(item['ticker'].trim().toUpperCase());
      }
      return new DistressedRegistry(out);
    } catch {
      return DistressedRegistry.empty;
    }
  }

  /** `true` quando o ativo está em recuperação. */
  contains(ticker: string): boolean {
    return this.tickers.has(ticker.toUpperCase());
  }
}
