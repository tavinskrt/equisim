import {
  ComputationFailure,
  type DateRange,
  DateTime,
  err,
  InsufficientData,
  isJsonObject,
  ok,
  RatePoint,
  RateSeries,
  type Result,
  TimeBasis,
  tryParseInt,
} from '../../core';
import { BrapiJson } from '../dtos/brapi-dtos';
import type { ApiClient } from '../network/api-client';

/**
 * Séries do Sistema Gerenciador de Séries Temporais do Banco Central.
 *
 * API aberta: sem token, sem cadastro, sem limite relevante. Preferida à
 * brapi para dados macro por ser fonte oficial e citável na monografia.
 */
export class BcbDatasource {
  /** Declara o datasource sobre um [ApiClient] configurado. */
  constructor(readonly client: ApiClient) {}

  /** CDI diário (SGS 12) — taxa livre de risco do CAPM e do índice de Sharpe. */
  static readonly seriesCdiDaily = 12;

  /**
   * IPCA mensal (SGS 433) — usado para a taxa real e para o crescimento
   * nominal da perpetuidade.
   */
  static readonly seriesIpcaMonthly = 433;

  /**
   * IBC-Br **dessazonalizado** (SGS 24364) — proxy mensal do produto real.
   *
   * É a parcela real do teto da perpetuidade, que até a decisão 25 era a
   * constante de 3% em `GrowthEstimator`. Medido sobre 10 anos, o índice dá
   * 1,45% ao ano.
   *
   * **Dessazonalizado, e não a série bruta (24363):** aquela oscila entre 103 e
   * 118 dentro do mesmo ano, e a razão entre duas pontas mediria sazonalidade,
   * não crescimento.
   *
   * É **índice**, não taxa. [series] divide por 100 como faz com as demais, o
   * que não atrapalha: só razões entre pontos são usadas, e o fator cancela.
   */
  static readonly seriesIbcBrMonthly = 24364;

  /**
   * Frequência de cada série do SGS.
   *
   * **A série carrega a própria base desde a decisão 59**, e o mapeamento
   * mora aqui porque é aqui que se sabe qual código do SGS foi pedido: 12 é
   * CDI diário em dias úteis, 433 e 24364 são mensais.
   */
  static basisOf(seriesId: number): TimeBasis {
    return seriesId === BcbDatasource.seriesCdiDaily ? TimeBasis.businessDaily : TimeBasis.monthly;
  }

  /**
   * Busca uma série no intervalo informado.
   *
   * A API devolve `{"data":"02/01/2024","valor":"0.043739"}`, com a data em
   * `dd/MM/yyyy` e o valor em **percentual do período**, como texto. Aqui vira
   * fração, que é a unidade usada em todo o domínio.
   */
  async series(seriesId: number, range: DateRange): Promise<Result<RateSeries>> {
    const response = await this.client.getJson(`${this.client.config.bcbBaseUrl}/bcdata.sgs.${seriesId}/dados`, {
      query: { formato: 'json', dataInicial: brDate(range.start), dataFinal: brDate(range.end) },
      heavy: true, // dez anos de CDI diário passam de 2.500 pontos
    });

    return response.flatMap((body) => {
      if (!Array.isArray(body)) {
        return err(new ComputationFailure(`Resposta inesperada da série SGS ${seriesId}.`));
      }

      const points: RatePoint[] = [];
      for (const item of body) {
        if (!isJsonObject(item)) continue;
        const date = parseBrDate(BrapiJson.asString(item['data']));
        const percent = BrapiJson.asDouble(item['valor']);
        if (date === null || percent === null) continue;
        points.push(new RatePoint({ date, rate: percent / 100.0 }));
      }

      if (points.length === 0) {
        return err(new InsufficientData(`Série SGS ${seriesId} sem dados no período solicitado.`));
      }
      return ok(new RateSeries(points, { basis: BcbDatasource.basisOf(seriesId) }));
    });
  }
}

function brDate(date: DateTime): string {
  return `${String(date.day).padStart(2, '0')}/${String(date.month).padStart(2, '0')}/${date.year}`;
}

function parseBrDate(raw: string | null): DateTime | null {
  if (raw === null) return null;
  const parts = raw.split('/');
  if (parts.length !== 3) return null;
  const day = tryParseInt(parts[0]!);
  const month = tryParseInt(parts[1]!);
  const year = tryParseInt(parts[2]!);
  if (day === null || month === null || year === null) return null;
  return DateTime.local(year, month, day);
}
