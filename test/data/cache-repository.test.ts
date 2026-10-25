import { beforeEach, describe, expect, it } from 'vitest';

import { DataQualityFailure, DateRange, type DateTime, Ticker } from '../../src/core';
import { CacheDatabase } from '../../src/data/cache/cache-database';
import { CachePolicy } from '../../src/data/cache/cache-policy';
import { MemoryKeyValueStore } from '../../src/data/cache/key-value-store';
import { BcbDatasource } from '../../src/data/datasources/bcb-datasource';
import { BrapiDatasource } from '../../src/data/datasources/brapi-datasource';
import {
  FundamentalsRepositoryImpl,
  MacroRepositoryImpl,
  PriceRepositoryImpl,
} from '../../src/data/repositories/market-repositories';
import { day, expectClose } from '../core/helpers';
import { clientWith, FixtureTransport } from './fixture-transport';

const t = (s: string): Ticker => Ticker.parse(s);
const wideRange = (): DateRange => new DateRange(day(2000, 1, 1), day(2030, 1, 1));
const sameDay = (a: DateTime, b: DateTime): boolean => a.equals(b);

const ALL_STATEMENTS = {
  '/v2/stocks/statistics?symbols=PETR4&mode=history': 'brapi_statistics_history_petr4',
  '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
  '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
  '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
  '/v2/stocks/statistics?symbols=PETR4&mode=current': 'brapi_statistics_current_petr4',
};

const batchRoute = { '/v2/stocks/historical': 'brapi_historical_batch' };
const prices = (fixture: FixtureTransport, cache: CacheDatabase | null): PriceRepositoryImpl =>
  new PriceRepositoryImpl({ remote: new BrapiDatasource(clientWith(fixture)), cache });

let store: MemoryKeyValueStore;
let db: CacheDatabase;

/** Apaga as marcas de validade: o cache passa a estar vencido, com as linhas intactas. */
async function expireAll(s: MemoryKeyValueStore): Promise<void> {
  for (const key of s.keys()) if (key.includes(':entrada:')) await s.del(key);
}

beforeEach(() => {
  store = new MemoryKeyValueStore();
  db = new CacheDatabase(store);
});

describe('Falha de gravação no cache não derruba a busca', () => {
  // Lente `risco`, 21/09/2026. O cache é **otimização, não requisito**, e a
  // suíte cobria a ausência dele desde a raiz (`cache: null`). Faltava o
  // outro caminho: o banco **existe como objeto**, a rede responde, e toda
  // operação nele falha — cota esgotada, IndexedDB bloqueado. Se a exceção
  // subisse, o aplicativo jogaria fora o dado verdadeiro que acabou de baixar.

  /** Um banco que **nunca abre**. */
  function brokenDatabase(): CacheDatabase {
    const broken = new MemoryKeyValueStore();
    broken.failing = true;
    return new CacheDatabase(broken);
  }

  it('a premissa do grupo: o banco realmente falha', async () => {
    // **Sem esta conferência os testes abaixo passariam vazios.**
    await expect(brokenDatabase().isFresh(CachePolicy.pricesKey('PETR4'), CachePolicy.historicalPrices)).rejects.toThrow();
  });

  it('o que a rede trouxe chega a quem pediu', async () => {
    const ticker = t('PETR4');
    const r = await prices(new FixtureTransport({ routes: batchRoute }), brokenDatabase()).dailyBatch([ticker], wideRange());
    expect(r.isOk, 'a série veio da rede: falhar aqui joga fora dado bom por causa de uma otimização').toBe(true);
    expect(r.unwrap().get(ticker)!.points.length).toBeGreaterThan(0);
  });

  it('e a leitura seguinte volta à rede, porque não há cache', async () => {
    // A consequência aceita: sem gravação, não há o que reaproveitar, e a
    // segunda chamada repete a requisição. É degradação, e não defeito.
    const fixture = new FixtureTransport({ routes: batchRoute });
    const repository = prices(fixture, brokenDatabase());
    await repository.dailyBatch([t('PETR4')], wideRange());
    expect(fixture.callCount['/v2/stocks/historical']).toBe(1);
    await repository.dailyBatch([t('PETR4')], wideRange());
    expect(fixture.callCount['/v2/stocks/historical']).toBe(2);
  });

  // Lente `risco`, 22/09/2026: a prova valia só para cotações, e o nome do
  // grupo prometia os três repositórios que gravam no mesmo banco.
  it('fundamentos: o que a rede trouxe chega a quem pediu', async () => {
    const repository = new FundamentalsRepositoryImpl({
      remote: new BrapiDatasource(clientWith(new FixtureTransport({ routes: ALL_STATEMENTS }))),
      cache: brokenDatabase(),
    });
    const r = await repository.history(t('PETR4'));
    expect(r.isOk, 'os exercícios vieram da rede').toBe(true);
    expect(r.unwrap().length).toBeGreaterThan(0);
  });

  it('macro: o que a rede trouxe chega a quem pediu', async () => {
    const repository = new MacroRepositoryImpl({
      remote: new BcbDatasource(clientWith(new FixtureTransport({ routes: { 'bcdata.sgs.12': 'bcb_cdi' } }))),
      cache: brokenDatabase(),
    });
    const r = await repository.riskFreeDaily(new DateRange(day(2024, 1, 1), day(2024, 3, 31)));
    expect(r.isOk, 'a série do CDI veio do SGS').toBe(true);
    expect(r.unwrap().dates.length).toBeGreaterThan(0);
  });
});

describe('Cache de cotações', () => {
  it('segunda leitura não vai à rede', async () => {
    const fixture = new FixtureTransport({ routes: batchRoute });
    const repository = prices(fixture, db);

    const first = await repository.dailyBatch([t('PETR4')], wideRange());
    expect(first.isOk).toBe(true);
    expect(fixture.callCount['/v2/stocks/historical']).toBe(1);

    const second = await repository.dailyBatch([t('PETR4')], wideRange());
    expect(second.isOk).toBe(true);
    expect(
      fixture.callCount['/v2/stocks/historical'],
      'cotação de pregão encerrado é imutável e não deve ser rebuscada',
    ).toBe(1);
    expect(second.unwrap().get(t('PETR4'))!.points.length).toBe(first.unwrap().get(t('PETR4'))!.points.length);
  });

  // A fonte devolve uma janela fixa de dez anos e a gravação é aditiva: com o
  // tempo o disco guarda mais do que a resposta traz. O caminho de SUCESSO
  // devolvia o recorte da resposta, e encurtava a série de quem já tinha
  // histórico mais longo — pior que o caminho degradado, que lê o disco.
  it('a renovação devolve o acumulado, e não só a janela que a fonte trouxe', async () => {
    await db.upsertPrices('PETR4', [{ date: '2001-03-15', close: 3.21, adjustedClose: null, volume: 1000 }]);
    const series = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([t('PETR4')], wideRange()))
      .unwrap()
      .get(t('PETR4'))!;
    expect(
      sameDay(series.points[0]!.date, day(2001, 3, 15)),
      'o pregão que só o disco tem precisa sobreviver à renovação',
    ).toBe(true);
    expect(series.points[0]!.close).toBe(3.21);
    expect(series.points.length).toBeGreaterThan(1);
  });

  it('desdobramento entre duas buscas descarta a base velha', async () => {
    // Lente `risco`, 21/09/2026. A resposta traz 2026-07-21 a R$ 41,66; o
    // disco o tem a 83,32, o dobro, que é como um grupamento de 2 apareceria.
    await db.upsertPrices('PETR4', [
      { date: '2001-03-15', close: 6.42, adjustedClose: null, volume: 1000 },
      { date: '2026-07-21', close: 83.32, adjustedClose: null, volume: 1000 },
    ]);
    const series = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([t('PETR4')], wideRange()))
      .unwrap()
      .get(t('PETR4'))!;
    expect(
      sameDay(series.points[0]!.date, day(2026, 7, 21)),
      'o histórico em outra base sai inteiro — perder profundidade é menos grave que servir uma série com degrau',
    ).toBe(true);
    expectClose(series.points[0]!.close, 41.66, 1e-9);
    expect(series.points.some((p) => p.date.year === 2001)).toBe(false);
  });

  it('sem evento, a profundidade do disco continua sobrevivendo', async () => {
    // O contraponto do caso acima: a tolerância não pode disparar em ruído.
    await db.upsertPrices('PETR4', [
      { date: '2001-03-15', close: 3.21, adjustedClose: null, volume: 1000 },
      { date: '2026-07-21', close: 41.7, adjustedClose: null, volume: 1000 },
    ]);
    const series = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([t('PETR4')], wideRange()))
      .unwrap()
      .get(t('PETR4'))!;
    expect(
      sameDay(series.points[0]!.date, day(2001, 3, 15)),
      'diferença de um centavo é ruído, e não mudança de base',
    ).toBe(true);
  });

  it('o pregão que a resposta omite também sai da base velha', async () => {
    // Lente `dados`, decisão 134. A resposta pula 18/08/2026; o disco o tem,
    // da busca anterior, na escala de antes do grupamento.
    await db.upsertPrices('PETR4', [
      { date: '2026-07-21', close: 83.32, adjustedClose: null, volume: 1000 },
      { date: '2026-08-18', close: 85.0, adjustedClose: null, volume: 1000 },
    ]);
    const series = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([t('PETR4')], wideRange()))
      .unwrap()
      .get(t('PETR4'))!;
    expect(
      series.points.some((p) => sameDay(p.date, day(2026, 8, 18))),
      'o pregão da base velha no meio da janela é degrau',
    ).toBe(false);
    expectClose(series.points[0]!.close, 41.66, 1e-9);
  });

  it('se a base velha não sai do disco, a nova não entra por cima', async () => {
    // Lente `dados`, 01/10/2026. O apagamento e a gravação eram dois passos
    // independentes, cada um engolindo a própria falha: se o apagamento
    // falhasse, a gravação seguia e o disco ficava com as duas bases.
    const bank = new BrokenDeletion(new MemoryKeyValueStore());
    await bank.upsertPrices('PETR4', [
      { date: '2001-03-15', close: 6.42, adjustedClose: null, volume: 1000 },
      { date: '2026-07-21', close: 83.32, adjustedClose: null, volume: 1000 },
    ]);
    const series = (await prices(new FixtureTransport({ routes: batchRoute }), bank).dailyBatch([t('PETR4')], wideRange()))
      .unwrap()
      .get(t('PETR4'))!;
    expectClose(series.points[0]!.close, 41.66, 1e-9, 'sem gravar, o que sai é a resposta, e não o disco velho');
    expect(series.points.some((p) => p.date.year === 2001)).toBe(false);
    const onDisk = await bank.pricesIn('PETR4', '2000-01-01', '2030-01-01');
    expect(onDisk.map((r) => r.date), 'nada da base nova entra ao lado da velha').toEqual(['2001-03-15', '2026-07-21']);
    expect(onDisk[onDisk.length - 1]!.close).toBe(83.32);
    expect(
      await bank.isFresh(CachePolicy.pricesKey('PETR4'), CachePolicy.historicalPrices),
      'sem carimbo, a próxima busca tenta de novo',
    ).toBe(false);
  });

  it('a mudança de base é vista no primeiro pregão em comum', async () => {
    // O primeiro dia da resposta, 21/07/2026, não está no disco; o segundo
    // está, no dobro.
    await db.upsertPrices('PETR4', [
      { date: '2001-03-15', close: 6.42, adjustedClose: null, volume: 1000 },
      { date: '2026-07-22', close: 85.16, adjustedClose: null, volume: 1000 },
    ]);
    const series = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([t('PETR4')], wideRange()))
      .unwrap()
      .get(t('PETR4'))!;
    expect(series.points.some((p) => p.date.year === 2001)).toBe(false);
    expect(sameDay(series.points[0]!.date, day(2026, 7, 21))).toBe(true);
  });

  it('cache preserva preços e datas fielmente', async () => {
    const repository = prices(new FixtureTransport({ routes: batchRoute }), db);
    const fromNetwork = (await repository.dailyBatch([t('PETR4')], wideRange())).unwrap().get(t('PETR4'))!;
    const fromCache = (await repository.dailyBatch([t('PETR4')], wideRange())).unwrap().get(t('PETR4'))!;
    for (let i = 0; i < fromNetwork.points.length; i++) {
      expect(sameDay(fromCache.points[i]!.date, fromNetwork.points[i]!.date)).toBe(true);
      expect(fromCache.points[i]!.close).toBe(fromNetwork.points[i]!.close);
    }
  });

  it('recorta ao intervalo solicitado', async () => {
    const repository = prices(new FixtureTransport({ routes: batchRoute }), db);
    const wide = (await repository.dailyBatch([t('PETR4')], wideRange())).unwrap().get(t('PETR4'))!;
    const narrow = (await repository.dailyBatch([t('PETR4')], new DateRange(wide.firstDate, wide.firstDate)))
      .unwrap()
      .get(t('PETR4'))!;
    expect(narrow.points.length).toBeLessThan(wide.points.length);
    expect(narrow.points.length).toBe(1);
  });

  it('janela mais larga que o cache não devolve série truncada em silêncio', async () => {
    // O risco concreto: pedir 10 anos, o cache ter 1 mês, e o backtest rodar
    // sobre o mês achando que rodou sobre a década. A série sai com as datas
    // que de fato tem, não com as pedidas.
    const fixture = new FixtureTransport({ routes: batchRoute });
    const repository = prices(fixture, db);
    const ticker = t('PETR4');
    const saved = (await repository.dailyBatch([ticker], wideRange())).unwrap().get(ticker)!;
    const wide = (await repository.dailyBatch([ticker], new DateRange(day(1990, 1, 1), day(2030, 1, 1))))
      .unwrap()
      .get(ticker)!;
    expect(fixture.callCount['/v2/stocks/historical']).toBe(1);
    expect(wide.points.length).toBe(saved.points.length);
    // A borda da série é a do DADO, e não a da janela pedida.
    expect(sameDay(wide.firstDate, saved.firstDate)).toBe(true);
    expect(wide.firstDate.isAfter(day(1990, 1, 1))).toBe(true);
  });

  it('rede fora recorre ao cache VENCIDO em vez de falhar', async () => {
    // O cache é contingência: descartá-lo por estar vencido justo quando a
    // rede caiu é jogar fora o dado no momento em que ele mais serve.
    const ticker = t('PETR4');
    const saved = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([ticker], wideRange()))
      .unwrap()
      .get(ticker)!;
    await expireAll(store);
    const offline = prices(new FixtureTransport({ failures: { '/v2/stocks/historical': 503 } }), db);
    const result = await offline.dailyBatch([ticker], wideRange());
    expect(result.isOk, 'havia dado em disco: falhar aqui desperdiça a contingência').toBe(true);
    expect(result.unwrap().get(ticker)!.points.length).toBe(saved.points.length);
  });

  it('recuperação parcial devolve o erro da rede, e não meio lote', async () => {
    // Lente `dados`, 21/09/2026. O recuo ao cache vencido vale quando ele
    // cobre tudo que faltou.
    const petr = t('PETR4');
    // Papel fora do lote da fixture: ele nunca chega ao disco.
    const missing = t('BBAS3');
    await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([petr], wideRange());
    await expireAll(store);

    const offline = prices(new FixtureTransport({ failures: { '/v2/stocks/historical': 429 } }), db);
    const r = await offline.dailyBatch([petr, missing], wideRange());
    expect(r.isErr, 'o cache vencido não cobre a BBAS3: o lote está incompleto').toBe(true);
    expect(
      r.failureOrNull,
      'o motivo tem de chegar a quem lê, e é o da rede — não "ativo sem cotação" três camadas adiante',
    ).toBeInstanceOf(DataQualityFailure);

    // E cobrindo tudo, o recuo continua valendo.
    const fallbackResult = await offline.dailyBatch([petr], wideRange());
    expect(fallbackResult.isOk).toBe(true);
    expect(fallbackResult.unwrap().has(petr)).toBe(true);
  });

  it('ativo que o lote omite também recorre ao cache vencido', async () => {
    // Decisão 77. Um lote que responde e deixa um ativo de fora fazia o ativo
    // sumir da resposta com o histórico dele em disco.
    const petr = t('PETR4');
    const vale = t('VALE3');
    const saved = (await prices(new FixtureTransport({ routes: batchRoute }), db).dailyBatch([petr], wideRange()))
      .unwrap()
      .get(petr)!;
    await expireAll(store);

    const partial = prices(
      new FixtureTransport({
        bodies: {
          '/v2/stocks/historical': `
{"results":[{"symbol":"VALE3","data":{"historicalDataPrice":[
  {"date":1704157200,"close":60.0},
  {"date":1704243600,"close":61.0}
]}}]}`,
        },
      }),
      db,
    );
    const r = (await partial.dailyBatch([petr, vale], wideRange())).unwrap();
    expect(r.get(vale), 'o que veio da rede continua vindo').toBeDefined();
    expect(r.get(petr)?.points.length, 'havia histórico em disco, e o lote não o substituiu').toBe(saved.points.length);
  });

  it('sem cache algum, a falha de rede é reportada', async () => {
    // A contraprova: o fallback não pode transformar ausência de dado em
    // sucesso vazio.
    const result = await prices(new FixtureTransport({ failures: { '/v2/stocks/historical': 503 } }), null).dailyBatch(
      [t('PETR4')],
      wideRange(),
    );
    expect(result.isErr).toBe(true);
  });
});

describe('Cache de fundamentos', () => {
  const fundamentals = (fixture: FixtureTransport): FundamentalsRepositoryImpl =>
    new FundamentalsRepositoryImpl({ remote: new BrapiDatasource(clientWith(fixture)), cache: db });

  it('persiste e recupera os campos derivados', async () => {
    const fixture = new FixtureTransport({ routes: ALL_STATEMENTS });
    const repository = fundamentals(fixture);
    const first = (await repository.history(t('PETR4'))).unwrap();
    const callsAfterFirst = fixture.callCount['/v2/stocks/income-statement'] ?? 0;
    const second = (await repository.history(t('PETR4'))).unwrap();
    expect(fixture.callCount['/v2/stocks/income-statement'], 'fundamentos anuais não precisam ser rebuscados').toBe(
      callsAfterFirst,
    );
    expect(second.length).toBe(first.length);
    expect(second.some((s) => s.operatingCashFlow !== null)).toBe(true);
  });

  it('falha da fonte recorre ao cache VENCIDO de fundamentos', async () => {
    // Desde a decisão 77, falha do snapshot corrente reprova a busca — e é
    // este recurso que impede a reprovação de virar avaliação nenhuma.
    const saved = (await fundamentals(new FixtureTransport({ routes: ALL_STATEMENTS })).history(t('PETR4'))).unwrap();
    await expireAll(store);
    const routes: Record<string, string> = { ...ALL_STATEMENTS };
    delete routes['/v2/stocks/statistics?symbols=PETR4&mode=current'];
    const outside = fundamentals(
      new FixtureTransport({ routes, failures: { '/v2/stocks/statistics?symbols=PETR4&mode=current': 503 } }),
    );
    const r = await outside.history(t('PETR4'));
    expect(r.isOk).toBe(true);
    expect(r.unwrap().length).toBe(saved.length);
  });

  it('resposta parcial não apaga do disco o que ela não trouxe', async () => {
    // Lente `risco`, 27/09/2026. A fonte tolera uma rota com corpo de forma
    // errada e devolve os exercícios sem aquela demonstração; o `upsert`
    // gravava nulo por cima do valor bom.
    const whole = (await fundamentals(new FixtureTransport({ routes: ALL_STATEMENTS })).history(t('PETR4'))).unwrap();
    const withRevenue = new Map<string, number>();
    for (const s of whole) if (s.totalRevenue !== null) withRevenue.set(s.fiscalPeriodEnd.key, s.totalRevenue);
    expect(withRevenue.size, 'a premissa: o DRE foi gravado').toBeGreaterThan(0);
    await expireAll(store);

    const routes: Record<string, string> = { ...ALL_STATEMENTS };
    delete routes['/v2/stocks/income-statement'];
    const partial = await fundamentals(
      new FixtureTransport({
        routes,
        bodies: { '/v2/stocks/income-statement': '{"results":[{"incomeStatementHistory":"não é lista"}]}' },
      }),
    ).history(t('PETR4'));
    expect(partial.isOk).toBe(true);
    const read = new Map(partial.unwrap().map((s) => [s.fiscalPeriodEnd.key, s.totalRevenue]));
    for (const [key, value] of withRevenue) expect(read.get(key), `a receita de ${key} estava no disco`).toBe(value);
  });

  it('sem cache, a falha da fonte é reportada', async () => {
    const outside = fundamentals(new FixtureTransport({ failures: { '/v2/stocks/statistics': 503 } }));
    expect((await outside.history(t('PETR4'))).isErr).toBe(true);
  });

  it('a atualização devolve a união do banco, e não só a janela da fonte', async () => {
    // Lente `dados`, 20/09/2026. A profundidade não pode depender do TTL.
    await db.upsertFundamentals('PETR4', [{ fiscalPeriodEnd: '2001-12-31', netIncome: 1000 }]);
    const repository = fundamentals(new FixtureTransport({ routes: ALL_STATEMENTS }));
    const rightAfter = (await repository.history(t('PETR4'))).unwrap();
    const secondTime = (await repository.history(t('PETR4'))).unwrap();
    expect(rightAfter.length, 'a profundidade não pode depender do TTL').toBe(secondTime.length);
    expect(
      rightAfter.some((s) => s.fiscalPeriodEnd.year === 2001),
      'o exercício que só o banco tem precisa voltar na atualização',
    ).toBe(true);
  });
});

describe('Cache macroeconômico', () => {
  const macro = (fixture: FixtureTransport): MacroRepositoryImpl =>
    new MacroRepositoryImpl({ remote: new BcbDatasource(clientWith(fixture)), cache: db });
  const cdiRoute = { 'bcdata.sgs.12': 'bcb_cdi' };
  const shortRange = (): DateRange => new DateRange(day(2024, 1, 1), day(2024, 3, 31));

  it('a atualização devolve a união do banco, e não só a janela do SGS', async () => {
    // Lente `dados`, 21/09/2026 — a mesma correção que os fundamentos.
    await db.upsertMacro(12, [{ date: '2010-01-04', value: 0.0004 }]);
    const repository = macro(new FixtureTransport({ routes: cdiRoute }));
    const range = new DateRange(day(2010, 1, 1), day(2024, 3, 31));
    const rightAfter = (await repository.riskFreeDaily(range)).unwrap();
    const secondTime = (await repository.riskFreeDaily(range)).unwrap();
    expect(rightAfter.dates.length, 'a profundidade não pode depender do TTL').toBe(secondTime.dates.length);
    expect(sameDay(rightAfter.dates[0]!, day(2010, 1, 4)), 'o ponto que só o banco tem precisa voltar na atualização').toBe(
      true,
    );
  });

  it('CDI é buscado uma vez e reutilizado', async () => {
    const fixture = new FixtureTransport({ routes: cdiRoute });
    const repository = macro(fixture);
    const first = (await repository.riskFreeDaily(shortRange())).unwrap();
    expect(fixture.callCount['bcdata.sgs.12']).toBe(1);
    const second = (await repository.riskFreeDaily(shortRange())).unwrap();
    expect(fixture.callCount['bcdata.sgs.12']).toBe(1);
    expect(second.rates.length).toBe(first.rates.length);
    expectClose(second.accumulated, first.accumulated, 1e-12);
  });

  it('janela curta em cache não serve janela longa', async () => {
    // A validade é por SÉRIE e o recorte é por JANELA.
    const fixture = new FixtureTransport({ routes: cdiRoute });
    const repository = macro(fixture);
    await repository.riskFreeDaily(shortRange());
    expect(fixture.callCount['bcdata.sgs.12']).toBe(1);
    await repository.riskFreeDaily(new DateRange(day(2014, 1, 1), day(2024, 3, 31)));
    expect(fixture.callCount['bcdata.sgs.12'], 'o cache não cobria o início pedido; tem de ir à rede').toBe(2);
  });

  it('fonte fora recorre ao cache vencido que cobre a janela', async () => {
    const saved = (await macro(new FixtureTransport({ routes: cdiRoute })).riskFreeDaily(shortRange())).unwrap();
    await expireAll(store);
    const r = await macro(new FixtureTransport({ failures: { 'bcdata.sgs.12': 503 } })).riskFreeDaily(shortRange());
    expect(r.isOk, 'havia dado em disco cobrindo a janela: é a contingência').toBe(true);
    expect(r.unwrap().rates.length).toBe(saved.rates.length);
  });

  it('fonte fora não faz cache curto passar por janela longa', async () => {
    // O caminho degradado exige a cobertura do início como o normal.
    await macro(new FixtureTransport({ routes: cdiRoute })).riskFreeDaily(shortRange());
    await expireAll(store);
    const r = await macro(new FixtureTransport({ failures: { 'bcdata.sgs.12': 503 } })).riskFreeDaily(
      new DateRange(day(2014, 1, 1), day(2024, 3, 31)),
    );
    expect(r.isErr, 'o cache não cobre o início pedido; a falha da fonte vale').toBe(true);
  });

  it('a mesma janela continua sendo servida do cache', async () => {
    const fixture = new FixtureTransport({ routes: cdiRoute });
    const repository = macro(fixture);
    await repository.riskFreeDaily(shortRange());
    await repository.riskFreeDaily(shortRange());
    await repository.riskFreeDaily(shortRange());
    expect(fixture.callCount['bcdata.sgs.12'], 'a conferência de cobertura não pode anular o cache').toBe(1);
  });
});

describe('Validade do cache', () => {
  it('o carimbo vence pela validade declarada, com o relógio injetado', async () => {
    let now = 1_000_000;
    const clocked = new CacheDatabase(new MemoryKeyValueStore(), () => now);
    await clocked.touch('prices:PETR4');
    expect(await clocked.isFresh('prices:PETR4', CachePolicy.historicalPrices)).toBe(true);
    now += CachePolicy.historicalPrices.inMilliseconds - 1;
    expect(await clocked.isFresh('prices:PETR4', CachePolicy.historicalPrices)).toBe(true);
    now += 1;
    expect(await clocked.isFresh('prices:PETR4', CachePolicy.historicalPrices)).toBe(false);
    expect(await clocked.isFresh('prices:VALE3', CachePolicy.historicalPrices), 'recurso nunca buscado').toBe(false);
  });

  it('o campo ausente na gravação não apaga o do disco, e o nulo só entra em linha nova', async () => {
    await db.upsertFundamentals('PETR4', [{ fiscalPeriodEnd: '2024-12-31', netIncome: 10, ebit: 20 }]);
    await db.upsertFundamentals('PETR4', [{ fiscalPeriodEnd: '2024-12-31', ebit: 30 }]);
    const rows = await db.fundamentalsOf('PETR4');
    expect(rows).toHaveLength(1);
    expect(rows[0]!.netIncome).toBe(10);
    expect(rows[0]!.ebit).toBe(30);
    expect(rows[0]!.cash).toBeNull();
  });
});

/** Um banco que lê e grava, mas não consegue apagar — o disco que trava no meio da troca de base. */
class BrokenDeletion extends CacheDatabase {
  override deletePricesOf(): Promise<void> {
    return Promise.reject(new Error('o disco recusou o apagamento'));
  }
}
