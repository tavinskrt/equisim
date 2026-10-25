import { Duration } from '../../core';

/**
 * Validade de cada tipo de dado.
 *
 * Cotação de pregão encerrado é fato passado e não muda: as linhas já
 * guardadas nunca são descartadas, e é isso que derruba a segunda execução de
 * uma simulação de ~3,5 s para praticamente zero.
 *
 * O que envelhece não é a linha, é a **ponta da série** — a cada pregão
 * existe um dia a mais para buscar. A validade abaixo governa só isso: quando
 * expira, a série é rebuscada e as linhas novas são somadas às antigas.
 *
 * O universo de tickers **não é cacheado**: `FundamentalsRepositoryImpl`
 * delega direto ao remoto. Quem for ligar o cache do universo precisa
 * introduzir validade e chave junto do caminho que as usa, e não antes.
 */
export const CachePolicy = {
  /**
   * Ponta da série de cotações.
   *
   * Meio dia: recarrega no máximo uma vez por turno de trabalho e ainda assim
   * alcança o pregão do dia. Um prazo longo aqui congelava a simulação na
   * data em que o cache foi preenchido — os aportes paravam ali, meses antes
   * de hoje, sem nenhum aviso.
   */
  historicalPrices: new Duration({ hours: 12 }),

  /** Fundamentos anuais: atualizam uma vez por ano, com folga. */
  fundamentals: new Duration({ days: 30 }),

  /** Perfil e setor: praticamente estáticos. */
  profile: new Duration({ days: 90 }),

  /** CDI e IPCA: publicação diária. */
  macro: new Duration({ days: 1 }),

  /** Chave de cache da série de cotações de um ativo. */
  pricesKey: (ticker: string): string => `prices:${ticker}`,

  /** Chave de cache dos exercícios de um ativo. */
  fundamentalsKey: (ticker: string): string => `fundamentals:${ticker}`,

  /** Chave de cache do perfil cadastral de um ativo. */
  profileKey: (ticker: string): string => `profile:${ticker}`,

  /** Chave de cache de uma série macroeconômica, pelo código SGS do BCB. */
  macroKey: (seriesId: number): string => `macro:${seriesId}`,
} as const;
