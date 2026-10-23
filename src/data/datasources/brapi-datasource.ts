import {
  type Asset,
  err,
  type FundamentalsSnapshot,
  InsufficientData,
  isJsonObject,
  type JsonObject,
  ok,
  PricePoint,
  PriceSeries,
  type Result,
  Ticker,
} from '../../core';
import { BrapiFundamentalsDto, BrapiJson, BrapiPriceDto, BrapiProfileDto } from '../dtos/brapi-dtos';
import type { ApiClient } from '../network/api-client';

/** Os quatro demonstrativos da brapi, fundidos pela chave `endDate`. */
const STATEMENT_ENDPOINTS = [
  '/v2/stocks/statistics',
  '/v2/stocks/income-statement',
  '/v2/stocks/balance-sheet',
  '/v2/stocks/cash-flow',
] as const;

/** Campos que descrevem o **hoje**, e não o exercício (decisão 77). */
const CURRENT_FIELDS = ['sharesOutstanding', 'enterpriseToEbitda', 'marketCap'] as const;

/**
 * Acesso aos endpoints da brapi.dev (v2).
 *
 * Todos os caminhos aqui foram verificados contra a API real em 19/08/2026;
 * as formas de resposta irregulares estão tratadas em [BrapiJson].
 */
export class BrapiDatasource {
  constructor(readonly client: ApiClient) {}

  private url(path: string): string {
    return `${this.client.config.brapiBaseUrl}${path}`;
  }

  // ------------------------------------------------------------- Cotações --

  /**
   * Histórico diário de vários ativos em **uma** requisição.
   *
   * O lote foi medido em 3.460 ms contra 6.417 ms sequenciais para 10 ativos
   * — 1,85× mais rápido — e consome 1 requisição em vez de 10, o que importa
   * porque o limite da API é inobservável.
   */
  async historicalBatch(
    tickers: readonly Ticker[],
    options: { range?: string } = {},
  ): Promise<Result<Map<Ticker, PriceSeries>>> {
    if (tickers.length === 0) return ok(new Map());

    const symbols = tickers.map((t) => t.value).join(',');
    const response = await this.client.getJson(this.url('/v2/stocks/historical'), {
      query: { symbols, range: options.range ?? '10y', interval: '1d' },
      heavy: true, // ~2.500 pontos por ativo
    });

    return response.flatMap((body) => {
      const results = BrapiJson.results(body);
      if (results.length === 0) {
        return err(new InsufficientData('Nenhuma cotação retornada para os ativos solicitados.'));
      }

      const out = new Map<Ticker, PriceSeries>();
      for (const entry of results) {
        if (!isJsonObject(entry)) continue;
        const symbol = BrapiJson.asString(entry['symbol']) ?? BrapiJson.asString(entry['requestedSymbol']);
        if (symbol === null) continue;
        const ticker = Ticker.tryParse(symbol);
        if (ticker === null) continue;

        const data = entry['data'];
        const raw = isJsonObject(data) ? data['historicalDataPrice'] : null;
        if (!Array.isArray(raw)) continue;

        const points = pricePoints(raw);
        if (points.length > 0) out.set(ticker, new PriceSeries({ ticker, points }));
      }

      if (out.size === 0) {
        return err(new InsufficientData('A resposta não continha nenhuma série de preços utilizável.'));
      }
      return ok(out);
    });
  }

  /** Série do Ibovespa, pelo `close` — a mesma convenção usada nos ativos. */
  async ibovespa(options: { range?: string } = {}): Promise<Result<PriceSeries>> {
    const response = await this.client.getJson(this.url('/v2/stocks/historical'), {
      query: { symbols: '^BVSP', range: options.range ?? '10y', interval: '1d' },
      heavy: true,
    });

    return response.flatMap((body) => {
      const data = BrapiJson.firstData(body);
      const raw = data?.['historicalDataPrice'];
      if (!Array.isArray(raw) || raw.length === 0) {
        return err(new InsufficientData('Sem histórico do Ibovespa.'));
      }
      // ^BVSP não passa no formato de ticker da B3; usa-se um rótulo interno.
      return ok(new PriceSeries({ ticker: Ticker.parse('IBOV11'), points: pricePoints(raw) }));
    });
  }

  // ----------------------------------------------------------- Fundamentos --

  /**
   * Os campos **crus** de cada exercício, sem passar pelo domínio.
   *
   * A fonte só oferece granularidade **anual** (16 exercícios, 2010–2025);
   * `mode=history&type=quarterly` também devolve anual. Limitação a declarar.
   *
   * Existe para o D7: a ponte de equity precisa saber quais termos a fonte
   * publica — não controladores, coligada, arrendamento —, e o mapeamento
   * para [FundamentalsSnapshot] descarta tudo que ele não tipa. O cache
   * guarda só o tipado, de modo que a pergunta só se responde na fonte.
   */
  async rawFundamentals(ticker: Ticker): Promise<Result<JsonObject[]>> {
    const r = await this.mergedStatements(ticker);
    if (r.isErr) return err(r.failureOrNull!);
    const merged = r.unwrap();
    const keys = [...merged.keys()].sort();
    return ok(keys.map((k) => merged.get(k)!));
  }

  /**
   * Os quatro demonstrativos fundidos pelo fim do exercício.
   *
   * **Falha de um endpoint reprova a busca inteira** (decisão 68). A versão
   * anterior seguia e devolvia `Ok` desde que **algum** dos quatro
   * respondesse — de modo que uma falha de rede na demonstração de resultado
   * produzia série com balanço preenchido e resultado ausente. Duas coisas
   * tornavam isso grave: essa forma é exatamente a que a decisão 52 trata
   * como "ausência não é zero", e o repositório **grava o resultado no
   * cache**, de modo que a corrupção sobrevivia à falha e era preferida nas
   * leituras seguintes.
   *
   * `getJson` devolve `Err` para status de erro, resposta vazia, falha de
   * transporte e JSON inválido — todos "deu errado". Companhia que
   * legitimamente não publica um demonstrativo responde 200 com lista vazia,
   * e essa continua passando.
   */
  private async mergedStatements(ticker: Ticker): Promise<Result<Map<string, JsonObject>>> {
    const merged = new Map<string, JsonObject>();
    for (const endpoint of STATEMENT_ENDPOINTS) {
      const response = await this.client.getJson(this.url(endpoint), {
        query: { symbols: ticker.value, mode: 'history' },
      });
      if (response.isErr) return err(response.failureOrNull!);
      for (const item of BrapiJson.firstDataList(response.unwrap())) {
        if (!isJsonObject(item)) continue;
        const endDate = BrapiJson.asString(item['endDate']);
        if (endDate === null) continue;
        const key = endDate.split('T')[0]!;
        let slot = merged.get(key);
        if (slot === undefined) {
          slot = {};
          merged.set(key, slot);
        }
        Object.assign(slot, item);
      }
    }
    if (merged.size === 0) {
      return err(new InsufficientData(`Nenhum demonstrativo disponível para ${ticker.value}.`));
    }
    return ok(merged);
  }

  /** Fundamentos anuais consolidados dos quatro demonstrativos. */
  async fundamentalsHistory(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    // Chave = fim do exercício; os quatro demonstrativos são fundidos por ela.
    const statements = await this.mergedStatements(ticker);
    if (statements.isErr) return err(statements.failureOrNull!);
    const merged = statements.unwrap();

    // `sharesOutstanding`, `marketCap` e `enterpriseToEbitda` descrevem o
    // **hoje**, não o exercício; sem eles não há valor por ação nem múltiplo
    // de saída.
    //
    // **Falha aqui também reprova a busca** (decisão 77), pela mesma razão da
    // decisão 68 e com consequência pior: sem o corrente, as linhas anuais
    // ficam com o próprio `marketCap` — o inflado pelo fator da unit, descrito
    // logo abaixo — e com a contagem do exercício no lugar da de hoje. Isso
    // saía como `Ok` e ia para o cache. Resposta 200 sem dado continua
    // passando: é ausência declarada pela fonte, e não falha.
    const current = await this.client.getJson(this.url('/v2/stocks/statistics'), {
      query: { symbols: ticker.value, mode: 'current' },
    });
    if (current.isErr) return err(current.failureOrNull!);
    const currentData = BrapiJson.firstData(current.unwrap());
    const present = (json: JsonObject | null, key: string): boolean =>
      json !== null && json[key] !== undefined && json[key] !== null;

    const snapshots: FundamentalsSnapshot[] = [];
    for (const [key, annual] of merged) {
      const date = BrapiJson.asDate(key);
      if (date === null) continue;
      // O snapshot corrente vem **depois** e prevalece. As linhas anuais também
      // trazem esses três campos, e nelas o `marketCap` é calculado como
      // `ações × preço da unit` — o que o infla pelo fator da unit: SAPR11
      // aparecia com R$ 59,9 bi contra os R$ 10,1 bi reais, KLBN11 com R$ 117
      // bi contra R$ 23,0 bi (medido em 21/08/2026). Deixá-las sobrescrever
      // estragava o peso do equity no WACC e impedia identificar a unit.
      //
      // **A contagem do exercício é preservada em campo próprio.** A
      // sobrescrita acima é correta para o valor por papel de hoje, mas destrói
      // a única base comparável do patrimônio: `bookValue` é publicado por ação
      // **do ano**, e multiplicá-lo pela contagem corrente mistura duas escalas.
      // O BBAS3 bonificou em 2024 e a contagem dobrou, de 2,865 bi para
      // 5,731 bi; sem `sharesOutstandingAsOf` não há patrimônio líquido nem
      // capital investido reconstituíveis (decisão 25).
      const fields: JsonObject = { ...annual };
      if (present(annual, 'sharesOutstanding')) fields['sharesOutstandingAsOf'] = annual['sharesOutstanding'];
      for (const field of CURRENT_FIELDS) {
        if (present(currentData, field)) fields[field] = currentData![field];
      }
      // **Campo de hoje que o snapshot corrente não traz fica ausente** — e
      // não com o valor da linha anual. A resposta vazia é ausência declarada,
      // e não falha (decisão 77); mas o `marketCap` da linha anual é o do fim
      // do exercício, e o inflado pela unit nas units, e a contagem é a do
      // exercício, que já está em `sharesOutstandingAsOf`. Nenhum descreve
      // hoje, e ausência não é o valor errado. **Campo a campo**, e não só com
      // o snapshot inteiro ausente: um corrente que traga a contagem e omita o
      // valor de mercado deixava o anual no lugar (lente `dados`, 15/09/2026).
      for (const field of CURRENT_FIELDS) {
        if (!present(currentData, field)) delete fields[field];
      }
      snapshots.push(new BrapiFundamentalsDto({ fiscalPeriodEnd: date, fields }).toDomain(ticker));
    }

    snapshots.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
    return ok(snapshots);
  }

  // --------------------------------------------------------------- Perfil --

  async profile(ticker: Ticker): Promise<Result<Asset>> {
    const response = await this.client.getJson(this.url('/v2/stocks/profile'), {
      query: { symbols: ticker.value },
    });
    return response.flatMap((body) => {
      const data = BrapiJson.firstData(body);
      if (data === null) return err(new InsufficientData(`Perfil indisponível para ${ticker.value}.`));
      return ok(BrapiProfileDto.fromJson(data).toDomain(ticker));
    });
  }

  // -------------------------------------------------------------- Tickers --

  /**
   * Universo de ações da B3.
   *
   * `type=stock` já exclui fundos — verificado: 781 ações contra 332 FIIs,
   * interseção vazia. Não há whitelist manual de Units: a anterior excluía
   * indevidamente IGTI11, ONCO11 e BRBI11.
   */
  async universe(): Promise<Result<Ticker[]>> {
    const response = await this.client.getJson(this.url('/v2/tickers'), {
      query: { type: 'stock', limit: '1000' },
    });
    return response.map((body) => {
      const tickers = new Set<Ticker>();
      for (const item of BrapiJson.results(body)) {
        const symbol =
          typeof item === 'string' ? item : isJsonObject(item) ? BrapiJson.asString(item['symbol']) : null;
        if (symbol === null) continue;
        const ticker = Ticker.tryParse(symbol);
        if (ticker !== null) tickers.add(ticker);
      }
      return [...tickers].sort((a, b) => a.compareTo(b));
    });
  }
}

function pricePoints(raw: readonly unknown[]): PricePoint[] {
  const points: PricePoint[] = [];
  for (const item of raw) {
    if (!isJsonObject(item)) continue;
    const dto = BrapiPriceDto.fromJson(item);
    if (dto !== null) points.push(dto.toDomain());
  }
  return points;
}
