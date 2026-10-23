import { describe, expect, it } from 'vitest';

import { DateRange } from '../../src/core';
import { ApiConfig, BrapiMode } from '../../src/data/config/api-config';
import { BcbDatasource } from '../../src/data/datasources/bcb-datasource';
import { TreasuryDatasource } from '../../src/data/datasources/treasury-datasource';
import type { HttpErrorType } from '../../src/data/network/http';
import { day } from '../core/helpers';
import { clientWith, FixtureTransport } from './fixture-transport';

/**
 * Falha de rede **sem status HTTP** nas fontes de taxa — lente `risco`,
 * 21/09/2026.
 *
 * O BCB e o Tesouro **são os fornecedores das taxas do DCF e do backtest**:
 * exceção crua atravessando a camada de dados quebraria o contrato `Result`
 * inteiro, e uma conexão que cai não tem status nenhum.
 *
 * A captura mora no `ApiClient`, e é ela que este arquivo cobra: **a garantia
 * é central, e a cobertura precisa ser de cada fonte**, porque quem acrescentar
 * uma quarta fonte amanhã pode não passar por lá.
 */

const config = new ApiConfig({
  mode: BrapiMode.direct,
  brapiBaseUrl: 'https://brapi.dev/api',
  bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
});

const kinds: HttpErrorType[] = ['connectionTimeout', 'receiveTimeout', 'connectionError', 'unknown'];

const catalog = `
{"result":{"resources":[
  {"format":"CSV","url":"https://exemplo.gov.br/precotaxatesourodireto.csv"}
]}}`;

describe('BcbDatasource — falha sem resposta do servidor', () => {
  for (const kind of kinds) {
    it(`${kind} vira Result.err, e não exceção`, async () => {
      const source = new BcbDatasource(clientWith(new FixtureTransport({ transportErrors: { 'bcdata.sgs': kind } }), config));
      const r = await source.series(BcbDatasource.seriesCdiDaily, new DateRange(day(2024, 1, 1), day(2024, 12, 31)));
      expect(r.isErr, `${kind} deveria virar Result.err`).toBe(true);
      expect(r.failureOrNull).not.toBeNull();
    });
  }
});

describe('TreasuryDatasource — falha sem resposta do servidor', () => {
  for (const kind of kinds) {
    it(`${kind} vira Result.err, e não exceção`, async () => {
      const source = new TreasuryDatasource(
        clientWith(new FixtureTransport({ transportErrors: { package_show: kind } }), config),
      );
      const r = await source.latest();
      expect(r.isErr, `${kind} deveria virar Result.err`).toBe(true);
      expect(r.failureOrNull).not.toBeNull();
    });
  }

  it('a queda no CSV, depois do catálogo, também não escapa', async () => {
    // **Duas chamadas, dois caminhos.** O catálogo responde e o arquivo cai.
    const source = new TreasuryDatasource(
      clientWith(
        new FixtureTransport({
          bodies: { package_show: catalog },
          transportErrors: { 'precotaxatesourodireto.csv': 'connectionError' },
        }),
        config,
      ),
    );
    const r = await source.latest();
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull).not.toBeNull();
  });
});
