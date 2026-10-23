import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

import type { BenchmarkRepository, FundamentalsRepository, MacroRepository, PriceRepository } from '../../src/core';
import { ApiConfig, BrapiMode } from '../../src/data/config/api-config';
import { BcbDatasource } from '../../src/data/datasources/bcb-datasource';
import { BrapiDatasource } from '../../src/data/datasources/brapi-datasource';
import { ApiClient } from '../../src/data/network/api-client';
import {
  BenchmarkRepositoryImpl,
  FundamentalsRepositoryImpl,
  MacroRepositoryImpl,
  PriceRepositoryImpl,
} from '../../src/data/repositories/market-repositories';
import { SqliteCacheDatabase } from '../lib/sqlite-cache';

/**
 * Dependências do executor de validação.
 *
 * Monta **exatamente** a mesma camada de dados que o aplicativo usa — os
 * mesmos datasources, os mesmos mapeadores, os mesmos repositórios. É o que
 * sustenta a afirmação de que os números da monografia vêm do código
 * entregue, e não de uma reimplementação paralela que poderia divergir.
 *
 * A única diferença é a infraestrutura que o hospedeiro fornece: aqui o cache
 * é SQLite em arquivo — com as tabelas do cache do aplicativo Flutter, de modo
 * que o cache que as execuções em Dart deixaram continua valendo.
 */
export class ValidationContext {
  private constructor(
    /** Cliente HTTP, com a mesma cadeia de interceptadores do aplicativo. */
    readonly client: ApiClient,
    /** Datasource da brapi — cotações, fundamentos e perfil. */
    readonly brapi: BrapiDatasource,
    /** Datasource do Banco Central — CDI e IPCA. */
    readonly bcb: BcbDatasource,
    /**
     * Cache SQLite **em arquivo**, e não em memória: é o que torna os
     * relatórios reprodutíveis entre execuções.
     */
    readonly cache: SqliteCacheDatabase,
    /** Repositório de cotações, sobre [brapi] e [cache]. */
    readonly prices: PriceRepository,
    /** Repositório de fundamentos e perfil. */
    readonly fundamentals: FundamentalsRepository,
    /** Repositório do Ibovespa. */
    readonly benchmark: BenchmarkRepository,
    /** Repositório de séries macroeconômicas. */
    readonly macro: MacroRepository,
  ) {}

  /**
   * Nome do arquivo de cache dentro do diretório de saída.
   *
   * Apagá-lo força a rebusca completa na próxima execução — o caminho para
   * revalidar contra dados frescos da fonte.
   */
  static readonly cacheFileName = 'validation_cache.sqlite';

  /**
   * Monta o contexto, resolvendo a credencial da brapi pelo `BRAPI_TOKEN` do
   * `.env` da raiz ou do ambiente.
   *
   * O `.env` é lido só aqui, no Node: o Vite embarca no bundle apenas as
   * variáveis `VITE_*`, de modo que `BRAPI_TOKEN` nunca vai para o navegador.
   *
   * - [outputDir]: diretório dos relatórios e do cache, criado se faltar.
   * - [verbose]: liga o log sanitizado das requisições.
   * - [cacheFile]: arquivo de cache no lugar do padrão.
   * - [frozenCache]: toda entrada presente no cache vale como fresca, e a
   *   execução só vai à rede pelo que falta. É o que congela a entrada do
   *   gabarito do D1 entre execuções.
   *
   * **Encerra o processo com código 2** quando não encontra credencial, em vez
   * de lançar: é ferramenta de linha de comando, e uma pilha esconderia a
   * instrução de configuração.
   */
  static create(args: { outputDir: string; verbose?: boolean; cacheFile?: string; frozenCache?: boolean }): ValidationContext {
    const token = readEnvFile('BRAPI_TOKEN') ?? process.env['BRAPI_TOKEN'] ?? null;
    const base = readEnvFile('BRAPI_BASE_URL') ?? process.env['BRAPI_BASE_URL'] ?? null;
    if (token === null || token.trim() === '') {
      process.stderr.write('Sem credencial da brapi. Preencha BRAPI_TOKEN no .env da raiz do projeto ou exporte a variável de ambiente.\n');
      process.exit(2);
    }
    const config = new ApiConfig({
      mode: BrapiMode.direct,
      brapiBaseUrl: base !== null && base.trim() !== '' ? base.trim() : ApiConfig.brapiDefaultBaseUrl,
      brapiToken: token.trim(),
      bcbBaseUrl: ApiConfig.bcbDefaultBaseUrl,
      credentialSource: 'BRAPI_TOKEN do .env ou do ambiente (só no Node)',
    });

    mkdirSync(args.outputDir, { recursive: true });
    const cache = new SqliteCacheDatabase(args.cacheFile ?? `${args.outputDir}/${ValidationContext.cacheFileName}`, {
      frozen: args.frozenCache ?? false,
    });
    const client = new ApiClient(config, {
      logRequests: args.verbose ?? false,
      logSink: (line) => process.stdout.write(`${line}\n`),
    });
    const brapi = new BrapiDatasource(client);
    const bcb = new BcbDatasource(client);
    return new ValidationContext(
      client,
      brapi,
      bcb,
      cache,
      new PriceRepositoryImpl({ remote: brapi, cache }),
      new FundamentalsRepositoryImpl({ remote: brapi, cache }),
      new BenchmarkRepositoryImpl(brapi),
      new MacroRepositoryImpl({ remote: bcb, cache }),
    );
  }

  /**
   * O mesmo contexto com outro repositório de índice.
   *
   * Existe para a entrada congelada: o Ibovespa vem sem cache da fonte, e
   * medir sobre ele em duas execuções dá dois números. Quem congela grava a
   * série e a serve por aqui — ver `tool/validation/frozen.ts`.
   */
  withBenchmark(other: BenchmarkRepository): ValidationContext {
    return new ValidationContext(this.client, this.brapi, this.bcb, this.cache, this.prices, this.fundamentals, other, this.macro);
  }

  /**
   * Fecha o banco de cache. Chamar sempre ao fim da execução: sem fechar, o
   * arquivo SQLite pode ficar com o journal pendente.
   */
  async dispose(): Promise<void> {
    this.cache.close();
  }
}

/** Lê uma chave do `.env` da raiz. */
function readEnvFile(key: string): string | null {
  if (!existsSync('.env')) return null;
  for (const line of readFileSync('.env', 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;
    const separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    if (trimmed.slice(0, separator).trim() === key) {
      const value = trimmed.slice(separator + 1).trim();
      return value === '' ? null : value;
    }
  }
  return null;
}

/**
 * Amostra padrão para as varreduras.
 *
 * Cobre perfis distintos de propósito: banco de balanço grande (ITUB4,
 * BBAS3), commodity cíclica (PETR4, VALE3), crescimento a múltiplo alto
 * (WEGE3), utilidade pública de fluxo estável (TAEE11, EGIE3) e varejo em
 * dificuldade (MGLU3) — para que os relatórios não descrevam só o caso fácil.
 */
export const defaultSample: readonly string[] = [
  'PETR4', 'VALE3', 'ITUB4', 'BBAS3', 'BBDC4', 'WEGE3', 'ABEV3',
  'TAEE11', 'EGIE3', 'CMIG4', 'ITSA4', 'B3SA3', 'RENT3', 'MGLU3',
  'SUZB3', 'KLBN11', 'RADL3', 'PRIO3', 'CSAN3', 'VIVT3',
];

/** Escreve um arquivo de saída e informa o caminho. */
export function writeReport(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  process.stdout.write(`  → ${path} (${(statSync(path).size / 1024).toFixed(1)} KB)\n`);
}

/** Formata fração como percentual com vírgula decimal. */
export const pct = (fraction: number, decimals = 2): string => `${(fraction * 100).toFixed(decimals).replace('.', ',')}%`;

/** Formata número com vírgula decimal, para colar em planilha brasileira. */
export const num2 = (value: number, decimals = 4): string => value.toFixed(decimals).replace('.', ',');
