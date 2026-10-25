import { type DateTime, err, InsufficientData, isJsonObject, ok, type Result, TreasuryCsv, type TreasuryQuote } from '../../core';
import type { ApiClient } from '../network/api-client';

/**
 * Cotações do dia dos títulos prefixados do Tesouro Direto (item A2.1).
 *
 * Lê o arquivo **direto**, e só o começo: ele vem em ordem decrescente de
 * data-base, e as linhas do dia mais recente estão nos primeiros quilobytes de
 * um arquivo de 14,5 MB. A leitura para na primeira linha de outra data.
 *
 * **Só no Node, nas ferramentas de `tool/`.** O arquivo libera CORS apenas
 * para o domínio do próprio Tesouro, e o navegador não pode lê-lo: na web o
 * aplicativo nem chama esta fonte, e a curva vem do pacote do build
 * (decisão 86).
 */
export class TreasuryDatasource {
  /**
   * Catálogo CKAN do conjunto de taxas do Tesouro.
   *
   * O endereço do arquivo vem dele a cada leitura: o identificador do recurso
   * muda quando o Tesouro republica o conjunto.
   */
  static readonly catalog =
    'https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show' +
    '?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto';

  /** Declara a fonte. */
  constructor(readonly client: ApiClient) {}

  /** Cotações da data-base mais recente publicada. */
  async latest(): Promise<Result<TreasuryQuote[]>> {
    const pkg = await this.client.getJson(TreasuryDatasource.catalog);
    if (pkg.isErr) return err(pkg.failureOrNull!);
    const csv = TreasuryDatasource.csvUrl(pkg.unwrap());
    if (csv === null) return err(new InsufficientData('O catálogo do Tesouro não lista o arquivo CSV.'));

    let first: DateTime | null = null;
    let header = true;
    const rows = await this.client.readLinesUntil(csv, {
      stop: (row) => {
        if (header) {
          header = false;
          return false;
        }
        const base = TreasuryCsv.baseDateOf(row);
        if (base === null) return false;
        first ??= base;
        return !base.equals(first);
      },
    });
    return rows.flatMap((lines) => {
      const quotes = TreasuryCsv.parse(lines);
      return quotes.length === 0
        ? err(new InsufficientData('O arquivo do Tesouro não trouxe título prefixado na data mais recente.'))
        : ok(quotes);
    });
  }

  /** Endereço do recurso CSV no catálogo, ou `null` quando ele não o lista. */
  static csvUrl(pkg: unknown): string | null {
    if (!isJsonObject(pkg)) return null;
    const result = pkg['result'];
    if (!isJsonObject(result)) return null;
    const resources = result['resources'];
    if (!Array.isArray(resources)) return null;
    for (const r of resources) {
      if (!isJsonObject(r)) continue;
      const format = String(r['format'] ?? '').toUpperCase();
      const url = r['url'];
      if (format === 'CSV' && typeof url === 'string' && url.length > 0) return url;
    }
    return null;
  }
}
