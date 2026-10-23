import { describe, expect, it } from 'vitest';

import {
  ComputationFailure,
  DataQualityFailure,
  DateRange,
  DateTime,
  InsufficientData,
  InvalidInput,
  type JsonObject,
  Ticker,
} from '../../src/core';
import { BcbDatasource } from '../../src/data/datasources/bcb-datasource';
import { BrapiDatasource } from '../../src/data/datasources/brapi-datasource';
import type { HttpErrorType } from '../../src/data/network/http';
import { day, expectClose } from '../core/helpers';
import { clientWith, FixtureTransport, readFixture } from './fixture-transport';

const t = (s: string): Ticker => Ticker.parse(s);

const ALL_STATEMENTS = {
  '/v2/stocks/statistics?symbols=PETR4&mode=history': 'brapi_statistics_history_petr4',
  '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
  '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
  '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
  '/v2/stocks/statistics?symbols=PETR4&mode=current': 'brapi_statistics_current_petr4',
};

function without(route: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(ALL_STATEMENTS)) if (k !== route) out[k] = v;
  return out;
}

describe('BrapiDatasource — cotações', () => {
  it('lote devolve uma série por ativo solicitado', async () => {
    const fixture = new FixtureTransport({ routes: { '/v2/stocks/historical': 'brapi_historical_batch' } });
    const datasource = new BrapiDatasource(clientWith(fixture));

    const result = await datasource.historicalBatch([t('PETR4'), t('VALE3')]);

    expect(result.isOk).toBe(true);
    const series = result.unwrap();
    expect(new Set([...series.keys()].map((x) => x.value))).toEqual(new Set(['PETR4', 'VALE3']));
    expect(series.get(t('PETR4'))!.points.length).toBeGreaterThan(0);
    // Uma única requisição para os dois ativos.
    expect(fixture.callCount['/v2/stocks/historical']).toBe(1);
  });

  it('série vem ordenada e com preços positivos', async () => {
    const datasource = new BrapiDatasource(
      clientWith(new FixtureTransport({ routes: { '/v2/stocks/historical': 'brapi_historical_batch' } })),
    );
    const series = (await datasource.historicalBatch([t('PETR4')])).unwrap().get(t('PETR4'))!;
    for (let i = 1; i < series.points.length; i++) {
      expect(series.points[i]!.date.isAfter(series.points[i - 1]!.date), 'a série precisa estar em ordem cronológica').toBe(
        true,
      );
    }
    expect(series.points.every((p) => p.close > 0)).toBe(true);
  });

  it('epoch em segundos vira data sem horário', async () => {
    const datasource = new BrapiDatasource(
      clientWith(new FixtureTransport({ routes: { '/v2/stocks/historical': 'brapi_historical_batch' } })),
    );
    const series = (await datasource.historicalBatch([t('PETR4')])).unwrap().get(t('PETR4'))!;
    const first = series.points[0]!.date;
    expect(first.hour).toBe(0);
    expect(first.minute).toBe(0);
  });

  it('Ibovespa é carregado da mesma rota histórica', async () => {
    const datasource = new BrapiDatasource(
      clientWith(new FixtureTransport({ routes: { '/v2/stocks/historical': 'brapi_ibovespa' } })),
    );
    const result = await datasource.ibovespa();
    expect(result.isOk).toBe(true);
    expect(result.unwrap().points.length).toBeGreaterThan(0);
  });
});

describe('BrapiDatasource — payload corrompido', () => {
  // Fixture gravada é resposta BOA: testar higienização contra ela prova só
  // o formato do arquivo. O que a camada existe para filtrar precisa ser
  // injetado de propósito.

  const historical = (body: string): BrapiDatasource =>
    new BrapiDatasource(clientWith(new FixtureTransport({ bodies: { '/v2/stocks/historical': body } })));

  it('descarta ponto com preço não positivo', async () => {
    const datasource = historical(`
{"results":[{"symbol":"PETR4","data":{"historicalDataPrice":[
  {"date":1704157200,"close":30.0},
  {"date":1704243600,"close":-5.0},
  {"date":1704330000,"close":0.0},
  {"date":1704416400,"close":31.5}
]}}]}`);
    const series = (await datasource.historicalBatch([t('PETR4')])).unwrap().get(t('PETR4'))!;
    // Dois pontos sobrevivem; o negativo e o zero somem sem derrubar o lote.
    expect(series.points.length).toBe(2);
    expect(series.points.every((p) => p.close > 0)).toBe(true);
  });

  it('reordena pontos que a fonte entrega fora de ordem', async () => {
    const datasource = historical(`
{"results":[{"symbol":"VALE3","data":{"historicalDataPrice":[
  {"date":1704416400,"close":31.5},
  {"date":1704157200,"close":30.0},
  {"date":1704330000,"close":31.0}
]}}]}`);
    const series = (await datasource.historicalBatch([t('VALE3')])).unwrap().get(t('VALE3'))!;
    expect(series.points.length).toBe(3);
    for (let i = 1; i < series.points.length; i++) {
      expect(
        series.points[i]!.date.isAfter(series.points[i - 1]!.date),
        'a série precisa sair cronológica, venha como vier',
      ).toBe(true);
    }
    // E a busca por data continua correta depois da reordenação.
    expect(series.closeAsOf(series.points[series.points.length - 1]!.date)).toBe(31.5);
  });

  it('ponto sem data ou sem fechamento é ignorado, não derruba o lote', async () => {
    const datasource = historical(`
{"results":[{"symbol":"ITUB4","data":{"historicalDataPrice":[
  {"close":30.0},
  {"date":1704157200},
  {"date":1704243600,"close":"texto"},
  {"date":1704330000,"close":32.0}
]}}]}`);
    const result = await datasource.historicalBatch([t('ITUB4')]);
    expect(result.isOk).toBe(true);
    expect(result.unwrap().get(t('ITUB4'))!.points.length).toBe(1);
  });

  it('ativo todo corrompido some do mapa sem levar o lote junto', async () => {
    // Mapa parcial é o contrato do lote: um ativo ruim não pode derrubar os
    // outros, nem entrar como série vazia que o backtest aceitaria.
    const datasource = historical(`
{"results":[
  {"symbol":"PETR4","data":{"historicalDataPrice":[
    {"date":1704157200,"close":-1.0},
    {"date":1704243600,"close":0.0}
  ]}},
  {"symbol":"VALE3","data":{"historicalDataPrice":[
    {"date":1704157200,"close":60.0}
  ]}}
]}`);
    const result = await datasource.historicalBatch([t('PETR4'), t('VALE3')]);
    expect(result.isOk).toBe(true);
    const map = result.unwrap();
    expect(map.has(t('PETR4'))).toBe(false);
    expect(map.get(t('VALE3'))!.points.length).toBe(1);
  });

  it('lote inteiro corrompido falha explicitamente, e não em silêncio', async () => {
    // Sem nenhuma série utilizável, devolver mapa vazio faria o consumidor
    // tratar corrupção como "ativo sem histórico". O erro precisa ser dito.
    const datasource = historical(`
{"results":[{"symbol":"PETR4","data":{"historicalDataPrice":[
  {"date":1704157200,"close":-1.0}
]}}]}`);
    const result = await datasource.historicalBatch([t('PETR4')]);
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });
});

describe('BrapiDatasource — falha sem resposta do servidor', () => {
  // O grupo de erro cobre status codificados (401, 404, 429). Uma conexão que
  // cai não tem status nenhum: a resposta é nula, e era o caminho sem
  // cobertura. Exceção crua atravessando a camada de dados quebraria o
  // contrato `Result` inteiro.

  async function becomesFailure(kind: HttpErrorType): Promise<void> {
    const datasource = new BrapiDatasource(
      clientWith(new FixtureTransport({ transportErrors: { '/v2/stocks/historical': kind } })),
    );
    const result = await datasource.historicalBatch([t('PETR4')]);
    expect(result.isErr, `${kind} deveria virar Result.err`).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  }

  it('tempo de conexão esgotado vira falha de domínio', () => becomesFailure('connectionTimeout'));
  it('tempo de recepção esgotado vira falha de domínio', () => becomesFailure('receiveTimeout'));
  it('conexão perdida vira falha de domínio', () => becomesFailure('connectionError'));

  it('erro de transporte desconhecido também não escapa', async () => {
    const datasource = new BrapiDatasource(
      clientWith(new FixtureTransport({ transportErrors: { '/v2/stocks/historical': 'unknown' } })),
    );
    const result = await datasource.historicalBatch([t('PETR4')]);
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(ComputationFailure);
  });
});

describe('BrapiDatasource — fundamentos', () => {
  it('falha de UM demonstrativo reprova a busca inteira', async () => {
    // Decisão 68. A versão anterior seguia e devolvia Ok desde que ALGUM dos
    // quatro respondesse — produzindo série com balanço preenchido e
    // resultado ausente, que é a forma que a decisão 52 trata como "ausência
    // não é zero". E o repositório GRAVA o resultado no cache, de modo que a
    // corrupção sobrevivia à falha de rede e era preferida nas leituras
    // seguintes.
    const datasource = new BrapiDatasource(
      clientWith(
        new FixtureTransport({
          routes: without('/v2/stocks/income-statement'),
          failures: { '/v2/stocks/income-statement': 503 },
        }),
      ),
    );
    const r = await datasource.fundamentalsHistory(t('PETR4'));
    expect(r.isErr, 'sem a DRE, a série não descreve a empresa').toBe(true);
  });

  it('demonstrativo com tipo indevido vira falha, e não exceção crua', async () => {
    // Lente `risco`, 21/09/2026. As três rotas de demonstrativo e as duas de
    // estatística: o histórico e o corrente trazem a contagem de ações e o
    // valor de mercado, que dividem o preço justo.
    const brokenCases: Record<string, string[]> = {
      '/v2/stocks/income-statement': [
        '{"results":[{"incomeStatementHistory":"não é lista"}]}',
        '{"results":[{"incomeStatementHistory":[{"endDate":"2024-12-31","netIncome":"quarenta bilhões"}]}]}',
      ],
      '/v2/stocks/balance-sheet': [
        '{"results":[{"data":"não é lista"}]}',
        '{"results":[{"data":[{"type":"yearly","endDate":"2024-12-31","totalAssets":"um trilhão","cash":[1]}]}]}',
      ],
      '/v2/stocks/cash-flow': [
        '{"results":[{"data":{"não":"é lista"}}]}',
        '{"results":[{"data":[{"type":"yearly","endDate":"2024-12-31","operatingCashFlow":"duzentos bilhões"}]}]}',
      ],
      '/v2/stocks/statistics?symbols=PETR4&mode=history': [
        '{"results":[{"data":"não é lista"}]}',
        '{"results":[{"data":[{"type":"yearly","endDate":"2025-12-31","sharesOutstanding":"treze bilhões","marketCap":[1]}]}]}',
      ],
      '/v2/stocks/statistics?symbols=PETR4&mode=current': [
        '{"results":[{"data":["não é objeto"]}]}',
        '{"results":[{"data":{"sharesOutstanding":"treze bilhões","marketCap":{"x":1},"enterpriseToEbitda":"quatro"}}]}',
      ],
    };
    for (const route of Object.keys(ALL_STATEMENTS)) {
      for (const body of [...brokenCases[route]!, '{"results":"nem objeto"}', '[]', 'isto não é json']) {
        const datasource = new BrapiDatasource(
          clientWith(new FixtureTransport({ routes: without(route), bodies: { [route]: body } })),
        );
        // O contrato é `Result`: ou vem erro, ou vem série — e nunca uma
        // exceção atravessando a camada de dados. **Quem cobra isso é o
        // `await`**: exceção que escape reprova o teste aqui mesmo.
        const r = await datasource.fundamentalsHistory(t('PETR4'));
        // O que nem é JSON é recusa, em toda rota; o JSON de forma errada numa
        // rota é tolerado, e as outras rotas continuam entregando os
        // exercícios — tolerar não é devolver série vazia.
        if (body === 'isto não é json') {
          expect(r.isErr, `${route} ${body}`).toBe(true);
          continue;
        }
        expect(r.isOk && r.unwrap().length > 0, `um corpo ruim numa rota não apaga as outras: ${route} ${body}`).toBe(true);
        // Tolerar o corpo é legítimo; **inventar número** não.
        for (const s of r.unwrap()) {
          for (const v of [
            s.netIncome,
            s.totalAssets,
            s.operatingCashFlow,
            s.sharesOutstanding,
            s.sharesOutstandingAsOf,
            s.marketCap,
            s.enterpriseToEbitda,
          ]) {
            expect(v === null || Number.isFinite(v), `${route} ${body}`).toBe(true);
          }
        }
      }
    }
  });

  it('e o mesmo vale para falha de transporte', async () => {
    const datasource = new BrapiDatasource(
      clientWith(
        new FixtureTransport({
          routes: without('/v2/stocks/cash-flow'),
          transportErrors: { '/v2/stocks/cash-flow': 'connectionTimeout' },
        }),
      ),
    );
    expect((await datasource.fundamentalsHistory(t('PETR4'))).isErr).toBe(true);
  });

  it('e vale para o snapshot corrente, que as linhas anuais não substituem', async () => {
    // Decisão 77. Sem o corrente, as linhas anuais ficavam com o PRÓPRIO
    // `marketCap` — o calculado por ações × preço da unit, que inflava o
    // SAPR11 de R$ 10,1 bi para R$ 59,9 bi — e com a contagem do exercício
    // no lugar da de hoje.
    const datasource = new BrapiDatasource(
      clientWith(
        new FixtureTransport({
          routes: without('/v2/stocks/statistics?symbols=PETR4&mode=current'),
          failures: { '/v2/stocks/statistics?symbols=PETR4&mode=current': 503 },
        }),
      ),
    );
    const r = await datasource.fundamentalsHistory(t('PETR4'));
    expect(r.isErr, 'sem o corrente, valor de mercado e contagem descrevem o exercício, e não hoje').toBe(true);
  });

  it('snapshot corrente vazio não deixa o valor de mercado anual no lugar', async () => {
    // Lente `dados`, 14/09/2026. Resposta 200 sem dado é ausência declarada,
    // e não falha — mas as linhas anuais ficavam com o próprio `marketCap`.
    const datasource = new BrapiDatasource(
      clientWith(
        new FixtureTransport({
          routes: without('/v2/stocks/statistics?symbols=PETR4&mode=current'),
          bodies: { '/v2/stocks/statistics?symbols=PETR4&mode=current': '{"results":[]}' },
        }),
      ),
    );
    const s = (await datasource.fundamentalsHistory(t('PETR4'))).unwrap();
    expect(s.every((x) => x.marketCap === null)).toBe(true);
    expect(s.every((x) => x.sharesOutstanding === null)).toBe(true);
    expect(s.some((x) => x.sharesOutstandingAsOf !== null), 'a contagem do exercício continua, em campo próprio').toBe(true);
  });

  it('snapshot corrente sem valor de mercado não deixa o anual no lugar', async () => {
    // Lente `dados`, 15/09/2026. A limpeza só valia com o snapshot inteiro
    // ausente: um corrente com a contagem e sem o `marketCap` deixava o da
    // linha anual passando por valor de hoje.
    const datasource = new BrapiDatasource(
      clientWith(
        new FixtureTransport({
          routes: without('/v2/stocks/statistics?symbols=PETR4&mode=current'),
          bodies: {
            '/v2/stocks/statistics?symbols=PETR4&mode=current':
              '{"results":[{"symbol":"PETR4","data":{"sharesOutstanding":12888733000}}]}',
          },
        }),
      ),
    );
    const s = (await datasource.fundamentalsHistory(t('PETR4'))).unwrap();
    expect(s.length).toBeGreaterThan(0);
    expect(s.every((x) => x.marketCap === null)).toBe(true);
    expect(s.every((x) => x.sharesOutstanding === 12888733000)).toBe(true);
  });

  it('funde os quatro demonstrativos pela chave do exercício', async () => {
    const datasource = new BrapiDatasource(clientWith(new FixtureTransport({ routes: ALL_STATEMENTS })));
    const result = await datasource.fundamentalsHistory(t('PETR4'));
    expect(result.isOk).toBe(true);
    const snapshots = result.unwrap();
    expect(snapshots.length, 'a fonte entrega 16 exercícios anuais').toBeGreaterThan(10);
    // Um mesmo exercício precisa reunir campos de demonstrativos diferentes.
    const recent = [...snapshots].reverse().find((s) => s.fiscalPeriodEnd.year >= 2023) ?? snapshots[snapshots.length - 1]!;
    expect(recent.totalRevenue, 'DRE').not.toBeNull();
    expect(recent.operatingCashFlow, 'DFC').not.toBeNull();
    expect(recent.cash, 'Balanço').not.toBeNull();
  });

  it('a fusão é por exercício, e não por posição: um ano que falta numa rota não desalinha os outros', async () => {
    // Lente `risco`, 27/09/2026: o teste acima olha um exercício só, e uma
    // fusão por posição acertaria nele por coincidência. Aqui o fluxo de
    // caixa perde 2020, e cada exercício é conferido contra a fixture.
    const fixture = (name: string): JsonObject => JSON.parse(readFixture(name)) as JsonObject;
    const years = (j: JsonObject): JsonObject[] => ((j['results'] as JsonObject[])[0]!['data'] as JsonObject[]);
    const dre = years(fixture('brapi_income_statement_history_petr4'));
    const dfcJson = fixture('brapi_cash_flow_history_petr4');
    const dfc = years(dfcJson);
    (dfcJson['results'] as JsonObject[])[0]!['data'] = dfc.filter((x) => x['endDate'] !== '2020-12-31');

    const snapshots = (
      await new BrapiDatasource(
        clientWith(
          new FixtureTransport({
            routes: without('/v2/stocks/cash-flow'),
            bodies: { '/v2/stocks/cash-flow': JSON.stringify(dfcJson) },
          }),
        ),
      ).fundamentalsHistory(t('PETR4'))
    ).unwrap();
    const byYear = new Map(snapshots.map((s) => [s.fiscalPeriodEnd.year, s]));
    for (const x of dre) {
      const year = DateTime.parse(x['endDate'] as string).year;
      const s = byYear.get(year);
      expect(s, `exercício ${year}`).toBeDefined();
      expect(s!.totalRevenue, `receita de ${year}`).toBe((x['totalRevenue'] as number | undefined) ?? null);
      const cash = dfc.find((y) => y['endDate'] === x['endDate'])!;
      expect(s!.operatingCashFlow, `fluxo de caixa de ${year}`).toBe(
        year === 2020 ? null : ((cash['operatingCashFlow'] as number | undefined) ?? null),
      );
    }
  });

  it('deriva D&A, alíquota efetiva e dívida líquida', async () => {
    const datasource = new BrapiDatasource(clientWith(new FixtureTransport({ routes: ALL_STATEMENTS })));
    const snapshots = (await datasource.fundamentalsHistory(t('PETR4'))).unwrap();
    expect(
      snapshots.some((s) => s.depreciationAndAmortization !== null),
      'D&A = EBITDA − EBIT deve ser derivável em algum exercício',
    ).toBe(true);

    const withTax = snapshots.filter((s) => s.effectiveTaxRate !== null);
    expect(withTax.length).toBeGreaterThan(0);
    // **Isto não testa o teto** (lente `risco`, 21/09/2026): é conferência de
    // **faixa do que a fonte trouxe**. Quem testa o teto é o núcleo.
    expect(
      withTax.every((s) => s.effectiveTaxRate! <= 0.5),
      'nenhum exercício da fixture sai fora da faixa que o núcleo garante',
    ).toBe(true);

    // Os números de um exercício, e não só a existência deles (lente `risco`,
    // 16/09/2026). No arquivo de 2025: imposto de R$ 39,994 bi sobre lucro
    // antes do imposto de R$ 150,599 bi; caixa de R$ 35,608 bi e aplicações
    // de R$ 15,000001 bi, que a dívida líquida desconta.
    const a2025 = snapshots.filter((s) => s.fiscalPeriodEnd.year === 2025);
    expect(a2025).toHaveLength(1);
    const y = a2025[0]!;
    expectClose(y.effectiveTaxRate, 39994 / 150599, 1e-12);
    expect(y.cash).toBe(35608000000);
    expect(y.shortTermInvestments).toBe(15000001000);
    expect(y.totalDebt).toBeGreaterThan(0);
    expectClose(y.netDebt, y.totalDebt - 35608000000 - 15000001000, 1e-3);
    if (y.ebitda === null) expect(y.depreciationAndAmortization).toBeNull();
    else expectClose(y.depreciationAndAmortization, y.ebitda - 145628000000, 1e-3);
  });

  it('exercícios saem em ordem cronológica', async () => {
    const datasource = new BrapiDatasource(clientWith(new FixtureTransport({ routes: ALL_STATEMENTS })));
    const snapshots = (await datasource.fundamentalsHistory(t('PETR4'))).unwrap();
    for (let i = 1; i < snapshots.length; i++) {
      expect(snapshots[i]!.fiscalPeriodEnd.isAfter(snapshots[i - 1]!.fiscalPeriodEnd)).toBe(true);
    }
  });
});

describe('BrapiDatasource — perfil e tickers', () => {
  it('mapeia setor e indústria da taxonomia da fonte', async () => {
    const datasource = new BrapiDatasource(
      clientWith(new FixtureTransport({ routes: { '/v2/stocks/profile': 'brapi_profile_petr4' } })),
    );
    const asset = (await datasource.profile(t('PETR4'))).unwrap();
    expect(asset.sector.isUnknown).toBe(false);
    expect(asset.sector.key).toBe('energia');
    expect(asset.industry).not.toBeNull();
  });
});

describe('BcbDatasource', () => {
  const range = new DateRange(day(2024, 1, 1), day(2024, 3, 31));
  const cdi = (): BcbDatasource =>
    new BcbDatasource(clientWith(new FixtureTransport({ routes: { 'bcdata.sgs.12': 'bcb_cdi' } })));

  it('converte percentual diário em fração', async () => {
    const result = await cdi().series(BcbDatasource.seriesCdiDaily, range);
    expect(result.isOk).toBe(true);
    const series = result.unwrap();
    expect(series.rates.length).toBeGreaterThan(0);
    // 0,043739% ao dia → 0,00043739 em fração.
    expectClose(series.rates[0], 0.00043739, 1e-9);
    expect(series.rates.every((r) => r > 0 && r < 0.01)).toBe(true);
  });

  it('acumula e anualiza o CDI do período', async () => {
    const series = (await cdi().series(BcbDatasource.seriesCdiDaily, range)).unwrap();
    // Os 61 dias do arquivo, compostos à mão fora do código: fator de
    // 1,0262106 no período e 11,2806% ao ano na base 252. A média linear das
    // taxas diárias vezes 252 daria 10,69% — e a composição é a regra.
    expect(series.rates).toHaveLength(61);
    expectClose(series.accumulated, 0.0262105893, 1e-9);
    expectClose(series.annualized(), 0.1128063761, 1e-9);
  });

  it('datas dd/MM/yyyy são interpretadas corretamente', async () => {
    const series = (await cdi().series(BcbDatasource.seriesCdiDaily, range)).unwrap();
    // A fixture começa em 02/01/2024. Sob uma troca dd/MM -> MM/dd ela
    // viraria 1 de FEVEREIRO; a asserção de dia torna o teste independente
    // de qual arquivo o alimenta.
    expect(series.dates[0]!.year).toBe(2024);
    expect(series.dates[0]!.month).toBe(1);
    expect(series.dates[0]!.day).toBe(2);
  });

  it('JSON sem as chaves esperadas vira falha, e não exceção crua', async () => {
    // Lente `risco`, 20/09/2026. A troca de layout do Banco Central escapava
    // como exceção nativa em vez de `Result.err`.
    for (const body of [
      '[{"valor":"0,04"}]', // sem `data`
      '[{"data":"02/01/2024"}]', // sem `valor`
      '[{"data":"02/01/2024","valor":"não é número"}]',
      '{"erro":"série indisponível"}', // objeto no lugar da lista
      'isto não é json',
    ]) {
      const datasource = new BcbDatasource(clientWith(new FixtureTransport({ bodies: { 'bcdata.sgs.12': body } })));
      const r = await datasource.series(BcbDatasource.seriesCdiDaily, range);
      expect(r.isErr, body).toBe(true);
    }
  });
});

describe('Tratamento de erro da API', () => {
  const failing = (status: number): BrapiDatasource =>
    new BrapiDatasource(clientWith(new FixtureTransport({ failures: { '/v2/stocks/profile': status } })));

  it('401 vira falha de credencial, não exceção crua', async () => {
    const result = await failing(401).profile(t('PETR4'));
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InvalidInput);
    expect(result.failureOrNull!.message).toContain('Credencial');
  });

  it('404 vira dado insuficiente', async () => {
    const result = await failing(404).profile(t('XXXX3'));
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('429 é reportado como limite de requisições', async () => {
    const result = await failing(429).profile(t('PETR4'));
    expect(result.failureOrNull).toBeInstanceOf(DataQualityFailure);
  });
});
