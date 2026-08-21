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
    validateStatus: (s) => s != null && s < 500,
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
  });

  group('Cache de proventos', () {
    test('segunda leitura vem do cache e preserva o rótulo fiscal', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/dividends': 'brapi_dividends_itub4',
      });
      final repository = DividendRepositoryImpl(
        remote: BrapiDatasource(clientWith(adapter)),
        cache: db,
      );
      final ticker = Ticker.parse('ITUB4');

      final first = (await repository.history(ticker)).unwrap();
      expect(adapter.callCount['/v2/stocks/dividends'], 1);

      final second = (await repository.history(ticker)).unwrap();
      expect(adapter.callCount['/v2/stocks/dividends'], 1);

      expect(second.length, first.length);
      expect(
        second.where((e) => e.kind == DividendKind.jcp).length,
        first.where((e) => e.kind == DividendKind.jcp).length,
      );
      expect(
        second.where((e) => e.paymentDateEstimated).length,
        first.where((e) => e.paymentDateEstimated).length,
      );
    });

    test('chave composta não colapsa tranches da mesma data-ex', () async {
      final ticker = Ticker.parse('BBAS3');
      // Caso real: BBAS3 em 11/03/2025 teve dois JCP de valores distintos.
      await db.upsertDividends([
        CachedDividendsCompanion.insert(
          ticker: ticker.value,
          exDate: '2025-03-11',
          paymentDate: '2025-04-01',
          amount: 0.14935148,
          label: 'JCP',
        ),
        CachedDividendsCompanion.insert(
          ticker: ticker.value,
          exDate: '2025-03-11',
          paymentDate: '2025-04-01',
          amount: 0.3425925,
          label: 'JCP',
        ),
        // Repetição idêntica da primeira: deve ser absorvida pela chave.
        CachedDividendsCompanion.insert(
          ticker: ticker.value,
          exDate: '2025-03-11',
          paymentDate: '2025-04-01',
          amount: 0.14935148,
          label: 'JCP',
        ),
      ]);

      final rows = await db.dividendsOf(ticker.value);
      expect(rows.length, 2,
          reason: 'duas tranches legítimas preservadas, duplicata exata removida');
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
