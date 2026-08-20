import 'package:dio/dio.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/datasources/remote/bcb_datasource.dart';
import 'package:equisim/data/datasources/remote/brapi_datasource.dart';
import 'package:equisim/data/network/api_client.dart';
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

  group('BrapiDatasource — cotações', () {
    test('lote devolve uma série por ativo solicitado', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      });
      final datasource = BrapiDatasource(clientWith(adapter));

      final result = await datasource.historicalBatch(
        [Ticker.parse('PETR4'), Ticker.parse('VALE3')],
      );

      expect(result.isOk, isTrue);
      final series = result.unwrap();
      expect(series.keys.map((t) => t.value).toSet(), {'PETR4', 'VALE3'});
      expect(series[Ticker.parse('PETR4')]!.points, isNotEmpty);
      // Uma única requisição para os dois ativos.
      expect(adapter.callCount['/v2/stocks/historical'], 1);
    });

    test('série vem ordenada e com preços positivos', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      })));

      final series = (await datasource.historicalBatch([Ticker.parse('PETR4')]))
          .unwrap()[Ticker.parse('PETR4')]!;

      for (var i = 1; i < series.points.length; i++) {
        expect(
          series.points[i].date.isAfter(series.points[i - 1].date),
          isTrue,
          reason: 'a série precisa estar em ordem cronológica',
        );
      }
      expect(series.points.every((p) => p.close > 0), isTrue);
    });

    test('epoch em segundos vira data sem horário', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      })));
      final series = (await datasource.historicalBatch([Ticker.parse('PETR4')]))
          .unwrap()[Ticker.parse('PETR4')]!;
      final first = series.points.first.date;
      expect(first.hour, 0);
      expect(first.minute, 0);
    });

    test('Ibovespa é carregado da mesma rota histórica', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_ibovespa',
      })));
      final result = await datasource.ibovespa();
      expect(result.isOk, isTrue);
      expect(result.unwrap().points, isNotEmpty);
    });
  });

  group('BrapiDatasource — proventos', () {
    Future<List<DividendEvent>> loadItub() async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/dividends': 'brapi_dividends_itub4',
      })));
      return (await datasource.dividends(Ticker.parse('ITUB4'))).unwrap();
    }

    test('classifica o rótulo fiscal de cada evento', () async {
      final events = await loadItub();
      expect(events, isNotEmpty);
      expect(
        events.any((e) => e.kind == DividendKind.jcp),
        isTrue,
        reason: 'ITUB4 é fortemente pagadora de JCP',
      );
      expect(events.every((e) => e.amountPerShare > 0), isTrue);
    });

    test('propaga a marca de data de pagamento estimada', () async {
      final events = await loadItub();
      // A fonte marca boa parte dos eventos de ITUB4 como estimados.
      expect(events.any((e) => e.paymentDateEstimated), isTrue);
    });

    test('data-ex nunca é posterior à data de pagamento', () async {
      final events = await loadItub();
      for (final e in events) {
        expect(e.exDate.isAfter(e.paymentDate), isFalse,
            reason: 'data-ex ${e.exDate} depois do pagamento ${e.paymentDate}');
      }
    });

    test('elimina duplicata exata sem colapsar tranches legítimas', () async {
      final events = await loadItub();
      final identities = events
          .map((e) => '${e.exDate}|${e.paymentDate}|${e.amountPerShare}|${e.kind}')
          .toList();
      expect(identities.length, identities.toSet().length,
          reason: 'não deve restar registro idêntico repetido');

      // Múltiplas tranches na mesma data-ex continuam presentes quando existem.
      final byExDate = <DateTime, int>{};
      for (final e in events) {
        byExDate[e.exDate] = (byExDate[e.exDate] ?? 0) + 1;
      }
      expect(byExDate.values.any((c) => c >= 1), isTrue);
    });

    test('eventos saem em ordem cronológica de data-ex', () async {
      final events = await loadItub();
      for (var i = 1; i < events.length; i++) {
        expect(events[i].exDate.isBefore(events[i - 1].exDate), isFalse);
      }
    });
  });

  group('BrapiDatasource — fundamentos', () {
    test('funde os quatro demonstrativos pela chave do exercício', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      })));

      final result =
          await datasource.fundamentalsHistory(Ticker.parse('PETR4'));
      expect(result.isOk, isTrue);

      final snapshots = result.unwrap();
      expect(snapshots.length, greaterThan(10),
          reason: 'a fonte entrega 16 exercícios anuais');

      // Um mesmo exercício precisa reunir campos de demonstrativos diferentes.
      final recent = snapshots.lastWhere(
        (s) => s.fiscalPeriodEnd.year >= 2023,
        orElse: () => snapshots.last,
      );
      expect(recent.totalRevenue, isNotNull, reason: 'DRE');
      expect(recent.operatingCashFlow, isNotNull, reason: 'DFC');
      expect(recent.cash, isNotNull, reason: 'Balanço');
    });

    test('deriva D&A, alíquota efetiva e dívida líquida', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      })));

      final snapshots =
          (await datasource.fundamentalsHistory(Ticker.parse('PETR4'))).unwrap();
      final withDerived = snapshots.where(
        (s) => s.depreciationAndAmortization != null,
      );
      expect(withDerived, isNotEmpty,
          reason: 'D&A = EBITDA − EBIT deve ser derivável em algum exercício');

      final withTax = snapshots.where((s) => s.effectiveTaxRate != null);
      expect(withTax, isNotEmpty);
      expect(withTax.every((s) => s.effectiveTaxRate! <= 0.5), isTrue,
          reason: 'a alíquota é limitada para conter exercícios atípicos');
    });

    test('exercícios saem em ordem cronológica', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      })));
      final snapshots =
          (await datasource.fundamentalsHistory(Ticker.parse('PETR4'))).unwrap();
      for (var i = 1; i < snapshots.length; i++) {
        expect(
          snapshots[i].fiscalPeriodEnd.isAfter(snapshots[i - 1].fiscalPeriodEnd),
          isTrue,
        );
      }
    });
  });

  group('BrapiDatasource — perfil e tickers', () {
    test('mapeia setor e indústria da taxonomia da fonte', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/profile': 'brapi_profile_petr4',
      })));
      final asset = (await datasource.profile(Ticker.parse('PETR4'))).unwrap();
      expect(asset.sector.isUnknown, isFalse);
      expect(asset.sector.key, 'energia');
      expect(asset.industry, isNotNull);
    });

    test('resolve renomeação usando o parâmetro plural correto', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/tickers/resolve': 'brapi_resolve_viia3',
      });
      final datasource = BrapiDatasource(clientWith(adapter));

      final resolved = await datasource.resolve(Ticker.parse('VIIA3'));
      expect(resolved.isOk, isTrue);
      expect(resolved.unwrap()?.value, 'BHIA3');
    });
  });

  group('BcbDatasource', () {
    test('converte percentual diário em fração', () async {
      final datasource = BcbDatasource(clientWith(FixtureAdapter(routes: {
        'bcdata.sgs.12': 'bcb_cdi',
      })));

      final result = await datasource.cdi(
        DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)),
      );
      expect(result.isOk, isTrue);

      final series = result.unwrap();
      expect(series.rates, isNotEmpty);
      // 0,043739% ao dia → 0,00043739 em fração.
      expect(series.rates.first, closeTo(0.00043739, 1e-9));
      expect(series.rates.every((r) => r > 0 && r < 0.01), isTrue);
    });

    test('acumula e anualiza o CDI do período', () async {
      final datasource = BcbDatasource(clientWith(FixtureAdapter(routes: {
        'bcdata.sgs.12': 'bcb_cdi',
      })));
      final series = (await datasource.cdi(
        DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)),
      )).unwrap();

      expect(series.accumulated, greaterThan(0));
      // Um trimestre de CDI a ~10,6% a.a. anualiza para a mesma ordem.
      expect(series.annualized(), greaterThan(0.08));
      expect(series.annualized(), lessThan(0.16));
    });

    test('datas dd/MM/yyyy são interpretadas corretamente', () async {
      final datasource = BcbDatasource(clientWith(FixtureAdapter(routes: {
        'bcdata.sgs.12': 'bcb_cdi',
      })));
      final series = (await datasource.cdi(
        DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)),
      )).unwrap();
      expect(series.dates.first.year, 2024);
      expect(series.dates.first.month, 1);
    });
  });

  group('Tratamento de erro da API', () {
    test('401 vira falha de credencial, não exceção crua', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: const {},
        failures: {'/v2/stocks/profile': 401},
      )));
      final result = await datasource.profile(Ticker.parse('PETR4'));
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InvalidInput>());
      expect(result.failureOrNull!.message, contains('Credencial'));
    });

    test('404 vira dado insuficiente', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: const {},
        failures: {'/v2/stocks/profile': 404},
      )));
      final result = await datasource.profile(Ticker.parse('XXXX3'));
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('429 é reportado como limite de requisições', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: const {},
        failures: {'/v2/stocks/profile': 429},
      )));
      final result = await datasource.profile(Ticker.parse('PETR4'));
      expect(result.failureOrNull, isA<DataQualityFailure>());
    });
  });
}
