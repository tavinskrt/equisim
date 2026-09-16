import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/datasources/local/cache_database.dart';
import 'package:equisim/data/datasources/remote/bcb_datasource.dart';
import 'package:equisim/data/datasources/remote/brapi_datasource.dart';
import 'package:equisim/data/network/api_client.dart';
import 'package:equisim/data/repositories/market_repositories.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_adapter.dart';

const _config = ApiConfig(
  mode: BrapiMode.direct,
  brapiBaseUrl: 'https://brapi.dev/api',
  brapiToken: 'token-de-teste',
  bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
);

ApiClient clientWith(FixtureAdapter adapter) {
  final dio = Dio(BaseOptions(
    responseType: ResponseType.plain,
    validateStatus: ApiClient.acceptsStatus,
  ));
  dio.httpClientAdapter = adapter;
  return ApiClient(_config, dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheDatabase db;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  group('Cache de cotações', () {
    test('segunda leitura não vai à rede', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      });
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(adapter)),
        cache: db,
      );
      final range = DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1));

      final first = await repository.dailyBatch([Ticker.parse('PETR4')], range);
      expect(first.isOk, isTrue);
      expect(adapter.callCount['/v2/stocks/historical'], 1);

      final second = await repository.dailyBatch([Ticker.parse('PETR4')], range);
      expect(second.isOk, isTrue);
      expect(
        adapter.callCount['/v2/stocks/historical'],
        1,
        reason: 'cotação de pregão encerrado é imutável e não deve ser rebuscada',
      );
      expect(
        second.unwrap()[Ticker.parse('PETR4')]!.points.length,
        first.unwrap()[Ticker.parse('PETR4')]!.points.length,
      );
    });

    // A fonte devolve uma janela fixa de dez anos e a gravação é aditiva: com o
    // tempo o disco guarda mais do que a resposta traz. O caminho de SUCESSO
    // devolvia o recorte da resposta, e encurtava a série de quem já tinha
    // histórico mais longo — pior que o caminho degradado, que lê o disco.
    test('a renovação devolve o acumulado, e não só a janela que a fonte trouxe',
        () async {
      final antigo = DateTime(2001, 3, 15);
      await db.upsertPrices([
        CachedPricesCompanion.insert(
          ticker: 'PETR4',
          date: '2001-03-15',
          close: 3.21,
          volume: const Value(1000),
        ),
      ]);
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/historical': 'brapi_historical_batch',
        }))),
        cache: db,
      );
      final range = DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1));

      final serie = (await repository.dailyBatch([Ticker.parse('PETR4')], range))
          .unwrap()[Ticker.parse('PETR4')]!;

      expect(serie.points.first.date, antigo,
          reason: 'o pregão que só o disco tem precisa sobreviver à renovação');
      expect(serie.points.first.close, 3.21);
      expect(serie.points.length, greaterThan(1));
    });

    test('cache preserva preços e datas fielmente', () async {
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/historical': 'brapi_historical_batch',
        }))),
        cache: db,
      );
      final range = DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1));

      final fromNetwork =
          (await repository.dailyBatch([Ticker.parse('PETR4')], range))
              .unwrap()[Ticker.parse('PETR4')]!;
      final fromCache =
          (await repository.dailyBatch([Ticker.parse('PETR4')], range))
              .unwrap()[Ticker.parse('PETR4')]!;

      for (var i = 0; i < fromNetwork.points.length; i++) {
        expect(fromCache.points[i].date, fromNetwork.points[i].date);
        expect(fromCache.points[i].close, fromNetwork.points[i].close);
      }
    });

    test('recorta ao intervalo solicitado', () async {
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/historical': 'brapi_historical_batch',
        }))),
        cache: db,
      );

      final wide = (await repository.dailyBatch(
        [Ticker.parse('PETR4')],
        DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1)),
      ))
          .unwrap()[Ticker.parse('PETR4')]!;

      final narrow = (await repository.dailyBatch(
        [Ticker.parse('PETR4')],
        DateRange(wide.firstDate, wide.firstDate),
      ))
          .unwrap()[Ticker.parse('PETR4')]!;

      expect(narrow.points.length, lessThan(wide.points.length));
      expect(narrow.points.length, 1);
    });

    test('janela mais larga que o cache não devolve série truncada em '
        'silêncio', () async {
      // O risco concreto: pedir 10 anos, o cache ter 1 mês, e o backtest rodar
      // sobre o mês achando que rodou sobre a década. O recorte por data é
      // lexicográfico no SQLite, então uma janela maior lê TUDO que existe —
      // e a série sai com as datas que de fato tem, não com as pedidas.
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      });
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(adapter)),
        cache: db,
      );
      final ticker = Ticker.parse('PETR4');

      final gravada = (await repository.dailyBatch(
        [ticker],
        DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1)),
      ))
          .unwrap()[ticker]!;

      // Segunda leitura, agora pedindo uma janela que começa DÉCADAS antes do
      // que existe em disco. O cache está fresco, então não há ida à rede.
      final larga = (await repository.dailyBatch(
        [ticker],
        DateRange(DateTime(1990, 1, 1), DateTime(2030, 1, 1)),
      ))
          .unwrap()[ticker]!;

      expect(adapter.callCount['/v2/stocks/historical'], 1);
      expect(larga.points.length, gravada.points.length);
      // A borda da série é a do DADO, e não a da janela pedida: é o que
      // permite ao backtest encurtar o período e avisar, em vez de simular
      // uma década sobre um mês.
      expect(larga.firstDate, gravada.firstDate);
      expect(larga.firstDate.isAfter(DateTime(1990, 1, 1)), isTrue);
    });

    test('rede fora recorre ao cache VENCIDO em vez de falhar', () async {
      // O cache é contingência: descartá-lo por estar vencido justo quando a
      // rede caiu é jogar fora o dado no momento em que ele mais serve. A
      // gravação é aditiva, então vencido aqui significa "sem os pregões mais
      // recentes", não "errado".
      final ticker = Ticker.parse('PETR4');
      final range = DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1));

      final ok = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/historical': 'brapi_historical_batch',
        }))),
        cache: db,
      );
      final gravada = (await ok.dailyBatch([ticker], range)).unwrap()[ticker]!;

      // Marca de validade apagada: o cache passa a estar vencido, e a rede
      // devolve erro de servidor.
      await db.customStatement('DELETE FROM cache_entries');

      final offline = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(
          failures: {'/v2/stocks/historical': 503},
        ))),
        cache: db,
      );

      final result = await offline.dailyBatch([ticker], range);
      expect(result.isOk, isTrue,
          reason: 'havia dado em disco: falhar aqui desperdiça a contingência');
      expect(result.unwrap()[ticker]!.points.length, gravada.points.length);
    });

    test('ativo que o lote omite também recorre ao cache vencido', () async {
      // Decisão 77. O recurso ao cache vencido existia só para o lote que
      // falha inteiro. Um lote que responde e deixa um ativo de fora — série
      // corrompida daquele papel, ou papel que a fonte deixou de devolver —
      // fazia o ativo sumir da resposta com o histórico dele em disco.
      final petr = Ticker.parse('PETR4');
      final vale = Ticker.parse('VALE3');
      final range = DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1));

      final ok = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/historical': 'brapi_historical_batch',
        }))),
        cache: db,
      );
      final gravada = (await ok.dailyBatch([petr], range)).unwrap()[petr]!;
      await db.customStatement('DELETE FROM cache_entries');

      final parcial = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(bodies: {
          '/v2/stocks/historical': '''
{"results":[{"symbol":"VALE3","data":{"historicalDataPrice":[
  {"date":1704157200,"close":60.0},
  {"date":1704243600,"close":61.0}
]}}]}''',
        }))),
        cache: db,
      );

      final r = (await parcial.dailyBatch([petr, vale], range)).unwrap();
      expect(r[vale], isNotNull, reason: 'o que veio da rede continua vindo');
      expect(r[petr]?.points.length, gravada.points.length,
          reason: 'havia histórico em disco, e o lote não o substituiu');
    });

    test('sem cache algum, a falha de rede é reportada', () async {
      // A contraprova: o fallback não pode transformar ausência de dado em
      // sucesso vazio. `cache: null` é o caminho real de quem roda onde o
      // banco não abre — alvo web sem asset, permissão negada, disco cheio.
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(
          failures: {'/v2/stocks/historical': 503},
        ))),
        cache: null,
      );

      final result = await repository.dailyBatch(
        [Ticker.parse('PETR4')],
        DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1)),
      );
      expect(result.isErr, isTrue);
    });
  });

  group('Cache de fundamentos', () {
    test('persiste e recupera os campos derivados', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      });
      final repository = FundamentalsRepositoryImpl(
        remote: BrapiDatasource(clientWith(adapter)),
        cache: db,
      );
      final ticker = Ticker.parse('PETR4');

      final first = (await repository.history(ticker)).unwrap();
      final callsAfterFirst =
          adapter.callCount['/v2/stocks/income-statement'] ?? 0;

      final second = (await repository.history(ticker)).unwrap();
      expect(adapter.callCount['/v2/stocks/income-statement'], callsAfterFirst,
          reason: 'fundamentos anuais não precisam ser rebuscados');

      expect(second.length, first.length);
      final withCashFlow = second.where((s) => s.operatingCashFlow != null);
      expect(withCashFlow, isNotEmpty);
    });

    test('falha da fonte recorre ao cache VENCIDO de fundamentos', () async {
      // Desde a decisão 77, falha do snapshot corrente reprova a busca — e é
      // este recurso que impede a reprovação de virar avaliação nenhuma para
      // quem já tem os exercícios em disco.
      final ticker = Ticker.parse('PETR4');
      final ok = FundamentalsRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/statistics?symbols=PETR4&mode=history':
              'brapi_statistics_history_petr4',
          '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
          '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
          '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
          '/v2/stocks/statistics?symbols=PETR4&mode=current':
              'brapi_statistics_current_petr4',
        }))),
        cache: db,
      );
      final gravada = (await ok.history(ticker)).unwrap();
      await db.customStatement('DELETE FROM cache_entries');

      final fora = FundamentalsRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(routes: {
          '/v2/stocks/statistics?symbols=PETR4&mode=history':
              'brapi_statistics_history_petr4',
          '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
          '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
          '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        }, failures: {
          '/v2/stocks/statistics?symbols=PETR4&mode=current': 503,
        }))),
        cache: db,
      );
      final r = await fora.history(ticker);
      expect(r.isOk, isTrue);
      expect(r.unwrap().length, gravada.length);
    });

    test('sem cache, a falha da fonte é reportada', () async {
      final fora = FundamentalsRepositoryImpl(
        remote: BrapiDatasource(clientWith(FixtureAdapter(
          failures: {'/v2/stocks/statistics': 503},
        ))),
        cache: db,
      );
      expect((await fora.history(Ticker.parse('PETR4'))).isErr, isTrue);
    });
  });

  group('Cache macroeconômico', () {
    test('CDI é buscado uma vez e reutilizado', () async {
      final adapter = FixtureAdapter(routes: {'bcdata.sgs.12': 'bcb_cdi'});
      final repository = MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(adapter)),
        cache: db,
      );
      final range = DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31));

      final first = (await repository.riskFreeDaily(range)).unwrap();
      expect(adapter.callCount['bcdata.sgs.12'], 1);

      final second = (await repository.riskFreeDaily(range)).unwrap();
      expect(adapter.callCount['bcdata.sgs.12'], 1);
      expect(second.rates.length, first.rates.length);
      expect(second.accumulated, closeTo(first.accumulated, 1e-12));
    });

    test('janela curta em cache não serve janela longa', () async {
      // A validade e por SERIE e o recorte e por JANELA. Sem conferir
      // cobertura, um grafico de tres meses marcava o CDI como fresco e a
      // simulacao de dez anos recebia tres meses achando que recebeu dez
      // anos — e apurava o CAGR decenal sobre eles.
      final adapter = FixtureAdapter(routes: {'bcdata.sgs.12': 'bcb_cdi'});
      final repository = MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(adapter)),
        cache: db,
      );

      final curta = DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31));
      await repository.riskFreeDaily(curta);
      expect(adapter.callCount['bcdata.sgs.12'], 1);

      final longa = DateRange(DateTime(2014, 1, 1), DateTime(2024, 3, 31));
      await repository.riskFreeDaily(longa);
      expect(adapter.callCount['bcdata.sgs.12'], 2,
          reason: 'o cache nao cobria o inicio pedido; tem de ir a rede');
    });

    test('fonte fora recorre ao cache vencido que cobre a janela', () async {
      final range = DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31));
      final gravada = (await MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(
            FixtureAdapter(routes: {'bcdata.sgs.12': 'bcb_cdi'}))),
        cache: db,
      ).riskFreeDaily(range))
          .unwrap();

      // Marca de validade apagada, e o Banco Central devolve erro.
      await db.customStatement('DELETE FROM cache_entries');
      final fora = MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(
            FixtureAdapter(failures: {'bcdata.sgs.12': 503}))),
        cache: db,
      );

      final r = await fora.riskFreeDaily(range);
      expect(r.isOk, isTrue,
          reason: 'havia dado em disco cobrindo a janela: é a contingência');
      expect(r.unwrap().rates.length, gravada.rates.length);
    });

    test('fonte fora não faz cache curto passar por janela longa', () async {
      // O caminho degradado exige a cobertura do início como o normal: sem
      // isso, a queda do Banco Central servia três meses à simulação de dez
      // anos, e o CAGR decenal saía sobre eles.
      await MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(
            FixtureAdapter(routes: {'bcdata.sgs.12': 'bcb_cdi'}))),
        cache: db,
      ).riskFreeDaily(DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)));

      await db.customStatement('DELETE FROM cache_entries');
      final fora = MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(
            FixtureAdapter(failures: {'bcdata.sgs.12': 503}))),
        cache: db,
      );

      final longa = DateRange(DateTime(2014, 1, 1), DateTime(2024, 3, 31));
      expect((await fora.riskFreeDaily(longa)).isErr, isTrue,
          reason: 'o cache não cobre o início pedido; a falha da fonte vale');
    });

    test('a mesma janela continua sendo servida do cache', () async {
      final adapter = FixtureAdapter(routes: {'bcdata.sgs.12': 'bcb_cdi'});
      final repository = MacroRepositoryImpl(
        remote: BcbDatasource(clientWith(adapter)),
        cache: db,
      );
      final range = DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31));
      await repository.riskFreeDaily(range);
      await repository.riskFreeDaily(range);
      await repository.riskFreeDaily(range);
      expect(adapter.callCount['bcdata.sgs.12'], 1,
          reason: 'a conferencia de cobertura nao pode anular o cache');
    });
  });

  group('Reprodutibilidade', () {
    test('cache limpo devolve o sistema ao estado inicial', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      });
      final repository = PriceRepositoryImpl(
        remote: BrapiDatasource(clientWith(adapter)),
        cache: db,
      );
      final range = DateRange(DateTime(2000, 1, 1), DateTime(2030, 1, 1));

      await repository.dailyBatch([Ticker.parse('PETR4')], range);
      await db.clearAll();
      await repository.dailyBatch([Ticker.parse('PETR4')], range);

      expect(adapter.callCount['/v2/stocks/historical'], 2);
    });
  });
}
