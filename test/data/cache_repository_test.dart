import 'package:dio/dio.dart';
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
